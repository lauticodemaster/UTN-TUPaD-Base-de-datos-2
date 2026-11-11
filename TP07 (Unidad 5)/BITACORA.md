# Bitácora de uso de IA

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| **Parte D.** Describí la estructura de `usuario_anon` (sin datos reales) con la consulta de usuarios por rol y mes de alta, y pedí la consulta equivalente sobre `usuario`, con mismas columnas, agrupamiento y orden, sin filtros ni columnas extra y sin ejecutarla. | Devolvió `SELECT rol, date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad FROM usuario GROUP BY rol, date_trunc('month', created_at) ORDER BY rol, mes_alta;` | Comparé columnas, agrupamiento y orden contra la consulta sobre `usuario_anon`: coinciden. Mi prompt tenía un typo (`'mon'`) que la IA resolvió bien. Ejecuté ambas consultas y verifiqué con `EXCEPT` en ambas direcciones que dan 0 filas. |
| **Reconstrucción previa a la Parte A.** Pedido a Claude Code: reconstruir `fn_autenticar` y `fn_resetear_password` (no se conservaron de la clase) con bcrypt, SECURITY DEFINER y registro de intentos. | Generó `sql/funciones_autenticacion.sql` con migración a bcrypt, `auditoria_login`, bloqueo tras 5 fallos en 15 min y `REVOKE … FROM PUBLIC`. | Se revisó línea por línea y se probó en `foodstore_test`. El simulacro mostró que el reset no distinguía cuentas ADMIN (ver fila Parte C). |
| **Parte A.** Pedido a Claude Code: spec Kiro (requirements/design) de roles con mínimo privilegio, y después `roles.sql`. | Spec en `docs/kiro_roles_spec/` y `sql/roles.sql` con GRANT por columna, `ALTER DEFAULT PRIVILEGES` y triggers SECURITY DEFINER. | **Caso de permiso de más:** el borrador traía `ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES TO rol_app_lectura`; se descartó por «denegar por defecto». **Caso incorrecto:** `REVOKE … IN SCHEMA` no tenía efecto; lo detectó `\ddp` vacío en `verificacion_permisos.sql`. Ver `docs/auditoria_ia_roles.md`. Decisiones revisadas y aprobadas por el equipo. |
| **Parte B.** Pedido a Claude Code: script de operaciones de prueba y análisis del log. | `sql/auditoria_test.sql` + `.sh`, `docs/informe_auditoria.md`. | Se verificó sobre el log real que el SELECT y el ROLLBACK no aparecen con `mod`. Se agregó la prueba de fuga de claves (`docs/prueba_fuga_claves_log.txt`). |
| **Parte C.** Pedido a Claude Code: script del simulacro y anonimizador del log. | `sql/simulacro_incidente.sql`/`.sh`, `sql/anonimizar_log.py`. | El escalamiento por motor falló como se esperaba, pero el reset de un ADMIN funcionó: **hallazgo corregido** y simulacro repetido. La reconstrucción del log se contrastó con lo ejecutado y el equipo la validó (`docs/informe_incidente.md` §4). |

## Caso más significativo de error de la IA (Parte E.2)
El `REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` con `IN SCHEMA`, que propuso la IA, parecía
correcto, corría sin error y se veía bien en una lectura rápida, pero no hacía nada: las
funciones nuevas seguían ejecutables por cualquiera. Lo descubrimos porque la verificación
no se quedó en «el script corre»: `\ddp` salió vacío, y una prueba concreta (crear una
función como `admin_datos` y consultar su ACL) confirmó el defecto antes y la corrección
después. El simulacro dejó una lección parecida: la revisión estática de permisos dio todo
OK, y recién la prueba de ataque mostró el camino `fn_resetear_password` → ADMIN.

## Nota sobre el historial de Git (Parte E.3)
Los artefactos de las Partes A–C se versionaron en la segunda entrega del TPI, en lugar de
avanzar con un commit por parte. La próxima vez: un commit por parte al terminar cada
una, con la spec de Kiro commiteada **antes** que el SQL que la implementa.
