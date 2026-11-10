# SPEC_U6 — Plan de mantenimiento, respaldo y recuperación (Food Store)

**Motor:** PostgreSQL 16+ · **Base principal:** `foodstore` · **Base de prueba:** `foodstore_restore_test`

## Qué se automatiza, cuándo y cómo se confirma

| Tarea | Qué se automatiza | Frecuencia | Condición de éxito |
| --- | --- | --- | --- |
| Respaldo de `foodstore` | `backup_foodstore.sh` / `.ps1` ejecuta `pg_dump -Fc` | Diaria | Existe `foodstore_AAAAMMDD_HHMMSS.dump` con tamaño > 0, `pg_restore --list` lo lee y el log termina en `OK`. Código de salida 0. |
| Chequeo de salud | `psql -f health_check.sql` | Diaria | Se ejecuta sin error; tamaño, conexiones, tuplas muertas y consultas activas quedan en el log. |
| Revisión de mantenimiento | `psql -f maintenance.sql` | Semanal | Reporte de tuplas muertas/autovacuum/estadísticas; `ANALYZE` solo si hay estadísticas desactualizadas. |
| Restauración de prueba | `restore_test.sh` / `.ps1` sobre `foodstore_restore_test` | Semanal | `pg_restore` termina sin error, los conteos coinciden con los previos al respaldo y los controles de inválidos devuelven 0. |

## Objetivos del laboratorio

- **RPO previsto:** 24 h (respaldo diario; se pierde como máximo un día de datos).
- **RTO previsto:** 15 min (restauración + validación mínima sobre la base de laboratorio).

## Reglas de seguridad

1. Ninguna contraseña en scripts, logs ni repositorio. Se usa `PGPASSWORD` de la sesión o `pgpass.conf` / `.pgpass`.
2. `foodstore` **nunca** se elimina ni se reemplaza; la restauración se hace solo en `foodstore_restore_test`.
3. El respaldo es formato custom (`-Fc`) para poder usar `pg_restore`.
4. Los scripts terminan con código distinto de 0 si `pg_dump`/`pg_restore` fallan.
5. Las pruebas destructivas (`DROP DATABASE`) solo se hacen sobre `foodstore_restore_test`, con una guarda que rechaza cualquier otro nombre.
6. **No se usa `VACUUM FULL`** como mantenimiento periódico (bloqueo exclusivo); todo `VACUUM`/`ANALYZE` manual se justifica con la observación previa.
7. Todo código generado con OpenCode se revisa y prueba manualmente antes de aceptarlo.

## Entregables

`SPEC_U6.md`, `backup_foodstore.sh/.ps1`, `health_check.sql`, `maintenance.sql`, `restore_test.sh/.ps1`, `informe_u6.pdf`. No se entrega la contraseña; el `.dump` puede omitirse con evidencia de tamaño y restauración.
