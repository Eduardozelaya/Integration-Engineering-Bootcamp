# Log de sessoes

| Data | Horas | DoD da sessao | Entregue? | O que travou |
|16/09/2026 |3| Repo criado, MQ de pé com filas de backout/DLQ | Sim | .wslConfig virou pasta; Maven puxou JRE 21 e roubou o alternative do java; MQ real = 286 MiB |
| 18/09/2026 | 4 | ACE conectado ao MQ; flow PassThrough funcionando end-to-end | Sim | 5 erros encadeados: policy nao implantada, libs MQ, ausentes, MQ_INSTALLATION_PATH, autorizacao de objeto, autorizacao de contexto |

## 2026-09-20 — ~2h30
- DoD: provar rollback, incremento de backout, desvio no 3º erro com Transaction mode Yes; contraste com No
- Entregue: sim. Incremento provado por efeito (janela de retenção), não por leitura de BOC — ver achado no doc
- Travou: `duplicate entry` no `ibmint package` (~40 min). Causa: `run/` do TEST_SERVER1 dentro do workspace
- Commits: 5264042 (evidências), 8c97617 (documentação)
23/09 — DoD: caminho feliz ok; B2 commitado; Exp E com 4 evidências e diff vazio após reverter; ESTADO.md atualizado.
23/09 — ~3h — DoD: caminho feliz pos-reversao; B2 commitado; Exp E com 4 evidencias e diff vazio apos reverter; ESTADO.md atualizado — Entregue: parcial (E completo e runtime revertido provado com orderId 24/25; docs e ESTADO.md ficam para a proxima sessao) — Travou: dmpmqmsg -f /dev/null abortava sem tty (rc=71) e fazia rollback, entao o zerar nunca tinha funcionado (BOC da residual subiu 0->3); previsao "2085 no log" errada (log mostra BIP2232E no GravarDLQ + BIP2648E); log de eventos em UTC e CP1252, com rotacao a cada start.
24/09 — DoD: repositório publicado sem segredos; briefing e ESTADO.md commitados.
24-25/09 — ESTADO.md reescrito sem senhas (76d5ea2); varredura de segredos: so ESTADO.md tinha a senha, .env nunca commitado, .env.example e docker-compose ja parametrizados; opcao b escolhida (rotacionar em vez de reescrever historico, para preservar hashes citados como evidencia); senhas trocadas por aleatorias (openssl rand -hex 8, admin e app diferentes), container recriado e mqsisetdbparms atualizado; validado com orderId 27. Travou: git grep rodado de docs/ buscou so a subpasta; cp pegou ESTADO.md antigo da pasta Downloads; primeira senha nova continha a antiga como prefixo.
