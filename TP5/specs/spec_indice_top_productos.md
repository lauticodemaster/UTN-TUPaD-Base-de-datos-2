# spec: indice_top_productos

Objetivo: acelerar el reporte "Top 5 productos mas vendidos" (queries.sql,
          seccion "Consultas analiticas", punto A), que hoy recorre entera
          detalle_pedido.

Consulta afectada:
  SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
  FROM   detalle_pedido dp
  JOIN   producto pr ON pr.id = dp.producto_id
  WHERE  dp.eliminado = FALSE
  GROUP  BY pr.id, pr.nombre
  ORDER  BY unidades DESC
  LIMIT  5;

Frecuencia estimada: alta. Es el panel de inicio del administrador; se
          consulta cada vez que alguien entra al backoffice (decenas de
          veces por dia) y no esta cacheado en la aplicacion.

Columnas que participan:
  - filtro:   detalle_pedido.eliminado (booleano, ~100% FALSE -> no sirve
              como columna indexada, si como condicion parcial)
  - JOIN:     detalle_pedido.producto_id = producto.id
  - agregado: detalle_pedido.cantidad (se suma, no se filtra)
  - ORDER BY: sobre el agregado, no sobre columnas de tabla -> no es
              indexable

Volumen actual: detalle_pedido 800.008 filas, ~9.100 paginas de heap.

Estado actual medido: Seq Scan on detalle_pedido + Hash Join contra
          producto. No hay ningun filtro selectivo, asi que un indice
          "para filtrar" no aplica: lo unico que puede ganar es leer
          menos bytes que el heap.

Criterio de aceptacion:
  1. El plan deja de tener Seq Scan sobre detalle_pedido.
  2. El nodo que lo reemplaza es Index Only Scan con Heap Fetches: 0
     (si hay Heap Fetches > 0 el indice no esta cubriendo y la propuesta
     no sirve).
  3. Los buffers leidos sobre detalle_pedido bajan al menos a la mitad.
  4. El tiempo de ejecucion mejora de forma reproducible (mediana de 3
     corridas en caliente), no solo en la primera corrida.
  5. El resultado es identico al de la consulta original.

Restricciones:
  - No se modifica el modelo de datos ni la consulta original.
  - Si el planificador no elige el indice con la configuracion por
     defecto, se documenta el hecho en vez de forzar enable_seqscan.
