# spec: indice_ranking_usuarios

Objetivo: acelerar el "Ranking de usuarios por gasto acumulado"
          (queries.sql, seccion "Consultas analiticas", punto C), que hoy
          recorre entera pedido y ademas derrama la agregacion a disco.

Consulta afectada:
  SELECT u.id, u.nombre || ' ' || u.apellido AS usuario,
         SUM(ped.total) AS gasto,
         RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
  FROM   pedido ped
  JOIN   usuario u ON u.id = ped.usuario_id
  WHERE  ped.eliminado = FALSE AND u.eliminado = FALSE
  GROUP  BY u.id, u.nombre, u.apellido
  ORDER  BY puesto;

Frecuencia estimada: media. Es el reporte de marketing; se corre a mano
          varias veces por semana y entero (no filtra por usuario), asi
          que no hay selectividad que aprovechar.

Columnas que participan:
  - filtro:   pedido.eliminado (condicion parcial, no columna indexada)
  - JOIN:     pedido.usuario_id = usuario.id
  - GROUP BY: usuario.id  -> el orden por pedido.usuario_id sirve
  - agregado: pedido.total

Volumen actual: pedido 200.003 filas, ~3.930 paginas de heap;
          usuario 20.005 filas.

Estado actual medido: Seq Scan on pedido + Hash Join, y despues
          HashAggregate con "Batches: 5, Disk Usage: 1576kB" — es decir,
          la tabla hash no entra en work_mem y se derrama a disco. Ese
          derrame, y no el Seq Scan en si, es el costo mas grande.

Indice ya existente a tener en cuenta: idx_pedido_usuario_id sobre
          pedido(usuario_id), sin condicion parcial y sin columnas
          incluidas. Cualquier propuesta nueva tiene que justificar por
          que no es redundante con ese.

Criterio de aceptacion:
  1. El plan deja de tener Seq Scan sobre pedido.
  2. Aparece Index Only Scan con Heap Fetches: 0.
  3. La agregacion deja de derramar a disco (GroupAggregate, o
     HashAggregate con Batches: 1) — este es el punto principal.
  4. El tiempo mejora de forma reproducible sobre la mediana de 3
     corridas en caliente.
  5. El ranking resultante es identico al original (mismo orden y
     mismos puestos).

Restricciones:
  - No se sube work_mem para resolverlo: eso maquilla el sintoma y lo
    paga cualquier otra consulta concurrente.
  - No se modifica el modelo ni la consulta.
