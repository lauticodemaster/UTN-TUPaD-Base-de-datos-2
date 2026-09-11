# Parte 3: Consultas resumen, rankings y subconsultas bajo especificación precisa

Dos consultas, cada una con dos versiones de estructura distinta, verificadas
como equivalentes entre sí con `EXCEPT`.

---

## Consulta (a) — Ranking de usuarios por gasto (función de ventana)

### Spec entregada a la IA

> «Generá una consulta SQL sobre el esquema de Food Store que devuelva, para
> cada usuario vigente (`usuario.eliminado = FALSE`) con al menos un pedido
> vigente (`pedido.eliminado = FALSE`), su nombre completo
> (`nombre || ' ' || apellido`), el total gastado (suma de `pedido.total` en
> sus pedidos no eliminados) y su puesto en un ranking de mayor a menor gasto
> total. En caso de empate, deben compartir el mismo puesto, y el siguiente
> puesto salta los lugares ocupados (semántica de `RANK`, no `ROW_NUMBER`).
> Ordenar por puesto ascendente. No usar `SELECT *`.»

### Versión 1 — función de ventana

```sql
SELECT u.nombre || ' ' || u.apellido AS nombre_completo,
       SUM(ped.total)               AS total_gastado,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM   usuario u
JOIN   pedido  ped ON ped.usuario_id = u.id AND ped.eliminado = FALSE
WHERE  u.eliminado = FALSE
GROUP  BY u.id, u.nombre, u.apellido
ORDER  BY puesto;
```

### Versión 2 — misma pregunta, sin función de ventana (subconsulta correlacionada)

Estructura distinta a propósito: en vez de `RANK()`, el puesto se calcula
contando, para cada usuario, cuántas filas de la agregación tienen un total
estrictamente mayor (+1) — que es exactamente lo que hace `RANK()` por
detrás.

```sql
SELECT t1.nombre_completo,
       t1.total_gastado,
       (SELECT COUNT(*)
        FROM (
            SELECT u2.id AS usuario_id, SUM(ped2.total) AS total_gastado
            FROM   usuario u2
            JOIN   pedido  ped2 ON ped2.usuario_id = u2.id AND ped2.eliminado = FALSE
            WHERE  u2.eliminado = FALSE
            GROUP  BY u2.id
        ) t2
        WHERE t2.total_gastado > t1.total_gastado) + 1 AS puesto
FROM (
    SELECT u.id AS usuario_id,
           u.nombre || ' ' || u.apellido AS nombre_completo,
           SUM(ped.total) AS total_gastado
    FROM   usuario u
    JOIN   pedido  ped ON ped.usuario_id = u.id AND ped.eliminado = FALSE
    WHERE  u.eliminado = FALSE
    GROUP  BY u.id, u.nombre, u.apellido
) t1
ORDER BY puesto;
```

### Verificación de equivalencia

```sql
(  -- v1 EXCEPT v2
  SELECT nombre_completo, total_gastado, puesto FROM ( /* versión 1 completa */ ) v1
)
EXCEPT
(
  SELECT nombre_completo, total_gastado, puesto FROM ( /* versión 2 completa */ ) v2
);
-- y la misma comparación invertida (v2 EXCEPT v1)
-- Ambas deben devolver 0 filas.
```

**Resultado real (verificado sobre `food_store`):** ambas direcciones del
`EXCEPT` (Versión 1 EXCEPT Versión 2, y Versión 2 EXCEPT Versión 1)
devolvieron **0 filas**, confirmando la equivalencia lógica entre la función
de ventana (`RANK()`) y la subconsulta correlacionada basada en conteo.

---

## Consulta (b) — Productos por encima del precio promedio de su categoría (subconsulta correlacionada)

### Spec entregada a la IA

> «Generá una consulta SQL sobre el esquema de Food Store que devuelva, para
> cada producto vigente (`producto.eliminado = FALSE`) cuya categoría también
> esté vigente (`categoria.eliminado = FALSE`), el nombre del producto, el
> nombre de su categoría y su precio, únicamente para los productos cuyo
> precio sea mayor al precio promedio de los productos vigentes de esa misma
> categoría (el promedio se calcula solo con productos no eliminados).
> Ordenar por categoría y luego por precio descendente. No usar `SELECT *`.»

### Versión 1 — subconsulta correlacionada

```sql
SELECT pr.nombre AS producto,
       c.nombre  AS categoria,
       pr.precio
FROM   producto pr
JOIN   categoria c ON c.id = pr.categoria_id AND c.eliminado = FALSE
WHERE  pr.eliminado = FALSE
  AND  pr.precio > (
        SELECT AVG(pr2.precio)
        FROM   producto pr2
        WHERE  pr2.categoria_id = pr.categoria_id
          AND  pr2.eliminado = FALSE
       )
ORDER  BY c.nombre, pr.precio DESC;
```

### Versión 2 — misma pregunta, con join + agregación (sin correlación)

```sql
SELECT pr.nombre AS producto,
       c.nombre  AS categoria,
       pr.precio
FROM   producto pr
JOIN   categoria c ON c.id = pr.categoria_id AND c.eliminado = FALSE
JOIN  (
        SELECT categoria_id, AVG(precio) AS precio_promedio
        FROM   producto
        WHERE  eliminado = FALSE
        GROUP  BY categoria_id
      ) prom ON prom.categoria_id = pr.categoria_id
WHERE  pr.eliminado = FALSE
  AND  pr.precio > prom.precio_promedio
ORDER  BY c.nombre, pr.precio DESC;
```

### Verificación de equivalencia

```sql
( /* versión 1 */ ) EXCEPT ( /* versión 2 */ );
( /* versión 2 */ ) EXCEPT ( /* versión 1 */ );
-- Ambas deben devolver 0 filas.
```

**Resultado real (verificado sobre `food_store`):** ambas direcciones del
`EXCEPT` devolvieron **0 filas**, confirmando la equivalencia lógica entre la
subconsulta correlacionada con `AVG` y el `JOIN` con subagregación
precomputada (respetando el filtro de borrado lógico dentro de la
subconsulta).

**Punto fino a explicar en la defensa:** el promedio de la versión 2 se
calcula en la subconsulta `prom` **filtrando `eliminado = FALSE` antes de
agrupar** — si ese filtro faltara ahí (aunque esté puesto afuera, en el
`WHERE` principal, sobre `pr`), el promedio incluiría productos eliminados de
la categoría y las dos versiones dejarían de ser equivalentes. Es exactamente
el caso que la consigna advierte: "una diferencia en el filtro de borrado
lógico dentro de un JOIN" puede hacer que dos consultas parezcan iguales sin
serlo.

---

## DUIA — Parte 3

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Qué propuso la IA | Se aceptó / se descartó — por qué |
|---|---|---|---|---|
| Claude (Anthropic), vía chat | Generar la consulta (a) — ranking de usuarios por gasto — con función de ventana | Spec de arriba, exigiendo semántica `RANK` (empates comparten puesto, siguiente puesto salta lugares) | `RANK() OVER (ORDER BY SUM(ped.total) DESC)` sobre la agregación por usuario | Se aceptó: es la forma estándar de `RANK` con desempate compartido, sin necesidad de `PARTITION BY` porque el ranking es global |
| Claude (Anthropic), vía chat | Generar una segunda versión de (a) con estructura distinta (subconsulta correlacionada en vez de función de ventana) | Se pidió explícitamente "la misma pregunta sin `RANK()`, usando subconsulta" | Subconsulta correlacionada que cuenta cuántas filas tienen total estrictamente mayor, +1 | Se aceptó tras verificar que replica la semántica de `RANK` (cuenta filas, no valores distintos, para que los empates no salteen puestos de más) |
| Claude (Anthropic), vía chat | Generar la consulta (b) — productos por encima del promedio de su categoría — con subconsulta correlacionada | Spec de arriba, con filtro de borrado lógico explícito en `producto` y en `categoria`, y en el cálculo del promedio | Subconsulta correlacionada `WHERE pr2.categoria_id = pr.categoria_id AND pr2.eliminado = FALSE` dentro del `AVG` | Se aceptó porque el filtro de borrado lógico está aplicado *dentro* de la subconsulta del promedio, no solo afuera — evita el error de "promedio contaminado con productos eliminados" que advierte la consigna |
| Claude (Anthropic), vía chat | Generar una segunda versión de (b) con estructura distinta (join + agregación precomputada en vez de subconsulta correlacionada) | Se pidió "la misma pregunta con join a una subconsulta agregada, no correlacionada" | Subconsulta `prom` agregada por categoría, unida por `categoria_id`, con el mismo filtro de borrado lógico repetido dentro de la agregación | Se aceptó, verificando que el filtro `eliminado = FALSE` se mantuvo dentro de la agregación de `prom` (si se hubiera perdido en la reescritura, habría dejado de ser equivalente a la versión 1) |

**Verificación completada:** los cuatro `EXCEPT` (dos por consulta, en ambos
sentidos) se corrieron sobre la base real `food_store` y los cuatro
devolvieron 0 filas — la Parte 3 queda cerrada con equivalencia confirmada.
