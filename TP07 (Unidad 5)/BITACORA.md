# Bitácora de uso de IA

| Prompt enviado a la IA | Respuesta relevante recibida | Validación o corrección humana aplicada |
|---|---|---|
| **Parte D.** Describí la estructura de `usuario_anon` (sin datos reales) con la consulta de usuarios por rol y mes de alta, y pedí la consulta equivalente sobre `usuario`, con mismas columnas, agrupamiento y orden, sin filtros ni columnas extra y sin ejecutarla. | Devolvió `SELECT rol, date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad FROM usuario GROUP BY rol, date_trunc('month', created_at) ORDER BY rol, mes_alta;` | Comparé columnas, agrupamiento y orden contra la consulta sobre `usuario_anon`: coinciden. Mi prompt tenía un typo (`'mon'`) que la IA resolvió bien. Ejecuté ambas consultas y verifiqué con `EXCEPT` en ambas direcciones que dan 0 filas. |
