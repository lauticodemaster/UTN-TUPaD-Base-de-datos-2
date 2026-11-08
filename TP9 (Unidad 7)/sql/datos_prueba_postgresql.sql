-- TP Unidad 7 - Datos de prueba en PostgreSQL (Food Store)
-- Requisito previo: TP1/schema.sql, TP1/objects.sql (sin el bloque "-- PRUEBA.") y TP1/data.sql.
--
-- La base de desarrollo tiene 3 pedidos (ids 1-3). La consigna pide al menos 5, así que
-- se agregan 4 pedidos DE PRUEBA (ids 4-7) usando el procedimiento sp_crear_pedido del
-- propio Food Store: valida usuario, disponibilidad y stock, congela precio_unitario
-- (trigger trg_subtotal) y recalcula el total (trg_total_ins). Ningún importe se escribe a mano.

SET search_path TO foodstore;

-- Los pedidos 1-3 conservan la fecha que tienen en el backup del equipo
-- (TP1/database/backups/foodstore_backup.sql).
UPDATE pedido SET fecha = DATE '2026-09-01' WHERE id IN (1, 2, 3);

-- Pedido 4 (prueba): Juliana - pizza, gaseosa y brownies
CALL sp_crear_pedido(2, 'TARJETA',
    '[{"producto_id":3,"cantidad":1},{"producto_id":7,"cantidad":2},{"producto_id":10,"cantidad":2}]');
-- Pedido 5 (prueba): Ramón - docena de empanadas y gaseosa
CALL sp_crear_pedido(4, 'EFECTIVO',
    '[{"producto_id":4,"cantidad":6},{"producto_id":6,"cantidad":4},{"producto_id":7,"cantidad":1}]');
-- Pedido 6 (prueba): Miguel - ensalada y jugos
CALL sp_crear_pedido(1, 'TRANSFERENCIA',
    '[{"producto_id":12,"cantidad":1},{"producto_id":8,"cantidad":2}]');
-- Pedido 7 (prueba): Iván - pizzas, gaseosa y flan
CALL sp_crear_pedido(3, 'EFECTIVO',
    '[{"producto_id":2,"cantidad":2},{"producto_id":7,"cantidad":1},{"producto_id":9,"cantidad":1}]');

-- sp_crear_pedido crea los pedidos como PENDIENTE con la fecha del día;
-- se les asigna una fecha y un estado del ciclo de vida del dominio.
UPDATE pedido SET fecha = DATE '2026-10-14', estado = 'CONFIRMADO' WHERE id = 4;
UPDATE pedido SET fecha = DATE '2026-10-21', estado = 'TERMINADO'  WHERE id = 5;
UPDATE pedido SET fecha = DATE '2026-10-30', estado = 'CANCELADO'  WHERE id = 6;
UPDATE pedido SET fecha = DATE '2026-11-02', estado = 'TERMINADO'  WHERE id = 7;

-- Control: el total guardado debe coincidir con la suma de subtotales vigentes.
SELECT p.id, p.fecha, p.estado, p.total,
       calcular_total_pedido(p.id) AS total_recalculado,
       p.total = calcular_total_pedido(p.id) AS coincide
FROM   pedido p
ORDER  BY p.id;
