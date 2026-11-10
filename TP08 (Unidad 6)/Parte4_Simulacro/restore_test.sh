#!/usr/bin/env bash
# Simulacro de restauración sobre foodstore_restore_test (NUNCA sobre foodstore).
# Sin contraseñas: usar PGPASSWORD en la sesión o ~/.pgpass.
# Uso: ./restore_test.sh [archivo.dump]   (por defecto, el último de ../Parte2_Respaldo/backups)
set -euo pipefail

PGHOST="${PGHOST:-localhost}"; PGPORT="${PGPORT:-5432}"; PGUSER="${PGUSER:-postgres}"
TEST_DB="foodstore_restore_test"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DUMP="${1:-$(ls -t "$DIR"/../Parte2_Respaldo/backups/foodstore_*.dump 2>/dev/null | head -n1 || true)}"
[ -n "$DUMP" ] && [ -f "$DUMP" ] || { echo "No hay respaldo .dump disponible" >&2; exit 1; }

mkdir -p "$DIR/logs"
LOG="$DIR/logs/restore_$(date +%Y%m%d_%H%M%S).log"
log() { echo "[$(date '+%T')] $*" | tee -a "$LOG"; }

AGE_MIN=$(( ( $(date +%s) - $(date -r "$DUMP" +%s) ) / 60 ))
log "Respaldo: $DUMP (antiguedad = ${AGE_MIN} min -> RPO observado)"

START=$(date +%s)   # cronometro: justo antes de crear la base

dropdb   -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w --if-exists "$TEST_DB"
createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w "$TEST_DB"
pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w -d "$TEST_DB" \
  --no-owner --no-privileges --exit-on-error "$DUMP" 2>>"$LOG"
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w -d "$TEST_DB" -v ON_ERROR_STOP=1 \
  -f "$DIR/validacion.sql" | tee -a "$LOG"

log "RTO observado = $(( $(date +%s) - START )) s"
log "Verificar: productos_invalidos = 0, detalles_invalidos = 0 y conteos iguales a los previos al respaldo."
