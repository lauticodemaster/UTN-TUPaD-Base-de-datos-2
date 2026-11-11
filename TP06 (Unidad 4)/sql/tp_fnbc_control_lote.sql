-- =============================================================================
-- TP Unidad 4 · Parte 1 — FNBC sobre control_lote_almacen
-- Entregable: tp_fnbc_control_lote.sql
--   1. esquema original + instancia de ejemplo
--   2. validación de las dependencias funcionales sobre los datos reales
--   3. tablas descompuestas (FNBC) + salvaguarda de la FD no preservada
--   4. vista de compatibilidad (reunión natural)
--   5. migración SIN PÉRDIDA dentro de una transacción reversible, con
--      verificación que aborta (ROLLBACK automático) si algo no cierra
--
-- Spec de Kiro que gobierna este script: ../specs/kiro/requirements.md,
-- design.md y tasks.md (incluye el plan de reversión obligatorio).
-- Plan de reversión ejecutable: rollback_fnbc_control_lote.sql
--
-- Protocolo (TP01/protocolo_seguridad.md): correr primero sobre foodstore_test,
-- con respaldo previo de foodstore.
-- Uso:  psql -d foodstore_test -v ON_ERROR_STOP=1 -f tp_fnbc_control_lote.sql
-- =============================================================================

SET search_path TO foodstore;

-- -----------------------------------------------------------------------------
-- 1) Maestras mínimas de la extensión mayorista (la consigna las asume
--    existentes; se crean solo si faltan) + esquema original + instancia
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lote     (id BIGINT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS deposito (id BIGINT PRIMARY KEY);

INSERT INTO lote(id)     VALUES (501),(502),(503) ON CONFLICT DO NOTHING;
INSERT INTO deposito(id) VALUES (30),(31),(32)    ON CONFLICT DO NOTHING;

-- Esquema heredado (con la redundancia que viola FNBC)
CREATE TABLE IF NOT EXISTS control_lote_almacen (
    lote_id                BIGINT NOT NULL REFERENCES lote(id),
    deposito_id            BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO control_lote_almacen VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- MIGRACIÓN — todo lo que sigue es UNA transacción. Si cualquier verificación
-- falla, RAISE EXCEPTION aborta y PostgreSQL revierte todo: la base queda
-- exactamente como estaba (el esquema heredado no se toca nunca).
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- 2) Validación de las FD contra los DATOS REALES (no solo contra el enunciado)
--    F1: {lote, deposito} -> responsable   (garantizada por la PK heredada)
--    F2: responsable -> deposito           (NO garantizada: hay que medirla)
--    Si F2 no se cumple en los datos, descomponer perdería información:
--    se aborta y se reporta para revisión humana.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_violaciones INT;
BEGIN
    SELECT count(*) INTO v_violaciones
    FROM (SELECT responsable_control_id
          FROM   control_lote_almacen
          GROUP  BY responsable_control_id
          HAVING count(DISTINCT deposito_id) > 1) x;

    IF v_violaciones > 0 THEN
        RAISE EXCEPTION 'F2 (responsable -> deposito) no se cumple en % responsables: migración abortada', v_violaciones;
    END IF;
    RAISE NOTICE 'Validación FD: F2 se cumple en los datos (0 responsables con >1 depósito)';
END $$;

-- -----------------------------------------------------------------------------
-- 3) Descomposición FNBC sobre la FD violatoria F2
--    R1 = (responsable_control_id, deposito_id)      -> dato maestro
--    R2 = (lote_id, responsable_control_id)          -> hecho operativo
-- -----------------------------------------------------------------------------
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
    deposito_id            BIGINT NOT NULL REFERENCES deposito(id),
    CONSTRAINT pk_responsable_deposito PRIMARY KEY (responsable_control_id),
    -- clave alternativa necesaria para la FK compuesta de control_lote
    CONSTRAINT uq_responsable_deposito UNIQUE (responsable_control_id, deposito_id)
);

CREATE TABLE control_lote (
    lote_id                BIGINT NOT NULL REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
    CONSTRAINT pk_control_lote PRIMARY KEY (lote_id, responsable_control_id)
);

-- Salvaguarda: la descomposición FNBC NO preserva F1
-- ({lote, deposito} -> responsable): con solo las claves, un mismo lote podría
-- recibir dos responsables del MISMO depósito. Un trigger restituye la regla.
CREATE OR REPLACE FUNCTION fn_chk_f1_control_lote()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   control_lote cl
        JOIN   responsable_deposito rd  ON rd.responsable_control_id = cl.responsable_control_id
        JOIN   responsable_deposito rdn ON rdn.responsable_control_id = NEW.responsable_control_id
        WHERE  cl.lote_id = NEW.lote_id
          AND  cl.responsable_control_id <> NEW.responsable_control_id
          AND  rd.deposito_id = rdn.deposito_id
    ) THEN
        RAISE EXCEPTION 'F1 violada: el lote % ya tiene responsable en ese depósito', NEW.lote_id;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_chk_f1_control_lote
BEFORE INSERT OR UPDATE ON control_lote
FOR EACH ROW EXECUTE FUNCTION fn_chk_f1_control_lote();

-- -----------------------------------------------------------------------------
-- 4) Vista de compatibilidad: reconstruye la relación original por reunión
--    natural sobre el atributo común (responsable_control_id)
-- -----------------------------------------------------------------------------
CREATE VIEW v_control_lote_almacen AS
SELECT cl.lote_id, rd.deposito_id, cl.responsable_control_id
FROM   control_lote cl
NATURAL JOIN responsable_deposito rd;

-- -----------------------------------------------------------------------------
-- 5) Migración de datos desde el esquema heredado
-- -----------------------------------------------------------------------------
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM   control_lote_almacen;

INSERT INTO control_lote (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM   control_lote_almacen;

-- -----------------------------------------------------------------------------
-- 6) Verificación de equivalencia (sin pérdida y sin tuplas espurias):
--    original EXCEPT vista  = 0  (nada se perdió)
--    vista EXCEPT original  = 0  (nada se inventó)
--    conteos iguales
--    Si falla, se aborta la transacción completa.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_perdidas  INT;
    v_espurias  INT;
    v_n_orig    INT;
    v_n_vista   INT;
BEGIN
    SELECT count(*) INTO v_perdidas FROM (
        SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen) a;
    SELECT count(*) INTO v_espurias FROM (
        SELECT lote_id, deposito_id, responsable_control_id FROM v_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id FROM control_lote_almacen) b;
    SELECT count(*) INTO v_n_orig  FROM control_lote_almacen;
    SELECT count(*) INTO v_n_vista FROM v_control_lote_almacen;

    RAISE NOTICE 'Verificación: original=% vista=% perdidas=% espurias=%',
                 v_n_orig, v_n_vista, v_perdidas, v_espurias;

    IF v_perdidas <> 0 OR v_espurias <> 0 OR v_n_orig <> v_n_vista THEN
        RAISE EXCEPTION 'Migración NO equivalente: se aborta (ROLLBACK)';
    END IF;
END $$;

SELECT * FROM v_control_lote_almacen ORDER BY lote_id;

-- Se confirma solo porque la verificación anterior pasó (si no, ya abortó).
COMMIT;

-- =============================================================================
-- 7) Pruebas posteriores: las anomalías de la Parte 1 d) ya no existen.
--    Cada prueba corre en su propia transacción y se revierte.
-- =============================================================================

-- 7.a Inserción: se registra el responsable 803 en el depósito 32 sin lote.
BEGIN;
INSERT INTO responsable_deposito VALUES (803, 32);
SELECT 'insercion_sin_lote_ok' AS prueba, count(*) AS filas
FROM responsable_deposito WHERE responsable_control_id = 803;
ROLLBACK;

-- 7.b Actualización: mover 801 al depósito 31 es UNA fila (antes eran dos).
BEGIN;
UPDATE responsable_deposito SET deposito_id = 31 WHERE responsable_control_id = 801;
SELECT 'actualizacion_una_fila' AS prueba, lote_id, deposito_id
FROM v_control_lote_almacen WHERE responsable_control_id = 801 ORDER BY lote_id;
ROLLBACK;

-- 7.c Salvaguarda F1: un segundo responsable del depósito 30 para el lote 501
--     debe ser rechazado por el trigger.
BEGIN;
INSERT INTO responsable_deposito VALUES (804, 30);
SAVEPOINT antes_de_violar_f1;
DO $$
BEGIN
    INSERT INTO control_lote VALUES (501, 804);
    RAISE EXCEPTION 'ERROR DE DISEÑO: el trigger F1 no rechazó la fila';
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'F1 violada%' THEN
        RAISE NOTICE 'Salvaguarda F1 OK: %', SQLERRM;
    ELSE
        RAISE;
    END IF;
END $$;
ROLLBACK;
