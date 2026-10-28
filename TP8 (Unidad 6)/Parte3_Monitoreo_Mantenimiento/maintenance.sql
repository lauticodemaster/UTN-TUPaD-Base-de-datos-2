-- maintenance.sql — PostgreSQL 16+
-- Ejecutar: psql -h localhost -U postgres -d foodstore -f maintenance.sql
-- No usa VACUUM FULL (bloqueo exclusivo + reescritura de tabla; no es mantenimiento periodico).

SET search_path TO foodstore;  -- las tablas viven en el esquema foodstore (TP1)

\echo '== 1. Autovacuum activo y umbrales =='
SELECT name, setting FROM pg_settings
WHERE name IN ('autovacuum', 'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_threshold', 'autovacuum_analyze_scale_factor');

\echo '== 2. Revision previa: proporcion de tuplas muertas y estadisticas =='
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS pct_muertas,
       n_mod_since_analyze,
       last_autovacuum, last_vacuum, last_autoanalyze, last_analyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, n_mod_since_analyze DESC;

\echo '== 3. Tablas candidatas a ANALYZE (con cambios y sin estadisticas de las ultimas 24 h) =='
SELECT relname, n_mod_since_analyze
FROM pg_stat_user_tables
WHERE n_mod_since_analyze > 0
  AND coalesce(greatest(last_analyze, last_autoanalyze), '-infinity') < now() - interval '1 day'
ORDER BY n_mod_since_analyze DESC;

-- 4. Accion segura y justificada: ANALYZE.
-- Solo recolecta estadisticas para el planificador; toma un lock liviano
-- (SHARE UPDATE EXCLUSIVE) que no bloquea lecturas ni escrituras. Se justifica por la
-- consulta 3: refresca estadisticas de tablas con modificaciones sin analizar. Si la
-- consulta 3 no devolvio filas, la accion es inocua.
\echo '== 4. ANALYZE de tablas del dominio =='
ANALYZE VERBOSE categoria;
ANALYZE VERBOSE producto;
ANALYZE VERBOSE usuario;
ANALYZE VERBOSE pedido;
ANALYZE VERBOSE detalle_pedido;

-- VACUUM (sin FULL) solo si la consulta 2 muestra pct_muertas alto (> ~20 %) en una tabla
-- que autovacuum no atendio; no bloquea DML. Ejemplo, descomentar tras observar:
-- VACUUM (VERBOSE, ANALYZE) detalle_pedido;
