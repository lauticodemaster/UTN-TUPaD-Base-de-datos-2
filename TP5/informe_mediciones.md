# Informe de mediciones — TP5, Unidad 3 Semana 5

**Grupo H: Saferazi** — Danilo Serrano, Elio Marí, Daniela Díaz, Jesús Ramírez y Lautaro Fernández.

Índices, vistas y vistas materializadas sobre Food Store.

---

## 0. Entorno y protocolo de medición

| | |
|---|---|
| Motor | PostgreSQL 17.6, x86_64-windows |
| Base | `foodstore_test`, schema `foodstore` (copia de trabajo, nunca `foodstore` directo) |
| `work_mem` | 4 MB |
| `shared_buffers` | 128 MB |
| `effective_cache_size` | 4 GB |
| `random_page_cost` | 4 (por defecto) |
| `seq_page_cost` | 1 |
| `max_parallel_workers_per_gather` | 2 |
| `jit` | on |

Volumen de la base al momento de medir:

| Tabla | Filas | Heap |
|---|---:|---:|
| `categoria` | 5 | 16 kB |
| `producto` | 50.012 | — |
| `usuario` | 20.005 | — |
| `pedido` | 200.003 | 31 MB (3.932 páginas) |
| `detalle_pedido` | 800.008 | 71 MB (9.112 páginas) |

Rango de fechas de los pedidos vigentes: **2025-09-11 a 2026-09-10** (13 meses).

**Protocolo.** Cada consulta se corre **tres veces en caliente** y se informa la **mediana**,
nunca la primera corrida: la primera mide caché frío, no el plan. Antes de cada bloque de
medición se corre `VACUUM (ANALYZE)` sobre las tablas involucradas — sin visibility map
poblado ningún `Index Only Scan` puede evitar el heap, así que ese `VACUUM` es precondición
de la estrategia, no algo cosmético.

### Normalización del punto de partida

La base traía tres índices *covering* creados en la **Parte 4 del TP4**
(`idx_dp_cov_facturacion`, `idx_pedido_cov_fecha`, `idx_producto_cov_categoria`). Esos
objetos eran de la competencia de optimización, no del esquema del proyecto. Se **borraron
antes de medir** para volver al set de índices con el que cerró la Semana 3, que es el punto
de partida que fija la consigna:

- de `schema.sql`: `idx_producto_categoria_id`, `idx_pedido_usuario_id`, `idx_producto_no_eliminado`
- del TP3: `idx_detalle_pedido_producto_id`, `idx_pedido_fecha`

Sin esta normalización, el "antes" habría estado contaminado con el trabajo de la semana
pasada y las mejoras medidas serían más chicas de lo que realmente son.

---

## 1. Parte A — Plan de indexado

### 1.1 Las tres consultas elegidas

De `queries.sql` se tomaron las tres consultas que hoy resuelven con `Seq Scan` sobre una
tabla grande y se ejecutan seguido:

| # | Consulta (`queries.sql`) | Tabla recorrida | Spec |
|---|---|---|---|
| Q2 | Analítica A — Top 5 productos más vendidos | `detalle_pedido` (800.008) | `specs/spec_indice_top_productos.md` |
| Q3 | Analítica C — Ranking de usuarios por gasto acumulado | `pedido` (200.003) | `specs/spec_indice_ranking_usuarios.md` |
| Q4 | Analítica D — Pedidos cuyo total supera el promedio | `pedido` (200.003), dos veces | `specs/spec_indice_pedidos_sobre_promedio.md` |

Se descartó como cuarta candidata el filtro por nombre de usuario de HU-PED-01
(`v_pedidos_resumen WHERE usuario LIKE '%Miguel%'`): recorre `usuario`, que con 20.005 filas
resuelve en **3,4 ms**. No hay nada que ganar ahí, y un índice de trigramas sobre esa tabla
sería el primer caso de sobreindexación del trabajo.

---

### 1.2 Q2 — Top 5 productos más vendidos

```sql
SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
FROM   detalle_pedido dp
JOIN   producto pr ON pr.id = dp.producto_id
WHERE  dp.eliminado = FALSE
GROUP  BY pr.id, pr.nombre
ORDER  BY unidades DESC
LIMIT  5;
```

#### Plan ANTES

```
Limit  (cost=26509.39..26509.40 rows=5 width=30) (actual time=256.148..256.150 rows=5 loops=1)
  Buffers: shared hit=1598 read=8355
  ->  Sort  (cost=26509.39..26634.42 rows=50012 width=30) (actual time=256.147..256.148 rows=5 loops=1)
        Sort Method: top-N heapsort  Memory: 25kB
        ->  HashAggregate  (cost=25178.59..25678.71 rows=50012 width=30) (actual time=256.072..256.137 rows=12 loops=1)
              Batches: 1  Memory Usage: 1561kB
              ->  Hash Join  (cost=1987.27..21178.55 rows=800008 width=26) (actual time=9.948..184.468 rows=800008 loops=1)
                    Hash Cond: (dp.producto_id = pr.id)
                    ->  Seq Scan on detalle_pedido dp  (cost=0.00..17091.08 rows=800008 width=12) (actual time=0.039..72.670 rows=800008 loops=1)
                          Filter: (NOT eliminado)
                          Buffers: shared hit=736 read=8355
                    ->  Hash  (cost=1362.12..1362.12 rows=50012 width=22) (actual time=9.790..9.791 rows=50012 loops=1)
                          ->  Seq Scan on producto pr  (cost=0.00..1362.12 rows=50012 width=22) (actual time=0.008..5.211 rows=50012 loops=1)
Execution Time: 256.653 ms
```

#### Índice creado

```sql
CREATE INDEX idx_dp_top_productos
    ON detalle_pedido (producto_id, cantidad)
    WHERE eliminado = FALSE;
```

#### Plan DESPUÉS (configuración por defecto, sin tocar nada)

```
Limit  (actual time=221.492..221.494 rows=5 loops=1)
  Buffers: shared hit=1593
  ->  Sort
        Sort Method: top-N heapsort  Memory: 25kB
        ->  HashAggregate  (cost=23210.68..23710.80 rows=50012 width=30) (actual time=221.436..221.499 rows=12 loops=1)
              Batches: 1  Memory Usage: 1561kB
              ->  Hash Join
                    ->  Index Only Scan using idx_dp_top_productos on detalle_pedido dp  (cost=0.42..15095.72 rows=803608 width=12) (actual time=0.063..45.246 rows=800008 loops=1)
                          Heap Fetches: 119
                          Buffers: shared hit=728
                    ->  Hash
                          ->  Seq Scan on producto pr  (actual time=0.012..4.955 rows=50012 loops=1)
                                Buffers: shared hit=862
Execution Time: 222.080 ms
```

#### Resultado

| | Antes | Después | |
|---|---:|---:|---|
| Plan sobre `detalle_pedido` | Seq Scan | **Index Only Scan** | criterio 1 cumplido |
| `Heap Fetches` | — | 119 sobre 800.008 (0,01 %) | criterio 2 cumplido |
| Buffers sobre `detalle_pedido` | 9.091 (736 hit + 8.355 read) | **728** | **12,5× menos** |
| Buffers totales | 9.953 | 1.590 | |
| Tiempo (mediana de 3) | **258,9 ms** | **222,9 ms** | −13,9 % |

**Lectura honesta del número.** La mejora es de 14 %, no de un orden de magnitud, y el spec
pedía una mejora "reproducible", no espectacular. El motivo está a la vista en el plan: el
escaneo bajó de 72,7 ms a 45,2 ms (−38 %), pero el `HashAggregate` sobre 800.008 filas
cuesta ~175 ms y **ningún índice lo puede evitar**, porque la consulta tiene que tocar todas
las filas para poder sumarlas. Lo que el índice compra es leer menos bytes; lo que queda es
trabajo de CPU irreducible. El día que ese reporte se quiera realmente rápido, la respuesta
no es otro índice sino materializarlo, como se hace en la Parte C con la facturación.

#### Triangulación: por qué `(producto_id, cantidad)` y no `(producto_id) INCLUDE (cantidad)`

La herramienta recomendó como opción principal la variante con `INCLUDE`, y dejó la de clave
compuesta como alternativa "por si no hay INCLUDE disponible". **Medidas las dos, la
recomendación queda invertida:**

| Variante | Páginas | Tamaño | ¿La elige el planificador con `random_page_cost` = 4? | Tiempo |
|---|---:|---:|---|---:|
| `(producto_id) INCLUDE (cantidad)` | 3.084 | 24 MB | **No** — hace falta bajar `random_page_cost` | 236,1 ms |
| `(producto_id, cantidad)` | **692** | **5.536 kB** | **Sí** | **222,9 ms** |

La causa es la **deduplicación de B-tree**: PostgreSQL agrupa las claves repetidas en una
sola entrada con su lista de TIDs, y **desactiva esa compresión en cuanto el índice tiene
columnas `INCLUDE`**. En esta tabla hay **12 `producto_id` distintos y 28 pares
`(producto_id, cantidad)` distintos** sobre 800.008 filas, así que la deduplicación es
justamente lo que más rinde: 4,5× menos páginas para exactamente el mismo plan.

Consecuencia práctica, y es el punto que hace falta sostener en la defensa: `INCLUDE` no es
"la forma moderna de hacer un índice covering". Conviene cuando la columna extra no se puede
comprimir; cuando la clave se repite mucho, meter la columna en la clave es más barato.

---

### 1.3 Q3 — Ranking de usuarios por gasto acumulado

```sql
SELECT u.id, u.nombre || ' ' || u.apellido AS usuario,
       SUM(ped.total) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM   pedido ped
JOIN   usuario u ON u.id = ped.usuario_id
WHERE  ped.eliminado = FALSE AND u.eliminado = FALSE
GROUP  BY u.id, u.nombre, u.apellido
ORDER  BY puesto;
```

#### Plan ANTES

```
Sort  (actual time=123.361..123.926 rows=20003 loops=1)
  Buffers: shared hit=4272, temp read=121 written=283
  ->  WindowAgg
        ->  Sort
              Sort Key: (sum(ped.total)) DESC
              ->  HashAggregate  (cost=8244.28..8494.34 rows=20005 width=65) (actual time=99.845..106.659 rows=20003 loops=1)
                    Group Key: u.id
                    Batches: 5  Memory Usage: 8241kB  Disk Usage: 1576kB      <-- derrame a disco
                    ->  Hash Join
                          ->  Seq Scan on pedido ped  (actual time=0.008..22.760 rows=200003 loops=1)
                                Buffers: shared hit=3932
                          ->  Hash
                                ->  Seq Scan on usuario u  (actual time=0.004..2.148 rows=20005 loops=1)
Execution Time: 126.022 ms
```

El problema principal no es el `Seq Scan`: es que la tabla hash de la agregación **no entra
en `work_mem` y se derrama a disco** (`Batches: 5`, `Disk Usage: 1576kB`, `temp written=283`).

#### Índice creado

```sql
CREATE INDEX idx_pedido_ranking_usuarios
    ON pedido (usuario_id) INCLUDE (total)
    WHERE eliminado = FALSE;
```

Acá `INCLUDE` **sí** conviene, al revés que en Q2: `usuario_id` tiene 20.005 valores
distintos sobre 200.003 filas, así que casi no hay nada que deduplicar, y meter `total` en la
clave encarecería cada comparación del árbol sin ganar espacio.

#### Progresión de mediciones

| Estado | Plan sobre `pedido` | Agregación | Buffers | Tiempo (mediana de 3) |
|---|---|---|---:|---:|
| Antes | Seq Scan | HashAggregate, `Batches: 5`, **Disk 1576 kB** | 4.272 + temp 121/283 | **135,1 ms** |
| Con índice, configuración por defecto | **Seq Scan igual** — el planificador ignora el índice | igual | 4.272 | 127,2 ms |
| Con índice, `random_page_cost = 1.1` | **Index Only Scan**, `Heap Fetches: 11` | HashAggregate, `Batches: 5`, Disk 1640 kB | 1.344 + temp | **106,1 ms** |
| Con índice, `rpc = 1.1` + `enable_hashagg = off` | **Index Only Scan** | **GroupAggregate, sin derrame** | **1.400, sin temp** | **78,5 ms** |

#### Qué significa cada renglón

1. **El índice solo no alcanza.** Con la configuración por defecto el plan no cambia. No es
   que el índice esté mal: es que con `random_page_cost = 4` el planificador cree que leer
   páginas de índice cuesta cuatro veces más que leer páginas secuenciales, y ese número
   describe un disco rígido de platos, no el SSD de esta máquina. Un índice que el
   planificador no elige es un índice que sólo cuesta.
2. **Bajando `random_page_cost` a 1.1, el planificador lo elige solo** y el escaneo pasa a
   `Index Only Scan` con `Heap Fetches: 11`: 4.272 → 1.344 buffers, 135,1 → 106,1 ms.
   El valor 1.1 no es arbitrario, es el que corresponde a almacenamiento sin cabezal; ya
   había quedado validado en la Parte 4 del TP4 sobre esta misma base.
3. **El derrame a disco sobrevive igual.** Con la entrada ya ordenada por `usuario_id`, el
   motor *podría* hacer `GroupAggregate` y no armar ninguna tabla hash. Forzándolo con
   `enable_hashagg = off` el tiempo baja a **78,5 ms** y el `temp written` desaparece: el
   plan por agrupamiento ordenado **es realmente mejor**, un 26 % más rápido. Pero el
   planificador lo estima al revés (6.473 para el hash contra 8.661 para el group) porque
   subestima lo que cuesta derramar.

**Decisión tomada: no se fuerza `enable_hashagg` en producción.** Apagar un método de plan a
nivel de servidor para arreglar una consulta es cambiar un problema conocido por varios
desconocidos. Se deja medido y documentado: el índice entrega 21 % por sí solo (135,1 →
106,1 ms) y hay otro 26 % disponible que depende de una decisión del planificador, no de un
objeto de la base. Si ese reporte llegara a ser crítico, el camino limpio es subir `work_mem`
**en esa sesión** (no globalmente) o materializarlo.

---

### 1.4 Q4 — Pedidos cuyo total supera el promedio

```sql
SELECT id, total
FROM   pedido
WHERE  eliminado = FALSE
  AND  total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
ORDER  BY total DESC;
```

#### Plan ANTES

```
Sort  (cost=17747.63..17914.30 rows=66668 width=16) (actual time=70.612..77.884 rows=99747 loops=1)
  Sort Key: pedido.total DESC
  Sort Method: external merge  Disk: 2640kB            <-- ordena contra disco
  Buffers: shared hit=7864, temp read=330 written=331
  InitPlan 1
    ->  Finalize Aggregate  (actual time=17.842..17.868 rows=1 loops=1)
          ->  Gather
                ->  Partial Aggregate
                      ->  Parallel Seq Scan on pedido pedido_1  (actual time=0.008..5.909 rows=66668 loops=3)
  ->  Seq Scan on pedido  (cost=0.00..6432.04 rows=66668 width=16) (actual time=17.854..45.821 rows=99747 loops=1)
        Filter: ((NOT eliminado) AND (total > (InitPlan 1).col1))
        Rows Removed by Filter: 100256
Execution Time: 80.809 ms
```

#### Índice creado

```sql
CREATE INDEX idx_pedido_sobre_promedio
    ON pedido (total DESC) INCLUDE (id)
    WHERE eliminado = FALSE;
```

**Éste es el índice que más rinde, y su justificación es la menos intuitiva del trabajo.**
El filtro devuelve 99.747 de 200.003 filas: **el 50 %**. Por selectividad, este índice no se
justificaría nunca — el manual diría que a esa proporción conviene recorrer el heap. Lo que
se compra no es el filtro, es el **`ORDER BY total DESC`**: recorriendo el índice hacia atrás
las filas salen ya ordenadas y el nodo `Sort` desaparece entero, junto con los 2.640 kB de
ordenamiento contra disco.

#### Plan DESPUÉS (configuración por defecto)

```
Index Only Scan using idx_pedido_sobre_promedio on pedido  (cost=5974.34..8705.02 rows=66668 width=16) (actual time=18.260..26.464 rows=99747 loops=1)
  Index Cond: (total > (InitPlan 1).col1)
  Heap Fetches: 4
  Buffers: shared hit=4447
  InitPlan 1
    ->  Finalize Aggregate  (actual time=18.229..18.250 rows=1 loops=1)
          ->  Parallel Seq Scan on pedido pedido_1      <-- el AVG todavía recorre la tabla
Execution Time: 28.963 ms
```

#### Resultado

| | Antes | Después (defecto) | Después (`rpc = 1.1`) |
|---|---:|---:|---:|
| Nodo `Sort` | `external merge  Disk: 2640kB` | **no existe** | **no existe** |
| Escaneo principal | Seq Scan | Index Only Scan (`Heap Fetches: 4`) | Index Only Scan |
| `AVG` del InitPlan | Parallel Seq Scan | Parallel Seq Scan | **Parallel Index Only Scan** |
| Buffers | 7.864 + temp 330/331 | 4.447 | **1.524** |
| Tiempo (mediana de 3) | **82,9 ms** | **29,1 ms** (−65 %) | **27,6 ms** (−67 %) |

Es el único de los tres que el planificador elige **solo, con la configuración por defecto**,
y da una mejora de **2,8×**. Con `random_page_cost = 1.1` el `AVG` del InitPlan también pasa
a resolverse por índice — y se resuelve con `idx_pedido_ranking_usuarios`, el índice de Q3:
dos consultas distintas terminan compartiendo un mismo objeto, que es exactamente lo que se
busca cuando se diseña un plan de indexado en vez de un índice por consulta.

---

### 1.5 Costo de los índices sobre las escrituras

Script: `mediciones/carga_escritura.sql`. 500 sentencias `INSERT` individuales sobre
`detalle_pedido` dentro de una transacción que se revierte, de modo que la medición no deja
datos. Los dos triggers de la tabla (`trg_subtotal` por fila y `trg_total_ins` por sentencia,
que recalcula `pedido.total`) están activos en todas las corridas, así que su costo es
constante y **la diferencia medida es mantenimiento de índices**.

| Estado | Corridas (ms) | Mediana | Δ |
|---|---|---:|---:|
| Antes de los índices nuevos | 105,8 / 99,8 / 99,7 / 99,7 | **99,8 ms** | — |
| Con los 3 índices aceptados | 139,2 / 136,8 / 136,5 / 138,8 | **137,8 ms** | **+38 %** |
| + el índice descartado `idx_pedido_estado_fecha` | 143,9 / 143,6 / 141,6 / 143,3 | **143,5 ms** | +43,8 % |

**Lectura.** El plan de indexado cuesta **+38 % en la carga de escritura** y compra 14 %,
21 % y 65 % en tres reportes que se ejecutan muchas más veces por día de lo que se cargan
500 renglones de pedido de golpe. Para este sistema el intercambio cierra.

El detalle importante está en el tercer renglón: un índice sobre `pedido` encarece los
`INSERT` en `detalle_pedido` aunque ni siquiera se toque `pedido` directamente. La razón es
`trg_total_ins`: cada `INSERT` dispara un `UPDATE pedido SET total = ...`, y como `total` es
columna del índice (en `INCLUDE`), ese `UPDATE` no puede ser HOT y hay que mantener el índice
500 veces. Es el tipo de costo que no aparece si uno mira sólo la tabla que indexa.

---

### 1.6 Índices propuestos y descartados

La bitácora completa está en `duia.md`. Resumen de lo rechazado:

| Propuesta | Motivo del descarte | Evidencia |
|---|---|---|
| `detalle_pedido (producto_id) INCLUDE (cantidad)` | 4,5× más grande para el mismo plan: `INCLUDE` desactiva la deduplicación de B-tree | 3.084 vs 692 páginas; 236,1 vs 222,9 ms |
| `detalle_pedido (producto_id) INCLUDE (cantidad, subtotal)` | Especulativo: anticipa un reporte por facturación que hoy no existe, y arrastra el mismo problema de deduplicación | mismo mecanismo que el anterior |
| `pedido (usuario_id, fecha DESC)` | Se solapa con `idx_pedido_ranking_usuarios` en la columna líder y ninguna consulta de `queries.sql` filtra por usuario **y** ordena por fecha | — |
| **`pedido (estado, fecha DESC)`** — **el descarte por sobreindexación** | ver abajo | +4,1 % de escritura, 0 consultas aceleradas |
| `idx_detalle_pedido_producto_id` (heredado del TP3) | Redundante: misma tabla, mismo predicado parcial, misma columna líder que `idx_dp_top_productos`. Se **borra** | la analítica E sigue por `Index Only Scan`, ahora sobre el índice nuevo |

#### El descarte por sobreindexación, en detalle

Propuesta recibida:

```sql
CREATE INDEX idx_pedido_estado_fecha
    ON pedido (estado, fecha DESC)
    WHERE eliminado = FALSE;
```

El argumento a favor era razonable: "tablero por estado (`PENDIENTE`/`CONFIRMADO`/...)".
Se rechaza por cuatro motivos, en orden de peso:

1. **No hay ninguna consulta que lo use.** En `queries.sql` `estado` aparece únicamente en un
   `UPDATE ... WHERE id = 1` (HU-PED-03), que resuelve por clave primaria. El tablero por
   estado que justificaría el índice **no existe en el sistema**. Indexar para una consulta
   hipotética es la definición de sobreindexación.
2. **`estado` es de cardinalidad bajísima:** 4 valores para 200.003 filas. Como columna líder
   deja al planificador eligiendo entre cuatro bloques de ~50.000 filas cada uno; ni siquiera
   con `fecha` de segunda columna eso se vuelve selectivo, salvo que además se filtre por
   rango de fechas — lo que nos devuelve al punto 1.
3. **Se mide lo que cuesta:** +4,1 % en la carga de escritura (137,8 → 143,5 ms) y 1.384 kB,
   a cambio de cero consultas aceleradas. Y `pedido` es una tabla *caliente*: `trg_total_ins`
   la actualiza en cada `INSERT` de `detalle_pedido`.
4. **El día que el tablero exista**, el índice correcto probablemente no sea éste sino uno
   parcial por el estado que realmente se consulta
   (`WHERE eliminado = FALSE AND estado = 'PENDIENTE'`), que es mucho más chico. Crearlo hoy
   "por las dudas" nos ataría a la forma equivocada.

Se conservó, en cambio, `idx_pedido_usuario_id` de `schema.sql`, aunque parezca redundante
con `idx_pedido_ranking_usuarios`. **No lo es:** el nuevo es parcial
(`WHERE eliminado = FALSE`), así que el viejo sigue siendo el único que sirve para buscar los
pedidos de un usuario **incluyendo los dados de baja**, que es lo que necesita la auditoría de
HU-PED-04. El criterio que se usó para decidir en los dos casos es el mismo: un índice viejo
se borra sólo cuando el nuevo cubre **todas** las consultas que el viejo cubría. Para
`detalle_pedido` se cumple; para `pedido` no.

---

## 2. Parte B — Vistas

`views.sql` crea la vista que faltaba; las tres de reporte ya existían en `objects.sql` desde
la Semana 2 y **no se reescribieron**. Lo que nunca se había hecho, y se hizo esta semana, es
verificar que devuelven exactamente lo mismo que la consulta escrita a mano.

### 2.1 Verificación de equivalencia

Script: `mediciones/verificacion_vistas.sql`. Dos controles por vista, porque uno solo no
alcanza: **diferencia simétrica** (`EXCEPT` en los dos sentidos) y **comparación de
`COUNT(*)`**. El `COUNT` hace falta porque `EXCEPT` elimina duplicados: si la vista repitiera
una fila y la consulta manual no, la diferencia simétrica daría 0 igual y no nos
enteraríamos.

Salida real:

```
--- 1) v_productos_vigentes: diferencia simetrica (esperado 0 filas) ---
 id | nombre | precio | stock | categoria
----+--------+--------+-------+-----------
(0 filas)

--- 1b) v_productos_vigentes: COUNT (esperado coinciden = t) ---
 vista | manual | coinciden
-------+--------+-----------
 50012 |  50012 | t

--- 2) v_pedidos_resumen: diferencia simetrica (esperado 0 filas) ---
(0 filas)

--- 2b) v_pedidos_resumen: COUNT ---
 vista  | manual | coinciden
--------+--------+-----------
 200003 | 200003 | t

--- 3) v_pedido_detalle: diferencia simetrica (esperado 0 filas) ---
(0 filas)

--- 3b) v_pedido_detalle: COUNT ---
 vista  | manual | coinciden
--------+--------+-----------
 800008 | 800008 | t

--- 3c) v_pedido_detalle: control propio, pedidos descuadrados (esperado 0) ---
 pedidos_descuadrados
----------------------
                    0

--- 4) v_usuarios_publico: diferencia simetrica (esperado 0 filas) ---
(0 filas)

--- 4b) v_usuarios_publico: COUNT ---
 vista | manual | coinciden
-------+--------+-----------
 20005 |  20005 | t
```

Las cuatro vistas quedan verificadas.

### 2.2 La vista de seguridad

Script: `mediciones/verificacion_seguridad.sql`. Salida real:

```
--- (a) la vista NO expone contrasena: esto TIENE que fallar ---
ERROR:  column "contrasena" does not exist
LÍNEA 1: SELECT contrasena FROM v_usuarios_publico LIMIT 1;

--- (b) app_lectura puede leer la vista ---
 id | nombre  | apellido |   rol
----+---------+----------+---------
  1 | Miguel  | Herrera  | USUARIO
  2 | Juliana | Paredes  | ADMIN
  3 | Iván    | Ivañez   | USUARIO

--- (c) app_lectura NO puede leer la tabla base: esto TIENE que fallar ---
ERROR:  permission denied for table usuario

--- (d) permisos efectivos ---
 puede_leer_tabla | puede_leer_vista
------------------+------------------
 f                | t
```

Los tres resultados esperados aparecen: el rol lee la vista sin tener ningún permiso sobre la
tabla. **Por qué funciona:** en PostgreSQL una vista se ejecuta con los permisos de su
**dueño**, no con los de quien la consulta; el motor entra a `usuario` en nombre del dueño de
la vista y lo único que `app_lectura` llega a ver son las siete columnas expuestas. No hace
falta `SECURITY DEFINER`.

### 2.3 Decisión sobre el filtro de vigencia

Al escribir las specs reapareció una inconsistencia que de entrada parece un error:
`v_productos_vigentes` filtra las **dos** tablas del JOIN, mientras que `v_pedidos_resumen` y
`v_pedido_detalle` filtran sólo la suya.

Está bien como está, y "corregirlo" rompería los reportes. El filtro de vigencia se aplica
sobre **la entidad de la que habla la vista**, no sobre todas las tablas del JOIN:

- `v_productos_vigentes` es un **catálogo** — dice qué se puede vender hoy. Un producto de una
  categoría dada de baja no se puede vender, así que corresponde que desaparezca.
- `v_pedidos_resumen` y `v_pedido_detalle` son **históricos** — dicen qué pasó. Filtrar
  `producto.eliminado` haría desaparecer renglones de pedidos ya cobrados y descuadraría
  `pedido.total`.

El control (3c) del punto 2.1 es la prueba: **0 pedidos descuadrados** sobre 200.003. Si
alguien agrega el filtro "por consistencia", ese control lo delata.

---

## 3. Parte C — Vista materializada

Reporte elegido: **facturación por categoría y mes** (`queries.sql`, analítica B). Es el caso
de libro: recorre `detalle_pedido` (800.008), `pedido` (200.003) y `producto` (50.012) para
devolver **29 filas**.

### 3.1 Objeto creado

```sql
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha)::DATE AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
JOIN   producto pr  ON pr.id  = dp.producto_id
JOIN   categoria c  ON c.id   = pr.categoria_id
WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
GROUP  BY c.nombre, date_trunc('month', ped.fecha)
WITH DATA;

CREATE UNIQUE INDEX uq_mv_facturacion_cat_mes
    ON mv_facturacion_categoria_mes (categoria, mes);
```

Dos decisiones que conviene poder defender:

- **El `ORDER BY` del reporte original no va adentro.** Una vista materializada es un
  conjunto de filas almacenado; ordenarla al crearla no garantiza nada sobre el orden en que
  se lea después. El orden se pide al consultarla.
- **El índice único no es opcional.** Sin él, `REFRESH MATERIALIZED VIEW CONCURRENTLY` está
  prohibido: PostgreSQL lo necesita para identificar cada fila y aplicar el delta sin tomar
  un lock exclusivo. Se crea ahora, aunque hoy el refresco sea bloqueante, para no tener que
  recrear la vista el día que el reporte no pueda quedar sin servicio durante el `REFRESH`.

### 3.2 Medición

Script: `mediciones/medicion_matview.sql`. Medianas de 3 corridas:

| Operación | Tiempo | Buffers |
|---|---:|---:|
| Consulta original, sin materializar | **279,8 ms** | 15.677 |
| El mismo reporte contra la vista materializada | **0,025 ms** | 1 página |
| `REFRESH MATERIALIZED VIEW` (bloqueante) | 238,3 ms | |
| `REFRESH MATERIALIZED VIEW CONCURRENTLY` | 261,1 ms | |

**Mejora de lectura: 279,8 ms → 0,025 ms ≈ 11.000×.** Toda la vista materializada ocupa
8.192 bytes (una página) más 16 kB de índice único: el reporte entero entra en caché y no
vuelve a tocar las tablas grandes nunca más.

Es, de lejos, la mejora más grande del trabajo, y el contraste con la Parte A es el
aprendizaje: en Q2 el índice compró 14 % porque la agregación sobre 800.008 filas es trabajo
irreducible; acá esa misma agregación **se paga una sola vez por refresco** en vez de una vez
por consulta.

### 3.3 Frecuencia de refresco propuesta

**Propuesta: una vez por hora, con `REFRESH MATERIALIZED VIEW CONCURRENTLY`.**

El razonamiento, con los números de arriba:

- **El refresco cuesta lo mismo que la consulta original** (238 ms bloqueante / 261 ms
  concurrente contra 280 ms). Es decir: la vista materializada conviene exactamente en la
  medida en que **se lea más veces de las que se refresca**. Refrescarla en cada lectura
  sería peor que no tenerla. A una lectura por minuto en horario comercial y un refresco por
  hora, la relación es de 60 a 1 y el ahorro es real.
- **Los datos de meses cerrados no cambian.** De las 29 filas, 27 corresponden a meses ya
  terminados y son inmutables; lo único que se mueve es el mes en curso. Refrescar más
  seguido recalcularía 13 meses para actualizar uno.
- **`CONCURRENTLY` cuesta 23 ms más (+9,6 %) y los vale.** Un `REFRESH` bloqueante toma un
  `ACCESS EXCLUSIVE` sobre la vista: durante esos 238 ms cualquiera que abra el tablero queda
  esperando. `CONCURRENTLY` no bloquea lectores. En un reporte de gerencia que se abre a
  cualquier hora, 23 ms de más es un precio barato por no tener una pantalla colgada.

**Qué implica para el usuario.** El número que ve puede tener hasta una hora de atraso, y eso
**hay que decirlo en la pantalla**: la propuesta es mostrar el reporte con la leyenda
"actualizado a las HH:MM" tomada de la hora del último refresco. El riesgo real no es el
atraso en sí, es que alguien compare este tablero con una consulta en vivo sobre `pedido`,
vea dos números distintos y concluya que el sistema está mal. La única facturación que puede
diferir es la del **mes en curso**; los meses cerrados coinciden siempre.

Si en algún momento se necesitara el dato al instante, la salida no es refrescar más seguido
sino dejar el mes en curso fuera de la vista materializada y calcularlo en vivo (son unos
pocos días de pedidos), uniéndolo con los meses cerrados que sí vienen materializados.

---

## 4. Resumen

| Consulta / reporte | Antes | Después | Mejora |
|---|---:|---:|---|
| Q2 — Top 5 productos más vendidos | 258,9 ms | 222,9 ms | −13,9 % (buffers 12,5× menos) |
| Q3 — Ranking de usuarios por gasto | 135,1 ms | 106,1 ms | −21,5 % (con `rpc = 1.1`) |
| Q4 — Pedidos sobre el promedio | 82,9 ms | 29,1 ms | **−65 %**, sin tocar configuración |
| Facturación por categoría y mes | 279,8 ms | **0,025 ms** | **≈ 11.000×** (Parte C) |
| Carga de 500 `INSERT` | 99,8 ms | 137,8 ms | **+38 %** (el precio) |
