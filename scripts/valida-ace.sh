#!/usr/bin/env bash
# Valida o codigo de integracao SEM o ACE (ADR 002): o que o CI publico consegue conferir.
# Uso: ./scripts/valida-ace.sh [pasta-ace]   (padrao: ace)
set -uo pipefail
SRC="${1:-ace}"
falhas=0
ok()     { echo "ok      $1"; }
falhou() { echo "FALHOU  $1"; falhas=$((falhas + 1)); }

echo "== 1. XML bem formado"
while IFS= read -r -d '' f; do
  if xmllint --noout "$f" 2>/dev/null; then ok "$f"; else falhou "$f"; fi
done < <(find "$SRC" -type f \( -name '*.msgflow' -o -name '*.policyxml' -o -name '*.descriptor' -o -name '.project' \) -print0)

echo "== 2. cada computeExpression do flow aponta para um modulo ESQL existente"
modulos=$(grep -rhoiE 'CREATE (COMPUTE|DATABASE|FILTER) MODULE [A-Za-z0-9_]+' "$SRC" --include='*.esql' | awk '{print $NF}' | sort -u)
refs=$(grep -rhoE 'computeExpression="esql://routine/#[A-Za-z0-9_]+\.' "$SRC" --include='*.msgflow' | sed -E 's/.*#([A-Za-z0-9_]+)\./\1/' | sort -u)
for r in $refs; do
  if grep -qx "$r" <<< "$modulos"; then ok "$r"; else falhou "$r (referenciado no flow, sem CREATE ... MODULE no ESQL)"; fi
done

echo "== 3. cada override do container aponta para um node existente"
while IFS= read -r linha; do
  case "$linha" in ''|'#'*) continue ;; esac
  chave=${linha%%=*}; flow=${chave%%#*}; resto=${chave#*#}; node=${resto%%.*}
  arq=$(find "$SRC" -name "$flow.msgflow" | head -1)
  if [ -n "$arq" ] && grep -q "string=\"$node\"" "$arq"; then ok "$flow#$node"; else falhou "$flow#$node (override para um node que nao existe)"; fi
done < "$SRC/docker/container.properties"

if [ "$falhas" -gt 0 ]; then echo "== $falhas falha(s)"; exit 1; fi
echo "== tudo ok"
