-- TP Unidad 5 · Parte B.2 — secuencia de operaciones de prueba para la auditoría.
-- Se ejecuta conectado como app_web (lo orquesta auditoria_test.sh, que además
-- provoca el inicio de sesión fallido). Todo en una transacción que se revierte:
-- el log registra las sentencias igual, y la base no cambia.
SET application_name = 'tp_u5_parte_b';
SET search_path TO foodstore;

BEGIN;
-- lectura (con log_statement='mod' NO debería aparecer en el log)
SELECT id, nombre, precio FROM producto WHERE id = 1;

-- inserción
INSERT INTO pedido (forma_pago, usuario_id) VALUES ('TARJETA', 10) RETURNING id AS pid \gset
INSERT INTO detalle_pedido (cantidad, pedido_id, producto_id) VALUES (1, :pid, 3);

-- actualización
UPDATE pedido SET estado = 'CONFIRMADO' WHERE id = :pid;
ROLLBACK;
