# Informe TP Unidad 4 — FNBC y desnormalización controlada en Food Store

| Entregable | Archivo |
|---|---|
| Parte 1 (esquema original, instancia, descomposición, vista, migración verificada) | [`sql/tp_fnbc_control_lote.sql`](sql/tp_fnbc_control_lote.sql) |
| Plan de reversión de la migración | [`sql/rollback_fnbc_control_lote.sql`](sql/rollback_fnbc_control_lote.sql) |
| Parte 2 (estructura, sincronización, consulta d, auditoría e) | [`sql/tp_desnormalizacion_top_categorias.sql`](sql/tp_desnormalizacion_top_categorias.sql) |
| Auditoría aislada / pruebas de sincronización | [`sql/auditoria_venta_categoria_dia.sql`](sql/auditoria_venta_categoria_dia.sql), [`sql/pruebas_sincronizacion_vcd.sql`](sql/pruebas_sincronizacion_vcd.sql) |
| Spec Kiro | [`specs/kiro/`](specs/kiro/) (requirements, design, tasks) |
| Teoría a)–f) | [`Parte-1/parte1_a_b.md`](Parte-1/parte1_a_b.md), [`ejercicio4.2_parte2/u4_tp_4.2_p2.md`](ejercicio4.2_parte2/u4_tp_4.2_p2.md) |
| Salidas reales | [`evidencias/`](evidencias/) |

**Entorno de prueba.** PostgreSQL 18.6 (cumple «16+»), base `foodstore` cargada con
`TP01/schema.sql`, `objects.sql`, `data.sql` y la carga masiva de TP03 (50.012 productos,
20.005 usuarios, 200.003 pedidos, 400.008 detalles). Respaldo previo con `pg_dump -Fc`
(6 MB, 1,1 s) y todo el trabajo sobre la copia `foodstore_test`, como pide
`TP01/protocolo_seguridad.md`.

---

## 1. Parte 1 — FNBC (resumen; el desarrollo formal está en los .md de teoría)

- FD: F1 `{LoteID, DepositoID} → ResponsableControlID`, F2 `ResponsableControlID → DepositoID`.
- Claves candidatas: `{LoteID, DepositoID}` y `{LoteID, ResponsableControlID}`; los tres atributos son primos (por eso cumple 3FN pero no FNBC).
- Violación: F2, porque `ResponsableControlID` no es superclave.
- Descomposición: `responsable_deposito(responsable_control_id PK, deposito_id)` y `control_lote(lote_id, responsable_control_id)`.
- Sin pérdida: el atributo común es clave de `responsable_deposito`.

**Más allá de lo pedido (salvaguardas):**
1. **Las FD se validan contra los datos reales** dentro de la transacción: si algún responsable aparece con dos depósitos, la migración aborta.
2. **La FD que no se preserva (F1) se restituye con un trigger**: sin él, un lote podría tener dos responsables del mismo depósito.
3. **El esquema heredado no se borra**: convive con el nuevo y existe un script de reversión.

### Cómo se probó (`evidencias/salida_fnbc_migracion.txt`)
| Prueba | Resultado |
|---|---|
| Migración en una transacción con verificación previa al COMMIT | `original=3 vista=3 perdidas=0 espurias=0` → COMMIT |
| Alta del responsable 803 sin lote (anomalía de inserción) | 1 fila, revertida |
| Mover 801 de depósito (anomalía de actualización) | 1 UPDATE cambia los 2 lotes en la vista |
| Segundo responsable del depósito 30 para el lote 501 | rechazado por el trigger F1 |
| Reversión después del COMMIT | quedan 3 filas en `control_lote_almacen`, no queda ningún objeto nuevo |
| Re-migración después de la reversión | vuelve a pasar la verificación |
| **Camino de aborto**: dato sucio `(503,30,802)` que viola F2 | `ERROR: F2 ... migración abortada`; no se creó ningún objeto y quedan las 4 filas originales |

---

## 2. Parte 2 — Top 5 de categorías del día

### a) Línea base (`evidencias/explain_antes.txt`)
Consulta 5.1 sobre 400.008 detalles / 200.003 pedidos (570 pedidos del día).
**Tiempo de ejecución: ~25–27 ms** (4 de 5 corridas; hubo un pico aislado de 150 ms).
**Nodo dominante:** `Parallel Seq Scan on pedido` (6,2 de ~7,8 ms por worker; descarta
66.478 filas por worker para quedarse con 190), seguido de 570 `Index Scan` sobre
`detalle_pedido`. Lee 6.286 buffers para devolver 5 filas.

### b) Patrón elegido y justificación
Se eligió una **tabla resumen mantenida por disparadores** (`venta_categoria_dia`) y no
una vista materializada. En (a) se ve que el costo lo explica recorrer `pedido` entero y
unir 1.142 detalles para devolver 5 filas, y eso pasa varias veces por minuto. Una vista
materializada repetiría ese recorrido en cada `REFRESH` y, entre un refresco y otro,
mostraría datos viejos, cuando el panel pide tiempo real. **Sincronización:** triggers
AFTER ROW que aplican el *delta* en la misma transacción que la escritura de la fuente
(alta, cambio y baja de detalle; cambio de fecha y baja de pedido; cambio de categoría de
producto), con upsert para soportar concurrencia y TRUNCATE prohibido. Si la transacción
de negocio se revierte, el resumen se revierte con ella. **Reversible sin pérdida:** sí.
La fuente de verdad (`detalle_pedido.subtotal`) no se modifica, así que basta con hacer
DROP de la tabla y los triggers (bloque 4 del script), y la tabla se puede reconstruir en
cualquier momento con su `INSERT … SELECT` inicial.

### c) Implementación
`sql/tp_desnormalizacion_top_categorias.sql`: carga inicial de 733 celdas (día × categoría).

### d) Antes / después (`evidencias/explain_antes.txt`, `explain_despues.txt`)
| | Antes (4 tablas) | Después (`venta_categoria_dia`) |
|---|---|---|
| Tiempo de ejecución | **26,99 ms** (corridas: 25,3 / 24,9 / 150,0 / 26,7) | **0,128 ms** (corridas: 0,160 / 0,134 / 0,139) |
| Nodo dominante | `Parallel Seq Scan on pedido` + Nested Loop con Index Scan en `detalle_pedido` | `Bitmap Index Scan on pk_venta_categoria_dia` (fecha = hoy) |
| Buffers leídos | 6.286 | 10 |
| Resultado | Bebidas 1.236.848,83 · Postres 1.212.002,32 · Pizzas 5.200 · Empanadas 730 · Ensaladas 500 | **idéntico** |

Mejora de ~200×. El costo se traslada a las escrituras: cada línea de detalle hace una
búsqueda por PK en `pedido` y otra en `producto`, más un upsert.

### e) Auditoría (`evidencias/salida_desnormalizacion.txt`)
`sql/auditoria_venta_categoria_dia.sql` sobre la base migrada: **0 filas**.
Además se probaron 7 casos de sincronización dentro de una transacción revertida (alta,
cambio de cantidad, baja de línea, cambio de fecha del pedido, baja del pedido, cambio de
categoría, TRUNCATE rechazado), y la auditoría dio 0 filas después de cada uno. Hubo
también un **control negativo**: se corrompió a mano una celda (+1) y la auditoría la
detectó (`5550.00` contra `5551.00`), lo que demuestra que un resultado vacío no es vacío
por accidente.

---

## 3. Decisiones de desnormalización documentadas (objetivo 3 del TPI)
| Estructura | Cuándo | Por qué | Salvaguardas |
|---|---|---|---|
| `venta_categoria_dia` (U4) | Reporte del panel en tiempo real | 27 ms → 0,13 ms, medido | Triggers por delta en la misma transacción, TRUNCATE prohibido, auditoría con control negativo, reversible con DROP |
| `mv_facturacion_categoria_mes` (TP05) | Reporte mensual, tolera desfasaje | Recorre 800k detalles para 29 filas | `REFRESH` programado, índice único para `CONCURRENTLY` |
| `pedido.total`, `detalle_pedido.subtotal` (TP01) | Desde el diseño inicial | Se lee en cada listado de pedidos | Triggers `trg_subtotal` y `trg_total_*`; `calcular_total_pedido()` como fuente de verdad |

## 4. Limitaciones conocidas
- La fecha del día se toma de `CURRENT_DATE` del servidor (en el clúster de prueba, UTC).
- La sincronización por delta no cubre cambios hechos con `session_replication_role = replica` (los triggers no se disparan). Para ese caso está la auditoría.

## 5. DUIA — Unidad 4
| Herramienta | Finalidad | Prompt / spec | Aceptado / descartado |
|---|---|---|---|
| Claude Code (Claude Opus 5.5) | Redactar la spec en formato Kiro, los scripts de migración, reversión y desnormalización, y ejecutarlos en un clúster local descartable | Spec `specs/kiro/*` + consigna de `TP_U4.pdf` | Se aceptó la tabla resumen con triggers. Se descartó la vista materializada (no cumple el requisito de tiempo real). Se agregaron, por revisión, la validación de F2 sobre los datos, el trigger de F1, la prohibición de TRUNCATE y el control negativo de la auditoría |

Solo se usaron datos sintéticos (carga masiva de TP03); no se envió a la IA ningún dato personal.
