-- ============================================================================
-- TP5 - Unidad 3, Semana 5 - Parte A
-- Plan de indexado de Food Store
--
-- Solo las sentencias ACEPTADAS. Lo que se propuso y se descarto esta en
-- duia.md, y las mediciones que respaldan cada decision en
-- informe_mediciones.md.
--
-- Punto de partida: los indices vigentes al cierre de la Semana 3
--   schema.sql  -> idx_producto_categoria_id, idx_pedido_usuario_id,
--                  idx_producto_no_eliminado
--   TP3         -> idx_detalle_pedido_producto_id, idx_pedido_fecha
--
-- Ejecutar sobre foodstore_test, nunca sobre foodstore directo
-- (protocolo de seguridad de la catedra, protocolo_seguridad.md).
-- ============================================================================

SET search_path TO foodstore;


-- ----------------------------------------------------------------------------
-- 1) Top 5 productos mas vendidos  (queries.sql, analitica A)
--    spec: specs/spec_indice_top_productos.md
--
-- La consulta no filtra nada: recorre las 800.008 filas vigentes de
-- detalle_pedido para agrupar por producto. Un indice "para filtrar" no
-- aplica; lo unico que se puede ganar es leer menos bytes que el heap.
--
-- key = (producto_id, cantidad), NO (producto_id) INCLUDE (cantidad).
-- Las dos variantes permiten Index Only Scan, pero solo la primera se
-- comprime: la deduplicacion de B-tree de PostgreSQL agrupa las claves
-- repetidas en una sola entrada con su lista de TIDs, y se desactiva en
-- cuanto el indice tiene columnas INCLUDE. Con 28 pares distintos sobre
-- 800.008 filas, la diferencia medida es 692 vs 3.084 paginas para el
-- mismo plan. Ver informe_mediciones.md, seccion "Triangulacion".
--
-- La condicion parcial va sobre eliminado porque la columna es ~100% FALSE:
-- como columna indexada no discrimina, como predicado achica el indice y lo
-- alinea al WHERE de todas las consultas del sistema.
CREATE INDEX idx_dp_top_productos
    ON detalle_pedido (producto_id, cantidad)
    WHERE eliminado = FALSE;

-- Reemplaza al indice heredado del TP3: misma tabla, mismo predicado, misma
-- columna lider. Todo lo que resolvia idx_detalle_pedido_producto_id lo
-- resuelve este. Conservar los dos seria pagar dos veces el mantenimiento
-- por la misma capacidad de busqueda.
-- Control corrido antes de borrarlo: la consulta "productos sin ventas"
-- (queries.sql, analitica E) sigue resolviendo por Index Only Scan, ahora
-- sobre idx_dp_top_productos.
DROP INDEX IF EXISTS idx_detalle_pedido_producto_id;


-- ----------------------------------------------------------------------------
-- 2) Ranking de usuarios por gasto acumulado  (queries.sql, analitica C)
--    spec: specs/spec_indice_ranking_usuarios.md
--
-- key = (usuario_id) para el JOIN y el GROUP BY; total viaja en INCLUDE
-- porque solo se suma: no filtra, no agrupa y no ordena, asi que no tiene
-- por que participar del orden del arbol.
--
-- Aca INCLUDE si conviene, al reves que en el indice 1: usuario_id tiene
-- 20.005 valores distintos sobre 200.003 filas, la deduplicacion casi no
-- tendria nada que comprimir, y meter total en la key encareceria cada
-- comparacion sin ganar nada.
--
-- No es redundante con idx_pedido_usuario_id (schema.sql): ese no es parcial,
-- asi que sigue siendo el unico que sirve para buscar pedidos de un usuario
-- incluyendo los dados de baja (HU-PED-04, auditoria).
CREATE INDEX idx_pedido_ranking_usuarios
    ON pedido (usuario_id) INCLUDE (total)
    WHERE eliminado = FALSE;


-- ----------------------------------------------------------------------------
-- 3) Pedidos cuyo total supera el promedio  (queries.sql, analitica D)
--    spec: specs/spec_indice_pedidos_sobre_promedio.md
--
-- El filtro devuelve el 50% de la tabla: no hay selectividad que aprovechar,
-- y se deja dicho a proposito. Lo que compra este indice es el ORDER BY:
-- las filas salen ya ordenadas por total y desaparece el "Sort Method:
-- external merge  Disk: 2640kB" del plan original. De paso, el AVG del
-- InitPlan tambien se resuelve por Index Only Scan.
--
-- El DESC documenta la intencion; PostgreSQL puede recorrer un B-tree hacia
-- atras, asi que ASC habria servido igual.
CREATE INDEX idx_pedido_sobre_promedio
    ON pedido (total DESC) INCLUDE (id)
    WHERE eliminado = FALSE;


-- ----------------------------------------------------------------------------
-- Precondicion de los tres: sin visibility map poblado no hay Index Only Scan
-- que evite el heap, y el planificador vuelve al Seq Scan.
VACUUM (ANALYZE) detalle_pedido;
VACUUM (ANALYZE) pedido;
