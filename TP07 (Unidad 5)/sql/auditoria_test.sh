#!/usr/bin/env bash
# TP Unidad 5 · Parte B — ejecuta la prueba de auditoría y recorta el fragmento de log.
# Requisitos: servidor con log_connections/log_disconnections/log_statement='mod'
# (ver docs/informe_auditoria.md), PGPASSFILE con la clave de app_web (fuera de Git).
# Uso: PGDATA=/ruta/al/cluster ./auditoria_test.sh > ../docs/log_auditoria_prueba.txt
set -euo pipefail
HOST=${PGHOST:-127.0.0.1}; PORT=${PGPORT:-55432}; DB=${PGDATABASE:-foodstore_test}
LOG="$PGDATA/log/postgresql.log"
DIR="$(cd "$(dirname "$0")" && pwd)"

inicio=$(wc -c < "$LOG")

# 1) lectura + inserción + actualización como app_web
psql -h "$HOST" -p "$PORT" -U app_web -d "$DB" -q -f "$DIR/auditoria_test.sql" >/dev/null

# 2) inicio de sesión fallido: clave incorrecta para app_web (sin PGPASSFILE)
PGPASSFILE=/dev/null PGPASSWORD='clave-incorrecta' \
  psql -h "$HOST" -p "$PORT" -U app_web -d "$DB" -c 'select 1' >/dev/null 2>&1 || true

sleep 1
tail -c +"$((inicio + 1))" "$LOG"
