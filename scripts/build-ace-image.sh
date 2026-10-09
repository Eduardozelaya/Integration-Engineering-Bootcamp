#!/usr/bin/env bash
# Monta a imagem do ACE a partir do commit atual (P5-1b).
# Fora do repositorio (licenca e tamanho): ACE em ~/ace/ace-12.0.12.27 e cliente MQ 9.4.0.26 em ~/mqclient.
set -eo pipefail
ACE_DIR="${ACE_DIR:-$HOME/ace/ace-12.0.12.27}"
MQC_DIR="${MQC_DIR:-$HOME/mqclient}"
TAG="${TAG:-integration-lab/ace:12.0.12.27-dev}"
REPO="$(git rev-parse --show-toplevel)"
CTX="$HOME/.cache/ace-image-ctx"   # no mesmo disco do ACE: permite hardlinks
rm -rf "$CTX" && mkdir -p "$CTX/src/ws" "$CTX/ace"
# shellcheck disable=SC1091
. "$ACE_DIR/server/bin/mqsiprofile" > /dev/null

echo "== 1. BAR do commit $(git -C "$REPO" rev-parse --short HEAD) (git archive, LF, sem Toolkit)"
git -C "$REPO" archive HEAD ace | tar -x -C "$CTX/src"
cp -r "$CTX/src/ace/apps/OrderProcessing" "$CTX/src/ace/policies/R2Policies" "$CTX/src/ws/"
ibmint package --input-path "$CTX/src/ws" --output-bar-file "$CTX/app-base.bar" \
  --project OrderProcessing --project R2Policies

echo "== 2. overrides do ambiente container"
ibmint apply overrides "$REPO/ace/docker/container.properties" \
  --input-bar-file "$CTX/app-base.bar" --output-bar-file "$CTX/app.bar"

echo "== 3. contexto de build (hardlinks; o Toolkit fica de fora)"
cp -al "$ACE_DIR/server" "$ACE_DIR/common" "$ACE_DIR/ace" "$ACE_DIR/license" "$CTX/ace/"
cp -al "$MQC_DIR" "$CTX/mqclient"
cp "$REPO/ace/docker/Dockerfile" "$REPO/ace/docker/start.sh" "$CTX/"
rm -rf "$CTX/src" "$CTX/app-base.bar"

echo "== 4. docker build"
docker build -t "$TAG" \
  --label "org.opencontainers.image.revision=$(git -C "$REPO" rev-parse --short HEAD)" "$CTX"
docker image ls "$TAG"
