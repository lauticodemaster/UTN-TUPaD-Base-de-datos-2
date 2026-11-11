# Parte A.4 — Auditoría de seguridad de `roles.sql` asistida por IA

**Herramienta:** Claude Code (Claude Opus 5.5), el mismo asistente que redactó la primera
versión del script, por lo que **no es una revisión independiente**: por eso cada
decisión pasó por revisión humana (ver la nota al pie de la tabla).

**Prompt de auditoría (reutilizable con otro asistente):**
```
Auditá este roles.sql de PostgreSQL 16+ bajo el principio de mínimo privilegio. Para cada
rol decí si tiene permisos de más o de menos según esta spec [pegar
docs/kiro_roles_spec/design.md], buscá caminos de escalamiento (SECURITY DEFINER, ADMIN
OPTION, default privileges, PUBLIC) y proponé correcciones concretas en SQL.
```

## Hallazgos y decisión
| # | Hallazgo | Origen | Propuesta de la IA | Decisión | Estado |
|---|---|---|---|---|---|
| 1 | **Permiso más amplio de lo necesario.** La primera versión tenía `ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES TO rol_app_lectura`: cualquier tabla futura, incluso una con datos personales, habría quedado legible para la app sin revisión | Borrador de la IA | Concederlo para «heredar la política» | **No se aplicó.** Se cambió por «denegar por defecto», porque una tabla nueva puede tener PII y se concede explícitamente después de actualizar la spec | Corregido en `roles.sql` §6 |
| 2 | **Sentencia incorrecta.** `ALTER DEFAULT PRIVILEGES … IN SCHEMA … REVOKE EXECUTE … FROM PUBLIC` no hace nada: los default privileges por esquema solo **agregan**. `\ddp` salía vacío | Borrador de la IA, detectado por `verificacion_permisos.sql` | Moverlo a nivel global (sin `IN SCHEMA`) | Aplicado. Verificado con una función nueva creada por `admin_datos`: `PUBLIC puede ejecutar fn nueva: false` | Corregido |
| 3 | Los triggers de `pedido.total` y `venta_categoria_dia` fallarían para `app_web`, porque corren con los privilegios del invocador | Revisión de la IA | Alternativa A: `GRANT UPDATE(total)` + escritura en `venta_categoria_dia` a la app. Alternativa B: trigger `SECURITY DEFINER` con `search_path` fijo | **Se eligió la B.** La A le daba a la app la capacidad de falsear totales | Aplicado y probado (total 3600 recalculado como `app_web`) |
| 4 | `fn_resetear_password` permitía a soporte tomar cuentas ADMIN | **Simulacro (Parte C)**, no lo detectó la revisión estática | Rechazar a los ADMIN dentro de la función | Aplicado (corrida 2 del simulacro) | Corregido |
| 5 | `soporte` puede leer mail y celular de **todos** los clientes (en el simulacro, 20.005 filas) | Revisión + simulacro | RLS o función que exija un ticket abierto | Se difiere como trabajo futuro, por decisión del equipo (requiere un modelo de tickets que Food Store no tiene) | Diferido |
| 6 | `app_web` puede insertar pedidos con cualquier `usuario_id` (no hay control por fila) | Revisión de la IA | RLS con `current_setting('app.usuario_id')` | Se difiere como trabajo futuro, por decisión del equipo (requiere cambios en la aplicación) | Diferido |
| 7 | Con `log_statement` en `ddl`/`mod`, un `ALTER ROLE … PASSWORD '…'` deja la clave en el log | Observado al configurar las claves de prueba | Fijar las claves solo con `\password`, que envía el hash SCRAM | Aplicado como instrucción en la cabecera de `roles.sql` | Corregido (procedimiento) |
| 8 | Rol heredado `app_lectura` (TP05) con SELECT sobre una vista con PII y sin justificar en la spec | Revisión de la IA | Eliminarlo | Aplicado (`roles.sql` §2) | Corregido |

> **Revisión humana:** el equipo revisó y **aprobó** las decisiones de los hallazgos
> 1–4 y 7–8. Los hallazgos 5 y 6 se **difieren** como trabajo futuro, también por decisión
> del equipo: requieren control por fila (RLS) y cambios en la aplicación, que quedan
> fuera del alcance de esta entrega.
