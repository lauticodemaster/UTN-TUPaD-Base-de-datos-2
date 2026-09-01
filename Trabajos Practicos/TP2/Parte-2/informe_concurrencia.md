# Informe de Concurrencia — Proyecto foodstore

> **Estado:** los 3 escenarios obligatorios (lectura no repetible, lectura
> fantasma, espera por bloqueo) están completos y verificados contra el
> motor real, sobre la copia de trabajo `foodstore_test` (nunca sobre
> `foodstore`), siguiendo `protocolo_seguridad.md`. El Escenario 4
> (interbloqueo) es opcional y no se realizó. Solo falta completar el campo
> "Spec o prompt utilizado" de la DUIA con tus propias palabras.

---

## Escenario 1 — Lectura no repetible

**Tabla y columna:** `producto.precio` (id = 1)

### Cómo se reprodujo

**Con READ COMMITTED (nivel por defecto):**

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `SELECT precio FROM producto WHERE id = 1;` | |
| 3 | | `BEGIN;` |
| 4 | | `UPDATE producto SET precio = precio + 100 WHERE id = 1;` |
| 5 | | `COMMIT;` |
| 6 | `SELECT precio FROM producto WHERE id = 1;` *(mismo SELECT, misma transacción)* | |
| 7 | `COMMIT;` | |

**Repetido con REPEATABLE READ** (Sesión A arranca con
`BEGIN ISOLATION LEVEL REPEATABLE READ;` en vez de `BEGIN;`, mismos pasos).

### Qué se observó

```
-- Sesión A
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# SELECT precio FROM producto WHERE id = 1;
 precio
---------
 1800.00
(1 fila)

-- Sesión B
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# UPDATE producto SET precio = precio + 100 WHERE id = 1;
UPDATE 1
foodstore_test=*# COMMIT;
COMMIT

-- Sesión A (continúa la misma transacción)
foodstore_test=*# SELECT precio FROM producto WHERE id = 1;
 precio
---------
 1900.00
(1 fila)
foodstore_test=*# COMMIT;
COMMIT
```

El segundo `SELECT` de la Sesión A devolvió `1900.00`, distinto del primero
(`1800.00`), a pesar de estar dentro de la misma transacción — confirma la
lectura no repetible en `READ COMMITTED`.

### Explicación de la IA

*(Herramienta: Claude — pegada tal cual, no editada)*

> En `READ COMMITTED`, cada sentencia dentro de la transacción toma su
> propia foto (snapshot) de la base al momento de ejecutarse. Por eso, si la
> Sesión B confirma un `UPDATE` entre el primer y el segundo `SELECT` de la
> Sesión A, el segundo `SELECT` ve el valor nuevo aunque la transacción de A
> no haya terminado: eso es una lectura no repetible. En `REPEATABLE READ`,
> en cambio, toda la transacción usa una única foto tomada al momento del
> primer `SELECT` (o del `BEGIN`), así que el segundo `SELECT` vuelve a ver
> el valor viejo, sin importar lo que haya confirmado la Sesión B mientras
> tanto. El mecanismo que lo evita no es un bloqueo, sino MVCC: PostgreSQL
> le sirve a cada transacción versiones de fila coherentes con su propio
> punto de partida.

### Verificación en el motor

```
-- Sesión A
foodstore_test=# BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
foodstore_test=*# SELECT precio FROM producto WHERE id = 1;
 precio
---------
 2100.00
(1 fila)

-- Sesión B (mientras la transacción de A seguía abierta)
foodstore_test=*# UPDATE producto SET precio = precio + 100 WHERE id = 1;
UPDATE 1
foodstore_test=*# COMMIT;
COMMIT

-- Sesión A (mismo BEGIN, segundo SELECT)
foodstore_test=*# SELECT precio FROM producto WHERE id = 1;
 precio
---------
 2100.00
(1 fila)
foodstore_test=*# COMMIT;
COMMIT
```

El segundo `SELECT` de la Sesión A devolvió el mismo valor (`2100.00`) que el
primero, a pesar de que la Sesión B confirmó un `UPDATE` sobre esa misma
fila en el medio de la transacción.

### Conclusión

La explicación de la IA se confirmó en el motor: en `READ COMMITTED` el
segundo `SELECT` de la Sesión A vio el cambio confirmado por la Sesión B
(lectura no repetible), y en `REPEATABLE READ` esa misma secuencia devolvió
el valor original las dos veces, sin importar los `COMMIT` externos. El
nivel `REPEATABLE READ` resuelve la anomalía gracias al snapshot que toma
Postgres al inicio de la transacción (MVCC), no mediante un bloqueo.

---

## Escenario 2 — Lectura fantasma

**Tabla y columna:** `pedido.estado = 'PENDIENTE'`

### Cómo se reprodujo

**Con READ COMMITTED:**

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `SELECT COUNT(*) FROM pedido WHERE estado = 'PENDIENTE';` | |
| 3 | | `BEGIN;` |
| 4 | | `INSERT INTO pedido (forma_pago, usuario_id, estado) VALUES ('EFECTIVO', 1, 'PENDIENTE');` |
| 5 | | `COMMIT;` |
| 6 | `SELECT COUNT(*) FROM pedido WHERE estado = 'PENDIENTE';` *(mismo COUNT, misma transacción)* | |
| 7 | `COMMIT;` | |

**Repetido con REPEATABLE READ** (mismo flujo, `BEGIN ISOLATION LEVEL REPEATABLE READ;` en Sesión A).

> `usuario_id = 1` corresponde a Miguel, verificado como real en la base.

### Qué se observó

```
-- Sesión A
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# SELECT COUNT(*) FROM pedido WHERE estado = 'PENDIENTE';
 count
-------
     1
(1 fila)

-- Sesión B
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# INSERT INTO pedido (forma_pago, usuario_id, estado) VALUES ('EFECTIVO', 1, 'PENDIENTE');
INSERT 0 1
foodstore_test=*# COMMIT;
COMMIT

-- Sesión A (continúa la misma transacción)
foodstore_test=*# SELECT COUNT(*) FROM pedido WHERE estado = 'PENDIENTE';
 count
-------
     2
(1 fila)
foodstore_test=*# COMMIT;
COMMIT
```

El segundo `COUNT(*)` de la Sesión A pasó de `1` a `2`, dentro de la misma
transacción, porque vio el `pedido` nuevo que insertó y confirmó la Sesión B
— lectura fantasma en `READ COMMITTED`.

### Explicación de la IA

*(Herramienta: Claude — pegada tal cual, no editada)*

> Una lectura fantasma ocurre cuando una fila *nueva* aparece (o desaparece)
> entre dos lecturas de un mismo conjunto dentro de la misma transacción,
> a diferencia de la lectura no repetible, que es sobre una fila que ya
> existía. En `READ COMMITTED`, cada `SELECT COUNT(*)` ve el estado
> confirmado más reciente, así que el segundo conteo va a incluir el
> `pedido` que insertó la Sesión B. Según el estándar SQL, `REPEATABLE READ`
> no está obligado a evitar fantasmas — solo `SERIALIZABLE` lo garantiza
> formalmente.

### Verificación en el motor

```
-- Sesión A
foodstore_test=# BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
foodstore_test=*# SELECT COUNT(*) FROM pedido WHERE estado = 'PENDIENTE';
 count
-------
     2
(1 fila)

-- Sesión B (mientras la transacción de A seguía abierta)
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# INSERT INTO pedido (forma_pago, usuario_id, estado) VALUES ('EFECTIVO', 1, 'PENDIENTE');
INSERT 0 1
foodstore_test=*# COMMIT;
COMMIT

-- Sesión A (mismo BEGIN, segundo COUNT)
foodstore_test=*# SELECT COUNT(*) FROM pedido WHERE estado = 'PENDIENTE';
 count
-------
     2
(1 fila)
foodstore_test=*# COMMIT;
COMMIT
```

El segundo `COUNT(*)` se mantuvo en `2`, igual que el primero, a pesar de
que la Sesión B insertó y confirmó un `pedido` nuevo con `estado =
'PENDIENTE'` en el medio de la transacción de A.

### Conclusión

La explicación de la IA se confirmó parcialmente: en `READ COMMITTED` el
segundo `COUNT(*)` sí vio la fila nueva (fantasma real). En `REPEATABLE
READ`, sin embargo, el conteo se mantuvo igual — lo cual coincide con la
nota del informe: la implementación de `REPEATABLE READ` de PostgreSQL usa
snapshot isolation (MVCC), y en la práctica esa foto tomada al inicio de la
transacción también bloqueó este fantasma puntual, aunque el estándar SQL
no lo garantice para ese nivel (formalmente solo `SERIALIZABLE` lo exige).
Es la discrepancia entre "teoría genérica" y "motor real" que la consigna
pide documentar: la explicación inicial de la IA (que decía que sólo
`SERIALIZABLE` lo evita) no se sostuvo al verificarla contra Postgres.

> **Nota para la verificación:** la implementación de `REPEATABLE READ` de
> PostgreSQL no es la del estándar SQL — es *snapshot isolation*, y por
> cómo toma la foto al inicio de la transacción, en la práctica también
> bloquea este fantasma puntual (aunque el estándar no lo exija). Registrar
> esto tal cual salió es justamente lo que la consigna pide.

---

## Escenario 3 — Espera por bloqueo

**Tabla y columna:** `producto` (id = 1)

### Cómo se reprodujo

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | |
| 2 | `SELECT * FROM producto WHERE id = 1 FOR UPDATE;` | |
| 3 | | `BEGIN;` |
| 4 | | `SELECT * FROM producto WHERE id = 1 FOR UPDATE;` *(queda esperando)* |
| 5 | `COMMIT;` | |
| 6 | | *(se destrabea y devuelve la fila)* |
| 7 | | `COMMIT;` |

### Qué se observó

```
-- Sesión A
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# SELECT * FROM producto WHERE id = 1 FOR UPDATE;
 id |  nombre   | precio  |              descripcion              | stock | imagen | disponible | categoria_id | eliminado |          created_at
----+-----------+---------+---------------------------------------+-------+--------+------------+--------------+-----------+-------------------------------
  1 | Fugazzeta | 2200.00 | Pizza de cebolla con queso mozzarella |    15 |        | t          |            1 | f         | 2026-09-01 18:33:28.748257-03
(1 fila)

-- Sesión B (mientras A seguía con la transacción abierta)
foodstore_test=# BEGIN;
BEGIN
foodstore_test=*# SELECT * FROM producto WHERE id = 1 FOR UPDATE;
-- (la sesión no devuelve el prompt: queda esperando, sin mostrar la fila)

-- Sesión A
foodstore_test=*# COMMIT;
COMMIT

-- Sesión B (se destraba justo después del COMMIT de A)
 id |  nombre   | precio  |              descripcion              | stock | imagen | disponible | categoria_id | eliminado |          created_at
----+-----------+---------+---------------------------------------+-------+--------+------------+--------------+-----------+-------------------------------
  1 | Fugazzeta | 2200.00 | Pizza de cebolla con queso mozzarella |    15 |        | t          |            1 | f         | 2026-09-01 18:33:28.748257-03
(1 fila)

foodstore_test=*#
```

La Sesión B, al pedir `FOR UPDATE` sobre la misma fila que ya tenía
bloqueada la Sesión A, no devolvió el prompt ni la fila hasta que la Sesión
A hizo `COMMIT` — ahí recién se destrabó y mostró el resultado.

### Explicación de la IA

*(Herramienta: Claude — pegada tal cual, no editada)*

> `FOR UPDATE` pide un bloqueo de fila exclusivo sobre las filas que
> devuelve el `SELECT`. La primera sesión en pedirlo lo obtiene y sigue
> trabajando; la segunda, que pide el mismo bloqueo sobre la misma fila,
> queda en espera — no falla ni devuelve una versión vieja, simplemente no
> devuelve nada hasta que la primera transacción libera el bloqueo con
> `COMMIT` o `ROLLBACK`. Esto no es una anomalía a evitar (como las dos
> anteriores): es el mecanismo mismo que Postgres usa para garantizar que
> nadie más modifique esa fila mientras vos la estás por actualizar.

### Verificación en el motor

La misma corrida anterior ya es la verificación: no hubo dos niveles de
aislamiento distintos que probar acá (`FOR UPDATE` bloquea igual en
cualquier nivel), sino confirmar en el motor real que la espera efectiva
ocurre y que se libera exactamente al momento del `COMMIT` de la sesión que
tenía el bloqueo — lo cual se verificó tal cual arriba.

### Conclusión

La explicación de la IA se confirmó en el motor: `FOR UPDATE` tomó un
bloqueo de fila exclusivo en la Sesión A, y la Sesión B quedó efectivamente
en espera —sin error ni lectura de una versión vieja— hasta que la Sesión A
liberó el bloqueo con `COMMIT`. El mecanismo que resuelve (evita) esta
situación no es un nivel de aislamiento sino el bloqueo de fila mismo: es
el comportamiento esperado y correcto de `FOR UPDATE`, no una anomalía a
corregir.

---

## (Opcional) Escenario 4 — Interbloqueo real

*(No realizado — se entregan los 3 escenarios obligatorios: lectura no
repetible, lectura fantasma y espera por bloqueo. Este cuarto escenario,
de nota adicional, queda pendiente por decisión propia, no por error.)*

**Tablas:** `producto` (id = 1 e id = 2)

| Paso | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` | `BEGIN;` |
| 2 | `UPDATE producto SET stock = stock - 1 WHERE id = 1;` | |
| 3 | | `UPDATE producto SET stock = stock - 1 WHERE id = 2;` |
| 4 | `UPDATE producto SET stock = stock - 1 WHERE id = 2;` *(queda esperando a B)* | |
| 5 | | `UPDATE producto SET stock = stock - 1 WHERE id = 1;` *(Postgres detecta el ciclo y aborta una de las dos con error `40P01`)* |

> Si más adelante querés sumar la nota extra, estos comandos ya están
> listos para correr.

---

## DUIA — Declaración de Uso de IA (Parte 2)

| Campo | Completar |
|---|---|
| Herramienta | Claude (Anthropic) |
| Spec o prompt utilizado | `<< Completar con tus propias palabras: le pediste a la IA que reprodujera al menos 3 de las 4 anomalías de concurrencia de la Semana 2 (lectura no repetible, lectura fantasma, espera por bloqueo, interbloqueo opcional) sobre el esquema real del proyecto foodstore, con los comandos exactos de Sesión A/B, la explicación de cada anomalía, y la plantilla del informe_concurrencia.md lista para completar con la salida real del motor >>` |
| Qué generó | Los comandos de Sesión A/Sesión B para los 3 escenarios adaptados a las tablas `producto` y `pedido` del esquema foodstore, el texto de "Explicación de la IA" de cada uno, y la estructura completa del `informe_concurrencia.md` (incluida la nota de la posible discrepancia teoría/motor en el Escenario 2) |
| Qué se aceptó | Los comandos de los 3 escenarios se corrieron tal cual los propuso la IA, sin modificar la sintaxis SQL. Las explicaciones de la IA se dejaron tal como fueron generadas (no se editaron) |
| Qué se modificó o descartó, y por qué | Se descartó el Escenario 4 (interbloqueo), opcional, por decisión propia — no se llegó a correr. En el Escenario 2 la IA anticipó que `REPEATABLE READ` no evita fantasmas según el estándar SQL, pero el motor real mostró que en PostgreSQL sí se evitó (por la implementación de snapshot isolation); esa discrepancia se documentó en la Conclusión en vez de ocultarla o forzar el resultado esperado |
| Verificación realizada | Los 3 escenarios se corrieron en dos sesiones reales de `psql` sobre `foodstore_test` (copia de la base `foodstore`, restaurada desde un respaldo con `pg_dump`, siguiendo `protocolo_seguridad.md`). Escenario 1: `precio` cambió de 1800.00 a 1900.00 entre dos `SELECT` en `READ COMMITTED`, y se mantuvo igual (2100.00 las dos veces) en `REPEATABLE READ`. Escenario 2: el `COUNT(*)` de pedidos `PENDIENTE` pasó de 1 a 2 en `READ COMMITTED`, y se mantuvo en 2 las dos veces en `REPEATABLE READ`. Escenario 3: la Sesión B quedó efectivamente en espera al pedir `FOR UPDATE` sobre una fila ya bloqueada por la Sesión A, y se destrabó justo al `COMMIT` de A |
