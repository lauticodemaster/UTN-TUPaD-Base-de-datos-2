# Declaración de Uso de IA (DUIA) — TP4 Parte 4

Competencia de optimización sobre la consulta de facturación por categoría y
mes de Food Store. Base `foodstore_test` (50.012 productos, 20.005 usuarios,
200.003 pedidos, 800.008 detalles), PostgreSQL 17.6. El detalle de cada
medición está en [`informe_competencia_parte4.md`](informe_competencia_parte4.md).

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| Claude (Anthropic), vía chat, con acceso de lectura a los archivos del proyecto | Diagnosticar el plan real de la consulta común y proponer reescrituras e índices | Se le pasó el `EXPLAIN (ANALYZE, BUFFERS)` completo del estado "antes" y se pidió que propusiera cambios justificados en los nodos concretos del plan, no en generalidades | Se aceptó el diagnóstico de que el cuello no está en el algoritmo de join —los tres Hash Join son correctos porque no hay filtro selectivo— sino en el volumen de páginas que atraviesa cada join. De ahí salieron los cuatro cambios aplicados |
| Claude | Proponer índices útiles para una consulta que no filtra nada | Se pidió tener en cuenta que la consulta agrupa el 100 % de las filas y que en el TP3 un índice sobre la columna del `GROUP BY` (`idx_pedido_fecha`) había sido ignorado | Se aceptó el enfoque de índices covering con `INCLUDE` y `WHERE eliminado = FALSE`. Se rechazó la primera propuesta, que volvía a ser un índice sobre `date_trunc('month', fecha)`: se creó, se midió, no apareció en ningún nodo del plan (132,0 vs 131,9 ms) y se borró |
| Claude | Explicar por qué los índices recién creados seguían sin usarse | Se le pasó el plan posterior a crear los índices, donde `detalle_pedido` y `pedido` seguían resolviéndose por `Parallel Seq Scan` | Se aceptó la explicación de `random_page_cost = 4` (default de disco rotativo) frente a SSD, pero después de validarla: se volvió el parámetro a 4 y se forzó el índice con `enable_seqscan = off`. El tiempo forzado (128,8 ms) dio igual al elegido con `random_page_cost = 1.1` (131,9 ms), lo que confirma que el plan por índice era genuinamente mejor y no un efecto del parámetro. Si el forzado hubiera sido peor, se descartaba |
| Claude | Buscar costo por fila evitable en la agregación | Se pidió revisar el `Group Key` del plan | Se aceptó el hallazgo de que `date_trunc('month', ped.fecha)` promociona un `DATE` a `TIMESTAMPTZ` —visible en el plan como `(ped.fecha)::timestamp with time zone`— y usa la variante STABLE de `date_trunc`, con conversión de huso en cada fila. Se verificó la volatilidad de cada firma en `pg_proc` antes de aceptar y se midió el efecto aislado (247,7 → 224,7 ms) |
| Claude | Verificar que la consulta reescrita sea equivalente | Se pidió verificar contra la consulta original sobre la base completa, no sobre un ejemplo | Se aceptó la verificación con `EXCEPT` en los dos sentidos (0 filas en ambos). Se agregó el conteo de filas de cada versión (29 y 29), porque `EXCEPT` solo no detecta diferencias de multiplicidad |
| Claude | Propuestas de cierre para bajar más el tiempo | Se preguntó qué más se podía hacer sobre el plan ya optimizado | Se descartaron las dos, después de medirlas: `work_mem = 64MB` (129,5 vs 131,9 ms, dentro del ruido; el plan ya decía `Batches: 1` en todos los nodos de hash) y `MATERIALIZED VIEW` precalculada (0,1 ms de lectura, pero el `REFRESH` cuesta 245 ms, lo mismo que la consulta original, y devuelve datos congelados) |

El enunciado nombra a OpenCode / Kiro como IA de la cátedra. Este trabajo se
hizo con Claude; si además se usó OpenCode o Kiro, corresponde agregar sus filas
a esta tabla.

## Criterio con que se aceptó cada propuesta

Ninguna propuesta se aplicó por sonar razonable. En todos los casos se leyó
completa, se identificó qué nodo del plan decía que iba a mejorar, se aplicó
sobre `foodstore_test`, se volvió a medir con `EXPLAIN (ANALYZE, BUFFERS)` (7 a 9
corridas, comparando medianas), se verificó en el plan nuevo que el cambio
efectivamente aparecía, y se contrastó contra el contador de buffers, que no
depende del ruido. Si la propuesta no se sostenía en el plan real, se documentó
como descartada con la evidencia en vez de forzar una mejora.

Resultado: 298,2 ms → 137,3 ms (mediana de 15 corridas, 2,17×), buffers 15.680 →
5.156, 29 filas en ambas versiones con equivalencia verificada por `EXCEPT`. Los
rangos observados no se superponen (antes 292,0–331,9 ms; después
131,7–155,7 ms).
