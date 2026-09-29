# Projeto 3 — Transacionalidade no MQ: retentativa, DLQ, backout e perda silenciosa

**Período:** 20–24/09/2026
**Ambiente:** IBM ACE 12.0.12.27 (Windows) + IBM MQ Advanced for Developers (container, WSL2)
**Application / flow:** `OrderProcessing` / `PassThrough`
**Horários:** evidências de trace, log do servidor e MQMD em **UTC**. Os laços de fila registram hora local (UTC − 3).

## Pergunta

O que acontece com uma mensagem quando o processamento falha e, depois, quando **o próprio tratamento da falha** falha? Em que condições ela é retentada, desviada com motivo, salva pelo MQ ou perdida?

A resposta separa garantia de entrega de perda silenciosa de dados. Nos experimentos abaixo, essa separação cabe em **uma linha** do `.msgflow`.

---

## 1. Configuração

### Filas — `mq/config/queues.mqsc`

| Objeto | Configuração relevante |
|---|---|
| `APP.IN` | `DEFPSIST(YES) BOTHRESH(3) BOQNAME('APP.BACKOUT') MAXDEPTH(50000)` |
| `APP.OUT` | `DEFPSIST(YES)` |
| `APP.BACKOUT` | `DEFPSIST(YES)`, com o `MAXDEPTH` padrão (5000) |
| `APP.DLQ` | `DEFPSIST(YES)` |
| `DEV.APP.SVRCONN` | SVRCONN com `MCAUSER('app')` |

O principal `app` tem, sobre `APP.**`: `+put +get +inq +browse +passall +setall`. As duas últimas são necessárias porque `SET OutputRoot = InputRoot` copia o MQMD, e gravar com o contexto de outra mensagem é uma permissão à parte.

### Falha controlada no ESQL (`ProcessarPedido`)

Três decisões deliberadas:

- **`COALESCE`**: em ESQL, comparar `NULL` com um literal dá `UNKNOWN`, não `FALSE`. Sem ele, o caminho feliz passaria por acidente.
- **`THROW` antes dos `SET`**: garante que a mensagem desviada carregue o payload original, sem os campos do Compute.
- **`CURRENT_GMTTIMESTAMP`**: carimbo em UTC, para correlacionar com o log do container sem converter fuso.

Caminho feliz de controle: `{"orderId":"9","valor":900}` saiu com `processedAt: 2026-09-21T01:00:26.463+00:00`. Isso confirma o `COALESCE` e o carimbo em UTC (22:00 local = 01:00 UTC do dia seguinte).

### Duas versões do flow

**v1 (experimentos A e B)**, sem tratamento de erro:
```
MQInput(APP.IN) ──► Compute ──► MQOutput(APP.OUT)
```

**v2 (experimentos C2, B2 e E)**, com o ramo Catch:
```
LerPedido (MQInput APP.IN) ──► ProcessarPedido (Compute) ──► GravarSaida (MQOutput APP.OUT)
        │
        └─ Catch ──► RegistrarTentativa (Trace) ──► TratarFalha (Compute) ──► GravarDLQ (MQOutput APP.DLQ)
```

| Node | Função |
|---|---|
| `RegistrarTentativa` | grava em `C:\temp\catch-trace.txt` uma linha por passagem pelo Catch: `${CURRENT_GMTTIMESTAMP} BOC=${Root.MQMD.BackoutCount} orderId=...` |
| `TratarFalha` | com `BOC < 2`, relança a exceção (rollback e nova entrega); com `BOC = 2`, monta `{original, erro{codigo, mensagem, detalhe, tentativas, flow, falhouEm}}` e deixa seguir |
| `GravarDLQ` | grava na `APP.DLQ`, na **mesma** unidade de trabalho da leitura de `APP.IN` |

O `TratarFalha` desvia na entrega com BOC 2, **antes** do `BOTHRESH(3)`. Por isso, no desenho normal, a `APP.BACKOUT` nunca é usada: ela é a rede de segurança para quando o próprio `TratarFalha` falhar (experimento E).

---

## 2. Método de evidência

Cada experimento da v2 segue o mesmo protocolo:

1. **Previsão escrita antes de rodar.**
2. **Diff de uma linha** do `.msgflow`, provando que só a propriedade estudada mudou (`exp-*-diff.txt`).
3. **Portão de estado inicial:** as quatro filas em `CURDEPTH(0)` e `IPPROCS(1)`.
4. **Quatro fontes independentes**, amarradas pelo mesmo `orderId`:

| Fonte | O que mostra | Relógio |
|---|---|---|
| laço de profundidade das filas (0,5 s) | onde a mensagem está a cada instante | local (WSL) |
| trace do Catch | quantas vezes o flow viu a mensagem, com qual BOC | UTC (Windows) |
| log de eventos do servidor (`events.txt`) | exceções e movimentos | UTC (Windows) |
| dump da mensagem final (`amqsbcg`, só leitura) | conteúdo e MQMD | UTC (container) |

5. **Reversão provada em duas camadas:** `git diff` vazio (o arquivo) e uma mensagem de erro chegando ao destino certo (o runtime).

---

## 3. Experimento A — v1, `Transaction mode: Yes`

Evidência: `docs/evidencias/exp-a-transacao-yes.txt`

| Horário (local) | `APP.IN` | `APP.BACKOUT` | |
|---|---|---|---|
| 22:25:37.4 | 0 | 2 | antes do put |
| 22:25:38.0 → 22:25:40.5 | **1** | 2 | mensagem retida, 5 amostras |
| 22:25:41.6 | 0 | **3** | desviada |

**Retenção de ~2,5 a 3 s.** Durante esse tempo a mensagem continuou visível em `APP.IN` enquanto o ACE a lia, falhava e revertia. É a assinatura do syncpoint: sob transação, o `MQGET` não remove a mensagem. Repetido com `orderId=4`, com a mesma duração.

A mensagem na `APP.BACKOUT` chegou com o payload original `{"orderId":"3","forcarErro":"true"}`, sem `processedBy` nem `processedAt`, o que mostra um rollback limpo. O MQMD preservou o horário do put original e `amqsput` como aplicação de origem, efeito do `+passall`. O `BackoutCount` veio **0**, como explicado na seção 10.

**Limite desta evidência:** a `APP.BACKOUT` já tinha mensagens de antes (2), e o número de tentativas foi inferido pela janela de retenção, sem ser medido. Os experimentos da v2 corrigem as duas coisas.

## 4. Experimento B — v1, `Transaction mode: No`

Única alteração: a propriedade `Transaction mode` do `MQInput`.
Evidência: `docs/evidencias/exp-b-transacao-no.txt`

A mensagem **nunca apareceu** em `APP.IN` nas 25 amostras (15 s). Verificação por exclusão: `APP.IN(0)`, `APP.OUT(0)`, `APP.BACKOUT(3)` inalterado, `APP.DLQ(0)`.

Sem syncpoint, o `MQGET` confirma a leitura no mesmo instante. Quando o `THROW` dispara, não há mais o que reverter. **A mensagem se perdeu, e nenhuma fila registra que ela existiu.**

---

## 5. Experimento C2 — v2, `Yes`, retentativa controlada e DLQ com motivo

Evidências: `docs/evidencias/exp-c2-*` · `orderId 20` · commit `867d221`

**Previsão:** o Catch dispara três vezes (BOC 0, 1, 2). Nas duas primeiras, o `TratarFalha` relança e há rollback. Na terceira, a mensagem vai para a DLQ com o motivo. `APP.BACKOUT` fica em 0.

**Resultado:**

| Fonte | Observado |
|---|---|
| trace | 3 linhas, BOC 0, 1, 2, a partir de 03:24:58 UTC, com ~1 s entre elas |
| filas | `APP.DLQ` = 1; `APP.BACKOUT` = 0; `APP.OUT` = 0 |
| DLQ | `{"original":{"orderId":"20","forcarErro":"true"},"erro":{...}}`, 238 bytes |
| MQMD na DLQ | `BackoutCount 0`; `PutTime 03:24:57.99`, o horário do put original |

**Conclusão:** a retentativa e o desvio com motivo acontecem **dentro da mesma unidade de trabalho**. A gravação na DLQ e a remoção de `APP.IN` são confirmadas juntas: não há janela em que a mensagem exista nas duas filas, nem em nenhuma.

## 6. O intervalo de ~1 s entre reentregas

| Experimento | Intervalos medidos |
|---|---|
| A | retenção de ~2,5–3 s para 3 entregas no flow e o desvio na 4ª |
| C2 | ~1 s entre BOC 0, 1 e 2 |
| E | **1,020 s** (BOC 0 → 1) e **1,000 s** (BOC 1 → 2); ~1,0 s até o `BIP2648E` na 4ª entrega |

**Conclusão:** neste ambiente, o MQInput reentrega a mensagem revertida com cerca de 1 s de intervalo, inclusive na 4ª entrega, que o flow nunca vê.

**Hipótese, não comprovada:** o intervalo vem do ciclo de leitura do MQInput numa conexão CLIENT entre Windows e o container. O que importa para o desenho não depende dela: **o intervalo não é garantido nem configurável.** Um backoff real (esperar mais a cada tentativa) precisa ser implementado no flow, por exemplo com o Timer ou com uma fila de reprocessamento.

---

## 7. Experimento B2 — v2, `Transaction mode: No`

Evidências: `docs/evidencias/exp-b2-*` · `orderId 21` · commits `2714638` e `65b68c9`

**Diff** (`exp-b2-diff.txt`): uma única linha, `transactionMode="no"` no `LerPedido`. O restante do flow, inclusive o Catch com o mesmo `TratarFalha`, é idêntico ao C2.

**Previsão:** o Catch dispara uma vez (BOC 0), e o `TratarFalha` relança. Como a leitura já foi confirmada, não há rollback nem reentrega, e a mensagem se perde.

**Resultado:**

| Fonte | Observado |
|---|---|
| trace | **1 linha**, `BOC=0` |
| filas | nenhuma variação em `APP.OUT`, `APP.DLQ` ou `APP.BACKOUT` (a prova é o **delta zero**) |
| log (UTC) | 03:32:27 deploy do `No`; **03:34:34** dois blocos de exceção terminando em **"Retentativa 1 de 3"**; **nada** até 03:39:10, a reversão |

**Conclusão:** o mesmo código que no C2 garante a entrega, aqui **causa** a perda. O relançamento que no C2 significa "tente de novo" significa, sem syncpoint, "descarte".

**O agravante é o que o log diz:**

1. **Ele anuncia uma retentativa que nunca acontece.** O texto "Retentativa 1 de 3" foi escrito supondo `Yes`. Nos 4,5 minutos seguintes não houve segunda entrega. Quem lê esse log num incidente acredita que a mensagem está sendo retentada, quando ela já não existe.
2. **A perda aparece como aviso.** O último registro é um `BIP2628W` (W, de warning). Um monitoramento que filtre só erros (`E`) não veria nada.

---

## 8. Experimento E — v2, `Yes`, falha no próprio tratamento

Evidências: `docs/evidencias/exp-e-*` · `orderId 23` · commit `19f4ccf`

**Diff** (`exp-e-diff.txt`): uma única linha, `GravarDLQ` → `queueName="APP.NAOEXISTE"`.

**Previsão:**
```
BOC 0 → falha → Catch → Trace → relança → ROLLBACK
BOC 1 → falha → Catch → Trace → relança → ROLLBACK
BOC 2 → falha → Catch → Trace → TratarFalha ok → GravarDLQ falha → ROLLBACK
BOC 3 → MQInput barra antes do flow (BOTHRESH) → APP.BACKOUT
```

**Resultado:**

Laço de filas (hora local; put às 02:50:54.851 UTC):
```
IN OUT BACKOUT DLQ
0  0   0       0     ← 5 amostras antes (estado inicial comprovado)
1  0   0       0     ← reservada sob syncpoint, 4 amostras
0  0   1       0     ← APP.BACKOUT a partir de 23:50:57.877, até o fim
```

Trace (UTC):
```
02:50:54.836 BOC=0 · 02:50:55.856 BOC=1 · 02:50:56.856 BOC=2
```
Não há linha `BOC=3`: o MQInput barrou a mensagem antes de ela entrar no flow.

Log do servidor (UTC):

| Horário | BIP | Leitura |
|---|---|---|
| 02:50:54.8 | `BIP2232E` + `BIP2628W` … "Retentativa 1 de 3" | 1ª entrega → rollback |
| 02:50:55.8 | `BIP2232E` no `TratarFalha` | 2ª entrega → rollback |
| 02:50:56.8 | `BIP2232E` **no `GravarDLQ`** | 3ª entrega; falha ao gravar na DLQ → rollback |
| 02:50:57.869 | **`BIP2648E`**: mensagem restaurada para uma fila | 4ª entrega → `APP.BACKOUT` |

Mensagem na `APP.BACKOUT`:
- corpo `{"orderId":"23","forcarErro":"true"}`, 36 bytes, **sem o campo `erro`**;
- `BackoutCount 0`, `PutApplName amqsput`, `PutTime 02:50:54.84`.

Fila de destino: `AMQ8147E: IBM MQ object APP.NAOEXISTE not found`.

**Conclusão:** quando o próprio tratamento de erro falha, o rollback desfaz tudo o que o flow fez, inclusive a mensagem que o `TratarFalha` montou. Ao atingir o `BOTHRESH`, o MQ move a mensagem **original** para a fila de backout. Nenhuma mensagem se perde, mesmo com duas falhas em sequência.

**Previsão que errou:** esperava-se o código `2085` no log. O log registra o **node** que falhou (`BIP2232E` no `GravarDLQ`), não o código do MQ. A prova passou a ser o conjunto `BIP2232E` + `BIP2648E` + `AMQ8147E`.

---

## 9. Quadro comparativo

| | A | B | C2 | B2 | E |
|---|---|---|---|---|---|
| Flow | v1 | v1 | v2 | v2 | v2 |
| `Transaction mode` | Yes | **No** | Yes | **No** | Yes |
| Falha extra | — | — | — | — | `GravarDLQ` quebrado |
| Entregas no flow | 3 (inferido) | 1 | **3** (trace) | **1** (trace) | **3** (trace) |
| Destino final | `APP.BACKOUT` | **nenhum** | `APP.DLQ`, com motivo | **nenhum** | `APP.BACKOUT` |
| Payload recuperável | sim | não | sim, com o erro | não | sim, original |
| O que o operador vê | mensagem na backout | nada nas filas | DLQ com o erro | um **aviso** e uma retentativa que não existe | backout e `BIP2648E` |

As três camadas de fila fazem coisas diferentes:

| Fila | Quem grava | Quando |
|---|---|---|
| `APP.DLQ` | o **flow**, de propósito | o erro esgotou as tentativas; a mensagem leva o motivo |
| `APP.BACKOUT` | o **MQInput**, pelo mecanismo do MQ | `BOC >= BOTHRESH`; mensagem original, sem motivo |
| DEADQ do queue manager | o **MQ** | não consegue entregar em lugar nenhum |

---

## 10. Achados colaterais

### O `BackoutCount` nas filas de destino é sempre 0, e isso está correto

Na `APP.BACKOUT` (A, E) e na `APP.DLQ` (C2), o `BackoutCount` veio 0. A mensagem gravada ali é um **put novo**, e todo put novo nasce com BOC 0. O BOC 3 existe só na 4ª entrega em `APP.IN`, a que o MQInput não repassa ao flow.

Consequência: **a contagem de tentativas não pode ser auditada pela fila de destino.** A evidência é o trace (uma linha por entrega no flow) ou a contagem de `BIP2232E` no log.

### O `BackoutCount` conta rollbacks de *qualquer* programa

Evidência: `docs/evidencias/achado-dmpmqmsg-boc3.txt`

A mensagem residual do C2 na `APP.DLQ` tinha BOC 0 no dump de 22/09. Dois dias depois, sem que o ACE tivesse tocado nela, estava com **BOC 3**. A causa foi o comando usado para esvaziar a fila:

```
dmpmqmsg -m QM1 -I APP.DLQ -f /dev/null
File '/dev/null' exists - overwrite (y)es/(n)o/(a)ll ?
Read - Messages:1   Written - Messages:0   rc=71
```

Sem terminal interativo, ninguém responde à pergunta. O `dmpmqmsg` aborta e **desfaz a leitura, que tinha sido feita sob syncpoint**. Cada tentativa de zerar foi um rollback, e o MQ incrementou o BOC.

**Por que importa em produção:** numa fila de entrada com `BOTHRESH(3)`, uma ferramenta de administração que falhe assim pode gastar as tentativas de uma mensagem antes de o flow rodar uma única vez. Quando o flow finalmente a lê, ela vai direto para a backout.

**Regra derivada:** passo destrutivo testa o código de retorno. O `2>/dev/null` que escondia o `rc=71` fez o comando de zerar falhar em silêncio desde a sessão anterior. Comando corrigido:

```bash
docker exec qm1 bash -c "dmpmqmsg -m QM1 -I $q -f stdout" > /dev/null 2>&1 \
  && echo "ok $q" || echo "FALHOU $q (rc=$?)"
```

### A transacionalidade é decidida no node de entrada

O `Compute` está com `Transaction: Automatic`, que herda a unidade de trabalho já aberta. Quem define o comportamento transacional do flow inteiro é o `MQInput`, como mostram B e B2.

### Retentativa: da fila, ou do flow

O `MQInput` não tem uma aba *Retry* no ACE 12. A retentativa **nativa** é da fila, via `BOTHRESH` e `BOQNAME` (experimento A). A retentativa **com motivo** precisa ser construída no flow, com o Catch lendo o `BackoutCount` (C2).

É um contraste direto com o WSO2 MI, onde `max.delivery.attempts` é propriedade do *message processor*, ou seja, do runtime e não do broker.

### Esvaziar filas com o ACE ligado

`CLEAR QLOCAL` falha com `AMQ8148E` (objeto em uso) enquanto houver handle aberto, e o ACE mantém abertas as filas do flow. Para esvaziar sem parar o ACE, use o `dmpmqmsg` corrigido acima. O `amqsget` também funciona.

### O log de eventos do servidor

| Propriedade | Valor |
|---|---|
| Arquivo | `servers\TEST_SERVER1\log\integration_server.TEST_SERVER1.events.txt` |
| Rotação | a cada inicialização (`.1` a `.9`); colete **antes** de reiniciar |
| Codificação | CP1252: leia com `iconv -f CP1252 -t UTF-8` |
| Relógio | UTC (a janela do servidor mostra hora local; os microssegundos são idênticos) |
| Falha num `MQOutput` do Catch | registra o node (`BIP2232E`), **não** o código do MQ |
| Texto do relançamento | "Retentativa N" só é registrado para **N = 1**; conte os `BIP2232E` |
| Ordem das mensagens | a mais externa primeiro; leia cada bloco de baixo para cima |

### Dois relógios

No experimento E, o trace (relógio do Windows) marcou a 1ª entrega em 02:50:54.836, e o `PutTime` do MQ (relógio do container) marcou 02:50:54.84: a entrega aparece ~4 ms *antes* do put. Diferenças de menos de ~10 ms entre máquinas não têm significado. Intervalos medidos num mesmo relógio, como os do trace, têm.

---

## 11. Premissas corrigidas

| Premissa inicial | O que os dados mostraram |
|---|---|
| As retentativas levam milissegundos | há ~1 s fixo entre entregas, não configurável |
| Na backout, o BOC 3 prova as tentativas | é 0 (put novo); quem prova é o trace |
| Na DLQ, o MQMD mostrará `BackoutCount 2` | é 0, pelo mesmo motivo |
| Put novo zera o BOC, e fim | nasce 0 **e sobe a cada rollback de qualquer programa** |
| Sem transação, não há rastro nenhum | não há rastro **nas filas**; o log registra um aviso e anuncia uma retentativa inexistente |
| O `2085` aparece no log | o log registra o node que falhou, não o código do MQ |
| "Retentativa N" é logado a cada tentativa | só para N = 1 |
| `dmpmqmsg -I -f /dev/null` esvazia a fila | aborta sem terminal (rc 71) e faz rollback |
| O caminho feliz prova a reversão | só uma mensagem de erro prova que o runtime do tratamento voltou |

---

## 12. Dívida de design

1. **O `TratarFalha` só é seguro com `Transaction mode: Yes`.** Relançar para ser retentado depende do syncpoint. Em `No`, o mesmo código causa perda (B2). Registrar como invariante no ESQL e como regra de revisão: consumidor com retentativa nunca em `No`.
2. **O limiar está em três lugares:** `BOTHRESH(3)` no `queues.mqsc`, `2` na lógica do ESQL e `"de 3"` no texto da mensagem. Mudar um sem os outros não gera erro nenhum. Opção: uma propriedade definida pelo usuário (UDP) no flow, com comentário ligando ao `queues.mqsc`.
3. **Erro permanente e erro transitório são tratados igual.** Um payload inválido não melhora com retentativa. Classificar antes de retentar, o que muda o critério do teste final para `OUT + DLQ + BACKOUT = 100`.
4. **Não há backoff.** O intervalo de ~1 s vem do MQInput e não é configurável.
5. **A `APP.BACKOUT` não tem consumidor.** Mensagens que chegam lá ficam sem motivo registrado. Candidato: um `BackoutHandler` (`MQInput(APP.BACKOUT)` → enriquecer → `MQOutput(APP.DLQ)`), ou um alerta de profundidade maior que 0 (Projeto 7).

---

## 13. Erros de ferramenta resolvidos

| Erro | Causa | Solução |
|---|---|---|
| `duplicate entry: R2Policies\MQ_LOCAL.policyxml` | o work dir `TEST_SERVER1` ficava **dentro** do workspace, e o `run/` dele tem cópia de cada projeto implantado | work dir movido para `C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1` |
| Policy ausente na implantação (`BIP1361E`) | a referência `{R2Policies}:MQ_LOCAL` **não** leva a policy junto no empacotamento | incluir `--project R2Policies` no `ibmint package`, ou implantar a policy em BAR próprio **antes** da aplicação |

O segundo ponto responde a *"como promover de dev para prod sem alterar o BAR?"*: policy e aplicação têm ciclos de vida distintos.

**Nota de método:** o `BIP8081E` é genérico e admite várias explicações plausíveis. O que resolveu foi reduzir o comando ao mínimo (`--project R2Policies` sozinho) antes de teorizar sobre interações entre as partes.

---

## 14. Próximos passos — parte 2

- [ ] **Idempotência:** consumir uma duplicata sem duplicar o efeito. O Global Cache **não** participa da transação MQ, então o ponto do flow em que a mensagem é marcada como processada define se há perda (marca antes de um rollback) ou uma janela de duplicação (marca depois do commit).
- [ ] Classificar erro permanente e transitório no `TratarFalha`.
- [ ] Request/reply com `APP.REPLY`, `ReplyToQ` e `CorrelId = MsgId`.
- [ ] Pub/sub em `APP.EVENTS`, com assinatura durável e não durável.
- [ ] **Teste final:** 100 mensagens, 30% com erro; soma das filas fechando, zero duplicatas, três execuções seguidas.
- [ ] Tuning com `Additional instances`: throughput e perda de ordenação.
- [ ] **F2:** amostrar `UNCOM` durante as retentativas e derrubar o consumidor com a transação aberta: prova o rollback implícito e mostra se o intervalo de ~1 s ocorre dentro ou fora da transação.
