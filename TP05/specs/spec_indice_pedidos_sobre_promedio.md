# spec: indice_pedidos_sobre_promedio

Objetivo: acelerar "Pedidos cuyo total supera el promedio general"
          (queries.sql, seccion "Consultas analiticas", punto D), que hoy
          recorre pedido dos veces y ordena en disco.

Consulta afectada:
  SELECT id, total
  FROM   pedido
  WHERE  eliminado = FALSE
    AND  total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
  ORDER  BY total DESC;

Frecuencia estimada: media-alta. Es el listado de "pedidos grandes" que
          usa el equipo de atencion al cliente para priorizar; se abre
          varias veces por dia.

Columnas que participan:
  - filtro:   pedido.eliminado (condicion parcial)
              pedido.total > :promedio  -> rango, indexable
  - ORDER BY: pedido.total DESC  -> indexable, y es lo que hoy cuesta
  - proyeccion: pedido.id, pedido.total

Volumen actual: pedido 200.003 filas, ~3.930 paginas de heap. El filtro
          devuelve 99.747 filas (~50%): NO es selectivo. Se deja escrito
          a proposito, porque un indice solo por selectividad aca no se
          justificaria; lo que se busca es otra cosa.

Estado actual medido: Seq Scan on pedido dos veces (una en el InitPlan
          del AVG, otra en la consulta) y despues
          "Sort Method: external merge  Disk: 2640kB" — ordena 99.747
          filas contra disco porque no entran en work_mem.

Criterio de aceptacion:
  1. Desaparece el nodo Sort: las filas tienen que salir ya ordenadas
     del indice (el ORDER BY total DESC se resuelve leyendo el indice al
     reves). Esto es lo que se compra, no la selectividad del filtro.
  2. Desaparece el "external merge ... Disk".
  3. El AVG del InitPlan tambien se resuelve por Index Only Scan.
  4. El tiempo mejora de forma reproducible sobre la mediana de 3
     corridas en caliente.
  5. El resultado es identico al original, incluido el orden.

Restricciones:
  - No se sube work_mem.
  - No se modifica el modelo ni la consulta.
