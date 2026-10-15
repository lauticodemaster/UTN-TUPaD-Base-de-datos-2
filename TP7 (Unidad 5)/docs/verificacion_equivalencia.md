# Parte D - Protección de datos personales: verificación de equivalencia

## 1. Construcción de `usuario_anon`
Script: `sql/usuario_anon.sql`.

La tabla `usuario_anon` se genera a partir de `usuario` con datos sintéticos
deterministas, derivados del `id` (sin `random()`, por lo que cada ejecución
produce el mismo resultado):

| Columna | Tratamiento |
|---|---|
| `id` | se conserva |
| `nombre`, `apellido` | `Nombre_<id>`, `Apellido_<id>` |
| `mail` | `usuario<id>@anon.example` |
| `celular` | número sintético de 10 dígitos derivado del `id` |
| `contrasena` | valor fijo `HASH_ANONIMIZADO` (nunca se copia, ni hasheada) |
| `rol`, `eliminado`, `created_at` | se copian sin modificar, porque son las columnas que usan los agregados |

## 2. Consulta pedida a OpenCode
Prompt enviado (describe solo la estructura de la tabla, sin datos reales):

> Tengo en PostgreSQL 16 la tabla usuario_anon con estas columnas: id BIGINT,
> nombre, apellido, mail, celular, contrasena (todas VARCHAR), rol (enum rol con
> valores 'ADMIN' y 'USUARIO'), eliminado BOOLEAN, created_at TIMESTAMPTZ. Esta
> consulta cuenta usuarios por rol y por mes de alta: `SELECT rol,
> date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad FROM
> usuario_anon GROUP BY rol, date_trunc('month', created_at) ORDER BY rol,
> mes_alta;` Dame una consulta equivalente sobre la tabla real usuario, que tiene
> las mismas columnas de rol y created_at. Requisitos: mismas columnas de salida,
> mismo agrupamiento, mismo orden, sin filtros ni columnas adicionales. Solo
> escribí la consulta, no la ejecutes contra ninguna base.

Respuesta de OpenCode:

```sql
SELECT rol, date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad
FROM usuario
GROUP BY rol, date_trunc('month', created_at)
ORDER BY rol, mes_alta;
```

Revisión: mismas columnas de salida, mismo agrupamiento y mismo orden que la
consulta sobre `usuario_anon`; no agregó filtros ni columnas extra. El prompt
enviado tenía un error de tipeo en el nombre del período (`'mon'`) que OpenCode
interpretó correctamente como `'month'`.

## 3. Consultas ejecutadas
Ambas están en `sql/verificacion_equivalencia.sql`: la consulta sobre
`usuario_anon`, la generada por OpenCode sobre `usuario`, y una comparación con
`EXCEPT` en ambas direcciones. Las dos consultas usan la misma expresión de mes y
la misma zona horaria de sesión.

## 4. Resultados lado a lado

| rol | mes_alta | cantidad (usuario_anon) | cantidad (usuario) |
|-----|----------|-------------------------|--------------------|
| ADMIN | 2024-01-01 00:00:00+00 | 2 | 2 |
| ADMIN | 2024-02-01 00:00:00+00 | 1 | 1 |
| USUARIO | 2024-01-01 00:00:00+00 | 15 | 15 |
| USUARIO | 2024-02-01 00:00:00+00 | 8 | 8 |

Comparación con `EXCEPT` en ambas direcciones (`solo_en_anon` / `solo_en_real`):
**0 filas**. Los agregados de `usuario_anon` y `usuario` son idénticos: mismos
agrupamientos y mismos conteos.

## 5. Información que no debe salir hacia un asistente de IA sin anonimizar
Ningún dato personal de los usuarios de Food Store debería llegar a un asistente
de IA sin anonimizar: nombre, apellido, mail y celular, ni sus contraseñas o
hashes. Tampoco los logs, dumps o resultados de consultas que contengan esos
datos, porque lo que se envía a un servicio externo deja de estar bajo nuestro
control. Por eso se reemplazan por valores sintéticos y se conservan solo las
columnas necesarias para el análisis, como el rol y la fecha de alta.
