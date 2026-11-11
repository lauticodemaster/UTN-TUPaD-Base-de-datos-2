#!/usr/bin/env bash
# TP Unidad 5 · Parte C — ejecuta el simulacro, recorta el log y lo anonimiza.
# Uso: PGDATA=/ruta/cluster PGPASSFILE=/ruta/fuera/de/git ./simulacro_incidente.sh <sufijo>
#   genera ../docs/salida_simulacro_<sufijo>.txt y ../docs/log_simulacro_<sufijo>_anonimizado.txt
set -euo pipefail
SUF=${1:-1}
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$PGDATA/log/postgresql.log"
TMP="$(mktemp)"

inicio=$(wc -c < "$LOG")
psql -X -q -w -h 127.0.0.1 -p 55432 -U app_web -d foodstore_test -f "$DIR/simulacro_incidente.sql" < /dev/null > "$DIR/../docs/salida_simulacro_${SUF}.txt" 2>&1 || true
sleep 1
tail -c +"$((inicio + 1))" "$LOG" > "$TMP"
python -I "$DIR/anonimizar_log.py" "$TMP" > "$DIR/../docs/log_simulacro_${SUF}_anonimizado.txt"
rm -f "$TMP"     # el log crudo no se versiona
