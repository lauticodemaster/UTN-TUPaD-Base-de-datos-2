# TP Unidad 7 · NoSQL y nuevas formas de almacenamiento (Food Store)

Modelado del subconjunto «pedidos y detalle de pedidos» de Food Store en MongoDB, con verificación
contra PostgreSQL.

| Archivo | Contenido |
|---|---|
| [`informe/informe_u7.pdf`](informe/informe_u7.pdf) | Informe de entrega (se genera desde `informe_u7.html`) |
| [`consultas_mongodb.js`](consultas_mongodb.js) | Colección con validador, `insertMany()` de los 7 pedidos, controles de integridad y consultas a) a d) |
| [`consultas_postgresql.sql`](consultas_postgresql.sql) | Consultas equivalentes b) y c), más d) como referencia |
| [`sql/datos_prueba_postgresql.sql`](sql/datos_prueba_postgresql.sql) | Pedidos de prueba 4 a 7, creados con `sp_crear_pedido` |
| [`sql/exportar_pedidos_mongodb.sql`](sql/exportar_pedidos_mongodb.sql) | Genera desde PostgreSQL los documentos del `insertMany()` |
| [`sql/experimento_divergencia.sql`](sql/experimento_divergencia.sql) | Muestra cómo se desincronizan las copias (con `ROLLBACK`) |
| [`evidencias/`](evidencias/) | Salidas de ejecución de ambos motores |
| [`ia/prompt_consigna6.md`](ia/prompt_consigna6.md) / [`ia/respuesta_ia.md`](ia/respuesta_ia.md) | Consigna 6: prompt y respuesta de la IA |
| [`laboratorio_ia.js`](laboratorio_ia.js) | Consigna 7: pruebas de atomicidad, transacciones y `Decimal128` |

## Cómo reproducir

Requiere Docker. Los comandos se ejecutan desde la raíz del repositorio. En Git Bash para Windows, antes
hay que ejecutar `export MSYS_NO_PATHCONV=1`.

```bash
docker run -d --name fs_pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=foodstore postgres:17
docker run -d --name fs_mongo mongo:8.0
```

```bash
P="docker exec -i fs_pg psql -U postgres -d foodstore -v ON_ERROR_STOP=1"
echo "CREATE SCHEMA foodstore;" | $P
$P < TP1/schema.sql
sed '/^-- PRUEBA\./,$d' TP1/objects.sql | $P      # se omite el DELETE de prueba final
$P < TP1/data.sql
$P < "TP9 (Unidad 7)/sql/datos_prueba_postgresql.sql"
$P < "TP9 (Unidad 7)/consultas_postgresql.sql"
$P < "TP9 (Unidad 7)/sql/experimento_divergencia.sql"
```

```bash
docker cp "TP9 (Unidad 7)/consultas_mongodb.js" fs_mongo:/tmp/consultas_mongodb.js
docker exec fs_mongo mongosh --quiet --file /tmp/consultas_mongodb.js
```

Para regenerar los documentos del `insertMany()` (por ejemplo, si cambian los datos), ejecutá
`psql -At < sql/exportar_pedidos_mongodb.sql` y pegá la salida en `consultas_mongodb.js`.

### Laboratorio de la consigna 7

El script `laboratorio_ia.js` se ejecuta después de `consultas_mongodb.js`. La prueba de transacciones
multidocumento necesita un replica set. Con el contenedor standalone falla a propósito, como evidencia.

```bash
docker run -d --name fs_mongo_rs mongo:8.0 --replSet rs0
docker exec fs_mongo_rs mongosh --quiet --eval 'rs.initiate({_id:"rs0",members:[{_id:0,host:"localhost:27017"}]})'
docker cp "TP9 (Unidad 7)/consultas_mongodb.js" fs_mongo_rs:/tmp/consultas_mongodb.js
docker cp "TP9 (Unidad 7)/laboratorio_ia.js" fs_mongo_rs:/tmp/laboratorio_ia.js
docker exec fs_mongo_rs mongosh --quiet --file /tmp/consultas_mongodb.js
docker exec fs_mongo_rs mongosh --quiet --file /tmp/laboratorio_ia.js
```

El PDF se regenera desde `informe/informe_u7.html` (en Edge o Chrome: Imprimir → Guardar como PDF, sin
encabezados).
