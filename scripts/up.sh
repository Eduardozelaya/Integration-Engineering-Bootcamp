#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "crie o .env a partir do .env.example"; exit 1; }
docker compose "$@" up -d
echo "aguardando o queue manager..."
until docker exec qm1 dspmq 2>/dev/null | grep -q Running; do sleep 3; done
docker exec -i qm1 runmqsc QM1 < mq/config/queues.mqsc
docker exec -i qm1 bash -s -- "${MQ_QMGR_NAME:-QM1}" < mq/config/authorities.sh
echo "pronto. console: https://localhost:9443"
