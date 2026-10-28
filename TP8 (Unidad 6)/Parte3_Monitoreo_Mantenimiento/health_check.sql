-- health_check.sql — PostgreSQL 16+
-- Ejecutar: psql -h localhost -U postgres -d foodstore -f health_check.sql

\echo '== 1. Tamano de la base =='
SELECT pg_size_pretty(pg_database_size('foodstore')) AS tamano;

\echo '== 2. Actividad de conexiones =='
SELECT numbackends, xact_commit, xact_rollback
FROM pg_stat_database
WHERE datname = 'foodstore';

\echo '== 3. Estado de tablas (tuplas vivas/muertas, autovacuum/autoanalyze) =='
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

\echo '== 4. Consultas activas (excluye esta sesion) =='
SELECT pid, state, now() - query_start AS duracion, query
FROM pg_stat_activity
WHERE datname = 'foodstore' AND state <> 'idle' AND pid <> pg_backend_pid();
