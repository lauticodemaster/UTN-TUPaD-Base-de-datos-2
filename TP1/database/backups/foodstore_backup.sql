--
-- PostgreSQL database dump
--

\restrict R008kgBr18v0YDxBORtX5v2MT6LRqtdQW0rLlcf4jhOZyZciYTAAEwv1dEj9NFy

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: foodstore; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA foodstore;


ALTER SCHEMA foodstore OWNER TO postgres;

--
-- Name: estado_pedido; Type: TYPE; Schema: foodstore; Owner: postgres
--

CREATE TYPE foodstore.estado_pedido AS ENUM (
    'PENDIENTE',
    'CONFIRMADO',
    'TERMINADO',
    'CANCELADO'
);


ALTER TYPE foodstore.estado_pedido OWNER TO postgres;

--
-- Name: forma_pago; Type: TYPE; Schema: foodstore; Owner: postgres
--

CREATE TYPE foodstore.forma_pago AS ENUM (
    'TARJETA',
    'TRANSFERENCIA',
    'EFECTIVO'
);


ALTER TYPE foodstore.forma_pago OWNER TO postgres;

--
-- Name: rol; Type: TYPE; Schema: foodstore; Owner: postgres
--

CREATE TYPE foodstore.rol AS ENUM (
    'ADMIN',
    'USUARIO'
);


ALTER TYPE foodstore.rol OWNER TO postgres;

--
-- Name: calcular_total_pedido(bigint); Type: FUNCTION; Schema: foodstore; Owner: postgres
--

CREATE FUNCTION foodstore.calcular_total_pedido(p_pedido_id bigint) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
	SELECT COALESCE(SUM(subtotal), 0)
	FROM   detalle_pedido
	WHERE  pedido_id = p_pedido_id AND eliminado = FALSE;
$$;


ALTER FUNCTION foodstore.calcular_total_pedido(p_pedido_id bigint) OWNER TO postgres;

--
-- Name: fn_recalcular_total(); Type: FUNCTION; Schema: foodstore; Owner: postgres
--

CREATE FUNCTION foodstore.fn_recalcular_total() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	-- Recalcula el total de cada pedido afectado (una sola pasada por sentencia)
	UPDATE pedido p
	SET total = calcular_total_pedido(p.id)
	WHERE p.id IN (SELECT pedido_id FROM afectados);
	RETURN NULL;
END;
$$;


ALTER FUNCTION foodstore.fn_recalcular_total() OWNER TO postgres;

--
-- Name: fn_set_subtotal(); Type: FUNCTION; Schema: foodstore; Owner: postgres
--

CREATE FUNCTION foodstore.fn_set_subtotal() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	-- Si no se pasÃ³ precio_unitario, se congela el precio actual del producto
	IF NEW.precio_unitario IS NULL THEN
		SELECT precio INTO NEW.precio_unitario
		FROM producto WHERE id = NEW.producto_id;
	END IF;
	NEW.subtotal := NEW.cantidad * NEW.precio_unitario;
	RETURN NEW;
END;
$$;


ALTER FUNCTION foodstore.fn_set_subtotal() OWNER TO postgres;

--
-- Name: soft_delete_fila(); Type: FUNCTION; Schema: foodstore; Owner: postgres
--

CREATE FUNCTION foodstore.soft_delete_fila() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
BEGIN
	EXECUTE format('UPDATE %I SET eliminado = TRUE WHERE id = $1', TG_TABLE_NAME)
	USING OLD.id;

	-- Cancela el delete.
	RETURN NULL;
END;
$_$;


ALTER FUNCTION foodstore.soft_delete_fila() OWNER TO postgres;

--
-- Name: sp_crear_pedido(bigint, foodstore.forma_pago, jsonb); Type: PROCEDURE; Schema: foodstore; Owner: postgres
--

CREATE PROCEDURE foodstore.sp_crear_pedido(IN p_usuario_id bigint, IN p_forma_pago foodstore.forma_pago, IN p_items jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_pedido_id BIGINT;
	v_item	  JSONB;
	v_producto_id BIGINT;
	v_cantidad	INTEGER;
	v_stock	   INTEGER;
	v_disponible  BOOLEAN;
BEGIN
	-- El usuario debe existir y no estar eliminado
	IF NOT EXISTS (SELECT 1 FROM usuario
				  WHERE id = p_usuario_id AND eliminado = FALSE) THEN
		RAISE EXCEPTION 'Usuario % inexistente o eliminado', p_usuario_id;
	END IF;

	INSERT INTO pedido(usuario_id, forma_pago)
	VALUES (p_usuario_id, p_forma_pago)
	RETURNING id INTO v_pedido_id;

	FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
		v_producto_id := (v_item->>'producto_id')::BIGINT;
		v_cantidad	:= (v_item->>'cantidad')::INTEGER;

		-- Bloquea la fila del producto para evitar sobreventa concurrente
		SELECT stock, disponible INTO v_stock, v_disponible
		FROM producto WHERE id = v_producto_id AND eliminado = FALSE
		FOR UPDATE;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'Producto % inexistente o eliminado', v_producto_id;
		END IF;
		IF NOT v_disponible THEN
			RAISE EXCEPTION 'Producto % no disponible', v_producto_id;
		END IF;
		IF v_stock < v_cantidad THEN
			RAISE EXCEPTION 'Stock insuficiente (producto %): hay %, se piden %',
							v_producto_id, v_stock, v_cantidad;
		END IF;

		INSERT INTO detalle_pedido(pedido_id, producto_id, cantidad)
		VALUES (v_pedido_id, v_producto_id, v_cantidad);

		-- Descuenta stock dentro de la misma transacciÃ³n
		UPDATE producto SET stock = stock - v_cantidad WHERE id = v_producto_id;
	END LOOP;
	-- Si alguna inserciÃ³n falla, toda la transacciÃ³n se revierte (rollback).
END;
$$;


ALTER PROCEDURE foodstore.sp_crear_pedido(IN p_usuario_id bigint, IN p_forma_pago foodstore.forma_pago, IN p_items jsonb) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: categoria; Type: TABLE; Schema: foodstore; Owner: postgres
--

CREATE TABLE foodstore.categoria (
    id bigint NOT NULL,
    nombre character varying(99) NOT NULL,
    descripcion character varying(255),
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE foodstore.categoria OWNER TO postgres;

--
-- Name: categoria_id_seq; Type: SEQUENCE; Schema: foodstore; Owner: postgres
--

ALTER TABLE foodstore.categoria ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME foodstore.categoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: detalle_pedido; Type: TABLE; Schema: foodstore; Owner: postgres
--

CREATE TABLE foodstore.detalle_pedido (
    id bigint NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    subtotal numeric(10,2) NOT NULL,
    pedido_id bigint NOT NULL,
    producto_id bigint NOT NULL,
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT detalle_pedido_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT detalle_pedido_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric)),
    CONSTRAINT detalle_pedido_subtotal_check CHECK ((subtotal >= (0)::numeric))
);


ALTER TABLE foodstore.detalle_pedido OWNER TO postgres;

--
-- Name: detalle_pedido_id_seq; Type: SEQUENCE; Schema: foodstore; Owner: postgres
--

ALTER TABLE foodstore.detalle_pedido ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME foodstore.detalle_pedido_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pedido; Type: TABLE; Schema: foodstore; Owner: postgres
--

CREATE TABLE foodstore.pedido (
    id bigint NOT NULL,
    fecha date DEFAULT CURRENT_DATE NOT NULL,
    estado foodstore.estado_pedido DEFAULT 'PENDIENTE'::foodstore.estado_pedido NOT NULL,
    total numeric(10,2) DEFAULT 0 NOT NULL,
    forma_pago foodstore.forma_pago NOT NULL,
    usuario_id bigint NOT NULL,
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pedido_total_check CHECK ((total >= (0)::numeric))
);


ALTER TABLE foodstore.pedido OWNER TO postgres;

--
-- Name: pedido_id_seq; Type: SEQUENCE; Schema: foodstore; Owner: postgres
--

ALTER TABLE foodstore.pedido ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME foodstore.pedido_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto; Type: TABLE; Schema: foodstore; Owner: postgres
--

CREATE TABLE foodstore.producto (
    id bigint NOT NULL,
    nombre character varying(99) NOT NULL,
    precio numeric(10,2) NOT NULL,
    descripcion character varying(255),
    stock integer DEFAULT 0 NOT NULL,
    imagen character varying(255),
    disponible boolean DEFAULT true NOT NULL,
    categoria_id bigint NOT NULL,
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_producto_precio_positivo CHECK ((precio > (0)::numeric)),
    CONSTRAINT producto_precio_check CHECK ((precio >= (0)::numeric)),
    CONSTRAINT producto_stock_check CHECK ((stock >= 0))
);


ALTER TABLE foodstore.producto OWNER TO postgres;

--
-- Name: producto_id_seq; Type: SEQUENCE; Schema: foodstore; Owner: postgres
--

ALTER TABLE foodstore.producto ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME foodstore.producto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuario; Type: TABLE; Schema: foodstore; Owner: postgres
--

CREATE TABLE foodstore.usuario (
    id bigint NOT NULL,
    nombre character varying(99) NOT NULL,
    apellido character varying(99) NOT NULL,
    mail character varying(160) NOT NULL,
    celular character varying(10),
    contrasena character varying(255) NOT NULL,
    rol foodstore.rol DEFAULT 'USUARIO'::foodstore.rol NOT NULL,
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_usuario_celular_solo_numeros CHECK (((celular IS NULL) OR ((celular)::text ~ '^[0-9]{10}$'::text))),
    CONSTRAINT chk_usuario_contrasena_min8 CHECK ((char_length((contrasena)::text) >= 8)),
    CONSTRAINT chk_usuario_mail_formato CHECK (((mail)::text ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'::text)),
    CONSTRAINT chk_usuario_mail_no_vacio CHECK ((char_length(TRIM(BOTH FROM mail)) > 0))
);


ALTER TABLE foodstore.usuario OWNER TO postgres;

--
-- Name: usuario_id_seq; Type: SEQUENCE; Schema: foodstore; Owner: postgres
--

ALTER TABLE foodstore.usuario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME foodstore.usuario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_categorias_vigentes; Type: VIEW; Schema: foodstore; Owner: postgres
--

CREATE VIEW foodstore.v_categorias_vigentes AS
 SELECT id,
    nombre,
    descripcion
   FROM foodstore.categoria
  WHERE (eliminado = false);


ALTER VIEW foodstore.v_categorias_vigentes OWNER TO postgres;

--
-- Name: v_pedido_detalle; Type: VIEW; Schema: foodstore; Owner: postgres
--

CREATE VIEW foodstore.v_pedido_detalle AS
 SELECT dp.pedido_id,
    pr.nombre AS producto,
    dp.cantidad,
    dp.precio_unitario,
    dp.subtotal
   FROM (foodstore.detalle_pedido dp
     JOIN foodstore.producto pr ON ((pr.id = dp.producto_id)))
  WHERE (dp.eliminado = false);


ALTER VIEW foodstore.v_pedido_detalle OWNER TO postgres;

--
-- Name: v_pedidos_resumen; Type: VIEW; Schema: foodstore; Owner: postgres
--

CREATE VIEW foodstore.v_pedidos_resumen AS
 SELECT ped.id,
    (((u.nombre)::text || ' '::text) || (u.apellido)::text) AS usuario,
    ped.fecha,
    ped.estado,
    ped.forma_pago,
    ped.total
   FROM (foodstore.pedido ped
     JOIN foodstore.usuario u ON ((u.id = ped.usuario_id)))
  WHERE (ped.eliminado = false);


ALTER VIEW foodstore.v_pedidos_resumen OWNER TO postgres;

--
-- Name: v_productos_vigentes; Type: VIEW; Schema: foodstore; Owner: postgres
--

CREATE VIEW foodstore.v_productos_vigentes AS
 SELECT p.id,
    p.nombre,
    p.precio,
    p.stock,
    c.nombre AS categoria
   FROM (foodstore.producto p
     JOIN foodstore.categoria c ON ((c.id = p.categoria_id)))
  WHERE ((p.eliminado = false) AND (c.eliminado = false));


ALTER VIEW foodstore.v_productos_vigentes OWNER TO postgres;

--
-- Data for Name: categoria; Type: TABLE DATA; Schema: foodstore; Owner: postgres
--

COPY foodstore.categoria (id, nombre, descripcion, eliminado, created_at) FROM stdin;
1	Pizzas	Pizzas de masa tradicional y rellenos variados	f	2026-09-01 18:33:28.743477-03
2	Empanadas	Empanadas de carne, pollo, queso y jamÃ³n	f	2026-09-01 18:33:28.744769-03
3	Bebidas	Bebidas frÃ­as y refrescos varios	f	2026-09-01 18:33:28.745299-03
4	Postres	Postres caseros y dulces variados	f	2026-09-01 18:33:28.745848-03
5	Ensaladas	Ensaladas frescas y saludables	f	2026-09-01 18:33:28.746366-03
\.


--
-- Data for Name: detalle_pedido; Type: TABLE DATA; Schema: foodstore; Owner: postgres
--

COPY foodstore.detalle_pedido (id, cantidad, precio_unitario, subtotal, pedido_id, producto_id, eliminado, created_at) FROM stdin;
1	2	1800.00	3600.00	1	1	f	2026-09-01 18:33:28.760999-03
2	1	350.00	350.00	1	7	f	2026-09-01 18:33:28.764173-03
3	3	150.00	450.00	2	4	f	2026-09-01 18:33:28.764973-03
4	2	140.00	280.00	2	5	f	2026-09-01 18:33:28.765718-03
5	1	250.00	250.00	2	8	f	2026-09-01 18:33:28.766443-03
6	1	1600.00	1600.00	3	2	f	2026-09-01 18:33:28.767199-03
7	2	200.00	400.00	3	9	f	2026-09-01 18:33:28.767959-03
8	1	500.00	500.00	3	11	f	2026-09-01 18:33:28.768653-03
\.


--
-- Data for Name: pedido; Type: TABLE DATA; Schema: foodstore; Owner: postgres
--

COPY foodstore.pedido (id, fecha, estado, total, forma_pago, usuario_id, eliminado, created_at) FROM stdin;
1	2026-09-01	CONFIRMADO	3950.00	EFECTIVO	1	f	2026-09-01 18:33:28.757-03
2	2026-09-01	PENDIENTE	980.00	TARJETA	3	f	2026-09-01 18:33:28.758633-03
3	2026-09-01	TERMINADO	2500.00	TRANSFERENCIA	5	f	2026-09-01 18:33:28.760268-03
\.


--
-- Data for Name: producto; Type: TABLE DATA; Schema: foodstore; Owner: postgres
--

COPY foodstore.producto (id, nombre, precio, descripcion, stock, imagen, disponible, categoria_id, eliminado, created_at) FROM stdin;
1	Fugazzeta	1800.00	Pizza de cebolla con queso mozzarella	15	\N	t	1	f	2026-09-01 18:33:28.748257-03
2	Mozzarella	1600.00	Pizza clÃ¡sica de queso mozzarella	20	\N	t	1	f	2026-09-01 18:33:28.750572-03
3	JamÃ³n y Queso	2000.00	Pizza con jamÃ³n serrano y queso	12	\N	t	1	f	2026-09-01 18:33:28.751199-03
4	Empanada de Carne	150.00	Empanada rellena de carne	50	\N	t	2	f	2026-09-01 18:33:28.751791-03
5	Empanada de Pollo	140.00	Empanada rellena de pollo	45	\N	t	2	f	2026-09-01 18:33:28.752355-03
6	Empanada de Queso	130.00	Empanada rellena de queso	40	\N	t	2	f	2026-09-01 18:33:28.752937-03
7	Gaseosa 2L	350.00	Gaseosa cola o naranja 2 litros	30	\N	t	3	f	2026-09-01 18:33:28.753496-03
8	Jugo Natural	250.00	Jugo de naranja o pomelo reciÃ©n exprimido	25	\N	t	3	f	2026-09-01 18:33:28.754024-03
9	Flan Casero	200.00	Flan tradicional con dulce de leche	10	\N	t	4	f	2026-09-01 18:33:28.75462-03
10	Brownie	180.00	Brownie de chocolate casero	8	\N	t	4	f	2026-09-01 18:33:28.755207-03
11	Ensalada Verde	500.00	Lechuga, tomate, cebolla y aderezo	6	\N	t	5	f	2026-09-01 18:33:28.755863-03
12	Ensalada CÃ©sar	700.00	Lechuga, pollo, queso parmesano y salsa CÃ©sar	5	\N	t	5	f	2026-09-01 18:33:28.75645-03
\.


--
-- Data for Name: usuario; Type: TABLE DATA; Schema: foodstore; Owner: postgres
--

COPY foodstore.usuario (id, nombre, apellido, mail, celular, contrasena, rol, eliminado, created_at) FROM stdin;
1	Miguel	Herrera	miguelherrera@gmail.com	2613649945	marmota5	USUARIO	f	2026-09-01 18:33:28.73747-03
2	Juliana	Paredes	juliparedes23@hotmail.com	2619938672	h1p0potomo2tr0	ADMIN	f	2026-09-01 18:33:28.740527-03
3	IvÃ¡n	IvaÃ±ez	iviva1717@yahoo.com	2617884561	vivilavidaloca_como_tu_te_llama_17	USUARIO	f	2026-09-01 18:33:28.741168-03
4	RamÃ³n	GarzÃ³n	1tiralodon@gmail.com	2614324865	Ocean0sPacificos_2f	ADMIN	f	2026-09-01 18:33:28.742221-03
5	Ariagna	Rodriguez	ariagnita38@gmail.com	2612261620	tela-CaraX8	USUARIO	f	2026-09-01 18:33:28.742883-03
\.


--
-- Name: categoria_id_seq; Type: SEQUENCE SET; Schema: foodstore; Owner: postgres
--

SELECT pg_catalog.setval('foodstore.categoria_id_seq', 5, true);


--
-- Name: detalle_pedido_id_seq; Type: SEQUENCE SET; Schema: foodstore; Owner: postgres
--

SELECT pg_catalog.setval('foodstore.detalle_pedido_id_seq', 8, true);


--
-- Name: pedido_id_seq; Type: SEQUENCE SET; Schema: foodstore; Owner: postgres
--

SELECT pg_catalog.setval('foodstore.pedido_id_seq', 3, true);


--
-- Name: producto_id_seq; Type: SEQUENCE SET; Schema: foodstore; Owner: postgres
--

SELECT pg_catalog.setval('foodstore.producto_id_seq', 12, true);


--
-- Name: usuario_id_seq; Type: SEQUENCE SET; Schema: foodstore; Owner: postgres
--

SELECT pg_catalog.setval('foodstore.usuario_id_seq', 5, true);


--
-- Name: categoria categoria_nombre_key; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.categoria
    ADD CONSTRAINT categoria_nombre_key UNIQUE (nombre);


--
-- Name: categoria categoria_pkey; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.categoria
    ADD CONSTRAINT categoria_pkey PRIMARY KEY (id);


--
-- Name: detalle_pedido detalle_pedido_pedido_id_producto_id_key; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.detalle_pedido
    ADD CONSTRAINT detalle_pedido_pedido_id_producto_id_key UNIQUE (pedido_id, producto_id);


--
-- Name: detalle_pedido detalle_pedido_pkey; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.detalle_pedido
    ADD CONSTRAINT detalle_pedido_pkey PRIMARY KEY (id);


--
-- Name: pedido pedido_pkey; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.pedido
    ADD CONSTRAINT pedido_pkey PRIMARY KEY (id);


--
-- Name: producto producto_pkey; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.producto
    ADD CONSTRAINT producto_pkey PRIMARY KEY (id);


--
-- Name: usuario usuario_mail_key; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.usuario
    ADD CONSTRAINT usuario_mail_key UNIQUE (mail);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id);


--
-- Name: idx_pedido_usuario_id; Type: INDEX; Schema: foodstore; Owner: postgres
--

CREATE INDEX idx_pedido_usuario_id ON foodstore.pedido USING btree (usuario_id);


--
-- Name: idx_producto_categoria_id; Type: INDEX; Schema: foodstore; Owner: postgres
--

CREATE INDEX idx_producto_categoria_id ON foodstore.producto USING btree (categoria_id);


--
-- Name: idx_producto_no_eliminado; Type: INDEX; Schema: foodstore; Owner: postgres
--

CREATE INDEX idx_producto_no_eliminado ON foodstore.producto USING btree (nombre) WHERE (eliminado = false);


--
-- Name: categoria trg_soft_delete_categoria; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_soft_delete_categoria BEFORE DELETE ON foodstore.categoria FOR EACH ROW EXECUTE FUNCTION foodstore.soft_delete_fila();


--
-- Name: detalle_pedido trg_soft_delete_detalle_pedido; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_soft_delete_detalle_pedido BEFORE DELETE ON foodstore.detalle_pedido FOR EACH ROW EXECUTE FUNCTION foodstore.soft_delete_fila();


--
-- Name: pedido trg_soft_delete_pedido; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_soft_delete_pedido BEFORE DELETE ON foodstore.pedido FOR EACH ROW EXECUTE FUNCTION foodstore.soft_delete_fila();


--
-- Name: producto trg_soft_delete_producto; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_soft_delete_producto BEFORE DELETE ON foodstore.producto FOR EACH ROW EXECUTE FUNCTION foodstore.soft_delete_fila();


--
-- Name: usuario trg_soft_delete_usuario; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_soft_delete_usuario BEFORE DELETE ON foodstore.usuario FOR EACH ROW EXECUTE FUNCTION foodstore.soft_delete_fila();


--
-- Name: detalle_pedido trg_subtotal; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_subtotal BEFORE INSERT OR UPDATE ON foodstore.detalle_pedido FOR EACH ROW EXECUTE FUNCTION foodstore.fn_set_subtotal();


--
-- Name: detalle_pedido trg_total_ins; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_total_ins AFTER INSERT ON foodstore.detalle_pedido REFERENCING NEW TABLE AS afectados FOR EACH STATEMENT EXECUTE FUNCTION foodstore.fn_recalcular_total();


--
-- Name: detalle_pedido trg_total_upd; Type: TRIGGER; Schema: foodstore; Owner: postgres
--

CREATE TRIGGER trg_total_upd AFTER UPDATE ON foodstore.detalle_pedido REFERENCING NEW TABLE AS afectados FOR EACH STATEMENT EXECUTE FUNCTION foodstore.fn_recalcular_total();


--
-- Name: detalle_pedido detalle_pedido_pedido_id_fkey; Type: FK CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.detalle_pedido
    ADD CONSTRAINT detalle_pedido_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES foodstore.pedido(id) ON DELETE RESTRICT;


--
-- Name: detalle_pedido detalle_pedido_producto_id_fkey; Type: FK CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.detalle_pedido
    ADD CONSTRAINT detalle_pedido_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES foodstore.producto(id);


--
-- Name: pedido pedido_usuario_id_fkey; Type: FK CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.pedido
    ADD CONSTRAINT pedido_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES foodstore.usuario(id);


--
-- Name: producto producto_categoria_id_fkey; Type: FK CONSTRAINT; Schema: foodstore; Owner: postgres
--

ALTER TABLE ONLY foodstore.producto
    ADD CONSTRAINT producto_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES foodstore.categoria(id);


--
-- PostgreSQL database dump complete
--

\unrestrict R008kgBr18v0YDxBORtX5v2MT6LRqtdQW0rLlcf4jhOZyZciYTAAEwv1dEj9NFy

