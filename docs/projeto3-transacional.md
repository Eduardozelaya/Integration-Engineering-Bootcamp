# Projeto 3 — Transacionalidade no MQ: rollback, backout e perda silenciosa

**Data:** 20/09/2026
**Ambiente:** IBM ACE 12.0.12.27 (Windows) + IBM MQ Advanced for Developers (container, WSL2)
**Flow:** `OrderProcessing/PassThrough` — `MQInput(APP.IN)` → `Compute` → `MQOutput(APP.OUT)`

## Pergunta

Duas execuções idênticas — mesma mensagem, mesma lógica, mesma infraestrutura — separadas por uma única propriedade booleana no node de entrada. O que muda?

A resposta é a diferença entre garantia de entrega e perda silenciosa de dados.

## 1. Configuração

| Objeto | Configuração relevante |
|---|---|
| `APP.IN` | `DEFPSIST(YES) BOTHRESH(3) BOQNAME('APP.BACKOUT') MAXDEPTH(50000)` |
| `APP.OUT` | `DEFPSIST(YES)` |
| `APP.BACKOUT` | `DEFPSIST(YES)` — `MAXDEPTH` padrão (5000) |
| `APP.DLQ` | `DEFPSIST(YES)` |
| `DEV.APP.SVRCONN` | SVRCONN com `MCAUSER('app')` |

Autorizações do principal `app` sobre `APP.**`: `+put +get +inq +browse +passall +setall`

### Falha controlada no ESQL

Três decisões deliberadas:

- **`COALESCE`** — em ESQL, comparar `NULL` com um literal resulta em `UNKNOWN`, não em `FALSE`. Sem ele, o caminho feliz passaria por acidente.
- **`THROW` antes dos `SET`** — garante que a mensagem desviada carregue o payload original, sem os campos do Compute.
- **`CURRENT_GMTTIMESTAMP`** — carimbo em UTC, para correlacionar com log de container sem conversão de fuso.

### Caminho feliz (controle)

Entrada `{"orderId":"9","valor":900}` → saída com `processedAt: 2026-09-21T01:00:26.463+00:00`.
Confirma que o `COALESCE` funciona e que o carimbo UTC está correto (22:00 local = 01:00 UTC do dia seguinte).

## 2. Experimento A — `Transaction mode: Yes`

Evidência: `docs/evidencias/exp-a-transacao-yes.txt`

| Horário | `APP.IN` | `APP.BACKOUT` | |
|---|---|---|---|
| 22:25:37.4 | 0 | 2 | antes do put |
| 22:25:38.0 | **1** | 2 | mensagem retida |
| 22:25:38.6 | **1** | 2 | |
| 22:25:39.3 | **1** | 2 | |
| 22:25:39.9 | **1** | 2 | |
| 22:25:40.5 | **1** | 2 | |
| 22:25:41.6 | 0 | **3** | desviada |

**Retenção: ~2,5 segundos, cinco amostras consecutivas.**

Durante esse intervalo a mensagem permaneceu visível em `APP.IN` enquanto o ACE a lia, falhava e revertia. É a assinatura visual do syncpoint: sob transação, o `MQGET` não remove a mensagem. Repetido com `orderId=4` às 22:18, mesma duração — reprodutível.

### Mensagem em `APP.BACKOUT`

| Campo | Valor |
|---|---|
| Dados do aplicativo | `{"orderId":"3","forcarErro":"true"}` |
| Modo de entrega | Persistente |
| Registro de data e hora | 22:10:58 — **instante do put original** |
| ID do aplicativo | `amqsput` — **produtor original** |
| Contagem de backout | **0** |

O payload chegou sem `processedBy` e `processedAt`: rollback limpo, verificado pelo conteúdo.

O timestamp e o ID do aplicativo preservam o contexto da mensagem original, embora quem gravou tenha sido o ACE. É o efeito prático de `+passall +setall` — sem elas, a gravação falharia com `2035`.

## 3. Experimento B — `Transaction mode: No`

Única alteração: a propriedade `Transaction mode` do `MQInput`.
Evidência: `docs/evidencias/exp-b-transacao-no.txt`

| Horário | `APP.IN` | `APP.BACKOUT` | |
|---|---|---|---|
| 22:38:34.7 | 0 | 3 | antes do put |
| — | | | **`>>> PUT orderId=7`** |
| 22:38:35.5 | 0 | 3 | |
| … 25 amostras … | 0 | 3 | |
| 22:38:50.4 | 0 | 3 | 15 s depois |

**A mensagem nunca apareceu em `APP.IN`.**

Sem syncpoint, o `MQGET` commita no mesmo instante da leitura; quando o `THROW` dispara, já não há o que reverter. Verificação por exclusão: `APP.IN(0)`, `APP.OUT(0)`, `APP.BACKOUT(3)` inalterado, `APP.DLQ(0)`.

Nenhum erro emitido. Nenhum alerta. Nenhum rastro.

## 4. Conclusão

| | `Yes` | `No` |
|---|---|---|
| Visível em `APP.IN` durante a falha | sim, ~2,5 s | não |
| Retentativas | 3 (`BOTHRESH`) | 0 |
| Destino final | `APP.BACKOUT` | **nenhum** |
| Payload recuperável | sim, íntegro | não |
| Erro visível ao operador | sim | **não** |

Mesma lógica, mesma mensagem, mesma infraestrutura. Uma propriedade booleana separa garantia de entrega de perda silenciosa.

O agravante não é a perda — é o silêncio. Uma fila que estoura `MAXDEPTH` grita. Uma mensagem que sai de `APP.IN` sem syncpoint e morre num `THROW` não deixa vestígio. O sintoma em produção é "o pedido sumiu", sem nada nos logs de fila para investigar.

## 5. Achados colaterais

### `BackoutCount` em `APP.BACKOUT` é sempre 0

Esperava-se `BOC 3`. O console mostrou **0**, e 0 é o valor correto.

O `BackoutCount` é atributo da mensagem *na fila de onde está sendo lida*, incrementado a cada `MQGET` sob syncpoint seguido de rollback. Ao atingir o threshold, a mensagem é gravada na `BOQNAME` — e um `MQPUT` cria mensagem nova, com contador zerado.

`BOC 3` só existe enquanto a mensagem está em `APP.IN`, durante a terceira tentativa. A contagem de tentativas **não é auditável pela fila de backout**; a evidência são o log do integration server e a janela de retenção capturada ao vivo.

### `MQInput` não tem mecanismo de retentativa próprio

O node não expõe aba *Retry* no ACE 12. A política de retentativa é inteiramente da fila, via `BOTHRESH` e `BOQNAME`.

Contraste direto com o WSO2 MI, onde `max.delivery.attempts` é propriedade do *message processor* — do runtime, não do broker. No par ACE + MQ, transação e retentativa são configuração externa ao flow: a transação no node de entrada, a retentativa na fila.

### A transacionalidade é decidida no node de entrada

O `Compute` está com `Transaction: Automatic`, que herda a unidade de trabalho já aberta. Quem define o comportamento transacional do flow é o `MQInput`.

### `CLEAR QLOCAL` falha com a fila em uso

`AMQ8148E: IBM MQ object in use` — o comando é recusado enquanto houver handle aberto. O ACE mantém as filas do flow abertas durante todo o tempo em que a aplicação está implantada, então `APP.BACKOUT` está em uso mesmo sem tráfego.

Consequência: `CLEAR` e `DEFINE ... REPLACE` sobre filas do flow só funcionam com a aplicação parada. O `up.sh` falhará se o lab for reiniciado com o ACE conectado e mensagens nas filas. Contorno no lab: esvaziar com `amqsget`.

## 6. Erros de ferramenta resolvidos nesta sessão

| Erro | Causa | Solução |
|---|---|---|
| `duplicate entry: R2Policies\MQ_LOCAL.policyxml` | `TEST_SERVER1` fica **dentro** do workspace; seu `run/` contém cópia implantada de cada projeto. O `--input-path` no workspace inteiro encontra as duas e colide ao gravar o zip | `--input-path` deve apontar para diretório contendo **apenas fontes** |
| Policy ausente do BAR da aplicação | A referência `{R2Policies}:MQ_LOCAL` **não** arrasta o artefato no empacotamento | Dois BARs separados; implantar a policy **antes** da aplicação, senão `BIP1361E` |

O segundo ponto é a resposta para *"como promover de dev para prod sem alterar o BAR?"* — policy e aplicação têm ciclos de vida distintos.

### Nota de método

| Hipótese | Teste que a derrubou |
|---|---|
| Dois `--project` colidindo | `--project R2Policies` sozinho duplicou igual |
| Cópia duplicada dentro do projeto | `dir /s` mostrou 3 arquivos, estrutura correta |
| **`run/` do TEST_SERVER1 no workspace** | `--input-path` no diretório do projeto → sucesso |

O que funcionou foi reduzir o comando ao mínimo antes de teorizar sobre interação entre partes. `BIP8081E` é genérica e comporta várias explicações plausíveis; só o caso isolado distingue entre elas.

## 7. Próximos passos

- [ ] Mover os work dirs (`TEST_SERVER1`, `TEST_SERVER`) para fora do workspace
- [ ] `BackoutHandler`: `MQInput(APP.BACKOUT)` → enriquecer com `ExceptionList` → `MQOutput(APP.DLQ)`
- [ ] Idempotência: consumir duplicata sem duplicar efeito
- [ ] Request/reply com `APP.REPLY` e `ReplyToQ`
- [ ] Pub/sub em `APP.EVENTS`, durável vs. não-durável
- [ ] Teste final: 100 mensagens, 30% com erro → `APP.OUT + APP.DLQ = 100`, zero duplicatas, três execuções
