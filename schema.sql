SET search_path TO foodstore;

-- ENUMS.
CREATE TYPE rol AS ENUM ('ADMIN', 'USUARIO');

CREATE TYPE estado_pedido AS ENUM (
	'PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO'
);

CREATE TYPE forma_pago AS ENUM (
	'TARJETA', 'TRANSFERENCIA', 'EFECTIVO'
);


-- TABLAS.
CREATE TABLE categoria(
	id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	nombre VARCHAR(99) NOT NULL UNIQUE,
	descripcion VARCHAR(255),
	eliminado BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
 
CREATE TABLE producto (
	id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	nombre VARCHAR(99) NOT NULL,
	precio NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
	descripcion VARCHAR(255),
	stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
	imagen VARCHAR(255),
	disponible BOOLEAN NOT NULL DEFAULT TRUE,
	categoria_id BIGINT NOT NULL REFERENCES categoria(id),
	eliminado BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE usuario (
	id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	nombre VARCHAR(99) NOT NULL,
	apellido VARCHAR(99) NOT NULL,
	mail VARCHAR(160) NOT NULL UNIQUE,
	celular VARCHAR(10),
	contrasena VARCHAR(255) NOT NULL,
	rol rol NOT NULL DEFAULT 'USUARIO',
	eliminado BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
 
CREATE TABLE pedido (
	id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	fecha DATE NOT NULL DEFAULT CURRENT_DATE,
	estado estado_pedido NOT NULL DEFAULT 'PENDIENTE',
	total NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
	forma_pago forma_pago NOT NULL,
	usuario_id BIGINT NOT NULL REFERENCES usuario(id),
	eliminado BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE detalle_pedido (
	id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	cantidad INTEGER NOT NULL CHECK (cantidad > 0),
	precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
	subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
	pedido_id BIGINT NOT NULL REFERENCES pedido(id) ON DELETE RESTRICT,
	producto_id BIGINT NOT NULL REFERENCES producto(id),
	eliminado BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	UNIQUE (pedido_id, producto_id)
);


-- ÍNDICES.
EXPLAIN ANALYZE
	SELECT * FROM producto
	WHERE categoria_id = 1;
EXPLAIN ANALYZE
	SELECT * FROM pedido
	WHERE usuario_id = 1;
EXPLAIN ANALYZE
	SELECT * FROM producto
	WHERE ELIMINADO = FALSE;

CREATE INDEX idx_producto_categoria_id ON producto(categoria_id);
CREATE INDEX idx_pedido_usuario_id ON pedido(usuario_id);
CREATE INDEX idx_producto_no_eliminado ON producto(nombre)
	WHERE eliminado = FALSE;

	ALTER TABLE usuario
  ADD CONSTRAINT chk_usuario_mail_no_vacio
  CHECK (char_length(trim(mail)) > 0);


-- Alternativa estricta email completo:
 ALTER TABLE usuario ADD CONSTRAINT chk_usuario_mail_formato
   CHECK (mail ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- usuario.celular solo números
-- Permite NULL (usuario sin celular) pero si tiene valor solo dígitos
ALTER TABLE usuario
  ADD CONSTRAINT chk_usuario_celular_solo_numeros
 CHECK (celular IS NULL OR celular ~ '^[0-9]{10}$')


-- Se añade constraint más estricto
ALTER TABLE producto
  ADD CONSTRAINT chk_producto_precio_positivo
  CHECK (precio > 0);


-- usuario.contrasena al menos 8 caracteres
ALTER TABLE usuario
  ADD CONSTRAINT chk_usuario_contrasena_min8
  CHECK (char_length(contrasena) >= 8);
```