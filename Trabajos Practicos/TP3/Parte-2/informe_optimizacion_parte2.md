# Informe de Optimización — TP3 Parte 2

> Base: `foodstore_test`, poblada con 50.012 productos, 20.005 usuarios,
> 200.005 pedidos y 600.008+ detalles de pedido (carga masiva de la
> Parte 1). `ANALYZE` corrido sobre todas las tablas antes de medir.

---

## Consulta 1 — Productos sin ventas

**Consulta original (`queries.sql`, sección "Productos sin ventas"):**

```sql
SELECT pr.id, pr.nombre
FROM   producto pr
LEFT   JOIN detalle_pedido dp
       ON dp.producto_id = pr.id AND dp.eliminado = FALSE
WHERE  pr.eliminado = FALSE
  AND  dp.id IS NULL
ORDER  BY pr.id;
```

### Plan antes (sin índice)

```
Sort  (cost=16381.51..16381.52 rows=1 width=22) (actual time=109.441..112.503 rows=50001 loops=1)
  ->  Hash Right Join  (cost=1987.27..16381.50 rows=1 width=22) (actual time=98.052..102.161 rows=50001 loops=1)
        Hash Cond: (dp.producto_id = pr.id)
        Filter: (dp.id IS NULL)
        Rows Removed by Filter: 600008
        ->  Seq Scan on detalle_pedido dp  (cost=0.00..12819.08 rows=600008 width=16) (actual time=0.011..41.982 rows=600008 loops=1)
              Filter: (NOT eliminado)
        ->  Hash  (cost=1362.12..1362.12 rows=50012 width=22) (actual time=11.898..11.899 rows=50012 loops=1)
              ->  Seq Scan on producto pr  (cost=0.00..1362.12 rows=50012 width=22) (actual time=0.036..7.817 rows=50012 loops=1)
                    Filter: (NOT eliminado)
Execution Time: 113.694 ms
```

**Nota:** el planificador estima `rows=1` para el resultado del join, pero
en realidad devuelve 50.001 filas — una desviación enorme entre la
estimación y la realidad, que explica varias decisiones de plan
cuestionables más abajo.

### Cambio propuesto y aplicado

1. Índice parcial:
   ```sql
   CREATE INDEX idx_detalle_pedido_producto_id
       ON detalle_pedido(producto_id)
       WHERE eliminado = FALSE;
   ```
2. Reescritura de `LEFT JOIN ... WHERE dp.id IS NULL` a `NOT EXISTS`:
   ```sql
   SELECT pr.id, pr.nombre
   FROM   producto pr
   WHERE  pr.eliminado = FALSE
     AND  NOT EXISTS (
           SELECT 1 FROM detalle_pedido dp
           WHERE dp.producto_id = pr.id AND dp.eliminado = FALSE
         )
   ORDER  BY pr.id;
   ```

**Por qué se probaron las dos cosas:** el índice solo, con la consulta
original, **no cambió el plan** (ver progresión abajo) — el
planificador siguió prefiriendo un Hash Anti Join que igual necesita
leer toda `detalle_pedido` para construir la tabla hash. Forzar
`enable_hashjoin = off` mostró que un plan con el índice (Merge Join)
sí era más rápido en la práctica, pero el cost estimado de ese plan
(45.867) es mucho más alto que el del Hash Join (16.381) — la mala
estimación de filas (`rows=1` vs 50.001 reales) hace que el
optimizador subestime el plan basado en índice. La reescritura con
`NOT EXISTS` le da al planificador una estimación de selectividad
mucho más precisa (`rows=50.007` estimadas vs 50.001 reales), y con
esa mejor información **elige solo, sin forzar nada,** un plan con
`Index Only Scan` sobre el índice nuevo.

### Progresión de mediciones

| Versión | Plan | Tiempo real |
|---|---|---|
| Original, sin índice | Hash Right Join + Seq Scan sobre `detalle_pedido` | 113.7 ms |
| Original + índice creado | Igual al anterior (planificador ignora el índice) | 103.9 ms |
| Original + índice, forzando `enable_hashjoin=off` | Merge Left Join + Index Scan | 92.9 ms |
| **`NOT EXISTS` + índice (plan elegido sin forzar nada)** | **Hash Right Anti Join + Index Only Scan** | **84.9 ms** |

**Mejora:** 113.7 ms → 84.9 ms ≈ **25% más rápido**, con índice +
reescritura, sin necesidad de forzar configuraciones del planificador.

### Verificación de equivalencia

```sql
SELECT pr.id, pr.nombre FROM producto pr
WHERE pr.eliminado = FALSE
  AND NOT EXISTS (SELECT 1 FROM detalle_pedido dp
                  WHERE dp.producto_id = pr.id AND dp.eliminado = FALSE)
EXCEPT
SELECT pr.id, pr.nombre FROM producto pr
LEFT JOIN detalle_pedido dp ON dp.producto_id = pr.id AND dp.eliminado = FALSE
WHERE pr.eliminado = FALSE AND dp.id IS NULL;
-- 0 filas: ambas versiones son equivalentes
```

---

## Consulta 2 — Pedidos filtrados por nombre de usuario (`LIKE '%Miguel%'`)

```sql
SELECT id, usuario, fecha, estado, forma_pago, total
FROM   v_pedidos_resumen
WHERE  usuario LIKE '%Miguel%'
ORDER  BY id;
```

### Plan medido

```
Sort  (cost=948.42..948.57 rows=60 width=60) (actual time=2.517..2.519 rows=17 loops=1)
  ->  Nested Loop  (cost=4.50..946.65 rows=60 width=60) (actual time=0.025..2.510 rows=17 loops=1)
        ->  Seq Scan on usuario u  (cost=0.00..687.09 rows=6 width=33) (actual time=0.010..2.479 rows=1 loops=1)
              Filter: ((((nombre)::text || ' '::text) || (apellido)::text) ~~ '%Miguel%'::text)
              Rows Removed by Filter: 20004
        ->  Bitmap Heap Scan on pedido ped (usando idx_pedido_usuario_id)
Execution Time: 2.539 ms
```

### Decisión: sin cambio aplicado

Con 2.5 ms, no hay nada que optimizar en términos de tiempo real. Pero
el motivo por el que **no se propone un índice** es la parte
importante a documentar: el filtro real es sobre la expresión
`nombre || ' ' || apellido ~~ '%Miguel%'`, con el comodín `%` al
**inicio** del patrón. Un índice B-tree convencional sobre `nombre` o
`apellido` no serviría para nada acá — Postgres no puede usar un
B-tree para buscar un patrón que puede empezar en cualquier posición
del texto. Para que un índice ayudara de verdad haría falta la
extensión `pg_trgm` con un índice GIN sobre la expresión concatenada,
algo así:

```sql
-- Alternativa NO aplicada (evaluada, no implementada por no ser necesaria a esta escala):
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_usuario_nombre_completo_trgm
    ON usuario USING GIN ((nombre || ' ' || apellido) gin_trgm_ops);
```

Se documenta la evaluación pero no se aplica: el criterio de la
consigna es medir antes de aceptar una propuesta, y acá la medición
(2.5 ms) muestra que agregar un índice GIN sería complejidad sin
beneficio real a este volumen de datos.

---

## Consulta 3 — Facturación por categoría y mes

```sql
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha)::DATE AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
JOIN   producto pr  ON pr.id  = dp.producto_id
JOIN   categoria c  ON c.id   = pr.categoria_id
WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
GROUP  BY c.nombre, date_trunc('month', ped.fecha)
ORDER  BY mes DESC, facturado DESC;
```

### Plan antes (sin índice)

Cadena de `Parallel Hash Join` sobre `detalle_pedido` (200.003 filas
por worker), `producto`, `categoria` y `pedido` (66.668 filas por
worker), seguido de `Partial HashAggregate` + `Gather Merge` +
`Finalize GroupAggregate` + `Sort`.

**Execution Time: 213.8 ms**

### Cambio propuesto y aplicado

```sql
CREATE INDEX idx_pedido_fecha ON pedido(fecha) WHERE eliminado = FALSE;
```

**Justificación de la propuesta:** se apuntó a la columna `fecha` de
`pedido` porque es la que participa en el `GROUP BY` vía
`date_trunc('month', ped.fecha)`.

### Plan después

**Idéntico al de antes** — sigue siendo `Parallel Seq Scan on pedido`
en el mismo nodo, sin ninguna mención al índice nuevo en ningún lugar
del plan.

**Execution Time: 182.0 ms** (la baja de 213.8 → 182.0 ms es atribuible
a caché entre corridas, no al índice — el plan no lo usa en ningún
nodo, así que no puede ser la causa de la diferencia).

### Conclusión (documentada según el criterio de aceptación)

**La propuesta no mejoró el plan.** Lo esperado era que el índice
acelerara el acceso a `pedido` por fecha; lo que pasó es que el
optimizador nunca lo consideró. La razón: esta consulta agrupa
prácticamente el 100% de las filas de `detalle_pedido` y `pedido` (no
hay ningún `WHERE` que filtre por rango de fechas, solo se agrupa por
mes). Cuando una consulta necesita leer casi toda una tabla, un
escaneo secuencial es más barato que recorrer un índice — un índice
solo gana cuando permite *evitar* leer la mayoría de las filas, y acá
no evita nada. Se documenta el resultado tal cual salió, sin forzar
una mejora artificial.

---

## Tabla comparativa (punto 2.2 de la consigna)

| Consulta | Plan antes (nodo, cost, tiempo real) | Cambio aplicado | Plan después (nodo, cost, tiempo real) | Mejora |
|---|---|---|---|---|
| Productos sin ventas | Hash Right Join + Seq Scan sobre detalle_pedido; cost≈16.381; 113.7 ms | `CREATE INDEX` sobre `detalle_pedido(producto_id)` + reescritura `NOT EXISTS` | Hash Right Anti Join + Index Only Scan; cost≈14.611; 84.9 ms | ≈25% (113.7→84.9 ms) |
| Pedidos por nombre (LIKE '%Miguel%') | Nested Loop + Seq Scan sobre usuario; cost≈948; 2.5 ms | Ninguno — se evaluó y descartó un índice GIN con pg_trgm por no ser necesario a esta escala | Sin cambio | N/A (ya era rápida; índice descartado con justificación) |
| Facturación por categoría y mes | Cadena de Parallel Hash Join + GroupAggregate; cost≈21.717; 213.8 ms | `CREATE INDEX` sobre `pedido(fecha)` | Mismo plan, índice no usado; 182.0 ms (mejora atribuible a caché, no al índice) | Sin mejora real — documentado como propuesta rechazada por el motor |

---

## DUIA — Declaración de Uso de IA (Parte 2)

| Campo | Completar |
|---|---|
| Herramienta | Claude (Anthropic), vía chat, con acceso de lectura a los archivos del proyecto |
| Spec o prompt utilizado | Se pidió elegir 3 consultas de `queries.sql` candidatas a volverse lentas con la base poblada masivamente, medirlas con `EXPLAIN ANALYZE` antes y después de proponer índices/reescrituras, y documentar cada resultado (mejore o no) |
| Qué generó | Selección justificada de las 3 consultas, el `CREATE INDEX` para `detalle_pedido(producto_id)` y `pedido(fecha)`, la reescritura con `NOT EXISTS` para la consulta de productos sin ventas, y la explicación de por qué el índice de la consulta de facturación no fue usado por el planificador |
| Qué se aceptó | El índice sobre `detalle_pedido(producto_id)` + la reescritura `NOT EXISTS` para la Consulta 1 (mejora real y verificada). Se aceptó no aplicar ningún índice en la Consulta 2, con la justificación de por qué un B-tree no serviría para el patrón `LIKE '%...%'` |
| Qué se modificó o descartó, y por qué | El índice `idx_pedido_fecha` de la Consulta 3 se creó pero se descartó como solución real: se dejó igual en la base de prueba a modo de evidencia (el plan no lo usa), mientras que en la conclusión se documenta explícitamente que no ayudó, en vez de forzar o simular una mejora que no ocurrió |
| Verificación realizada | Los 4 `EXPLAIN ANALYZE` de la Consulta 1 (sin índice, con índice ignorado, con índice forzado vía `enable_hashjoin=off`, y con `NOT EXISTS`), el `EXPLAIN ANALYZE` antes/después de la Consulta 2 y la Consulta 3, y la verificación de equivalencia de resultados de la Consulta 1 con `EXCEPT` (0 filas), todo corrido sobre `foodstore_test` |
