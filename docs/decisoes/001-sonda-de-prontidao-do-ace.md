# 001 — Sonda de prontidão do ACE no Kubernetes

**Situação:** implementada e provada em 19/10 (notebook secundário): calibração, troca de versão e o cenário do P5-3b. Evidência: `docs/evidencias/sonda-honesta-ace.txt`.

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

## Revisão (18/10): o usuário da sonda
Pesquisa na fonte da imagem (Dockerfile-server do mq-container e documentação "MQ Advanced for Developers
container image"):
- O htpasswd é um serviço de autorização **exclusivo da imagem de desenvolvedor** (`MQ_CONNAUTH_USE_HTP=true`
  só nela; `false` na imagem de servidor). A documentação descreve apenas os usuários `admin` e `app`.
- `MQ_ADMIN_PASSWORD` e `MQ_APP_PASSWORD` constam como descontinuadas desde o MQ 9.4.0 (senhas montadas por
  Secret). No lab (MQ 10.0, fixado por digest) ainda funcionam: risco registrado para uma troca de imagem.

**Decisão revista:** a sonda usa o `app`, com as 4 permissões medidas (PUT na fila de comandos; GET/BROWSE/INQ
no modelo de resposta; DSP na APP.IN; DSP no queue manager). É um **desvio consciente** do usuário próprio
de monitoração: a imagem de desenvolvedor não oferece um terceiro usuário. Em produção (imagem não-dev,
usuários de LDAP ou do sistema), a sonda teria um usuário só de consulta, como decidido originalmente.
Consequência: o `app`, que lê e grava nas filas, passa a poder consultar o status da APP.IN e do queue manager.

## Observação (19/10, notebook secundário)
O intervalo que a sonda de porta deixa passar apareceu numa máquina mais lenta: o Deployment do ACE ficou
`Available` e, logo em seguida, o MQ mostrava `IPPROCS(0)`; 15 s depois, `IPPROCS(1)`. Sem erro em
nenhum dos dois logs: era só a abertura da fila ainda em andamento. A sonda honesta teria mantido o pod
`NotReady` nesses segundos.
