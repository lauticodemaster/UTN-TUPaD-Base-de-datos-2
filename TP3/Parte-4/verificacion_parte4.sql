-- TP3 Parte 4 — crea la vista de seguridad y corre las verificaciones.
-- Uso:  psql -d foodstore_test -f verificacion_parte4.sql
-- Las verificaciones no modifican datos; lo único que crea son la vista
-- v_usuarios_publico, el rol app_lectura y sus permisos.

SET search_path TO foodstore;

\echo '=== 2.2 — creación de v_usuarios_publico ==='

CREATE VIEW v_usuarios_publico AS
SELECT u.id,
       u.nombre,
       u.apellido,
       u.mail,
       u.celular,
       u.rol,
       u.created_at
FROM   usuario u
WHERE  u.eliminado = FALSE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_lectura') THEN
        CREATE ROLE app_lectura NOLOGIN;
    END IF;
END $$;

GRANT USAGE  ON SCHEMA foodstore   TO app_lectura;
GRANT SELECT ON v_usuarios_publico TO app_lectura;


\echo ''
\echo '=== 3.1a — v_productos_vigentes: diferencia simétrica (esperado: 0 filas) ==='
(
  SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes
  EXCEPT
  SELECT p.id, p.nombre, p.precio, p.stock, c.nombre
  FROM   producto p JOIN categoria c ON c.id = p.categoria_id
  WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
)
UNION ALL
(
  SELECT p.id, p.nombre, p.precio, p.stock, c.nombre
  FROM   producto p JOIN categoria c ON c.id = p.categoria_id
  WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
  EXCEPT
  SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes
);

\echo '=== 3.1b — v_productos_vigentes: mismo COUNT (esperado: t) ==='
SELECT (SELECT COUNT(*) FROM v_productos_vigentes)
     = (SELECT COUNT(*)
        FROM   producto p JOIN categoria c ON c.id = p.categoria_id
        WHERE  p.eliminado = FALSE AND c.eliminado = FALSE) AS coinciden;


\echo ''
\echo '=== 3.2a — v_pedidos_resumen: diferencia simétrica (esperado: 0 filas) ==='
(
  SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen
  EXCEPT
  SELECT ped.id, u.nombre || ' ' || u.apellido, ped.fecha, ped.estado,
         ped.forma_pago, ped.total
  FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
  WHERE  ped.eliminado = FALSE
)
UNION ALL
(
  SELECT ped.id, u.nombre || ' ' || u.apellido, ped.fecha, ped.estado,
         ped.forma_pago, ped.total
  FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
  WHERE  ped.eliminado = FALSE
  EXCEPT
  SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen
);

\echo '=== 3.2b — v_pedidos_resumen: mismo COUNT (esperado: t) ==='
SELECT (SELECT COUNT(*) FROM v_pedidos_resumen)
     = (SELECT COUNT(*)
        FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
        WHERE  ped.eliminado = FALSE) AS coinciden;


\echo ''
\echo '=== 3.3a — v_pedido_detalle: diferencia simétrica (esperado: 0 filas) ==='
(
  SELECT pedido_id, producto, cantidad, precio_unitario, subtotal
  FROM   v_pedido_detalle
  EXCEPT
  SELECT dp.pedido_id, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal
  FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
  WHERE  dp.eliminado = FALSE
)
UNION ALL
(
  SELECT dp.pedido_id, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal
  FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
  WHERE  dp.eliminado = FALSE
  EXCEPT
  SELECT pedido_id, producto, cantidad, precio_unitario, subtotal
  FROM   v_pedido_detalle
);

\echo '=== 3.3b — v_pedido_detalle: mismo COUNT (esperado: t) ==='
SELECT (SELECT COUNT(*) FROM v_pedido_detalle)
     = (SELECT COUNT(*)
        FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
        WHERE  dp.eliminado = FALSE) AS coinciden;

\echo '=== 3.3c — suma de subtotales vs pedido.total (esperado: 0) ==='
SELECT COUNT(*) AS pedidos_descuadrados
FROM   pedido ped
JOIN   LATERAL (
         SELECT COALESCE(SUM(v.subtotal), 0) AS suma
         FROM   v_pedido_detalle v
         WHERE  v.pedido_id = ped.id
       ) s ON TRUE
WHERE  ped.eliminado = FALSE
  AND  s.suma <> ped.total;


\echo ''
\echo '=== 3.4a — v_usuarios_publico: diferencia simétrica (esperado: 0 filas) ==='
(
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   v_usuarios_publico
  EXCEPT
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   usuario WHERE eliminado = FALSE
)
UNION ALL
(
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   usuario WHERE eliminado = FALSE
  EXCEPT
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   v_usuarios_publico
);

\echo '=== 3.4b — la vista NO expone contrasena (esperado: ERROR column does not exist) ==='
SELECT contrasena FROM v_usuarios_publico LIMIT 1;

\echo '=== 3.4c — prueba de permisos con app_lectura ==='
SET ROLE app_lectura;
\echo '--- SELECT sobre la vista (esperado: 3 filas) ---'
SELECT id, nombre, apellido FROM v_usuarios_publico LIMIT 3;
\echo '--- SELECT sobre la tabla base (esperado: ERROR permission denied) ---'
SELECT id, nombre FROM usuario LIMIT 3;
RESET ROLE;

\echo ''
\echo '=== fin ==='
