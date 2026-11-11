# Design — Migración FNBC y desnormalización controlada

## 1. FNBC sobre `control_lote_almacen`
- FD: F1 `{LoteID, DepositoID} → ResponsableControlID`; F2 `ResponsableControlID → DepositoID`.
- Claves candidatas: `{LoteID, DepositoID}` y `{LoteID, ResponsableControlID}`.
- F2 viola FNBC: su determinante no es superclave. Descomposición sobre F2:
  - R1 `responsable_deposito(responsable_control_id PK, deposito_id)`
  - R2 `control_lote(lote_id, responsable_control_id)` PK compuesta
- Sin pérdida (Heath): el atributo común `responsable_control_id` es clave de R1.
- Pérdida de preservación de F1 → trigger `trg_chk_f1_control_lote` (BEFORE INSERT/UPDATE).

### Flujo de la migración (una transacción)
```
BEGIN
 ├─ validar F2 en datos ──(falla)──► RAISE → ROLLBACK automático
 ├─ CREATE R1, R2, trigger F1, vista
 ├─ INSERT R1 (DISTINCT), INSERT R2
 ├─ verificar EXCEPT ambos sentidos + conteos ──(falla)──► RAISE → ROLLBACK
COMMIT
```

### Plan de reversión
| Situación | Acción |
|---|---|
| Falla antes del COMMIT | Nada que hacer: PostgreSQL revierte la transacción |
| Problema después del COMMIT | `rollback_fnbc_control_lote.sql`: re-sincroniza altas nuevas hacia el esquema heredado (aborta ante conflicto), elimina vista, trigger y tablas nuevas |
| Desastre | Restaurar el respaldo previo (`pg_restore`, procedimiento de U6) |

El esquema heredado se conserva durante la convivencia; se eliminará en una migración
posterior, recién con la aplicación leyendo de la vista/las tablas nuevas.

## 2. Desnormalización `venta_categoria_dia`
- Patrón: tabla resumen `(fecha, categoria_id) → total_vendido`, PK compuesta, índice
  `(fecha, total_vendido DESC)`.
- Sincronización por triggers AFTER ROW, por **delta** (no recalcula todo):
  - `detalle_pedido` INSERT/UPDATE/DELETE → resta OLD vigente, suma NEW vigente.
  - `pedido` UPDATE OF fecha, eliminado → mueve el total del pedido entre celdas.
  - `producto` UPDATE OF categoria_id → mueve sus ventas entre categorías.
  - TRUNCATE de `detalle_pedido`/`pedido` → prohibido.
- Upsert `ON CONFLICT DO UPDATE` para la primera venta del día de una categoría.
- Alternativa descartada: vista materializada (ver informe §2.b).
- Reversión: DROP de triggers, funciones y tabla; la fuente no cambia.
- Auditoría: FULL JOIN entre el recálculo desde la fuente y la tabla resumen.
