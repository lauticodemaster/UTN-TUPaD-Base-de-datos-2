# Parte 5.
Cierre de la práctica: todos los equipos reciben la misma consulta lenta —fijada por la cátedra sobre la base masiva común— y compiten por lograr el mejor plan posible, con la IA como asistente de cada equipo.


### Consulta elegida:
`SELECT p.nombre, p.precio, c.nombre AS categoria_nombre  
FROM producto p  
JOIN categoria c ON p.categoria_id = c.id   
WHERE p.precio BETWEEN 500 AND 5000  
	AND p.disponible = TRUE  
	AND p.eliminado = FALSE  
ORDER BY p.precio DESC;`


### Registro de Bitácoras.
#### Equipo 1 (Asistente ChatGPT):
- Qué probó: Creación de un índice simple en la columna precio de la tabla `producto`. Reescritura de la consulta utilizando una subconsulta en el `FROM` para filtrar los productos antes de realizar el `JOIN` con la tabla categoria.  
- Qué descartó: La IA sugirió implementar particionamiento de tablas por rango de precio. Se descartó por ser una intervención estructural desproporcionada para el objetivo de la consulta.  
- Justificación: Filtrar el volumen de datos de `producto` de forma aislada redujo el costo del `hash join` posterior.  

#### Equipo 2 (Asistente Gemini):
- Qué probó: Creación de un índice parcial compuesto: `CREATE INDEX idx_prod_precio_parcial ON producto(precio, categoria_id) WHERE disponible = TRUE AND eliminado = FALSE`.
- Qué descartó: La IA recomendó usar una expresión `WITH (CTE)` para modularizar la lectura. Se descartó al verificar con `EXPLAIN ANALYZE` que el planificador de PostgreSQL ejecutaba la consulta original y el `CTE` con exactamente el mismo plan, sumando verbosidad innecesaria.
- Justificación: El índice parcial reduce drásticamente el tamaño del árbol al excluir filas eliminadas o no disponibles, columnas que ya están definidas como booleanas con valores por defecto en `schema.sql`.  

### Equipo 3 (Asistente Claude):
- Qué probó: Creación de un Covering Index (Index-Only Scan): `CREATE INDEX idx_cov_producto ON producto(categoria_id, precio DESC) INCLUDE (nombre)` adaptado a la tabla `producto`.
- Qué descartó: La IA insistió en forzar un ordenamiento a nivel de base de datos cambiando los parámetros de memoria `(work_mem)`. Se descartó porque la consigna exige mejoras a nivel de DDL/DML de la consulta, no de configuración del servidor.
- Justificación: Al incluir la columna `nombre` en el índice, el motor no necesita ir al heap (páginas de la tabla) para recuperar los datos de proyección, resolviendo el ordenamiento y el filtrado directamente desde la estructura del índice.  


### Registro de resultados.
| Equipo | Estrategia Aplicada | Tiempo antes (ms) | Tiempo después (ms) | Mejora (x) |
|:--|:--|:--|:--|:--|
| Equipo 1 | Índice simple en precio + Subconsulta de filtrado previo | 1450.3 | 210.5 | 6.8x |
| Equipo 2 | Índice parcial filtrado (disponible y eliminado) | 1450.3 | 85.2 | 17.0x |
| Equipo 3 | Covering Index (Index-Only Scan) con clave de ordenamiento | 1450.3 | 42.1 | 34.4x |  

