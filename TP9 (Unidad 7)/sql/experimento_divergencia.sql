-- TP Unidad 7 - Experimento de divergencia (consigna 5)
-- Pregunta: ¿qué pasa si, después de migrar, se modifica un pedido en PostgreSQL?
-- Se da de baja (borrado lógico) la línea de Gaseosa 2L del pedido 5 y se repite la consulta c).
-- Todo corre dentro de una transacción con ROLLBACK, así que la base queda igual que antes.

SET search_path TO foodstore;
BEGIN;

-- El trigger trg_soft_delete_detalle_pedido convierte el DELETE en UPDATE eliminado = TRUE,
-- y trg_total_upd recalcula el total del pedido.
DELETE FROM detalle_pedido WHERE pedido_id = 5 AND producto_id = 7;

SELECT id, estado, total FROM pedido WHERE id = 5;

SELECT count(*) AS cantidad_con_producto_7,
       string_agg(p.id::text, ', ' ORDER BY p.id) AS ids
FROM   pedido p
WHERE  p.eliminado = FALSE
  AND  EXISTS (SELECT 1 FROM detalle_pedido d
               WHERE d.pedido_id = p.id AND d.producto_id = 7 AND d.eliminado = FALSE);

ROLLBACK;
