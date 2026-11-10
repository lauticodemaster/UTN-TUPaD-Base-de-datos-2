-- ============================================================================
-- BASE DE DATOS II - UTN TUPaD
-- TRABAJO PRÁCTICO N.º 8 (UNIDAD 8) - FOOD STORE EN LA FERIA
-- Consigna 1.c: Pruebas en SQLite (Transacciones, C1 Catálogo y C7 Errores)
-- Archivo: movil/pruebas_sqlite.sql
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- PREPARACIÓN PREVIA: Cargar datos iniciales en producto_cache para las pruebas
-- ----------------------------------------------------------------------------
INSERT OR REPLACE INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, fecha_copia)
VALUES 
    (1, 'Fugazzeta', 180000, 15, 1, 0, '2026-11-10 10:00:00'),
    (2, 'Mozzarella', 160000, 20, 1, 0, '2026-11-10 10:00:00'),
    (3, 'Jamón y Queso', 200000, 12, 1, 0, '2026-11-10 10:00:00'),
    (7, 'Gaseosa 2L', 35000, 30, 1, 0, '2026-11-10 10:00:00'),
    (10, 'Brownie (Agotado)', 18000, 0, 1, 0, '2026-11-10 10:00:00'),
    (99, 'Producto Descatalogado', 10000, 10, 0, 1, '2026-11-10 10:00:00');

-- ============================================================================
-- 1. TRANSACCIONES: BORRADOR COMPLETO (COMMIT) Y OPERACIÓN DESHECHA (ROLLBACK)
-- ============================================================================

-- 1.A. Operación Exitosa: Borrador + Ítems + Solicitud en Cola_Sync guardada con COMMIT
BEGIN TRANSACTION;

INSERT INTO pedido_borrador (id_local, usuario, forma_pago, fecha)
VALUES ('b1000000-0000-0000-0000-000000000001', 'cliente_feria_01', 'EFECTIVO', '2026-11-10 11:30:00');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES 
    ('b1000000-0000-0000-0000-000000000001', 1, 2, 180000), -- 2 Fugazzeta a $1.800
    ('b1000000-0000-0000-0000-000000000001', 7, 1, 35000);  -- 1 Gaseosa 2L a $350

INSERT INTO cola_sync (solicitud_uuid, id_local, estado, motivo)
VALUES ('s1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'PENDIENTE', 'Nuevo pedido registrado en tablet');

COMMIT;

-- Verificación de la persistencia del borrador:
SELECT '--- Borrador persistido (COMMIT) ---' AS verificacion;
SELECT * FROM pedido_borrador WHERE id_local = 'b1000000-0000-0000-0000-000000000001';
SELECT * FROM item_borrador WHERE id_local = 'b1000000-0000-0000-0000-000000000001';
SELECT * FROM cola_sync WHERE solicitud_uuid = 's1000000-0000-0000-0000-000000000001';


-- 1.B. Operación Deshecha: Cliente se arrepiente antes de confirmar
BEGIN TRANSACTION;

INSERT INTO pedido_borrador (id_local, usuario, forma_pago, fecha)
VALUES ('b2000000-0000-0000-0000-000000000002', 'cliente_cancela', 'TARJETA', '2026-11-10 11:35:00');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('b2000000-0000-0000-0000-000000000002', 2, 4, 160000);

-- Se aborta la operación:
ROLLBACK;

-- Verificación de que ROLLBACK dejó la base intacta (resultado esperado: 0 filas):
SELECT '--- Conteo tras ROLLBACK (debe ser 0) ---' AS verificacion;
SELECT count(*) AS borradores_fantasma FROM pedido_borrador WHERE id_local = 'b2000000-0000-0000-0000-000000000002';
SELECT count(*) AS items_fantasma FROM item_borrador WHERE id_local = 'b2000000-0000-0000-0000-000000000002';


-- ============================================================================
-- 2. CASO C1: CONSULTA DEL CATÁLOGO DISPONIBLE OFFLINE
-- ============================================================================
-- La tablet consulta localmente sin enviar peticiones de red al servidor central.
-- Filtros aplicados: disponible = 1, eliminado = 0 y stock_visto > 0.
-- Obsérvese que se excluye 'Brownie' (stock = 0) y 'Producto Descatalogado' (eliminado = 1).
SELECT '--- CASO C1: Catálogo activo offline ---' AS caso;

SELECT 
    id AS codigo,
    nombre,
    precio_centavos / 100.0 AS precio_pesos,
    stock_visto,
    fecha_copia
FROM producto_cache
WHERE disponible = 1 
  AND eliminado = 0 
  AND stock_visto > 0
ORDER BY id;


-- ============================================================================
-- 3. CASO C7: ERRORES DE INTEGRIDAD Y RESTRICCIONES (CHECK Y FK)
-- ============================================================================
-- En SQLite en modo estricto con foreign_keys = ON, las siguientes sentencias fallan
-- protegiendo la base de corrupción de datos.

-- Prueba 3.A: Intento de insertar ítem con cantidad = 0
-- Falla por restricción CHECK (cantidad > 0)
-- Comando:
--   INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
--   VALUES ('b1000000-0000-0000-0000-000000000001', 1, 0, 180000);
-- Error producido: CHECK constraint failed: cantidad > 0

-- Prueba 3.B: Intento de insertar ítem con producto inexistente (id = 99999)
-- Falla por clave foránea hacia producto_cache(id)
-- Comando:
--   INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
--   VALUES ('b1000000-0000-0000-0000-000000000001', 99999, 1, 100000);
-- Error producido: FOREIGN KEY constraint failed

-- Verificación final: Se comprueba que ningún registro anómalo ingresó a item_borrador:
SELECT '--- Verificación Caso C7: Ningún registro espurio en item_borrador ---' AS verificacion_c7;
SELECT * FROM item_borrador WHERE cantidad <= 0 OR producto_id = 99999;
