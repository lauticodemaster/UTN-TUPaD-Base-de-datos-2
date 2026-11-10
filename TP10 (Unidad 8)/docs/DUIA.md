# DUIA — Declaración de Uso de IA (TP Unidad 8)

**Grupo H: Saferazi**  
**Integrantes:** Danilo Serrano, Elio Marí, Daniela Díaz, Jesús Ramírez, Lautaro Fernández  
**Docente:** Carlos Yácomo  
**Asignatura:** Base de Datos II — Tecnicatura Universitaria en Programación (UTN)  
**Ciclo Lectivo:** 2026

---

## 1. Declaración de Cumplimiento

El equipo declara que el presente trabajo práctico fue desarrollado bajo el protocolo de buenas prácticas de la cátedra: **especificar → generar → leer → verificar → decidir**.

Ninguna porción de código, sentencia SQL ni esquema generado por herramientas de Inteligencia Artificial fue incorporado al proyecto sin previa lectura crítica, análisis de impacto y verificación práctica contra los motores de bases de datos involucrados (PostgreSQL 16+ y SQLite 3.50+).

## 2. Inventario de Herramientas Utilizadas

| Herramienta | Versión / Modelo | Rol en el Proceso |
|---|---|---|
| **Kiro** | 1.1.14 | Redacción de especificación formal (`requirements.md` en notación EARS, `design.md`, `tasks.md`). |
| **OpenCode CLI / Assistant** | Muse-Spark / DeepMind Coding Agent | Generación de esqueletos de sentencias DDL, consultas analíticas y simulador de pruebas. |
| **SQLite 3.50+** | CLI / Python 3.14 Built-in | Ejecución de validaciones de integridad (`STRICT`, foreign keys, semáforo). |
| **PostgreSQL 17** | Motor Relacional | Fuente de verdad (SSOT), generación de vista `v_snapshot_movil` y verificación de inmutabilidad. |

## 3. Matriz de Decisiones y Descarte Fundamentado

Bajo el compromiso de no delegar la toma de decisiones técnicas a la IA, se resumen los principales puntos donde la sugerencia fue evaluada críticamente:

| Módulo / Script | Propuesta de la IA | Decisión del Equipo | Justificación Técnica |
|---|---|---|---|
| `schema_sqlite.sql` | Proponer tablas estándar sin cláusula `STRICT` y habilitar tipos flexibles. | **Descartado** | Se forzó la declaración `STRICT` en las 4 tablas para garantizar integridad de dominio e impedir errores de tipado en campos numéricos y monetarios. |
| `schema_sqlite.sql` | Permitir que la tablet apruebe ventas localmente si había stock en cache. | **Descartado** | Viola la Regla de Oro del apunte: *"El móvil propone, el servidor dispone"*. `SIMULADO_APROBADO` nunca es una venta definitiva. |
| `semaforo.sql` | Reevaluar en cada corrida todas las solicitudes anteriores (`CONFLICTO` y `RECHAZADO`). | **Descartado** | Viola el principio de idempotencia y destruye la trazabilidad histórica. El semáforo solo procesa `WHERE estado = 'PENDIENTE'`. |
| `semaforo.sql` | Actualizar el precio automáticamente en el borrador ante diferencias. | **Descartado** | Un aumento de precio requiere la aceptación explícita del consumidor. No se pueden alterar condiciones comerciales unilateralmente. |
| Code Review (U6) | Aplicar `pg_restore --clean --if-exists` de forma desatendida en producción. | **Descartado con Fundamento** | Ejecutar un borrado destructivo automatizado sobre la base viva es un riesgo operacional inaceptable. Las restauraciones automáticas solo van a entornos de staging (`foodstore_restore_test`). |
| Code Review (U7) | Utilizar `Decimal128` en MongoDB en reemplazo de `Double`. | **Aceptado** | Evita la pérdida de centavos por redondeo de punto flotante binario en acumulados contables. |

## 4. Firma y Compromiso

El equipo asume la autoría intelectual del análisis, la defensa oral individual y los resultados presentados en el informe, ratificando que el software fue testeado exhaustivamente.
