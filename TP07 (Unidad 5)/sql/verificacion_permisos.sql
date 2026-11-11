-- TP Unidad 5 · Parte A.3 — verificación de permisos (salida en docs/salida_verificacion_permisos.txt)
-- Uso: psql -d foodstore_test -f verificacion_permisos.sql
SET search_path TO foodstore;

\echo '=== \\du (roles del proyecto) ==='
\du rol_*|app_web|admin_datos|soporte_ops|reportes_bi

\echo '=== Membresías (con/sin ADMIN OPTION) ==='
SELECT m.rolname AS miembro, r.rolname AS rol, a.admin_option
FROM   pg_auth_members a
JOIN   pg_roles r ON r.oid = a.roleid
JOIN   pg_roles m ON m.oid = a.member
WHERE  m.rolname IN ('app_web','admin_datos','soporte_ops','reportes_bi')
ORDER  BY 1, 2;

\echo '=== Privilegios de tabla (information_schema.role_table_grants) ==='
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios,
       bool_or(is_grantable = 'YES') AS con_grant_option
FROM   information_schema.role_table_grants
WHERE  table_schema = 'foodstore'
  AND  grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
                   'rol_auditor','app_web','soporte_ops','reportes_bi','PUBLIC')
GROUP  BY grantee, table_name
ORDER  BY grantee, table_name;

\echo '=== Vistas materializadas (information_schema no las lista) ==='
SELECT r.rolname, has_table_privilege(r.rolname, 'foodstore.mv_facturacion_categoria_mes', 'SELECT') AS select_mv
FROM   pg_roles r
WHERE  r.rolname IN ('rol_reportes','rol_app_lectura','rol_soporte','app_web')
ORDER  BY 1;

\echo '=== Privilegios de columna sobre usuario (information_schema.column_privileges) ==='
SELECT grantee, privilege_type, string_agg(column_name, ', ' ORDER BY column_name) AS columnas
FROM   information_schema.column_privileges
WHERE  table_schema = 'foodstore' AND table_name = 'usuario'
  AND  grantee LIKE 'rol_%'
  AND  (grantee, privilege_type) NOT IN (SELECT grantee, privilege_type
                                         FROM information_schema.role_table_grants
                                         WHERE table_schema='foodstore' AND table_name='usuario')
GROUP  BY grantee, privilege_type
ORDER  BY grantee, privilege_type;

\echo '=== ¿Alguien que no sea admin_datos puede leer usuario.contrasena? (esperado: solo admin_datos) ==='
SELECT r.rolname
FROM   pg_roles r
WHERE  r.rolname IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes','rol_auditor',
                     'app_web','soporte_ops','reportes_bi','admin_datos')
  AND  has_column_privilege(r.rolname, 'foodstore.usuario', 'contrasena', 'SELECT')
ORDER  BY 1;

\echo '=== EXECUTE sobre funciones sensibles ==='
SELECT r.rolname,
       has_function_privilege(r.rolname, 'foodstore.fn_autenticar(text,text)', 'EXECUTE')     AS fn_autenticar,
       has_function_privilege(r.rolname, 'foodstore.fn_resetear_password(bigint)', 'EXECUTE') AS fn_resetear_password
FROM   pg_roles r
WHERE  r.rolname IN ('app_web','soporte_ops','reportes_bi','admin_datos')
UNION ALL
SELECT 'PUBLIC',
       EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               WHERE p.oid = 'foodstore.fn_autenticar(text,text)'::regprocedure AND a.grantee = 0),
       EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               WHERE p.oid = 'foodstore.fn_resetear_password(bigint)'::regprocedure AND a.grantee = 0)
ORDER  BY 1;

\echo '=== Default privileges ==='
\ddp

\echo '=== Pruebas negativas (cada una debe FALLAR con permission denied) ==='
SET ROLE app_web;
\set ON_ERROR_STOP off
SELECT contrasena FROM usuario LIMIT 1;
INSERT INTO usuario (nombre, apellido, mail, contrasena, rol) VALUES ('X','Y','x@y.test','12345678','ADMIN');
DELETE FROM pedido WHERE id = 1;
CREATE TABLE foodstore.tabla_intrusa (id int);
RESET ROLE;
SET ROLE reportes_bi;
SELECT count(*) FROM usuario;
RESET ROLE;
SET ROLE soporte_ops;
UPDATE pedido SET total = 0 WHERE id = 1;
RESET ROLE;

\echo '=== Pruebas positivas (cada una debe FUNCIONAR, en transacción revertida) ==='
BEGIN;
SET ROLE app_web;
INSERT INTO usuario (nombre, apellido, mail, contrasena) VALUES ('Prueba','Permisos','prueba.permisos@anon.example','HashDePrueba123') RETURNING id, rol;
INSERT INTO pedido (forma_pago, usuario_id) VALUES ('EFECTIVO', 1) RETURNING id AS pid \gset
INSERT INTO detalle_pedido (cantidad, pedido_id, producto_id) VALUES (2, :pid, 1);
SELECT id, total FROM pedido WHERE id = :pid;      -- total recalculado por trigger SECURITY DEFINER
RESET ROLE;
SET ROLE reportes_bi;
SELECT count(*) AS filas_usuario_anon FROM usuario_anon;
RESET ROLE;
ROLLBACK;
