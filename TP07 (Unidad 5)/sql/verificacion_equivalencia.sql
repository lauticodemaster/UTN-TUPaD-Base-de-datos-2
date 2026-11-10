-- TP Unidad 5 - Parte D: verificacion de equivalencia de agregados
-- Ambas consultas usan la MISMA expresion de mes y la misma zona horaria de sesion.

-- 1) Sobre usuario_anon
SELECT rol, date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad
FROM usuario_anon
GROUP BY rol, date_trunc('month', created_at)
ORDER BY rol, mes_alta;

-- 2) Sobre usuario (real)  <-- esta es la que le piden a OpenCode
SELECT rol, date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad
FROM usuario
GROUP BY rol, date_trunc('month', created_at)
ORDER BY rol, mes_alta;

-- 3) Prueba de equivalencia: si ambas direcciones devuelven 0 filas, son identicos
SELECT 'solo_en_anon' AS lado, * FROM (
    SELECT rol, date_trunc('month', created_at) AS mes_alta, count(*) AS cantidad
    FROM usuario_anon GROUP BY 2, 1
    EXCEPT
    SELECT rol, date_trunc('month', created_at), count(*)
    FROM usuario GROUP BY 2, 1
) a
UNION ALL
SELECT 'solo_en_real', * FROM (
    SELECT rol, date_trunc('month', created_at), count(*)
    FROM usuario GROUP BY 2, 1
    EXCEPT
    SELECT rol, date_trunc('month', created_at), count(*)
    FROM usuario_anon GROUP BY 2, 1
) b;
