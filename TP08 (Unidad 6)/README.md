# TP Unidad 6 — Mantenimiento, respaldo y recuperación (Food Store)

| Carpeta | Contenido |
| --- | --- |
| `Parte1_Especificacion/` | `SPEC_U6.md` |
| `Parte2_Respaldo/` | `backup_foodstore.sh` / `.ps1` (`backups/` y `logs/` se generan al ejecutar) |
| `Parte3_Monitoreo_Mantenimiento/` | `health_check.sql`, `maintenance.sql` |
| `Parte4_Simulacro/` | `restore_test.sh` / `.ps1`, `validacion.sql` |
| `Parte5_Informe/` | `informe_u6.md` (plantilla a completar con los valores observados; exportar a `informe_u6.pdf`) |

## Orden de ejecución (PowerShell, contraseña solo en la sesión)

```powershell
$env:PGPASSWORD = Read-Host "Password"       # no se guarda en ningún archivo
psql -h localhost -U postgres -d foodstore -f Parte4_Simulacro\validacion.sql   # conteos de referencia
.\Parte2_Respaldo\backup_foodstore.ps1
psql -h localhost -U postgres -d foodstore -f Parte3_Monitoreo_Mantenimiento\health_check.sql
psql -h localhost -U postgres -d foodstore -f Parte3_Monitoreo_Mantenimiento\maintenance.sql
.\Parte4_Simulacro\restore_test.ps1
```

Los binarios de PostgreSQL 17 están en `C:\Program Files\PostgreSQL\17\bin` (agregar al `PATH` si hace falta).
