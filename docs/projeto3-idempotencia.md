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
| D2a — falha após a marca, sem desmarcar | DUP 1, OUT 0, DLQ 0 (pedido legítimo perdido como duplicata) | DUP 1, OUT 0, DLQ 0; trace 1 linha (BOC 0); log termina em "Retentativa 1 de 3" e a 2ª entrega não deixa rastro (`exp-d2a-falha-apos-marca.txt`) |
| D2b — com desmarcar condicionado | DLQ 1 com motivo, DUP 0 | trace 3 linhas; DLQ 1 com motivo (tentativas 3), DUP 0; reenvio sem gatilho processado (OUT 1) (`exp-d2b-desmarcar-no-catch.txt`) |
| D3 — redeploy do flow | OUT 2 (memória perdida) | antes do redeploy: OUT 1, DUP 1 (controle); redeploy 02:49:46 (BIP2269I); depois: OUT 2 — a duplicata passou (`exp-d3-redeploy-apaga-marcas.txt`) |

## 6. Dívida de design e achados
- **`APP.DUP` com `MAXDEPTH` padrão (5000).** Um produtor em laço enche a fila; o `GravarDuplicata` falha com `2053` (fila cheia), há rollback, e as duplicatas passam a ir para a `APP.BACKOUT` — a cadeia do exp E, por outra causa. Opções: `MAXDEPTH(50000)` como a `APP.IN`; alerta de profundidade (Projeto 7).
- **O `+passall` registra o usuário de origem.** Na `APP.DUP`, o ID do usuário é `mqm` (quem rodou o `amqsput`), não `app` (quem o ACE usa para conectar). Útil para auditoria; é também o motivo de o MQ separar `passall` de `put` (Projetos 6 e 11).
- **A 2ª entrega do D2a não deixa rastro no log.** Ela não passa pelo Catch (sem trace) e não gera erro (sem log). Só a fila de auditoria prova que ela existiu, o que justifica a opção B com evidência.
- **A marca não expira.** Sem TTL, a memória cresce enquanto o servidor estiver no ar.
- **Um deploy de qualquer flow da application apaga as marcas.** O deploy do `ConsultarPedido` (request/reply) reiniciou também o `PassThrough`, que está na mesma application `OrderProcessing`. A janela do D3 abre mesmo quando o flow com a deduplicação não mudou.
