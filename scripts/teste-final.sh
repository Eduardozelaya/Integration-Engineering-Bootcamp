#!/usr/bin/env bash
# Teste final do Projeto 3: carga mista no PassThrough e conferencia das somas.
# Uso: ./scripts/teste-final.sh <execucao 1..9>   (cada execucao usa a faixa de orderId execucao*1000)
set -u
RUN="${1:?uso: $0 <execucao 1..9>}"
B=$((RUN * 1000))
DIR=docs/evidencias/teste-final; mkdir -p "$DIR"
LOG="$DIR/execucao-$RUN.txt"
APPPW=$(grep "^MQ_APP_PASSWORD=" .env | cut -d= -f2 | tr -d '\r\n')
REST=https://localhost:9443/ibmmq/rest/v3/messaging/qmgr/QM1/queue
CURL=(curl -sk -u "app:$APPPW" -H "ibm-mq-rest-csrf-token: x")

mq()     { printf '%s\n' "$@" | docker exec -i qm1 runmqsc QM1; }
prof()   { mq "DISPLAY QSTATUS($1) CURDEPTH" | grep -o "CURDEPTH([0-9]*)" | tr -dc '0-9'; }
zerar()  { docker exec qm1 bash -c "dmpmqmsg -m QM1 -I $1 -f stdout" > /dev/null 2>&1; }
drenar() { : > "$2"; while :; do
             r=$("${CURL[@]}" -X DELETE "$REST/$1/message?wait=500" -w $'\n%{http_code}')
             [ "${r##*$'\n'}" = "200" ] || break
             printf '%s\n' "${r%$'\n'*}" >> "$2"; done; }
conf()   { if [ "$2" = "$3" ]; then echo "  ok      $1: $2"; else echo "  FALHOU  $1: $2 (esperado $3)"; FALHAS=$((FALHAS+1)); fi; }

# portao: consumidor ativo e filas vazias
for q in APP.IN APP.OUT APP.DLQ APP.BACKOUT APP.DUP; do zerar $q; done
IPP=$(mq "DISPLAY QSTATUS(APP.IN) IPPROCS" | grep -o "IPPROCS([0-9]*)")
[ "$IPP" = "IPPROCS(1)" ] || { echo "PAROU: APP.IN com $IPP (o ACE nao esta consumindo)"; exit 1; }

# carga: validos, erros intercalados, e as duplicatas por ultimo (depois dos originais)
CARGA=$(mktemp)
for i in $(seq 1 35);  do echo "{\"orderId\":\"$((B+i))\",\"valor\":$((B+i))}"; done              >> "$CARGA"
for i in $(seq 1 15);  do echo "{\"orderId\":\"$((B+100+i))\",\"forcarErro\":\"true\"}"; done     >> "$CARGA"
for i in $(seq 36 70); do echo "{\"orderId\":\"$((B+i))\",\"valor\":$((B+i))}"; done              >> "$CARGA"
for i in $(seq 1 5);   do echo "{\"valor\":$i}"; done                                             >> "$CARGA"
for i in $(seq 1 5);   do echo '{"orderId":'; echo "texto invalido $i"; done                      >> "$CARGA"
for i in $(seq 1 10);  do echo "{\"orderId\":\"$((B+i))\",\"valor\":$((B+i))}"; done              >> "$CARGA"

{
  echo "# Teste final - execucao $RUN | orderId na faixa $B | $(date -Is)"
  echo "# portao: $IPP, filas zeradas | carga: $(wc -l < "$CARGA") mensagens"
  T0=$(date +%s)
  docker exec -i qm1 /opt/mqm/samp/bin/amqsput APP.IN QM1 < "$CARGA" > /dev/null
  echo ">>> carga enviada em $(date -u +%T) UTC"

  # espera a APP.IN esvaziar e ficar vazia por 3 s seguidos (limite: 300 s)
  vazias=0
  for s in $(seq 1 300); do
    if [ "$(prof APP.IN)" = "0" ]; then vazias=$((vazias+1)); else vazias=0; fi
    [ $vazias -ge 3 ] && break; sleep 1
  done
  echo ">>> APP.IN vazia apos ~$(( $(date +%s) - T0 )) s"

  OUTN=$(prof APP.OUT); DLQN=$(prof APP.DLQ); DUPN=$(prof APP.DUP); BKN=$(prof APP.BACKOUT)
  drenar APP.OUT "$DIR/execucao-$RUN-out.jsonl"
  drenar APP.DLQ "$DIR/execucao-$RUN-dlq.jsonl"
  drenar APP.DUP "$DIR/execucao-$RUN-dup.jsonl"
  D="$DIR/execucao-$RUN-dlq.jsonl"; O="$DIR/execucao-$RUN-out.jsonl"

  FALHAS=0
  echo "===== conferencias"
  conf "APP.OUT"                      "$OUTN" 70
  conf "APP.DLQ"                      "$DLQN" 30
  conf "APP.DUP"                      "$DUPN" 10
  conf "APP.BACKOUT"                  "$BKN"  0
  conf "soma OUT+DLQ+DUP+BACKOUT"     "$((OUTN+DLQN+DUPN+BKN))" 110
  conf "orderId repetidos na OUT"     "$(grep -o '"orderId":"[0-9]*"' "$O" | sort | uniq -d | wc -l)" 0
  conf "DLQ TRANSITORIO c/ 3 tentativas" "$(grep '"tipo":"TRANSITORIO"' "$D" | grep -c '"tentativas":3')" 15
  conf "DLQ PERMANENTE c/ 1 tentativa"   "$(grep '"tipo":"PERMANENTE"'  "$D" | grep -c '"tentativas":1')" 15
  conf "DLQ com originalBruto"        "$(grep -c '"originalBruto"' "$D")" 30
  echo "===== resultado: $([ $FALHAS -eq 0 ] && echo PASSOU || echo "FALHOU ($FALHAS conferencias)")"
} | tee "$LOG"
rm -f "$CARGA"
