SET search_path TO foodstore;


-- HISTORIAS DE USUARIO
-- Cada consulta a continuación resuelve una historia de usuario del TPI.
-- Las consultas pueden ejecutarse sobre la base de datos después de correr
-- schema.sql, objects.sql y data.sql.


-- ÉPICA 1
-- HU-CAT-01: Listar categorías
-- Como operador, quiero listar las categorías vigentes para asociar productos.
SELECT id, nombre, descripcion
FROM   categoria
WHERE  eliminado = FALSE
ORDER  BY id;

-- HU-CAT-02: Crear categoría
-- Como operador, quiero crear una categoría para organizar el catálogo.
INSERT INTO categoria(nombre, descripcion)
VALUES ('Adicionales', 'Aderezos, condimentos y extras')
RETURNING id;

-- HU-CAT-03: Editar categoría
-- Como operador, quiero actualizar una categoría existente.
UPDATE categoria
SET    nombre = 'Pizzas Especiales', descripcion = 'Pizzas con ingredientes premium'
WHERE  id = 1 AND eliminado = FALSE;

-- HU-CAT-04: Eliminar categoría (baja lógica)
-- Como operador, quiero dar de baja lógica una categoría sin perder historial.
UPDATE categoria
SET    eliminado = TRUE
WHERE  id = 6 AND eliminado = FALSE;


-- ÉPICA 2
-- HU-PROD-01: Listar productos
-- Como operador, quiero listar productos con su stock y categoría.
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM   producto p
JOIN   categoria c ON c.id = p.categoria_id
WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
ORDER  BY p.id;

-- Filtro opcional por categoría (ejemplo: categoría 2 = Empanadas)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM   producto p
JOIN   categoria c ON c.id = p.categoria_id
WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
  AND  p.categoria_id = 2
ORDER  BY p.id;

-- HU-PROD-02: Crear producto
-- Como operador, quiero crear un producto y asociarlo a una categoría.
INSERT INTO producto(nombre, descripcion, precio, stock, imagen, disponible, categoria_id)
SELECT 'Calabresa', 'Pizza con salsa picante y carnes', 2100.00, 8, NULL, TRUE, c.id
FROM   categoria c
WHERE  c.id = 1 AND c.eliminado = FALSE
RETURNING id;

-- HU-PROD-03: Editar producto
-- Como operador, quiero actualizar precio, stock o categoría de un producto.
UPDATE producto
SET    precio = COALESCE(1850.00, precio),
       stock  = COALESCE(18,     stock)
WHERE  id = 1 AND eliminado = FALSE;

-- HU-PROD-04: Eliminar producto (baja lógica)
-- Como operador, quiero retirar un producto del catálogo sin borrar su historial.
UPDATE producto
SET    eliminado = TRUE
WHERE  id = 13 AND eliminado = FALSE;


-- ÉPICA 3
-- HU-USR-01: Listar usuarios
-- Como operador, quiero consultar la información de contacto de los usuarios.
SELECT id, nombre, apellido, mail, rol
FROM   usuario
WHERE  eliminado = FALSE
ORDER  BY id;

-- HU-USR-02: Crear usuario
-- Como operador, quiero crear un usuario para asociarlo luego a pedidos.
INSERT INTO usuario(nombre, apellido, mail, celular, contrasena, rol)
VALUES ('Ana', 'García', 'anag@mail.com', '2612345678', 'secure123', 'USUARIO')
RETURNING id;

-- HU-USR-03: Editar usuario
-- Como operador, quiero corregir o actualizar datos de un usuario.
UPDATE usuario
SET    celular = '2617654321'
WHERE  id = 1 AND eliminado = FALSE;

-- HU-USR-04: Eliminar usuario (baja lógica)
-- Como operador, quiero dar de baja lógica a un usuario.
UPDATE usuario
SET    eliminado = TRUE
WHERE  id = 2 AND eliminado = FALSE;


-- ÉPICA 4
-- HU-PED-01: Listar pedidos
-- Como operador, quiero listar pedidos con su estado y total.
SELECT id, usuario, fecha, estado, forma_pago, total
FROM   v_pedidos_resumen
ORDER  BY id;

-- Filtro opcional por usuario (búsqueda parcial)
SELECT id, usuario, fecha, estado, forma_pago, total
FROM   v_pedidos_resumen
WHERE  usuario LIKE '%Miguel%'
ORDER  BY id;

-- HU-PED-02: Crear pedido con detalles
-- Como operador, quiero crear un pedido y cargar sus líneas.
-- Este procedimiento está en objects.sql como sp_crear_pedido().
-- Ejemplo de llamada:
CALL sp_crear_pedido(
     1,                 -- usuario_id (debe estar vigente)
     'EFECTIVO'::forma_pago,
     '[{"producto_id":1,"cantidad":2},
       {"producto_id":7,"cantidad":1}]'::jsonb);

-- HU-PED-03: Actualizar estado / forma de pago
-- Como operador, quiero actualizar el estado y/o la forma de pago de un pedido.
UPDATE pedido
SET    estado = 'CONFIRMADO'::estado_pedido, forma_pago = 'TARJETA'::forma_pago
WHERE  id = 1 AND eliminado = FALSE;

-- HU-PED-04: Eliminar pedido (baja lógica)
-- Como operador, quiero dar de baja lógica un pedido sin perder auditoría.
BEGIN;
  UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 1;
  UPDATE pedido         SET eliminado = TRUE WHERE id = 1;
COMMIT;


-- VISTAS DE UTILIDAD
-- Vista: Productos vigentes
SELECT * FROM v_productos_vigentes;

-- Vista: Categorías vigentes
SELECT * FROM v_categorias_vigentes;

-- Vista: Resumen de pedidos
SELECT * FROM v_pedidos_resumen;

-- Vista: Detalle de un pedido específico
SELECT * FROM v_pedido_detalle
WHERE  pedido_id = 1;


-- CONSULTAS ANALÍTICAS
-- A) Top 5 productos más vendidos (por cantidad)
SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
FROM   detalle_pedido dp
JOIN   producto pr ON pr.id = dp.producto_id
WHERE  dp.eliminado = FALSE
GROUP  BY pr.id, pr.nombre
ORDER  BY unidades DESC
LIMIT  5;

-- B) Facturación por categoría y por mes
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

-- C) Ranking de usuarios por gasto acumulado (función de ventana)
SELECT u.id, u.nombre || ' ' || u.apellido AS usuario,
       SUM(ped.total) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM   pedido ped
JOIN   usuario u ON u.id = ped.usuario_id
WHERE  ped.eliminado = FALSE AND u.eliminado = FALSE
GROUP  BY u.id, u.nombre, u.apellido
ORDER  BY puesto;

-- D) Pedidos cuyo total supera el promedio general (subconsulta)
SELECT id, total
FROM   pedido
WHERE  eliminado = FALSE
  AND  total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
ORDER  BY total DESC;

-- E) Productos sin ventas (LEFT JOIN + IS NULL)
SELECT pr.id, pr.nombre
FROM   producto pr
LEFT   JOIN detalle_pedido dp
       ON dp.producto_id = pr.id AND dp.eliminado = FALSE
WHERE  pr.eliminado = FALSE
  AND  dp.id IS NULL
ORDER  BY pr.id;


-- FUNCIONES DE UTILIDAD
-- Calcular total de un pedido específico
SELECT calcular_total_pedido(1) AS total_pedido_1;

-- Calcular totales de todos los pedidos
SELECT p.id, p.usuario_id, calcular_total_pedido(p.id) AS total_calculado, p.total
FROM   pedido p
WHERE  p.eliminado = FALSE
ORDER  BY p.id;
