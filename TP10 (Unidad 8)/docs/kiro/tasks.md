# Plan de Tareas de Implementación (Tasks)

**Proyecto:** Food Store en la Feria - Módulo Móvil Offline  
**Herramienta:** Kiro  
**Equipo:** Grupo H (Saferazi)

---

## Tareas

- [x] **TASK-01: Definición de Esquema SQLite (`schema_sqlite.sql`)**
  - Activar claves foráneas (`PRAGMA foreign_keys = ON;`).
  - Crear las cuatro tablas requeridas (`producto_cache`, `pedido_borrador`, `item_borrador`, `cola_sync`) con cláusula `STRICT`.
  - Crear tabla de importación auxiliar `snapshot_servidor`.
  - Configurar restricciones de chequeo (`CHECK`), claves primarias y foráneas con eliminación en cascada donde corresponda.

- [x] **TASK-02: Pruebas Iniciales de Esquema e Integridad (`pruebas_sqlite.sql`)**
  - Probar inserción transaccional de borrador completo mediante bloque `BEGIN ... COMMIT`.
  - Probar cancelación y reversión limpia mediante `BEGIN ... ROLLBACK`.
  - Implementar consulta autónoma del catálogo offline (**Caso C1**).
  - Validar disparadores de error ante cantidad en 0 y producto inexistente (**Caso C7**).

- [x] **TASK-03: Generación e Importación de la Instantánea (`servidor_snapshot.csv`)**
  - Definir vista `v_snapshot_movil` en PostgreSQL con conversión de precios a centavos enteros.
  - Exportar catálogo de prueba a CSV con encabezados.
  - Diseñar procedimiento de carga masiva en SQLite hacia `snapshot_servidor` y propagación a `producto_cache`.

- [x] **TASK-04: Implementación del Motor Semáforo (`semaforo.sql` / `simulador.py`)**
  - Escribir consulta agregada con priorización: Rojo (RECHAZADO) > Amarillo (CONFLICTO) > Verde (SIMULADO_APROBADO).
  - Filtrar rigurosamente solo solicitudes en estado `PENDIENTE`.
  - Construir simulador automatizado en Python para reproducir con trazabilidad los casos **C2, C3, C4, C5 y C6**.

- [x] **TASK-05: Elaboración del Mapa de Capa de Datos y Mantenimiento**
  - Mapear responsabilidades, entidades y fuentes de verdad de PostgreSQL, MongoDB y SQLite.
  - Redactar adenda al plan de mantenimiento de la Unidad 6 (respaldos de tablet, desfasaje por restore de servidor y revisión de incidencias).
  - Ejecutar revisión de código con IA (Code Review) sobre scripts de cursada, documentando decisiones con al menos un descarte justificado.

- [x] **TASK-06: Documentación de Uso de IA y Trazabilidad**
  - Redactar bitácora de interacción (`bitacora_ia.md`) con prompts, propuestas aceptadas y descartadas.
  - Formalizar la Declaración de Uso de IA (`DUIA.md`) bajo lineamientos de la cátedra.

- [x] **TASK-07: Compilación del Informe Final y README**
  - Diseñar `informe.html` maquetado profesionalmente (máximo 6 páginas).
  - Exportar a `informe.pdf` mediante Chromium / Edge headless.
  - Generar `README.md` con instrucciones de reproducción paso a paso.
