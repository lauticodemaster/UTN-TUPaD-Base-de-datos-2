-- =============================================================================
-- TP Unidad 5 · Parte A — roles.sql (mínimo privilegio)
-- Spec previa: docs/kiro_roles_spec/requirements.md y design.md
-- Requiere: funciones_autenticacion.sql aplicado. Ejecutar como superusuario.
-- Idempotente: se puede volver a correr.
-- Contraseñas de login: NO van en Git. Después de correr el script:
--     \password app_web     \password admin_datos   (etc.)
-- Uso: psql -d foodstore_test -v ON_ERROR_STOP=1 -f roles.sql
-- =============================================================================

SET search_path TO foodstore;

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Creación de roles (CREATE ROLE no tiene IF NOT EXISTS)
-- -----------------------------------------------------------------------------
DO $$
DECLARE r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['rol_app_lectura','rol_app_escritura','rol_soporte',
                             'rol_reportes','rol_auditor'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
    FOREACH r IN ARRAY ARRAY['app_web','admin_datos','soporte_ops','reportes_bi'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I LOGIN PASSWORD NULL', r);
        END IF;
    END LOOP;
END $$;

-- Atributos explícitos: ninguno es superusuario ni crea roles/bases
ALTER ROLE admin_datos NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3;
ALTER ROLE app_web     NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 20;
ALTER ROLE soporte_ops NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 2;
ALTER ROLE reportes_bi NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 2;

-- Sesiones humanas privilegiadas: registro completo (spec Req. 5.3)
ALTER ROLE soporte_ops SET log_statement = 'all';

-- -----------------------------------------------------------------------------
-- 2) Denegación por defecto
-- -----------------------------------------------------------------------------
DO $$ BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO app_web, admin_datos, soporte_ops, reportes_bi',
                   current_database());
END $$;

REVOKE ALL ON SCHEMA public    FROM PUBLIC;
REVOKE ALL ON SCHEMA foodstore FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA foodstore FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA foodstore FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA foodstore FROM PUBLIC;

-- Rol heredado de TP05 (app_lectura) reemplazado por rol_reportes/rol_soporte
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_lectura') THEN
        REVOKE ALL ON ALL TABLES IN SCHEMA foodstore FROM app_lectura;
        REVOKE ALL ON SCHEMA foodstore FROM app_lectura;
        DROP ROLE app_lectura;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3) admin_datos: dueño del esquema y de sus objetos (sin SUPERUSER)
-- -----------------------------------------------------------------------------
ALTER SCHEMA foodstore OWNER TO admin_datos;
DO $$
DECLARE o RECORD;
BEGIN
    FOR o IN
        SELECT c.relname, c.relkind FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'foodstore' AND c.relkind IN ('r','v','m','p')
    LOOP
        EXECUTE format('ALTER %s foodstore.%I OWNER TO admin_datos',
            CASE o.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
            o.relname);
    END LOOP;
    FOR o IN
        SELECT p.oid::regprocedure AS firma, p.prokind FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'foodstore'
    LOOP
        EXECUTE format('ALTER %s %s OWNER TO admin_datos',
            CASE o.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, o.firma);
    END LOOP;
    FOR o IN
        SELECT t.typname FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'foodstore' AND t.typtype = 'e'
    LOOP
        EXECUTE format('ALTER TYPE foodstore.%I OWNER TO admin_datos', o.typname);
    END LOOP;
END $$;
GRANT USAGE ON SCHEMA public TO admin_datos;       -- pgcrypto (crypt, gen_salt)

-- Los triggers corren con los privilegios de QUIEN DISPARA la sentencia.
-- Para no conceder a app_web UPDATE(total) ni escritura en tablas derivadas,
-- las funciones de trigger que escriben otras tablas pasan a SECURITY DEFINER
-- (dueño admin_datos) con search_path fijo.
DO $$
DECLARE f TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY['fn_recalcular_total()','fn_vcd_detalle()','fn_vcd_pedido()',
                             'fn_vcd_producto()','fn_chk_f1_control_lote()'] LOOP
        IF to_regprocedure('foodstore.' || f) IS NOT NULL THEN
            EXECUTE format('ALTER FUNCTION foodstore.%s SECURITY DEFINER SET search_path = foodstore, pg_temp', f);
        END IF;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 4) Grupos
-- -----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA foodstore TO rol_app_lectura, rol_app_escritura,
                                   rol_soporte, rol_reportes, rol_auditor;

-- rol_app_lectura
GRANT SELECT ON categoria, producto, pedido, detalle_pedido TO rol_app_lectura;
GRANT SELECT (id, nombre, apellido, mail, celular, rol, eliminado, created_at)
      ON usuario TO rol_app_lectura;                     -- columna: SIN contrasena

-- rol_app_escritura
GRANT INSERT ON pedido, detalle_pedido TO rol_app_escritura;
GRANT UPDATE (estado, forma_pago, eliminado) ON pedido         TO rol_app_escritura;
GRANT UPDATE (cantidad, eliminado)           ON detalle_pedido TO rol_app_escritura;
GRANT INSERT (nombre, apellido, mail, celular, contrasena) ON usuario TO rol_app_escritura; -- SIN rol
GRANT UPDATE (nombre, apellido, celular)                   ON usuario TO rol_app_escritura;

-- rol_soporte
GRANT SELECT ON pedido, detalle_pedido, producto TO rol_soporte;
GRANT SELECT (id, nombre, apellido, mail, celular, eliminado, created_at) ON usuario TO rol_soporte;
GRANT UPDATE (estado) ON pedido TO rol_soporte;
GRANT EXECUTE ON FUNCTION fn_resetear_password(BIGINT) TO rol_soporte;

-- rol_reportes: solo estructuras agregadas o anonimizadas
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['v_productos_vigentes','v_categorias_vigentes','v_pedidos_resumen',
                             'mv_facturacion_categoria_mes','venta_categoria_dia','usuario_anon'] LOOP
        IF to_regclass('foodstore.' || t) IS NOT NULL THEN
            EXECUTE format('GRANT SELECT ON foodstore.%I TO rol_reportes', t);
        END IF;
    END LOOP;
END $$;

-- rol_auditor
GRANT SELECT ON auditoria_login TO rol_auditor;

-- -----------------------------------------------------------------------------
-- 5) Logins -> grupos (sin ADMIN OPTION)
-- -----------------------------------------------------------------------------
GRANT rol_app_lectura, rol_app_escritura TO app_web;
GRANT rol_soporte  TO soporte_ops;
GRANT rol_reportes TO reportes_bi;
GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT) TO app_web;

-- -----------------------------------------------------------------------------
-- 6) Política para objetos FUTUROS creados por admin_datos
-- -----------------------------------------------------------------------------
-- OJO: va SIN "IN SCHEMA". Los default privileges por esquema solo pueden
-- AGREGAR privilegios sobre el default global; un REVOKE ... IN SCHEMA no
-- quita el EXECUTE que PUBLIC recibe por defecto en toda función nueva.
-- (Hallazgo de la verificación: con IN SCHEMA, \ddp quedaba vacío.)
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- Tablas y secuencias no otorgan nada a PUBLIC por defecto: no hace falta revocar.
-- La política heredada es "denegar por defecto": NINGÚN grupo recibe nada
-- automáticamente sobre una tabla nueva (podría contener datos personales).
-- Cada tabla nueva se concede explícitamente después de actualizar la spec.

COMMIT;
