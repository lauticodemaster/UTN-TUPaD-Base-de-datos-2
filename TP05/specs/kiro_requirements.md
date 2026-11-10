# Requirements Document

## Introduction

Este documento especifica los requisitos para la creación de índices, vistas y una vista
materializada sobre el esquema `foodstore` de PostgreSQL 16, en el marco del trabajo
práctico TP5. El objetivo es mejorar el rendimiento de las consultas analíticas ya
existentes y formalizar las vistas de acceso al dominio, sin modificar el modelo de
datos ni las consultas originales.

Los objetos a crear son:

- **Tres índices** que eliminan escaneos secuenciales costosos y derrames a disco en
  las consultas analíticas A, C y D de `queries.sql`.
- **Cuatro vistas** que encapsulan las consultas frecuentes del sistema y protegen
  columnas sensibles, incluyendo una cuarta vista (`v_usuarios_publico`) que no existe
  actualmente.
- **Una vista materializada** que precomputa la facturación por categoría y mes,
  reduciendo el tiempo de esa consulta en al menos un orden de magnitud.

---

## Glossary

- **Baseline**: tiempo de ejecución medido antes de cualquier modificación, tomado como
  mediana de tres corridas en caliente con buffers cargados.
- **Condición parcial**: cláusula `WHERE` en la definición del índice que restringe las
  filas indexadas; reduce el tamaño del índice y el costo de mantenimiento.
- **Corridas en caliente**: ejecuciones realizadas después de que PostgreSQL ya cargó las
  páginas relevantes en `shared_buffers`, de modo que el resultado no esté inflado por
  I/O de disco frío.
- **Derrame a disco (spill)**: situación en la que una operación de hash o sort no entra
  en `work_mem` y escribe datos temporales al disco; se detecta con `Batches > 1` o
  `Sort Method: external merge`.
- **Heap Fetches**: número de visitas al heap (tabla base) que realiza un `Index Only
  Scan`; debe ser 0 para que el índice sea verdaderamente cubriente.
- **Índice cubriente**: índice que contiene todas las columnas que la consulta necesita
  leer, permitiendo resolver la consulta sin tocar el heap.
- **Sistema**: el motor PostgreSQL 16 operando sobre el esquema `foodstore`.
- **Vista materializada**: objeto que almacena físicamente el resultado de una consulta y
  debe refrescarse explícitamente; permite tiempos de consulta independientes del tamaño
  de las tablas origen.
- **EXCEPT simétrico**: par de consultas `A EXCEPT B` y `B EXCEPT A`; si ambas devuelven
  0 filas, los conjuntos son idénticos.
- **Filtro de vigencia**: predicado `eliminado = FALSE` aplicado sobre la entidad
  principal de una consulta para excluir filas dadas de baja lógicamente.
- **REFRESH CONCURRENTLY**: modalidad de refresco de vista materializada que no toma un
  lock exclusivo sobre la vista; requiere un índice único sobre las columnas de la vista.

---

## Índices ya existentes en el esquema

Los siguientes índices fueron creados en `schema.sql` y deben tenerse en cuenta para
evitar redundancias:

| Nombre del índice               | Definición                                        |
|---------------------------------|---------------------------------------------------|
| `idx_producto_categoria_id`     | `producto(categoria_id)`                          |
| `idx_pedido_usuario_id`         | `pedido(usuario_id)` — sin condición parcial,     |
|                                 | sin columnas incluidas                            |
| `idx_producto_no_eliminado`     | `producto(nombre) WHERE eliminado = FALSE`        |

Cada requisito de índice nuevo justifica explícitamente por qué no es redundante con
los anteriores.

---

## Invariante del sistema: filtros de vigencia en vistas

El filtro de vigencia (`eliminado = FALSE`) se aplica exclusivamente sobre la entidad
que da nombre a la vista, no sobre todas las tablas del JOIN. Esta decisión es un
invariante del sistema y debe respetarse en toda implementación:

- Las vistas de **catálogo** (p. ej. `v_productos_vigentes`) también filtran entidades
  relacionadas porque su propósito es mostrar lo que puede venderse hoy; un producto
  cuya categoría esté dada de baja no debe aparecer.
- Las vistas **históricas** (`v_pedidos_resumen`, `v_pedido_detalle`) registran hechos
  ya ocurridos. Filtrar `usuario.eliminado` o `producto.eliminado` en ellas haría
  desaparecer líneas de pedidos ya cobrados y descuadraría `pedido.total`. Cualquier
  propuesta que agregue esos filtros "por coherencia" se considera incorrecta.

---

## Requirements

---

### Requisito 1: Índice cubriente sobre `detalle_pedido` para el top de productos

**User Story:** Como administrador del sistema, quiero que la consulta de los 5 productos
más vendidos se ejecute sin escanear toda la tabla `detalle_pedido`, para que el panel
de inicio del backoffice responda con tiempos aceptables aunque el volumen de datos siga
creciendo.

#### Contexto

- Consulta objetivo: `queries.sql`, sección "Consultas analíticas", punto A.
- Tabla afectada: `detalle_pedido` (~800.008 filas, ~9.100 páginas de heap).
- Estado actual: `Seq Scan` sobre `detalle_pedido` + `Hash Join` contra `producto`;
  todas las páginas del heap se leen aunque solo se necesitan `producto_id` y `cantidad`
  de las filas no eliminadas.
- Índice existente relevante: ninguno de los tres índices actuales cubre
  `detalle_pedido`; no hay redundancia posible.
- Columnas que intervienen en la consulta: `eliminado` (condición parcial), `producto_id`
  (JOIN y GROUP BY), `cantidad` (SUM).
- El `ORDER BY` se aplica sobre el agregado `SUM(dp.cantidad)`, no sobre una columna
  de tabla, por lo que no es indexable.

#### Criterios de aceptación

1. WHEN se ejecuta la consulta del top de productos, THE Sistema SHALL producir un plan
   de ejecución que no contenga el nodo `Seq Scan` sobre `detalle_pedido`.

2. WHEN el planificador elige el índice, THE Sistema SHALL mostrar un nodo
   `Index Only Scan` sobre `detalle_pedido` con `Heap Fetches: 0`; un valor de
   `Heap Fetches > 0` indica que el índice no es cubriente y la propuesta no cumple
   este requisito.

3. WHEN se comparan los buffers leídos sobre `detalle_pedido` entre el plan con índice
   y el baseline, THE Sistema SHALL mostrar una reducción de al menos el 50 % en el
   número de buffers leídos.

4. WHEN se mide la mediana del tiempo de ejecución sobre tres corridas en caliente,
   THE Sistema SHALL mostrar una mejora respecto al baseline; la primera corrida no
   se considera suficiente por sí sola.

5. THE Sistema SHALL devolver un resultado idéntico al de la consulta original;
   la verificación se realiza con `EXCEPT` simétrico (0 filas en ambas direcciones)
   y comparación de `COUNT(*)`.

6. IF el planificador no elige el índice con la configuración por defecto,
   THEN THE Sistema SHALL documentar ese comportamiento en el informe de mediciones
   en lugar de forzar la elección mediante `enable_seqscan = off`.

---

### Requisito 2: Índice parcial cubriente sobre `pedido` para pedidos sobre el promedio

**User Story:** Como integrante del equipo de atención al cliente, quiero que el listado
de pedidos cuyo total supera el promedio general se entregue sin ordenación externa en
disco, para que la consulta responda de forma predecible en las varias veces por día que
se abre.

#### Contexto

- Consulta objetivo: `queries.sql`, sección "Consultas analíticas", punto D.
- Tabla afectada: `pedido` (~200.003 filas, ~3.930 páginas de heap).
- Estado actual: `Seq Scan` sobre `pedido` dos veces (una en el `InitPlan` del `AVG`,
  otra en la consulta principal) + `Sort Method: external merge  Disk: 2640kB`; el
  ordenador externo escribe ~2,6 MB a disco porque las 99.747 filas resultado no caben
  en `work_mem`.
- El filtro `total > promedio` devuelve ~50 % de las filas; la propuesta no se justifica
  por selectividad sino por eliminar el `Sort` externo.
- Índice existente relevante: `idx_pedido_usuario_id` cubre `pedido(usuario_id)` y no
  incluye `total` ni `eliminado`; no hay redundancia con el índice propuesto.
- Columnas que intervienen: `eliminado` (condición parcial), `total` (filtro de rango,
  `ORDER BY DESC`, `SUM` en `InitPlan`), `id` (proyección).
- Restricción operativa: no se incrementa `work_mem` para resolver el problema.

#### Criterios de aceptación

1. WHEN se ejecuta la consulta de pedidos sobre el promedio, THE Sistema SHALL producir
   un plan de ejecución sin el nodo `Sort`; las filas deben salir ya ordenadas del
   índice, resolviendo el `ORDER BY total DESC` mediante lectura inversa del índice.

2. WHEN se revisa el plan de ejecución, THE Sistema SHALL mostrar que ha desaparecido
   el nodo `Sort Method: external merge  Disk`.

3. WHEN el motor evalúa el `InitPlan` que calcula el `AVG`, THE Sistema SHALL resolverlo
   mediante `Index Only Scan` sobre el índice propuesto.

4. WHEN se mide la mediana del tiempo de ejecución sobre tres corridas en caliente,
   THE Sistema SHALL mostrar una mejora respecto al baseline.

5. THE Sistema SHALL devolver un resultado idéntico al original, incluido el orden de
   las filas; la verificación se realiza con `EXCEPT` simétrico y comparación de
   `COUNT(*)`.

---

### Requisito 3: Índice cubriente sobre `pedido` para el ranking de usuarios

**User Story:** Como analista de marketing, quiero que el ranking de usuarios por gasto
acumulado se ejecute sin que la agregación desborde a disco, para que el reporte tarde
menos al correrlo manualmente varias veces por semana.

#### Contexto

- Consulta objetivo: `queries.sql`, sección "Consultas analíticas", punto C.
- Tabla afectada: `pedido` (~200.003 filas) con `JOIN` a `usuario` (~20.005 filas).
- Estado actual: `Seq Scan` sobre `pedido` + `Hash Join` + `HashAggregate` con
  `Batches: 5, Disk Usage: 1576kB`; el derrame de la tabla hash, no el escaneo
  secuencial, es el costo dominante.
- El índice existente `idx_pedido_usuario_id` cubre `pedido(usuario_id)` pero no
  incluye `total` ni la condición parcial `eliminado = FALSE`; el índice propuesto
  añade la columna `total` como columna incluida y la condición parcial, por lo que
  no es redundante.
- Columnas que intervienen: `eliminado` (condición parcial), `usuario_id` (JOIN y
  GROUP BY), `total` (SUM).
- Restricción operativa: no se incrementa `work_mem`.

#### Criterios de aceptación

1. WHEN se ejecuta la consulta de ranking de usuarios, THE Sistema SHALL producir un
   plan de ejecución que no contenga `Seq Scan` sobre `pedido`.

2. WHEN el planificador elige el índice, THE Sistema SHALL mostrar un nodo
   `Index Only Scan` sobre `pedido` con `Heap Fetches: 0`.

3. WHEN se revisa el nodo de agregación en el plan, THE Sistema SHALL mostrar que la
   agregación no desborda a disco; el criterio se cumple si el plan muestra
   `GroupAggregate` o `HashAggregate` con `Batches: 1`.

4. WHEN se mide la mediana del tiempo de ejecución sobre tres corridas en caliente,
   THE Sistema SHALL mostrar una mejora respecto al baseline.

5. THE Sistema SHALL devolver un ranking idéntico al original, con el mismo orden y
   los mismos valores de `puesto`; la verificación se realiza con `EXCEPT` simétrico
   y comparación de `COUNT(*)`.

---

### Requisito 4: Vista `v_productos_vigentes`

**User Story:** Como desarrollador de la aplicación, quiero consultar los productos
vigentes a través de una vista que ya incorpore el filtro de vigencia y el JOIN con la
categoría, para no repetir esa lógica en cada pantalla del backoffice.

#### Contexto

- La vista ya existe en `objects.sql`; este requisito exige verificar que su definición
  es equivalente a la consulta manual de `queries.sql`.
- Columnas expuestas: `id`, `nombre`, `precio`, `stock`, `categoria` (nombre de la
  tabla `categoria`).
- Filtro de vigencia aplicado: `producto.eliminado = FALSE AND categoria.eliminado = FALSE`
  (vista de catálogo; ambos filtros son obligatorios según el invariante del sistema).

#### Criterios de aceptación

1. THE Sistema SHALL exponer exactamente las columnas `id`, `nombre`, `precio`,
   `stock` y `categoria` en la vista `v_productos_vigentes`.

2. WHEN se compara `v_productos_vigentes` contra la consulta manual equivalente,
   THE Sistema SHALL mostrar 0 filas en `(SELECT … FROM v_productos_vigentes EXCEPT
   SELECT … FROM consulta_manual)` y 0 filas en la dirección inversa.

3. WHEN se comparan los conteos, THE Sistema SHALL mostrar que `COUNT(*) FROM
   v_productos_vigentes` es igual al `COUNT(*)` de la consulta manual.

4. THE Sistema SHALL incluir en la vista el filtro `categoria.eliminado = FALSE`,
   de modo que un producto cuya categoría esté dada de baja no aparezca en el resultado.

---

### Requisito 5: Vista `v_pedidos_resumen`

**User Story:** Como operador del sistema, quiero consultar un resumen de pedidos con
datos del usuario a través de una vista, sin que datos sensibles del usuario queden
expuestos en la consulta.

#### Contexto

- La vista ya existe en `objects.sql`; este requisito exige verificar su equivalencia
  con la consulta manual.
- Columnas expuestas: `id`, `usuario` (concatenación `nombre || ' ' || apellido`),
  `fecha`, `estado`, `forma_pago`, `total`.
- Filtro de vigencia: `pedido.eliminado = FALSE` únicamente; `usuario.eliminado` no
  se filtra (vista histórica; ver invariante del sistema).
- Columnas ocultas: `mail`, `celular`, `contrasena` de la tabla `usuario` no se
  incluyen en la definición.

#### Criterios de aceptación

1. THE Sistema SHALL exponer exactamente las columnas `id`, `usuario`, `fecha`,
   `estado`, `forma_pago` y `total` en la vista `v_pedidos_resumen`.

2. WHEN se compara `v_pedidos_resumen` contra la consulta manual equivalente,
   THE Sistema SHALL mostrar 0 filas en el `EXCEPT` simétrico y conteos iguales.

3. THE Sistema SHALL omitir el filtro `usuario.eliminado = FALSE` de la definición
   de la vista, para que pedidos de usuarios dados de baja sigan apareciendo en el
   historial.

4. THE Sistema SHALL excluir las columnas `mail`, `celular` y `contrasena` del listado
   de columnas de la vista.

---

### Requisito 6: Vista `v_pedido_detalle`

**User Story:** Como operador del sistema, quiero consultar el detalle de líneas de
un pedido a través de una vista, para no repetir el JOIN y el filtro de vigencia en
cada pantalla de detalle de pedido.

#### Contexto

- La vista ya existe en `objects.sql`; este requisito exige verificar su equivalencia
  y agregar el control de cuadre de totales.
- Columnas expuestas: `pedido_id`, `producto` (nombre), `cantidad`, `precio_unitario`,
  `subtotal`.
- Filtro de vigencia: `detalle_pedido.eliminado = FALSE` únicamente; `producto.eliminado`
  no se filtra (vista histórica; ver invariante del sistema).

#### Criterios de aceptación

1. THE Sistema SHALL exponer exactamente las columnas `pedido_id`, `producto`,
   `cantidad`, `precio_unitario` y `subtotal` en la vista `v_pedido_detalle`.

2. WHEN se compara `v_pedido_detalle` contra la consulta manual equivalente,
   THE Sistema SHALL mostrar 0 filas en el `EXCEPT` simétrico y conteos iguales.

3. THE Sistema SHALL omitir el filtro `producto.eliminado = FALSE` de la definición
   de la vista, para que líneas de productos dados de baja sigan apareciendo en el
   historial de pedidos.

4. WHEN se compara la suma de `subtotales` por pedido en la vista contra `pedido.total`
   para todos los pedidos vigentes, THE Sistema SHALL mostrar 0 pedidos con diferencia
   mayor a 0,00.

---

### Requisito 7: Vista `v_usuarios_publico` (nueva)

**User Story:** Como administrador de seguridad, quiero otorgar a un rol de solo lectura
acceso a los datos de usuarios sin exponer el hash de contraseña, para cumplir el
principio de mínimo privilegio.

#### Contexto

- Esta vista no existe en `objects.sql`; debe crearse.
- Columnas expuestas: `id`, `nombre`, `apellido`, `mail`, `celular`, `rol`, `created_at`
  (lista explícita; `SELECT *` queda prohibido para esta vista).
- Columna oculta: `contrasena`.
- Filtro de vigencia: `usuario.eliminado = FALSE`.
- Rol destinatario: `app_lectura`, creado con `GRANT SELECT` únicamente sobre esta
  vista.

#### Criterios de aceptación

1. THE Sistema SHALL exponer exactamente las columnas `id`, `nombre`, `apellido`,
   `mail`, `celular`, `rol` y `created_at` en la vista `v_usuarios_publico`, sin
   utilizar `SELECT *` en su definición.

2. WHEN se compara `v_usuarios_publico` contra la consulta manual equivalente,
   THE Sistema SHALL mostrar 0 filas en el `EXCEPT` simétrico y conteos iguales.

3. WHEN un cliente ejecuta `SELECT contrasena FROM v_usuarios_publico`,
   THE Sistema SHALL retornar un error con el mensaje "column ... does not exist",
   confirmando que la columna no está expuesta por la vista.

4. WHEN el rol `app_lectura` ejecuta `SELECT * FROM v_usuarios_publico`,
   THE Sistema SHALL permitir la operación y devolver filas.

5. WHEN el rol `app_lectura` ejecuta `SELECT * FROM usuario`,
   THE Sistema SHALL retornar un error de permisos ("permission denied for table usuario"),
   confirmando que el rol no tiene acceso directo a la tabla.

6. THE Sistema SHALL listar las columnas de la vista una a una en su definición,
   de modo que cualquier columna añadida a la tabla `usuario` en el futuro no quede
   automáticamente expuesta.

---

### Requisito 8: Vista materializada `mv_facturacion_categoria_mes`

**User Story:** Como integrante de la gerencia, quiero que el tablero de facturación
por categoría y mes responda en milisegundos en lugar de en cientos de milisegundos,
para poder abrirlo varias veces al día sin degradar el rendimiento del sistema.

#### Contexto

- Consulta objetivo: `queries.sql`, sección "Consultas analíticas", punto B.
- Estado actual: 266–270 ms; recorre `detalle_pedido` (800k filas), `pedido` (200k),
  `producto` (50k) y `categoria` para devolver 29 filas; la relación entre trabajo
  realizado y resultado obtenido es el caso típico para materialización.
- Frecuencia de lectura: alta — el tablero lo consulta la gerencia varias veces al día
  y lo carga la pantalla de inicio del backoffice.
- Frecuencia de cambio: los pedidos de meses cerrados no cambian; solo varía el mes
  en curso.
- El `ORDER BY` (mes DESC, facturado DESC) se aplica al consultar la vista, no en su
  definición; una vista materializada es un conjunto de filas almacenadas y el orden
  en que se leen depende del acceso, no del `ORDER BY` de creación.

#### Criterios de aceptación

1. THE Sistema SHALL crear la vista materializada con la cláusula `WITH DATA`, de modo
   que las filas estén disponibles inmediatamente tras la creación.

2. THE Sistema SHALL definir un índice único sobre las columnas `(categoria, mes)` de
   la vista materializada, como requisito previo para poder ejecutar
   `REFRESH MATERIALIZED VIEW CONCURRENTLY` en el futuro.

3. WHEN se compara `mv_facturacion_categoria_mes` (ordenada) contra la consulta
   original (ordenada), THE Sistema SHALL mostrar 0 filas en el `EXCEPT` simétrico
   y el mismo `COUNT(*)`.

4. WHEN se mide la mediana del tiempo de consulta sobre la vista materializada en tres
   corridas en caliente, THE Sistema SHALL mostrar un tiempo menor a 27 ms (al menos
   un orden de magnitud inferior al baseline de 266–270 ms).

5. WHEN se ejecuta el `REFRESH` de la vista materializada, THE Sistema SHALL registrar
   el tiempo de ese refresco en el informe de mediciones, porque ese costo es el que
   determina si la estrategia de materialización es viable.

6. THE Sistema SHALL incluir en el informe de mediciones la frecuencia de refresco
   propuesta y una descripción del impacto para el usuario final de que el dato no
   esté actualizado al segundo (datos con latencia de refresco conocida).

7. IF el `ORDER BY` se incluye dentro de la definición de la vista materializada,
   THEN THE Sistema SHALL rechazar esa implementación, porque el orden de lectura de
   una vista materializada no está garantizado por el orden de inserción.
