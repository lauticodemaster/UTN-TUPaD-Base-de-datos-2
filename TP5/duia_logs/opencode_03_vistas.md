
```sql
SET search_path TO foodstore;

-- ============================================================
-- (a) v_usuarios_publico + rol app_lectura
-- ============================================================
CREATE OR REPLACE VIEW v_usuarios_publico AS
SELECT id,
       nombre,
       apellido,
       mail,
       celular,
       rol,
       created_at
FROM   usuario
WHERE  eliminado = FALSE;

CREATE ROLE app_lectura NOLOGIN;

GRANT USAGE ON SCHEMA foodstore TO app_lectura;
GRANT SELECT ON v_usuarios_publico TO app_lectura;
-- Intencionalmente NO hay ningun GRANT sobre la tabla usuario.
REVOKE ALL ON usuario FROM app_lectura;

-- ============================================================
-- (b) MV facturacion por categoria y mes
-- ============================================================
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes WITH DATA AS
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha)::DATE AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
JOIN   producto pr  ON pr.id  = dp.producto_id
JOIN   categoria c  ON c.id   = pr.categoria_id
WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
GROUP  BY c.nombre, date_trunc('month', ped.fecha);
-- Sin ORDER BY dentro: el orden se pide al consultar.

CREATE UNIQUE INDEX uq_mv_facturacion_cat_mes
  ON mv_facturacion_categoria_mes (categoria, mes);
```

```sql
-- ============================================================
-- (c1) Equivalencia v_productos_vigentes
-- ============================================================
-- Diferencia simetrica: debe dar 0 filas en ambos sentidos.
(SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
 FROM producto p JOIN categoria c ON c.id = p.categoria_id
 WHERE p.eliminado = FALSE AND c.eliminado = FALSE
 EXCEPT
 SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes)
UNION ALL
(SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes
 EXCEPT
 SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
 FROM producto p JOIN categoria c ON c.id = p.categoria_id
 WHERE p.eliminado = FALSE AND c.eliminado = FALSE);

SELECT (SELECT COUNT(*) FROM v_productos_vigentes) AS vista,
       (SELECT COUNT(*) FROM producto p JOIN categoria c ON c.id = p.categoria_id
        WHERE p.eliminado = FALSE AND c.eliminado = FALSE) AS manual;

-- ============================================================
-- (c2) Equivalencia v_pedidos_resumen
-- ============================================================
(SELECT ped.id, u.nombre || ' ' || u.apellido AS usuario,
        ped.fecha, ped.estado, ped.forma_pago, ped.total
 FROM pedido ped JOIN usuario u ON u.id = ped.usuario_id
 WHERE ped.eliminado = FALSE
 EXCEPT
 SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen)
UNION ALL
(SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen
 EXCEPT
 SELECT ped.id, u.nombre || ' ' || u.apellido AS usuario,
        ped.fecha, ped.estado, ped.forma_pago, ped.total
 FROM pedido ped JOIN usuario u ON u.id = ped.usuario_id
 WHERE ped.eliminado = FALSE);

SELECT (SELECT COUNT(*) FROM v_pedidos_resumen) AS vista,
       (SELECT COUNT(*) FROM pedido ped JOIN usuario u ON u.id = ped.usuario_id
        WHERE ped.eliminado = FALSE) AS manual;

-- ============================================================
-- (c3) Equivalencia v_pedido_detalle + control de descuadre
-- ============================================================
(SELECT dp.pedido_id, pr.nombre AS producto,
        dp.cantidad, dp.precio_unitario, dp.subtotal
 FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
 WHERE dp.eliminado = FALSE
 EXCEPT
 SELECT pedido_id, producto, cantidad, precio_unitario, subtotal FROM v_pedido_detalle)
UNION ALL
(SELECT pedido_id, producto, cantidad, precio_unitario, subtotal FROM v_pedido_detalle
 EXCEPT
 SELECT dp.pedido_id, pr.nombre AS producto,
        dp.cantidad, dp.precio_unitario, dp.subtotal
 FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
 WHERE dp.eliminado = FALSE);

SELECT (SELECT COUNT(*) FROM v_pedido_detalle) AS vista,
       (SELECT COUNT(*) FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
        WHERE dp.eliminado = FALSE) AS manual;

-- Control propio del spec: 0 pedidos descuadrados.
SELECT COUNT(*) AS pedidos_descuadrados
FROM pedido p
WHERE p.eliminado = FALSE
  AND p.total <> (SELECT COALESCE(SUM(d.subtotal), 0) FROM v_pedido_detalle d
                  WHERE d.pedido_id = p.id);

-- ============================================================
-- (c4) Equivalencia v_usuarios_publico + controles de seguridad
-- ============================================================
(SELECT id, nombre, apellido, mail, celular, rol, created_at
 FROM usuario WHERE eliminado = FALSE
 EXCEPT
 SELECT id, nombre, apellido, mail, celular, rol, created_at FROM v_usuarios_publico)
UNION ALL
(SELECT id, nombre, apellido, mail, celular, rol, created_at FROM v_usuarios_publico
 EXCEPT
 SELECT id, nombre, apellido, mail, celular, rol, created_at
 FROM usuario WHERE eliminado = FALSE);

SELECT (SELECT COUNT(*) FROM v_usuarios_publico) AS vista,
       (SELECT COUNT(*) FROM usuario WHERE eliminado = FALSE) AS manual;

-- Debe fallar con "column contrasena does not exist":
SELECT contrasena FROM v_usuarios_publico;

-- Debe leer la vista pero recibir "permission denied" en la tabla:
SET ROLE app_lectura;
SELECT * FROM v_usuarios_publico LIMIT 5;  -- OK
SELECT * FROM usuario LIMIT 5;             -- permission denied
RESET ROLE;

-- ============================================================
-- (c5) Equivalencia MV contra consulta original
-- ============================================================
(SELECT c.nombre AS categoria,
        date_trunc('month', ped.fecha)::DATE AS mes,
        SUM(dp.subtotal) AS facturado
 FROM detalle_pedido dp
 JOIN pedido ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
 JOIN producto pr ON pr.id = dp.producto_id
 JOIN categoria c ON c.id = pr.categoria_id
 WHERE dp.eliminado = FALSE AND c.eliminado = FALSE
 GROUP BY c.nombre, date_trunc('month', ped.fecha)
 EXCEPT
 SELECT categoria, mes, facturado FROM mv_facturacion_categoria_mes)
UNION ALL
(SELECT categoria, mes, facturado FROM mv_facturacion_categoria_mes
 EXCEPT
 SELECT c.nombre AS categoria,
        date_trunc('month', ped.fecha)::DATE AS mes,
        SUM(dp.subtotal) AS facturado
 FROM detalle_pedido dp
 JOIN pedido ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
 JOIN producto pr ON pr.id = dp.producto_id
 JOIN categoria c ON c.id = pr.categoria_id
 WHERE dp.eliminado = FALSE AND c.eliminado = FALSE
 GROUP BY c.nombre, date_trunc('month', ped.fecha));

SELECT (SELECT COUNT(*) FROM mv_facturacion_categoria_mes) AS vista,
       29 AS esperado_segun_spec;

-- Lectura ordenada (el ORDER BY va aqui, no en la MV):
SELECT categoria, mes, facturado FROM mv_facturacion_categoria_mes
ORDER BY mes DESC, facturado DESC;
```

Decisiones:

**(a) `v_usuarios_publico`:**
- Columnas una por una (`id, nombre, apellido, mail, celular, rol, created_at`), nunca `SELECT *`. Es requisito explícito del spec (`TP5/specs/spec_vistas_reportes.md:55`): una columna futura no debe auto-exponerse. `contrasena` queda fuera por diseño, no por filtro.
- Tipos verificados contra `TP1/schema.sql:37-47`: `rol` es enum `rol`, `created_at` es `timestamptz`, resto coincide con lo pedido. No hago casts para que el `EXCEPT` compare tipos idénticos.
- Filtro `eliminado = FALSE` solo sobre `usuario`, tal como pide el spec. Es vista de entidad simple, sin JOIN, así que no aplica la discusión de vigencia de históricos.
- Rol: `NOLOGIN` porque es un rol de acceso para heredar, no un usuario de conexión. `GRANT USAGE ON SCHEMA` es obligatorio: sin él, el `GRANT SELECT` sobre la vista no sirve (falla con `permission denied for schema`). `GRANT SELECT` solo sobre la vista + `REVOKE ALL ON usuario` garantiza el criterio 3: en Postgres el lector solo necesita permiso sobre la vista (el dueño de la vista es quien accede a la tabla base), así que no hace falta `SECURITY DEFINER`.

**(b) MV:**
- Copio la consulta del spec (`TP5/specs/spec_mv_facturacion_categoria_mes.md:9-18`) literal, incluyendo `ped.eliminado = FALSE` en el `JOIN` y `dp.eliminado / c.eliminado` en el `WHERE`. No filtro `pr.eliminado`: cambiarlo rompería la equivalencia con el reporte original y contradice la decisión de no filtrar históricos.
- `WITH DATA` (requisito 1): la vista nace poblada y consultable de inmediato.
- Índice `UNIQUE (categoria, mes)` (requisito 2): es la llave natural del `GROUP BY`. Sin él, `REFRESH CONCURRENTLY` está prohibido por Postgres. Lo creo ahora aunque el refresh de hoy sea bloqueante.
- Quito el `ORDER BY` original (requisito 3): una MV es un heap almacenado, el orden de inserción no garantiza orden de lectura. El `ORDER BY mes DESC, facturado DESC` va en cada `SELECT` que la consuma.

**(c) Verificaciones:**
- Para las 5 relaciones uso el mismo patrón que exige el spec: diferencia simétrica (`EXCEPT` en ambos sentidos, unidos con `UNION ALL`) = 0 filas, más `COUNT(*)` coincidente. Un solo `EXCEPT` no basta: detecta filas sobrantes en un sentido pero no en el otro.
- La consulta "manual" de cada bloque es la definición ya existente en `TP1/objects.sql:5-26` (vistas 1-3), la definición nueva (vista 4) y la consulta del spec (MV). Así la vista se compara contra exactamente lo que reemplaza.
- Vista 3 suma el control propio del spec (`spec_vistas_reportes.md:43-45`): pedidos vigentes donde `pedido.total <> SUM(subtotal)` deben ser 0. Si alguien agrega el filtro `producto.eliminado` "por consistencia", este control lo delata.
- Vista 4 suma los dos controles de seguridad del spec: `SELECT contrasena` debe fallar a nivel catálogo, y el bloque `SET ROLE app_lectura` prueba el permiso real (lee vista, deniega tabla).
