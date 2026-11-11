# Parte B — Activación y prueba de la auditoría

## 1. Parámetros modificados (`postgresql.conf` del servidor de desarrollo)
| Parámetro | Valor anterior (default) | Valor aplicado | Para qué |
|---|---|---|---|
| `logging_collector` | `off` | `on` | Mandar el log a un archivo propio |
| `log_directory` / `log_filename` | `log` / `postgresql-%Y-%m-%d_%H%M%S.log` | `log` / `postgresql.log` | Un único archivo para la prueba |
| `log_line_prefix` | `'%m [%p] '` | `'%m [%p] user=%u db=%d host=%h app=%a '` | **Quién**, sobre qué base, **desde dónde** y con qué cliente, en cada línea |
| `log_connections` | `off` | `on` | Recepción, autenticación (método y línea de `pg_hba`) y autorización de cada conexión |
| `log_disconnections` | `off` | `on` | Fin de sesión y duración |
| `log_statement` | `none` | `mod` | DDL y DML de modificación (INSERT/UPDATE/DELETE/TRUNCATE…) |
| `lc_messages` | idioma del SO | `C` | Mensajes en inglés, estables para analizarlos con herramientas |

Además, por rol: `ALTER ROLE soporte_ops SET log_statement = 'all'` (las sesiones humanas
privilegiadas registran también las lecturas; ver `sql/roles.sql`).

Servidor: PostgreSQL 18.6, clúster de desarrollo propio. Script: `sql/auditoria_test.sql`,
orquestado por `sql/auditoria_test.sh`. Fragmento capturado: [`log_auditoria_prueba.txt`](log_auditoria_prueba.txt).

## 2. Secuencia ejecutada
Como `app_web`: una lectura de `producto`, un INSERT en `pedido`, un INSERT en
`detalle_pedido`, un UPDATE de `pedido.estado` (dentro de una transacción revertida), y
después un intento de conexión con contraseña incorrecta.

## 3. Qué sirve para auditar en el fragmento y qué queda afuera
**Lo que sí aporta:**
- **Quién:** `user=app_web` en cada línea, y `identity="app_web" method=scram-sha-256` en la autenticación.
- **Qué:** el texto de los INSERT y del UPDATE, con los valores concretos (`id = 200011`).
- **Cuándo:** marca de tiempo con milisegundos y zona horaria, y la duración de la sesión.
- **Desde dónde:** `host=127.0.0.1 port=58353` y `application_name`.
- **Intento fallido:** `FATAL: password authentication failed for user "app_web"`, con la línea de `pg_hba.conf` que coincidió.
- **Correlación:** el PID (`[14156]`) agrupa todas las líneas de una misma sesión.

**Lo que queda fuera de este mecanismo nativo:**
- **La lectura no aparece**: con `mod`, un `SELECT` masivo de datos personales no deja rastro. Pasar todo a `all` aumenta mucho el volumen y, como se ve más abajo, filtra contraseñas.
- **No registra el resultado**: el `ROLLBACK` no figura, así que el log muestra un INSERT que en realidad nunca se confirmó.
- **No hay detalle por fila ni por objeto**: no dice qué filas tocó un UPDATE con `WHERE` amplio, ni si un `SELECT` sobre una vista accedió a `usuario` por debajo. Eso es lo que agrega **pgaudit** (registro por objeto `OBJECT`, por clase `READ`/`WRITE`/`ROLE`/`DDL`, en formato estructurado).
- **Las sentencias dinámicas** dentro de funciones `SECURITY DEFINER` quedan registradas como la llamada, no como lo que se ejecutó adentro. Por eso `fn_autenticar` escribe en `auditoria_login`.
- **No hay integridad**: un superusuario puede editar el archivo o desactivar el registro (`ALTER SYSTEM`) sin que quede evidencia.

## 4. ¿El log es un activo sensible?
Sí. La prueba [`prueba_fuga_claves_log.txt`](prueba_fuga_claves_log.txt) demuestra que
cuando `fn_autenticar` se invoca con literales, **la contraseña en claro queda en la línea
`STATEMENT`** del log crudo; con consultas parametrizadas (`$1, $2`) no aparece. También
quedan mails, IP y, con `log_statement` en `ddl`/`mod`, cualquier `ALTER ROLE … PASSWORD
'…'`. Por eso el archivo solo debería poder leerlo la cuenta de servicio del motor y, para
investigar, un rol auditor (permisos de SO `0600`, o `0640` con un grupo de auditoría
dedicado; `log_file_mode` del motor). Dentro del motor, la lectura de archivos del servidor
(`pg_read_server_files`, `pg_read_file`) no se concede a ningún rol de la aplicación, y el
log debería enviarse a un repositorio central de solo-agregado, fuera del alcance del DBA.
