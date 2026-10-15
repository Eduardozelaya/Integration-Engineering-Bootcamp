# 001 — Sonda de prontidão do ACE no Kubernetes

**Situação:** proposta (14/10). Implementação na próxima sessão.

## Contexto
A readiness atual do ACE (P5-4c) confere a porta 7600, ou seja, o processo. O P5-3b mostrou um ACE com o
processo no ar e os flows "started" que não lia a fila por ~8 min (2085, depois 2035 só no log do MQ).
Para um consumidor de fila, a readiness não controla tráfego (o ACE busca as mensagens no MQ); ela importa
nas decisões do Kubernetes: atualização do Deployment (o pod antigo só sai quando o novo está pronto),
`rollout status`, `kubectl wait` e monitoração.

## Opções
| Opção | Honesta? | Custo |
| --- | --- | --- |
| A. porta 7600 (atual) | não: aprova o ACE parado do P5-3b | nenhum |
| B. status dos flows pela API do ACE | não: os flows dizem "started" sem ler | baixo |
| C. procurar BIP2666E no log do ACE | parcial: pega o 2085, não o 2035 (silencioso no ACE) | baixo |
| D. perguntar ao MQ se há handle de leitura na APP.IN vindo do IP do pod | sim, e por pod | permissão de consulta no MQ |

Conferido em 14/10: o MQ mostra `CONNAME(<IP do pod>)` e `INPUT(SHARED)` por handle; o `APPLTAG` é igual
em todos os pods e não serve. A imagem do ACE tem `runmqsc` no cliente MQ (modo cliente, `-c`).

## Decisão
Opção D, como **readiness** (nunca liveness), com um usuário próprio de consulta (`monitor`), separado do
`app`: o `app` continua só lendo e gravando nas filas `APP.*`. O IP do pod entra pela Downward API
(`status.podIP`). Período de 15 s, para não pesar no MQ.

## Consequências
- Atualizações do Deployment só removem o pod antigo quando o novo está lendo a fila.
- Um MQ fora do ar deixa os pods NotReady, sem reiniciá-los (não é liveness); o ACE se reconecta sozinho (P5-3b).
- Custo: um usuário e permissões de consulta a mais no MQ (dsp; put na fila de comandos; fila de resposta),
  descritos em `authorities.mqsc`. Menor privilégio aprofundado no Projeto 11.
- Dependência nova da sonda: o canal e o listener do MQ (os mesmos que o ACE já usa).

## Achados de 14/10 (antes de implementar)
- A imagem do MQ autentica por arquivo htpasswd (`MQ_CONNAUTH_USE_HTP=true`); `app` nao e usuario do
  sistema operacional. Criar o `monitor` = uma linha a mais no htpasswd (falta descobrir onde a imagem
  gera o arquivo e se aceita um arquivo proprio, montado por Secret), e nao uma imagem derivada.
- `runmqsc -c -u app` a partir do pod do ACE: a conexao e a senha passam; o comando e recusado
  (AMQ8135E). No MQ: AMQ8077W, 'app' sem autoridade na `SYSTEM.ADMIN.COMMAND.QUEUE` (put).
  E a primeira porta de uma cadeia: abrir uma por vez (fila de comandos -> fila de resposta -> dsp na
  APP.IN), lendo cada recusa, para o `monitor` receber so o necessario.
- Efeito colateral positivo: o `app` nao consegue consultar o queue manager; a imagem de desenvolvedor
  nao lhe da mais do que o authorities.mqsc.

## Permissoes minimas da sonda (medidas em 14/10)
Cadeia descoberta com o `app` como cobaia, uma permissao por vez, e desfeita no fim
(evidencia: `docs/evidencias/sonda-permissoes-descobertas.txt`):

| Objeto | Permissao | Recusa aparece em |
| --- | --- | --- |
| `SYSTEM.ADMIN.COMMAND.QUEUE` | PUT | log do MQ (AMQ8077W) |
| `SYSTEM.MQSC.REPLY.QUEUE` (modelo) | GET, BROWSE, INQ | log do MQ (AMQ8077W) |
| `APP.IN` (so ela, nao `APP.**`) | DSP | resposta do comando (AMQ8135E) |
| queue manager | DSP | resposta do comando (AMQ8135E) |

- As recusas do command server (DSP) nao aparecem no log de erros do MQ: so na resposta ao cliente.
- O IP do pod muda quando o pod e recriado (10.244.0.5 -> 10.244.0.3 apos stop/start do no): a sonda
  precisa do IP atual pela Downward API, nunca de um valor fixo.
- `AUTHRMV` deixa o registro vazio ('none'); `DELETE AUTHREC` o apaga. A limpeza usou os dois.
- Falta: como a imagem do MQ permite acrescentar o usuario `monitor` (autenticacao por htpasswd,
  `MQ_CONNAUTH_USE_HTP=true`, mas o arquivo nao e visivel no container). Consultar a documentacao da imagem.
