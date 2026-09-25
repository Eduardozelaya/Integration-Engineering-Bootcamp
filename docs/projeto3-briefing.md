# Briefing — Laboratório de Integração, Projeto 3 e sessão de 23/09/2026
### O que é o plano, o que é o Projeto 3, o que já foi provado e como cada ponto foi feito

> Documento de entendimento e de registro. Sugestão de caminho no repositório: `docs/projeto3-briefing.md`.
> Cada ponto realizado segue o formato **objetivo → o que foi feito → resultado → o que isso ensina**.
> Horários de evidência estão em **UTC** (hora local = UTC − 3).

---

## 1. O plano em uma página

### 1.1 Objetivo

Profissional sênior de integração com base em **WSO2** fazendo a transição para o ecossistema **IBM** (App Connect Enterprise, MQ, API Connect). O produto final não é "ter estudado", e sim um **portfólio público** em que cada competência vem acompanhada de evidência reproduzível: código, configuração, logs e medições. Mercado-alvo: bancos, seguradoras e consultorias no Rio e em São Paulo.

### 1.2 Arquitetura do laboratório

| Lado | O que roda | Papel |
|---|---|---|
| **Linux (WSL2, Debian 13)** | Docker nativo com `qm1` (IBM MQ) e `mock` (WireMock) | infraestrutura |
| **Windows 11** | ACE 12.0.12.27 Toolkit e integration server `TEST_SERVER1`; MQ Client em `C:\MQClient` | desenvolvimento e runtime do ACE |
| **Ponte** | `localhost:1414`, canal `DEV.APP.SVRCONN`, conexão CLIENT | o ACE no Windows consome filas no container |

### 1.3 Os projetos e em que tier cada um está

**Tier 1 — a linha de corte.** Ao concluir, começar a se candidatar.

| # | Projeto | Do que se trata | Estado |
|---|---|---|---|
| 1 | **Conector R2/S3 com SigV4** | Assinatura AWS SigV4 feita à mão num Java Compute, empacotada como Shared Library reutilizável, com credenciais no vault e testes JUnit contra vetores oficiais. É a diferença entre prova de conceito e componente enterprise. | pendente; o flow `testarR2` está escondido no `Module5` e precisa ser extraído |
| 3 | **MQ transacional** | Provar que o fluxo não perde nem duplica mensagem: unidade de trabalho, backout, DLQ com motivo, idempotência, request/reply, pub/sub. | **parte 1 concluída** |
| 7 | **Observabilidade (mínimo)** | Logs estruturados com `correlationId`, traces OpenTelemetry até o Jaeger, métricas no Prometheus/Grafana, alertas por profundidade de fila. Responde a "onde está a mensagem X?". | pendente |
| 5 | **CI/CD e containers (mínimo)** | Build do BAR sem Toolkit (`ibmint`/`mqsipackagebar`), JUnit no pipeline, imagem do ACE, GitHub Actions. Prova que você opera, não só desenvolve. | pendente; o `sync-ace.sh` e os fontes versionados já são pré-requisito dele |

**Tier 2**

| # | Projeto | Do que se trata |
|---|---|---|
| 9 | **DFDL / copybook** | Mensagens COBOL de mainframe em formato fixo. É a maior lacuna do plano original e é comum em banco. |
| 10 | **Banco + transação XA** | Gravar em Postgres e em MQ na mesma transação coordenada. É a solução robusta de idempotência que o Projeto 3 só aproxima. |
| 6 | **Segurança ponta a ponta** | OAuth2/JWT com Keycloak, mTLS, validação de JWT no ACE (defesa em profundidade), segredos em vault. |
| 11 | **Segurança do MQ** | TLS no canal, CHLAUTH e CONNAUTH. |

**Tier 3**

| # | Projeto | Do que se trata |
|---|---|---|
| 4 | **Kafka** | Eventos com Redpanda; nodes Kafka do ACE; consumidor no WSO2 MI; a pergunta "MQ ou Kafka?". |
| 2 | **Gateway** | A mesma API publicada em WSO2 APIM e IBM API Connect, com o comparativo das políticas. O DataPower não roda nesta máquina (8 GB). |
| 8 | **Capstone** | Pedido ponta a ponta: gateway → ACE → MQ → estoque com retry e circuit breaker → R2 → Kafka → MI. Uma história de 10 minutos que aguenta "e se cair?". |

---

## 2. O Projeto 3 — do que se trata

### 2.1 Por que existe

O IBM MQ é o coração das integrações em banco, seguradora e telecom. Muitos candidatos dizem que "conhecem MQ". Poucos conseguem **demonstrar**, com evidência, o que acontece com uma mensagem quando algo falha. O Projeto 3 existe para responder, com laboratório funcionando, a duas perguntas que aparecem em quase toda entrevista:

- *"O que acontece se o consumidor cair no meio de uma mensagem?"*
- *"Como você evita processar duas vezes?"*

### 2.2 Os cinco conceitos que explicam todos os resultados

| Conceito | Em uma frase |
|---|---|
| **Unidade de trabalho (UoW) / syncpoint** | Com `Transaction mode: Yes`, o MQInput lê a mensagem sem removê-la; tudo que o flow grava fica pendente; no fim, ou tudo vale junto (commit) ou nada aconteceu (rollback). |
| **BackoutCount (BOC)** | Contador no cabeçalho MQMD, mantido pelo **queue manager**: sobe a cada rollback sobre a mensagem e nasce 0 em todo put novo. |
| **BOTHRESH / BOQNAME** | Atributos da fila de entrada (`3` e `APP.BACKOUT`). Se `BOC >= 3`, o MQInput não entrega a mensagem ao flow e a move para a fila de backout. |
| **Terminal Catch** | Recebe a mensagem **original** mais o `ExceptionList` quando algo falha, ainda dentro da mesma UoW. |
| **Transaction mode: No** | A leitura é confirmada na hora; não há o que desfazer. Uma exceção significa perda da mensagem. |

### 2.3 O flow `PassThrough` (application `OrderProcessing`)

```
LerPedido (MQInput APP.IN) ──► ProcessarPedido (Compute) ──► GravarSaida (MQOutput APP.OUT)
        │
        └─ Catch ──► RegistrarTentativa (Trace) ──► TratarFalha (Compute) ──► GravarDLQ (MQOutput APP.DLQ)
```

- **ProcessarPedido** acrescenta `processedBy` e `processedAt` (ISO, UTC). Com `"forcarErro":"true"` no corpo, lança `THROW USER EXCEPTION 2951`.
- **RegistrarTentativa** grava em `C:\temp\catch-trace.txt` uma linha por passagem pelo Catch: horário GMT, `BOC` e `orderId`.
- **TratarFalha** decide: se `BOC < 2`, relança (rollback e nova entrega); se `BOC = 2`, monta `{original, erro{codigo, mensagem, detalhe, tentativas, flow, falhouEm}}` e deixa seguir para a DLQ.

### 2.4 As três camadas de fila, que são coisas diferentes

| Fila | Quem grava | Quando |
|---|---|---|
| `APP.DLQ` | o **flow**, de propósito | erro esgotou as tentativas; mensagem com motivo estruturado |
| `APP.BACKOUT` | o **MQInput**, pelo mecanismo do MQ | `BOC >= BOTHRESH`; mensagem original, sem motivo |
| DEADQ do queue manager | o **MQ** | não consegue entregar em lugar nenhum |

### 2.5 Divisão do projeto

**Parte 1 (concluída):** comportamento transacional, retentativa, DLQ com motivo, perda sem transação, rede de segurança.

**Parte 2 (próxima):**
1. idempotência;
2. request/reply com `APP.REPLY` e `CorrelId`;
3. pub/sub em `APP.EVENTS`, com assinatura durável e não durável;
4. teste de 100 mensagens com 30% de erro (`OUT + DLQ = 100`, zero duplicatas, três vezes seguidas);
5. tuning com `Additional instances`.

**Critério de pronto do projeto:** o teste de 100 mensagens fecha a conta três vezes seguidas, e o `queues.mqsc` sobe o ambiente do zero.

---

## 3. O que já foi realizado — visão por sessão

| Sessão | Entregas principais |
|---|---|
| **17–19/09** | Ambiente reprodutível (`up.sh`, `queues.mqsc`, `authorities.sh`); ACE no Windows conectado ao MQ no WSL; cadeia de cinco erros resolvida (`BIP1361E`, `BIP2684E` duas vezes, `2035` duas vezes); flow `PassThrough` ponta a ponta; backout provado numa falha real de autorização. |
| **20–21/09** | Experimentos A (Yes retém e faz backout), B (No perde) e C (Catch → DLQ). |
| **22→23/09** | Auditoria das evidências (três fragilidades); fontes versionados de verdade (`f1a3919`); `sync-ace.sh`; Trace node (`f0575aa`); **C2** com medição (`867d221`); achado do **intervalo fixo de ~1 s**; **B2** executado. |
| **23→24/09** | Detalhada na seção 4: B2 commitado; log de eventos descoberto; **Experimento E**; achado do `dmpmqmsg`; reversão provada. |

### 3.1 Resultado dos experimentos da parte 1

| Exp. | Configuração | Resultado | O que prova |
|---|---|---|---|
| **C2** | `Yes`, Catch → TratarFalha → DLQ | trace BOC 0, 1, 2 com ~1 s de intervalo; DLQ com `original` e `erro` | retentativa controlada e DLQ com motivo, na mesma UoW |
| **B2** | `No`, mesmo tratamento | Catch dispara 1 vez; nada em fila alguma | sem syncpoint, o relançamento descarta a mensagem |
| **E** | `Yes`, `GravarDLQ` → fila inexistente | trace 3 linhas; BACKOUT 1, DLQ 0; corpo original | se o tratamento falhar, o MQ salva a mensagem |

---

## 4. Sessão de 23→24/09 — cada ponto documentado

### 4.1 Retomada do ambiente

**Objetivo.** MQ e ACE no ar e conectados antes de qualquer experimento.

**Feito.**
1. `./scripts/up.sh` no WSL.
2. `IntegrationServer --work-dir C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1` num console do ACE.
3. `DISPLAY QSTATUS(APP.IN) IPPROCS` para conferir a conexão.

**Resultado.**
- O `up.sh` reaplicou filas e autorizações e mostrou `BOTHRESH(3)`, `BOQNAME(APP.BACKOUT)` e `MCAUSER(app)`.
- O servidor chegou ao `BIP1991I` às 23:25:33 local, com `OrderProcessing` e `R2Policies` carregados.
- O primeiro `IPPROCS(0)` foi consultado antes da subida do ACE; o caminho feliz logo depois provou a conexão.

**O que ensina.**
- **Ordem obrigatória: MQ primeiro, ACE depois.**
- O work dir real fica em `servers\`, não em `workspace\`; o ESTADO.md estava desatualizado.
- A janela do `IntegrationServer` fica ocupada enquanto o servidor roda. Os comandos `ibmint` precisam de um **segundo** console do ACE.
- O log de inicialização confirmou pendências de projetos futuros:
  - apps de curso rodando no mesmo servidor;
  - porta de debug 9997 aberta e segurança de administração inativa (Projeto 6);
  - OpenTelemetry desligado por configuração, não por plataforma (hipótese para o Projeto 7).

### 4.2 Caminho feliz pós-reversão do B2 (`orderId 22`)

**Objetivo.** Provar que o flow voltou a funcionar depois do experimento B2.

**Feito.** `amqsput` em `APP.IN` e `amqsget` em `APP.OUT`, com o `EOF` do heredoc na coluna 0 (na sessão anterior, o `EOF` indentado travou o terminal).

**Resultado.** Saiu `{"orderId":"22","valor":2200,"processedBy":"ACE-LAB","processedAt":"2026-09-24T02:26:47.762+00:00"}`.

**O que ensina.** O timestamp em UTC está correto: 02:26 UTC corresponde a 23:26 local.

### 4.3 Commit do B2

**Objetivo.** Guardar a evidência do experimento em que `No` perde a mensagem.

**Feito.** `git add docs/evidencias/exp-b2-*`, com conferência de que o `PassThrough.msgflow` **não** aparecia no status.

**Resultado.** Commit `2714638`, com 4 arquivos: diff, log do servidor, trace e laço de filas. O arquivo vazio `docs/docs.md` foi identificado (`wc -c` = 0) e removido.

**O que ensina.** Conferir o `git status --short` antes de todo commit. Um `git add docs/` teria levado o arquivo vazio junto.

### 4.4 Descoberta do log de eventos do servidor

**Objetivo.** Ter uma fonte de log reproduzível, sem copiar da janela.

**Feito.** Listagem de `servers\TEST_SERVER1\log\`; diagnóstico de codificação com `file` (instalado, pois não vem no Debian mínimo), `od -c`, `head` e `tail`.

**Resultado.**

| Propriedade | Valor |
|---|---|
| Arquivo | `integration_server.TEST_SERVER1.events.txt` |
| Rotação | a cada inicialização: atual → `.1` → … → `.9` |
| Codificação | ISO-8859 / CP1252; o `grep` o trata como binário e corta a saída |
| Relógio | **UTC**, com sufixo `Z`; a janela mostra hora local |
| Leitura correta | `iconv -f CP1252 -t UTF-8 <arquivo> \| grep ...` |

**O que ensina.**
- **Evidência de log vem do arquivo, nunca da janela.** O arquivo está no mesmo relógio do trace e é reproduzível por `grep`.
- Colete o log **antes** de reiniciar o servidor. Depois do reinício ele vai para `.1`.
- A prova de que janela e arquivo registram os mesmos eventos: **microssegundos idênticos**, com exatamente 3 h de diferença (`00:34:34.613304` na janela, `03:34:34.613304Z` no arquivo).

### 4.5 Log do B2 extraído do arquivo, e o que ele revelou

**Objetivo.** Substituir a cópia da janela pela fonte em arquivo, com contexto completo.

**Feito.** `iconv ... events.txt.1 | sed -n '67,90p'`, com um cabeçalho de procedência. Commit `65b68c9`.

**Resultado — linha do tempo do B2 (UTC):**

| Horário | Evento |
|---|---|
| 03:32:27 | deploy do flow com `Transaction mode: No` |
| 03:34:34 | falha do `orderId 21`: dois blocos de 4 mensagens, terminando em "Retentativa 1 de 3" |
| 03:39:10 | deploy da reversão para `Yes` |

**O que ensina.** Três achados:

1. **O log mente em modo `No`.** Ele anuncia *"Retentativa 1 de 3"*, e não há nenhuma retentativa nos 4,5 minutos seguintes. Num incidente real, quem lê o log acredita que a mensagem está sendo retentada quando ela já não existe.
2. **A perda aparece como aviso.** O último registro é um `BIP2628W` (W, de warning). Um monitoramento que filtre só erros (`E`) não veria nada.
3. **O limiar aparece em três lugares:** `BOTHRESH(3)` no `queues.mqsc`, `2` na lógica do ESQL, e `"de 3"` no texto da mensagem. Mudar um sem os outros não gera erro nenhum.

Leitura de log: o ACE imprime a exceção mais externa primeiro. Dentro de cada bloco de mesmo horário, leia **de baixo para cima**.

### 4.6 Experimento E — preparação

**Objetivo.** Isolar uma única mudança: o `GravarDLQ` passa a apontar para uma fila inexistente.

**Feito.**
1. No Toolkit, `GravarDLQ` → Queue name → `APP.NAOEXISTE`.
2. `ibmint package` e `ibmint deploy` (BAR com os dois ESQLs e a policy).
3. `sync-ace.sh --apply` e `git diff ace/ | tee docs/evidencias/exp-e-diff.txt`.

**Resultado.**
- O diff tem **uma única linha**, só o `queueName`; o `location` ficou igual, então não há ruído de layout.
- O `BIP9339W` sobre a policy inalterada é esperado e inofensivo.

**O que ensina.** Uma evidência só isola uma causa se o diff mostrar uma única mudança.

### 4.7 Achado lateral — o comando de zerar nunca tinha funcionado

**Objetivo.** Começar o experimento com as quatro filas vazias.

**Feito.** O portão mostrou `APP.DLQ` com `CURDEPTH(1)` depois do zeramento. O diagnóstico rodou o comando sem `2>/dev/null` e leu a mensagem com `amqsbcg`.

**Resultado.**
```
File '/dev/null' exists - overwrite (y)es/(n)o/(a)ll ?
Read - Messages:1   Written - Messages:0   rc=71
BackoutCount : 3     orderId "20"     PutTime 03:24:57.99
```

**Mecanismo.**
1. O `dmpmqmsg -f /dev/null` pergunta se pode sobrescrever o arquivo.
2. O `docker exec` não tem terminal interativo, então ninguém responde e o comando aborta.
3. A leitura, feita sob syncpoint, é desfeita.
4. Cada tentativa fracassada foi um **rollback**, e o BOC da mensagem residual do C2 subiu de **0 para 3**.

**Correção.**
```bash
docker exec qm1 bash -c "dmpmqmsg -m QM1 -I $q -f stdout" > /dev/null 2>&1 \
  && echo "ok $q" || echo "FALHOU $q (rc=$?)"
```

Evidência: `docs/evidencias/achado-dmpmqmsg-boc3.txt`.

**O que ensina.**
- **O BOC não conta tentativas do ACE: conta rollbacks de qualquer programa sobre a mensagem.** Numa fila de entrada, uma ferramenta de administração que falhe assim pode gastar as tentativas de uma mensagem antes de o flow rodar uma única vez.
- **Um `2>/dev/null` transforma falha em silêncio.** É o mesmo padrão do `DEFINE REPLACE`: o comando "funciona" e não faz nada. Todo passo destrutivo precisa testar o `rc`.

### 4.8 Experimento E — execução e evidências

**Previsão (escrita antes):**
```
BOC 0 → falha → Catch → Trace → relança → ROLLBACK
BOC 1 → falha → Catch → Trace → relança → ROLLBACK
BOC 2 → falha → Catch → Trace → TratarFalha ok → GravarDLQ falha → ROLLBACK
BOC 3 → MQInput barra antes do flow → APP.BACKOUT
```

**Laço de filas** (`exp-e-rede-seguranca.txt`, `orderId 23`, PUT às 02:50:54.851 UTC):
```
IN OUT BACKOUT DLQ
0  0   0       0     ← 5 amostras antes
1  0   0       0     ← reservada sob syncpoint (4 amostras)
0  0   1       0     ← BACKOUT a partir de 23:50:57.877 local, até o fim
```

**Trace** (`exp-e-trace.txt`):
```
02:50:54.836 BOC=0 | 02:50:55.856 BOC=1 | 02:50:56.856 BOC=2
```
Os intervalos são de 1,020 s e 1,000 s. Não há linha com BOC 3.

**BACKOUT** (`exp-e-backout-dump.txt`):
- corpo `{"orderId":"23","forcarErro":"true"}`, 36 bytes, **sem o campo `erro`**;
- `BackoutCount 0`;
- `PutApplName amqsput`;
- `PutTime 02505484`.

**Log do servidor** (`exp-e-log-servidor.txt`, UTC):

| Horário | BIP | Leitura |
|---|---|---|
| 02:50:54.8 | `BIP2232E` + `BIP2628W` … "Retentativa 1 de 3" | 1ª entrega → rollback |
| 02:50:55.8 | `BIP2232E` no TratarFalha | 2ª entrega → rollback |
| 02:50:56.8 | `BIP2232E` **no GravarDLQ** | 3ª entrega, falha na gravação → rollback |
| 02:50:57.869 | **`BIP2648E`**, mensagem restaurada para uma fila | 4ª entrega, movida para `APP.BACKOUT` |

**Fila de destino** (`exp-e-fila-inexistente.txt`): `AMQ8147E: IBM MQ object APP.NAOEXISTE not found`.

**Conclusão.** Quando o próprio tratamento de erro falha, o rollback desfaz tudo o que o flow fez, e o MQ, ao atingir o `BOTHRESH`, move a mensagem original intacta para a fila de backout. Nenhuma mensagem se perde, mesmo com duas falhas em sequência.

**O que ensina.**
- **A previsão "2085 no log" estava errada.** O log registra o *node* que falhou (`BIP2232E` no `GravarDLQ`), não o código do MQ. A prova passou a ser o `BIP2232E`, o `BIP2648E` e o `AMQ8147E`.
- **O texto "Retentativa N" só é logado para N = 1**; isso se repetiu no C2 e no E. Para contar tentativas pelo log, conte os `BIP2232E`.
- **Dois relógios.** O trace (Windows) marcou a 1ª entrega 4 ms *antes* do `PutTime` (container). Diferenças de menos de ~10 ms entre máquinas não têm significado; intervalos medidos num mesmo relógio, sim.
- O intervalo de ~1 s se repetiu pela terceira vez (A, C2, E), inclusive na 4ª entrega, que o flow nunca vê.
- Um filtro construído a partir de uma previsão errada esconde justamente o que importa. Colete a janela de tempo inteira e filtre depois.

### 4.9 Reversão, provada em duas camadas

**Objetivo.** Voltar ao estado commitado e provar isso.

**Feito.**
1. `GravarDLQ` → `APP.DLQ`, package, deploy, `sync`.
2. `git diff ace/` → **vazio**; `git status` mostrou só `docs/log.md`.
3. Teste de runtime: `orderId 24` (normal) e `orderId 25` (com erro).

**Resultado.** `APP.OUT` = 1 (o `orderId 24` com `processedAt`), `APP.DLQ` = 1 (o `orderId 25` com `original` e `erro`), `APP.BACKOUT` = 0.

**O que ensina.** O `git diff` vazio prova o **arquivo**. Só uma mensagem de **erro** prova que o **runtime** voltou, porque o caminho feliz não passa pelo `GravarDLQ` e funcionaria com qualquer configuração dele.

### 4.10 Encerramento

- Evidências commitadas; `docs/log.md` atualizado (`879cda9`).
- **Achado:** o repositório **não tem remoto**. Nunca houve `push`, e a única cópia está no disco virtual do WSL. Medida imediata: `git bundle create /mnt/c/Users/LGzel/integration-lab-<data>.bundle --all`.

---

## 5. Índice de evidências e commits

| Commit | Conteúdo |
|---|---|
| `f1a3919` | fontes reais do ACE versionados; zip removido; evidências do C antigo |
| `f0575aa` | Trace node no ramo Catch |
| `867d221` | C2: 3 tentativas medidas, intervalo de ~1 s |
| `d915660` | correção de permissão do trace copiado de `/mnt/c` |
| `2714638` | B2: `No` perde a mensagem |
| `65b68c9` | log do B2 extraído do `events.txt.1` |
| `19f4ccf` | Experimento E e achado do `dmpmqmsg` |
| `879cda9` | `log.md` da sessão de 23/09 |
| `76d5ea2` | `ESTADO.md` reescrito, sem senhas |

| Arquivo em `docs/evidencias/` | Prova |
|---|---|
| `exp-c2-*` | retentativa e DLQ com motivo |
| `exp-b2-diff.txt` | a mudança de uma linha (`transactionMode="no"`) |
| `exp-b2-transacao-no.txt`, `exp-b2-trace.txt` | Catch 1 vez; nada em fila alguma |
| `exp-b2-log-servidor.txt` | "Retentativa 1 de 3" que nunca ocorre |
| `exp-e-diff.txt` | a mudança de uma linha (`APP.NAOEXISTE`) |
| `exp-e-rede-seguranca.txt` | laço de filas: BACKOUT 1, DLQ 0 |
| `exp-e-trace.txt` | 3 entregas no flow |
| `exp-e-backout-dump.txt` | mensagem original intacta |
| `exp-e-log-servidor.txt` | `BIP2232E` no GravarDLQ e `BIP2648E` |
| `exp-e-fila-inexistente.txt` | `AMQ8147E` |
| `achado-dmpmqmsg-boc3.txt` | BOC 0 → 3 por rollbacks de outro programa |

---

## 6. Premissas corrigidas (material de artigo)

| Premissa inicial | O que os dados mostraram |
|---|---|
| As retentativas levam milissegundos | há ~1 s fixo entre entregas, não configurável |
| Na DLQ, o MQMD mostrará `BackoutCount 2` | é 0: put novo nasce com BOC 0 |
| Put novo zera o BOC, e fim | nasce 0 **e sobe a cada rollback de qualquer programa**, inclusive ferramentas de administração |
| Na BACKOUT, o BOC 3 prova as tentativas | é 0; quem prova é o trace |
| `BIP1990I` = inicialização concluída | 1990 é o início; **1991** é a conclusão |
| O log do B2 se perdeu | estava no `events.txt.1`, e também na cópia da janela |
| O 2085 aparece no log do servidor | o log registra o node que falhou, não o código do MQ |
| "Retentativa N" é logado a cada tentativa | só para N = 1; conte os `BIP2232E` |
| O `dmpmqmsg -I -f /dev/null` esvazia a fila | aborta sem terminal (rc 71) e faz rollback |
| Janela e arquivo de log são fontes diferentes | mesmo evento, microssegundos idênticos; janela em hora local, arquivo em UTC |
| O caminho feliz prova a reversão | só uma mensagem de erro prova que o runtime do tratamento voltou |

---

## 7. Dívida de design registrada

1. **O `TratarFalha` depende de `Transaction mode: Yes`.** Relançar para ser retentado só é seguro com syncpoint; em `No`, o mesmo código causa perda. Registrar como invariante no ESQL e como regra de revisão de código no Projeto 5: consumidor com retentativa nunca em `No`.
2. **O limiar está em três lugares:** `BOTHRESH(3)`, o `2` no ESQL e o `"de 3"` no texto. Opção: uma UDP no flow, com comentário ligando ao `queues.mqsc`.
3. **Erro permanente e transitório tratados igual.** Payload inválido não melhora com retentativa. Classificar antes de retentar, o que muda o critério do teste final para `OUT + DLQ + BACKOUT = 100`.
4. **Backoff real precisa estar no flow.** O intervalo do MQInput não é garantido nem configurável.

---

## 8. Perguntas de entrevista que este trabalho responde

| Pergunta | Resposta com evidência |
|---|---|
| O que acontece se o consumidor cair no meio de uma mensagem? | Com `Yes`, rollback e reentrega (C2); com `No`, perda (B2). A diferença é uma linha no `.msgflow`. |
| Como você trata mensagem envenenada? | Catch intercepta, retenta sob controle e grava na DLQ com o erro estruturado. Se isso falhar, o `BOTHRESH` move para a backout (E). |
| Qual a diferença entre backout e DLQ? | Tabela da seção 2.4. |
| Como você investiga uma mensagem que sumiu? | Laço de profundidade das filas, trace do flow, `events.txt` em UTC, `AMQERR01.LOG` para autorização, `amqsbcg` para ler sem consumir. |
| O que o BackoutCount conta? | Rollbacks sobre a mensagem, de qualquer programa, com o caso do `dmpmqmsg` como exemplo real. |

---

## 9. Próximos passos, em ordem

1. **Publicar o repositório.**
   - Confirmar `git check-ignore .env`.
   - Procurar senhas no histórico com `git log -S "Abcd1234"`.
   - Reescrever o `ESTADO.md` sem senhas.
   - Limpar o histórico antes do primeiro push, **ou** trocar a senha do laboratório.
   - Criar o remoto e fazer o `push`.
2. **`docs/projeto3-transacional.md`**: C2, intervalo de 1 s, B2, E, achado do BOC, premissas corrigidas.
3. **`ESTADO.md` completo:**
   - caminho `servers\TEST_SERVER1`;
   - comando de zerar com `-f stdout`;
   - log de eventos em UTC/CP1252 com rotação;
   - regra *deploy → sync → commit*;
   - regra *evidência de log vem do arquivo*.
4. **Parte 2 — idempotência.** Antes de codificar, responda por escrito: em que ponto do flow marcar o `MsgId` como processado, sabendo que o Global Cache **não** participa da transação MQ? Marcar cedo demais perde mensagens no rollback; marcar tarde deixa uma janela de duplicação.

---

## 10. Glossário de códigos vistos nesta sessão

| Código | Significado |
|---|---|
| `BIP1990I` / `BIP1991I` | início / fim da inicialização do servidor |
| `BIP2232E` | erro ao tratar um erro anterior (esperado quando o Catch relança) |
| `BIP2230E` | erro ao processar mensagem no node indicado |
| `BIP2488E` | erro numa instrução ESQL (informa linha e coluna) |
| `BIP2951I` | evento gerado pelo código do usuário (o texto do `THROW`) |
| `BIP2628W` | exceção chegou ao node de entrada |
| `BIP2648E` | mensagem restaurada para uma fila (movida para backout) |
| `BIP9339W` | policy reimplantada sem mudança; recursos não afetados |
| `AMQ8147E` | objeto MQ não encontrado |
| `AMQ8148` | objeto em uso (impede o `CLEAR QLOCAL`) |
| `2035` / `2085` | MQRC não autorizado / objeto desconhecido |
| `rc=71` do `dmpmqmsg` | abortou; aqui, no prompt de sobrescrever arquivo |
