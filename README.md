# integration-lab

![ci](https://github.com/Eduardozelaya/Integration-Engineering-Bootcamp/actions/workflows/ci.yml/badge.svg)

Laboratório de integração enterprise com **IBM App Connect Enterprise (ACE) 12** e **IBM MQ**, construído do zero para estudo e como portfólio. Cada afirmação deste repositório vem acompanhada de **evidência reproduzível**: configuração versionada, trace do flow, profundidade das filas e log do servidor, todos amarrados pelo mesmo identificador de mensagem.

> **English summary.** Hands-on integration lab with IBM ACE 12 and IBM MQ. Every claim is backed by reproducible evidence (versioned config, flow trace, queue depths, server logs). Current focus: transactional messaging — proving under which conditions a message is retried, dead-lettered, backed out or lost.

---

## O que já está provado

**Projeto 3 — MQ transacional.** O que acontece com uma mensagem quando algo falha?

| Experimento | Configuração | Resultado | Evidência |
|---|---|---|---|
| **C2** | `Transaction mode: Yes`, Catch com retentativa controlada | 3 entregas (BOC 0, 1, 2) e mensagem na DLQ com o erro estruturado | [`exp-c2-*`](docs/evidencias/) |
| **B2** | a mesma lógica, com `Transaction mode: No` | a mensagem **se perde**, e o log ainda anuncia "Retentativa 1 de 3" | [`exp-b2-*`](docs/evidencias/) |
| **E** | o próprio tratamento de erro falha | o rollback desfaz tudo, e o MQ move a mensagem original para a fila de backout | [`exp-e-*`](docs/evidencias/) |

A diferença entre **perder** e **não perder** a mensagem nos experimentos C2 e B2 é **uma linha** no `.msgflow` ([diff](docs/evidencias/exp-b2-diff.txt)).

### Achados medidos, não supostos

- **O MQ reentrega com ~1 s de intervalo fixo**, medido em três experimentos. Não é garantido nem configurável; um backoff real precisa ser implementado no flow.
- **O `BackoutCount` conta rollbacks de *qualquer* programa**, não só do ACE. Uma ferramenta de administração falhando em silêncio levou o BOC de uma mensagem de 0 para 3 ([evidência](docs/evidencias/achado-dmpmqmsg-boc3.txt)).
- **O log de eventos registra o node que falhou, não o código do MQ**, e só registra o texto de retentativa na primeira tentativa. Para contar tentativas, use o trace ou os `BIP2232E`.

Relatório técnico completo (configuração, previsões, evidências e conclusões de cada experimento): [`docs/projeto3-transacional.md`](docs/projeto3-transacional.md). Visão geral do plano: [`docs/projeto3-briefing.md`](docs/projeto3-briefing.md).

---

## Arquitetura

```
 Windows 11                                   WSL2 (Debian 13) + Docker
┌──────────────────────────────┐             ┌──────────────────────────────┐
│ ACE 12.0.12.27 Toolkit       │             │ qm1  IBM MQ  (QM1)           │
│ Integration server           │  CLIENT     │   APP.IN  → APP.OUT          │
│   TEST_SERVER1               │────1414────►│   APP.DLQ  APP.BACKOUT       │
│ MQ Redistributable Client    │  DEV.APP.   │   APP.REPLY  APP.EVENTS      │
│                              │  SVRCONN    │ mock  WireMock               │
└──────────────────────────────┘             └──────────────────────────────┘
```

### Flow `PassThrough`

```
LerPedido (MQInput APP.IN) ──► ProcessarPedido (Compute) ──► GravarSaida (MQOutput APP.OUT)
        │
        └─ Catch ──► RegistrarTentativa (Trace) ──► TratarFalha (Compute) ──► GravarDLQ (MQOutput APP.DLQ)
```

---

## Roteiro

| # | Projeto | Estado |
|---|---|---|
| 3 | **MQ transacional** — backout, DLQ, idempotência, request/reply, pub/sub | parte 1 concluída; idempotência em andamento |
| 1 | Conector S3/R2 com assinatura AWS SigV4 em Java Compute, Shared Library e JUnit | pendente |
| 7 | Observabilidade — logs estruturados, OpenTelemetry, Prometheus/Grafana | pendente |
| 5 | CI/CD — build do BAR sem Toolkit, imagem do ACE, GitHub Actions | pendente |
| 9, 10, 6, 11 | Copybook/DFDL, transação XA com banco, segurança ponta a ponta, TLS no MQ | planejado |
| 4, 2, 8 | Kafka, gateway (WSO2 APIM × IBM API Connect), capstone | planejado |

---

## Como rodar

**Pré-requisitos:** WSL2 com Docker; no Windows, ACE 12 Developer Edition e o MQ Redistributable Client (o ACE não embarca cliente MQ).

```bash
cp .env.example .env          # defina as senhas (mínimo de 8 caracteres)
./scripts/up.sh               # sobe o MQ e o mock, cria as filas e aplica as autorizações
```

No console do ACE:

```
mqsisetdbparms -w <work-dir> -n mq::mqcreds -u app -p <MQ_APP_PASSWORD>
IntegrationServer --work-dir <work-dir>
```

Configuração completa do ambiente, armadilhas conhecidas e comandos de referência: [`ESTADO.md`](ESTADO.md).

---

## Estrutura

```
ace/apps/          fontes dos flows e do ESQL (sincronizados do workspace por scripts/sync-ace.sh)
ace/policies/      policies do ACE (conexão MQ)
mq/config/         queues.mqsc e authorities.sh: fonte da verdade do queue manager
scripts/           up.sh, sync-ace.sh
docs/evidencias/   saídas brutas de cada experimento
docs/              briefing, log de sessões, notas
```

---

## Princípios

- **Previsão escrita antes de rodar.** Quando ela erra, o erro vira conteúdo.
- **Evidência autocontida:** estado inicial comprovado, marcador de disparo, o mesmo identificador em todas as fontes e um diff de uma linha isolando a mudança.
- **Segredos só no `.env`**, fora do git.
- **Nenhum artefato de empregador.** Todo o conteúdo foi construído do zero.
