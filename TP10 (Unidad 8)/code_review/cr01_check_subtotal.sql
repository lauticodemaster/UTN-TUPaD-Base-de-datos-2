-- =============================================================================
-- Code review CR-01 (informe U8 §5): CHECK de coherencia del subtotal.
-- El informe de U8 registraba este hallazgo como "Aceptado / Corregido", pero la
-- restricción no estaba versionada en ningún script; este archivo la agrega.
-- Reversible: todo en una transacción; si hay filas que no cumplen, ADD CONSTRAINT
-- falla y no se aplica nada.
-- Uso: psql -d foodstore_test -v ON_ERROR_STOP=1 -f cr01_check_subtotal.sql
-- =============================================================================
SET search_path TO foodstore;

BEGIN;
-- Diagnóstico previo: filas que violarían la regla (esperado: 0)
SELECT count(*) AS filas_incoherentes
FROM   detalle_pedido
WHERE  subtotal <> cantidad * precio_unitario;

ALTER TABLE detalle_pedido
    ADD CONSTRAINT chk_detalle_subtotal_coherente
    CHECK (subtotal = cantidad * precio_unitario);
COMMIT;

-- Prueba negativa: un subtotal artificial debe ser rechazado. trg_subtotal
-- (BEFORE) recalcula NEW.subtotal, así que para probar el CHECK en sí se
-- desactiva solo ese trigger dentro de una transacción revertida.
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_subtotal;
SAVEPOINT prueba;
DO $$
BEGIN
    UPDATE detalle_pedido SET subtotal = subtotal + 1 WHERE id = 1;
    RAISE EXCEPTION 'ERROR: el CHECK no rechazó el subtotal artificial';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CR-01 OK, rechazado: %', SQLERRM;
END $$;
ROLLBACK;
