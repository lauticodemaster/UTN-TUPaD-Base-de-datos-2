# spec: mv_facturacion_categoria_mes

Objetivo: materializar el reporte agregado mas caro del sistema,
          "Facturacion por categoria y por mes" (queries.sql, seccion
          "Consultas analiticas", punto B), que hoy recorre las cuatro
          tablas del dominio para devolver 29 filas.

Consulta a materializar:
  SELECT c.nombre AS categoria,
         date_trunc('month', ped.fecha)::DATE AS mes,
         SUM(dp.subtotal) AS facturado
  FROM   detalle_pedido dp
  JOIN   pedido   ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
  JOIN   producto pr  ON pr.id  = dp.producto_id
  JOIN   categoria c  ON c.id   = pr.categoria_id
  WHERE  dp.eliminado = FALSE AND c.eliminado = FALSE
  GROUP  BY c.nombre, date_trunc('month', ped.fecha)
  ORDER  BY mes DESC, facturado DESC;

Frecuencia de lectura estimada: alta. Es el tablero que mira la gerencia;
          se abre varias veces por dia y ademas lo levanta la pantalla de
          inicio del backoffice.
Frecuencia de cambio del dato de origen: los pedidos de meses cerrados no
          cambian; solo se mueve el mes en curso.

Estado actual medido: 266-270 ms, con Seq Scan sobre detalle_pedido
          (800.008 filas), pedido (200.003) y producto (50.012), para
          devolver 29 filas. Relacion de trabajo a resultado pesima: es
          el caso de libro para materializar.

Requisitos:
  1. CREATE MATERIALIZED VIEW ... WITH DATA.
  2. Indice UNICO sobre (categoria, mes). Sin un indice unico,
     REFRESH MATERIALIZED VIEW CONCURRENTLY no esta permitido: PostgreSQL
     lo necesita para identificar cada fila y aplicar el delta sin tomar
     un lock exclusivo. Se crea ahora aunque el refresh de hoy sea
     bloqueante, para no tener que recrear la vista mas adelante.
  3. El ORDER BY NO va dentro de la vista materializada: el orden se
     pide al consultarla. Una vista materializada es un conjunto de
     filas almacenado, y ordenarla al crearla no garantiza nada sobre el
     orden en que se lean despues.

Criterio de aceptacion:
  1. SELECT sobre la vista materializada devuelve exactamente las mismas
     filas que la consulta original (EXCEPT en los dos sentidos = 0 y
     mismo COUNT).
  2. El tiempo de consulta baja al menos un orden de magnitud.
  3. Queda medido tambien el costo del REFRESH, porque es lo que decide
     si la vista materializada conviene o no.
  4. Queda documentada la frecuencia de refresco propuesta y que implica
     para el usuario que el dato no este al segundo.
