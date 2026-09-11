# Parte 2: Lectura crítica de planes de join interpretados por IA.

Se eligió el query plan de la consulta de facturación por categoría y por mes original, resultado de un EXPLAIN ANALYZE.
```text
"Sort  (cost=26480.80..26526.42 rows=18250 width=260) (actual time=192.850..200.240 rows=17.00 loops=1)"
"  Sort Key: (((date_trunc('month'::text, (ped.fecha)::timestamp with time zone)))::date) DESC, (sum(dp.subtotal)) DESC"
"  Sort Method: quicksort  Memory: 25kB"
"  Buffers: shared hit=2605 read=5518"
"  ->  Finalize HashAggregate  (cost=22485.85..22942.10 rows=18250 width=260) (actual time=190.606..200.205 rows=17.00 loops=1)"
"        Group Key: c.nombre, (date_trunc('month'::text, (ped.fecha)::timestamp with time zone))"
"        Batches: 1  Memory Usage: 289kB"
"        Buffers: shared hit=2605 read=5518"
"        ->  Gather  (cost=17348.47..22047.85 rows=43800 width=260) (actual time=190.413..197.891 rows=43.00 loops=1)"
"              Workers Planned: 2"
"              Workers Launched: 2"
"              Buffers: shared hit=2605 read=5518"
"              ->  Partial HashAggregate  (cost=16348.47..16667.85 rows=18250 width=260) (actual time=159.676..159.719 rows=14.33 loops=3)"
"                    Group Key: c.nombre, date_trunc('month'::text, (ped.fecha)::timestamp with time zone)"
"                    Batches: 1  Memory Usage: 289kB"
"                    Buffers: shared hit=2605 read=5518"
"                    Worker 0:  Batches: 1  Memory Usage: 289kB"
"                    Worker 1:  Batches: 1  Memory Usage: 289kB"
"                    ->  Hash Join  (cost=4932.22..16035.96 rows=41668 width=234) (actual time=38.134..142.621 rows=66669.33 loops=3)"
"                          Hash Cond: (pr.categoria_id = c.id)"
"                          Buffers: shared hit=2605 read=5518"
"                          ->  Nested Loop  (cost=4920.60..15587.97 rows=83337 width=18) (actual time=37.833..122.026 rows=66669.33 loops=3)"
"                                Buffers: shared hit=2602 read=5518"
"                                ->  Parallel Hash Join  (cost=4920.17..13503.07 rows=83337 width=18) (actual time=37.778..102.383 rows=66669.33 loops=3)"
"                                      Hash Cond: (ped.id = dp.pedido_id)"
"                                      Buffers: shared hit=2556 read=5518"
"                                      ->  Parallel Seq Scan on pedido ped  (cost=0.00..7467.68 rows=166668 width=12) (actual time=11.990..33.621 rows=133334.33 loops=3)"
"                                            Filter: (NOT eliminado)"
"                                            Buffers: shared hit=283 read=5518"
"                                      ->  Parallel Hash  (cost=3449.52..3449.52 rows=117652 width=22) (actual time=25.261..25.261 rows=66669.33 loops=3)"
"                                            Buckets: 262144  Batches: 1  Memory Usage: 13056kB"
"                                            Buffers: shared hit=2273"
"                                            ->  Parallel Seq Scan on detalle_pedido dp  (cost=0.00..3449.52 rows=117652 width=22) (actual time=0.007..9.458 rows=66669.33 loops=3)"
"                                                  Filter: (NOT eliminado)"
"                                                  Buffers: shared hit=2273"
"                                ->  Memoize  (cost=0.43..0.51 rows=1 width=16) (actual time=0.000..0.000 rows=1.00 loops=200008)"
"                                      Cache Key: dp.producto_id"
"                                      Cache Mode: logical"
"                                      Hits: 17847  Misses: 1  Evictions: 0  Overflows: 0  Memory Usage: 1kB"
"                                      Buffers: shared hit=46"
"                                      Worker 0:  Hits: 90381  Misses: 1  Evictions: 0  Overflows: 0  Memory Usage: 1kB"
"                                      Worker 1:  Hits: 91769  Misses: 9  Evictions: 0  Overflows: 0  Memory Usage: 2kB"
"                                      ->  Index Scan using producto_pkey on producto pr  (cost=0.42..0.50 rows=1 width=16) (actual time=0.012..0.012 rows=1.00 loops=11)"
"                                            Index Cond: (id = dp.producto_id)"
"                                            Index Searches: 11"
"                                            Buffers: shared hit=46"
"                          ->  Hash  (cost=11.00..11.00 rows=50 width=224) (actual time=0.284..0.284 rows=5.00 loops=3)"
"                                Buckets: 1024  Batches: 1  Memory Usage: 9kB"
"                                Buffers: shared hit=3"
"                                ->  Seq Scan on categoria c  (cost=0.00..11.00 rows=50 width=224) (actual time=0.274..0.275 rows=5.00 loops=3)"
"                                      Filter: (NOT eliminado)"
"                                      Buffers: shared hit=3"
"Planning:"
"  Buffers: shared hit=12"
"Planning Time: 0.689 ms"
"Execution Time: 201.073 ms"
```

Posteriormente se le planteó la siguiente consulta a Gemini 3.1 Pro: «Explica este plan, nodo por nodo, en lenguaje natural: [texto completo del query plan]». La respuesta de la IA, Gemini 3.1 Pro, es generalmente correcta, pero no especifica qué tablas son internas y qué tablas externas, y agrupa nodos con funciones estrechamente relacionadas.  

### Tabla crítica.
| Afirmaciones de la IA (Gemini 3.1 Pro) | ¿Es correcta? | Corrección/evidencia del plan real |
|:---------|:---------|:--|
| `Seq Scan on categoria`: Lee toda la tabla `categoria`, ignorando los registros marcados como eliminados; `Hash`: Toma esas categorías y construye una pequeña tabla hash en memoria para cruzarla más adelante. | Correcta. | El plan en efecto usa `Seq Scan on categoria c` para escanear toda la tabla categoría, y después procede a armar la tabla hash: `Hash (cost=11.00..11.00 rows=50 width=224)`. |
| `Parallel Seq Scan on detalle_pedido`, `Parallel Hash`, `Parallel Seq Scan on pedido`, `Parallel Hash Join`: Lee en paralelo y une velozmente pedidos y detalles. | Correcta, pero omite qué tabla es interna/externa. | `detalle_pedido` es la tabla interna que alimenta el `Parallel Hash`, mientras que `pedido` es la tabla externa escaneada secuencialmente para el `Parallel Hash Join`. |
| `Index Scan on producto`, `Memoize`, `Nested Loop`: Usa un bucle que, para cada fila del cruce anterior, busca el producto usando índice y una capa de caché. | Correcta. | El resultado del cruce pedido-detalle actúa como relación externa del `Nested Loop`. Para cada fila, se accede a `producto` (tabla interna) pasando por el nodo `Memoize`, el cual refleja una alta tasa de aciertos (`Hits: 17847` / `Misses: 1`). |
| `Hash Join`: Une todo el conjunto anterior con la tabla hash de `categoria` preparada en el paso 1. | Correcta, pero incompleta en cuanto a roles. | Describe bien la operación lógica, pero falta especificar que el resultado de (pedidos + detalles + productos) funciona como tabla externa que consulta la tabla hash interna de `categoria` mediante la condición `pr.categoria_id = c.id`. |
| `Partial HashAggregate`, `Gather`, `Finalize HashAggregate`: Agrupación dividida donde los workers calculan sumas parciales y el líder recolecta y consolida. | Correcta. | Se observa explícitamente en el plan el uso de un `Partial HashAggregate` distribuido, un `Gather` con `Workers Launched: 2` y la consolidación final en `Finalize HashAggregate` agrupando por mes y categoría. |
| `Sort`: Ordena la tabla por mes y luego por la suma total de forma descendente en memoria RAM usando quicksort. | Correcta. | El plan especifica claramente `Sort Key: ... DESC, (sum(dp.subtotal)) DESC` y confirma el uso de memoria: `Sort Method: quicksort Memory: 25kB`. |
