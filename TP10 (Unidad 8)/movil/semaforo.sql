-- ============================================================================
-- BASE DE DATOS II - UTN TUPaD
-- TRABAJO PRÁCTICO N.º 8 (UNIDAD 8) - FOOD STORE EN LA FERIA
-- Consigna 2.b: Motor de Sincronización del Semáforo
-- Archivo: movil/semaforo.sql
-- ============================================================================

-- El móvil propone, el servidor dispone.
-- Este script evalúa exclusivamente las solicitudes en estado 'PENDIENTE'
-- cruzando los ítems del borrador con la instantánea del servidor (snapshot_servidor).
-- Garantiza idempotencia: re-ejecutarlo sobre solicitudes ya resueltas no cambia nada.

UPDATE cola_sync
SET 
    estado = eval.nuevo_estado,
    motivo = eval.nuevo_motivo
FROM (
    SELECT 
        c.solicitud_uuid,
        -- Determinación del estado según prioridad del semáforo:
        -- 1. ROJO: RECHAZADO si algún ítem no existe, no está disponible, está eliminado o no alcanza el stock
        -- 2. AMARILLO: CONFLICTO si no hay rojo pero cambió algún precio
        -- 3. VERDE: SIMULADO_APROBADO si todo coincide
        CASE
            WHEN SUM(
                CASE 
                    WHEN s.id IS NULL THEN 1
                    WHEN s.stock < i.cantidad THEN 1
                    WHEN s.disponible IN ('f', 'false', '0') OR s.disponible = 0 THEN 1
                    WHEN s.eliminado IN ('t', 'true', '1') OR s.eliminado = 1 THEN 1
                    ELSE 0 
                END
            ) > 0 THEN 'RECHAZADO'

            WHEN SUM(
                CASE 
                    WHEN i.precio_centavos_visto <> s.precio_centavos THEN 1
                    ELSE 0
                END
            ) > 0 THEN 'CONFLICTO'

            ELSE 'SIMULADO_APROBADO'
        END AS nuevo_estado,

        -- Diagnóstico detallado del motivo
        CASE
            WHEN SUM(CASE WHEN s.id IS NULL THEN 1 ELSE 0 END) > 0 
                THEN 'RECHAZADO: Producto inexistente en el servidor'
            WHEN SUM(CASE WHEN s.stock < i.cantidad THEN 1 ELSE 0 END) > 0 
                THEN 'RECHAZADO: Stock insuficiente en el servidor'
            WHEN SUM(CASE WHEN s.disponible IN ('f', 'false', '0') OR s.disponible = 0 OR s.eliminado IN ('t', 'true', '1') OR s.eliminado = 1 THEN 1 ELSE 0 END) > 0 
                THEN 'RECHAZADO: Producto no disponible o dado de baja'
            WHEN SUM(CASE WHEN i.precio_centavos_visto <> s.precio_centavos THEN 1 ELSE 0 END) > 0 
                THEN 'CONFLICTO: Precio modificado en el servidor respecto al borrador'
            ELSE 'SIMULADO_APROBADO: Stock y precios validados contra la instantanea'
        END AS nuevo_motivo

    FROM cola_sync c
    JOIN item_borrador i ON c.id_local = i.id_local
    LEFT JOIN snapshot_servidor s ON i.producto_id = s.id
    WHERE c.estado = 'PENDIENTE'
    GROUP BY c.solicitud_uuid
) AS eval
WHERE cola_sync.solicitud_uuid = eval.solicitud_uuid;

-- Consulta de verificación de la cola de sincronización tras la evaluación
SELECT 
    solicitud_uuid,
    id_local,
    estado,
    motivo,
    creado_en
FROM cola_sync
ORDER BY creado_en DESC;
