SET search_path TO foodstore;

-- INSERCIÓN DE USUARIOS.
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES (
	'Miguel', 'Herrera', 'miguelherrera@gmail.com', '2613649945', 'marmota5', 'USUARIO'
);
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES (
	'Juliana', 'Paredes', 'juliparedes23@hotmail.com', '2619938672', 'h1p0potomo2tr0', 'ADMIN'
);
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES (
	'Iván', 'Ivañez', 'iviva1717@yahoo.com', '2617884561', 'vivilavidaloca_como_tu_te_llama_17', 'USUARIO'
);
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES (
	'Ramón', 'Garzón', '1tiralodon@gmail.com', '2614324865', 'Ocean0sPacificos_2f', 'ADMIN'
);
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES (
	'Ariagna', 'Rodriguez', 'ariagnita38@gmail.com', '2612261620', 'tela-CaraX8', 'USUARIO'
);

-- INSERCIÓN DE CATEGORÍAS.
INSERT INTO categoria (nombre, descripcion) VALUES (
	'Pizzas', 'Pizzas de masa tradicional y rellenos variados'
);
INSERT INTO categoria (nombre, descripcion) VALUES (
	'Empanadas', 'Empanadas de carne, pollo, queso y jamón'
);
INSERT INTO categoria (nombre, descripcion) VALUES (
	'Bebidas', 'Bebidas frías y refrescos varios'
);
INSERT INTO categoria (nombre, descripcion) VALUES (
	'Postres', 'Postres caseros y dulces variados'
);
INSERT INTO categoria (nombre, descripcion) VALUES (
	'Ensaladas', 'Ensaladas frescas y saludables'
);

-- INSERCIÓN DE PRODUCTOS.
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Fugazzeta', 'Pizza de cebolla con queso mozzarella', 1800.00, 15, TRUE, 1
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Mozzarella', 'Pizza clásica de queso mozzarella', 1600.00, 20, TRUE, 1
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Jamón y Queso', 'Pizza con jamón serrano y queso', 2000.00, 12, TRUE, 1
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Empanada de Carne', 'Empanada rellena de carne', 150.00, 50, TRUE, 2
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Empanada de Pollo', 'Empanada rellena de pollo', 140.00, 45, TRUE, 2
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Empanada de Queso', 'Empanada rellena de queso', 130.00, 40, TRUE, 2
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Gaseosa 2L', 'Gaseosa cola o naranja 2 litros', 350.00, 30, TRUE, 3
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Jugo Natural', 'Jugo de naranja o pomelo recién exprimido', 250.00, 25, TRUE, 3
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Flan Casero', 'Flan tradicional con dulce de leche', 200.00, 10, TRUE, 4
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Brownie', 'Brownie de chocolate casero', 180.00, 8, TRUE, 4
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Ensalada Verde', 'Lechuga, tomate, cebolla y aderezo', 500.00, 6, TRUE, 5
);
INSERT INTO producto (nombre, descripcion, precio, stock, disponible, categoria_id) VALUES (
	'Ensalada César', 'Lechuga, pollo, queso parmesano y salsa César', 700.00, 5, TRUE, 5
);


-- INSERCIÓN DE PEDIDOS.
INSERT INTO pedido (usuario_id, forma_pago, estado) VALUES (1, 'EFECTIVO', 'CONFIRMADO');
INSERT INTO pedido (usuario_id, forma_pago, estado) VALUES (3, 'TARJETA', 'PENDIENTE');
INSERT INTO pedido (usuario_id, forma_pago, estado) VALUES (5, 'TRANSFERENCIA', 'TERMINADO');

------ A PARTIR DE ESTE PUNTO SE RECOMIENDA PRIMERO EJECUTAR LA SECCIÓN DE FUNCIONES
------ Y TRIGGERS EN EL ARCHIVO objects.sql PARA PODER COMPLETAR LOS DATOS.

-- DETALLES DEL PEDIDO 1 (Miguel - 2 fugazzetas y 1 gaseosa)
-- El trigger trg_subtotal congela el precio_unitario y calcula el subtotal.
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (1, 1, 2);
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (1, 7, 1);

-- DETALLES DEL PEDIDO 2 (Iván - empanadas y jugo)
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (2, 4, 3);
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (2, 5, 2);
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (2, 8, 1);

-- DETALLES DEL PEDIDO 3 (Ariagna - pizza, postre y ensalada)
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (3, 2, 1);
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (3, 9, 2);
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad) VALUES (3, 11, 1);

SELECT * FROM usuario;
SELECT * FROM categoria;
SELECT * FROM producto;
SELECT * FROM pedido;
SELECT * FROM detalle_pedido;