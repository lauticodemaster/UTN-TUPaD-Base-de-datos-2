# Especificación de Requisitos de Software (SRS) - Módulo Móvil Offline

**Proyecto:** Food Store en la Feria (TP Unidad 8)  
**Herramienta de Especificación:** Kiro  
**Equipo:** Grupo H (Saferazi)  
**Notación:** EARS (Easy Approach to Requirements Syntax)

---

## 1. Contexto y Propósito

El food truck de Food Store opera en una feria gastronómica sin conectividad garantizada a Internet. Para mantener la atención al cliente fluida y sin demoras, la tablet del punto de venta gestiona un catálogo local desacoplado y permite la confección de borradores de pedidos en una base de datos local SQLite.

Bajo la **Regla de Oro**: *"El móvil propone, el servidor dispone"*, la tablet nunca confirma ventas reales ni altera el stock o los precios maestros de PostgreSQL. El presente documento especifica formalmente las reglas de sincronización, validación por semáforo y resiliencia offline.

---

## 2. Requisitos del Sistema (Notación EARS)

### REQ-01: Detección de Discrepancia de Precios (Caso C2)
* **Tipo:** Condicional / Event-driven
* **Requisito:**  
  `WHEN el precio vigente en el snapshot del servidor (snapshot_servidor.precio_centavos) difiere del precio registrado en el borrador (item_borrador.precio_centavos_visto) para cualquier ítem de la solicitud, THE SYSTEM SHALL marcar la solicitud en cola_sync con estado 'CONFLICTO' y motivo descriptivo.`
* **Caso de Prueba Asociado:** **C2**
* **Criterio de Aceptación:** La solicitud no pasa a aprobado hasta que el cliente acepte el nuevo precio, se actualice el borrador y se emita una nueva solicitud de sincronización.

---

### REQ-02: Rechazo por Quiebre de Stock (Caso C3)
* **Tipo:** Comportamiento no deseado / Event-driven
* **Requisito:**  
  `WHEN la cantidad solicitada de un producto (item_borrador.cantidad) sea mayor al stock disponible reportado por el servidor (snapshot_servidor.stock), THE SYSTEM SHALL marcar la solicitud en cola_sync con estado 'RECHAZADO' y motivo 'Stock insuficiente en el servidor'.`
* **Caso de Prueba Asociado:** **C3**
* **Criterio de Aceptación:** La solicitud queda bloqueada impidiendo la confirmación de una venta inviable.

---

### REQ-03: Rechazo por Baja Lógica o No Disponibilidad (Caso C4)
* **Tipo:** Estado / Event-driven
* **Requisito:**  
  `WHEN un producto incluido en el borrador se encuentre marcado como no disponible (disponible = 'f' / 0) o dado de baja (eliminado = 't' / 1) en el snapshot del servidor, THE SYSTEM SHALL marcar la solicitud en cola_sync como 'RECHAZADO' y al refrescar el catálogo local SHALL mantener la fila como lápida (tombstone) con eliminado = 1 excluyéndola de las búsquedas activas.`
* **Caso de Prueba Asociado:** **C4**
* **Criterio de Aceptación:** Los ítems eliminados no se borran físicamente (evitando errores de clave foránea en borradores históricos) pero dejan de ofrecerse al público.

---

### REQ-04: Idempotencia y Prevención de Solicitudes Duplicadas (Caso C6)
* **Tipo:** Ubicuo / Restricción de Integridad
* **Requisito:**  
  `THE SYSTEM SHALL garantizar que cada solicitud de sincronización posea un identificador único global (solicitud_uuid como PRIMARY KEY), bloqueando con error de unicidad cualquier reenvío con el mismo UUID y evitando que el evaluador del semáforo reexamine solicitudes cuyo estado no sea 'PENDIENTE'.`
* **Caso de Prueba Asociado:** **C6**
* **Criterio de Aceptación:** Repetir la ejecución del script de sincronización sobre una solicitud resuelta produce exactamente el mismo estado sin duplicar registros ni alterar contadores.

---

### REQ-05: Autonomía de Consulta del Catálogo Offline (Caso C1)
* **Tipo:** Estado / Ubicuo
* **Requisito:**  
  `WHILE la tablet se encuentre desconectada de la red, THE SYSTEM SHALL permitir la consulta ágil de productos filtrando exclusivamente aquellos con disponible = 1, eliminado = 0 y stock_visto > 0 a partir de producto_cache.`
* **Caso de Prueba Asociado:** **C1**
* **Criterio de Aceptación:** Tiempo de respuesta inmediato e independencia total de PostgreSQL.

---

### REQ-06: Aprobación Simulada de Borradores Válidos (Caso C5)
* **Tipo:** Event-driven
* **Requisito:**  
  `WHEN todos los ítems de una solicitud pendiente coincidan exactamente en precio con el servidor y su cantidad sea menor o igual al stock disponible, THE SYSTEM SHALL marcar la solicitud como 'SIMULADO_APROBADO'.`
* **Caso de Prueba Asociado:** **C5**
* **Criterio de Aceptación:** Estado verde en cola_sync, manteniendo intacto el estado del servidor PostgreSQL (ninguna venta generada en el backend).

---

### REQ-07: Integridad Referencial y Dominio Estricto (Caso C7)
* **Tipo:** Restricción de Integridad / STRICT
* **Requisito:**  
  `THE SYSTEM SHALL impedir la inserción de ítems con cantidad menor o igual a cero (CHECK cantidad > 0) o referencias a productos inexistentes (FOREIGN KEY producto_id), revirtiendo la transacción y dejando la base de datos sin filas huérfanas.`
* **Caso de Prueba Asociado:** **C7**
* **Criterio de Aceptación:** Violaciones de restricción lanzan excepción SQLite y no persisten datos.
