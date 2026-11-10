-- ============================================================================
-- BASE DE DATOS II - UTN TUPaD
-- TRABAJO PRÁCTICO N.º 8 (UNIDAD 8) - FOOD STORE EN LA FERIA
-- Consigna 1.b: Esquema de la base SQLite para la tablet móvil
-- Archivo: movil/schema_sqlite.sql
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- 1. Tabla: producto_cache
-- Copia local del catálogo de productos obtenida del servidor.
-- Tablas STRICT para garantizar tipado fuerte y validación de dominios.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS producto_cache (
    id INTEGER PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock_visto INTEGER NOT NULL DEFAULT 0 CHECK (stock_visto >= 0),
    disponible INTEGER NOT NULL CHECK (disponible IN (0, 1)),
    eliminado INTEGER NOT NULL CHECK (eliminado IN (0, 1)),
    fecha_copia TEXT NOT NULL
) STRICT;

-- ----------------------------------------------------------------------------
-- 2. Tabla: pedido_borrador
-- Registro de borradores iniciados offline en el food truck.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pedido_borrador (
    id_local TEXT PRIMARY KEY,
    usuario TEXT NOT NULL,
    forma_pago TEXT NOT NULL CHECK (forma_pago IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')),
    fecha TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP)
) STRICT;

-- ----------------------------------------------------------------------------
-- 3. Tabla: item_borrador
-- Líneas de producto y cantidades asociadas a cada borrador local.
-- Posee claves foráneas a pedido_borrador y producto_cache.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS item_borrador (
    id_local TEXT NOT NULL,
    producto_id INTEGER NOT NULL,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id),
    FOREIGN KEY (id_local) REFERENCES pedido_borrador(id_local) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES producto_cache(id)
) STRICT;

-- ----------------------------------------------------------------------------
-- 4. Tabla: cola_sync
-- Cola de sincronización que gestiona los estados de resolución del semáforo.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cola_sync (
    solicitud_uuid TEXT PRIMARY KEY,
    id_local TEXT NOT NULL,
    estado TEXT NOT NULL CHECK (estado IN ('PENDIENTE', 'CONFLICTO', 'RECHAZADO', 'SIMULADO_APROBADO')),
    motivo TEXT,
    creado_en TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
    FOREIGN KEY (id_local) REFERENCES pedido_borrador(id_local) ON DELETE CASCADE
) STRICT;

-- ----------------------------------------------------------------------------
-- 5. Tabla auxiliar: snapshot_servidor
-- Recibe la importación directa del archivo CSV exportado desde PostgreSQL.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS snapshot_servidor (
    id INTEGER PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL,
    stock INTEGER NOT NULL,
    disponible TEXT NOT NULL,
    eliminado TEXT NOT NULL
) STRICT;
