-- TP U4 · Pruebas del mecanismo de sincronización de venta_categoria_dia.
-- Todo corre en UNA transacción que se revierte al final: la base no cambia.
SET search_path TO foodstore;
\set auditar 'SELECT count(*) AS filas_desincronizadas FROM (' :'q' ') x;'
BEGIN;

-- caso 1: alta de pedido de hoy con dos líneas
INSERT INTO pedido (forma_pago, usuario_id) VALUES ('EFECTIVO', 1) RETURNING id AS nuevo_pedido \gset
INSERT INTO detalle_pedido (cantidad, pedido_id, producto_id) VALUES (3, :nuevo_pedido, 1), (2, :nuevo_pedido, 7);
\echo 'caso 1 - alta de pedido con 2 lineas'
\i auditoria_venta_categoria_dia.sql

-- caso 2: cambio de cantidad
UPDATE detalle_pedido SET cantidad = 10 WHERE pedido_id = :nuevo_pedido AND producto_id = 1;
\echo 'caso 2 - update de cantidad'
\i auditoria_venta_categoria_dia.sql

-- caso 3: baja lógica de una línea (DELETE -> soft delete)
DELETE FROM detalle_pedido WHERE pedido_id = :nuevo_pedido AND producto_id = 7;
\echo 'caso 3 - baja logica de una linea'
\i auditoria_venta_categoria_dia.sql

-- caso 4: el pedido cambia de fecha (de hoy a ayer)
UPDATE pedido SET fecha = CURRENT_DATE - 1 WHERE id = :nuevo_pedido;
\echo 'caso 4 - cambio de fecha del pedido'
\i auditoria_venta_categoria_dia.sql

-- caso 5: baja lógica del pedido completo
DELETE FROM pedido WHERE id = :nuevo_pedido;
\echo 'caso 5 - baja logica del pedido'
\i auditoria_venta_categoria_dia.sql

-- caso 6: un producto con ventas cambia de categoría
UPDATE producto SET categoria_id = CASE WHEN categoria_id = 1 THEN 2 ELSE 1 END WHERE id = 7;
\echo 'caso 6 - cambio de categoria de producto'
\i auditoria_venta_categoria_dia.sql

-- caso 7: TRUNCATE de la fuente debe ser rechazado
SAVEPOINT s7;
\echo 'caso 7 - TRUNCATE detalle_pedido (debe fallar)'
TRUNCATE detalle_pedido CASCADE;
ROLLBACK TO SAVEPOINT s7;

-- caso 8 (control negativo): se corrompe a mano una celda; la auditoria DEBE detectarla
UPDATE venta_categoria_dia SET total_vendido = total_vendido + 1 WHERE fecha = CURRENT_DATE AND categoria_id = 1;
\echo 'caso 8 - corrupcion deliberada (la auditoria debe devolver 1 fila)'
\i auditoria_venta_categoria_dia.sql

ROLLBACK;
