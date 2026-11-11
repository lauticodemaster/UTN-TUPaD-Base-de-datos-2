# Design — Roles y permisos de Food Store

## Jerarquía
```
                 admin_datos (LOGIN, dueño del esquema foodstore, NOSUPERUSER)
                        │ es dueño de tablas, vistas y funciones
 ┌──────────────┬───────┴────────┬──────────────┬─────────────┐
 rol_app_lectura rol_app_escritura rol_soporte   rol_reportes  rol_auditor   (NOLOGIN)
   └──────┬──────────┘              │              │             │
       app_web                  soporte_ops    reportes_bi    (asignación nominal)
```

## Matriz objeto × rol
| Objeto | lectura | escritura | soporte | reportes | auditor |
|---|---|---|---|---|---|
| `categoria`, `producto` | SELECT | — | SELECT | — | — |
| `pedido` | SELECT | INSERT, UPDATE(estado, forma_pago, eliminado) | SELECT, UPDATE(estado) | — | — |
| `detalle_pedido` | SELECT | INSERT, UPDATE(cantidad, eliminado) | SELECT | — | — |
| `usuario` | SELECT(id, nombre, apellido, mail, celular, rol, eliminado, created_at) | INSERT(nombre, apellido, mail, celular, contrasena), UPDATE(nombre, apellido, celular) | SELECT(id, nombre, apellido, mail, celular, eliminado, created_at) | — | — |
| `usuario.contrasena` | **nunca** | solo INSERT (alta), se guarda hash | **nunca** | — | — |
| vistas `v_*`, `mv_*`, `venta_categoria_dia`, `usuario_anon` | — | — | — | SELECT | — |
| `auditoria_login` | — | — | — | — | SELECT |
| `fn_autenticar` | app_web | | | | |
| `fn_resetear_password` | | | EXECUTE | | |

Notas de diseño:
- La columna `rol` de `usuario` NO está en el INSERT de la app: el default `'USUARIO'` impide escalar a ADMIN desde el registro.
- `UPDATE` sobre `pedido.total` no se concede: lo mantienen los triggers, que corren con los privilegios del dueño.
- Sin DELETE para nadie salvo `admin_datos`: las bajas son lógicas (`eliminado`).
- `CONNECTION LIMIT` en las cuentas de login para acotar el abuso de una credencial robada.
- Contraseñas de login: `PASSWORD NULL` en el script; se fijan fuera de Git con `\password`.

## Auditoría
| Capa | Mecanismo | Qué responde |
|---|---|---|
| Servidor | `log_connections`, `log_disconnections`, `log_statement='mod'`, `log_line_prefix='%m [%p] user=%u db=%d host=%h app=%a '` | quién se conectó, desde dónde, qué modificó y cuándo |
| Sesiones humanas privilegiadas | `ALTER ROLE soporte_ops SET log_statement='all'` | también las lecturas del personal de soporte |
| Aplicación | `auditoria_login` + `RAISE LOG` en `fn_autenticar` | intentos de login de clientes (no visibles para el motor como conexiones) |
