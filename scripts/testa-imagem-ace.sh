#!/usr/bin/env bash
# Constroi a imagem do ACE e roda o teste final SOBRE ELA, com as travas de 27/10 (ADR 003):
# o build que falha para tudo; o container e recriado; o sistema dentro dele e conferido antes do teste.
# Uso: ./scripts/testa-imagem-ace.sh <numero-da-execucao>
set -euo pipefail
cd "$(dirname "$0")/.."

N="${1:?uso: $0 <numero-da-execucao>}"
[ ! -e "docs/evidencias/teste-final/execucao-$N.txt" ] || { echo "PARADO: a execucao $N ja existe"; exit 1; }

BASE=$(grep -oE '^FROM ubuntu:[0-9.]+' ace/docker/Dockerfile | cut -d: -f2)
[ -n "$BASE" ] || { echo "PARADO: a base do Ubuntu nao foi encontrada no Dockerfile"; exit 1; }
echo "== base esperada: Ubuntu $BASE | execucao $N"

./scripts/build-ace-image.sh
./scripts/up.sh
docker compose --profile ace up -d --force-recreate ace
sleep 25

SO=$(docker exec ace grep PRETTY_NAME /etc/os-release)
echo "== sistema no container: $SO"
grep -q "$BASE" <<< "$SO" || { echo "PARADO: o container nao esta na $BASE"; exit 1; }

./scripts/teste-final.sh "$N"
