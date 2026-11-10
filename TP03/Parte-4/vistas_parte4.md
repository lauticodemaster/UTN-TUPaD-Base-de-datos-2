# TP3 — Parte 4: Vistas para los reportes del sistema

> Base: `foodstore_test`, la misma poblada en la Parte 1 (50.012 productos,
> 20.005 usuarios, 200.005 pedidos, 600.008+ detalles). Todo corre con
> `SET search_path TO foodstore;`.

## Punto de partida: qué había y qué faltaba

Antes de escribir nada revisamos `objects.sql`, y resulta que tres de las
vistas que pide la consigna ya estaban creadas de la semana anterior:

| Vista | ¿Existía? | Qué cubre de la consigna |
|---|---|---|
| `v_productos_vigentes` | Sí | Productos vigentes con su categoría |
| `v_pedidos_resumen` | Sí | Pedidos con los datos del usuario |
| `v_pedido_detalle` | Sí | Detalle de un pedido con el nombre del producto |
| `v_usuarios_publico` | **No** | Usuario sin la columna `contrasena` (punto 4) |

Así que el trabajo de esta parte no fue "crear cuatro vistas de cero", sino:

1. escribir la especificación de cada una (lo que no estaba documentado),
2. **verificar la equivalencia** de las tres existentes contra una consulta
   manual, que es lo que la consigna pide y nunca se había hecho,
3. **crear la vista que faltaba**, la de seguridad sobre `usuario`,
4. dejar registrada una decisión de diseño que apareció al revisar el filtro
   de vigencia (ver "Decisión sobre el filtro `eliminado`" más abajo).

---

## 1. Especificaciones (specs)

### spec: vista_productos_vigentes

```
# spec: vista_productos_vigentes
Objetivo: catálogo de productos a la venta, con el nombre de la categoría
          ya resuelto, para no repetir el JOIN en cada pantalla.
Columnas a exponer: id, nombre, precio, stock, categoria (nombre)
Filtro de vigencia: producto.eliminado = FALSE Y categoria.eliminado = FALSE
Columna oculta por seguridad: ninguna
Criterio de aceptación: el resultado coincide exactamente con la consulta
                        manual equivalente (0 filas de diferencia simétrica
                        y mismo COUNT).
```

### spec: vista_pedidos_resumen

```
# spec: vista_pedidos_resumen
Objetivo: listado de pedidos con el nombre del usuario ya armado, para el
          panel de administración.
Columnas a exponer: id, usuario (nombre || ' ' || apellido), fecha, estado,
                    forma_pago, total
Filtro de vigencia: pedido.eliminado = FALSE
Columna oculta por seguridad: usuario.contrasena, usuario.mail y
                    usuario.celular no se exponen (solo el nombre visible)
Criterio de aceptación: coincide con la consulta manual equivalente.
```

### spec: vista_pedido_detalle

```
# spec: vista_pedido_detalle
Objetivo: renglones de un pedido con el nombre del producto resuelto, para
          la vista de detalle y para el comprobante.
Columnas a exponer: pedido_id, producto (nombre), cantidad, precio_unitario,
                    subtotal
Filtro de vigencia: detalle_pedido.eliminado = FALSE
Columna oculta por seguridad: ninguna
Criterio de aceptación: coincide con la consulta manual equivalente y la
                        suma de subtotales por pedido sigue dando el mismo
                        total que pedido.total.
```

### spec: vista_usuarios_publico (la que faltaba)

```
# spec: vista_usuarios_publico
Objetivo: poder dar SELECT sobre los usuarios a un rol de solo lectura sin
          darle acceso a la tabla usuario, donde vive el hash de contraseña.
Columnas a exponer: id, nombre, apellido, mail, celular, rol, created_at
Filtro de vigencia: usuario.eliminado = FALSE
Columna oculta por seguridad: contrasena  <-- el punto del ejercicio
Criterio de aceptación: un rol con SELECT solo sobre la vista puede leerla,
                        y recibe "permission denied" al intentar leer la
                        tabla usuario.
```

---

## 2. SQL

### 2.1 Las tres vistas que ya existían

Se dejan tal cual están en `objects.sql`. Se transcriben acá para que la
Parte 4 se pueda leer sola, pero **no se vuelven a ejecutar** (ya están
creadas en la base):

```sql
SET search_path TO foodstore;

CREATE VIEW v_productos_vigentes AS
SELECT p.id, p.nombre, p.precio, p.stock,
       c.nombre AS categoria
FROM   producto p
JOIN   categoria c ON c.id = p.categoria_id
WHERE  p.eliminado = FALSE AND c.eliminado = FALSE;

CREATE VIEW v_pedidos_resumen AS
SELECT  ped.id,
        u.nombre || ' ' || u.apellido AS usuario,
        ped.fecha, ped.estado, ped.forma_pago, ped.total
FROM    pedido ped
JOIN    usuario u ON u.id = ped.usuario_id
WHERE   ped.eliminado = FALSE;

CREATE VIEW v_pedido_detalle AS
SELECT  dp.pedido_id,
        pr.nombre AS producto,
        dp.cantidad, dp.precio_unitario, dp.subtotal
FROM    detalle_pedido dp
JOIN    producto pr ON pr.id = dp.producto_id
WHERE   dp.eliminado = FALSE;
```

### 2.2 La vista nueva: `v_usuarios_publico`

```sql
SET search_path TO foodstore;

-- Expone usuario sin la columna contrasena.
-- Las columnas se listan una por una a propósito. Con un SELECT * acá,
-- cualquier columna que se agregue a la tabla más adelante quedaría
-- expuesta sola, sin que nadie lo revise.
CREATE VIEW v_usuarios_publico AS
SELECT u.id,
       u.nombre,
       u.apellido,
       u.mail,
       u.celular,
       u.rol,
       u.created_at
FROM   usuario u
WHERE  u.eliminado = FALSE;
```

Y el rol de solo lectura con el que se prueba que sirve:

```sql
-- CREATE ROLE no admite IF NOT EXISTS, así que se pregunta antes.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_lectura') THEN
        CREATE ROLE app_lectura NOLOGIN;
    END IF;
END $$;

GRANT USAGE  ON SCHEMA foodstore        TO app_lectura;
GRANT SELECT ON v_usuarios_publico      TO app_lectura;
-- Ojo: NO se otorga nada sobre la tabla usuario. Ese es el punto.
```

**Por qué funciona:** en PostgreSQL una vista se ejecuta con los permisos de
**su dueño**, no con los de quien la consulta. Por eso `app_lectura` puede
leer `v_usuarios_publico` aunque no tenga ningún permiso sobre `usuario`: el
motor entra a la tabla base en nombre del dueño de la vista. Lo único que
`app_lectura` llega a ver son las siete columnas que la vista expone.

---

## 3. Verificación de equivalencia

La consigna pide comprobar que cada vista devuelve **exactamente** lo mismo
que la consulta escrita a mano. Usamos dos controles por vista, porque uno
solo no alcanza:

- **Diferencia simétrica** con `EXCEPT` en los dos sentidos. Si da 0 filas,
  ningún lado tiene una fila que el otro no tenga.
- **Comparación de `COUNT(*)`**. Esto hace falta porque `EXCEPT` elimina
  duplicados: si la vista repitiera una fila y la consulta manual no, la
  diferencia simétrica daría 0 igual y no nos enteraríamos. El COUNT sí lo
  detecta.

### 3.1 `v_productos_vigentes`

```sql
-- (a) diferencia simétrica: debe dar 0 filas
(
  SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes
  EXCEPT
  SELECT p.id, p.nombre, p.precio, p.stock, c.nombre
  FROM   producto p JOIN categoria c ON c.id = p.categoria_id
  WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
)
UNION ALL
(
  SELECT p.id, p.nombre, p.precio, p.stock, c.nombre
  FROM   producto p JOIN categoria c ON c.id = p.categoria_id
  WHERE  p.eliminado = FALSE AND c.eliminado = FALSE
  EXCEPT
  SELECT id, nombre, precio, stock, categoria FROM v_productos_vigentes
);

-- (b) mismo número de filas: debe dar TRUE
SELECT (SELECT COUNT(*) FROM v_productos_vigentes)
     = (SELECT COUNT(*)
        FROM   producto p JOIN categoria c ON c.id = p.categoria_id
        WHERE  p.eliminado = FALSE AND c.eliminado = FALSE) AS coinciden;
```

Resultado obtenido:

```
[pendiente: pegar salida de (a) y (b)]
```

### 3.2 `v_pedidos_resumen`

```sql
-- (a) diferencia simétrica: debe dar 0 filas
(
  SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen
  EXCEPT
  SELECT ped.id, u.nombre || ' ' || u.apellido, ped.fecha, ped.estado,
         ped.forma_pago, ped.total
  FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
  WHERE  ped.eliminado = FALSE
)
UNION ALL
(
  SELECT ped.id, u.nombre || ' ' || u.apellido, ped.fecha, ped.estado,
         ped.forma_pago, ped.total
  FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
  WHERE  ped.eliminado = FALSE
  EXCEPT
  SELECT id, usuario, fecha, estado, forma_pago, total FROM v_pedidos_resumen
);

-- (b) mismo número de filas: debe dar TRUE
SELECT (SELECT COUNT(*) FROM v_pedidos_resumen)
     = (SELECT COUNT(*)
        FROM   pedido ped JOIN usuario u ON u.id = ped.usuario_id
        WHERE  ped.eliminado = FALSE) AS coinciden;
```

Resultado obtenido:

```
[pendiente: pegar salida de (a) y (b)]
```

### 3.3 `v_pedido_detalle`

```sql
-- (a) diferencia simétrica: debe dar 0 filas
(
  SELECT pedido_id, producto, cantidad, precio_unitario, subtotal
  FROM   v_pedido_detalle
  EXCEPT
  SELECT dp.pedido_id, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal
  FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
  WHERE  dp.eliminado = FALSE
)
UNION ALL
(
  SELECT dp.pedido_id, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal
  FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
  WHERE  dp.eliminado = FALSE
  EXCEPT
  SELECT pedido_id, producto, cantidad, precio_unitario, subtotal
  FROM   v_pedido_detalle
);

-- (b) mismo número de filas: debe dar TRUE
SELECT (SELECT COUNT(*) FROM v_pedido_detalle)
     = (SELECT COUNT(*)
        FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
        WHERE  dp.eliminado = FALSE) AS coinciden;

-- (c) control extra propio: la suma de subtotales de la vista tiene que
--     seguir dando el mismo total que guarda pedido.total.
--     Si esto fallara, la vista estaría escondiendo renglones.
SELECT COUNT(*) AS pedidos_descuadrados
FROM   pedido ped
JOIN   LATERAL (
         SELECT COALESCE(SUM(v.subtotal), 0) AS suma
         FROM   v_pedido_detalle v
         WHERE  v.pedido_id = ped.id
       ) s ON TRUE
WHERE  ped.eliminado = FALSE
  AND  s.suma <> ped.total;
```

Resultado obtenido:

```
[pendiente: pegar salida de (a), (b) y (c)]
```

### 3.4 `v_usuarios_publico` — equivalencia y prueba de seguridad

```sql
-- (a) equivalencia contra la consulta manual: debe dar 0 filas
(
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   v_usuarios_publico
  EXCEPT
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   usuario WHERE eliminado = FALSE
)
UNION ALL
(
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   usuario WHERE eliminado = FALSE
  EXCEPT
  SELECT id, nombre, apellido, mail, celular, rol, created_at
  FROM   v_usuarios_publico
);

-- (b) la vista NO expone contrasena: esta consulta tiene que fallar
--     con ERROR: column "contrasena" does not exist
SELECT contrasena FROM v_usuarios_publico LIMIT 1;

-- (c) prueba del permiso. Requiere ser superusuario (o miembro del rol)
--     para poder hacer SET ROLE.
SET ROLE app_lectura;
SELECT id, nombre, apellido FROM v_usuarios_publico LIMIT 3;  -- debe andar
SELECT id, nombre FROM usuario LIMIT 3;   -- debe dar permission denied
RESET ROLE;
```

Resultado obtenido:

```
[pendiente: pegar salida de (a), (b) y (c)]
```

---

## 4. Decisión sobre el filtro `eliminado`

Escribiendo las specs apareció una inconsistencia que conviene dejar
anotada, porque de entrada parece un error de las vistas:

- `v_productos_vigentes` filtra **las dos** tablas
  (`producto.eliminado = FALSE AND categoria.eliminado = FALSE`).
- `v_pedidos_resumen` filtra solo `pedido.eliminado`, **no** `usuario.eliminado`.
- `v_pedido_detalle` filtra solo `detalle_pedido.eliminado`, **no**
  `producto.eliminado`.

Lo primero que pensamos fue que faltaban dos filtros y había que agregarlos.
Mirándolo mejor, es al revés: **está bien como está, y agregarlos rompería
los reportes.**

El motivo es que las tres vistas no son la misma clase de vista:

- `v_productos_vigentes` es un **catálogo**: muestra qué se puede vender hoy.
  Un producto de una categoría dada de baja no se puede vender, así que
  corresponde que desaparezca.
- `v_pedidos_resumen` y `v_pedido_detalle` son **históricos**: muestran lo que
  ya pasó. Si filtráramos por `producto.eliminado = FALSE`, dar de baja un
  producto haría desaparecer renglones de pedidos viejos que ya se cobraron, y
  la suma de subtotales dejaría de coincidir con `pedido.total` — justo lo que
  detecta el control (c) del punto 3.3. Lo mismo con el usuario: dar de baja a
  un cliente no puede borrar su historial de compras.

En resumen: el filtro de vigencia se aplica sobre **la entidad de la que
habla la vista**, no sobre todas las tablas del JOIN. Se decide no tocar las
vistas existentes.

---

## 5. DUIA — Declaración de Uso de IA (Parte 4)

| Campo | Detalle |
|---|---|
| Herramienta | Claude (Anthropic), vía chat, con acceso de lectura a los archivos del proyecto |
| Spec o prompt utilizado | Se le pasó el PDF de la consigna (Parte B), `schema.sql` y `objects.sql`, y se le pidió determinar qué vistas de las pedidas ya existían, escribir las specs faltantes, y generar el SQL de verificación de equivalencia y de la vista de seguridad |
| Qué propuso la IA | Detectó que las tres vistas de reporte ya estaban creadas en `objects.sql` y que la única faltante era la de seguridad sobre `usuario`; generó `v_usuarios_publico` + el rol `app_lectura` con sus GRANT, y los bloques `EXCEPT` de verificación |
| Qué se aceptó | La vista `v_usuarios_publico` con las columnas listadas explícitamente (no `SELECT *`), el rol de solo lectura, y el esquema de verificación con diferencia simétrica **más** comparación de `COUNT(*)`: el `COUNT` se sumó porque `EXCEPT` elimina duplicados y por sí solo no detectaría una fila repetida |
| Qué se modificó o descartó, y por qué | Se **descartó** la propuesta inicial de agregar `usuario.eliminado = FALSE` a `v_pedidos_resumen` y `producto.eliminado = FALSE` a `v_pedido_detalle` "por consistencia". Al analizarlo, ese cambio haría desaparecer renglones de pedidos históricos al dar de baja un producto o un cliente, descuadrando `pedido.total`. Se documentó la decisión en el punto 4 en vez de aplicar el cambio |
| Verificación realizada | [pendiente: completar con las salidas reales de los puntos 3.1 a 3.4 una vez corridas sobre `foodstore_test`] |
