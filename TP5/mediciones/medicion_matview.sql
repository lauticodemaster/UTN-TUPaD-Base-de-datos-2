-- ============================================================================
-- TP5 - Parte C: costo de leer el reporte materializado vs. calcularlo,
--                y costo de los dos tipos de REFRESH.
-- ============================================================================
SET search_path TO foodstore;

\echo '=== 1) Consulta ORIGINAL sin materializar ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha)::DATE AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
JOIN   producto pr  ON pr.id  = dp.producto_id
JOIN   categoria c  ON c.id   = pr.categoria_id
WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
GROUP  BY c.nombre, date_trunc('month', ped.fecha)
ORDER  BY mes DESC, facturado DESC;

\echo '=== 2) El MISMO reporte contra la vista materializada ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT categoria, mes, facturado
FROM   mv_facturacion_categoria_mes
ORDER  BY mes DESC, facturado DESC;

\echo '=== 3) Costo del REFRESH bloqueante ==='
\timing on
REFRESH MATERIALIZED VIEW mv_facturacion_categoria_mes;
\echo '=== 4) Costo del REFRESH CONCURRENTLY (habilitado por el indice unico) ==='
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
\timing off

\echo '=== 5) Tamano de la vista materializada y su indice ==='
SELECT pg_size_pretty(pg_relation_size('mv_facturacion_categoria_mes')) AS mv,
       pg_size_pretty(pg_relation_size('uq_mv_facturacion_cat_mes'))    AS indice_unico;
