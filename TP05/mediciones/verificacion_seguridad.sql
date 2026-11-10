-- ============================================================================
-- TP5 - Prueba de la vista de seguridad v_usuarios_publico (Parte B, punto 4)
-- ============================================================================
SET search_path TO foodstore;

\echo '--- (a) la vista NO expone contrasena: esto TIENE que fallar ---'
SELECT contrasena FROM v_usuarios_publico LIMIT 1;

\echo '--- (b) app_lectura puede leer la vista ---'
SET ROLE app_lectura;
SELECT id, nombre, apellido, rol FROM v_usuarios_publico ORDER BY id LIMIT 3;

\echo '--- (c) app_lectura NO puede leer la tabla base: esto TIENE que fallar ---'
SELECT id, nombre FROM usuario ORDER BY id LIMIT 3;

RESET ROLE;
\echo '--- (d) permisos efectivos sobre la tabla y sobre la vista ---'
SELECT has_table_privilege('app_lectura', 'foodstore.usuario', 'SELECT')            AS puede_leer_tabla,
       has_table_privilege('app_lectura', 'foodstore.v_usuarios_publico', 'SELECT') AS puede_leer_vista;
