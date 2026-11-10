# Consigna 6 · Prompt para la herramienta de IA

Copiar el texto de abajo en la herramienta de IA que use el equipo. Guardar la respuesta completa en
`ia/respuesta_ia.md`, indicando la herramienta, el modelo y la fecha. El informe solo cita las dos
afirmaciones que se contrastan, porque la consigna no admite transcripciones extensas.

---

Estoy evaluando cómo almacenar los pedidos de "Food Store", una app de comida que hoy usa PostgreSQL.
El modelo actual es relacional: tablas `usuario`, `producto`, `categoria`, `pedido` (id, fecha, estado
ENUM PENDIENTE/CONFIRMADO/TERMINADO/CANCELADO, total NUMERIC(10,2), forma_pago, usuario_id FK) y
`detalle_pedido` (cantidad > 0, precio_unitario NUMERIC(10,2) congelado al comprar, subtotal,
pedido_id FK, producto_id FK, UNIQUE(pedido_id, producto_id)). Hay borrado lógico (columna `eliminado`),
triggers que calculan el subtotal y recalculan el total, y un procedimiento que crea el pedido en una
transacción, bloquea el producto con FOR UPDATE y descuenta stock.

El acceso más frecuente es leer un pedido completo (cabecera, cliente y todas sus líneas), y es
obligatorio que las cantidades, los precios históricos y los totales sean siempre coherentes entre sí y
con el stock.

Compará PostgreSQL y MongoDB para almacenar y consultar estos pedidos: modelo de datos (tablas con JOIN
frente a documento con líneas embebidas), consultas típicas, integridad y transacciones, precisión de
los importes y rendimiento. Recomendá si conviene mantener PostgreSQL, pasar este subconjunto a MongoDB
o combinar ambos, y justificá con criterios técnicos concretos.
