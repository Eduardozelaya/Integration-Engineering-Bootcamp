#!/usr/bin/env bash
# Copia projetos do workspace do Toolkit (Windows) para o repositorio (WSL).
# Uso: ./scripts/sync-ace.sh          -> dry-run (mostra o que mudaria)
#      ./scripts/sync-ace.sh --apply  -> aplica
set -euo pipefail

WS=/mnt/c/Users/LGzel/IBM/ACET12/workspace
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# projeto do Toolkit -> pasta dentro de ace/  (so o que entra no portfolio)
declare -A MAP=(
  [OrderProcessing]=apps
  [R2Policies]=policies
)

command -v rsync >/dev/null || { echo "ERRO: rsync nao instalado (sudo apt install rsync)" >&2; exit 1; }

OPTS=(-rt --delete --itemize-changes --chmod=D755,F644 --exclude='bin/')
[[ "${1:-}" == "--apply" ]] || OPTS+=(--dry-run)

for p in "${!MAP[@]}"; do
  src="$WS/$p/"
  dst="$REPO/ace/${MAP[$p]}/$p/"
  [[ -d "$src" ]] || { echo "ERRO: origem nao existe: $src" >&2; exit 1; }
  [[ "${1:-}" == "--apply" ]] && mkdir -p "$dst"
  echo "=== $p -> ace/${MAP[$p]}/$p"
  rsync "${OPTS[@]}" "$src" "$dst"
done

if [[ "${1:-}" == "--apply" ]]; then
  git -C "$REPO" status --short ace/
else
  echo "(dry-run: nada foi alterado; rode com --apply)"
fi
