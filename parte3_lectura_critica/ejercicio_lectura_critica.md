# Ejercicio de Lectura Crítica — Parte 3

## Script 1

```sql
-- Generado para: dar de baja las funciones de películas retiradas de cartel
UPDATE funcion
SET activa = FALSE;
```

**Qué haría realmente**

No tiene cláusula `WHERE`. Un `UPDATE` sin `WHERE` afecta **todas las filas
de la tabla**, sin excepción. Este script pondría `activa = FALSE` en cada
fila de `funcion`, incluidas las funciones de películas que siguen en
cartel hoy mismo.

**Por qué no coincide con la consigna**

La consigna pide dar de baja *solo* las funciones retiradas de cartel. El
script generado no distingue "retirada" de "vigente": trata a todas las
filas igual. El nombre del comentario (`-- Generado para: ...`) describe
una intención razonable, pero el código no la implementa — es exactamente
el patrón de los casos de la sección 6.1: sintaxis válida, intención
razonable, efecto real muy distinto al declarado.

**Versión corregida**

Falta el criterio que identifica "retirada de cartel" en tu esquema
(columna de fecha de fin de exhibición, un estado, o similar). Con una
columna típica `fecha_fin`:

```sql
UPDATE funcion
SET activa = FALSE
WHERE fecha_fin < CURRENT_DATE
  AND activa = TRUE;
```

El `AND activa = TRUE` no es obligatorio para la corrección, pero evita
tocar (y disparar triggers de auditoría, si los hubiera) sobre filas que ya
estaban en `FALSE`. Reemplazá `fecha_fin` por el campo real que tu esquema
de cátedra use para marcar que una función terminó su ciclo en cartelera.

---

## Script 2

```sql
-- Generado para: limpiar las categorías sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

**Qué haría realmente**

Depende de un detalle silencioso de SQL: si **una sola fila** de
`producto.categoria_id` es `NULL`, la subconsulta devuelve una lista que
incluye `NULL`. Y `x NOT IN (a, b, NULL)` no evalúa a verdadero ni a falso
para ningún `x` — evalúa a `UNKNOWN`, y una fila con `WHERE` en `UNKNOWN` no
se selecciona nunca. Resultado real: si hay algún producto sin categoría
asignada, este `DELETE` no borra **ninguna** fila de `categoria`, aunque
existan categorías genuinamente sin productos. No tira error, no avisa
nada: simplemente no hace lo que dice que hace.

**Por qué no coincide con la consigna**

La consigna es "limpiar las categorías sin productos asociados". Tal como
está escrito, el script puede terminar sin limpiar nada (efecto: 0 filas)
de forma completamente silenciosa, dando una falsa sensación de que
"ya se ejecutó y no había nada que limpiar" cuando en realidad el bug es el
`NOT IN` con `NULL`, no la ausencia de categorías vacías.

**Versión corregida**

`NOT EXISTS` no tiene el problema de `NULL` porque compara existencia fila
por fila en vez de construir una lista con `IN`/`NOT IN`:

```sql
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1 FROM producto p WHERE p.categoria_id = c.id
);
```

Esto es correcto independientemente de si `producto.categoria_id` admite
`NULL` o no.

**Nota adicional (más allá de lo que pide la consigna):** si tu propio
proyecto sigue la convención de borrado lógico (columna `eliminado`, como
en Food Store), un `DELETE` físico —corregido o no— rompe esa convención.
La versión que respeta el patrón del proyecto sería:

```sql
UPDATE categoria c
SET eliminado = TRUE
WHERE eliminado = FALSE
  AND NOT EXISTS (
      SELECT 1 FROM producto p
      WHERE p.categoria_id = c.id AND p.eliminado = FALSE
  );
```

Esto ademas evita marcar como "sin productos" una categoría cuyos productos
están todos dados de baja lógica pero técnicamente siguen en la tabla.
