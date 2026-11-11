-- =============================================================================
-- TP Unidad 4 · Parte 2 — Desnormalización controlada: top 5 categorías del día
-- Entregable: tp_desnormalizacion_top_categorias.sql
--
-- Patrón elegido: TABLA RESUMEN mantenida por DISPARADORES
--   venta_categoria_dia(fecha, categoria_id) -> total_vendido
-- (justificación en ../informe_u4.md §2.b; una vista materializada no sirve
--  porque el panel exige datos en tiempo real y habría que refrescarla varias
--  veces por minuto recorriendo las 4 tablas cada vez).
--
-- Fuente de verdad: detalle_pedido.subtotal (+ pedido.fecha/eliminado y
-- producto.categoria_id). La tabla resumen es SOLO un caché derivado: se puede
-- borrar y reconstruir en cualquier momento sin perder información.
--
-- Uso: psql -d foodstore_test -v ON_ERROR_STOP=1 -f tp_desnormalizacion_top_categorias.sql
-- =============================================================================

SET search_path TO foodstore;

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Estructura desnormalizada
-- -----------------------------------------------------------------------------
CREATE TABLE venta_categoria_dia (
    fecha         DATE          NOT NULL,
    categoria_id  BIGINT        NOT NULL REFERENCES categoria(id),
    total_vendido NUMERIC(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT pk_venta_categoria_dia PRIMARY KEY (fecha, categoria_id)
);

COMMENT ON TABLE venta_categoria_dia IS
  'DESNORMALIZADA (TP U4): suma de detalle_pedido.subtotal vigente por día y categoría. '
  'Mantenida por trg_vcd_*. Auditar con la sección 5 de tp_desnormalizacion_top_categorias.sql.';

-- Carga inicial desde la fuente de verdad (misma semántica que la consulta 5.1)
INSERT INTO venta_categoria_dia (fecha, categoria_id, total_vendido)
SELECT ped.fecha, pr.categoria_id, SUM(dp.subtotal)
FROM   detalle_pedido dp
JOIN   producto pr ON pr.id  = dp.producto_id
JOIN   pedido  ped ON ped.id = dp.pedido_id
WHERE  dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP  BY ped.fecha, pr.categoria_id;

-- Índice para el ORDER BY total DESC dentro de un día
CREATE INDEX idx_vcd_fecha_total ON venta_categoria_dia (fecha, total_vendido DESC);

-- -----------------------------------------------------------------------------
-- 2) Mecanismo de sincronización
-- -----------------------------------------------------------------------------

-- Aplica un delta sobre una celda (fecha, categoría). Upsert: soporta altas
-- concurrentes de la primera venta del día de una categoría.
CREATE OR REPLACE FUNCTION fn_vcd_aplicar(p_fecha DATE, p_categoria BIGINT, p_delta NUMERIC)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO venta_categoria_dia AS v (fecha, categoria_id, total_vendido)
    VALUES (p_fecha, p_categoria, p_delta)
    ON CONFLICT (fecha, categoria_id)
    DO UPDATE SET total_vendido = v.total_vendido + EXCLUDED.total_vendido;
$$;

-- 2.a detalle_pedido: INSERT / UPDATE / DELETE (el DELETE de Food Store es
--     soft-delete, llega como UPDATE de eliminado; igual se cubre el DELETE).
--     AFTER: el subtotal ya fue calculado por trg_subtotal (BEFORE).
CREATE OR REPLACE FUNCTION fn_vcd_detalle()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_fecha DATE; v_ped_elim BOOLEAN; v_cat BIGINT;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') AND NOT OLD.eliminado THEN
        SELECT fecha, eliminado INTO v_fecha, v_ped_elim FROM pedido   WHERE id = OLD.pedido_id;
        SELECT categoria_id    INTO v_cat              FROM producto WHERE id = OLD.producto_id;
        IF NOT v_ped_elim THEN
            PERFORM fn_vcd_aplicar(v_fecha, v_cat, -OLD.subtotal);
        END IF;
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') AND NOT NEW.eliminado THEN
        SELECT fecha, eliminado INTO v_fecha, v_ped_elim FROM pedido   WHERE id = NEW.pedido_id;
        SELECT categoria_id    INTO v_cat              FROM producto WHERE id = NEW.producto_id;
        IF NOT v_ped_elim THEN
            PERFORM fn_vcd_aplicar(v_fecha, v_cat, NEW.subtotal);
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_vcd_detalle
AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_vcd_detalle();

-- 2.b pedido: cambio de fecha o (des)eliminación mueve todo su detalle.
--     No se dispara con el UPDATE de total que hace trg_total_*.
CREATE OR REPLACE FUNCTION fn_vcd_pedido()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT pr.categoria_id, SUM(dp.subtotal) AS s
        FROM   detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id
        WHERE  dp.pedido_id = NEW.id AND dp.eliminado = FALSE
        GROUP  BY pr.categoria_id
    LOOP
        IF NOT OLD.eliminado THEN PERFORM fn_vcd_aplicar(OLD.fecha, r.categoria_id, -r.s); END IF;
        IF NOT NEW.eliminado THEN PERFORM fn_vcd_aplicar(NEW.fecha, r.categoria_id,  r.s); END IF;
    END LOOP;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_vcd_pedido
AFTER UPDATE OF fecha, eliminado ON pedido
FOR EACH ROW
WHEN (OLD.fecha IS DISTINCT FROM NEW.fecha OR OLD.eliminado IS DISTINCT FROM NEW.eliminado)
EXECUTE FUNCTION fn_vcd_pedido();

-- 2.c producto: si cambia de categoría, sus ventas cambian de celda.
CREATE OR REPLACE FUNCTION fn_vcd_producto()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT ped.fecha, SUM(dp.subtotal) AS s
        FROM   detalle_pedido dp JOIN pedido ped ON ped.id = dp.pedido_id
        WHERE  dp.producto_id = NEW.id AND dp.eliminado = FALSE AND ped.eliminado = FALSE
        GROUP  BY ped.fecha
    LOOP
        PERFORM fn_vcd_aplicar(r.fecha, OLD.categoria_id, -r.s);
        PERFORM fn_vcd_aplicar(r.fecha, NEW.categoria_id,  r.s);
    END LOOP;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_vcd_producto
AFTER UPDATE OF categoria_id ON producto
FOR EACH ROW
WHEN (OLD.categoria_id IS DISTINCT FROM NEW.categoria_id)
EXECUTE FUNCTION fn_vcd_producto();

-- 2.d TRUNCATE de la fuente: no se puede sincronizar por delta -> se prohíbe
--     mientras exista la tabla resumen (salvaguarda explícita).
CREATE OR REPLACE FUNCTION fn_vcd_no_truncate()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'TRUNCATE de % deshabilitado: desincronizaría venta_categoria_dia', TG_TABLE_NAME;
END $$;

CREATE TRIGGER trg_vcd_no_truncate_detalle BEFORE TRUNCATE ON detalle_pedido
FOR EACH STATEMENT EXECUTE FUNCTION fn_vcd_no_truncate();
CREATE TRIGGER trg_vcd_no_truncate_pedido  BEFORE TRUNCATE ON pedido
FOR EACH STATEMENT EXECUTE FUNCTION fn_vcd_no_truncate();

COMMIT;

ANALYZE venta_categoria_dia;

-- -----------------------------------------------------------------------------
-- 3) Consulta 5.2 d): mismo reporte leyendo la estructura desnormalizada
--    (solo une con categoria —5 filas— para mostrar el nombre)
-- -----------------------------------------------------------------------------
-- SELECT c.nombre AS categoria, v.total_vendido
-- FROM   venta_categoria_dia v
-- JOIN   categoria c ON c.id = v.categoria_id
-- WHERE  v.fecha = CURRENT_DATE AND v.total_vendido > 0
-- ORDER  BY v.total_vendido DESC
-- LIMIT  5;

-- -----------------------------------------------------------------------------
-- 4) Reversión (sin pérdida: la fuente de verdad nunca se modificó)
-- -----------------------------------------------------------------------------
-- BEGIN;
-- DROP TRIGGER trg_vcd_detalle ON detalle_pedido;
-- DROP TRIGGER trg_vcd_pedido ON pedido;
-- DROP TRIGGER trg_vcd_producto ON producto;
-- DROP TRIGGER trg_vcd_no_truncate_detalle ON detalle_pedido;
-- DROP TRIGGER trg_vcd_no_truncate_pedido ON pedido;
-- DROP FUNCTION fn_vcd_detalle(), fn_vcd_pedido(), fn_vcd_producto(),
--               fn_vcd_no_truncate(), fn_vcd_aplicar(DATE, BIGINT, NUMERIC);
-- DROP TABLE venta_categoria_dia;
-- COMMIT;

-- -----------------------------------------------------------------------------
-- 5) Script de auditoría (5.2 e): filas donde el dato redundante difiere de
--    la fuente de verdad. RESULTADO ESPERADO: VACÍO.
--    Una celda en 0 equivale a una celda ausente.
-- -----------------------------------------------------------------------------
WITH fuente AS (
    SELECT ped.fecha, pr.categoria_id, SUM(dp.subtotal) AS total
    FROM   detalle_pedido dp
    JOIN   producto pr ON pr.id  = dp.producto_id
    JOIN   pedido  ped ON ped.id = dp.pedido_id
    WHERE  dp.eliminado = FALSE AND ped.eliminado = FALSE
    GROUP  BY ped.fecha, pr.categoria_id
)
SELECT COALESCE(f.fecha, v.fecha)               AS fecha,
       COALESCE(f.categoria_id, v.categoria_id) AS categoria_id,
       COALESCE(f.total, 0)                     AS total_fuente,
       COALESCE(v.total_vendido, 0)             AS total_redundante
FROM   fuente f
FULL   JOIN venta_categoria_dia v
       ON v.fecha = f.fecha AND v.categoria_id = f.categoria_id
WHERE  COALESCE(f.total, 0) <> COALESCE(v.total_vendido, 0);
