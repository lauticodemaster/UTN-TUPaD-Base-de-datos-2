-- TP3 Parte-1 - Carga masiva de 50000 productos
-- Distribuidos de forma pareja entre las 5 categorías existentes (10000 por categoría)
-- Precios aleatorios entre 500 y 5000, stock aleatorio entre 0 y 200
-- Usa generate_series, sin PL/pgSQL, sin modificar otras tablas

SET search_path TO foodstore;

INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id)
SELECT
    'Producto ' || g AS nombre,
    'Producto generado masivamente #' || g AS descripcion,
    round((500 + random() * 4500)::numeric, 2) AS precio,
    floor(random() * 201)::int AS stock,
    TRUE AS disponible,
    ((g - 1) % 5) + 1 AS categoria_id
FROM generate_series(1, 50000) AS g;

-- Verificación (consultas de control, no modifican datos):
-- SELECT categoria_id, count(*) FROM producto GROUP BY categoria_id ORDER BY categoria_id;
-- SELECT min(precio), max(precio) FROM producto WHERE nombre LIKE 'Producto %';
-- SELECT min(stock), max(stock) FROM producto WHERE nombre LIKE 'Producto %';
-- SELECT count(*) FROM producto; -- debe ser 50000 + los 12 iniciales = 50012
