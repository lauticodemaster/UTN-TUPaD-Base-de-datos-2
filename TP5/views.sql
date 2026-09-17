-- ============================================================================
-- TP5 - Unidad 3, Semana 5 - Partes B y C
-- Vistas de reporte, vista de seguridad y vista materializada de Food Store
--
-- specs: specs/spec_vistas_reportes.md
--        specs/spec_mv_facturacion_categoria_mes.md
-- Verificacion de equivalencia: mediciones/verificacion_vistas.sql
--
-- Ejecutar sobre foodstore_test, nunca sobre foodstore directo.
-- ============================================================================

SET search_path TO foodstore;


-- ============================================================================
-- PARTE B - Vistas para los reportes del sistema
-- ============================================================================

-- ----------------------------------------------------------------------------
-- B.1 a B.3 - Las tres vistas de reporte YA EXISTEN en objects.sql (Semana 2).
--
-- Se transcriben aca para que este archivo se pueda leer solo, pero estan
-- COMENTADAS a proposito: volver a ejecutarlas no agrega nada y la consigna
-- pide no reescribir lo heredado. Lo que si se hizo esta semana, y nunca se
-- habia hecho, es verificar que devuelven exactamente lo mismo que la
-- consulta escrita a mano (ver mediciones/verificacion_vistas.sql).
--
-- CREATE VIEW v_productos_vigentes AS
-- SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
-- FROM   producto p
-- JOIN   categoria c ON c.id = p.categoria_id
-- WHERE  p.eliminado = FALSE AND c.eliminado = FALSE;
--
-- CREATE VIEW v_pedidos_resumen AS
-- SELECT ped.id, u.nombre || ' ' || u.apellido AS usuario,
--        ped.fecha, ped.estado, ped.forma_pago, ped.total
-- FROM   pedido ped
-- JOIN   usuario u ON u.id = ped.usuario_id
-- WHERE  ped.eliminado = FALSE;
--
-- CREATE VIEW v_pedido_detalle AS
-- SELECT dp.pedido_id, pr.nombre AS producto,
--        dp.cantidad, dp.precio_unitario, dp.subtotal
-- FROM   detalle_pedido dp
-- JOIN   producto pr ON pr.id = dp.producto_id
-- WHERE  dp.eliminado = FALSE;


-- ----------------------------------------------------------------------------
-- B.4 - v_usuarios_publico: la vista de seguridad (punto 4 de la Parte B)
--
-- Expone usuario SIN la columna contrasena, para poder dar SELECT sobre los
-- usuarios a un rol de solo lectura sin darle ningun permiso sobre la tabla
-- base.
--
-- Las columnas se listan una por una a proposito. Con un SELECT * aca,
-- cualquier columna que se agregue a usuario mas adelante quedaria expuesta
-- sola, sin que nadie lo revise.
CREATE OR REPLACE VIEW v_usuarios_publico AS
SELECT u.id,
       u.nombre,
       u.apellido,
       u.mail,
       u.celular,
       u.rol,
       u.created_at
FROM   usuario u
WHERE  u.eliminado = FALSE;

-- Rol de solo lectura con el que se prueba que la vista sirve para lo que se
-- creo. CREATE ROLE no admite IF NOT EXISTS, asi que se pregunta antes.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_lectura') THEN
        CREATE ROLE app_lectura NOLOGIN;
    END IF;
END $$;

GRANT USAGE  ON SCHEMA foodstore   TO app_lectura;
GRANT SELECT ON v_usuarios_publico TO app_lectura;
-- Intencionalmente NO hay ningun GRANT sobre la tabla usuario. Ese es el punto.
REVOKE ALL ON usuario FROM app_lectura;

-- Por que alcanza: en PostgreSQL una vista se ejecuta con los permisos de su
-- DUENO, no con los de quien la consulta. app_lectura puede leer
-- v_usuarios_publico sin tener nada sobre usuario porque el motor entra a la
-- tabla base en nombre del dueno de la vista. Lo unico que app_lectura llega
-- a ver son las siete columnas que la vista expone. No hace falta
-- SECURITY DEFINER.

