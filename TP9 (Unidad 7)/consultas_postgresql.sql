-- TP Unidad 7 - NoSQL | Food Store
-- Consultas en PostgreSQL equivalentes a los apartados b) y c) de MongoDB (consigna 5).
-- Requisito previo: TP1/schema.sql, TP1/objects.sql, TP1/data.sql y sql/datos_prueba_postgresql.sql.
--
-- Todas las consultas excluyen filas con borrado lógico (eliminado = TRUE), porque la
-- migración a MongoDB solo llevó pedidos y líneas vigentes. Sin ese filtro, ambos motores
-- podrían devolver conjuntos distintos.

SET search_path TO foodstore;

-- 0) Subconjunto migrado: pedidos vigentes y cantidad de líneas por pedido.
--    Debe coincidir con los 7 documentos y sus arreglos "lineas" en MongoDB.
SELECT p.id, p.estado, p.total, count(d.id) AS lineas
FROM   pedido p
JOIN   detalle_pedido d ON d.pedido_id = p.id AND d.eliminado = FALSE
WHERE  p.eliminado = FALSE
GROUP  BY p.id, p.estado, p.total
ORDER  BY p.id;

-- b) Pedidos con estado TERMINADO
--    MongoDB: db.pedidos.find({ estado: "TERMINADO" })
SELECT p.id, p.fecha, p.estado, p.total
FROM   pedido p
WHERE  p.estado = 'TERMINADO'
  AND  p.eliminado = FALSE
ORDER  BY p.id;

SELECT count(*) AS cantidad_terminados
FROM   pedido
WHERE  estado = 'TERMINADO' AND eliminado = FALSE;

-- c) Pedidos que contienen el producto 7 (Gaseosa 2L)
--    MongoDB: db.pedidos.find({ "lineas.producto_id": 7 })
--    Se usa EXISTS y no un JOIN para devolver cada pedido una sola vez, igual que find(),
--    que devuelve documentos y no líneas.
SELECT p.id, p.estado, d.id AS detalle_id, d.cantidad, d.precio_unitario, d.subtotal
FROM   pedido p
JOIN   detalle_pedido d ON d.pedido_id = p.id
WHERE  d.producto_id = 7
  AND  d.eliminado = FALSE
  AND  p.eliminado = FALSE
ORDER  BY p.id;

SELECT count(*) AS cantidad_con_producto_7
FROM   pedido p
WHERE  p.eliminado = FALSE
  AND  EXISTS (SELECT 1
               FROM   detalle_pedido d
               WHERE  d.pedido_id = p.id
                 AND  d.producto_id = 7
                 AND  d.eliminado = FALSE);

-- Ids recuperados en cada consulta, en el mismo formato que la tabla de verificación.
SELECT 'b) estado TERMINADO' AS consulta,
       count(*) AS cantidad,
       string_agg(id::text, ', ' ORDER BY id) AS ids
FROM   pedido
WHERE  estado = 'TERMINADO' AND eliminado = FALSE
UNION ALL
SELECT 'c) producto 7',
       count(*),
       string_agg(p.id::text, ', ' ORDER BY p.id)
FROM   pedido p
WHERE  p.eliminado = FALSE
  AND  EXISTS (SELECT 1 FROM detalle_pedido d
               WHERE d.pedido_id = p.id AND d.producto_id = 7 AND d.eliminado = FALSE);

-- d) (referencia) Pedidos con total > 2500, para contrastar con el apartado d) de MongoDB.
SELECT id, estado, total
FROM   pedido
WHERE  total > 2500 AND eliminado = FALSE
ORDER  BY id;
