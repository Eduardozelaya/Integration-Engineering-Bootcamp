#!/usr/bin/env bash
# Sonda de prontidao do ACE (ADR 001): pronto = existe handle de LEITURA na APP.IN vindo do IP DESTE pod.
# Usada como readinessProbe, NUNCA liveness: se o MQ cair, o pod fica NotReady e o ACE se reconecta
# sozinho (P5-3b); como liveness, o Kubernetes reiniciaria todos os ACE sem resolver nada.
set -u
: "${POD_IP:?}" "${MQ_HOST:?}" "${MQ_APP_PASSWORD:?}"
export MQSERVER="DEV.APP.SVRCONN/TCP/${MQ_HOST}(1414)"
saida=$(printf '%s\nDISPLAY QSTATUS(APP.IN) TYPE(HANDLE) CONNAME\n' "$MQ_APP_PASSWORD" \
  | timeout 8 /opt/mqm-client/bin/runmqsc -c -u app QM1 2>&1) || true
if grep -q "CONNAME(${POD_IP})" <<< "$saida"; then
  exit 0
fi
echo "sem handle de leitura na APP.IN para ${POD_IP}"
exit 1
