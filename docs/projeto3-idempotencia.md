# Projeto 3, parte 2 — Idempotência

## 1. Decisões
- Chave: `orderId` (identificador de negócio), não `MsgId`.
- Armazenamento: `SHARED ROW` do ESQL. Mesmas propriedades transacionais do Global Cache (nenhuma), sem custo de infraestrutura; o Global Cache está desligado no servidor (`cacheOn` comentado). Fica como variação para mais de um servidor.
- Destino da duplicata: fila de auditoria `APP.DUP` (nenhuma mensagem some sem rastro em fila). Critério do teste final: `OUT + DLQ + DUP = total`.
- Marca: último passo do `ProcessarPedido`. O Catch desmarca **somente** se esta mensagem marcou (flag no `Environment`).

## 2. Experimentos
| Exp. | Previsão | Resultado |
|---|---|---|
| D0 — linha de base | 2 saídas para o mesmo orderId | OUT 2; MsgId diferentes (`exp-d0-duplicata.txt`) |
| D1 — deduplicação | OUT 1, DUP 1 | OUT 1 (99 bytes, processado), DUP 1 (29 bytes, original intacto); MsgId diferentes (`exp-d1-deduplicacao.txt`) |
| D2a — falha após a marca, sem desmarcar | DUP 1, OUT 0, DLQ 0 (pedido legítimo perdido como duplicata) | DUP 1, OUT 0, DLQ 0; trace 1 linha (BOC 0); log termina em "Retentativa 1 de 3" e a 2ª entrega não deixa rastro (`exp-d2a-falha-apos-marca.txt`) |
| D2b — com desmarcar condicionado | DLQ 1 com motivo, DUP 0 | trace 3 linhas; DLQ 1 com motivo (tentativas 3), DUP 0; reenvio sem gatilho processado (OUT 1) (`exp-d2b-desmarcar-no-catch.txt`) |
| D3 — redeploy do flow | OUT 2 (memória perdida) | antes do redeploy: OUT 1, DUP 1 (controle); redeploy 02:49:46 (BIP2269I); depois: OUT 2 — a duplicata passou (`exp-d3-redeploy-apaga-marcas.txt`) |

## 3. Dívida de design e achados
- **`APP.DUP` com `MAXDEPTH` padrão (5000).** Um produtor em laço enche a fila; o `GravarDuplicata` falha com `2053` (fila cheia), há rollback, e as duplicatas passam a ir para a `APP.BACKOUT` — a cadeia do exp E, por outra causa. Opções: `MAXDEPTH(50000)` como a `APP.IN`; alerta de profundidade (Projeto 7).
- **O `+passall` registra o usuário de origem.** Na `APP.DUP`, o ID do usuário é `mqm` (quem rodou o `amqsput`), não `app` (quem o ACE usa para conectar). Útil para auditoria; é também o motivo de o MQ separar `passall` de `put` (Projetos 6 e 11).
- **A 2ª entrega do D2a não deixa rastro no log.** Ela não passa pelo Catch (sem trace) e não gera erro (sem log). Só a fila de auditoria prova que ela existiu, o que justifica a opção B com evidência.
- **A marca não expira.** Sem TTL, a memória cresce enquanto o servidor estiver no ar.
- **Um deploy de qualquer flow da application apaga as marcas.** O deploy do `ConsultarPedido` (request/reply) reiniciou também o `PassThrough`, que está na mesma application `OrderProcessing`. A janela do D3 abre mesmo quando o flow com a deduplicação não mudou.

---

## 4. Qual duplicata e evitada

O **reenvio do produtor**: o mesmo pedido (`orderId`) enviado de novo, como uma mensagem nova, com outro `MsgId` (exp D0). Por isso a chave e o `orderId`, de negocio, e nao o `MsgId`, que muda a cada envio.

Nao e o caso da **reentrega do MQ apos um rollback**: ai e a mesma mensagem voltando, e quem a trata e a transacao, nao a deduplicacao. Para que as duas coisas nao se misturem, o Catch desmarca o pedido quando esta mensagem o marcou (D2a -> D2b).

## 5. Retencao das marcas

As marcas ficam numa `SHARED ROW` do ESQL, em memoria do servidor:

| Aspecto | Comportamento |
|---|---|
| TTL | nenhum: a lista so cresce |
| redeploy de qualquer flow da application | apaga todas as marcas (exp D3) |
| reinicio do servidor | apaga todas as marcas (consequencia de estar em memoria; nao medido) |
| compartilhamento | entre os modulos do mesmo schema, no mesmo servidor |

## 6. Janelas residuais

| Janela | O que acontece | Medido? | Mitigacao |
|---|---|---|---|
| verificacao e marca em blocos `ATOMIC` separados | com instancias adicionais, duas copias do mesmo pedido podem verificar antes de qualquer uma marcar, e as duas passam | nao (D-T3, no Projeto 5) | um unico bloco atomico, ou a marca no banco |
| replicas (pods) | cada processo tem a propria memoria: a duplicata passa se cair numa replica diferente da do original | nao (Projeto 5) | marca num armazenamento compartilhado |
| redeploy ou reinicio | a memoria some e uma duplicata posterior passa | sim (D3) | marca persistente |
| falha no commit do MQ depois da marca | a saida e desfeita, mas a marca fica; na reentrega, o pedido e tratado como duplicata e nunca e processado | nao (analise) | marca na mesma transacao da saida |

**Conclusao:** a marca em memoria e suficiente para o lab, com uma instancia e sem redeploy no meio. A solucao de producao e uma tabela com chave unica, gravada **na mesma transacao** da mensagem de saida (Projeto 10).
