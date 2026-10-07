# Preparação para entrevista — perguntas, correções e respostas

> Material de revisão. Cada resposta traz a **primeira versão** (escrita sem consulta), a **análise** do que estava errado ou faltando, a **versão revisada** e a **evidência** no repositório que sustenta cada afirmação.
> Regra: responder com as próprias palavras. A versão revisada é referência, não texto para decorar.

---

## 1. "Como você evita processar duas vezes?"

**Estrutura esperada**
- Diferenciar rollback/reentrega de duplicidade de negócio.
- Explicar a chave de idempotência e onde ela é persistida.
- Mostrar o comportamento para o mesmo `MsgId`.
- Citar o limite: a idempotência precisa proteger o efeito colateral, não apenas o consumo da fila.

### Primeira versão

> Para evitar o reprocessamento de uma mensagem é necessário um mecanismo de identificação de que este é o primeiro e único momento de processamento dessa mensagem. Realizamos essa análise com uma lógica que identifica cada mensagem da fila que é processada com uma chave dela e que a marca nesse processo. Essa chave de identificação fica na sessão da mensageria. O `MsgId` pode trazer mensagens iguais n vezes, mas com seu valor diferente; no caso, ali não se trata do valor da mensagem, mas em si de sua execução. Rollback se trata de uma forma de retornar ao ponto em que o sistema estava íntegro.

### Análise

**Certo:** uma chave identifica o que já foi processado e é marcada durante o processamento; o `MsgId` muda mesmo quando o conteúdo é o mesmo.

| Trecho | Problema | Correção |
|---|---|---|
| "identifica cada **mensagem** da fila" | a chave não identifica a mensagem | identifica o **pedido**: `orderId`, chave de negócio |
| "a chave fica na **sessão da mensageria**" | **errado**: o MQ não guarda a marca | a marca fica na **memória do integration server** (`SHARED ROW`), **fora do MQ e fora da transação** |
| "o `MsgId` pode trazer mensagens iguais n vezes com valor diferente" | ideia certa, formulação confusa | "o reenvio do produtor gera `MsgId` novo para o mesmo pedido; por isso o `MsgId` não serve de chave" (D0) |
| "rollback é retornar ao ponto íntegro" | definição correta, mas não responde à pergunta | falta dizer **por que a reentrega após rollback não é duplicata** |
| — | **faltou** o comportamento com o mesmo `MsgId` | a reentrega vem com o mesmo `MsgId` e `BackoutCount` maior; **deve** ser reprocessada, porque o rollback desfez o efeito. Só funciona porque o Catch **desmarca** o pedido antes do rollback (D2a → D2b) |
| — | **faltou** o limite | a idempotência protege o **efeito**, não a fila (ver abaixo) |

**O ponto mais valioso, e o follow-up mais comum: "e se o flow chamar uma API?"**
No laboratório, todos os efeitos do flow são gravações em fila na mesma unidade de trabalho, então o rollback desfaz tudo. Se o flow chamar uma **API REST** de pagamento antes de falhar, o rollback desfaz as filas, mas **não desfaz a chamada HTTP**. A reentrega, com o **mesmo** `MsgId` e sem nenhum reenvio do produtor, chamaria a API de novo: **pagamento duplicado**. A chave precisa chegar até o efeito colateral: enviar o `orderId` como cabeçalho `Idempotency-Key` para a API, ou gravar a marca na mesma transação do efeito (XA, Projeto 10).

### Versão revisada (≈ 60 s)

> Separo dois casos. Quando o flow falha e há rollback, o MQ reentrega a mesma mensagem, com o mesmo `MsgId`. Isso não é duplicata, porque o rollback desfez o efeito, e ela deve ser reprocessada. A duplicata que causa dano é o produtor reenviando o mesmo pedido: aí o `MsgId` é novo, então a chave de idempotência tem que ser de negócio, o `orderId`.
>
> No meu laboratório, marco o pedido na memória do integration server como último passo do processamento. Uma duplicata vai intacta para uma fila de auditoria, e não é descartada. Se o processamento falha depois da marca, o tratamento de erro desfaz a marca; senão, a reentrega seria confundida com duplicata. Eu provei esse defeito e a correção.
>
> O limite é que a marca não participa da transação: um redeploy apaga tudo, e se o flow tiver um efeito fora da transação, como uma chamada HTTP, o rollback não o desfaz. Para esses casos, a chave tem que ir até o sistema de destino, ou a marca precisa estar no banco, sob a mesma transação XA.

### Evidência

| Afirmação | Onde |
|---|---|
| reenvio do produtor gera `MsgId` novo | `docs/evidencias/exp-d0-duplicata.txt` |
| deduplicação por `orderId`, duplicata intacta na `APP.DUP` | `docs/evidencias/exp-d1-deduplicacao.txt` |
| sem desmarcar, pedido legítimo vira duplicata | `docs/evidencias/exp-d2a-falha-apos-marca.txt` |
| com desmarcar, 3 tentativas e reenvio processado | `docs/evidencias/exp-d2b-desmarcar-no-catch.txt` |
| redeploy apaga as marcas | `docs/evidencias/exp-d3-redeploy-apaga-marcas.txt` |
| desenho completo | `docs/projeto3-idempotencia.md` |

---

## 2. "O que acontece se o consumidor cair no meio de uma mensagem?"

**Estrutura esperada**
- O que acontece com a unidade de trabalho e com o `MQGET`?
- Como o rollback afeta a mensagem e o `BackoutCount`?
- Em que momento a mensagem vai para `APP.BACKOUT` / DLQ?
- Como provar o comportamento em um teste?

### Primeira versão

> Se um consumidor cair, então a mensagem vai prontamente para uma fila de DLQ.

### Análise

**Errado, e é um erro importante:** a mensagem **não** vai direto para a DLQ. É exatamente o comportamento que os experimentos A e C2 mostram.

| Momento | O que acontece |
|---|---|
| 1. `MQGET` sob syncpoint | a mensagem **não sai** da fila; fica reservada para o consumidor (retenção de ~2,5 s no experimento A) |
| 2. o consumidor cai | a conexão com o queue manager se rompe |
| 3. rollback **implícito** | o **queue manager** desfaz a unidade de trabalho por conta própria |
| 4. a mensagem volta | disponível de novo em `APP.IN`, **com o `BackoutCount` incrementado** |
| 5. reentrega | quando o consumidor volta, ou outro assume, recebe a mesma mensagem |
| 6. só após `BOTHRESH` tentativas | o MQInput move a mensagem para a `APP.BACKOUT` |

**E a `APP.DLQ`?** Quem grava nela é o **flow**, pelo Catch, diante de um **erro de processamento**. Numa queda, o processo morreu, e o Catch **não executa**. Uma queda **nunca** leva a mensagem direto para a `APP.DLQ`.

**E com `Transaction mode: No`?** O `MQGET` já confirmou a remoção, e a queda **perde** a mensagem (experimentos B e B2).

### Versão revisada (≈ 45 s)

> Depende do modo transacional. Com syncpoint, o `MQGET` não remove a mensagem; ela fica reservada. Se o consumidor cai, a conexão se rompe e o próprio queue manager faz o rollback: a mensagem volta para a fila de entrada com o `BackoutCount` incrementado e é reentregue quando o consumidor volta. Ela só vai para a fila de backout depois de atingir o `BOTHRESH`. Não vai para a DLQ da aplicação, porque quem grava lá é o tratamento de erro do flow, e numa queda ele nem executa. Sem syncpoint, a leitura já confirmou a remoção, e a queda perde a mensagem. Medi os dois casos no laboratório: com transação, a mensagem ficou retida e foi para a backout depois de três tentativas; sem transação, sumiu sem rastro.

### Evidência

| Afirmação | Onde |
|---|---|
| retenção sob syncpoint e desvio para a backout | `docs/evidencias/exp-a-transacao-yes.txt` |
| sem syncpoint, a mensagem se perde | `docs/evidencias/exp-b-transacao-no.txt`, `exp-b2-*` |
| retentativa e DLQ com motivo pelo Catch | `docs/evidencias/exp-c2-*` |
| queda real do consumidor: mensagem e `BackoutCount` preservados através da queda; DLQ só após a 3ª tentativa contada desde antes da queda | `docs/evidencias/exp-f-queda-do-consumidor.txt` |

**Lacuna restante:** no exp F, a queda ocorreu 355 ms após a 2ª entrega, provavelmente com a transação já encerrada. Ele prova que a mensagem e o contador sobrevivem à queda, mas não distingue um rollback implícito de uma transação aberta. Pendente: F2 (capturar `UNCOM` no instante da queda).

---

## 3. Num request/reply, como o requisitante encontra a sua resposta?

O servico copia o `MsgId` da pergunta para o `CorrelId` da resposta (R1). Mas quem garante a correlacao e o requisitante: ele tem de ler a fila de respostas filtrando pelo proprio `CorrelId`. No R2, um requisitante sem filtro recebeu a resposta de outro pedido; no R1b, com filtro, recebeu so a sua e ignorou a isca. A resposta tambem precisa de `Expiry`, senao uma resposta sem leitor fica na fila para sempre.

## 4. Um erro tratado pode desaparecer?

Pode. No R3b, o Catch respondia ao requisitante com o motivo, e o flow terminava normalmente: commit, a requisicao era consumida, e o log do servidor nao registrava nada. Um servico falhando em 100% das consultas mostraria zero erros. A correcao (R3c) foi o caminho de erro responder, guardar o original numa fila de auditoria e registrar num trace, na mesma unidade de trabalho.

## 5. Todo erro merece retentativa?

Nao. Retentar um JSON invalido gasta tempo e esconde o problema. No B1, o tratamento passou a classificar pelo codigo do erro: parser (5700-5799) e validacao de negocio (2952) sao permanentes e vao para a DLQ na 1a passagem; o resto e transitorio e ganha 3 tentativas. A DLQ registra o tipo, e quem opera sabe se deve reprocessar ou falar com quem enviou.

## 6. BOTHRESH(0) e seguro?

Nao, e o motivo nao e o obvio. Com `BOTHRESH(0)`, o MQ desvia ja na 2a entrega; sem `BOQNAME`, vai para a DEADQ. No R3a, o desvio foi recusado por falta de `+passall` na DEADQ, e a mensagem entrou em laco: uma por segundo, com 1 linha no log do ACE e 21 recusas no log do queue manager. Hoje o CI barra qualquer fila de entrada sem `BOTHRESH(3)` e `BOQNAME`.

## 7. Como voce sabe que o seu ambiente e reproduzivel?

Porque um pipeline o recria do zero a cada commit. Ao montar o CI, ele mostrou que o meu nao era: uma permissao (`+passall`) tinha sido aplicada a mao e nunca entrou no codigo. Um ambiente novo falharia com `2035` no primeiro pedido. Corrigi, e o pipeline passou a conferir essa permissao.

## 8. Como voce investiga um problema de desempenho?

Separando as camadas. O teste final mostrou ~1 s por mensagem. Medi o MQ sozinho, sem o ACE, no lab e num runner do GitHub: 3-4 ms e 1-2 ms por mensagem. O disco ficou descartado como causa, e a investigacao foi para a camada entre o ACE e o MQ.

## 9. Perguntas a preparar

- "Qual a diferenca entre fila de backout e DLQ?" — `docs/projeto3-transacional.md`, secoes 9 e 20
- "Sua solucao e *exactly-once*?" — `docs/projeto3-idempotencia.md`, secao 6 (janelas residuais)
- "Por que `+passall` e uma permissao separada de `+put`?" — `docs/projeto3-idempotencia.md`, secao 3; o drift de 05/10 (`7a1d785`)
- "Como voce investiga uma mensagem que sumiu?" — laco de filas, trace, `events.txt` em UTC, `AMQERR01.LOG`, `amqsbcg`
