-- =============================================================================
-- TP Unidad 5 · Parte C — Simulacro de incidente de acceso indebido
-- SOLO contra el entorno de desarrollo propio (foodstore_test).
-- Orquestación: simulacro_incidente.sh (recorta el log y lo anonimiza).
--
-- Escenario (lo conoce el equipo, NO se le da a la IA):
--   Un empleado de soporte (credencial soporte_ops) abusa de su acceso:
--   1. prueba claves de un cliente a través de la aplicación (fn_autenticar
--      vía la cuenta técnica app_web): 4 fallos y 1 éxito;
--   2. hace una lectura masiva de usuario con su credencial de soporte, e
--      intenta leer contrasena;
--   3. intenta escalar: GRANT admin_datos y SET ROLE admin_datos (motor), y
--      resetear la contraseña de un usuario ADMIN de la aplicación para luego
--      entrar como ese ADMIN.
-- Contraseñas de los logins: en PGPASSFILE (fuera de Git).
-- Datos: solo usuarios sintéticos de la carga masiva de TP03.
-- =============================================================================

\set ON_ERROR_STOP off
\set objetivo_cliente 'usuario5@mailmasivo.com'
\set objetivo_admin_id 25
\set objetivo_admin_mail 'usuario20@mailmasivo.com'

-- ---------------------------------------------------------------- paso 1
\connect foodstore_test app_web 127.0.0.1 55432
SET application_name = 'psql';
SELECT fn_autenticar(:'objetivo_cliente', 'Password123')   AS intento_1;
SELECT fn_autenticar(:'objetivo_cliente', 'Qwerty2026')    AS intento_2;
SELECT fn_autenticar(:'objetivo_cliente', 'ClaveSegura')   AS intento_3;
SELECT fn_autenticar(:'objetivo_cliente', 'ClaveSegura4')  AS intento_4;
SELECT fn_autenticar(:'objetivo_cliente', 'ClaveSegura5')  AS intento_5_exitoso;

-- ---------------------------------------------------------------- paso 2
\connect foodstore_test soporte_ops 127.0.0.1 55432
SET application_name = 'psql';
SELECT count(*) AS filas_leidas FROM (
    SELECT id, nombre, apellido, mail, celular FROM foodstore.usuario
) volcado;
SELECT id, mail, contrasena FROM foodstore.usuario LIMIT 10;

-- ---------------------------------------------------------------- paso 3
GRANT admin_datos TO soporte_ops;
SET ROLE admin_datos;
SELECT foodstore.fn_resetear_password(:objetivo_admin_id) AS clave_temporal \gset
\echo 'reset sobre ADMIN devolvió clave temporal:' :{?clave_temporal}

\connect foodstore_test app_web 127.0.0.1 55432
SET application_name = 'psql';
\if :{?clave_temporal}
SELECT fn_autenticar(:'objetivo_admin_mail', :'clave_temporal') AS login_como_admin;
\else
\echo 'sin clave temporal: no hay login como ADMIN'
\endif
