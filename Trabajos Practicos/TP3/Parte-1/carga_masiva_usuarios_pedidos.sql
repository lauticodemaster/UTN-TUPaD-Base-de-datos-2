-- TP3 Parte 1 - Carga masiva de usuarios y pedidos (con sus detalles)
-- Complementa a carga_masiva_productos.sql (que ya carga los 50.000 productos)
--
-- Genera:
--   - 20.000 usuarios
--   - 200.000 pedidos, con usuario_id tomado de usuarios existentes
--     (semilla + recién cargados) y fecha distribuida en el último año
--   - entre 1 y 4 líneas de detalle_pedido por pedido nuevo, con
--     productos DISTINTOS dentro de cada pedido (respeta el
--     UNIQUE(pedido_id, producto_id))
--
-- Usa generate_series + CTEs, sin PL/pgSQL, sin tocar otras tablas.
--
-- IMPORTANTE (protocolo de seguridad de la cátedra):
--   Ejecutar primero sobre foodstore_test, nunca sobre foodstore directo.
--   Correr dentro de BEGIN; ...; para poder hacer ROLLBACK si algo no cierra,
--   y recién después de revisar los conteos, aplicar sobre la base real.

SET search_path TO foodstore;

-- ============================================================
-- 1) 20.000 usuarios nuevos
-- ============================================================
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol)
SELECT
    'Usuario' || g                                             AS nombre,
    'Apellido' || g                                            AS apellido,
    'usuario' || g || '@mailmasivo.com'                        AS mail,
    (2600000000 + g)::text                                     AS celular,
    'ClaveSegura' || g                                         AS contrasena,
    CASE WHEN g % 20 = 0 THEN 'ADMIN' ELSE 'USUARIO' END::rol  AS rol
FROM generate_series(1, 20000) AS g;

-- Verificación:
-- SELECT count(*) FROM usuario; -- debe ser 20000 + los 5 iniciales = 20005


-- ============================================================
-- 2) 200.000 pedidos nuevos
--    usuario_id elegido al azar entre TODOS los usuarios vigentes
--    (semilla + los recién cargados). fecha distribuida en los
--    últimos 365 días para que la consulta de facturación por mes
--    tenga variedad real (si no, todos caerían en CURRENT_DATE).
-- ============================================================
CREATE TEMP TABLE tmp_pedidos_nuevos AS
WITH usuarios_ids AS (
    SELECT array_agg(id) AS arr, count(*) AS cnt
    FROM usuario
    WHERE eliminado = FALSE
),
nuevos_pedidos AS (
    INSERT INTO pedido (usuario_id, forma_pago, estado, fecha)
    SELECT
        arr[floor(random() * cnt)::int + 1] AS usuario_id,
        (ARRAY['TARJETA','TRANSFERENCIA','EFECTIVO']::forma_pago[])
            [floor(random() * 3)::int + 1] AS forma_pago,
        (ARRAY['PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO']::estado_pedido[])
            [floor(random() * 4)::int + 1] AS estado,
        (CURRENT_DATE - floor(random() * 365)::int) AS fecha
    FROM generate_series(1, 200000) AS g, usuarios_ids
    RETURNING id
)
SELECT id FROM nuevos_pedidos;

-- Verificación:
-- SELECT count(*) FROM tmp_pedidos_nuevos; -- debe ser 200000
-- SELECT count(*) FROM pedido;             -- debe ser 200000 + los 3 iniciales = 200003


-- ============================================================
-- 3) Detalles de esos 200.000 pedidos: entre 1 y 4 líneas cada uno,
--    con productos distintos dentro de un mismo pedido.
--
--    Nota de rendimiento: para no tener que ordenar aleatoriamente
--    las ~50.000 filas de producto por cada uno de los 200.000
--    pedidos (eso sería carísimo), primero se acota a una ventana
--    aleatoria de 300 ids de producto y recién esa ventana chica
--    se mezcla con ORDER BY random(). Sigue garantizando productos
--    distintos por pedido porque se toman sin reposición de un
--    mismo conjunto.
-- ============================================================
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
SELECT
    tp.id                            AS pedido_id,
    prod.id                          AS producto_id,
    (1 + floor(random() * 5))::int   AS cantidad
FROM tmp_pedidos_nuevos tp
CROSS JOIN LATERAL (
    SELECT p.id
    FROM producto p
    CROSS JOIN (
        SELECT floor(random() * (m.max_id - 300))::bigint + 1 AS win_start
        FROM (SELECT max(id) AS max_id FROM producto) m
    ) w
    WHERE p.id >= w.win_start
      AND p.id <  w.win_start + 300
      AND p.eliminado = FALSE
    ORDER BY random()
    LIMIT (1 + floor(random() * 4))::int
) AS prod;

DROP TABLE tmp_pedidos_nuevos;

-- Verificación (consultas de control, no modifican datos):
-- SELECT count(*) FROM detalle_pedido;
-- SELECT count(DISTINCT pedido_id) FROM detalle_pedido; -- cercano a 200000
-- SELECT count(*) FROM pedido p
--   WHERE NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.pedido_id = p.id);
--   -- pedidos sin ningún detalle (puede haber algunos pocos, es esperable)

-- ============================================================
-- 4) Actualizar estadísticas para el optimizador antes de medir
-- ============================================================
ANALYZE usuario;
ANALYZE pedido;
ANALYZE detalle_pedido;
