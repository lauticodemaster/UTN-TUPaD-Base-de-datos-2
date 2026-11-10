-- TP Unidad 7 - Exportación de pedidos de PostgreSQL al formato documental.
-- Genera, por cada pedido vigente, el literal JavaScript que se pega en el insertMany()
-- de consultas_mongodb.js. Así los ids, importes, cantidades y estados salen de la base
-- y no se escriben a mano.
--
-- Uso: psql -At -f exportar_pedidos_mongodb.sql  (salida sin encabezados)

SET search_path TO foodstore;

SELECT format(
$doc$  {
    _id: %s,
    fecha: ISODate("%s"),
    estado: "%s",
    forma_pago: "%s",
    total: Decimal128("%s"),
    cliente: { usuario_id: %s, nombre: "%s", apellido: "%s" },
    lineas: [
%s
    ],
    origen: "%s"
  }$doc$,
    p.id,
    to_char(p.fecha, 'YYYY-MM-DD'),
    p.estado,
    p.forma_pago,
    p.total,
    u.id, u.nombre, u.apellido,
    (SELECT string_agg(
                format('      { detalle_id: %s, producto_id: %s, nombre: "%s", categoria: "%s", cantidad: %s, precio_unitario: Decimal128("%s"), subtotal: Decimal128("%s") }',
                       d.id, pr.id, pr.nombre, c.nombre, d.cantidad, d.precio_unitario, d.subtotal),
                E',\n' ORDER BY d.id)
     FROM detalle_pedido d
     JOIN producto  pr ON pr.id = d.producto_id
     JOIN categoria c  ON c.id  = pr.categoria_id
     WHERE d.pedido_id = p.id AND d.eliminado = FALSE),
    CASE WHEN p.id <= 3 THEN 'TP1/data.sql' ELSE 'prueba TP Unidad 7' END
) || CASE WHEN p.id < max(p.id) OVER () THEN ',' ELSE '' END
FROM   pedido  p
JOIN   usuario u ON u.id = p.usuario_id
WHERE  p.eliminado = FALSE
ORDER  BY p.id;
