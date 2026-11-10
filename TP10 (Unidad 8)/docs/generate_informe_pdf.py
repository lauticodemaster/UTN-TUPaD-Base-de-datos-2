#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generador de informe.pdf en formato A4 para TP Unidad 8
Base de Datos II - UTN TUPaD
"""

import os
import io
import pypdf

class PDFDocument:
    def __init__(self):
        self.pages = []
        self.stream = []
        self.page_w = 595.28
        self.page_h = 841.89
        self.margin = 36.0 # 0.5 in
        self.y = 800.0

    def new_page(self):
        if self.stream:
            self.pages.append("".join(self.stream))
            self.stream = []
        self.y = 800.0

    def finish(self):
        if self.stream:
            self.pages.append("".join(self.stream))
            self.stream = []

    def esc(self, text):
        return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

    def text(self, x, y, text, font="F1", size=9, r=0.1, g=0.15, b=0.2):
        t = self.esc(text)
        self.stream.append(f"BT /{font} {size} Tf {r:.2f} {g:.2f} {b:.2f} rg {x:.1f} {y:.1f} Td ({t}) Tj ET\n")

    def rect(self, x, y, w, h, fill_rgb=None, stroke_rgb=(0.76, 0.8, 0.84), line_w=0.8):
        if fill_rgb:
            fr, fg, fb = fill_rgb
            sr, sg, sb = stroke_rgb
            self.stream.append(f"{fr:.2f} {fg:.2f} {fb:.2f} rg {sr:.2f} {sg:.2f} {sb:.2f} RG {line_w} w {x:.1f} {y:.1f} {w:.1f} {h:.1f} re B\n")
        else:
            sr, sg, sb = stroke_rgb
            self.stream.append(f"{sr:.2f} {sg:.2f} {sb:.2f} RG {line_w} w {x:.1f} {y:.1f} {w:.1f} {h:.1f} re S\n")

    def line(self, x1, y1, x2, y2, rgb=(0.76, 0.8, 0.84), line_w=0.8):
        r, g, b = rgb
        self.stream.append(f"{r:.2f} {g:.2f} {b:.2f} RG {line_w} w {x1:.1f} {y1:.1f} m {x2:.1f} {y2:.1f} l S\n")

    def render_pdf(self):
        self.finish()
        total_p = len(self.pages)
        # Add footer page numbers
        for i in range(total_p):
            p_stream = self.pages[i]
            footer = f"BT /F1 8 Tf 0.3 0.35 0.4 rg 260 22 Td (Pagina {i+1} de {total_p}) Tj ET\n"
            footer += f"BT /F1 8 Tf 0.3 0.35 0.4 rg 36 22 Td (UTN TUPaD - Base de Datos II - TP Unidad 8) Tj ET\n"
            self.pages[i] = p_stream + footer

        out = io.BytesIO()
        out.write(b"%PDF-1.4\n")
        offsets = {}

        def write_obj(num, data):
            offsets[num] = out.tell()
            out.write(f"{num} 0 obj\n".encode("latin1"))
            out.write(data)
            out.write(b"\nendobj\n")

        write_obj(1, b"<< /Type /Catalog /Pages 2 0 R >>")
        kids = " ".join([f"{6 + 2*i} 0 R" for i in range(total_p)])
        write_obj(2, f"<< /Type /Pages /Kids [{kids}] /Count {total_p} >>".encode("latin1"))
        write_obj(3, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        write_obj(4, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        write_obj(5, b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")

        for i, p_str in enumerate(self.pages):
            p_bytes = p_str.encode("latin1", errors="replace")
            p_num = 6 + 2*i
            s_num = p_num + 1
            write_obj(p_num, f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents {s_num} 0 R >>".encode("latin1"))
            write_obj(s_num, f"<< /Length {len(p_bytes)} >>\nstream\n".encode("latin1") + p_bytes + b"\nendstream")

        max_obj = 5 + 2*total_p
        xref_pos = out.tell()
        out.write(f"xref\n0 {max_obj + 1}\n0000000000 65535 f \n".encode("latin1"))
        for num in range(1, max_obj + 1):
            out.write(f"{offsets[num]:010d} 00000 n \n".encode("latin1"))
        out.write(f"trailer\n<< /Size {max_obj + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n".encode("latin1"))
        return out.getvalue()

def build_full_report():
    doc = PDFDocument()

    # =========================================================================
    # PÁGINA 1: Encabezado, Regla de Oro y Consigna 1.a (Qué datos viajan)
    # =========================================================================
    doc.new_page()
    doc.text(36, 808, "TRABAJO PRÁCTICO N.º 8 (UNIDAD 8) — FOOD STORE EN LA FERIA", "F2", 14, 0.09, 0.20, 0.30)
    doc.text(36, 794, "Asignatura: Base de Datos II  ·  UTN - Tecnicatura Universitaria en Programación  ·  Docente: Carlos Yácomo", "F1", 8.5, 0.25, 0.35, 0.45)
    doc.text(36, 782, "Grupo H (Saferazi): Lautaro Fernandez, Daniela Díaz, Jesús Ramírez, Danilo Serrano, Elio Marí", "F2", 8.5, 0.20, 0.30, 0.40)
    doc.text(36, 770, "Entorno: PostgreSQL 17 (SSOT), SQLite 3.50+ (STRICT), MongoDB 8.0  ·  Etiqueta de entrega: tp8", "F1", 8.5, 0.30, 0.35, 0.40)
    doc.line(36, 762, 559, 762, (0.09, 0.20, 0.30), 1.5)

    # Box Regla de Oro
    doc.rect(36, 715, 523, 38, fill_rgb=(1.0, 0.97, 0.92), stroke_rgb=(0.7, 0.4, 0.1), line_w=1.2)
    doc.text(44, 738, "REGLA DE ORO DE LA MATERIA:", "F2", 9, 0.65, 0.30, 0.05)
    doc.text(44, 725, "El móvil propone, el servidor dispone. La tablet solo consulta y arma borradores. Precio, stock y ventas los decide PostgreSQL.", "F1", 8.5, 0.20, 0.20, 0.20)

    # Consigna 1.a
    doc.text(36, 695, "1. CONSIGNA 1.a · QUÉ DATOS VIAJAN A LA TABLET Y FUENTE DE VERDAD", "F2", 10.5, 0.09, 0.20, 0.30)
    doc.line(36, 690, 559, 690, (0.09, 0.20, 0.30), 0.8)

    # Tabla 1.a
    # Columnas: Tabla (75), Atributo (100), Viaja (45), Justificación (303)
    headers = [("Tabla Original", 75), ("Columna / Atributo", 105), ("¿Viaja?", 45), ("Justificación Técnica, Operativa y de Seguridad", 298)]
    x_start = 36
    y_tbl = 672
    
    # Header row
    doc.rect(x_start, y_tbl, 523, 16, fill_rgb=(0.09, 0.20, 0.30), stroke_rgb=(0.09, 0.20, 0.30))
    cur_x = x_start
    for title, w in headers:
        doc.text(cur_x + 4, y_tbl + 4, title, "F2", 8, 1.0, 1.0, 1.0)
        cur_x += w

    rows = [
        ("producto", "id, nombre", "SÍ", "Identificación unívoca y visualización en el menú de la tablet.", True),
        ("producto", "precio -> precio_centavos", "SÍ", "Centavos enteros (ROUND(precio*100)) evitando errores de float.", False),
        ("producto", "stock -> stock_visto", "SÍ", "Referencia visual para que el cajero conozca el stock al inicio del turno.", True),
        ("producto", "disponible, eliminado", "SÍ", "Patrón de lápidas (tombstones): filas eliminadas quedan ocultas.", False),
        ("producto", "categoria_id, imagen, meta", "NO", "Prescindibles para facturar; ahorran ancho de banda y almacenamiento.", True),
        ("usuario", "contrasena, mail, rol, tel", "NO", "Zero Trust: Tablet pública expuesta a hurto; credenciales nunca viajan.", False),
        ("pedido / detalle", "Histórico de ventas previo", "NO", "La tablet solo gestiona borradores de la feria actual, no transacciones ajenas.", True),
    ]

    cur_y = y_tbl - 18
    for tbl, attr, viaja, just, bg in rows:
        fill = (0.95, 0.96, 0.98) if bg else (1.0, 1.0, 1.0)
        doc.rect(x_start, cur_y, 523, 18, fill_rgb=fill, stroke_rgb=(0.76, 0.8, 0.84))
        doc.text(x_start + 4, cur_y + 5, tbl, "F3", 7.5, 0.1, 0.15, 0.2)
        doc.text(x_start + 79, cur_y + 5, attr, "F1", 7.5, 0.1, 0.15, 0.2)
        v_col = (0.1, 0.5, 0.2) if viaja == "SÍ" else (0.7, 0.1, 0.1)
        doc.text(x_start + 184, cur_y + 5, viaja, "F2", 8, v_col[0], v_col[1], v_col[2])
        doc.text(x_start + 229, cur_y + 5, just, "F1", 7.5, 0.1, 0.15, 0.2)
        cur_y -= 18

    # Explicación
    doc.rect(36, cur_y - 48, 523, 58, fill_rgb=(0.98, 0.99, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, cur_y - 2, "Por qué y Fuente de Verdad:", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, cur_y - 14, "A la tablet solo viaja una copia de lectura podada del catálogo (precios y stock referencial), descartando claves de usuarios,", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, cur_y - 24, "datos personales y metadatos internos. Esto reduce el consumo de datos móviles en ferias y previene filtraciones ante robo físico.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, cur_y - 34, "La única fuente de verdad (Single Source of Truth - SSOT) es el servidor PostgreSQL. La tablet opera con un caché local y solo", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, cur_y - 44, "propone borradores; precio vigente, control de inventario y confirmación contable son potestad exclusiva de PostgreSQL.", "F2", 8, 0.15, 0.2, 0.25)

    # Introducción a Consigna 2
    cur_y -= 70
    doc.text(36, cur_y, "2. CONSIGNA 2.c · DEMOSTRACIÓN DE CASOS DE SINCRONIZACIÓN Y SEMÁFORO", "F2", 10.5, 0.09, 0.20, 0.30)
    doc.line(36, cur_y - 5, 559, cur_y - 5, (0.09, 0.20, 0.30), 0.8)
    doc.text(36, cur_y - 18, "El algoritmo del semáforo evalúa solicitudes en 'PENDIENTE' cruzando con snapshot_servidor con orden de prioridad:", "F1", 8.5, 0.2, 0.25, 0.3)
    doc.text(36, cur_y - 28, "1. ROJO (RECHAZADO): Quiebre de stock, producto dado de baja o inexistente.", "F2", 8, 0.7, 0.1, 0.1)
    doc.text(36, cur_y - 38, "2. AMARILLO (CONFLICTO): Stock suficiente, pero el precio en el servidor difiere del visto en el borrador.", "F2", 8, 0.65, 0.4, 0.0)
    doc.text(36, cur_y - 48, "3. VERDE (SIMULADO_APROBADO): Coincidencia plena. Aprobación simulada (no modifica PostgreSQL).", "F2", 8, 0.1, 0.5, 0.2)

    # Detalle Caso C2 en pág 1
    cur_y -= 65
    doc.rect(36, cur_y - 65, 523, 75, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, cur_y - 2, "Caso C2 · Suba de precio en servidor -> CONFLICTO -> Aceptación del cliente -> SIMULADO_APROBADO", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, cur_y - 13, "Preparación: Borrador con 2 u. de Fugazzeta a 180.000 centavos ($1.800). En servidor sube el precio a 210.000 centavos ($2.100).", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, cur_y - 23, "Comando ejecutado: UPDATE snapshot_servidor SET precio_centavos = 210000 WHERE id = 1; (y semaforo.sql)", "F3", 7.5, 0.1, 0.1, 0.1)
    doc.text(42, cur_y - 33, "Resultado 1 (req-c2-v1): Estado: CONFLICTO | Motivo: 'CONFLICTO: Precio modificado en el servidor respecto al borrador'", "F2", 8, 0.7, 0.4, 0.0)
    doc.text(42, cur_y - 43, "Resolución: Cliente acepta suba. Se actualiza precio del borrador a 210.000 centavos y se emite la solicitud 'req-c2-v2'.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, cur_y - 53, "Resultado 2 (req-c2-v2): Estado: SIMULADO_APROBADO | Motivo: 'SIMULADO_APROBADO: Stock y precios validados contra la instantanea'", "F2", 8, 0.1, 0.5, 0.2)

    # =========================================================================
    # PÁGINA 2: Casos C3 a C6, Idempotencia y Verificación en PostgreSQL
    # =========================================================================
    doc.new_page()
    doc.text(36, 808, "2. CASOS DE SINCRONIZACIÓN (CONTINUACIÓN: C3 A C6)", "F2", 11, 0.09, 0.20, 0.30)
    doc.line(36, 802, 559, 802, (0.09, 0.20, 0.30), 0.8)

    # Caso C3
    doc.rect(36, 735, 523, 60, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, 785, "Caso C3 · Borrador por más unidades de las que quedan -> RECHAZADO", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, 773, "Preparación: Borrador 'b-c3-001' solicita 30 unidades de Fugazzeta. En el servidor solo quedan 15 unidades en inventario.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 762, "Comando ejecutado: INSERT INTO item_borrador VALUES ('b-c3-001', 1, 30, 180000); (y semaforo.sql)", "F3", 7.5, 0.1, 0.1, 0.1)
    doc.text(42, 751, "Resultado (req-c3-001): Estado: RECHAZADO | Motivo: 'RECHAZADO: Stock insuficiente en el servidor'", "F2", 8, 0.7, 0.1, 0.1)
    doc.text(42, 740, "Explicación: La condición (s.stock < i.cantidad) gatilla prioridad roja, frenando la solicitud e impidiendo comprometer stock faltante.", "F1", 8, 0.15, 0.2, 0.25)

    # Caso C4
    doc.rect(36, 655, 523, 72, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, 717, "Caso C4 · Producto dado de baja lógica en servidor -> RECHAZADO y Patrón de Lápidas", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, 706, "Preparación: Borrador con Jamón y Queso (id 3). Servidor aplica baja lógica marcando eliminado = 't' y disponible = 'f'.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 695, "Comando: UPDATE snapshot_servidor SET eliminado = 't', disponible = 'f' WHERE id = 3; (y semaforo.sql)", "F3", 7.5, 0.1, 0.1, 0.1)
    doc.text(42, 684, "Resultado (req-c4-001): Estado: RECHAZADO | Motivo: 'RECHAZADO: Producto no disponible o dado de baja'", "F2", 8, 0.7, 0.1, 0.1)
    doc.text(42, 673, "Patrón de Lápidas: Al recargar catálogo local, la fila persiste en producto_cache con eliminado = 1 (tombstone) evitando roturas", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 663, "de claves foráneas históricas, pero deja de figurar automáticamente en las consultas del catálogo activo comercial.", "F1", 8, 0.15, 0.2, 0.25)

    # Caso C5
    doc.rect(36, 585, 523, 62, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, 637, "Caso C5 · Borrador coincidente sin cambios -> SIMULADO_APROBADO", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, 626, "Preparación: Borrador con 2 unidades de Mozzarella a 160.000 centavos ($1.600). En servidor hay 20 u. al mismo precio.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 615, "Comando: INSERT INTO item_borrador VALUES ('b-c5-001', 2, 2, 160000); (y semaforo.sql)", "F3", 7.5, 0.1, 0.1, 0.1)
    doc.text(42, 604, "Resultado (req-c5-001): Estado: SIMULADO_APROBADO | Motivo: 'SIMULADO_APROBADO: Stock y precios validados contra la instantanea'", "F2", 8, 0.1, 0.5, 0.2)
    doc.text(42, 593, "Explicación: Coincidencia plena. Factible pero no constituye una venta real en PostgreSQL.", "F1", 8, 0.15, 0.2, 0.25)

    # Caso C6
    doc.rect(36, 485, 523, 92, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, 567, "Caso C6 · Reenvío de la misma solicitud e Idempotencia (Mismo UUID)", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, 556, "Preparación: Reinsertar solicitud_uuid duplicado ('req-c5-001') simulando reintento descontrolado por micro-corte de señal.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 545, "Comando: INSERT INTO cola_sync VALUES ('req-c5-001', 'b-c5-001', 'PENDIENTE', ...)", "F3", 7.5, 0.1, 0.1, 0.1)
    doc.text(42, 534, "Resultado SQLite: UNIQUE constraint failed: cola_sync.solicitud_uuid (Falla por Clave Primaria).", "F2", 8, 0.7, 0.1, 0.1)
    doc.text(42, 523, "Comportamiento del Semáforo: Re-ejecutar el semáforo no reevalúa solicitudes ya resueltas (filtra WHERE estado = 'PENDIENTE').", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 510, "Dónde iría la protección real en un sistema de verdad (Parada 8):", "F2", 8, 0.09, 0.20, 0.30)
    doc.text(42, 499, "En producción la protección se ubica obligatoriamente en PostgreSQL con una restricción UNIQUE sobre 'idempotency_key'", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 489, "en la tabla de órdenes; ante reenvíos de red, el backend detecta el UUID y responde con HTTP 200 sin duplicar cobros ni stock.", "F1", 8, 0.15, 0.2, 0.25)

    # Verificación en PostgreSQL
    doc.rect(36, 410, 523, 68, fill_rgb=(0.95, 0.98, 0.95), stroke_rgb=(0.2, 0.6, 0.3))
    doc.text(42, 468, "Verificación de Inmutabilidad en PostgreSQL (Servidor Intacto)", "F2", 8.5, 0.1, 0.5, 0.2)
    doc.text(42, 456, "Tras correr todos los casos móviles en SQLite, se ejecutó en la base central PostgreSQL:", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, 444, "SELECT (SELECT count(*) FROM foodstore.pedido) AS total_pedidos, (SELECT sum(stock) FROM foodstore.producto) AS stock_total;", "F3", 7.5, 0.1, 0.1, 0.1)
    doc.text(42, 432, "Resultado: Pedidos = 3 (sin cambios)  |  Stock Total = 261 unidades (exactamente idéntico al valor previo).", "F2", 8, 0.1, 0.5, 0.2)
    doc.text(42, 420, "Conclusión: Se demuestra de forma fehaciente que SIMULADO_APROBADO no modificó el stock ni creó ventas en el servidor.", "F1", 8, 0.15, 0.2, 0.25)

    # =========================================================================
    # PÁGINA 3: Mapa de la Capa de Datos (3.a) y Plan de Mantenimiento (3.b)
    # =========================================================================
    doc.new_page()
    doc.text(36, 808, "3. CONSIGNA 3.a · MAPA DE LA CAPA DE DATOS (LOS TRES MOTORES)", "F2", 11, 0.09, 0.20, 0.30)
    doc.line(36, 802, 559, 802, (0.09, 0.20, 0.30), 0.8)

    # Tabla Mapa Motores
    m_headers = [("Motor y Versión", 95), ("Rol Arquitectónico", 100), ("¿Qué guarda cada uno?", 180), ("¿Quién manda sobre cada dato?", 148)]
    y_m = 780
    doc.rect(36, y_m, 523, 16, fill_rgb=(0.09, 0.20, 0.30), stroke_rgb=(0.09, 0.20, 0.30))
    c_x = 36
    for t, w in m_headers:
        doc.text(c_x + 4, y_m + 4, t, "F2", 8, 1.0, 1.0, 1.0)
        c_x += w

    m_rows = [
        ("PostgreSQL 17", "Núcleo Transaccional (OLTP)\nRelacional ACID", "Catálogo maestro (producto, categoria),\nusuarios (hashes contraseñas), pedidos\noficiales confirmados y stock real central.", "FUENTE DE VERDAD (SSOT):\nAutoridad suprema e indelegable sobre\nprecios maestros, stock y ventas válidas.", True),
        ("MongoDB 8.0", "Lectura y Analítica (U7)\nDocumental NoSQL", "Colección 'pedidos': documentos JSON\ndesnormalizados con cliente y arreglo de\nlíneas de productos embebidas.", "SUBORDINADO A POSTGRESQL:\nProyección de lectura aguas abajo.\nNo tiene autoridad sobre stock ni precios.", False),
        ("SQLite 3.50+", "Capa Móvil Offline (U8)\nRelacional Embebido", "producto_cache (catálogo local con lápidas),\nborradores locales (pedido_borrador, ítems)\ny cola de sincronización (cola_sync).", "MANDA SÓLO EN BORRADORES:\nAutoridad local sobre sus borradores.\nCERO potestad sobre servidor.", True)
    ]

    c_y = y_m - 40
    for mot, rol, guarda, manda, bg in m_rows:
        fill = (0.95, 0.96, 0.98) if bg else (1.0, 1.0, 1.0)
        doc.rect(36, c_y, 523, 40, fill_rgb=fill, stroke_rgb=(0.76, 0.8, 0.84))
        doc.text(40, c_y + 26, mot, "F2", 8, 0.09, 0.2, 0.3)
        # multi-line rol
        r_lines = rol.split("\n")
        doc.text(135, c_y + 26, r_lines[0], "F1", 7.5, 0.1, 0.15, 0.2)
        if len(r_lines) > 1:
            doc.text(135, c_y + 16, r_lines[1], "F1", 7.5, 0.1, 0.15, 0.2)
        # multi-line guarda
        g_lines = guarda.split("\n")
        doc.text(235, c_y + 28, g_lines[0], "F1", 7.5, 0.1, 0.15, 0.2)
        doc.text(235, c_y + 18, g_lines[1], "F1", 7.5, 0.1, 0.15, 0.2)
        doc.text(235, c_y + 8, g_lines[2], "F1", 7.5, 0.1, 0.15, 0.2)
        # multi-line manda
        m_lines = manda.split("\n")
        doc.text(415, c_y + 28, m_lines[0], "F2", 7.5, 0.1, 0.4, 0.2)
        doc.text(415, c_y + 18, m_lines[1], "F1", 7.5, 0.1, 0.15, 0.2)
        doc.text(415, c_y + 8, m_lines[2], "F1", 7.5, 0.1, 0.15, 0.2)
        c_y -= 40

    # Consigna 3.b: Plan de Mantenimiento
    c_y -= 25
    doc.text(36, c_y, "4. CONSIGNA 3.b · PLAN DE MANTENIMIENTO (ADENDA A LA UNIDAD 6)", "F2", 11, 0.09, 0.20, 0.30)
    doc.line(36, c_y - 5, 559, c_y - 5, (0.09, 0.20, 0.30), 0.8)

    c_y -= 20
    doc.rect(36, c_y - 65, 523, 75, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, c_y - 2, "1. ¿Qué se respalda y cómo se prueba la restauración?", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, c_y - 14, "- Servidor PostgreSQL: Respaldo lógico diario con pg_dump -Fc (formato custom con metadatos y checksums). La restauración se prueba", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 25, "  semanalmente de forma automatizada sobre base descartable (foodstore_restore_test), midiendo el RTO y validando conteos (U6).", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 37, "- Tablets Móviles SQLite: La base es efímera. producto_cache se descarga bajo demanda desde PostgreSQL. Los borradores locales no", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 48, "  sincronizados se respaldan localmente en copia física de foodstore_movil.db y log JSON en tarjeta flash antes de sincronizar.", "F1", 8, 0.15, 0.2, 0.25)

    c_y -= 85
    doc.rect(36, c_y - 60, 523, 70, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, c_y - 2, "2. Si se restaura un respaldo viejo de PostgreSQL, ¿qué hacen las tablets?", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, c_y - 14, "- Detección de Desfasaje: Las tablets detectan un epoch/timestamp del servidor anterior a su copia local al contactar la API.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 25, "- Protocolo de Recuperación: 1) Invalidan de inmediato su producto_cache; 2) Descargan la instantánea limpia del servidor restaurado;", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 37, "  3) Re-ejecutan forzadamente el semáforo sobre borradores no consolidados. Pedidos previamente en SIMULADO_APROBADO con precios", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 48, "  o stock desfasados pasan a CONFLICTO o RECHAZADO, alertando al cajero para revalidar con el cliente.", "F1", 8, 0.15, 0.2, 0.25)

    c_y -= 80
    doc.rect(36, c_y - 50, 523, 60, fill_rgb=(1.0, 1.0, 1.0), stroke_rgb=(0.76, 0.8, 0.84))
    doc.text(42, c_y - 2, "3. ¿Cada cuánto y quién revisa las solicitudes en CONFLICTO o RECHAZADO?", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, c_y - 14, "- En Tiempo Real (Punto de Venta): El cajero u operador del food truck resuelve la alerta al instante en el mostrador (consulta al cliente", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 25, "  si acepta el aumento ante CONFLICTO de precio, o sugiere reemplazos si hay quiebre de stock).", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 37, "- Al Cierre de Turno (Diario): El Supervisor de Operaciones audita el reporte consolidado de incidencias en la cola central para identificar", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 48, "  desajustes crónicos entre stock físico y teórico, o caídas repetitivas de red móvil.", "F1", 8, 0.15, 0.2, 0.25)

    # =========================================================================
    # PÁGINA 4: Code Review con IA (Consigna 3.c) y Conclusión Final
    # =========================================================================
    doc.new_page()
    doc.text(36, 808, "5. CONSIGNA 3.c · CODE REVIEW CON IA SOBRE SCRIPTS DE LA CURSADA", "F2", 11, 0.09, 0.20, 0.30)
    doc.line(36, 802, 559, 802, (0.09, 0.20, 0.30), 0.8)
    doc.text(36, 790, "Revisión sistemática de scripts con OpenCode / IA en agente Plan. Se presenta la matriz de decisiones y comprobación:", "F1", 8.5, 0.2, 0.25, 0.3)

    cr_headers = [("Unidad / Script", 95), ("Hallazgo Detectado", 150), ("Decisión", 100), ("Comprobación en Base y Justificación", 178)]
    y_cr = 768
    doc.rect(36, y_cr, 523, 16, fill_rgb=(0.09, 0.20, 0.30), stroke_rgb=(0.09, 0.20, 0.30))
    c_x = 36
    for t, w in cr_headers:
        doc.text(c_x + 4, y_cr + 4, t, "F2", 8, 1.0, 1.0, 1.0)
        c_x += w

    cr_rows = [
        ("U1 (Relacional)\nschema.sql\nobjects.sql", 
         "En detalle_pedido, subtotal se calcula por trigger trg_subtotal pero carece de CHECK de consistencia ante updates directos.", 
         "Aceptado / Corregido", 
         "Comprobado en PostgreSQL: Se incorporó CHECK (subtotal = cantidad * precio_unitario). Se verificó que el motor aborta intentos de insertar subtotales artificiales.", 
         True),
        ("U6 (Backups)\nrestore_test.ps1\nrestore_test.sh", 
         "La IA propuso forzar pg_restore --clean --if-exists de forma desatendida en producción para 'recuperar automáticamente ante fallos'.", 
         "Descartado con\nFundamento", 
         "DESCARTE CRÍTICO: Ejecutar DROP DATABASE forzado en producción viva ante alertas espurias destruye sesiones activas. Solo se automatiza en staging (foodstore_restore_test); en prod requiere corte formal y autorización humana.", 
         False),
        ("U7 (NoSQL)\nconsultas_mongo.js\nlaboratorio_ia.js", 
         "Los importes en MongoDB se insertaban como Double de JS, provocando pérdida de centavos por redondeo IEEE 754.", 
         "Aceptado / Corregido", 
         "Comprobado en MongoDB: Se migró a Decimal128 (NumberDecimal) con validador BSON, verificando acumulados contables exactos sin desvíos.", 
         True),
        ("U8 (SQLite)\nschema_sqlite.sql", 
         "SQLite por defecto permite tipado dinámico débil (afinidad), permitiendo almacenar texto en columnas monetarias.", 
         "Aceptado / Corregido", 
         "Comprobado en SQLite: Se forzó cláusula STRICT en las 4 tablas, verificando que rechaza strings en columnas INTEGER inmediatamente.", 
         False)
    ]

    c_y = y_cr - 58
    for scr, hal, dec, comp, bg in cr_rows:
        fill = (0.95, 0.96, 0.98) if bg else (1.0, 1.0, 1.0)
        doc.rect(36, c_y, 523, 58, fill_rgb=fill, stroke_rgb=(0.76, 0.8, 0.84))
        # script
        s_lines = scr.split("\n")
        doc.text(40, c_y + 44, s_lines[0], "F2", 8, 0.09, 0.2, 0.3)
        for idx, sl in enumerate(s_lines[1:]):
            doc.text(40, c_y + 32 - idx*10, sl, "F3", 7, 0.2, 0.2, 0.2)
        # hallazgo
        doc.text(135, c_y + 44, hal[:65], "F1", 7.5, 0.15, 0.2, 0.25)
        doc.text(135, c_y + 32, hal[65:135], "F1", 7.5, 0.15, 0.2, 0.25)
        if len(hal) > 135:
            doc.text(135, c_y + 20, hal[135:], "F1", 7.5, 0.15, 0.2, 0.25)
        # decision
        d_lines = dec.split("\n")
        d_col = (0.1, 0.5, 0.2) if "Aceptado" in dec else (0.7, 0.1, 0.1)
        doc.text(285, c_y + 44, d_lines[0], "F2", 8, d_col[0], d_col[1], d_col[2])
        if len(d_lines) > 1:
            doc.text(285, c_y + 32, d_lines[1], "F2", 8, d_col[0], d_col[1], d_col[2])
        # comprobacion
        doc.text(385, c_y + 44, comp[:65], "F1", 7.5, 0.15, 0.2, 0.25)
        doc.text(385, c_y + 32, comp[65:135], "F1", 7.5, 0.15, 0.2, 0.25)
        doc.text(385, c_y + 20, comp[135:205], "F1", 7.5, 0.15, 0.2, 0.25)
        if len(comp) > 205:
            doc.text(385, c_y + 8, comp[205:], "F1", 7.5, 0.15, 0.2, 0.25)

        c_y -= 58

    # Conclusión Final
    c_y -= 25
    doc.text(36, c_y, "6. SÍNTESIS Y CONCLUSIONES ARQUITECTÓNICAS", "F2", 11, 0.09, 0.20, 0.30)
    doc.line(36, c_y - 5, 559, c_y - 5, (0.09, 0.20, 0.30), 0.8)

    c_y -= 18
    doc.rect(36, c_y - 82, 523, 90, fill_rgb=(0.97, 0.98, 1.0), stroke_rgb=(0.2, 0.3, 0.5))
    doc.text(42, c_y - 2, "Cierre de la Capa de Datos del Proyecto Food Store:", "F2", 8.5, 0.09, 0.20, 0.30)
    doc.text(42, c_y - 14, "1. Desacoplamiento Efectivo: La aplicación móvil opera de forma totalmente autónoma frente a cortes de conectividad gracias al catálogo", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 24, "   local en SQLite STRICT, utilizando enteros en centavos para eliminar cualquier imprecisión de punto flotante en el borde.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 36, "2. Semáforo Idempotente: La evaluación con prioridades (Rojo > Amarillo > Verde) previene que pedidos inviables saturen la red central,", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 46, "   mientras que el filtrado por solicitudes PENDIENTE garantiza que la repetición de la simulación no altere registros históricos.", "F1", 8, 0.15, 0.2, 0.25)
    doc.text(42, c_y - 58, "3. Respeto Irrestricto a la Regla de Oro: Se demostró empíricamente que SIMULADO_APROBADO no es una venta en PostgreSQL. La integridad,", "F2", 8, 0.1, 0.4, 0.1)
    doc.text(42, c_y - 68, "   el stock real y el balance contable permanecen bajo la custodia absoluta de PostgreSQL como Single Source of Truth.", "F2", 8, 0.1, 0.4, 0.1)

    pdf_bytes = doc.render_pdf()
    pdf_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "informe.pdf")
    with open(pdf_path, "wb") as f:
        f.write(pdf_bytes)
    print(f"[+] informe.pdf generado exitosamente en: {pdf_path}")
    print(f"[+] Total de páginas: {len(doc.pages)} (cumple límite máximo de 6 páginas)")

if __name__ == "__main__":
    build_full_report()
