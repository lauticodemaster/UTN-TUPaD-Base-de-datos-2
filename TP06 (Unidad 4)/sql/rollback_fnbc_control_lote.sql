-- =============================================================================
-- TP Unidad 4 · Plan de reversión de la migración FNBC (obligatorio por spec)
--
-- Cuándo se usa: si, ya confirmada la migración (COMMIT), aparece un problema
-- en producción durante el período de convivencia. El esquema heredado
-- control_lote_almacen NO se elimina en la migración, por lo que la reversión
-- es sin pérdida: se sincroniza primero cualquier alta hecha sobre las tablas
-- nuevas y luego se eliminan los objetos nuevos.
--
-- Si la migración falla ANTES del COMMIT no hace falta este script:
-- PostgreSQL revierte la transacción completa.
--
-- Uso: psql -d foodstore_test -v ON_ERROR_STOP=1 -f rollback_fnbc_control_lote.sql
-- =============================================================================

SET search_path TO foodstore;

BEGIN;

-- 1) Devolver al esquema heredado lo que se haya cargado en el nuevo.
--    Si un (lote, deposito) ya existe con OTRO responsable, se aborta: es un
--    conflicto que decide una persona, no el script.
DO $$
DECLARE v_conflictos INT;
BEGIN
    SELECT count(*) INTO v_conflictos
    FROM   v_control_lote_almacen v
    JOIN   control_lote_almacen o USING (lote_id, deposito_id)
    WHERE  o.responsable_control_id <> v.responsable_control_id;
    IF v_conflictos > 0 THEN
        RAISE EXCEPTION 'Reversión abortada: % conflictos (lote,deposito) con distinto responsable', v_conflictos;
    END IF;
END $$;

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
SELECT lote_id, deposito_id, responsable_control_id
FROM   v_control_lote_almacen
ON CONFLICT (lote_id, deposito_id) DO NOTHING;

-- 2) Eliminar los objetos introducidos por la migración (orden inverso)
DROP VIEW     IF EXISTS v_control_lote_almacen;
DROP TRIGGER  IF EXISTS trg_chk_f1_control_lote ON control_lote;
DROP FUNCTION IF EXISTS fn_chk_f1_control_lote();
DROP TABLE    IF EXISTS control_lote;
DROP TABLE    IF EXISTS responsable_deposito;

-- 3) Comprobación: el esquema heredado sigue entero
SELECT count(*) AS filas_control_lote_almacen FROM control_lote_almacen;

COMMIT;
