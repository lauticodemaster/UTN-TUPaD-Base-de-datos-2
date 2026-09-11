-- ============================================================================
-- TP4 - Semana 4 - Unidad 2 - Parte 4
-- Competencia de optimización entre equipos
--
-- Consulta común: facturación por categoría y mes (queries.sql, sección
-- "Consultas analíticas", punto B). 3 JOIN + agregación.
--
-- Script reproducible de punta a punta. Ejecutar sobre foodstore_test, nunca
-- sobre foodstore directo (protocolo de seguridad de la cátedra).
--
-- Requisito previo: base masiva de la Semana 3 ya cargada
-- (carga_masiva_productos.sql + carga_masiva_usuarios_pedidos.sql) e índices
-- de la Semana 3 ya creados.
-- ============================================================================

SET search_path TO foodstore;


-- ============================================================================
-- 0) Preparación de la medición
-- ============================================================================

-- Estadísticas frescas y visibility map poblado. Después de una carga masiva
-- el visibility map queda vacío y sin él ningún Index Only Scan puede evitar
-- ir al heap, así que este VACUUM es precondición de la estrategia (punto 2.1),
-- no algo cosmético.
VACUUM (ANALYZE) categoria;
VACUUM (ANALYZE) producto;
VACUUM (ANALYZE) usuario;
VACUUM (ANALYZE) pedido;
VACUUM (ANALYZE) detalle_pedido;

-- Constancia del entorno en el que se mide.
SELECT name, setting, unit FROM pg_settings
WHERE  name IN ('work_mem','shared_buffers','max_parallel_workers_per_gather',
                'effective_cache_size','random_page_cost','jit');


-- ============================================================================
-- 1) Medición "antes" - consulta común tal cual está en queries.sql
--    Estado: solo los índices al cierre de la Semana 3, configuración por
--    defecto. Correr varias veces y tomar la mediana, no la primera corrida
--    (la primera mide caché frío, no el plan).
-- ============================================================================

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


-- ============================================================================
-- 2) Estrategia aplicada - cuatro cambios, en este orden
-- ============================================================================

-- 2.1 Índices covering: uno por cada tabla que el plan recorre entera.
--     La consulta no filtra nada, agrupa el 100% de las filas; por eso un
--     índice "para filtrar" no sirve (fue lo que falló en el TP3). Lo que sí
--     sirve es un índice más angosto que el heap con todas las columnas que la
--     consulta toca de esa tabla, para recorrerlo por Index Only Scan.
--       detalle_pedido: heap 71 MB  -> índice 33 MB
--       pedido:         heap 31 MB  -> índice 6.0 MB
--       producto:       heap 6.9 MB -> índice 1.5 MB

CREATE INDEX idx_dp_cov_facturacion
    ON detalle_pedido (pedido_id) INCLUDE (producto_id, subtotal)
    WHERE eliminado = FALSE;

CREATE INDEX idx_pedido_cov_fecha
    ON pedido (id) INCLUDE (fecha)
    WHERE eliminado = FALSE;

CREATE INDEX idx_producto_cov_categoria
    ON producto (id) INCLUDE (categoria_id);

VACUUM (ANALYZE) producto;
VACUUM (ANALYZE) pedido;
VACUUM (ANALYZE) detalle_pedido;

-- 2.2 random_page_cost para SSD.
--     Con el default de 4 (disco rotativo) el planificador descarta los
--     índices de 2.1 aunque pesen menos de la mitad que el heap, y sigue
--     eligiendo Parallel Seq Scan. En SSD el valor recomendado ronda 1.1.
--     La contra-prueba está en la sección 3.
SET random_page_cost = 1.1;

-- 2.3 Más paralelismo.
--     La máquina tiene 6 núcleos / 12 hilos; el default de 2 workers deja el
--     resto ocioso en una consulta que es escaneo + agregación.
SET max_parallel_workers_per_gather = 4;

-- 2.4 Reescritura de la consulta. Dos cambios:
--     (a) Agregar por pr.categoria_id (BIGINT) y unir categoria al final. En
--         el plan original el join contra categoria arrastra 800.008 filas
--         para unirlas contra 5, y recién ahí agrupa. Agrupando primero, esa
--         unión queda contra 29 filas y la clave de hash pasa de texto a
--         entero. Equivalente porque categoria.nombre tiene UNIQUE.
--     (b) date_trunc('month', ped.fecha::timestamp) en vez de
--         date_trunc('month', ped.fecha). ped.fecha es DATE; la versión
--         original lo promociona a TIMESTAMPTZ y usa date_trunc(text,
--         timestamptz), que es STABLE y convierte huso horario por fila. Con
--         ::timestamp se usa date_trunc(text, timestamp), IMMUTABLE, sin
--         conversión. Verificable con:
--            SELECT proname, pg_get_function_arguments(oid), provolatile
--            FROM pg_proc WHERE proname = 'date_trunc';

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, x.mes, x.facturado
FROM (
    SELECT pr.categoria_id,
           date_trunc('month', ped.fecha::timestamp)::DATE AS mes,
           SUM(dp.subtotal)                                AS facturado
    FROM   detalle_pedido dp
    JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
    JOIN   producto pr  ON pr.id  = dp.producto_id
    WHERE  dp.eliminado = FALSE
    GROUP  BY pr.categoria_id, date_trunc('month', ped.fecha::timestamp)
) x
JOIN categoria c ON c.id = x.categoria_id AND c.eliminado = FALSE
ORDER BY x.mes DESC, x.facturado DESC;


-- ============================================================================
-- 3) Contra-prueba del punto 2.2
--
--    Si forzando el índice con enable_seqscan = off (cost model por defecto)
--    el tiempo real es casi igual que con random_page_cost = 1.1 (índice
--    elegido solo), entonces bajar el parámetro no inventó una mejora: solo
--    dejó que el planificador eligiera por su cuenta el plan que ya era mejor.
--    Mismo procedimiento que en el TP3 con enable_hashjoin = off.
-- ============================================================================

SET random_page_cost = 4;      -- vuelve al default
SET enable_seqscan  = off;     -- fuerza el camino por índice

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, x.mes, x.facturado
FROM (
    SELECT pr.categoria_id,
           date_trunc('month', ped.fecha::timestamp)::DATE AS mes,
           SUM(dp.subtotal)                                AS facturado
    FROM   detalle_pedido dp
    JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
    JOIN   producto pr  ON pr.id  = dp.producto_id
    WHERE  dp.eliminado = FALSE
    GROUP  BY pr.categoria_id, date_trunc('month', ped.fecha::timestamp)
) x
JOIN categoria c ON c.id = x.categoria_id AND c.eliminado = FALSE
ORDER BY x.mes DESC, x.facturado DESC;

RESET enable_seqscan;
SET  random_page_cost = 1.1;


-- ============================================================================
-- 4) Verificación de equivalencia
--    La consulta reescrita tiene que devolver exactamente lo mismo que la
--    consulta común. Debe dar 0 en los dos sentidos.
-- ============================================================================

WITH original AS (
    SELECT c.nombre AS categoria,
           date_trunc('month', ped.fecha)::DATE AS mes,
           SUM(dp.subtotal) AS facturado
    FROM   detalle_pedido dp
    JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
    JOIN   producto pr  ON pr.id  = dp.producto_id
    JOIN   categoria c  ON c.id   = pr.categoria_id
    WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
    GROUP  BY c.nombre, date_trunc('month', ped.fecha)
),
optimizada AS (
    SELECT c.nombre AS categoria, x.mes, x.facturado
    FROM (
        SELECT pr.categoria_id,
               date_trunc('month', ped.fecha::timestamp)::DATE AS mes,
               SUM(dp.subtotal)                                AS facturado
        FROM   detalle_pedido dp
        JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
        JOIN   producto pr  ON pr.id  = dp.producto_id
        WHERE  dp.eliminado = FALSE
        GROUP  BY pr.categoria_id, date_trunc('month', ped.fecha::timestamp)
    ) x
    JOIN categoria c ON c.id = x.categoria_id AND c.eliminado = FALSE
)
SELECT 'original EXCEPT optimizada' AS sentido, count(*) AS filas_diferentes
FROM  (SELECT * FROM original EXCEPT SELECT * FROM optimizada) d
UNION ALL
SELECT 'optimizada EXCEPT original', count(*)
FROM  (SELECT * FROM optimizada EXCEPT SELECT * FROM original) d
UNION ALL
SELECT 'filas devueltas por original',   count(*) FROM original
UNION ALL
SELECT 'filas devueltas por optimizada', count(*) FROM optimizada;


-- ============================================================================
-- 5) Propuestas que se probaron y no funcionaron
--    Quedan documentadas y ejecutables. No forman parte de la entrega final.
-- ============================================================================

-- 5.1 Índice sobre la expresión date_trunc(fecha).
--     Idea: "si agrupás por date_trunc('month', fecha), indexá esa expresión".
--     Medido: el plan no lo menciona en ningún nodo y el tiempo no cambia. Un
--     índice de expresión sirve para filtrar u ordenar por esa expresión; acá
--     solo aparece en el GROUP BY y hay que leer igual todas las filas.
--
-- CREATE INDEX idx_pedido_mes_expr
--     ON pedido ((date_trunc('month', fecha::timestamp))) WHERE eliminado = FALSE;
-- VACUUM (ANALYZE) pedido;
--   -- correr el EXPLAIN de 2.4 y comprobar que idx_pedido_mes_expr no aparece
-- DROP INDEX idx_pedido_mes_expr;

-- 5.2 Subir work_mem.
--     Idea: "los hash joins van a memoria, dales más work_mem".
--     Medido: sin efecto, dentro del ruido. El plan ya dice "Batches: 1" en
--     todos los nodos de hash, o sea que ninguno vuelca a disco. work_mem solo
--     ayuda con Batches > 1 o con un Sort en "external merge".
--
-- SET work_mem = '64MB';

-- 5.3 Vista materializada.
--     Idea: "precalculá la facturación en una MATERIALIZED VIEW".
--     Medido: 0.1 ms de lectura, pero no es la misma consulta: devuelve datos
--     congelados al último REFRESH, y el REFRESH cuesta 227-283 ms (mediana
--     245), lo mismo que la consulta original. Cambia el problema, no lo
--     optimiza.
--
-- CREATE MATERIALIZED VIEW mv_facturacion AS
-- SELECT c.nombre AS categoria,
--        date_trunc('month', ped.fecha::timestamp)::DATE AS mes,
--        SUM(dp.subtotal) AS facturado
-- FROM   detalle_pedido dp
-- JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
-- JOIN   producto pr  ON pr.id  = dp.producto_id
-- JOIN   categoria c  ON c.id   = pr.categoria_id
-- WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
-- GROUP  BY c.nombre, date_trunc('month', ped.fecha::timestamp);
-- REFRESH MATERIALIZED VIEW mv_facturacion;
-- DROP MATERIALIZED VIEW mv_facturacion;

-- 5.4 idx_pedido_fecha (heredado del TP3).
--     Sigue en la base y sigue sin aparecer en ningún plan, igual que en la
--     Semana 3. Un índice sobre la columna del GROUP BY no ayuda cuando no hay
--     filtro que permita evitar leer filas.


-- ============================================================================
-- 6) Observación de correctitud (no es una optimización)
--
--    La consulta común filtra dp.eliminado = FALSE y c.eliminado = FALSE, pero
--    no filtra pr.eliminado en el join a producto. Es el tipo de
--    inconsistencia de borrado lógico dentro de un JOIN que advierte la Parte
--    3 del TP.
--
--    Hoy el resultado no cambia porque no hay productos eliminados:
--        SELECT count(*) FROM producto WHERE eliminado;   -- 0
--
--    No se corrigió a propósito: agregar pr.eliminado = FALSE cambiaría el
--    conjunto de resultados en cuanto exista un producto dado de baja, y la
--    consulta de la competencia tiene que ser la misma para todos los equipos.
-- ============================================================================


-- ============================================================================
-- 7) Limpieza (solo si se quiere volver al estado previo a la competencia)
-- ============================================================================
-- DROP INDEX IF EXISTS idx_dp_cov_facturacion;
-- DROP INDEX IF EXISTS idx_pedido_cov_fecha;
-- DROP INDEX IF EXISTS idx_producto_cov_categoria;
-- RESET random_page_cost;
-- RESET max_parallel_workers_per_gather;
