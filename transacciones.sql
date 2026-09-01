SET search_path TO foodstore;

-- TRANSACCIONES Y CONCURRENCIA
-- Estos scripts demuestran atomicidad, transacciones manuales, aislamiento
-- y bloqueos. Ejecutarlos después de schema.sql, objects.sql y data.sql.


-- ESCENARIO 1
-- Intentamos crear un pedido con un producto inexistente (ID 999).
-- El procedimiento lanza excepción y el pedido no se crea.
-- Estado antes:
SELECT COUNT(*) AS pedidos_antes FROM pedido;

-- Esto falla: producto 999 no existe
CALL sp_crear_pedido(
    1,
    'EFECTIVO'::forma_pago,
    '[{"producto_id":999,"cantidad":2}]'::jsonb
);
-- ERROR: Producto 999 inexistente o eliminado

-- Estado después: sigue igual (rollback automático).
SELECT COUNT(*) AS pedidos_despues FROM pedido;


-- ESCENARIO 2
-- Intentamos pedir 9999 unidades de un producto que tiene poco stock.
SELECT id, nombre, stock FROM producto WHERE id = 1;
CALL sp_crear_pedido(
    1,
    'TARJETA'::forma_pago,
    '[{"producto_id":1,"cantidad":9999}]'::jsonb
);
-- ERROR: Stock insuficiente

-- Verificar que el stock no se tocó:
SELECT id, nombre, stock FROM producto WHERE id = 1;


-- ESCENARIO 3
-- Empezamos a crear un peddido pero decidimos revertir.
SELECT COUNT(*) AS antes FROM pedido;

BEGIN;
    INSERT INTO pedido (usuario_id, forma_pago)
    VALUES (5, 'TRANSFERENCIA'::forma_pago);

    -- Cambiamos de idea; revertimos todo.
ROLLBACK;

-- Verificar: la cantidad no cambió
SELECT COUNT(*) AS despues FROM pedido;


-- ESCENARIO 4
-- Uso normal del procedimiento: crea pedido, descuenta stock, calcula el total.
SELECT stock AS stock_antes FROM producto WHERE id = 2;

CALL sp_crear_pedido(
    1,
    'EFECTIVO'::forma_pago,
    '[{"producto_id":2,"cantidad":1},{"producto_id":9,"cantidad":2}]'::jsonb
);

SELECT stock AS stock_despues FROM producto WHERE id = 2;

-- Ver el pedido creado:
SELECT * FROM v_pedidos_resumen ORDER BY id DESC LIMIT 1;
SELECT * FROM v_pedido_detalle
WHERE pedido_id = (SELECT MAX(id) FROM pedido);


-- ESCENARIO 5
-- Eliminar un pedido y sus detalles de forma atómica.
BEGIN;
    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 2;
    UPDATE pedido SET eliminado = TRUE WHERE id = 2;
COMMIT;
SELECT * FROM pedido
WHERE eliminado = TRUE;

-- Ya no aparece en la vista:
SELECT * FROM v_pedidos_resumen WHERE id = 2;

-- Pero sigue en la tabla real:
SELECT id, estado, eliminado FROM pedido WHERE id = 2;


-- ESCENARIO 6
-- Intentar insertar datos que violen los CHECK.
-- cantidad <= 0 (violación)
DO $$
BEGIN
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
    VALUES (1, 3, 0);
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CHECK violado: cantidad debe ser > 0';
END $$;

-- precio negativo (violación)
DO $$
BEGIN
    INSERT INTO producto (nombre, precio, stock, categoria_id)
    VALUES ('Test', -100, 5, 1);
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CHECK violado: precio debe ser >= 0';
END $$;


-- ESCENARIO 7
-- Intentar insertar un detalle con pedido inexistente.
DO $$
BEGIN
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
    VALUES (99999, 1, 1);
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'FK violada: el pedido 99999 no existe';
END $$;


-- ESCENARIO 8
-- Intentar duplicar un producto en el mismo pedido.
DO $$
BEGIN
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad)
    VALUES (1, 1, 1);  -- producto 1 ya está en pedido 1
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'UNIQUE violado: producto ya existe en este pedido';
END $$;



-- ESCENARIO 9
-- Para probar esto se necesitan DOS sesiones psql abiertas simultáneamente.
-- SESIÓN 1 (ejecutar primero):
BEGIN;
SELECT stock FROM producto WHERE id = 1 FOR UPDATE;
	-- (la fila queda bloqueada, esta sesión "no termina")
	-- Esperar unos segundos para que Sesión 2 intente...
	UPDATE producto SET stock = stock - 1 WHERE id = 1;
COMMIT;

-- SESIÓN 2 (ejecutar mientras Sesión 1 está bloqueando):
BEGIN;
SELECT stock FROM producto WHERE id = 1 FOR UPDATE;
-- ↑ Esta línea ESPERA hasta que Sesión 1 haga COMMIT
-- Recién ahí puede continuar y ve el stock ya actualizado.
UPDATE producto SET stock = stock - 1 WHERE id = 1;
COMMIT;

-- Resultado: ambas sesiones descuentan 1 unidad de forma segura,
-- sin sobreventa. El FOR UPDATE serializa el acceso a la fila.


-- ESCENARIO 10
-- PostgreSQL usa READ COMMITTED por defecto.
-- Con SERIALIZABLE, las transacciones se comportan como si se ejecutaran
-- una después de otra

-- Ejemplo teórico con dos sesiones:
-- SESIÓN 1 (READ COMMITTED):
	BEGIN;
	SELECT stock FROM producto WHERE id = 1;  -- lee 15
		-- (Sesión 2 cambia el stock a 14 y hace COMMIT)
	SELECT stock FROM producto WHERE id = 1;  -- lee 14 (lectura no repetible)
	COMMIT;

-- SESIÓN 1 (SERIALIZABLE):
	BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
	SELECT stock FROM producto WHERE id = 1;  -- lee 15
	-- (Sesión 2 cambia el stock a 14 y hace COMMIT)
	SELECT stock FROM producto WHERE id = 1;  -- SIGUE leyendo 15
	COMMIT;
	-- En SERIALIZABLE, la snapshot no cambia durante la transacción.

-- La diferencia es que READ COMMITTED ve los cambios de otras transacciones
-- después de cada sentencia, mientras que SERIALIZABLE ve una "foto"
-- del momento en que empezó la transacción.


-- VERIFICACIÓN FINAL
-- Después de ejecutar todos los escenarios, verificar que los datos
-- están en un estado consistente:
SELECT 'Categorías vigentes' AS tabla, COUNT(*) AS cantidad
FROM v_categorias_vigentes
UNION ALL
SELECT 'Productos vigentes', COUNT(*) FROM v_productos_vigentes
UNION ALL
SELECT 'Pedidos vigentes', COUNT(*) FROM v_pedidos_resumen;


-- Verificar que los totales son correctos:
SELECT p.id,
       p.total AS total_almacenado,
       calcular_total_pedido(p.id) AS total_calculado,
       CASE WHEN p.total = calcular_total_pedido(p.id)
            THEN 'OK' ELSE 'ERROR' END AS estado
FROM pedido p
WHERE p.eliminado = FALSE
ORDER BY p.id; 
