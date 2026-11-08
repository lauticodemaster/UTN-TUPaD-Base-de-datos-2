// TP Unidad 7 - NoSQL | Food Store
// Base "foodstore", colección "pedidos": un documento por pedido, con el cliente y las
// líneas de detalle embebidas. Ejecutar con: mongosh --quiet --file consultas_mongodb.js
//
// Los documentos del insertMany() se generaron desde PostgreSQL con
// sql/exportar_pedidos_mongodb.sql. Los ids, importes, cantidades y estados son los de origen.

db = db.getSiblingDB("foodstore");
db.pedidos.drop();   // permite re-ejecutar el script desde cero

// ---------------------------------------------------------------------------
// 1) Creación de la colección con validación (reglas de integridad, consigna 3)
// ---------------------------------------------------------------------------
db.createCollection("pedidos", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "fecha", "estado", "forma_pago", "total", "cliente", "lineas"],
      properties: {
        _id:        { bsonType: "int", description: "pedido.id de PostgreSQL" },
        fecha:      { bsonType: "date" },
        estado:     { enum: ["PENDIENTE", "CONFIRMADO", "TERMINADO", "CANCELADO"] },
        forma_pago: { enum: ["TARJETA", "TRANSFERENCIA", "EFECTIVO"] },
        total:      { bsonType: "decimal", minimum: 0 },
        cliente: {
          bsonType: "object",
          required: ["usuario_id", "nombre", "apellido"],
          properties: { usuario_id: { bsonType: "int" } }
        },
        lineas: {
          bsonType: "array",
          minItems: 1,
          items: {
            bsonType: "object",
            required: ["detalle_id", "producto_id", "nombre", "cantidad", "precio_unitario", "subtotal"],
            properties: {
              producto_id:     { bsonType: "int" },
              cantidad:        { bsonType: "int", minimum: 1 },
              precio_unitario: { bsonType: "decimal", minimum: 0 },
              subtotal:        { bsonType: "decimal", minimum: 0 }
            }
          }
        }
      }
    },
    // Regla de coherencia de importes (equivale a trg_subtotal + trg_total_* de PostgreSQL):
    // total = suma de subtotales, y en cada línea subtotal = cantidad * precio_unitario.
    $expr: {
      $and: [
        { $eq: ["$total", { $sum: "$lineas.subtotal" }] },
        { $allElementsTrue: [ { $map: {
            input: "$lineas", as: "l",
            in: { $eq: ["$$l.subtotal", { $multiply: ["$$l.cantidad", "$$l.precio_unitario"] }] }
        } } ] }
      ]
    }
  }
});

// ---------------------------------------------------------------------------
// 2) Migración (consigna 2)
// ---------------------------------------------------------------------------
const resultadoInsert = db.pedidos.insertMany([
  {
    _id: 1,
    fecha: ISODate("2026-09-01"),
    estado: "CONFIRMADO",
    forma_pago: "EFECTIVO",
    total: Decimal128("3950.00"),
    cliente: { usuario_id: 1, nombre: "Miguel", apellido: "Herrera" },
    lineas: [
      { detalle_id: 1, producto_id: 1, nombre: "Fugazzeta", categoria: "Pizzas", cantidad: 2, precio_unitario: Decimal128("1800.00"), subtotal: Decimal128("3600.00") },
      { detalle_id: 2, producto_id: 7, nombre: "Gaseosa 2L", categoria: "Bebidas", cantidad: 1, precio_unitario: Decimal128("350.00"), subtotal: Decimal128("350.00") }
    ],
    origen: "TP1/data.sql"
  },
  {
    _id: 2,
    fecha: ISODate("2026-09-01"),
    estado: "PENDIENTE",
    forma_pago: "TARJETA",
    total: Decimal128("980.00"),
    cliente: { usuario_id: 3, nombre: "Iván", apellido: "Ivañez" },
    lineas: [
      { detalle_id: 3, producto_id: 4, nombre: "Empanada de Carne", categoria: "Empanadas", cantidad: 3, precio_unitario: Decimal128("150.00"), subtotal: Decimal128("450.00") },
      { detalle_id: 4, producto_id: 5, nombre: "Empanada de Pollo", categoria: "Empanadas", cantidad: 2, precio_unitario: Decimal128("140.00"), subtotal: Decimal128("280.00") },
      { detalle_id: 5, producto_id: 8, nombre: "Jugo Natural", categoria: "Bebidas", cantidad: 1, precio_unitario: Decimal128("250.00"), subtotal: Decimal128("250.00") }
    ],
    origen: "TP1/data.sql"
  },
  {
    _id: 3,
    fecha: ISODate("2026-09-01"),
    estado: "TERMINADO",
    forma_pago: "TRANSFERENCIA",
    total: Decimal128("2500.00"),
    cliente: { usuario_id: 5, nombre: "Ariagna", apellido: "Rodriguez" },
    lineas: [
      { detalle_id: 6, producto_id: 2, nombre: "Mozzarella", categoria: "Pizzas", cantidad: 1, precio_unitario: Decimal128("1600.00"), subtotal: Decimal128("1600.00") },
      { detalle_id: 7, producto_id: 9, nombre: "Flan Casero", categoria: "Postres", cantidad: 2, precio_unitario: Decimal128("200.00"), subtotal: Decimal128("400.00") },
      { detalle_id: 8, producto_id: 11, nombre: "Ensalada Verde", categoria: "Ensaladas", cantidad: 1, precio_unitario: Decimal128("500.00"), subtotal: Decimal128("500.00") }
    ],
    origen: "TP1/data.sql"
  },
  {
    _id: 4,
    fecha: ISODate("2026-10-14"),
    estado: "CONFIRMADO",
    forma_pago: "TARJETA",
    total: Decimal128("3060.00"),
    cliente: { usuario_id: 2, nombre: "Juliana", apellido: "Paredes" },
    lineas: [
      { detalle_id: 9, producto_id: 3, nombre: "Jamón y Queso", categoria: "Pizzas", cantidad: 1, precio_unitario: Decimal128("2000.00"), subtotal: Decimal128("2000.00") },
      { detalle_id: 10, producto_id: 7, nombre: "Gaseosa 2L", categoria: "Bebidas", cantidad: 2, precio_unitario: Decimal128("350.00"), subtotal: Decimal128("700.00") },
      { detalle_id: 11, producto_id: 10, nombre: "Brownie", categoria: "Postres", cantidad: 2, precio_unitario: Decimal128("180.00"), subtotal: Decimal128("360.00") }
    ],
    origen: "prueba TP Unidad 7"
  },
  {
    _id: 5,
    fecha: ISODate("2026-10-21"),
    estado: "TERMINADO",
    forma_pago: "EFECTIVO",
    total: Decimal128("1770.00"),
    cliente: { usuario_id: 4, nombre: "Ramón", apellido: "Garzón" },
    lineas: [
      { detalle_id: 12, producto_id: 4, nombre: "Empanada de Carne", categoria: "Empanadas", cantidad: 6, precio_unitario: Decimal128("150.00"), subtotal: Decimal128("900.00") },
      { detalle_id: 13, producto_id: 6, nombre: "Empanada de Queso", categoria: "Empanadas", cantidad: 4, precio_unitario: Decimal128("130.00"), subtotal: Decimal128("520.00") },
      { detalle_id: 14, producto_id: 7, nombre: "Gaseosa 2L", categoria: "Bebidas", cantidad: 1, precio_unitario: Decimal128("350.00"), subtotal: Decimal128("350.00") }
    ],
    origen: "prueba TP Unidad 7"
  },
  {
    _id: 6,
    fecha: ISODate("2026-10-30"),
    estado: "CANCELADO",
    forma_pago: "TRANSFERENCIA",
    total: Decimal128("1200.00"),
    cliente: { usuario_id: 1, nombre: "Miguel", apellido: "Herrera" },
    lineas: [
      { detalle_id: 15, producto_id: 12, nombre: "Ensalada César", categoria: "Ensaladas", cantidad: 1, precio_unitario: Decimal128("700.00"), subtotal: Decimal128("700.00") },
      { detalle_id: 16, producto_id: 8, nombre: "Jugo Natural", categoria: "Bebidas", cantidad: 2, precio_unitario: Decimal128("250.00"), subtotal: Decimal128("500.00") }
    ],
    origen: "prueba TP Unidad 7"
  },
  {
    _id: 7,
    fecha: ISODate("2026-11-02"),
    estado: "TERMINADO",
    forma_pago: "EFECTIVO",
    total: Decimal128("3750.00"),
    cliente: { usuario_id: 3, nombre: "Iván", apellido: "Ivañez" },
    lineas: [
      { detalle_id: 17, producto_id: 2, nombre: "Mozzarella", categoria: "Pizzas", cantidad: 2, precio_unitario: Decimal128("1600.00"), subtotal: Decimal128("3200.00") },
      { detalle_id: 18, producto_id: 7, nombre: "Gaseosa 2L", categoria: "Bebidas", cantidad: 1, precio_unitario: Decimal128("350.00"), subtotal: Decimal128("350.00") },
      { detalle_id: 19, producto_id: 9, nombre: "Flan Casero", categoria: "Postres", cantidad: 1, precio_unitario: Decimal128("200.00"), subtotal: Decimal128("200.00") }
    ],
    origen: "prueba TP Unidad 7"
  }
]);
print("Documentos insertados: " + Object.keys(resultadoInsert.insertedIds).length);

// Índices para las consultas frecuentes (por estado y por producto dentro de las líneas)
db.pedidos.createIndex({ estado: 1 });
db.pedidos.createIndex({ "lineas.producto_id": 1 });

// ---------------------------------------------------------------------------
// 3) Verificación de integridad posterior a la migración (consigna 3)
//    Debe devolver 0 documentos: total = suma de subtotales y subtotal = cantidad * precio.
// ---------------------------------------------------------------------------
print("\n== Verificación: documentos con importes incoherentes (esperado: ninguno) ==");
printjson(db.pedidos.aggregate([
  { $project: {
      total: 1,
      suma_subtotales: { $sum: "$lineas.subtotal" },
      lineas_mal: { $size: { $filter: {
          input: "$lineas", as: "l",
          cond: { $ne: ["$$l.subtotal", { $multiply: ["$$l.cantidad", "$$l.precio_unitario"] }] }
      } } }
  } },
  { $match: { $or: [ { $expr: { $ne: ["$total", "$suma_subtotales"] } }, { lineas_mal: { $gt: 0 } } ] } }
]).toArray());

print("\n== Verificación: el validador rechaza una línea con cantidad 0 ==");
try {
  db.pedidos.insertOne({
    _id: 999, fecha: new Date(), estado: "PENDIENTE", forma_pago: "EFECTIVO",
    total: Decimal128("0.00"),
    cliente: { usuario_id: 1, nombre: "Prueba", apellido: "Validador" },
    lineas: [ { detalle_id: 999, producto_id: 1, nombre: "Fugazzeta", cantidad: 0,
                precio_unitario: Decimal128("1800.00"), subtotal: Decimal128("0.00") } ]
  });
  print("ERROR: el documento inválido fue aceptado");
} catch (e) {
  print("Rechazado: " + e.errmsg);
}

print("\n== Verificación: el validador rechaza un total que no coincide con sus líneas ==");
try {
  db.pedidos.insertOne({
    _id: 998, fecha: new Date(), estado: "PENDIENTE", forma_pago: "EFECTIVO",
    total: Decimal128("5000.00"),   // la línea suma 3600.00
    cliente: { usuario_id: 1, nombre: "Prueba", apellido: "Validador" },
    lineas: [ { detalle_id: 998, producto_id: 1, nombre: "Fugazzeta", cantidad: 2,
                precio_unitario: Decimal128("1800.00"), subtotal: Decimal128("3600.00") } ]
  });
  print("ERROR: el documento inválido fue aceptado");
} catch (e) {
  print("Rechazado: " + e.errmsg);
}

// ---------------------------------------------------------------------------
// 4) Consultas (consigna 4)
// ---------------------------------------------------------------------------

// a) Todos los pedidos, con su identificador y estado
print("\n== a) Todos los pedidos (id y estado) ==");
printjson(db.pedidos.find({}, { _id: 1, estado: 1 }).sort({ _id: 1 }).toArray());

// b) Pedidos en un estado existente en los datos migrados: TERMINADO
print("\n== b) Pedidos con estado TERMINADO ==");
printjson(db.pedidos.find({ estado: "TERMINADO" }, { _id: 1, estado: 1, fecha: 1, total: 1 })
                    .sort({ _id: 1 }).toArray());
print("Cantidad: " + db.pedidos.countDocuments({ estado: "TERMINADO" }));

// c) Pedidos que contienen un producto determinado: Gaseosa 2L (producto_id 7 en PostgreSQL)
//    Se filtra por el id conservado y no por el nombre, que puede cambiar en el catálogo.
print("\n== c) Pedidos que contienen el producto 7 (Gaseosa 2L) ==");
printjson(db.pedidos.find({ "lineas.producto_id": 7 },
                          { _id: 1, estado: 1, "lineas.$": 1 })
                    .sort({ _id: 1 }).toArray());
print("Cantidad: " + db.pedidos.countDocuments({ "lineas.producto_id": 7 }));

// d) Pedidos cuyo total supera $2500. Umbral: el promedio de los 7 pedidos migrados es
//    17210 / 7 = 2458,57; se redondea a 2500 para separar los pedidos por encima de la media.
//    El pedido 3 vale exactamente 2500 y NO debe aparecer ($gt es estricto).
print("\n== d) Pedidos con total > 2500 ==");
printjson(db.pedidos.find({ total: { $gt: Decimal128("2500") } }, { _id: 1, estado: 1, total: 1 })
                    .sort({ _id: 1 }).toArray());
print("Promedio de totales: " + db.pedidos.aggregate([
  { $group: { _id: null, promedio: { $avg: "$total" } } }
]).toArray()[0].promedio);

// Evidencia: la consulta c) usa el índice multikey sobre lineas.producto_id
print("\n== Plan de la consulta c) ==");
const plan = db.pedidos.find({ "lineas.producto_id": 7 }).explain("executionStats");
print("Etapa: " + plan.queryPlanner.winningPlan.inputStage?.stage +
      " | índice: " + plan.queryPlanner.winningPlan.inputStage?.indexName +
      " | docs examinados: " + plan.executionStats.totalDocsExamined +
      " | devueltos: " + plan.executionStats.nReturned);
