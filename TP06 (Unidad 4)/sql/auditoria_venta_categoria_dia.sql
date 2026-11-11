-- Auditoría de desincronización de venta_categoria_dia (TP U4 5.2 e). Resultado esperado: vacío.
SET search_path TO foodstore;
WITH fuente AS (
    SELECT ped.fecha, pr.categoria_id, SUM(dp.subtotal) AS total
    FROM   detalle_pedido dp
    JOIN   producto pr ON pr.id  = dp.producto_id
    JOIN   pedido  ped ON ped.id = dp.pedido_id
    WHERE  dp.eliminado = FALSE AND ped.eliminado = FALSE
    GROUP  BY ped.fecha, pr.categoria_id
)
SELECT COALESCE(f.fecha, v.fecha)               AS fecha,
       COALESCE(f.categoria_id, v.categoria_id) AS categoria_id,
       COALESCE(f.total, 0)                     AS total_fuente,
       COALESCE(v.total_vendido, 0)             AS total_redundante
FROM   fuente f
FULL   JOIN venta_categoria_dia v
       ON v.fecha = f.fecha AND v.categoria_id = f.categoria_id
WHERE  COALESCE(f.total, 0) <> COALESCE(v.total_vendido, 0);
