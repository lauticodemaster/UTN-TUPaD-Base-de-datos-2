-- ============================================================================
-- TP5 - Verificacion de equivalencia de las vistas (Parte B punto 3, Parte C)
--
-- Dos controles por vista, porque uno solo no alcanza:
--   (a) diferencia simetrica con EXCEPT en los dos sentidos -> debe dar 0 filas
--   (b) comparacion de COUNT(*) -> hace falta porque EXCEPT elimina duplicados:
--       si la vista repitiera una fila y la consulta manual no, (a) daria 0
--       igual y no nos enterariamos.
-- ============================================================================

SET search_path TO foodstore;

\echo '--- 1) v_productos_vigentes: diferencia simetrica (esperado 0 filas) ---'
(SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes
 EXCEPT
 SELECT p.id, p.nombre, p.precio, p.stock, c.nombre
 FROM   producto p JOIN categoria c ON c.id = p.categoria_id
 WHERE  p.eliminado = FALSE AND c.eliminado = FALSE)
UNION ALL
(SELECT p.id, p.nombre, p.precio, p.stock, c.nombre
 FROM   producto p JOIN categoria c ON c.id = p.categoria_id
 WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
 EXCEPT
 SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes);

\echo '--- 1b) v_productos_vigentes: COUNT (esperado coinciden = t) ---'
SELECT (SELECT COUNT(*) FROM v_productos_vigentes) AS vista,
       (SELECT COUNT(*) FROM producto p JOIN categoria c ON c.id = p.categoria_id
        WHERE p.eliminado = FALSE AND c.eliminado = FALSE) AS manual,
       (SELECT COUNT(*) FROM v_productos_vigentes)
     = (SELECT COUNT(*) FROM producto p JOIN categoria c ON c.id = p.categoria_id
        WHERE p.eliminado = FALSE AND c.eliminado = FALSE) AS coinciden;

\echo '--- 2) v_pedidos_resumen: diferencia simetrica (esperado 0 filas) ---'
(SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen
 EXCEPT
 SELECT ped.id, u.nombre || ' ' || u.apellido, ped.fecha, ped.estado,
        ped.forma_pago, ped.total
 FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
 WHERE  ped.eliminado = FALSE)
UNION ALL
(SELECT ped.id, u.nombre || ' ' || u.apellido, ped.fecha, ped.estado,
        ped.forma_pago, ped.total
 FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
 WHERE  ped.eliminado = FALSE
 EXCEPT
 SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen);

\echo '--- 2b) v_pedidos_resumen: COUNT (esperado coinciden = t) ---'
SELECT (SELECT COUNT(*) FROM v_pedidos_resumen) AS vista,
       (SELECT COUNT(*) FROM pedido ped JOIN usuario u ON u.id = ped.usuario_id
        WHERE ped.eliminado = FALSE) AS manual,
       (SELECT COUNT(*) FROM v_pedidos_resumen)
     = (SELECT COUNT(*) FROM pedido ped JOIN usuario u ON u.id = ped.usuario_id
        WHERE ped.eliminado = FALSE) AS coinciden;

\echo '--- 3) v_pedido_detalle: diferencia simetrica (esperado 0 filas) ---'
(SELECT pedido_id, producto, cantidad, precio_unitario, subtotal FROM v_pedido_detalle
 EXCEPT
 SELECT dp.pedido_id, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal
 FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
 WHERE  dp.eliminado = FALSE)
UNION ALL
(SELECT dp.pedido_id, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal
 FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
 WHERE  dp.eliminado = FALSE
 EXCEPT
 SELECT pedido_id, producto, cantidad, precio_unitario, subtotal FROM v_pedido_detalle);

\echo '--- 3b) v_pedido_detalle: COUNT (esperado coinciden = t) ---'
SELECT (SELECT COUNT(*) FROM v_pedido_detalle) AS vista,
       (SELECT COUNT(*) FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
        WHERE dp.eliminado = FALSE) AS manual,
       (SELECT COUNT(*) FROM v_pedido_detalle)
     = (SELECT COUNT(*) FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
        WHERE dp.eliminado = FALSE) AS coinciden;

\echo '--- 3c) v_pedido_detalle: control propio, pedidos descuadrados (esperado 0) ---'
-- Si la vista escondiera renglones, la suma de subtotales dejaria de coincidir
-- con pedido.total. Es el control que delata a quien agregue el filtro
-- producto.eliminado "por consistencia".
SELECT COUNT(*) AS pedidos_descuadrados
FROM   pedido p
WHERE  p.eliminado = FALSE
  AND  p.total <> (SELECT COALESCE(SUM(d.subtotal), 0)
                   FROM v_pedido_detalle d WHERE d.pedido_id = p.id);

\echo '--- 4) v_usuarios_publico: diferencia simetrica (esperado 0 filas) ---'
(SELECT id, nombre, apellido, mail, celular, rol, created_at FROM v_usuarios_publico
 EXCEPT
 SELECT id, nombre, apellido, mail, celular, rol, created_at
 FROM   usuario WHERE eliminado = FALSE)
UNION ALL
(SELECT id, nombre, apellido, mail, celular, rol, created_at
 FROM   usuario WHERE eliminado = FALSE
 EXCEPT
 SELECT id, nombre, apellido, mail, celular, rol, created_at FROM v_usuarios_publico);

\echo '--- 4b) v_usuarios_publico: COUNT (esperado coinciden = t) ---'
SELECT (SELECT COUNT(*) FROM v_usuarios_publico) AS vista,
       (SELECT COUNT(*) FROM usuario WHERE eliminado = FALSE) AS manual,
       (SELECT COUNT(*) FROM v_usuarios_publico)
     = (SELECT COUNT(*) FROM usuario WHERE eliminado = FALSE) AS coinciden;

\echo '--- 5) mv_facturacion_categoria_mes: diferencia simetrica (esperado 0 filas) ---'
(SELECT categoria, mes, facturado FROM mv_facturacion_categoria_mes
 EXCEPT
 SELECT c.nombre, date_trunc('month', ped.fecha)::DATE, SUM(dp.subtotal)
 FROM   detalle_pedido dp
 JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
 JOIN   producto pr  ON pr.id  = dp.producto_id
 JOIN   categoria c  ON c.id   = pr.categoria_id
 WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
 GROUP  BY c.nombre, date_trunc('month', ped.fecha))
UNION ALL
(SELECT c.nombre, date_trunc('month', ped.fecha)::DATE, SUM(dp.subtotal)
 FROM   detalle_pedido dp
 JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
 JOIN   producto pr  ON pr.id  = dp.producto_id
 JOIN   categoria c  ON c.id   = pr.categoria_id
 WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
 GROUP  BY c.nombre, date_trunc('month', ped.fecha)
 EXCEPT
 SELECT categoria, mes, facturado FROM mv_facturacion_categoria_mes);

\echo '--- 5b) mv_facturacion_categoria_mes: COUNT ---'
SELECT COUNT(*) AS filas_materializadas FROM mv_facturacion_categoria_mes;
