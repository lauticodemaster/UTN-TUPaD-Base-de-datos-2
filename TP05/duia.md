# DUIA — Declaración de Uso de IA (TP5, Unidad 3 Semana 5)

**Grupo H: Saferazi** — Danilo Serrano, Elio Marí, Daniela Díaz, Jesús Ramírez y Lautaro Fernández.

Bitácora del flujo **especificar → generar → leer → verificar → decidir** sobre Food Store.

Las transcripciones crudas de cada corrida de OpenCode están en `duia_logs/`; lo que sigue
es la bitácora razonada, con lo que se aceptó, lo que se modificó y lo que se descartó.

| Herramienta | Versión / modelo | Para qué se usó |
|---|---|---|
| **Kiro** | 1.1.14 | Especificar: consolidar las cinco specs de `specs/` en la especificación del trabajo, con criterios de aceptación medibles |
| **OpenCode** (CLI) | `muse-spark-1.3-contributor-free` | Generar: proponer las sentencias `CREATE INDEX`, y escribir el SQL de las vistas, la vista materializada y las verificaciones |
| **PostgreSQL 17.6** | — | Verificar: toda propuesta se aceptó o se rechazó con `EXPLAIN (ANALYZE, BUFFERS)`, nunca por el argumento de la herramienta |

**Regla que se siguió en todo el trabajo:** ningún script generado se ejecutó sin leerlo
línea por línea, y ninguna propuesta se aceptó por su explicación. Se delegó la escritura
del SQL; **la decisión no se delegó nunca**, y abajo están los cuatro casos en los que la
decisión terminó siendo la contraria a la recomendación recibida.

---

## Interacción 1 — Especificación (Kiro)

**Propósito:** especificar antes de generar.

**Prompt entregado, tal cual:**

```
Leé TP5/specs/ (los 5 archivos), TP1/schema.sql y TP1/queries.sql. Escribí la
especificación del trabajo "índices, vistas y vista materializada de Food Store"
para PostgreSQL 16: requisitos con criterios de aceptación medibles (plan esperado,
buffers, tiempo), diseño de cada objeto y tareas. No escribas SQL de implementación
ni ejecutes nada: solo la especificación. Respetá que no se modifica el modelo de
datos ni las consultas originales.
```

**Qué se le dio de contexto:** los cinco borradores de spec redactados por el equipo
(`specs/spec_indice_top_productos.md`, `spec_indice_ranking_usuarios.md`,
`spec_indice_pedidos_sobre_promedio.md`, `spec_vistas_reportes.md`,
`spec_mv_facturacion_categoria_mes.md`), más el esquema y las consultas heredadas.

**Qué se aceptó:** la estructura de requisitos con criterio de aceptación por objeto, que es
lo que después permitió rechazar propuestas con un criterio escrito de antemano en vez de
"me parece". Las specs de `specs/` son las que se le pasaron a OpenCode como contexto en las
interacciones 2 y 3.

**Nota sobre el formato de las specs.** El formato de `specs/*.md` es el que define la propia
consigna en su punto 5 (`# spec: nombre` / objetivo / consulta afectada / columnas candidatas
/ criterio de aceptación). Se mantuvo ese formato porque es el que la cátedra evalúa y porque
es el que se le entrega literalmente al agente generador.

---

## Interacción 2 — Índices sobre `detalle_pedido` (OpenCode)

Log crudo: `duia_logs/opencode_01_top_productos.txt`

**Prompt entregado, tal cual:**

```
Lee el archivo TP5/specs/spec_indice_top_productos.md y el archivo TP1/schema.sql.
A partir de ESA especificacion, proponeme las sentencias CREATE INDEX que
resolverian el criterio de aceptacion. No escribas ningun archivo, no ejecutes
nada: respondeme solo con las propuestas. Para cada propuesta deci: tipo de indice,
columnas, si es parcial y por que, si usa INCLUDE y por que, y que riesgo tiene.
Proponeme tambien cualquier indice adicional que te parezca util para esa tabla
aunque no lo pida el spec.
```

**Qué propuso:**

| | Propuesta | Cómo la presentó |
|---|---|---|
| P1 | `detalle_pedido (producto_id) INCLUDE (cantidad) WHERE eliminado = FALSE` | "Principal recomendada" |
| P2 | `detalle_pedido (producto_id, cantidad) WHERE eliminado = FALSE` | "Variante equivalente (si no hay INCLUDE)" |
| P3 | `detalle_pedido (producto_id) INCLUDE (cantidad, subtotal) WHERE eliminado = FALSE` | "Adicional fuera del spec", anticipando un futuro reporte por facturación |

Acertó en lo conceptual: descartó `eliminado` como columna indexada y la usó como predicado
parcial, explicó por qué el `ORDER BY` sobre `SUM()` no es indexable, y avisó que el
planificador podía seguir prefiriendo `Seq Scan`.

### Qué se ACEPTÓ: P2 — invirtiendo la recomendación

Se creó **P2**, no P1. La herramienta presentó P2 como un plan B para versiones viejas de
PostgreSQL; la medición dice lo contrario:

| Variante | Páginas del índice | Tamaño | Tiempo |
|---|---:|---:|---:|
| P1 — `(producto_id) INCLUDE (cantidad)` | 3.084 | 24 MB | 236,1 ms |
| **P2 — `(producto_id, cantidad)`** | **692** | **5.536 kB** | **222,9 ms** |

**El motivo es la deduplicación de B-tree, que P1 desactiva.** PostgreSQL comprime las claves
repetidas en una única entrada con su lista de TIDs, pero apaga esa compresión en cuanto el
índice tiene columnas `INCLUDE`. Sobre 800.008 filas hay **12 `producto_id` distintos y 28
pares `(producto_id, cantidad)` distintos**: la deduplicación es exactamente lo que más rinde
acá, y P1 la tira a la basura. Consecuencia medible: con P1 el planificador **no** elegía el
índice con la configuración por defecto; con P2 lo elige solo.

La herramienta no mencionó la deduplicación en ningún momento. Es el tipo de cosa que
aparece midiendo, no leyendo la respuesta.

### Qué se DESCARTÓ

- **P1** — por lo anterior. Se creó, se midió, se borró.
- **P3** — especulativa: el reporte "top por facturación" que la justificaría no existe en
  `queries.sql`, y arrastra el mismo problema de `INCLUDE`. Indexar para una consulta que
  todavía no existe es sobreindexación aunque el razonamiento suene razonable.

### Qué se CORRIGIÓ del diagnóstico

La herramienta afirmó: *"hoy el único índice con `producto_id` es `UNIQUE(pedido_id,
producto_id)`"*. **Es falso.** Existía `idx_detalle_pedido_producto_id`, creado en el TP3, y
la herramienta no lo vio porque se le dio `schema.sql` como contexto y ese índice no está
ahí: lo agregó un script de la semana anterior. Aprendizaje operativo: al pedir un plan de
indexado hay que darle **el estado real del catálogo** (`pg_indexes`), no el archivo de
esquema, porque el archivo miente por omisión apenas el proyecto tiene una semana de historia.

Consecuencia de haberlo detectado: `idx_dp_top_productos` **reemplaza** a
`idx_detalle_pedido_producto_id` (misma tabla, mismo predicado parcial, misma columna líder),
así que el viejo se borra en `indices.sql`. Antes de borrarlo se controló que la analítica E
("productos sin ventas") siguiera resolviendo por `Index Only Scan`: lo hace, ahora sobre el
índice nuevo, con 728 buffers.

---

## Interacción 3 — Índices sobre `pedido` (OpenCode)

Log crudo: `duia_logs/opencode_02_pedido.txt`

**Prompt entregado, tal cual:**

```
Lee TP5/specs/spec_indice_ranking_usuarios.md,
TP5/specs/spec_indice_pedidos_sobre_promedio.md y TP1/schema.sql. A partir de ESAS
especificaciones proponeme las sentencias CREATE INDEX para la tabla pedido. No
escribas archivos ni ejecutes nada: respondeme solo con las propuestas. Para cada
una deci tipo, columnas, si es parcial y por que, si usa INCLUDE y por que, y que
riesgo tiene. Al final proponeme ademas cualquier otro indice que le pondrias a la
tabla pedido para el resto de las consultas del sistema.
```

**Qué propuso:** cuatro índices.

| | Propuesta | Destino |
|---|---|---|
| 1 | `pedido (usuario_id) INCLUDE (total) WHERE eliminado = FALSE` | ranking de usuarios |
| 2 | `pedido (total DESC) INCLUDE (id) WHERE eliminado = FALSE` | pedidos sobre el promedio |
| 3a | `pedido (usuario_id, fecha DESC) WHERE eliminado = FALSE` | "historial de un usuario" |
| 3b | `pedido (estado, fecha DESC) WHERE eliminado = FALSE` | "tablero por estado" |

### Qué se ACEPTÓ: 1 y 2, tal cual

Las dos se crearon sin modificaciones, y el argumento que dio para cada una se sostuvo al
medirlo:

- **#1** entrega `Index Only Scan` con `Heap Fetches: 11` y baja los buffers de 4.272 a 1.344.
- **#2** hace desaparecer el `Sort Method: external merge Disk: 2640kB` del plan original y
  lleva la consulta de 82,9 ms a 29,1 ms (−65 %), **eligiéndolo el planificador solo**, con
  la configuración por defecto.

Además acertó al justificar por qué #1 **no** es redundante con `idx_pedido_usuario_id` de
`schema.sql` (ese no es parcial ni covering), aunque propuso reemplazarlo. **Ahí no se le hizo
caso:** el viejo se conserva, porque al no ser parcial es el único que sirve para buscar
pedidos de un usuario **incluyendo los dados de baja**, que es lo que necesita la auditoría de
HU-PED-04. El criterio que se fijó es que un índice viejo se borra sólo si el nuevo cubre
**todas** sus consultas; para `detalle_pedido` se cumplía, para `pedido` no.

### Qué se DESCARTÓ: 3a

Se solapa con #1 en la columna líder y **ninguna consulta de `queries.sql` filtra por usuario
y ordena por fecha**. La propia herramienta avisó del solape ("crear 1 + 3a duplica"), así que
acá el descarte coincidió con su advertencia.

### **El caso de sobreindexación descartado (requisito de la consigna): 3b**

```sql
CREATE INDEX idx_pedido_estado_fecha
    ON pedido (estado, fecha DESC)
    WHERE eliminado = FALSE;
```

Justificación recibida: *"tablero por estado (`PENDIENTE`/`CONFIRMADO`/...)"*, reconociendo
ella misma que *"`estado` solo es poco selectivo"*.

**Se rechaza. Los cuatro motivos, en orden de peso:**

1. **Ninguna consulta del sistema lo usaría.** En `queries.sql`, `estado` aparece únicamente
   en un `UPDATE ... WHERE id = 1` (HU-PED-03), que resuelve por clave primaria. El tablero
   por estado que justificaría el índice **no existe**. Indexar para una consulta hipotética
   es la definición de sobreindexación, y es exactamente lo que el spec pedía vigilar.
2. **Cardinalidad bajísima en la columna líder:** `estado` tiene 4 valores para 200.003 filas
   — bloques de ~50.000 filas cada uno. Ni con `fecha` de segunda columna se vuelve selectivo,
   salvo que además se filtre por rango de fechas, lo que nos devuelve al punto 1.
3. **Se midió lo que cuesta.** Con el índice creado, la carga de 500 `INSERT` pasó de
   **137,8 ms a 143,5 ms (+4,1 %)**, y ocupa 1.384 kB. A cambio: **cero** consultas
   aceleradas. Y `pedido` es una tabla caliente — `trg_total_ins` la actualiza en cada
   `INSERT` de `detalle_pedido`, así que ese 4 % se paga en todo el sistema, no en un reporte.
4. **El día que el tablero exista, éste probablemente no sea el índice correcto**, sino uno
   parcial por el estado que realmente se consulte
   (`WHERE eliminado = FALSE AND estado = 'PENDIENTE'`), mucho más chico. Crearlo hoy "por las
   dudas" nos ataría a la forma equivocada y habría que borrarlo igual.

El índice se creó, se midió y se borró. La medición está en `informe_mediciones.md` §1.5.

---

## Interacción 4 — Vistas, vista materializada y verificaciones (OpenCode)

Log crudo: `duia_logs/opencode_03_vistas.txt`

**Prompt entregado, tal cual:**

```
Lee TP5/specs/spec_vistas_reportes.md, TP5/specs/spec_mv_facturacion_categoria_mes.md,
TP1/schema.sql y TP1/objects.sql. Generame el SQL de: (a) la vista v_usuarios_publico
que falta, con el rol de solo lectura y sus GRANT, (b) la vista materializada de
facturacion por categoria y mes con su indice unico, y (c) las consultas de
verificacion de equivalencia de cada vista contra la consulta manual. No escribas
archivos ni ejecutes nada, respondeme con el SQL en el chat y explicame cada decision.
```

**Qué propuso:** `v_usuarios_publico` con las siete columnas listadas una por una, el rol
`app_lectura NOLOGIN` con `GRANT USAGE` + `GRANT SELECT` sobre la vista, la vista
materializada con su índice único, y los cinco bloques de verificación por diferencia
simétrica + `COUNT(*)`.

### Qué se ACEPTÓ

- La vista con las columnas **listadas explícitamente**, no `SELECT *`. El argumento es
  correcto y vale repetirlo: con `SELECT *`, cualquier columna que se agregue a `usuario` más
  adelante quedaría expuesta sola, sin que nadie lo revise.
- El `GRANT USAGE ON SCHEMA` junto al `GRANT SELECT`: sin el primero, el segundo no sirve
  (falla con `permission denied for schema`). Es un error clásico y lo evitó.
- Su explicación de por qué **no** hace falta `SECURITY DEFINER`: en PostgreSQL una vista se
  ejecuta con los permisos de su dueño, así que `app_lectura` puede leerla sin tener nada
  sobre la tabla base. Se verificó en la base, no se aceptó de palabra (ver abajo).
- Dejar el `ORDER BY` **fuera** de la vista materializada, con el argumento correcto: una MV
  es un conjunto de filas almacenado y el orden de inserción no garantiza el orden de lectura.
- El esquema de verificación con **diferencia simétrica más `COUNT(*)`**. Los dos controles
  hacen falta: `EXCEPT` elimina duplicados, así que si la vista repitiera una fila y la
  consulta manual no, la diferencia simétrica daría 0 igual y no nos enteraríamos. El `COUNT`
  sí lo detecta.

### Qué se CORRIGIÓ antes de ejecutar (dos errores que habrían roto el script)

1. **Sintaxis inválida en la vista materializada.** Generó:

   ```sql
   CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes WITH DATA AS
   SELECT ...
   ```

   `WITH DATA` va **al final**, después del `SELECT`, no entre el nombre y el `AS`. Tal cual
   venía, la sentencia no compila. Corregido a:

   ```sql
   CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
   SELECT ...
   GROUP BY ...
   WITH DATA;
   ```

   Es exactamente el motivo por el que la cátedra exige leer línea por línea antes de
   ejecutar: la explicación que acompañaba el bloque era correcta y el SQL no.

2. **`CREATE ROLE app_lectura NOLOGIN;` sin guarda.** `CREATE ROLE` no admite
   `IF NOT EXISTS`, así que al reejecutar el script falla con `role already exists` y corta
   todo lo que viene después. Se envolvió en un bloque `DO` que pregunta primero contra
   `pg_roles`, para que `views.sql` sea reejecutable.

Se agregó además `DROP MATERIALIZED VIEW IF EXISTS` antes del `CREATE`, por el mismo motivo.

### Verificación de equivalencia realizada (requisito de la consigna)

Se corrieron las cinco verificaciones sobre `foodstore_test`
(`mediciones/verificacion_vistas.sql`). Resultados reales:

| Vista | Diferencia simétrica | `COUNT(*)` vista = manual | Control extra |
|---|---|---|---|
| `v_productos_vigentes` | **0 filas** | 50.012 = 50.012 | — |
| `v_pedidos_resumen` | **0 filas** | 200.003 = 200.003 | — |
| `v_pedido_detalle` | **0 filas** | 800.008 = 800.008 | **0 pedidos descuadrados** |
| `v_usuarios_publico` | **0 filas** | 20.005 = 20.005 | ver seguridad |
| `mv_facturacion_categoria_mes` | **0 filas** | 29 filas materializadas | — |

Y las tres pruebas de seguridad de `v_usuarios_publico`
(`mediciones/verificacion_seguridad.sql`):

```
SELECT contrasena FROM v_usuarios_publico;
  -> ERROR: column "contrasena" does not exist          (esperado)

SET ROLE app_lectura; SELECT ... FROM v_usuarios_publico;
  -> devuelve filas                                      (esperado)

SET ROLE app_lectura; SELECT ... FROM usuario;
  -> ERROR: permission denied for table usuario          (esperado)

has_table_privilege('app_lectura','foodstore.usuario','SELECT')            -> f
has_table_privilege('app_lectura','foodstore.v_usuarios_publico','SELECT') -> t
```

La afirmación de la herramienta sobre los permisos del dueño de la vista quedó comprobada
contra el motor, que era el punto: se aceptó el mecanismo **después** de verlo funcionar, no
porque lo explicara bien.

---

## Interacción 5 — Revisión final del SQL entregado (OpenCode)

Captura: `capturas/opencode_revision_final.png`

**Propósito:** revisar, no generar. Se le dio a leer el SQL ya escrito y corregido, para que
buscara errores que se nos hubieran pasado.

**Prompt entregado, tal cual:**

```
Lee TP5/indices.sql y TP5/views.sql. Revisalos: decime si alguna sentencia tiene
un error de sintaxis de PostgreSQL, si algun indice quedo redundante con otro, y
si la vista materializada podria refrescarse con CONCURRENTLY. Se breve, no
escribas archivos.
```

**Qué respondió:**

1. *"Sintaxis PostgreSQL: sin errores."* — repasa `CREATE INDEX ... INCLUDE (...) WHERE ...`,
   `DROP INDEX IF EXISTS`, `VACUUM (ANALYZE)`, `CREATE OR REPLACE VIEW`, el bloque
   `DO $$ ... CREATE ROLE`, los `GRANT`/`REVOKE`, `DROP`/`CREATE MATERIALIZED VIEW ... WITH
   DATA`, `CREATE UNIQUE INDEX` y `ANALYZE`. En particular da por válida la forma corregida
   del `WITH DATA`, que es la que ella misma había generado mal en la interacción 4.
2. *"Índices redundantes: ninguno queda."* — confirma que `idx_dp_top_productos` es superset
   de `idx_detalle_pedido_producto_id` **y que ese se borra**, que
   `idx_pedido_ranking_usuarios` no es redundante con `idx_pedido_usuario_id` por tener
   distinto predicado (*"el no-parcial sigue necesario para auditoría"*), y que
   `idx_pedido_sobre_promedio` es el único sobre `total`.
3. *"MV `CONCURRENTLY`: sí puede"* — porque el índice único está sobre la llave del
   `GROUP BY`, que es el requisito del motor.

**Qué se hizo con eso:** no cambió nada del entregable; se usó como control cruzado de las
decisiones ya tomadas y medidas. Sirve, además, para mostrar el contraste con la interacción
4: la misma herramienta que había escrito `WITH DATA` en el lugar equivocado valida sin
problema la versión corregida. Una revisión con IA detecta lo que uno le pregunta, no lo que
uno no pensó preguntar.

---

## Capturas

| Archivo | Qué muestra |
|---|---|
| `capturas/kiro_spec_requirements.png` | Kiro con el spec `foodstore-indices-vistas-mv` abierto (Requirements / Design / Task list) y el prompt de la interacción 1 en el panel de chat |
| `capturas/opencode_terminal_lectura.png` | OpenCode corriendo en la terminal, leyendo `TP5/indices.sql` y `TP5/views.sql` |
| `capturas/opencode_revision_final.png` | La respuesta completa de la revisión de la interacción 5 |

---

## Cierre: dónde la herramienta ayudó y dónde no

**Ayudó** en escribir SQL correcto rápido, en no olvidarse del `GRANT USAGE ON SCHEMA`, en
proponer el predicado parcial en vez de indexar el booleano, y en avisar de riesgos reales
(que el planificador podía ignorar el índice, que un índice sobre `total` se paga caro porque
un trigger toca esa columna todo el tiempo).

**No ayudó**, y hubo que corregirla, en cuatro puntos, todos detectados midiendo o leyendo:

1. Recomendó `INCLUDE` donde la clave compuesta es 4,5× más chica, por ignorar la
   deduplicación de B-tree.
2. Afirmó un estado del catálogo que era falso, por haber leído `schema.sql` en lugar del
   catálogo real.
3. Generó una sentencia `CREATE MATERIALIZED VIEW` sintácticamente inválida, con una
   explicación correcta al lado.
4. Propuso un índice de baja cardinalidad para un reporte que no existe.

Ninguno de los cuatro se detecta leyendo la respuesta: los cuatro se detectan ejecutando,
midiendo y comparando contra el criterio de aceptación escrito **antes** de pedir la
propuesta. Ésa es, en concreto, la diferencia entre delegar la escritura del SQL y delegar la
decisión.
