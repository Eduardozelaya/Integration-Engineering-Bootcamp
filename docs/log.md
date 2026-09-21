# Log de sessoes

| Data | Horas | DoD da sessao | Entregue? | O que travou |
|16/09/2026 |3| Repo criado, MQ de pé com filas de backout/DLQ | Sim | .wslConfig virou pasta; Maven puxou JRE 21 e roubou o alternative do java; MQ real = 286 MiB |
| 18/09/2026 | 4 | ACE conectado ao MQ; flow PassThrough funcionando end-to-end | Sim | 5 erros encadeados: policy nao implantada, libs MQ, ausentes, MQ_INSTALLATION_PATH, autorizacao de objeto, autorizacao de contexto |

## 2026-09-20 — ~2h30
- DoD: provar rollback, incremento de backout, desvio no 3º erro com Transaction mode Yes; contraste com No
- Entregue: sim. Incremento provado por efeito (janela de retenção), não por leitura de BOC — ver achado no doc
- Travou: `duplicate entry` no `ibmint package` (~40 min). Causa: `run/` do TEST_SERVER1 dentro do workspace
- Commits: 5264042 (evidências), 8c97617 (documentação)
