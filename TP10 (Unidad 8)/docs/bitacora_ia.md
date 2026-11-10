# Bitácora de Uso de Inteligencia Artificial

**Proyecto:** Food Store en la Feria (TP Unidad 8)  
**Grupo H (Saferazi):** Danilo Serrano, Elio Marí, Daniela Díaz, Jesús Ramírez, Lautaro Fernández  
**Herramientas:** Kiro 1.1.14 / OpenCode CLI / Antigravity Assistant

---

## Entrada 1: Especificación del Esquema Móvil en SQLite y Restricciones STRICT

* **Qué se le pidió a la IA:**  
  Generar el script `schema_sqlite.sql` para SQLite 3.37+ que contenga las tablas `producto_cache`, `pedido_borrador`, `item_borrador` y `cola_sync`, respetando la regla de foreign keys activas, almacenamiento de precios en centavos enteros y tipos estrictos.

* **Qué sugirió la IA:**  
  1. Sugirió definir `precio_centavos` como `INTEGER NOT NULL CHECK (precio_centavos >= 0)` en tablas `STRICT`.
  2. Sugirió agregar una tabla `pago_transaccion` adicional para registrar intentos de cobro con pasarelas de pago externas.
  3. Sugirió que la tablet pudiera auto-asignar `estado = 'CONFIRMADO'` si el stock local era mayor a 5 unidades.

* **Qué se aceptó:**  
  Se aceptó el esquema con cláusulas `STRICT`, `PRAGMA foreign_keys = ON;`, enteros en centavos y claves compuestas para `item_borrador`.

* **Qué se descartó y por qué:**  
  - **Descarte de tabla de pagos externa:** No es parte del alcance del TP y agregaba complejidad innecesaria.
  - **Descarte de confirmación local de ventas:** Violación flagrante de la Regla de Oro del apunte (*"El móvil propone, el servidor dispone"*). La tablet **nunca** confirma ventas ni modifica el stock del servidor; solo puede emitir un estado `SIMULADO_APROBADO` local como borrador factible.

---

## Entrada 2: Lógica de Resolución del Semáforo y Manejo de Conflictos

* **Qué se le pidió a la IA:**  
  Diseñar la consulta SQL para `semaforo.sql` que evalúe solicitudes pendientes cruzando los borradores locales con `snapshot_servidor`, clasificando en ROJO (RECHAZADO), AMARILLO (CONFLICTO) y VERDE (SIMULADO_APROBADO).

* **Qué sugirió la IA:**  
  1. Utilizar un `UPDATE ... FROM ...` con agregación condicional mediante `CASE WHEN` y `SUM(...) > 0` agrupando por `solicitud_uuid`.
  2. Sugirió evaluar tanto las solicitudes `PENDIENTE` como las solicitudes en `CONFLICTO` y `RECHAZADO` en cada pasada para "ver si el servidor ya tiene stock nuevamente".
  3. Sugirió auto-actualizar el precio del borrador al precio del servidor en caso de conflicto sin intervención del usuario.

* **Qué se aceptó:**  
  Se aceptó la estructura del `UPDATE ... FROM` agrupado con orden de prelación: Rojo (stock insuficiente o producto dado de baja) prevalece sobre Amarillo (cambio de precio), y si no hay desvíos pasa a Verde.

* **Qué se descartó y por qué:**  
  - **Descarte de reevaluación de resueltos:** Si la simulación reevalúa solicitudes en `CONFLICTO` o `RECHAZADO`, se rompe la idempotencia y se altera el historial de auditoría de la tablet. Solo deben evaluarse las solicitudes con `estado = 'PENDIENTE'`.
  - **Descarte de auto-actualización silenciosa de precios:** En un punto de venta, si un producto sube de precio el cliente tiene derecho a decidir si desea comprarlo o no. Modificar el precio en el borrador automáticamente sin consentimiento del cliente viola las reglas del negocio gastronómico.

---

## Entrada 3: Code Review Multi-Unidad y Procedimiento de Restauración

* **Qué se le pidió a la IA:**  
  Revisar los scripts de cursada de las Unidades 1, 6 y 7, proponiendo mejoras de robustez, concurrencia y mantenimiento.

* **Qué sugirió la IA:**  
  1. En Unidad 7 (MongoDB): reemplazar tipos numéricos `Double` de JavaScript por `Decimal128` en importes contables.
  2. En Unidad 1 (PostgreSQL): agregar validación estricta de coherencia entre `subtotal` y `cantidad * precio_unitario`.
  3. En Unidad 6 (PostgreSQL): automatizar el script de restauración en producción añadiendo los modificadores `--clean --if-exists` sin confirmación humana previa.

* **Qué se aceptó:**  
  Se aceptaron las observaciones de tipos monetarios en MongoDB (`Decimal128`) y la restricción de consistencia en el esquema relacional.

* **Qué se descartó y por qué (Descarte con Fundamento):**  
  Se descartó rotundamente la automatización ciega de `pg_restore --clean` sobre el ambiente de producción. Forzar la eliminación de la base operativa ante una alerta de backup sin aislar sesiones activas ni requerir confirmación manual de un DBA senior puede destruir transacciones recientes legítimas y provocar un desastre operacional severo. La restauración automatizada debe restringirse estrictamente a bases de staging descartables (`foodstore_restore_test`).
