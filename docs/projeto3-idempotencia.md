# Projeto 3, parte 2 — Idempotência

## 1. Qual duplicata estamos evitando?
<!-- com as suas palavras: reentrega do MQ apos rollback x reenvio do produtor; evidencia do D0 (MsgId diferentes, mesmo orderId) -->

## 2. Decisões
- Chave: `orderId` (identificador de negócio), não `MsgId`.
- Armazenamento: `SHARED ROW` do ESQL. Mesmas propriedades transacionais do Global Cache (nenhuma), sem custo de infraestrutura; o Global Cache está desligado no servidor (`cacheOn` comentado). Fica como variação para mais de um servidor.
- Destino da duplicata: fila de auditoria `APP.DUP` (nenhuma mensagem some sem rastro em fila). Critério do teste final: `OUT + DLQ + DUP = total`.
- Marca: último passo do `ProcessarPedido`. O Catch desmarca **somente** se esta mensagem marcou (flag no `Environment`).

## 3. Por quanto tempo a marca vale?
<!-- TTL escolhido e por que; nesta versao a marca nao expira (divida registrada) -->

## 4. Janela residual
<!-- queda do processo entre a marca e o commit; reinicio/redeploy apaga a memoria (D3); por que isso motiva o Projeto 10 (XA) -->

## 5. Experimentos
| Exp. | Previsão | Resultado |
|---|---|---|
| D0 — linha de base | 2 saídas para o mesmo orderId | OUT 2; MsgId diferentes (`exp-d0-duplicata.txt`) |
| D1 — deduplicação | OUT 1, DUP 1 | OUT 1 (99 bytes, processado), DUP 1 (29 bytes, original intacto); MsgId diferentes (`exp-d1-deduplicacao.txt`) |
| D2a — falha após a marca, sem desmarcar | DUP 1, OUT 0, DLQ 0 (pedido legítimo perdido como duplicata) | |
| D2b — com desmarcar condicionado | DLQ 1 com motivo, DUP 0 | |
| D3 — reinício do servidor | OUT 2 (memória perdida) | |
