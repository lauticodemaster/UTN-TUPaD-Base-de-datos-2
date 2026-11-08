# Consigna 6 · Respuesta de la herramienta de IA

- **Herramienta:** Claude (modelo Claude Opus 5.5, Anthropic), usado desde Claude Code.
- **Fecha:** 2026-11-08.
- **Prompt:** el de [`prompt_consigna6.md`](prompt_consigna6.md), sin cambios.
- **Advertencia metodológica:** la misma herramienta armó el laboratorio de este TP, así que la respuesta
  no es independiente de él. Por eso el contraste de la consigna 7 se apoya en documentación oficial de
  MongoDB y en pruebas ejecutadas, no en la opinión de la IA.

---

## Respuesta

**1. Modelo de datos.** En PostgreSQL, un pedido completo se reconstruye con un JOIN entre `pedido`,
`detalle_pedido`, `producto` y `usuario`. En MongoDB, lo natural es un documento por pedido con las
líneas embebidas en un arreglo y un resumen del cliente. Como las líneas solo existen dentro de su pedido
y se leen siempre con él, embeberlas sigue la recomendación de MongoDB para relaciones uno a pocos de
tipo «contiene». El documento debe guardar el snapshot del producto (nombre y precio al comprar), no una
referencia al precio vigente.

**2. Consultas típicas.** Leer un pedido completo en MongoDB es una sola lectura por `_id`, sin JOIN.
Buscar pedidos que contengan un producto se resuelve con `{"lineas.producto_id": X}` y un índice
multikey. Los reportes que cruzan pedidos con el catálogo o con usuarios (ventas por categoría, stock,
clientes) son más simples en SQL; en MongoDB requieren `$lookup` o duplicar datos.

**3. Integridad y transacciones.** En MongoDB, **una operación de escritura sobre un único documento es
atómica, incluso si modifica documentos embebidos**. Por eso, escribir un pedido con todas sus líneas
embebidas es todo o nada sin necesidad de una transacción. Pero crear un pedido en Food Store también
descuenta stock en `producto`, que estaría en otra colección. Para eso hacen falta **transacciones
multidocumento**, disponibles desde MongoDB 4.0 (con replica set). La documentación advierte que tienen
mayor costo de rendimiento y que no deberían reemplazar un buen diseño de esquema. PostgreSQL ya resuelve
todo esto con ACID, `FOR UPDATE`, claves foráneas y triggers.

**4. Precisión de importes.** Los importes no deben guardarse como `double` (binario de punto flotante),
porque valores como 0,1 no tienen representación exacta y las sumas acumulan errores de redondeo. En
MongoDB se usa **`Decimal128`** (decimal de 128 bits con 34 dígitos significativos), que es el
equivalente de `NUMERIC(10,2)` de PostgreSQL.

**5. Validación.** MongoDB permite validación con `$jsonSchema` para tipos, campos obligatorios, rangos y
enumeraciones. No hay claves foráneas: la existencia del producto o del usuario debe controlarla la
aplicación.

**6. Rendimiento.** El documento embebido tiene ventaja en la lectura frecuente del pedido completo,
aunque con índices adecuados PostgreSQL también resuelve esa lectura en milisegundos para volúmenes como
los de una tienda. El límite de 16 MB por documento no es un problema para pedidos de pocas líneas.

**Recomendación.** Mantener PostgreSQL como fuente de verdad de los pedidos, porque la coherencia entre
pedido, líneas, precios y stock es transaccional y abarca varias entidades. MongoDB solo se justificaría
como almacén secundario de lectura (por ejemplo, historial de pedidos o vista de cliente) alimentado desde
PostgreSQL. En ese caso hay que asumir el costo de sincronizar las dos copias.
