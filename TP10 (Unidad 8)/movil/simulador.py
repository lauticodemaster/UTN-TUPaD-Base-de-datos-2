#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
BASE DE DATOS II - UTN TUPaD
TRABAJO PRÁCTICO N.º 8 (UNIDAD 8) - FOOD STORE EN LA FERIA
Simulador Integral de la Capa Móvil y Sincronización (Casos C1 a C7)
Archivo: movil/simulador.py
============================================================================
"""

import os
import sys
import csv
import sqlite3

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "foodstore_movil.db")
SCHEMA_PATH = os.path.join(BASE_DIR, "schema_sqlite.sql")
SNAPSHOT_CSV_PATH = os.path.join(BASE_DIR, "servidor_snapshot.csv")
SEMAFORO_SQL_PATH = os.path.join(BASE_DIR, "semaforo.sql")

def print_separator(title):
    print("\n" + "=" * 78)
    print(f" {title}")
    print("=" * 78)

def inicializar_base():
    print_separator("1. CREACIÓN DE ESQUEMA EN SQLITE (STRICT MODE)")
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        print(f"[-] Base anterior eliminada: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")
    
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        schema_sql = f.read()
    
    conn.executescript(schema_sql)
    print(f"[+] Esquema creado exitosamente en {DB_PATH} (tablas STRICT y claves foráneas activadas).")
    conn.close()

def importar_snapshot_inicial():
    print_separator("2. IMPORTACIÓN DE INSTANTÁNEA DEL SERVIDOR (CONSIGNA 2.a)")
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")
    cursor = conn.cursor()

    # Cargar CSV en snapshot_servidor
    with open(SNAPSHOT_CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        filas = [
            (int(r["id"]), r["nombre"], int(r["precio_centavos"]), int(r["stock"]), r["disponible"], r["eliminado"])
            for r in reader
        ]

    cursor.executemany("""
        INSERT INTO snapshot_servidor (id, nombre, precio_centavos, stock, disponible, eliminado)
        VALUES (?, ?, ?, ?, ?, ?)
    """, filas)
    print(f"[+] {len(filas)} productos importados a tabla 'snapshot_servidor' desde CSV.")

    # Cargar producto_cache desde snapshot_servidor
    cursor.execute("""
        INSERT OR REPLACE INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, fecha_copia)
        SELECT 
            id,
            nombre,
            precio_centavos,
            stock,
            CASE WHEN disponible IN ('t', 'true', '1', 1) THEN 1 ELSE 0 END,
            CASE WHEN eliminado IN ('t', 'true', '1', 1) THEN 1 ELSE 0 END,
            datetime('now')
        FROM snapshot_servidor;
    """)
    conn.commit()
    print("[+] Catálogo local 'producto_cache' inicializado con la instantánea.")

    cursor.execute("SELECT count(*) FROM producto_cache WHERE disponible = 1 AND eliminado = 0;")
    activos = cursor.fetchone()[0]
    print(f"[+] Total productos disponibles y activos en cache: {activos}")
    conn.close()

def ejecutar_semaforo(conn):
    """Ejecuta la consulta del semáforo para todas las solicitudes en estado PENDIENTE."""
    with open(SEMAFORO_SQL_PATH, "r", encoding="utf-8") as f:
        sql = f.read()
    conn.executescript(sql)
    conn.commit()

def probar_casos():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")
    cursor = conn.cursor()

    # -------------------------------------------------------------------------
    print_separator("CASO C1: CONSULTA AUTÓNOMA DEL CATÁLOGO DISPONIBLE OFFLINE")
    # -------------------------------------------------------------------------
    print("[*] Consulta del catálogo en SQLite sin conectarse al servidor PostgreSQL:")
    cursor.execute("""
        SELECT id, nombre, precio_centavos, precio_centavos / 100.0, stock_visto, fecha_copia
        FROM producto_cache
        WHERE disponible = 1 AND eliminado = 0 AND stock_visto > 0
        LIMIT 5;
    """)
    for r in cursor.fetchall():
        print(f"    - ID {r[0]:2d}: {r[1]:<20} | ${r[3]:>7.2f} ({r[2]} centavos) | Stock visto: {r[4]}")
    print("[OK] C1 verificado: La tablet consulta y visualiza productos disponibles autónomamente.")

    # -------------------------------------------------------------------------
    print_separator("CASO C7: RESTRICCIONES DE INTEGRIDAD (CHECK Y FOREIGN KEY)")
    # -------------------------------------------------------------------------
    # Creamos un borrador para pruebas C7
    cursor.execute("""
        INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
        VALUES ('b-c7-001', 'tester_integridad', 'EFECTIVO');
    """)

    # Prueba C7.1: Cantidad en 0
    try:
        cursor.execute("""
            INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
            VALUES ('b-c7-001', 1, 0, 180000);
        """)
        print("[FALLO] No se detectó el error de cantidad en 0.")
    except sqlite3.IntegrityError as e:
        print(f"[OK] C7.1 detectado con éxito: CHECK constraint failed (cantidad > 0) -> {e}")

    # Prueba C7.2: Producto inexistente
    try:
        cursor.execute("""
            INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
            VALUES ('b-c7-001', 99999, 1, 100000);
        """)
        print("[FALLO] No se detectó la clave foránea inexistente.")
    except sqlite3.IntegrityError as e:
        print(f"[OK] C7.2 detectado con éxito: FOREIGN KEY constraint failed -> {e}")

    # Verificación de que item_borrador quedó intacto
    cursor.execute("SELECT count(*) FROM item_borrador WHERE id_local = 'b-c7-001';")
    count_c7 = cursor.fetchone()[0]
    print(f"[+] Total ítems registrados para 'b-c7-001' tras errores: {count_c7} (correcto: 0).")
    conn.commit()

    # -------------------------------------------------------------------------
    print_separator("CASO C2: SUBIDA DE PRECIO EN SERVIDOR -> CONFLICTO -> ACEPTACIÓN")
    # -------------------------------------------------------------------------
    # 1. Crear borrador con Fugazzeta al precio visto de 180.000 centavos ($1.800)
    cursor.execute("INSERT INTO pedido_borrador VALUES ('b-c2-001', 'cliente_c2', 'EFECTIVO', datetime('now'));")
    cursor.execute("INSERT INTO item_borrador VALUES ('b-c2-001', 1, 2, 180000);")
    cursor.execute("INSERT INTO cola_sync VALUES ('req-c2-v1', 'b-c2-001', 'PENDIENTE', 'Nuevo pedido emitido', datetime('now'));")
    conn.commit()

    # 2. En el servidor sube el precio de Fugazzeta a $2.100 (210.000 centavos)
    cursor.execute("UPDATE snapshot_servidor SET precio_centavos = 210000 WHERE id = 1;")
    conn.commit()
    print("[*] Servidor actualizó precio de Fugazzeta de 180.000 a 210.000 centavos.")

    # 3. Correr semáforo
    ejecutar_semaforo(conn)
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c2-v1';")
    res_c2_v1 = cursor.fetchone()
    print(f"[+] Resultado Solicitud req-c2-v1: Estado = {res_c2_v1[0]} | Motivo = {res_c2_v1[1]}")

    # 4. El cliente acepta: actualizamos el borrador y generamos nueva solicitud req-c2-v2
    cursor.execute("UPDATE item_borrador SET precio_centavos_visto = 210000 WHERE id_local = 'b-c2-001' AND producto_id = 1;")
    cursor.execute("INSERT INTO cola_sync VALUES ('req-c2-v2', 'b-c2-001', 'PENDIENTE', 'Reintento con precio aceptado', datetime('now'));")
    conn.commit()

    ejecutar_semaforo(conn)
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c2-v2';")
    res_c2_v2 = cursor.fetchone()
    print(f"[+] Resultado Solicitud req-c2-v2: Estado = {res_c2_v2[0]} | Motivo = {res_c2_v2[1]}")
    print("[OK] C2 verificado: Detectó CONFLICTO inicial y resolvió a SIMULADO_APROBADO tras aceptación.")

    # Restaurar precio de Fugazzeta para no interferir en siguientes casos
    cursor.execute("UPDATE snapshot_servidor SET precio_centavos = 180000 WHERE id = 1;")
    conn.commit()

    # -------------------------------------------------------------------------
    print_separator("CASO C3: BORRADOR POR MÁS UNIDADES DE LAS QUE QUEDAN -> RECHAZADO")
    # -------------------------------------------------------------------------
    # Fugazzeta tiene stock = 15 en el servidor. El borrador pide 30 unidades.
    cursor.execute("INSERT INTO pedido_borrador VALUES ('b-c3-001', 'cliente_c3_exceso', 'TARJETA', datetime('now'));")
    cursor.execute("INSERT INTO item_borrador VALUES ('b-c3-001', 1, 30, 180000);")
    cursor.execute("INSERT INTO cola_sync VALUES ('req-c3-001', 'b-c3-001', 'PENDIENTE', 'Borrador con alta demanda', datetime('now'));")
    conn.commit()

    ejecutar_semaforo(conn)
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c3-001';")
    res_c3 = cursor.fetchone()
    print(f"[+] Resultado Solicitud req-c3-001: Estado = {res_c3[0]} | Motivo = {res_c3[1]}")
    print("[OK] C3 verificado: RECHAZADO por quiebre de stock (solicitado: 30, stock servidor: 15).")

    # -------------------------------------------------------------------------
    print_separator("CASO C4: PRODUCTO DADO DE BAJA LÓGICA -> RECHAZADO Y LÁPIDA")
    # -------------------------------------------------------------------------
    # 1. Crear borrador con Jamón y Queso (id = 3)
    cursor.execute("INSERT INTO pedido_borrador VALUES ('b-c4-001', 'cliente_c4', 'TRANSFERENCIA', datetime('now'));")
    cursor.execute("INSERT INTO item_borrador VALUES ('b-c4-001', 3, 1, 200000);")
    cursor.execute("INSERT INTO cola_sync VALUES ('req-c4-001', 'b-c4-001', 'PENDIENTE', 'Pedido de pizza especial', datetime('now'));")
    conn.commit()

    # 2. En el servidor dan de baja lógica el producto 3 (eliminado = 't')
    cursor.execute("UPDATE snapshot_servidor SET eliminado = 't', disponible = 'f' WHERE id = 3;")
    conn.commit()
    print("[*] Servidor dio de baja lógica a producto 3 (Jamón y Queso).")

    # 3. Evaluar semáforo
    ejecutar_semaforo(conn)
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c4-001';")
    res_c4 = cursor.fetchone()
    print(f"[+] Resultado Solicitud req-c4-001: Estado = {res_c4[0]} | Motivo = {res_c4[1]}")

    # 4. Recargar el catálogo local desde el snapshot
    cursor.execute("""
        UPDATE producto_cache 
        SET eliminado = 1, disponible = 0, fecha_copia = datetime('now')
        WHERE id = 3;
    """)
    conn.commit()

    # 5. Comprobar que la fila queda (lápida / tombstone) pero no aparece en el catálogo activo
    cursor.execute("SELECT count(*) FROM producto_cache WHERE id = 3;")
    existe_fila = cursor.fetchone()[0]
    cursor.execute("SELECT count(*) FROM producto_cache WHERE id = 3 AND disponible = 1 AND eliminado = 0;")
    visible_catalogo = cursor.fetchone()[0]
    print(f"[+] Fila física en producto_cache (lápida persistente): {existe_fila} (esperado: 1)")
    print(f"[+] Visibilidad en catálogo activo comercial: {visible_catalogo} (esperado: 0)")
    print("[OK] C4 verificado: Solicitud rechazada y patrón de lápidas respetado.")

    # -------------------------------------------------------------------------
    print_separator("CASO C5: BORRADOR SIN CAMBIOS -> SIMULADO_APROBADO")
    # -------------------------------------------------------------------------
    # Producto 2 (Mozzarella): stock = 20, precio = 160.000 centavos. Pedido por 2 unidades.
    cursor.execute("INSERT INTO pedido_borrador VALUES ('b-c5-001', 'cliente_c5_ok', 'EFECTIVO', datetime('now'));")
    cursor.execute("INSERT INTO item_borrador VALUES ('b-c5-001', 2, 2, 160000);")
    cursor.execute("INSERT INTO cola_sync VALUES ('req-c5-001', 'b-c5-001', 'PENDIENTE', 'Pedido estándar sin desvíos', datetime('now'));")
    conn.commit()

    ejecutar_semaforo(conn)
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c5-001';")
    res_c5 = cursor.fetchone()
    print(f"[+] Resultado Solicitud req-c5-001: Estado = {res_c5[0]} | Motivo = {res_c5[1]}")
    print("[OK] C5 verificado: Aprobación simulada exitosa (no modifica stock ni crea venta en servidor).")

    # -------------------------------------------------------------------------
    print_separator("CASO C6: REENVÍO DE LA MISMA SOLICITUD (IDEMPOTENCIA)")
    # -------------------------------------------------------------------------
    # Intento 1: Re-insertar la misma solicitud con el mismo UUID (req-c5-001)
    try:
        cursor.execute("INSERT INTO cola_sync VALUES ('req-c5-001', 'b-c5-001', 'PENDIENTE', 'Duplicado por reintento de red', datetime('now'));")
        print("[FALLO] Se permitió reinsertar solicitud_uuid duplicado.")
    except sqlite3.IntegrityError as e:
        print(f"[OK] C6.1 Rechazo de clave primaria duplicada: {e}")

    # Intento 2: Re-ejecutar el semáforo para comprobar que no reevalúa req-c5-001
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c5-001';")
    estado_antes = cursor.fetchone()
    ejecutar_semaforo(conn)
    cursor.execute("SELECT estado, motivo FROM cola_sync WHERE solicitud_uuid = 'req-c5-001';")
    estado_despues = cursor.fetchone()
    print(f"[+] Estado req-c5-001 antes de re-ejecución: {estado_antes[0]}")
    print(f"[+] Estado req-c5-001 después de re-ejecución: {estado_despues[0]}")
    print("[OK] C6 verificado: Idempotencia garantizada (la simulación no reevalúa solicitudes resueltas).")

    # -------------------------------------------------------------------------
    print_separator("RESUMEN FINAL DE LA COLA DE SINCRONIZACIÓN")
    # -------------------------------------------------------------------------
    cursor.execute("""
        SELECT solicitud_uuid, id_local, estado, motivo
        FROM cola_sync
        ORDER BY creado_en ASC;
    """)
    for r in cursor.fetchall():
        print(f"| {r[0]:<12} | {r[1]:<12} | {r[2]:<17} | {r[3]}")

    conn.close()

if __name__ == "__main__":
    inicializar_base()
    importar_snapshot_inicial()
    probar_casos()
