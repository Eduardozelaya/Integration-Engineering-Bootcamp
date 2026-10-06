#!/usr/bin/env bash
# A imagem de desenvolvedor autoriza o principal 'app' apenas no perfil DEV.**
# As filas APP.* precisam do seu proprio perfil generico.
# +passall +setall: o ACE grava com o contexto da mensagem original (SET OutputRoot = InputRoot)
# e desvia para backout/DEADQ preservando o contexto (erro 5 de 18/09; exp R3a).
# NOTA: Projeto 11 substitui isto por permissoes por fila (menor privilegio).
set -euo pipefail
QM="${1:-QM1}"
setmqaut -m "$QM" -t qmgr -p app +connect +inq +setall
setmqaut -m "$QM" -n "APP.**" -t queue -p app +get +put +inq +browse +passall +setall
echo "autorizacoes aplicadas em $QM"
