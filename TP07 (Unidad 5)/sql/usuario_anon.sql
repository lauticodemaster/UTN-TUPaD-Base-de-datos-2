-- TP Unidad 5 - Parte D: tabla usuario_anon (datos sinteticos deterministas)
-- Regla: todo dato identificable se reemplaza por un valor derivado del id
-- (sin random(), asi cada corrida da el mismo resultado). Las columnas que
-- usan los agregados (rol, eliminado, created_at) se copian SIN alterar.

DROP TABLE IF EXISTS usuario_anon;

CREATE TABLE usuario_anon AS
SELECT
    u.id,
    'Nombre_'   || u.id                              AS nombre,
    'Apellido_' || u.id                              AS apellido,
    'usuario'   || u.id || '@anon.example'           AS mail,
    -- celular sintetico de 10 digitos, derivado del id
    lpad((u.id % 10000000000)::text, 10, '0')        AS celular,
    -- nunca se copia la contrasena, ni siquiera hasheada
    'HASH_ANONIMIZADO'                               AS contrasena,
    u.rol,
    u.eliminado,
    u.created_at
FROM usuario u;

ALTER TABLE usuario_anon ADD PRIMARY KEY (id);

-- Control rapido: misma cantidad de filas que la tabla real
SELECT (SELECT count(*) FROM usuario)      AS filas_usuario,
       (SELECT count(*) FROM usuario_anon) AS filas_usuario_anon;
