# ESTADO.md — Laboratório de Integração (IBM ACE + MQ + WSO2)
### Documento de retomada. Última atualização: 24/09/2026

> **Para quem ler isto:** este arquivo é o estado atual do projeto. O ambiente abaixo está verificado. Vá direto para a seção 7 (Próximo passo).
> Visão geral do plano e do Projeto 3: `docs/projeto3-briefing.md`. Histórico por sessão: `docs/log.md`.

---

## 1. Objetivo

Profissional sênior de integração com base em **WSO2** fazendo a transição para o ecossistema **IBM** (App Connect Enterprise, MQ, API Connect). O entregável é um portfólio público em que cada competência vem com **evidência reproduzível**: código, configuração, logs e medições. Mercado-alvo: Rio de Janeiro e São Paulo — bancos, seguradoras e consultorias.

Plano original em `plano-integration-engineer.md`; correções e reordenação em `plano-integration-engineer-addendum-v2.md`.

**Cadência assumida:** 4–6 h/semana (Tier 1 em ~16 semanas).

---

## 2. Ambiente — Linux (WSL2)

A infraestrutura roda aqui e o desenvolvimento roda no Windows. A ponte entre os dois é `localhost:1414`.

| Item | Valor |
|---|---|
| Distro | Debian 13 (trixie), WSL2 |
| Usuário | `zelaya` |
| RAM / swap | 4 GiB / 8 GiB (via `C:\Users\LGzel\.wslconfig`); host com 8 GB no total |
| Docker | engine **nativo** no WSL (não Docker Desktop); systemd via `/etc/wsl.conf` |
| Java / build | Temurin 17, Maven 3.9.9 |
| Utilitários | git, jq, curl, openssl, rsync, file (os dois últimos não vêm no Debian mínimo) |
| Repositório | `~/integration-lab`, branch `master` |

### Containers

```
qm1    icr.io/ibm-messaging/mq:latest   portas 1414, 9443   mem_limit 1g
mock   wiremock/wiremock:latest         porta 8080          mem_limit 256m
```

- **Subir tudo:** `cd ~/integration-lab && ./scripts/up.sh`
- **Parar preservando dados:** `docker compose stop`. **Nunca** `down -v`, que apaga o volume `mqdata`.
- `wsl --shutdown` derruba os containers; depois dele, rode o `./scripts/up.sh` de novo.
- **O queue manager roda em UTC.**

### Objetos do MQ — `mq/config/queues.mqsc` é a fonte da verdade

Qualquer `ALTER` manual numa fila `APP.*` é desfeito no próximo `up.sh`. Um experimento que exija outro valor deve mudar o arquivo e commitar, ou declarar a alteração temporária na evidência.

| Objeto | Configuração |
|---|---|
| `APP.IN` | `DEFPSIST(YES) BOTHRESH(3) BOQNAME('APP.BACKOUT') MAXDEPTH(50000)` |
| `APP.OUT`, `APP.BACKOUT`, `APP.DLQ`, `APP.REPLY` | `DEFPSIST(YES)` |
| `APP.EVENTS` | TOPIC, topic string `app/events` |
| `DEV.APP.SVRCONN` | SVRCONN com `MCAUSER('app')`; usa **ALTER**, nunca `DEFINE REPLACE` |

### Autorizações — `mq/config/authorities.sh`

```bash
setmqaut -m QM1 -t qmgr -p app +connect +inq +setall
setmqaut -m QM1 -n "APP.**" -t queue -p app +put +get +inq +browse +passall +setall
```

O principal é `app`, com perfil genérico `APP.**`: a imagem de desenvolvedor só autoriza `DEV.**`, e não existe grupo `mqclient` nela.

### Credenciais

As senhas ficam **só** no `.env`, que está fora do git. O modelo está em `.env.example`, e o `docker-compose.yml` lê as variáveis `${MQ_ADMIN_PASSWORD}` e `${MQ_APP_PASSWORD}`. As senhas do MQ precisam de pelo menos 8 caracteres.

Console web: `https://localhost:9443`, usuário `admin`, senha em `MQ_ADMIN_PASSWORD`.

> **Histórico:** até 24/09 este arquivo trazia a senha do laboratório em texto claro (commit `58650d1`). A senha foi trocada; a que consta no histórico está inválida.

---

## 3. Ambiente — Windows

| Item | Valor |
|---|---|
| ACE | **12.0.12.27** Developer Edition, Windows 64 |
| Workspace do Toolkit | `C:\Users\LGzel\IBM\ACET12\workspace` |
| **Work dir do servidor** | `C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1` (fora do workspace, para evitar `duplicate entry`) |
| Integration servers | `TEST_SERVER1`, independente, sem integration node |
| MQ client | Redistributable 9.4.0.26 em `C:\MQClient` (o ACE **não** embarca cliente MQ) |
| Usuário Windows | `LGzel` (≠ `zelaya`, que é o usuário do Linux) |

### Variáveis de ambiente de usuário (obrigatórias)

```
PATH                  += C:\MQClient\bin64
MQ_INSTALLATION_PATH   = C:\MQClient
MQ_FILE_PATH           = C:\MQClient
```

Sem `MQ_INSTALLATION_PATH`, o ACE não carrega as bibliotecas do MQ, mesmo com o PATH correto. O redistributable **não traz `setmqenv`**.

### Console de comandos do ACE

```
"C:\Program Files\IBM\ACE\12.0.12.27\ace.cmd"
```

- Os comandos `mqsi*` e `ibmint` **só existem aqui**. É um cmd do Windows: `dir /a`, não `ls`.
- A janela em que o `IntegrationServer` roda fica ocupada. Para os comandos `ibmint`, abra um **segundo** console. Fechar a primeira janela derruba o servidor.

### Subir o servidor

```
IntegrationServer --work-dir C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1
```

A inicialização terminou quando aparece o `BIP1991I` (o `BIP1990I` é só o início).

### Credencial do MQ no servidor

```
mqsisetdbparms -w C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1 -n mq::mqcreds -u app -p <MQ_APP_PASSWORD do .env>
mqsireportdbparms -w C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1 -n mq::mqcreds
```

A sintaxe `-w` é a de servidor independente. Reinicie o servidor depois de alterar a credencial.

### Log de eventos do servidor

| Propriedade | Valor |
|---|---|
| Arquivo | `servers\TEST_SERVER1\log\integration_server.TEST_SERVER1.events.txt` |
| No WSL | `/mnt/c/Users/LGzel/IBM/ACET12/servers/TEST_SERVER1/log/` |
| Rotação | a cada inicialização: atual → `.1` → … → `.9` |
| Codificação | CP1252 (o `grep` o trata como binário) |
| Relógio | **UTC**, com sufixo `Z`; a janela do servidor mostra hora local |

```bash
iconv -f CP1252 -t UTF-8 <arquivo> | grep ...
```

---

## 4. Artefatos do ACE

### Fontes versionados

| Projeto do workspace | Pasta no repositório |
|---|---|
| `OrderProcessing` (Application) | `ace/apps/OrderProcessing` |
| `R2Policies` (Policy Project) | `ace/policies/R2Policies` |

A cópia é feita por `scripts/sync-ace.sh`, com mapa explícito projeto → pasta. O padrão é dry-run; `--apply` aplica. O script falha se a origem não existir e usa `-rt --chmod=D755,F644` para não herdar o 777 do NTFS. Projetos de curso do workspace **não** vão para o repositório.

**Regra: deploy → `./scripts/sync-ace.sh --apply` → commit.**

### `R2Policies` / `MQ_LOCAL.policyxml` (tipo MQEndpoint)

| Propriedade | Valor |
|---|---|
| Connection | `CLIENT` |
| Queue manager | `QM1`, host `localhost`, porta `1414` |
| Channel | `DEV.APP.SVRCONN` |
| Security identity (DSN) | `mqcreds` |
| Use SSL | `false` (TLS é o Projeto 11) |

### `OrderProcessing` / `PassThrough.msgflow`

```
LerPedido (MQInput APP.IN) ──► ProcessarPedido (Compute) ──► GravarSaida (MQOutput APP.OUT)
        │
        └─ Catch ──► RegistrarTentativa (Trace) ──► TratarFalha (Compute) ──► GravarDLQ (MQOutput APP.DLQ)
```

| Node | Função |
|---|---|
| `LerPedido` | domínio JSON; `Transaction mode` **Yes** (é o padrão, por isso o atributo não aparece no `.msgflow`); policy `{R2Policies}:MQ_LOCAL` |
| `ProcessarPedido` | acrescenta `processedBy: ACE-LAB` e `processedAt` em ISO, UTC. Com `"forcarErro":"true"` no corpo, lança `THROW USER EXCEPTION 2951` |
| `RegistrarTentativa` | grava em `C:\temp\catch-trace.txt` a linha `${CURRENT_GMTTIMESTAMP} BOC=${Root.MQMD.BackoutCount} orderId=${Root.JSON.Data.orderId}` |
| `TratarFalha` | com `BOC < 2`, relança (rollback e nova entrega); com `BOC = 2`, monta `{original, erro{codigo, mensagem, detalhe, tentativas, flow, falhouEm}}` |
| `GravarDLQ` | grava em `APP.DLQ`, commitando junto com a remoção da mensagem de `APP.IN` |

### Empacotar e implantar

```
ibmint package --input-path C:\Users\LGzel\IBM\ACET12\workspace --output-bar-file C:\temp\OrderProcessing.bar --project OrderProcessing --project R2Policies
ibmint deploy --input-bar-file C:\temp\OrderProcessing.bar --output-host localhost --output-port 7600
```

Na reimplantação, o `BIP9339W` (policy sem mudança) é esperado e inofensivo.

---

## 5. O que já está provado

| # | Prova | Evidência |
|---|---|---|
| 1 | Ambiente reprodutível: o `up.sh` recria o MQ e o mock e aplica filas e autorizações | `scripts/up.sh` |
| 2 | ACE (Windows) conecta ao MQ (WSL) em modo CLIENT, com credencial do vault | sessão de 18/09 |
| 3 | Flow ponta a ponta: `APP.IN` → `APP.OUT` com `processedBy` e `processedAt` em UTC | caminho feliz |
| 4 | **C2** — o Catch retenta sob controle: trace BOC 0, 1, 2, depois DLQ com motivo estruturado | `exp-c2-*` |
| 5 | **Intervalo de ~1 s fixo entre reentregas**, medido em três experimentos (A, C2, E); não garantido nem configurável | `exp-c2-trace.txt`, `exp-e-trace.txt` |
| 6 | **B2** — com `Transaction mode: No`, o Catch dispara uma vez e a mensagem se perde; o log ainda anuncia "Retentativa 1 de 3" | `exp-b2-*` |
| 7 | **E** — se o próprio tratamento falhar, o rollback desfaz tudo e o MQ move a mensagem original para `APP.BACKOUT` (`BIP2648E`) | `exp-e-*` |
| 8 | **O BOC sobe com o rollback de qualquer programa**, não só do ACE: uma mensagem residual foi de 0 para 3 por falhas do `dmpmqmsg` | `achado-dmpmqmsg-boc3.txt` |
| 9 | Duplicação demonstrada: a mesma mensagem enviada duas vezes gera duas saídas (o "antes" da idempotência) | sessão de 19/09 |

---

## 6. Erros resolvidos (registro — vale como conteúdo)

### Cadeia de conexão ACE ↔ MQ (18/09)

| # | Erro | Causa | Solução |
|---|---|---|---|
| 1 | `BIP1361E` | o Policy Project é um artefato separado e precisa ser implantado também | incluir `R2Policies` no BAR |
| 2 | `BIP2684E` | o ACE não embarca cliente MQ | instalar o MQ Redistributable Client |
| 3 | `BIP2684E` persistindo | o runtime precisa da raiz da instalação | definir `MQ_INSTALLATION_PATH` e `MQ_FILE_PATH` |
| 4 | `2035` no `APP.IN` | a imagem de dev só autoriza `DEV.**` | `setmqaut` no principal `app`, perfil `APP.**` |
| 5 | `2035` no `MQOutput` | `SET OutputRoot = InputRoot` copia o MQMD; gravar com contexto de outra mensagem exige permissão própria | `+passall +setall` |

### Armadilhas silenciosas (o comando "funciona" e não faz o esperado)

| Armadilha | Consequência | Regra |
|---|---|---|
| `DEFINE ... REPLACE` em objeto pré-existente | zera atributos não informados (apagou o `MCAUSER`) | `ALTER` em objeto que a imagem já cria |
| `dmpmqmsg -I <fila> -f /dev/null` | pergunta se sobrescreve o arquivo, aborta sem terminal (rc 71) e faz rollback, **incrementando o BOC** | `-f stdout > /dev/null` e testar o `rc` |
| `2>/dev/null` em passo destrutivo | esconde a falha | todo passo destrutivo testa o `rc` e imprime `ok`/`FALHOU` |
| `git grep` / `git log -- <caminho>` fora da raiz | busca só na subpasta atual; o teste "passa" | rodar da raiz ou usar `git -C ~/integration-lab ...` |
| `EOF` de heredoc indentado | o terminal fica esperando (`>`) | `EOF` sempre na coluna 0 |
| `cp` de `/mnt/c` | o arquivo entra no git como executável (777 do NTFS) | `install -m 644` ou `chmod 644` |
| `mkdir` fora da condição `--apply` | um dry-run que escreve em disco | dry-run estritamente só leitura |

### Outros

- **`ibmint package --java-version` não existe no 12.0.12.27.** A sintaxe varia por fix pack; rode o comando sem argumentos e leia a ajuda antes de escrever script de pipeline.
- **`CLEAR QLOCAL` falha com o ACE ligado** (`AMQ8148`, fila em uso). Esvazie com o `dmpmqmsg` corrigido.
- **Work dir dentro do workspace** causa `duplicate entry` no Toolkit. Por isso ele foi para `servers\`.
- **`APPLTAG` guarda só os últimos 28 caracteres** do caminho do executável. Para achar a conexão do ACE, filtre por canal ou `CONNAME`.
- **`CONNAME(172.18.0.1)`** é o gateway da bridge do Docker. Todo cliente do Windows aparece com esse endereço, então CHLAUTH por endereço não distingue o ACE (Projeto 11).
- **O log não registra o código do MQ** quando um `MQOutput` falha no Catch: registra `BIP2232E` no node. O texto "Retentativa N" só é logado para N = 1. **Conte tentativas pelos `BIP2232E` ou pelo trace.**
- **Dois relógios:** o trace (Windows) e o `PutTime` (container) diferem alguns milissegundos. Diferenças abaixo de ~10 ms entre máquinas não têm significado.
- **O flow consome antes do `BIP1991I`.** No exp F, a mensagem parada foi processada 114 ms antes do "servidor concluiu a inicialização" (mesmo relógio). Esperar o `BIP1991I` não garante que nada foi processado: o consumo começa no `BIP2269I` do flow.
- **O mesmo `MsgId`, três formatos.** `amqsbcg`: `X'414D5120...'` (maiúsculas). API REST: `ID:414d5120...` (prefixo JMS, minúsculas). `CAST` do ESQL: `X'414d5120...'` (minúsculas). Normalizar os dois lados (sem prefixo, mesma caixa) antes de comparar.

### Diagnóstico padrão

```bash
docker exec qm1 bash -c 'tail -60 /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG'     # 2035, canal, autenticação
iconv -f CP1252 -t UTF-8 /mnt/c/Users/LGzel/IBM/ACET12/servers/TEST_SERVER1/log/integration_server.TEST_SERVER1.events.txt | tail -40
```

---

## 7. PRÓXIMO PASSO (comece aqui)

### 7.1 Pendências de fechamento

- [x] Senha do laboratório trocada (`.env`, recriação do container, `mqsisetdbparms`) e validada com um caminho feliz
- [x] Repositório publicado no GitHub (`git remote -v` mostra `origin`)
- [ ] `docs/projeto3-transacional.md` com C2, intervalo de 1 s, B2, E, achado do BOC e premissas corrigidas

### 7.2 Projeto 3, parte 2 — idempotência

**Antes de codificar, responda por escrito em `docs/projeto3-idempotencia.md`:** *(respondido em 06/10: secoes 4 a 6 do documento)*

1. Em que ponto do flow o `MsgId` (ou o `orderId`) é marcado como processado? O **Global Cache não participa da transação MQ**:
   - marcar **antes** de um rollback faz a reentrega ser descartada como duplicata, o que é perda silenciosa;
   - marcar **depois** do commit deixa uma janela de duplicação.

   Descreva essa janela com precisão. Ela é o argumento para a tabela sob XA do Projeto 10.
2. A chave de idempotência é o `MsgId` do MQ ou um identificador de negócio (`orderId`)? Um reenvio pelo cliente gera `MsgId` novo.
3. Por quanto tempo a marca vale? Defina o TTL e o que acontece quando ele expira.

**Definition of done:** a mesma mensagem enviada duas vezes gera **uma** saída em `APP.OUT`, e a segunda é descartada com log. Um rollback no meio **não** faz a reentrega ser descartada. Três evidências (laço de filas, trace e log) com o mesmo identificador.

### 7.3 Resto do Projeto 3

- Classificar erro permanente × transitório no `TratarFalha`. Isso muda o critério do teste final para `OUT + DLQ + BACKOUT = 100`; escreva o critério **antes**.
- Request/reply com `APP.REPLY`, `ReplyToQ` e `CorrelId = MsgId`; dois clientes simultâneos.
- Pub/sub em `APP.EVENTS`, com assinatura durável × não durável.
- **Teste final:** 100 mensagens, 30% com erro, soma fechando, zero duplicatas, três execuções seguidas.
- Tuning com `Additional instances`: medir throughput e observar a perda de ordenação.

---

## 8. Roteiro

**Tier 1 — a linha de corte (~80–100 h). A partir daqui, começar a se candidatar.**

| # | Projeto | Estado |
|---|---|---|
| 1 | Conector R2/S3 com SigV4 | pendente; o flow `testarR2` está no `Module5` e precisa ser extraído para projeto próprio |
| 3 | MQ transacional | **parte 1 concluída**; parte 2 em seguida |
| 7 | Observabilidade (mínimo) | pendente; testar se o OpenTelemetry habilita no Windows (está desligado por *configuração*) |
| 5 | CI/CD e containers (mínimo) | pendente; `sync-ace.sh` e fontes versionados já são base |

**Tier 2 (~+60 h):** 9 (DFDL/copybook), 10 (banco + XA), 6 (segurança ponta a ponta), 11 (TLS/CHLAUTH/CONNAUTH no MQ).

**Tier 3:** 4 (Kafka), 2 (gateway), 8 (capstone).

**Restrições de memória (host de 8 GB):**
- MQ + mock + Postgres + Keycloak cabem juntos.
- Kafka/Redpanda e WSO2 MI: um de cada vez.
- **DataPower (4 GB+) não roda nesta máquina.**

---

## 9. Comandos de referência

```bash
# --- WSL: ambiente ---
cd ~/integration-lab && ./scripts/up.sh
docker ps --format "table {{.Names}}\t{{.Status}}"
docker compose stop                                   # preserva o volume

# --- WSL: estado das filas (portao antes de todo experimento) ---
docker exec -i qm1 runmqsc QM1 <<'EOF' | grep -E "QUEUE|CURDEPTH|IPPROCS"
DISPLAY QSTATUS(APP.IN) CURDEPTH IPPROCS
DISPLAY QSTATUS(APP.OUT) CURDEPTH
DISPLAY QSTATUS(APP.BACKOUT) CURDEPTH
DISPLAY QSTATUS(APP.DLQ) CURDEPTH
EOF

# --- WSL: zerar filas (funciona com o ACE ligado; testa o rc) ---
for q in APP.OUT APP.DLQ APP.BACKOUT; do
  docker exec qm1 bash -c "dmpmqmsg -m QM1 -I $q -f stdout" > /dev/null 2>&1 \
    && echo "ok      $q" || echo "FALHOU  $q (rc=$?)"
done

# --- WSL: enviar, ler e inspecionar ---
docker exec -i qm1 bash -c '/opt/mqm/samp/bin/amqsput APP.IN QM1' <<'EOF'
{"orderId":"NN","valor":100}
EOF
docker exec -i qm1 bash -c '/opt/mqm/samp/bin/amqsget APP.OUT QM1'        # destrutivo
docker exec -i qm1 bash -c '/opt/mqm/samp/bin/amqsbcg APP.DLQ QM1'        # so leitura

# --- WSL: sincronizar fontes do ACE ---
./scripts/sync-ace.sh            # dry-run
./scripts/sync-ace.sh --apply
git diff ace/

# --- WSL: evidencias ---
grep "orderId='NN'" /mnt/c/temp/catch-trace.txt | tee docs/evidencias/<exp>-trace.txt
chmod 644 docs/evidencias/*.txt
```

```
:: --- Windows (console do ACE) ---
"C:\Program Files\IBM\ACE\12.0.12.27\ace.cmd"
IntegrationServer --work-dir C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1
mqsireportdbparms -w C:\Users\LGzel\IBM\ACET12\servers\TEST_SERVER1 -n mq::mqcreds
ibmint package --input-path C:\Users\LGzel\IBM\ACET12\workspace --output-bar-file C:\temp\OrderProcessing.bar --project OrderProcessing --project R2Policies
ibmint deploy --input-bar-file C:\temp\OrderProcessing.bar --output-host localhost --output-port 7600
```

---

## 10. Método e disciplina

- **Commit por sessão.** Sem commit, a sessão não aconteceu.
- **`docs/log.md`:** uma linha por sessão — data, horas, definition of done, entregue?, o que travou.
- **Definition of done escrita antes de começar**, não depois.
- **Regra dos 45 minutos:** travou 45 min no mesmo erro, registra em `docs/notas/erros.md` e muda de tarefa.
- **Previsão escrita antes de rodar o experimento.** Quando ela erra, o erro vira linha na tabela de premissas corrigidas.
- **Evidência autocontida:**
  - estado inicial comprovado (portão com quatro `CURDEPTH(0)` e `IPPROCS(1)`);
  - marcador de disparo;
  - o mesmo `orderId` em todas as fontes;
  - diff de uma linha isolando a mudança.
- **Evidência de log vem do `events.txt`, nunca da janela.** Colete antes de reiniciar o servidor.
- **Reversão se prova em duas camadas:** `git diff` vazio (arquivo) **e** uma mensagem de erro chegando ao destino certo (runtime).
- **Passo destrutivo testa o `rc`.** Nada de `2>/dev/null` sem checagem.
- **Separar mudança de layout de mudança de lógica** nos commits do `.msgflow`.
- **Vídeo de 90 s por projeto** no README; recrutador não clona repositório.
- **Nada de artefato de empregador** no repositório. Tudo reimplementado do zero.
- **Segredos só no `.env`.** Antes de todo push, `git -C ~/integration-lab grep -n -i "password\|senha\|secret"`.
- **Cópia de segurança:** `git bundle create /mnt/c/Users/LGzel/integration-lab-$(date +%F).bundle --all`.

---

## 11. Decisões em aberto

- [x] ~~Migrar do `ace-projects.zip` para fontes versionados~~ — feito em 22/09 (`f1a3919`)
- [x] ~~Histórico com senha: reescrever ou rotacionar?~~ — rotacionar, para preservar os hashes citados como evidência (24/09)
- [x] ~~Publicar o repositório~~ — `github.com/Eduardozelaya/Integration-Engineering-Bootcamp`, 25/09
- [ ] E-mail público nos commits: manter o Gmail ou usar o `noreply` do GitHub nos próximos
- [ ] Limiar duplicado em três lugares (`BOTHRESH(3)`, `2` no ESQL, `"de 3"` no texto): UDP no flow e comentário ligando ao `queues.mqsc`
- [ ] Invariante do `TratarFalha`: só é seguro com `Transaction mode: Yes`; registrar no ESQL e como regra de revisão (Projeto 5)
- [ ] Limpar o `TEST_SERVER1`: remover do servidor os apps de curso (`Module5`, `Modulo4`, `Modulo8`, `LojaApiV2`); eles continuam no workspace
- [ ] Reorganizar o workspace em `LabMQPolicies` / `LabShared` / `OrderProcessing` (hoje a policy está em `R2Policies`)
- [ ] Mestrado em paralelo? Se sim, manter 4 h/semana e Tier 1 em ~16 semanas
- [ ] Inglês técnico de conversa. Teste: gravar 3 min explicando o Projeto 3 em inglês
- [ ] Certificação **C1000-171** (ACE v12.0). Cobre App Connect Designer e CDK (~6 h a mais). **Agendar a prova antes de se sentir pronto.**

## Situacao dos projetos (06/10)
- Projeto 3: **concluido**. Criterio de pronto atingido em 04/10 (teste final 3x); ambiente reproduzivel provado pelo CI em 05/10; documentacao fechada em 06/10.
- Pendencias do Projeto 3 deslocadas: Frente D (instancias/replicas, ordem, concorrencia da deduplicacao) vai para o Projeto 5; Frente E (pub/sub) apos o P5-1; comparativo WSO2 MI opcional.
- Proximo: Projeto 5 (P5-0: BAR gerado a partir do repositorio, em Linux, sem Toolkit).

## Atualizacao 06/10 — versoes fixadas e decisoes
- MQ servidor: 10.0.0.0 (nivel p1000-L260522), imagem fixada pelo digest sha256:2cb02e79... no compose, no CI e no Terraform.
- MQ cliente no Windows: 9.4.0.26 (cliente 9.4 com servidor 10.0 validado pelo teste final de 04/10).
- authorities.sh reproduz o MQ real: qmgr '+connect +inq +setall'; APP.** '+get +put +inq +browse +passall +setall' (drift corrigido em 05/10, 7a1d785).
- A imagem de desenvolvedor da ao principal 'app' 'get browse put inq' no perfil DEV.**, sem passall: o desvio para a DEADQ falha com 2035 (exp R3a).
- Decisao em aberto (Projeto 11): dar +put +passall na DEV.DEAD.LETTER.QUEUE como defesa em profundidade, alem de exigir BOQNAME em toda fila de entrada (ja barrado no CI).
