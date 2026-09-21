# ESTADO.md — Laboratório de Integração (IBM ACE + MQ + WSO2)
### Documento de retomada. Última atualização: 19/09/2026

> **Para o assistente que ler isto:** este arquivo é o estado completo do projeto. Não é preciso refazer diagnóstico de ambiente — tudo abaixo está verificado e funcionando. Vá direto para a seção 7 (Próximo passo).

---

## 1. Objetivo

Profissional sênior de integração com base em **WSO2** fazendo transição para o ecossistema **IBM** (App Connect Enterprise, MQ, API Connect), com portfólio público de projetos como evidência. Mercado-alvo: Rio de Janeiro / São Paulo — bancos, seguradoras, consultorias.

Plano original em `plano-integration-engineer.md`; correções e reordenação em `plano-integration-engineer-addendum-v2.md`.

**Cadência assumida:** 4–6 h/semana (Tier 1 em ~16 semanas). Ajustar se a disponibilidade real for outra.

---

## 2. Ambiente — Linux (WSL2)

Infraestrutura roda aqui. Desenvolvimento roda no Windows. A ponte é `localhost:1414`.

| Item | Valor |
|---|---|
| Distro | Debian 13 (trixie), WSL2, kernel 6.18 |
| Usuário | `zelaya` |
| RAM / swap | 4 GiB / 8 GiB (via `C:\Users\LGzel\.wslconfig`) |
| Host | Windows 11, 8 GB RAM total |
| Docker | engine **nativo** no WSL (não Docker Desktop), systemd via `/etc/wsl.conf` |
| Java | Temurin 17, `JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64`, alternatives em modo manual |
| Outros | Maven 3.9.9, git 2.47.3, jq, curl, openssl |
| Repositório | `~/integration-lab` (git, branch `master`, 7 commits) |

### Containers

```
qm1    icr.io/ibm-messaging/mq:latest   portas 1414, 9443   mem_limit 1g   uso real ~286 MiB
mock   wiremock/wiremock:latest         porta 8080          mem_limit 256m  uso real ~82 MiB
```

Subir tudo: `cd ~/integration-lab && ./scripts/up.sh`
Parar preservando dados: `docker compose stop` (**nunca** `down -v`, apaga o volume `mqdata`)

> **Atenção:** `wsl --shutdown` derruba os containers. Depois dele, rodar `./scripts/up.sh` de novo.

### Objetos do MQ (`mq/config/queues.mqsc`, idempotente)

| Objeto | Configuração |
|---|---|
| `APP.IN` | `DEFPSIST(YES) BOTHRESH(3) BOQNAME('APP.BACKOUT') MAXDEPTH(50000)` |
| `APP.OUT` | `DEFPSIST(YES)` |
| `APP.BACKOUT` | `DEFPSIST(YES)` |
| `APP.DLQ` | `DEFPSIST(YES)` |
| `APP.REPLY` | `DEFPSIST(YES)` |
| `APP.EVENTS` | TOPIC, topic string `app/events` |
| `DEV.APP.SVRCONN` | SVRCONN com `MCAUSER('app')` — usa **ALTER**, nunca `DEFINE REPLACE` |

### Autorizações (`mq/config/authorities.sh`)

```bash
setmqaut -m QM1 -t qmgr -p app +connect +inq +setall
setmqaut -m QM1 -n "APP.**" -t queue -p app +put +get +inq +browse +passall +setall
```

Principal `app`, perfil genérico `APP.**` (a imagem de desenvolvedor só autoriza `DEV.**`). Não existe grupo `mqclient` nesta imagem.

### Credenciais (`.env`, fora do Git)

```
MQ_QMGR_NAME=QM1
MQ_ADMIN_PASSWORD=Abcd1234
MQ_APP_PASSWORD=Abcd1234
```

Console web: `https://localhost:9443` — usuário `admin`, senha `Abcd1234`.

---

## 3. Ambiente — Windows

| Item | Valor |
|---|---|
| ACE | **12.0.12.27** Developer Edition, Windows 64 |
| Workspace | `C:\Users\LGzel\IBM\ACET12\workspace` |
| Integration servers | `TEST_SERVER1`, `TEST_SERVER` — **independentes**, sem integration node |
| MQ client | Redistributable 9.4.0.26 em `C:\MQClient` (o ACE **não** embarca cliente MQ) |
| Usuário Windows | `LGzel` (≠ `zelaya`, que é o do Linux) |

### Variáveis de ambiente de usuário (obrigatórias)

```
PATH                  += C:\MQClient\bin64
MQ_INSTALLATION_PATH   = C:\MQClient
MQ_FILE_PATH           = C:\MQClient
```

Sem `MQ_INSTALLATION_PATH` o ACE não carrega as bibliotecas do MQ, mesmo com o PATH correto. O redistributable **não traz `setmqenv`**.

### Abrir o console de comandos do ACE

```
"C:\Program Files\IBM\ACE\12.0.12.27\ace.cmd"
```

Comandos `mqsi*` e `ibmint` **só existem aqui**. Não existem no PowerShell comum nem no WSL.

### Credencial do MQ no servidor

```
mqsisetdbparms -w C:\Users\LGzel\IBM\ACET12\workspace\TEST_SERVER1 -n mq::mqcreds -u app -p Abcd1234
mqsireportdbparms -w C:\Users\LGzel\IBM\ACET12\workspace\TEST_SERVER1 -n mq::mqcreds
```

Sintaxe `-w` porque é servidor independente. Servidor com node usaria `mqsisetdbparms NOMEDONODE ...`.

---

## 4. Artefatos do ACE

### `R2Policies` (Policy Project)
`MQ_LOCAL.policyxml`, tipo **MQEndpoint**:

| Propriedade | Valor |
|---|---|
| Connection | `CLIENT` |
| Queue manager name | `QM1` |
| Queue manager host name | `localhost` |
| Listener port number | `1414` |
| Channel name | `DEV.APP.SVRCONN` |
| Security identity (DSN) | `mqcreds` |
| Use SSL | `false` (TLS é o Projeto 11) |

### `OrderProcessing` (Application)
`PassThrough.msgflow`: `MQInput(APP.IN)` → `Compute` → `MQOutput(APP.OUT)`, ambos os nodes MQ com policy `{R2Policies}:MQ_LOCAL`.
`MQInput`: Message domain `JSON`, **Transaction mode `Yes`**.

`PassThrough_Compute.esql`:
```sql
CREATE COMPUTE MODULE PassThrough_Compute
  CREATE FUNCTION Main() RETURNS BOOLEAN
  BEGIN
    SET OutputRoot = InputRoot;
    SET OutputRoot.JSON.Data.processedBy = 'ACE-LAB';
    SET OutputRoot.JSON.Data.processedAt =
        CAST(CURRENT_TIMESTAMP AS CHARACTER FORMAT 'yyyy-MM-dd''T''HH:mm:ss.SSSZZZ');
    RETURN TRUE;
  END;
END MODULE;
```

Backup versionado em `ace/ace-projects.zip` (Project Interchange).

---

## 5. O que já está provado

1. **Ambiente reprodutível.** `./scripts/up.sh` recria MQ e mock do zero, aplica filas e autorizações, e imprime verificação (`BOTHRESH(3)`, `MCAUSER(app)`).
2. **ACE (Windows) conecta ao MQ (WSL)** em modo CLIENT, autenticado por credencial do vault.
3. **Flow `PassThrough` funciona ponta a ponta.** Mensagem em `APP.IN` sai em `APP.OUT` com `processedBy` e `processedAt`.
4. **Backout funciona.** Numa falha real de autorização, o ACE fez rollback e moveu a mensagem para `APP.BACKOUT`, com o payload original intacto (sem os campos do Compute) — prova de rollback limpo.
5. **Duplicação está demonstrada.** A mesma mensagem enviada duas vezes gerou duas saídas — o "antes" que o Projeto 3 vai corrigir com idempotência.

---

## 6. Erros resolvidos (registro — vale como conteúdo)

Cadeia de cinco obstáculos, cada um mascarando o seguinte. Material de artigo.

| # | Erro | Causa | Solução |
|---|---|---|---|
| 1 | `BIP1361E` | Policy Project é artefato separado da Application e precisa ser implantado também | Incluir `R2Policies` no BAR, ou implantar separado |
| 2 | `BIP2684E` | ACE não embarca cliente MQ; conexão CLIENT exige bibliotecas nativas C | Instalar MQ Redistributable Client em `C:\MQClient` |
| 3 | `BIP2684E` persistindo | PATH acha a DLL, mas o runtime precisa saber a raiz da instalação; o redist não traz `setmqenv` | Definir `MQ_INSTALLATION_PATH` e `MQ_FILE_PATH` |
| 4 | `2035` / `AMQ8077W` no `APP.IN` | Imagem de desenvolvedor só autoriza `DEV.**`; não existe grupo `mqclient` | `setmqaut` no principal `app`, perfil `APP.**` |
| 5 | `2035` no `MQOutput` e `APP.BACKOUT` | `SET OutputRoot = InputRoot` copia o MQMD; gravar com contexto de outra mensagem é permissão separada de `put` | Acrescentar `+passall +setall` |

Outros dois:

- **`DEFINE ... REPLACE` zera atributos não informados.** Nosso mqsc redefiniu `DEV.APP.SVRCONN` e apagou silenciosamente o `MCAUSER('app')` que a imagem já tinha. Usar `ALTER` em objeto pré-existente. Sem erro emitido — o comando "funcionou".
- **`ibmint package --java-version` não existe no 12.0.12.27.** A sintaxe do `ibmint` varia por fix pack. Rodar o comando sem argumentos e ler a ajuda antes de escrever script de pipeline.

Diagnóstico padrão de `2035`: sempre o log do queue manager, nunca a mensagem do Toolkit.
```bash
docker exec qm1 bash -c 'tail -60 /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG'
```

---

## 7. PRÓXIMO PASSO (comece aqui)

### 7.1 Pendência imediata (5 min)

O ESQL foi corrigido com o formato ISO mas **ainda não foi implantado**. Pelo Command Console:

```
ibmint package --input-path C:\Users\LGzel\IBM\ACET12\workspace --output-bar-file C:\temp\OrderProcessing.bar --project OrderProcessing --project R2Policies

tar -tf C:\temp\OrderProcessing.bar

ibmint deploy --input-bar-file C:\temp\OrderProcessing.bar --output-host localhost --output-port 7600
```

(A porta 7600 é a API REST de administração — a mesma que o Toolkit usa, funciona com o servidor no ar.)

Valide mandando `{"orderId":"9","valor":900}` em `APP.IN` e conferindo que `processedAt` saiu como `2026-09-19T...` e não como `TIMESTAMP '...'`.

### 7.2 Sessão 3 — Projeto 3, parte 1 (~2h30)

**Definition of done:** provar que falha no flow causa rollback, que o contador de backout incrementa a cada tentativa, e que na terceira a mensagem vai para `APP.BACKOUT` com `BOC 3`.

**Exercício 1 — falha controlada.** No `PassThrough_Compute.esql`, logo após `SET OutputRoot = InputRoot;`:

```sql
IF InputRoot.JSON.Data.forcarErro = 'true' THEN
    THROW USER EXCEPTION MESSAGE 2951 VALUES('Falha proposital para testar backout');
END IF;
```

Deploy.

**Exercício 2 — o experimento.** Mandar em `APP.IN`:
```json
{"orderId":"3","forcarErro":"true"}
```
Esperar ~10 s (três tentativas), depois:
```bash
docker exec -i qm1 runmqsc QM1 <<'EOF'
DISPLAY QLOCAL(APP.IN) CURDEPTH
DISPLAY QLOCAL(APP.BACKOUT) CURDEPTH
EOF

docker exec qm1 bash -c 'dmpmqmsg -m QM1 -i APP.BACKOUT -f stdout' 2>/dev/null | grep -E "^A BOC|^A MSI"
```
Esperado: `APP.IN(0)`, `APP.BACKOUT(1)`, **`BOC 3`**. Anotar os estados intermediários.

**Exercício 3 — o contraste.** Mudar `MQInput` para `Transaction mode: No`, repetir. A mensagem some: não vai para `APP.OUT`, nem `APP.BACKOUT`, nem DLQ. Perda de mensagem reproduzível, mesma lógica, uma propriedade diferente. **Este par de experimentos é o núcleo do Projeto 3.**

**Exercício 4 — voltar para `Yes`** e documentar os dois resultados em `docs/projeto3-transacional.md`.

### 7.3 Resto do Projeto 3 (sessões seguintes)

- Tratamento de erro estruturado: terminal `Failure` + subflow de erro, log com `correlationId`.
- Roteamento para `APP.DLQ` com motivo, em vez de só backout.
- Idempotência: consumir duplicata sem duplicar efeito (Global Cache agora; tabela no Projeto 10).
- Request/reply usando `APP.REPLY` e `ReplyToQ`.
- Pub/sub com `APP.EVENTS`, assinatura durável vs não-durável.
- **Teste final:** 100 mensagens, 30% forçando erro → `APP.OUT + APP.DLQ = 100`, zero duplicatas, três execuções seguidas.
- Tuning: `Additional instances`, medir throughput, observar perda de ordenação.

---

## 8. Roteiro restante

**Tier 1 — a linha de corte (~80–100 h). A partir daqui, começar a se candidatar.**

| # | Projeto | Estado |
|---|---|---|
| 1 | Conector R2/S3 com SigV4 | pendente — fechar sem expandir |
| 3 | MQ transacional (backout, DLQ, idempotência) | **em andamento** |
| 7 | Observabilidade — versão mínima | pendente |
| 5 | CI/CD e containers — versão mínima | pendente |

**Tier 2 (~+60 h):** 9 (DFDL/copybook — maior lacuna do plano original), 10 (banco + transação coordenada XA), 6 (segurança ponta a ponta), 11 (TLS/CHLAUTH/CONNAUTH no MQ).

**Tier 3:** 4 (Kafka), 2 (gateway), 8 (capstone).

**Restrições conhecidas de memória (host 8 GB):**
- MQ + mock + Postgres + Keycloak: cabem juntos.
- Kafka/Redpanda e WSO2 MI: um de cada vez.
- **DataPower (4 GB+): não roda nesta máquina.** Projeto 2 fica para outra máquina ou VM de nuvem.
- **OpenTelemetry só existe no ACE Linux x86-64.** O Projeto 7 exige ACE em container — antecipa parte do Projeto 5.

---

## 9. Comandos de referência

```bash
# --- WSL ---
cd ~/integration-lab && ./scripts/up.sh      # sobe tudo e aplica filas + autorizações
docker ps --format "table {{.Names}}\t{{.Status}}"
docker stats --no-stream
docker compose stop                          # preserva o volume
docker exec -i qm1 runmqsc QM1 < mq/config/queues.mqsc
docker exec qm1 bash -c 'tail -60 /var/mqm/qmgrs/QM1/errors/AMQERR01.LOG'
docker exec qm1 bash -c 'dmpmqaut -m QM1 -n APP.IN -t queue'
docker exec qm1 bash -c 'dmpmqmsg -m QM1 -i APP.BACKOUT -f stdout' 2>/dev/null | head -30

docker exec -i qm1 runmqsc QM1 <<'EOF'
DISPLAY QLOCAL(APP.IN) CURDEPTH
DISPLAY QLOCAL(APP.OUT) CURDEPTH
DISPLAY QLOCAL(APP.BACKOUT) CURDEPTH
CLEAR QLOCAL(APP.OUT)
EOF
```

```
:: --- Windows (ACE Command Console) ---
"C:\Program Files\IBM\ACE\12.0.12.27\ace.cmd"

mqsireportdbparms -w C:\Users\LGzel\IBM\ACET12\workspace\TEST_SERVER1 -n mq::mqcreds
IntegrationServer --work-dir C:\Users\LGzel\IBM\ACET12\workspace\TEST_SERVER1

ibmint package --input-path C:\Users\LGzel\IBM\ACET12\workspace --output-bar-file C:\temp\OrderProcessing.bar --project OrderProcessing --project R2Policies
ibmint deploy --input-bar-file C:\temp\OrderProcessing.bar --output-host localhost --output-port 7600
```

---

## 10. Método e disciplina

- **Commit por sessão.** Sem commit, a sessão não aconteceu.
- **`docs/log.md`** — uma linha por sessão: data, horas, definition of done, entregue?, o que travou.
- **`docs/notas/erros.md`** — regra dos 45 minutos: travou 45 min no mesmo erro, registra e muda de tarefa.
- **Definition of done escrita antes de começar**, não depois.
- **Vídeo de 90 s por projeto** no README — item de maior retorno por hora do plano; recrutador não clona repositório.
- **Nada de artefato de empregador** no repositório, mesmo sem dados sensíveis. Tudo reimplementado do zero.
- Repositório público desde o início: muda o comportamento de quem escreve.

---

## 11. Decisões em aberto

- [ ] Mestrado em paralelo? (pastas "Mestrado em eng…" e "Artigos para Congre…" no perfil sugerem que sim). Se sim, manter 4 h/semana e Tier 1 em ~16 semanas.
- [ ] Inglês técnico de conversa — para vagas IBM em consultoria/squad internacional, elimina mais candidatos que conhecimento de ACE. Teste: gravar 3 min explicando o Projeto 3 em inglês.
- [ ] Reorganizar workspace do ACE em `LabMQPolicies` / `LabShared` / `OrderProcessing` (hoje a policy está em `R2Policies`, herdado de outro contexto).
- [ ] Migrar de `ace-projects.zip` (Project Interchange) para versionamento dos fontes (`.msgflow`, `.esql`, `.policyxml` são texto) — pré-requisito para diff legível em revisão de código no Projeto 5.
- [ ] Certificação **C1000-171** (ACE v12.0 — mesma versão instalada). Cobre App Connect Designer e CDK, que o plano não estuda: reservar ~6 h. **Agendar a prova antes de se sentir pronto** — é o único mecanismo do plano que cria prazo.
