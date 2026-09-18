#!/usr/bin/env bash
# A imagem de desenvolvedor autoriza o principal 'app' apenas no perfil DEV.**
# As filas APP.* precisam do seu proprio perfil generico.
# NOTA: Projeto 11 substitui isto por permissoes por fila (menor privilegio).
set -euo pipefail
QM="${1:-QM1}"
setmqaut -m "$QM" -t qmgr -p app +connect +inq
setmqaut -m "$QM" -n "APP.**" -t queue -p app +get +put +inq +browse
echo "autorizacoes aplicadas em $QM"
