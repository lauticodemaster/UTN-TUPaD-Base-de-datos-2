-- =============================================================================
-- TP Unidad 5 · Reconstrucción de fn_autenticar y fn_resetear_password (Clase 2)
-- (los artefactos de clase no se conservaron; se reconstruyen como paso previo
--  a la Parte A, según lo pide la consigna; ver BITACORA.md)
--
-- Decisiones:
--  * Contraseñas con bcrypt (pgcrypto). Se migran las que estén en claro.
--  * Ambas funciones son SECURITY DEFINER con search_path fijo: la aplicación
--    NUNCA lee la columna contrasena; solo puede preguntar "¿coincide?".
--  * Cada intento queda en auditoria_login (rendición de cuentas) y en el log
--    del servidor vía RAISE LOG (registro técnico), SIN la contraseña.
--  * Bloqueo temporal: 5 fallos en 15 minutos bloquean el mail 15 minutos.
-- Uso: psql -d foodstore_test -v ON_ERROR_STOP=1 -f funciones_autenticacion.sql
-- =============================================================================

SET search_path TO foodstore;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

BEGIN;

-- 1) Migración de contraseñas en claro a bcrypt (idempotente)
UPDATE usuario
SET    contrasena = public.crypt(contrasena, public.gen_salt('bf', 8))
WHERE  contrasena NOT LIKE '$2%';

-- 2) Tabla de auditoría de autenticación (append-only para la aplicación)
CREATE TABLE IF NOT EXISTS auditoria_login (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ocurrido_en  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    mail_intento VARCHAR(160) NOT NULL,
    usuario_id   BIGINT,
    exito        BOOLEAN NOT NULL,
    motivo       TEXT NOT NULL,
    rol_db       NAME NOT NULL DEFAULT session_user,
    ip_origen    INET DEFAULT inet_client_addr()
);
CREATE INDEX IF NOT EXISTS idx_auditoria_login_mail_tiempo
    ON auditoria_login (mail_intento, ocurrido_en DESC);

-- 3) fn_autenticar
CREATE OR REPLACE FUNCTION fn_autenticar(p_mail TEXT, p_contrasena TEXT)
RETURNS BIGINT                      -- id del usuario si autentica, NULL si no
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = foodstore, pg_temp
AS $$
DECLARE
    v_id      BIGINT;
    v_hash    TEXT;
    v_fallos  INT;
BEGIN
    SELECT count(*) INTO v_fallos
    FROM   auditoria_login
    WHERE  mail_intento = lower(p_mail) AND NOT exito
      AND  ocurrido_en > clock_timestamp() - interval '15 minutes';

    IF v_fallos >= 5 THEN
        INSERT INTO auditoria_login (mail_intento, exito, motivo)
        VALUES (lower(p_mail), FALSE, 'BLOQUEADO');
        RAISE LOG 'fn_autenticar: BLOQUEADO mail=% fallos_15min=%', lower(p_mail), v_fallos;
        RETURN NULL;
    END IF;

    SELECT id, contrasena INTO v_id, v_hash
    FROM   usuario
    WHERE  lower(mail) = lower(p_mail) AND NOT eliminado;

    IF v_id IS NOT NULL AND public.crypt(p_contrasena, v_hash) = v_hash THEN
        INSERT INTO auditoria_login (mail_intento, usuario_id, exito, motivo)
        VALUES (lower(p_mail), v_id, TRUE, 'OK');
        RAISE LOG 'fn_autenticar: OK mail=% usuario_id=%', lower(p_mail), v_id;
        RETURN v_id;
    END IF;

    INSERT INTO auditoria_login (mail_intento, usuario_id, exito, motivo)
    VALUES (lower(p_mail), v_id, FALSE,
            CASE WHEN v_id IS NULL THEN 'MAIL_INEXISTENTE' ELSE 'CLAVE_INCORRECTA' END);
    RAISE LOG 'fn_autenticar: FALLO mail=% fallos_previos_15min=%', lower(p_mail), v_fallos;
    RETURN NULL;
END $$;

-- 4) fn_resetear_password (uso exclusivo de soporte)
CREATE OR REPLACE FUNCTION fn_resetear_password(p_usuario_id BIGINT)
RETURNS TEXT                         -- contraseña temporal, se muestra una sola vez
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = foodstore, pg_temp
AS $$
DECLARE
    v_temporal TEXT := encode(public.gen_random_bytes(9), 'base64');
BEGIN
    -- Corrección tras el simulacro (Parte C): soporte NO puede resetear
    -- cuentas ADMIN; eso permitía tomar una cuenta administrativa.
    IF EXISTS (SELECT 1 FROM usuario WHERE id = p_usuario_id AND rol = 'ADMIN') THEN
        INSERT INTO auditoria_login (mail_intento, usuario_id, exito, motivo)
        SELECT lower(mail), id, FALSE, 'RESET_ADMIN_DENEGADO_' || session_user FROM usuario WHERE id = p_usuario_id;
        RAISE LOG 'fn_resetear_password: DENEGADO usuario_id=% es ADMIN, por=%', p_usuario_id, session_user;
        RETURN NULL;
    END IF;
    UPDATE usuario
    SET    contrasena = public.crypt(v_temporal, public.gen_salt('bf', 8))
    WHERE  id = p_usuario_id AND NOT eliminado;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario % inexistente o eliminado', p_usuario_id;
    END IF;
    INSERT INTO auditoria_login (mail_intento, usuario_id, exito, motivo)
    SELECT lower(mail), id, TRUE, 'RESET_POR_' || session_user FROM usuario WHERE id = p_usuario_id;
    RAISE LOG 'fn_resetear_password: usuario_id=% por=%', p_usuario_id, session_user;
    RETURN v_temporal;
END $$;

-- Las funciones nacen con EXECUTE para PUBLIC: se revoca ya (los GRANT
-- puntuales están en roles.sql).
REVOKE ALL ON FUNCTION fn_autenticar(TEXT, TEXT)    FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_resetear_password(BIGINT) FROM PUBLIC;

COMMIT;
