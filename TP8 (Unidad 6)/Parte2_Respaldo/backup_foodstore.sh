#!/usr/bin/env bash
# Respaldo custom de foodstore. La contraseña NO se guarda aquí:
# usar PGPASSWORD en la sesión o ~/.pgpass (pgpass.conf en Windows).
set -euo pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
DB="foodstore"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$DIR/backups"
LOG_DIR="$DIR/logs"
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

STAMP="$(date +%Y%m%d_%H%M%S)"
FILE="$BACKUP_DIR/${DB}_${STAMP}.dump"
LOG="$LOG_DIR/backup_${STAMP}.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

log "Inicio respaldo de $DB -> $FILE"
if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB" -Fc -w -f "$FILE" 2>>"$LOG"; then
  if pg_restore --list "$FILE" >/dev/null 2>>"$LOG"; then
    log "OK tamano=$(wc -c <"$FILE") bytes archivo=$FILE"
  else
    log "ERROR: el archivo generado no es legible por pg_restore"
    rm -f "$FILE"; exit 2
  fi
else
  rc=$?
  log "ERROR: pg_dump fallo (codigo $rc)"
  rm -f "$FILE"; exit "$rc"
fi
