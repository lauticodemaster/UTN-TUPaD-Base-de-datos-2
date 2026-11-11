# Requirements — Migración FNBC `control_lote_almacen` y desnormalización `venta_categoria_dia`

> Spec en formato Kiro (requirements / design / tasks). Redactada con asistencia de IA
> (ver DUIA en `../../informe_u4.md` §5) y revisada por el equipo antes de escribir SQL.

## Introducción
Food Store tiene un esquema heredado (`control_lote_almacen`) que viola FNBC y un reporte
de panel (top 5 categorías del día) que recorre cuatro tablas muchas veces por minuto.
Se necesita (1) llevar el esquema heredado a FNBC sin perder datos y con posibilidad de
volver atrás, y (2) introducir una redundancia controlada y auditable para el reporte.

## Requisito 1 — Validación de dependencias funcionales sobre datos reales
**Historia:** Como DBA, quiero verificar que los datos cumplen las FD antes de descomponer,
para no perder información por una FD que el enunciado afirma pero los datos no respetan.

**Criterios de aceptación (EARS)**
1. CUANDO se ejecute la migración, el sistema DEBERÁ comprobar que
   `responsable_control_id → deposito_id` se cumple en todas las filas.
2. SI existe al menos un responsable con más de un depósito, ENTONCES el sistema DEBERÁ
   abortar la migración completa y dejar la base sin cambios.

## Requisito 2 — Descomposición FNBC
1. El sistema DEBERÁ crear `responsable_deposito(responsable_control_id PK, deposito_id)`
   y `control_lote(lote_id, responsable_control_id)` con PK y FK.
2. El sistema DEBERÁ proveer `v_control_lote_almacen` que reconstruya la relación original
   por reunión natural.
3. Como la descomposición no preserva `{lote, deposito} → responsable`, el sistema DEBERÁ
   rechazar, mediante trigger, un segundo responsable del mismo depósito para un mismo lote.

## Requisito 3 — Migración sin pérdida y reversible
1. La migración DEBERÁ ejecutarse en una única transacción.
2. ANTES del COMMIT, el sistema DEBERÁ verificar con `EXCEPT` en ambos sentidos y conteo
   que vista y original son idénticos; SI difieren, ENTONCES DEBERÁ abortar.
3. La migración NO DEBERÁ eliminar ni modificar `control_lote_almacen` (convivencia).
4. DEBERÁ existir un script de reversión que, tras un COMMIT, devuelva la base al
   esquema heredado sin pérdida, abortando si detecta conflictos.
5. Todo DEBERÁ probarse primero en `foodstore_test` con respaldo previo de `foodstore`.

## Requisito 4 — Desnormalización controlada del top 5 diario
1. El reporte DEBERÁ poder resolverse sin recorrer `detalle_pedido` ni `pedido`.
2. El dato redundante DEBERÁ mantenerse sincronizado en la misma transacción que la
   escritura de la fuente (INSERT/UPDATE/DELETE de detalle, cambio de fecha o baja de
   pedido, cambio de categoría de producto).
3. SI se intenta TRUNCATE sobre la fuente, ENTONCES el sistema DEBERÁ rechazarlo.
4. DEBERÁ existir un script de auditoría cuyo resultado sea vacío cuando hay
   sincronización, y que detecte una corrupción deliberada (control negativo).
5. La estructura DEBERÁ ser eliminable sin pérdida de información (la fuente de verdad
   no se modifica).
