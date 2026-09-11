# TP4 — Parte 4: Competencia de optimización entre equipos

> Base: `foodstore_test`, PostgreSQL 17.6, poblada con la carga masiva de la
> Semana 3 (50.012 productos, 20.005 usuarios, 200.003 pedidos y 800.008
> detalles de pedido). Índices de la Semana 3 ya creados
> (`idx_producto_categoria_id`, `idx_pedido_usuario_id`,
> `idx_producto_no_eliminado`, más `idx_detalle_pedido_producto_id` e
> `idx_pedido_fecha`, que se agregaron en el TP3).
>
> Hardware: AMD Ryzen 5 5500 (6 núcleos / 12 hilos), 16 GB RAM, SSD.
> Servidor con la configuración de fábrica: `shared_buffers` 128 MB, `work_mem`
> 4 MB, `effective_cache_size` 4 GB, `random_page_cost` 4,
> `max_parallel_workers_per_gather` 2.
>
> El script que reproduce cada medición de este informe es
> [`competencia_parte4.sql`](competencia_parte4.sql).

## Consulta común

Se eligió la consulta de facturación por categoría y por mes, tal cual está en
`queries.sql` (sección "Consultas analíticas", punto B). Tiene 3 `JOIN` más
agregación, como pide la consigna, y es la misma para todos los equipos.

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

Devuelve 29 filas (5 categorías por unos 13 meses con ventas). Es un buen caso
para la competencia porque es la consulta que en el TP3 se resistió a la
optimización: ahí se le creó `idx_pedido_fecha` y el planificador lo ignoró por
completo, sin mejora real.

## Cómo se midió

Antes de comparar tiempos hay que fijar el criterio de medición, o los números
no dicen nada. Lo que se hizo:

- `VACUUM (ANALYZE)` sobre las 5 tablas antes de medir. Después de la carga
  masiva las estadísticas quedan viejas y, sobre todo, el *visibility map* queda
  vacío. Sin ese mapa poblado ningún `Index Only Scan` puede evitar ir al heap,
  así que sin este paso la estrategia de más abajo directamente no funciona. La
  diferencia es de unos 46 ms sin tocar una línea de SQL.
- Varias corridas de cada variante y se toma la mediana, nunca la primera (la
  primera mide caché frío). En esta máquina el ruido entre corridas anda por el
  ±15 %, así que un solo `EXPLAIN ANALYZE` no alcanza. Para aislar el aporte de
  cada cambio se usaron 7 a 9 corridas; para el número final de la competencia,
  15 corridas seguidas del estado "antes" y 15 del "después".
- `EXPLAIN (ANALYZE, BUFFERS)`, no solo `ANALYZE`. El contador de buffers es la
  evidencia que no depende del ruido: si el plan nuevo toca tres veces menos
  páginas, la mejora es del plan y no de la caché.
- Un cambio por vez, medido en aislamiento, para poder atribuir cada mejora a su
  causa.

## Plan antes

`EXPLAIN (ANALYZE, BUFFERS)` de la consulta común, en el estado de cierre de la
Semana 3 y con la configuración por defecto (extracto de los nodos que
importan):

```
Sort  (cost=29490.96..29495.52 rows=1825 width=52) (actual time=284.077..289.048 rows=29 loops=1)
  Buffers: shared hit=13824 read=1856
  ->  Finalize GroupAggregate  (actual time=284.009..289.022 rows=29 loops=1)
        ->  Gather Merge  (actual time=283.994..288.975 rows=81 loops=1)
              Workers Planned: 2   Workers Launched: 2
              ->  Sort  (actual time=275.670..275.674 rows=27 loops=3)
                    ->  Partial HashAggregate  (actual time=275.622..275.634 rows=27 loops=3)
                          Group Key: c.nombre, date_trunc('month', (ped.fecha)::timestamp with time zone)
                          ->  Hash Join  (actual time=27.447..222.434 rows=266669 loops=3)
                                Hash Cond: (pr.categoria_id = c.id)
                                ->  Hash Join  (actual time=27.378..152.478 rows=266669 loops=3)
                                      Hash Cond: (dp.producto_id = pr.id)
                                      ->  Parallel Hash Join  (actual time=15.944..103.998 rows=266669 loops=3)
                                            Hash Cond: (dp.pedido_id = ped.id)
                                            ->  Parallel Seq Scan on detalle_pedido dp  (actual time=0.085..36.812 rows=266669 loops=3)
                                            ->  Parallel Hash  (actual time=15.635..15.636 rows=66668 loops=3)
                                                  ->  Parallel Seq Scan on pedido ped  (actual time=0.008..8.549 rows=66668 loops=3)
                                      ->  Hash  (actual time=11.288..11.288 rows=50012 loops=3)
                                            ->  Seq Scan on producto pr  (actual time=0.027..6.810 rows=50012 loops=3)
                                ->  Hash  (actual time=0.037..0.038 rows=5 loops=3)
                                      ->  Seq Scan on categoria c  (actual time=0.030..0.032 rows=5 loops=3)
Planning Time: 1.864 ms
Execution Time: 289.388 ms
```

Lectura del plan:

- Hay tres `Seq Scan` completos: `detalle_pedido` (800.008 filas, 71 MB),
  `pedido` (200.003 filas, 31 MB) y `producto` (50.012 filas, 6,9 MB). En total
  15.680 buffers (13.824 hit + 1.856 read).
- Los tres joins son **Hash Join**, y está bien que lo sean: no hay ningún filtro
  selectivo, así que el optimizador arma tablas hash y hace una sola pasada. No
  hay nada para corregir en la elección del algoritmo de join.
- El costo no está en los joins **sino en el volumen que los atraviesa**: 266.669
  filas por worker en cada uno de los tres niveles.
- El join contra `categoria` arrastra las 800.008 filas para unirlas contra una
  tabla de 5, y recién después agrupa.
- En el `Group Key` la fecha aparece como
  `(ped.fecha)::timestamp with time zone`. Es un `DATE` que se está promoviendo
  a `timestamptz` (ver más abajo).

De ahí salen los cuatro cambios que se aplicaron.

## Estrategia aplicada

### Índices covering para llegar a Index Only Scan

La consulta no filtra nada, agrupa el 100 % de las filas. Por eso un índice
"para filtrar" no puede servir; esa fue la lección del TP3. Lo que sí sirve es
un índice más angosto que la tabla que contenga todas las columnas que la
consulta toca de esa tabla, para que el recorrido completo se haga sobre el
índice y no sobre el heap.

```sql
CREATE INDEX idx_dp_cov_facturacion
    ON detalle_pedido (pedido_id) INCLUDE (producto_id, subtotal)
    WHERE eliminado = FALSE;

CREATE INDEX idx_pedido_cov_fecha
    ON pedido (id) INCLUDE (fecha)
    WHERE eliminado = FALSE;

CREATE INDEX idx_producto_cov_categoria
    ON producto (id) INCLUDE (categoria_id);
```

El tamaño de cada índice contra el heap correspondiente:

| Tabla | Heap | Índice covering |
|---|---|---|
| `detalle_pedido` | 71 MB | 33 MB |
| `pedido` | 31 MB | 6,0 MB |
| `producto` | 6,9 MB | 1,5 MB |

La condición `WHERE eliminado = FALSE` los hace índices parciales: no indexan
las filas dadas de baja, y de paso le indican al planificador que el filtro de
borrado lógico ya está cubierto por el índice.

### random_page_cost para SSD

Con los índices creados y `ANALYZE` corrido, el planificador los seguía
ignorando: dos de los tres seguían resolviéndose por `Parallel Seq Scan`.

La causa es `random_page_cost = 4`, el valor por defecto, pensado para disco
rotativo: le dice al planificador que una lectura aleatoria cuesta cuatro veces
una secuencial. En un SSD la relación real está más cerca de 1.1, que es el
valor que recomienda la documentación de PostgreSQL para estado sólido.

```sql
SET random_page_cost = 1.1;
```

Para no aceptar este cambio a ciegas se hizo una contra-prueba, con el mismo
método que en el TP3 (donde se usó `enable_hashjoin = off`): se volvió
`random_page_cost` a 4 y se forzó el camino por índice con
`enable_seqscan = off`. El tiempo forzado dio 128,8 ms contra 131,9 ms del plan
elegido solo con `random_page_cost = 1.1`. Son prácticamente iguales, así que
bajar el parámetro no inventó una mejora: solo le permitió al planificador
elegir por su cuenta el plan que ya era el mejor. Si el forzado hubiera sido más
lento, el cambio se descartaba.

### Más paralelismo

El default de `max_parallel_workers_per_gather = 2` deja 10 de los 12 hilos de
la máquina ociosos en una consulta que es escaneo más agregación, o sea
perfectamente paralelizable.

```sql
SET max_parallel_workers_per_gather = 4;
```

Este cambio rinde poco sobre el plan viejo (6 %, de 224,7 a 211,7 ms) y mucho
sobre el plan con `Index Only Scan` (51 %, de 199,5 a 131,9 ms). El motivo es
que el plan viejo está limitado por el ancho de banda de lectura del heap, no
por CPU; agregar workers sirve recién cuando el escaneo dejó de ser el cuello.

### Reescritura de la consulta

```sql
SELECT c.nombre AS categoria, x.mes, x.facturado
FROM (
    SELECT pr.categoria_id,
           date_trunc('month', ped.fecha::timestamp)::DATE AS mes,
           SUM(dp.subtotal)                                AS facturado
    FROM   detalle_pedido dp
    JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
    JOIN   producto pr  ON pr.id  = dp.producto_id
    WHERE  dp.eliminado = FALSE
    GROUP  BY pr.categoria_id, date_trunc('month', ped.fecha::timestamp)
) x
JOIN categoria c ON c.id = x.categoria_id AND c.eliminado = FALSE
ORDER BY x.mes DESC, x.facturado DESC;
```

Son dos cambios, cada uno justificado en un nodo concreto del plan.

El primero es agregar por `pr.categoria_id` y unir `categoria` al final. En el
plan original el join contra `categoria` arrastra las 800.008 filas para
unirlas contra 5, y recién ahí agrupa. Agrupando primero por `categoria_id`, esa
unión pasa a hacerse contra 29 filas, y la clave de agrupamiento pasa de
`VARCHAR` a `BIGINT` (hashear un entero es más barato que hashear texto). Es
equivalente porque `categoria.nombre` tiene restricción `UNIQUE`: no hay dos
categorías distintas con el mismo nombre que puedan colapsar al reincorporar el
nombre.

El segundo es usar `date_trunc('month', ped.fecha::timestamp)` en vez de
`date_trunc('month', ped.fecha)`. Sale de leer el `Group Key` del plan: dice
`(ped.fecha)::timestamp with time zone`. Como `ped.fecha` es `DATE` y no existe
`date_trunc(text, date)`, PostgreSQL lo promociona a `timestamptz`, y eso
implica una conversión de huso horario por cada una de las 800.008 filas. Además
las dos firmas no tienen la misma volatilidad:

```sql
SELECT proname, pg_get_function_arguments(oid), provolatile FROM pg_proc WHERE proname = 'date_trunc';
```

| Firma | Volatilidad |
|---|---|
| `date_trunc(text, timestamp with time zone)` | STABLE |
| `date_trunc(text, timestamp without time zone)` | IMMUTABLE |

Casteando a `timestamp` (sin huso) se usa la variante IMMUTABLE, sin conversión
de zona. Medido solo, ese cast baja de 247,7 a 224,7 ms, un 9 %.

## Progresión de mediciones

Esta tabla sirve para atribuir cada mejora a su causa, no como medición oficial
(esa está en la sección siguiente). Todos los valores son la mediana de 7 a 9
corridas encadenadas en una misma sesión; con ±15 % de ruido, las diferencias
chicas (filas 2, 7 y 11) están dentro del margen de error. Entre paréntesis, el
mínimo observado.

| Estado medido | Mediana | Mín. | vs. baseline |
|---|---|---|---|
| Consulta original, sin `VACUUM` previo | 353,2 ms | (303,0) | — |
| Consulta original + `VACUUM (ANALYZE)` — baseline | 307,0 ms | (299,9) | 1,00× |
| Baseline + 3 índices covering (`random_page_cost` 4) | 301,8 ms | (290,2) | 1,02× |
| Consulta original + covering + `rpc` 1.1 + 4 workers | 268,0 ms | (266,0) | 1,15× |
| Reescritura (a) sola, sin covering | 247,7 ms | (242,4) | 1,24× |
| Reescritura (a) + covering | 239,6 ms | (235,8) | 1,28× |
| Reescritura (a)+(b) + covering | 224,7 ms | (212,5) | 1,37× |
| Fila anterior + `work_mem` 64 MB | 222,7 ms | (214,3) | 1,38× |
| Reescritura completa + covering + 4 workers | 211,7 ms | (209,3) | 1,45× |
| Reescritura completa + covering + `rpc` 1.1 + 2 workers | 199,5 ms | (195,2) | 1,54× |
| Reescritura completa + covering + `rpc` 1.1 + 4 workers | 131,9 ms | (127,1) | 2,33× |
| Fila anterior + `work_mem` 64 MB | 129,5 ms | (126,5) | 2,37× (ruido) |
| Fila anterior forzando `enable_seqscan = off` | 128,8 ms | (127,1) | 2,38× |

Lo que muestra la tabla:

- Ninguna palanca sola alcanza. Los índices solos dan 1,02×, la reescritura sola
  1,24×, el cost model más paralelismo sin reescribir 1,15×. El 2,33× aparece
  recién con las cuatro juntas.
- La anteúltima fila valida la última: forzar el índice con el cost model por
  defecto da el mismo tiempo que dejar que el planificador lo elija con
  `random_page_cost = 1.1`. La mejora es del plan, no del parámetro.
- Las filas de `work_mem` no prueban nada: su diferencia es menor que el ruido y
  el plan no cambia (ver la sección de propuestas descartadas).

## Plan después

```
Sort  (cost=20291.84..20291.95 rows=46 width=44) (actual time=125.848..129.519 rows=29 loops=1)
  Buffers: shared hit=5156
  ->  Hash Join  (actual time=125.790..129.479 rows=29 loops=1)
        Hash Cond: (pr.categoria_id = c.id)
        ->  Finalize HashAggregate  (actual time=125.761..129.441 rows=29 loops=1)
              Group Key: pr.categoria_id, date_trunc('month', (ped.fecha)::timestamp without time zone)
              ->  Gather  (actual time=125.119..129.349 rows=133 loops=1)
                    Workers Planned: 4   Workers Launched: 4
                    ->  Partial HashAggregate  (actual time=112.821..112.832 rows=27 loops=5)
                          ->  Parallel Hash Join  (actual time=11.639..87.752 rows=160002 loops=5)
                                Hash Cond: (dp.producto_id = pr.id)
                                ->  Parallel Hash Join  (actual time=9.292..50.311 rows=160002 loops=5)
                                      Hash Cond: (dp.pedido_id = ped.id)
                                      ->  Parallel Index Only Scan using idx_dp_cov_facturacion on detalle_pedido dp
                                            (actual time=0.134..14.334 rows=160002 loops=5)
                                            Heap Fetches: 0
                                      ->  Parallel Hash  (actual time=9.028..9.028 rows=40001 loops=5)
                                            ->  Parallel Index Only Scan using idx_pedido_cov_fecha on pedido ped
                                                  (actual time=0.052..4.098 rows=40001 loops=5)
                                                  Heap Fetches: 0
                                ->  Parallel Hash  (actual time=2.289..2.289 rows=10002 loops=5)
                                      ->  Parallel Index Only Scan using idx_producto_cov_categoria on producto pr
                                            (actual time=0.045..5.206 rows=50012 loops=1)
                                            Heap Fetches: 0
        ->  Hash  (actual time=0.019..0.020 rows=5 loops=1)
              ->  Seq Scan on categoria c  (actual time=0.015..0.016 rows=5 loops=1)
Planning Time: 1.614 ms
Execution Time: 129.722 ms
```

Comparado con el plan de antes:

| | Antes | Después |
|---|---|---|
| Acceso a `detalle_pedido` | `Parallel Seq Scan` (71 MB) | `Parallel Index Only Scan`, Heap Fetches 0 |
| Acceso a `pedido` | `Parallel Seq Scan` (31 MB) | `Parallel Index Only Scan`, Heap Fetches 0 |
| Acceso a `producto` | `Seq Scan` (6,9 MB) | `Parallel Index Only Scan`, Heap Fetches 0 |
| Workers | 2 | 4 |
| Clave de agrupamiento | `c.nombre` (VARCHAR) + timestamptz | `categoria_id` (BIGINT) + timestamp |
| Join con `categoria` | contra 800.008 filas, antes de agrupar | contra 29 filas, después de agrupar |
| Cierre de la agregación | `Sort` + `Gather Merge` + `Finalize GroupAggregate` | `Gather` + `Finalize HashAggregate` |
| Buffers | 15.680 (13.824 hit + 1.856 read) | 5.156 (todos hit) |
| Algoritmo de join | Hash Join ×3 | Hash Join ×3 (sin cambio) |

Los tres **`Heap Fetches: 0`** confirman que los índices covering hicieron lo que se
esperaba: las tres tablas se recorren enteras sin tocar el heap.

Conviene tener presente para la defensa oral que el **algoritmo de join no cambió**: siguen siendo tres Hash Join, y estaba bien que lo fueran. Lo que se optimizó no
es cómo se combinan las tablas sino cuántas páginas hay que leer para alimentar
esos joins (tres veces menos) y cuánto trabajo por fila se hace encima (la
conversión de huso y el hash sobre texto).

### Verificación de equivalencia

```sql
(consulta_original) EXCEPT (consulta_optimizada);
(consulta_optimizada) EXCEPT (consulta_original);
```

| Comparación | Filas diferentes |
|---|---|
| original EXCEPT optimizada | 0 |
| optimizada EXCEPT original | 0 |
| filas devueltas por la original | 29 |
| filas devueltas por la optimizada | 29 |

## Registro de la competencia

Para el número que se lleva a la competencia se hizo una medición limpia,
separada de las corridas encadenadas de la sección anterior: se borraron los
tres índices covering para volver la base al estado de cierre de la Semana 3, se
midió la consulta original 15 veces, se reaplicó la estrategia completa y se
midió 15 veces más.

| | Corridas | Mediana | Mín. | Máx. |
|---|---|---|---|---|
| Antes (consulta original, índices Semana 3, config por defecto) | 15 | 298,2 ms | 292,0 ms | 331,9 ms |
| Después (estrategia completa) | 15 | 137,3 ms | 131,7 ms | 155,7 ms |

La mejora es de **2,17× en mediana**. La peor corrida del plan optimizado
(155,7 ms) es más rápida que la mejor del plan original (292,0 ms), o sea que
los dos rangos no se superponen y la mejora no depende de qué corrida se elija.

| Equipo | Estrategia aplicada | Antes (ms) | Después (ms) | Mejora |
|---|---|---|---|---|
| (nuestro equipo) | 3 índices covering parciales + `random_page_cost` 1.1 + `max_parallel_workers_per_gather` 4 + reescritura (agregación temprana por `categoria_id` y `date_trunc` inmutable) | 298,2 | 137,3 | 2,17× |
| Equipo 2 | *(completar en clase)* | | | |
| Equipo 3 | *(completar en clase)* | | | |
| Equipo 4 | *(completar en clase)* | | | |

Los tiempos son la mediana de 15 corridas de `EXPLAIN (ANALYZE, BUFFERS)` sobre
`foodstore_test`, después de `VACUUM (ANALYZE)`, en la máquina descrita al
inicio. Para que la comparación entre equipos sea válida todos deberían medir
con el mismo criterio (mediana de varias corridas, nunca la primera) y sobre la
misma base. Si se mide en máquinas distintas, lo comparable no es el tiempo
absoluto sino la mejora relativa y la reducción de buffers, que no dependen del
hardware.

### Propuestas que se probaron y no funcionaron

La consigna pide documentar toda propuesta de la IA, no solo la que quedó. Estas
se midieron y se descartaron:

| Propuesta | Resultado medido | Veredicto |
|---|---|---|
| Índice de expresión sobre `date_trunc('month', fecha)` | No aparece en ningún nodo del plan; 132,0 vs 131,9 ms | Descartada |
| Subir `work_mem` a 64 MB | 129,5 vs 131,9 ms, dentro del ruido | Descartada |
| `MATERIALIZED VIEW` precalculada | 0,1 ms de lectura, pero el `REFRESH` cuesta 227 a 283 ms (mediana 245) | Descartada |
| `idx_pedido_fecha` (heredado del TP3) | Sigue sin aparecer en ningún plan | Descartada |

El detalle de por qué se descartó cada una, para poder defenderlo oralmente:

- El índice de expresión sirve para filtrar u ordenar por esa expresión. Acá
  `date_trunc('month', fecha)` solo aparece en el `GROUP BY` y hay que leer
  igual las 200.003 filas de `pedido`. Suena razonable y no sirve.
- `work_mem` solo ayuda cuando algún nodo de hash reporta `Batches > 1` o cuando
  un `Sort` reporta `external merge`. El plan ya decía `Batches: 1` en todos
  lados: nada estaba volcando a disco, así que subir `work_mem` es gastar
  memoria a cambio de nada.
- La vista materializada es la propuesta más tentadora (0,1 ms parece ganar la
  competencia) y la que menos corresponde: no responde la misma pregunta.
  Devuelve datos congelados al último `REFRESH`, y ese `REFRESH` cuesta lo mismo
  que la consulta original. Precalcular no es optimizar, es mover el costo a
  otro momento y perder actualidad. Solo se justificaría si el reporte se
  consultara muchas veces por cada actualización de datos, que no es el caso.
- `idx_pedido_fecha` se dejó en la base como evidencia. Sigue sin usarse, por lo
  mismo que en el TP3: la consulta no filtra por fecha, agrupa por fecha.

## Un tema de correctitud, aparte de la optimización

Al leer la consulta común para optimizarla apareció algo que conviene señalar
aunque no dé milisegundos. La consulta filtra `dp.eliminado = FALSE` y
`c.eliminado = FALSE`, pero no filtra `pr.eliminado` en el join a `producto`. Es
justo el tipo de inconsistencia de borrado lógico dentro de un `JOIN` sobre la
que advierte la Parte 3 del enunciado.

Hoy no cambia el resultado, y está verificado:

```sql
SELECT count(*) FROM producto WHERE eliminado;   -- 0
```

No se corrigió a propósito: agregar `pr.eliminado = FALSE` cambiaría el conjunto
de resultados en cuanto exista un producto dado de baja, y la consulta de la
competencia tiene que ser idéntica para todos los equipos. Queda anotado como
algo a corregir fuera de la competencia.

## Declaración de Uso de IA (DUIA)

La versión completa está en [`duia_parte4.md`](duia_parte4.md). En resumen:

| Herramienta | Para qué se usó | Se aceptó / se descartó |
|---|---|---|
| Claude (Anthropic), con acceso de lectura a los archivos del proyecto | Diagnosticar el plan real y proponer índices y reescrituras justificadas en los nodos del plan | Se aceptó el diagnóstico (el cuello no está en el algoritmo de join sino en el volumen) y sobre esa base los cuatro cambios aplicados |
| Claude | Proponer índices para una consulta sin filtros | Se aceptó el enfoque covering con `INCLUDE`. Se rechazó su primera propuesta, que volvía a ser un índice sobre `date_trunc(fecha)`: se creó, se midió, no apareció en el plan y se borró |
| Claude | Explicar por qué los índices no se usaban | Se aceptó la explicación de `random_page_cost` con SSD, pero después de validarla forzando `enable_seqscan = off`. Como el tiempo forzado dio igual, se confirmó que el plan por índice era genuinamente mejor |
| Claude | Verificar la consulta reescrita | Se aceptó la verificación con `EXCEPT` en los dos sentidos. Se agregó el conteo de filas de cada versión, porque `EXCEPT` solo no detecta diferencias de multiplicidad |
| Claude | Propuestas de cierre | Se descartaron `work_mem` y la vista materializada, las dos después de medirlas |

El enunciado menciona OpenCode / Kiro como la IA de la cátedra. Este trabajo se
hizo con Claude; si además se usa OpenCode o Kiro, hay que agregar sus filas a
la tabla de la DUIA.

## Conclusión

La consulta que en el TP3 se había resistido a toda optimización, donde el
índice propuesto fue ignorado y la única "mejora" era caché, bajó de **298,2 ms a 137,3 ms (2,17×)**, con tres veces menos buffers (15.680 a 5.156) y equivalencia
verificada con `EXCEPT`. De las dos cifras la más sólida es la de buffers: es un
conteo exacto, no depende del ruido ni de qué corrida se elija, y explica de
dónde sale el tiempo ganado.

La diferencia con el intento de la Semana 3 fue cambiar la pregunta. En el TP3
la pregunta era "qué índice acelera el filtro", y la respuesta era "ninguno",
porque no hay filtro. Acá la pregunta fue "cómo se leen menos páginas para
devolver exactamente lo mismo", y eso sí tiene respuesta: un índice más angosto
que la tabla, un cost model que refleje el disco real, y una consulta que no
arrastre 800.008 filas hasta el final para unirlas contra 5.
