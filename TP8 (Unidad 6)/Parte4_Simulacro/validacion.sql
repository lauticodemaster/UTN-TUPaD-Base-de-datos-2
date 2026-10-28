-- validacion.sql — controles minimos. Ejecutar sobre foodstore (antes del respaldo, para
-- registrar los conteos de referencia) y sobre foodstore_restore_test (despues de restaurar).
-- Nota: en el esquema de TP1 la tabla de clientes se llama "usuario" (el enunciado dice "cliente").

SET search_path TO foodstore;  -- las tablas viven en el esquema foodstore (TP1)

SELECT 'categoria' AS tabla, COUNT(*) AS filas FROM categoria
UNION ALL SELECT 'usuario (cliente)', COUNT(*) FROM usuario
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido;

SELECT COUNT(*) AS productos_invalidos
FROM producto
WHERE precio < 0 OR stock < 0;

SELECT COUNT(*) AS detalles_invalidos
FROM detalle_pedido
WHERE cantidad <= 0 OR precio_unitario < 0;
