// TP Unidad 7 - Consigna 7: laboratorio para contrastar dos afirmaciones de la IA.
// Requisito previo: consultas_mongodb.js ya ejecutado (colección foodstore.pedidos).
// Trabaja sobre una copia (pedidos_lab) con el mismo validador, así que no modifica los datos migrados.
// Ejecutar con: mongosh --quiet --file laboratorio_ia.js

db = db.getSiblingDB("foodstore");
const esReplicaSet = (() => { try { return db.adminCommand({ replSetGetStatus: 1 }).ok === 1; } catch (e) { return false; } })();
print("Servidor: MongoDB " + db.version() + " | replica set: " + esReplicaSet);

db.pedidos_lab.drop();
db.createCollection("pedidos_lab", {
  validator: db.getCollectionInfos({ name: "pedidos" })[0].options.validator
});
db.pedidos_lab.insertMany(db.pedidos.find().toArray());

// =============================================================================
// Afirmación 1: "una operación de escritura sobre un único documento es atómica,
// incluso si modifica documentos embebidos", y para varios documentos hacen falta
// transacciones multidocumento (replica set).
// =============================================================================
print("\n== A1.a) Update válido que cambia una línea y el total en una sola operación ==");
// Pedido 2: la línea de Empanada de Carne (producto 4) pasa de 3 a 4 unidades (+150).
let r = db.pedidos_lab.updateOne(
  { _id: 2 },
  { $set: { "lineas.$[l].cantidad": 4, "lineas.$[l].subtotal": Decimal128("600.00"),
            total: Decimal128("1130.00") } },
  { arrayFilters: [ { "l.producto_id": 4 } ] }
);
print("modificados: " + r.modifiedCount);
printjson(db.pedidos_lab.findOne({ _id: 2 }, { total: 1, lineas: { $elemMatch: { producto_id: 4 } } }));

print("\n== A1.b) Update que cambia la cantidad pero olvida el total: se rechaza ENTERO ==");
try {
  db.pedidos_lab.updateOne(
    { _id: 2 },
    { $set: { "lineas.$[l].cantidad": 5, "lineas.$[l].subtotal": Decimal128("750.00") } },
    { arrayFilters: [ { "l.producto_id": 4 } ] }
  );
  print("ERROR: se aceptó un update incoherente");
} catch (e) {
  print("Rechazado: " + e.errmsg);
}
print("Estado del documento después del rechazo (sin cambios parciales):");
printjson(db.pedidos_lab.findOne({ _id: 2 }, { total: 1, lineas: { $elemMatch: { producto_id: 4 } } }));

print("\n== A1.c) Pedido + descuento de stock en DOS colecciones dentro de una transacción ==");
db.productos_lab.drop();
db.productos_lab.insertOne({ _id: 7, nombre: "Gaseosa 2L", stock: 30 });
const session = db.getMongo().startSession();
try {
  session.startTransaction();
  const sdb = session.getDatabase("foodstore");
  sdb.pedidos_lab.insertOne({
    _id: 8, fecha: new Date("2026-11-08"), estado: "PENDIENTE", forma_pago: "EFECTIVO",
    total: Decimal128("700.00"),
    cliente: { usuario_id: 5, nombre: "Ariagna", apellido: "Rodriguez" },
    lineas: [ { detalle_id: 20, producto_id: 7, nombre: "Gaseosa 2L", categoria: "Bebidas",
                cantidad: 2, precio_unitario: Decimal128("350.00"), subtotal: Decimal128("700.00") } ]
  });
  sdb.productos_lab.updateOne({ _id: 7, stock: { $gte: 2 } }, { $inc: { stock: -2 } });
  session.commitTransaction();
  print("Transacción confirmada. Pedido 8 existe: " + (db.pedidos_lab.countDocuments({ _id: 8 }) === 1) +
        " | stock Gaseosa: " + db.productos_lab.findOne({ _id: 7 }).stock);
} catch (e) {
  try { session.abortTransaction(); } catch (_) {}
  print("Transacción NO disponible: " + (e.errmsg || e.message));
  print("Pedido 8 existe: " + (db.pedidos_lab.countDocuments({ _id: 8 }) === 1) +
        " | stock Gaseosa: " + db.productos_lab.findOne({ _id: 7 }).stock);
} finally {
  session.endSession();
}

// =============================================================================
// Afirmación 2: double no representa exactamente fracciones decimales;
// Decimal128 sí ("equivalente a NUMERIC").
// =============================================================================
print("\n== A2) Suma de importes con centavos: double vs Decimal128 (aritmética en el servidor) ==");
db.importes_lab.drop();
db.importes_lab.insertMany([
  { tipo: "double",     montos: [0.10, 0.20, 1800.10, 1800.10, 1800.10] },
  { tipo: "Decimal128", montos: [Decimal128("0.10"), Decimal128("0.20"),
                                 Decimal128("1800.10"), Decimal128("1800.10"), Decimal128("1800.10")] }
]);
printjson(db.importes_lab.aggregate([
  { $project: { _id: 0, tipo: 1,
      suma_0_10_mas_0_20: { $add: [ { $arrayElemAt: ["$montos", 0] }, { $arrayElemAt: ["$montos", 1] } ] },
      es_igual_a_0_30: { $eq: [ { $add: [ { $arrayElemAt: ["$montos", 0] }, { $arrayElemAt: ["$montos", 1] } ] },
                                { $cond: [ { $eq: ["$tipo", "double"] }, 0.3, Decimal128("0.30") ] } ] },
      tres_x_1800_10: { $sum: { $slice: ["$montos", 2, 3] } },
      tipo_bson: { $type: { $arrayElemAt: ["$montos", 0] } } } }
]).toArray());

print("\nTotales de la colección migrada (Decimal128), suma exacta: " +
      db.pedidos.aggregate([{ $group: { _id: null, s: { $sum: "$total" } } }]).toArray()[0].s);

db.pedidos_lab.drop(); db.productos_lab.drop(); db.importes_lab.drop();
