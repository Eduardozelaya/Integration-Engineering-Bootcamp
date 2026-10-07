# integration-lab

![ci](https://github.com/Eduardozelaya/Integration-Engineering-Bootcamp/actions/workflows/ci.yml/badge.svg)

Laboratório de integração enterprise com **IBM App Connect Enterprise 12** e **IBM MQ 10**, construído do zero. **Resultado principal:** em 3 execuções de 110 mensagens, misturando pedidos válidos, falhas transitórias, mensagens inválidas e duplicatas, **nenhuma mensagem se perdeu e nenhum pedido foi processado duas vezes**. Cada afirmação tem evidência versionada: previsão escrita antes de rodar, trace do flow, profundidade das filas e log do servidor.

> **English summary.** Hands-on integration lab with IBM ACE 12 and IBM MQ 10, built from scratch. Main result: across 3 runs of 110 mixed messages (valid orders, transient failures, invalid payloads, duplicates), no message was lost and no order was processed twice. Every claim is backed by versioned evidence. A GitHub Actions pipeline rebuilds the MQ environment from the repository on every push and enforces the lessons as checks.

---

## Destaques

| | Resultado | Evidência |
|---|---|---|
| **Teste final** | 3 × 110 mensagens, 9 de 9 conferências em todas: OUT 70, DLQ 30, DUP 10, BACKOUT 0, zero duplicatas | [`teste-final.sh`](scripts/teste-final.sh), [`teste-final/`](docs/evidencias/teste-final/) |
| **Queda do consumidor** | processo encerrado à força no meio de uma retentativa; a mensagem voltou à fila com o contador de tentativas preservado | [`exp-f`](docs/evidencias/exp-f-queda-do-consumidor.txt) |
| **Transação** | com `Transaction mode: Yes`, a falha vira retentativa e DLQ com motivo; com `No`, a mesma lógica **perde** a mensagem. A diferença é uma linha | [`exp-c2-*`, `exp-b2-*`, `exp-e-*`](docs/evidencias/), [diff](docs/evidencias/exp-b2-diff.txt) |
| **Classificação de erros** | erro permanente vai à DLQ em 1 passagem; transitório ganha 3; os bytes originais chegam até de mensagens ilegíveis | [`exp-b1`](docs/evidencias/exp-b1-classificacao-de-erros.txt), [`exp-b1c`](docs/evidencias/exp-b1c-bytes-originais.txt) |
| **Erro em serviço síncrono** | o caminho de erro responde em 133 ms, guarda o original e registra; sem isso, a falha some do log | [`exp-r3c`](docs/evidencias/exp-r3c-erro-guardado-e-registrado.txt) |
| **Request/reply** | sem filtro pelo `CorrelId`, um cliente recebe a resposta de outro; com filtro, só a sua | [`exp-r2`](docs/evidencias/exp-r2-expiry-resposta-orfa.txt), [`exp-r1b`](docs/evidencias/exp-r1b-requisitante-com-filtro.txt) |
| **Idempotência** | chave de negócio (`orderId`), marca desfeita no Catch, e os limites medidos: redeploy apaga a memória | [`projeto3-idempotencia.md`](docs/projeto3-idempotencia.md) |
| **CI e drift** | a cada push, o MQ sobe do zero só com o repositório; ao ser montado, o CI encontrou uma permissão aplicada à mão que nunca tinha entrado no código | [`ci.yml`](.github/workflows/ci.yml), [`vaga-devops.md`](docs/vaga-devops.md) |

Relatório técnico completo: [`docs/projeto3-transacional.md`](docs/projeto3-transacional.md) · Perguntas de entrevista com evidência: [`docs/entrevista.md`](docs/entrevista.md)

### Achados medidos, não supostos

- **Cada mensagem leva ~1 s neste ambiente, com ou sem rollback** (teste final), enquanto o MQ sozinho faz ~3–4 ms por mensagem ([D-T0](docs/evidencias/exp-d-t0-linha-de-base-mq.txt)). O disco foi descartado; o gargalo está entre o ACE e o MQ, em investigação.
- **O `BackoutCount` conta rollbacks de *qualquer* programa**, não só do ACE. Uma ferramenta de administração falhando em silêncio levou o BOC de uma mensagem de 0 para 3 ([evidência](docs/evidencias/achado-dmpmqmsg-boc3.txt)).
- **Tratar um erro pode escondê-lo:** um Catch que responde e termina normalmente faz o commit, e o log do servidor não registra nada ([exp-r3b](docs/evidencias/exp-r3b-servico-responde-erro.txt)).
- **`BOTHRESH(0)` não é "sem limite":** o MQ desvia já na 2ª entrega, e sem permissão na DEADQ a mensagem entra em laço, com uma única linha no log ([exp-r3a](docs/evidencias/exp-r3a-servico-falha-sem-tratamento.txt)).

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
| 3 | **MQ transacional** — backout, DLQ, idempotência, request/reply, pub/sub | **concluído** (teste final 3×); tuning e pub/sub seguem com o Projeto 5 |
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

## Pipeline e infraestrutura como codigo

| O que | Onde | O que prova |
|---|---|---|
| CI no GitHub Actions | `.github/workflows/ci.yml` | a cada push, o IBM MQ sobe do zero so com o que esta no repositorio; regras viram verificacoes (fila de entrada sem `BOTHRESH(3)` ou `app` sem `passall` = vermelho) |
| Segredos | job `gitleaks` no CI + `.gitleaksignore` revisado | o historico inteiro e varrido a cada push; o unico achado (um marcador do `.env.example`) esta documentado |
| Versoes fixadas | CI, compose e Terraform | o MQ 10.0.0.0 pelo mesmo digest nos tres lugares; `ubuntu-24.04`; `checkout@v5`; `gitleaks` 8.30.1 |
| Terraform (provider Docker) | `infra/local/main.tf` | plan salvo e aplicado, estado fora do git, senhas como `sensitive`, `plan` limpo apos o `apply` |
| Linha de base do MQ | `docs/evidencias/exp-d-t0-linha-de-base-mq.txt` | ~3-4 ms por mensagem no WSL2, ~1-2 ms no runner do GitHub |

Detalhes e o que cada passo prova para operacao: `docs/vaga-devops.md`.
