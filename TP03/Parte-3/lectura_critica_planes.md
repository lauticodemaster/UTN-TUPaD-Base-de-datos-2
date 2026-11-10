# TP3 — Parte 3: Lectura crítica de planes interpretados por IA

**Plan real utilizado:** Consulta 1 ("Productos sin ventas"), plan obtenido en la Parte 2 con `EXPLAIN ANALYZE`.

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

## Paso 1 — Explicación "a ciegas" pedida a la IA

Se le pasó únicamente el texto del plan de arriba (sin la consulta SQL ni contexto adicional) y se le pidió que lo explique nodo por nodo. Esta fue la explicación obtenida:

> "El plan arranca con un **Sort** que ordena el resultado final; le costó 16.381 ms y devolvió 1 fila. Ese Sort recibe los datos de un **Hash Right Join** entre `detalle_pedido` y `producto`, que junta ambas tablas por `producto_id = pr.id`. Dentro del join hay un filtro `dp.id IS NULL` que descarta 600.008 filas, es decir, se eliminaron 600.008 registros de la tabla `detalle_pedido` porque no cumplían la condición. Por debajo, un **Seq Scan sobre `detalle_pedido`** recorre toda la tabla sin usar ningún filtro, y en paralelo se arma un **Hash** con un **Seq Scan sobre `producto`**, que sí aplica el filtro `NOT eliminado` y descarta algunas filas. En total la consulta tardó 112,5 ms, que es el tiempo del Sort final."

## Paso 2 — Contraste frase por frase contra el plan real

| Afirmación de la IA | ¿Correcta? | Corrección / evidencia del plan real |
|---|---|---|
| "El Sort... le costó 16.381 ms" | No | 16.381,51 es el **cost** estimado por el planificador (unidad arbitraria, no tiempo), no milisegundos. El tiempo real del Sort surge de `actual time=109.441..112.503`, y son ms, no el número de cost. Confunde cost con tiempo real. |
| "y devolvió 1 fila" | No | `rows=1` en el encabezado del Sort es la **estimación** del planificador, no lo que devolvió en la práctica. El propio `actual` de ese mismo nodo dice `rows=50001`: devolvió 50.001 filas reales. Es justamente la desviación estimación-vs-realidad que el informe de la Parte 2 señala como la causa de varias decisiones cuestionables del plan. |
| "Hash Right Join entre `detalle_pedido` y `producto`... por `producto_id = pr.id`" | Sí | Coincide con `Hash Cond: (dp.producto_id = pr.id)` y los dos scans hijos. |
| "el filtro `dp.id IS NULL` descarta 600.008 filas, es decir, se eliminaron 600.008 registros de la tabla `detalle_pedido`" | Parcialmente incorrecta | `Rows Removed by Filter: 600008` no elimina filas de la tabla `detalle_pedido`; se aplica **sobre las filas ya emparejadas por el join** (candidatas de salida del Hash Right Join), y descarta las que tienen `dp.id` no nulo (es decir, los productos que sí tuvieron ventas). No es un filtro sobre la tabla origen, sino post-join. La IA da a entender que se perdieron registros de la tabla base, cuando en realidad son pares join descartados. |
| "un Seq Scan sobre `detalle_pedido` recorre toda la tabla sin usar ningún filtro" | No | El nodo sí tiene `Filter: (NOT eliminado)`. Que no aparezca una línea de "Rows Removed by Filter" en ese nodo no significa "sin filtro": significa que el filtro se aplicó y no descartó ninguna fila (las 600.008 filas leídas pasaron el filtro, porque ninguna tenía `eliminado = TRUE`). La IA confunde "ausencia de filas removidas" con "ausencia de filtro". |
| "se arma un Hash con un Seq Scan sobre `producto`, que sí aplica el filtro `NOT eliminado` y descarta algunas filas" | Parcialmente incorrecta | El filtro existe, correcto, pero no descarta ninguna fila: `rows=50012` estimadas y `actual rows=50012` — coinciden exactamente, y tampoco aparece "Rows Removed by Filter" en este nodo. Decir que "descarta algunas filas" no está sustentado por el plan; en los hechos, el filtro no rechazó nada. |
| "la consulta tardó 112,5 ms, que es el tiempo del Sort final" | Parcialmente incorrecta | 112,503 ms es el `actual time` superior del nodo Sort (cuándo terminó de emitir filas), pero el tiempo total real de la consulta es el que figura aparte como `Execution Time: 113.694 ms`, que incluye overhead del executor por fuera de los nodos del plan (por ejemplo, entrega final de resultados). Son casi iguales pero no son el mismo dato, y la IA los trata como si fueran uno solo. |
