-- Costo de los indices sobre las escrituras (Parte A, punto 5).
-- 500 sentencias INSERT individuales sobre detalle_pedido, dentro de una
-- transaccion que se revierte: la medicion no deja datos en la base.
-- Se corre igual antes y despues de crear los indices nuevos; los triggers
-- (trg_subtotal y trg_total_ins) estan activos en las dos corridas, asi que
-- su costo es constante y la diferencia es mantenimiento de indices.
SET search_path TO foodstore;
BEGIN;
DO $$
DECLARE
    v_pedido BIGINT;
    t0 TIMESTAMPTZ;
    t1 TIMESTAMPTZ;
    i  INT;
BEGIN
    INSERT INTO pedido (fecha, estado, forma_pago, usuario_id)
    VALUES (CURRENT_DATE, 'PENDIENTE', 'EFECTIVO', 1)
    RETURNING id INTO v_pedido;

    t0 := clock_timestamp();
    FOR i IN 1..500 LOOP
        INSERT INTO detalle_pedido (cantidad, precio_unitario, subtotal,
                                    pedido_id, producto_id)
        VALUES (1, 100.00, 0, v_pedido, i);
    END LOOP;
    t1 := clock_timestamp();

    RAISE NOTICE 'carga de 500 INSERT: % ms',
        round((extract(epoch FROM (t1 - t0)) * 1000)::numeric, 1);
END $$;
ROLLBACK;
