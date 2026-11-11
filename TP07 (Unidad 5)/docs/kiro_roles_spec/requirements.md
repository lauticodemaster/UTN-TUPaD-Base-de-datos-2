# Requirements — Roles y permisos de Food Store (mínimo privilegio)

> Spec en formato Kiro, redactada **antes** de escribir `sql/roles.sql`.

## Introducción
Food Store accede a PostgreSQL desde la aplicación web, el equipo de soporte, los reportes
de negocio y un administrador de datos. Cada actor debe tener solo los privilegios que su
operación exige. Toda concesión debe estar justificada aquí antes de aparecer en el SQL.

## Requisito 1 — Roles de grupo (NOLOGIN)
| Rol | Qué habilita | Por qué eso y no otra cosa |
|---|---|---|
| `rol_app_lectura` | SELECT sobre catálogo, pedidos y detalle, y sobre `usuario` **solo** en las columnas no secretas | La tienda muestra catálogo, historial y perfil; nunca necesita leer `contrasena` |
| `rol_app_escritura` | INSERT/UPDATE sobre `pedido` y `detalle_pedido`; INSERT en `usuario` **sin la columna `rol`**; UPDATE de nombre/apellido/celular | Alta de pedidos y registro de clientes. Excluir `rol` impide que la app cree usuarios ADMIN. Sin DELETE: la baja es lógica |
| `rol_soporte` | SELECT sobre pedidos y sobre columnas de contacto de `usuario`; UPDATE de `pedido.estado`; EXECUTE de `fn_resetear_password` | Atiende reclamos y destraba cuentas sin ver contraseñas ni poder borrar |
| `rol_reportes` | SELECT sobre las vistas de reporte, `mv_facturacion_categoria_mes`, `venta_categoria_dia` y `usuario_anon` | El análisis trabaja sobre agregados y datos anonimizados, no sobre PII |
| `rol_auditor` *(agregado por el equipo)* | SELECT sobre `auditoria_login` | Quien investiga incidentes debe poder leer la evidencia sin poder alterarla ni leer datos de negocio |

## Requisito 2 — Roles de login
| Rol | Miembro de | Justificación |
|---|---|---|
| `app_web` | `rol_app_lectura`, `rol_app_escritura` + EXECUTE `fn_autenticar` | Cuenta técnica de la aplicación; autentica clientes solo a través de la función |
| `admin_datos` | dueño del esquema (sin SUPERUSER) | Ejecuta migraciones y mantenimiento; no administra el clúster |
| `soporte_ops` *(agregado)* | `rol_soporte` | Credencial nominal del equipo de soporte para trazar acciones humanas |
| `reportes_bi` *(agregado)* | `rol_reportes` | Credencial de la herramienta de BI |

## Requisito 3 — Denegación por defecto
1. `PUBLIC` NO DEBERÁ tener CONNECT a la base, CREATE en ningún esquema ni EXECUTE sobre funciones.
2. Ningún rol de login, salvo `admin_datos`, DEBERÁ poder crear objetos.
3. Ningún rol DEBERÁ tener `WITH GRANT OPTION` ni `ADMIN OPTION` sobre `admin_datos`.
4. Las tablas y funciones que `admin_datos` cree en el futuro DEBERÁN heredar esta política (`ALTER DEFAULT PRIVILEGES`).

## Requisito 4 — Verificación
1. CUANDO se aplique `roles.sql`, el equipo DEBERÁ verificar con `\du` y con
   `information_schema.role_table_grants` / `column_privileges` que cada rol tiene
   exactamente lo de esta spec.
2. SI un rol de bajo privilegio intenta obtener membresía en `admin_datos`, ENTONCES el
   motor DEBERÁ rechazarlo.

## Requisito 5 — Auditoría
1. El servidor DEBERÁ registrar conexiones, desconexiones y sentencias de modificación.
2. Cada intento de autenticación de cliente DEBERÁ quedar registrado en `auditoria_login`, sin la contraseña.
3. Las sesiones de `soporte_ops` (credencial humana privilegiada) DEBERÁN registrarse con `log_statement = 'all'`.
