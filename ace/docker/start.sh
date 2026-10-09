#!/usr/bin/env bash
# Inicializacao do container do ACE: a configuracao de ambiente entra aqui, nao na imagem.
set -eo pipefail
# shellcheck disable=SC1091
command -v IntegrationServer > /dev/null || { set +e; . /opt/ibm/ace-12/server/bin/mqsiprofile > /dev/null; set -e; }
WD=/home/aceuser/ace-server
: "${MQ_APP_PASSWORD:?defina MQ_APP_PASSWORD (vem do .env, nunca da imagem)}"
# A policy do repositorio aponta para localhost (o lab); no container, o MQ e outro servico.
sed -i "s#<queueManagerHostname>[^<]*</queueManagerHostname>#<queueManagerHostname>${MQ_HOST:-qm1}</queueManagerHostname>#" \
  "$WD/run/R2Policies/MQ_LOCAL.policyxml"
grep -o "<queueManagerHostname>[^<]*</queueManagerHostname>" "$WD/run/R2Policies/MQ_LOCAL.policyxml"
mqsisetdbparms -w "$WD" -n mq::mqcreds -u "${MQ_APP_USER:-app}" -p "$MQ_APP_PASSWORD" > /dev/null
exec IntegrationServer --work-dir "$WD" --admin-rest-api 7600 --http-port-number 7800
