# spec: vistas_reportes

Objetivo: dejar los tres reportes habituales de Food Store detras de una
          vista cada uno, para no repetir el JOIN y el filtro de vigencia
          en cada pantalla, y agregar una cuarta vista que permita dar
          acceso de lectura a usuario sin exponer el hash de contrasena.

Punto de partida: en objects.sql (Semana 2) ya existen v_productos_vigentes,
          v_pedidos_resumen y v_pedido_detalle. La especificacion las cubre
          igual, porque hasta ahora nunca se verifico que devuelvan
          exactamente lo mismo que la consulta escrita a mano — que es lo
          que pide el punto 3 de la Parte B. La cuarta no existe.

---

## vista 1: v_productos_vigentes

Columnas a exponer: id, nombre, precio, stock, categoria (nombre)
Filtro de vigencia: producto.eliminado = FALSE AND categoria.eliminado = FALSE
Columna oculta por seguridad: ninguna
Criterio de aceptacion: la diferencia simetrica (EXCEPT en los dos
          sentidos) contra la consulta manual da 0 filas, Y el COUNT(*)
          coincide.

## vista 2: v_pedidos_resumen

Columnas a exponer: id, usuario (nombre || ' ' || apellido), fecha,
          estado, forma_pago, total
Filtro de vigencia: pedido.eliminado = FALSE
          (NO se filtra usuario.eliminado: ver "Decision sobre el filtro
          de vigencia" mas abajo)
Columnas ocultas por seguridad: de usuario solo sale el nombre; mail,
          celular y contrasena no se exponen
Criterio de aceptacion: idem vista 1.

## vista 3: v_pedido_detalle

Columnas a exponer: pedido_id, producto (nombre), cantidad,
          precio_unitario, subtotal
Filtro de vigencia: detalle_pedido.eliminado = FALSE
          (NO se filtra producto.eliminado)
Columna oculta por seguridad: ninguna
Criterio de aceptacion: idem vista 1, mas un control propio: la suma de
          subtotales por pedido sigue coincidiendo con pedido.total para
          todos los pedidos vigentes (0 pedidos descuadrados).

## vista 4: v_usuarios_publico  (la que falta — punto 4 de la Parte B)

Objetivo: poder otorgar SELECT sobre los usuarios a un rol de solo
          lectura sin darle ningun permiso sobre la tabla usuario, donde
          vive el hash de contrasena.
Columnas a exponer: id, nombre, apellido, mail, celular, rol, created_at
Filtro de vigencia: usuario.eliminado = FALSE
Columna oculta por seguridad: contrasena  <-- el punto del ejercicio
Requisito de escritura: las columnas se listan una por una. Con SELECT *
          cualquier columna que se agregue a la tabla mas adelante
          quedaria expuesta sola, sin que nadie lo revise.
Criterio de aceptacion:
  1. Equivalencia contra la consulta manual (EXCEPT + COUNT).
  2. SELECT contrasena FROM v_usuarios_publico falla con
     "column ... does not exist".
  3. Un rol app_lectura con GRANT SELECT solo sobre la vista puede
     leerla, y recibe "permission denied" al leer la tabla usuario.

---

## Decision sobre el filtro de vigencia (se especifica a proposito)

El filtro de vigencia se aplica sobre la entidad de la que habla la
vista, no sobre todas las tablas del JOIN:

- v_productos_vigentes es un catalogo — dice que se puede vender hoy —
  asi que un producto de una categoria dada de baja debe desaparecer.
- v_pedidos_resumen y v_pedido_detalle son historicos — dicen que paso.
  Filtrar producto.eliminado o usuario.eliminado ahi haria desaparecer
  renglones de pedidos ya cobrados y descuadraria pedido.total.

Cualquier propuesta que agregue esos filtros "por consistencia" se
rechaza, y el control de descuadre de la vista 3 es la prueba.
