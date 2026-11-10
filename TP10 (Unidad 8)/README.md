# TP Unidad 8 — Food Store en la Feria: La Base de la Tablet y el Cierre de la Capa de Datos

**Trabajo Práctico N.º 8 (Unidad 8 - Semanas 12 y 13)**  
**Asignatura:** Base de Datos II — Tecnicatura Universitaria en Programación (UTN)  
**Docente:** Carlos Yácomo  
**Grupo H: Saferazi**  
*Integrantes:* Danilo Serrano, Elio Marí, Daniela Díaz, Jesús Ramírez, Lautaro Fernández  

---

## 📌 De qué se trata

El food truck de Food Store atiende en una feria al aire libre con conectividad intermitente o nula. Este trabajo práctico resuelve el desacoplamiento y la resiliencia offline de la capa de datos:
1. **Base local en la tablet (SQLite 3.37+ STRICT):** Maneja un catálogo local en cache (`producto_cache`), permite armar borradores de pedidos (`pedido_borrador`, `item_borrador`) y registrar solicitudes en cola (`cola_sync`).
2. **Sincronización mediante el Semáforo (PostgreSQL ↔ SQLite):** Exporta una instantánea (`v_snapshot_movil` a CSV) y evalúa mediante reglas de negocio priorizadas:
   - 🔴 **Rojo (RECHAZADO):** Falta de stock, producto dado de baja o inexistente.
   - 🟡 **Amarillo (CONFLICTO):** El precio en el servidor cambió respecto al borrador.
   - 🟢 **Verde (SIMULADO_APROBADO):** Coincidencia total (factible, no confirma venta en el servidor).
3. **Cierre arquitectónico de la materia:** Mapa consolidado de los 3 motores (PostgreSQL, MongoDB y SQLite), adenda al plan de mantenimiento y Code Review con IA sobre los scripts de la cursada.

> **Regla de Oro:**  
> *El móvil propone, el servidor dispone. La tablet solo consulta y arma borradores. Precio, stock y ventas los decide PostgreSQL.*

---

## 📂 Estructura de Entregables

```text
TP10 (Unidad 8)/
├── README.md                           # Guía completa y orden de reproducción
├── movil/
│   ├── schema_sqlite.sql               # Consigna 1.b: DDL SQLite en modo STRICT
│   ├── pruebas_sqlite.sql              # Consigna 1.c: Transacciones, Caso C1 y Caso C7
│   ├── semaforo.sql                    # Consigna 2.b: Algoritmo SQL del semáforo
│   ├── servidor_snapshot.csv           # Consigna 2.a: Exportación CSV de la vista del servidor
│   ├── foodstore_movil.db              # Base SQLite funcional y poblada con los casos
│   └── simulador.py                    # Suite automatizada de pruebas y simulación (C1 a C7)
└── docs/
    ├── informe.pdf                     # Informe final de entrega (máx. 6 páginas)
    ├── informe.html                    # Fuente HTML del informe para renderizado PDF
    ├── informe.md                      # Versión Markdown completa para lectura en GitHub
    ├── bitacora_ia.md                  # Consigna 4.b: Registro de interacción con IA
    ├── DUIA.md                         # Consigna 4.b: Declaración oficial de uso de IA
    └── kiro/                           # Consigna 4.a: Especificación en Kiro
        ├── requirements.md             # Requisitos funcionales en notación EARS
        ├── design.md                   # Diseño técnico y arquitectura del módulo móvil
        └── tasks.md                    # Plan de tareas de implementación
```

---

## 🚀 Cómo reproducir paso a paso

### Opción 1: Ejecución integral automatizada con Python (Recomendada)
Desde la raíz del repositorio, ejecutar:
```bash
python "TP10 (Unidad 8)/movil/simulador.py"
```
Este script:
1. Recrea la base `foodstore_movil.db` aplicando `schema_sqlite.sql`.
2. Importa la instantánea desde `servidor_snapshot.csv` y refresca `producto_cache`.
3. Ejecuta las pruebas de integridad (Caso C1 y restricciones de Caso C7).
4. Ejecuta de forma secuencial y documentada los escenarios **C2, C3, C4, C5 y C6**.
5. Muestra la tabla final de auditoría en la terminal.

---

### Opción 2: Ejecución manual con la CLI de SQLite (`sqlite3`)

1. **Crear el esquema:**
   ```bash
   sqlite3 "TP10 (Unidad 8)/movil/foodstore_movil.db" < "TP10 (Unidad 8)/movil/schema_sqlite.sql"
   ```

2. **Importar la instantánea exportada de PostgreSQL:**
   ```bash
   sqlite3 "TP10 (Unidad 8)/movil/foodstore_movil.db"
   ```
   Dentro de `sqlite3`:
   ```sql
   .mode csv
   .import --skip 1 "TP10 (Unidad 8)/movil/servidor_snapshot.csv" snapshot_servidor

   -- Cargar producto_cache desde snapshot_servidor:
   INSERT OR REPLACE INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, fecha_copia)
   SELECT 
       id, nombre, precio_centavos, stock,
       CASE WHEN disponible IN ('t', 'true', '1', 1) THEN 1 ELSE 0 END,
       CASE WHEN eliminado IN ('t', 'true', '1', 1) THEN 1 ELSE 0 END,
       CURRENT_TIMESTAMP
   FROM snapshot_servidor;
   ```

3. **Ejecutar las pruebas de transacciones y restricciones:**
   ```bash
   sqlite3 "TP10 (Unidad 8)/movil/foodstore_movil.db" < "TP10 (Unidad 8)/movil/pruebas_sqlite.sql"
   ```

4. **Ejecutar el semáforo:**
   ```bash
   sqlite3 "TP10 (Unidad 8)/movil/foodstore_movil.db" < "TP10 (Unidad 8)/movil/semaforo.sql"
   ```

---

## 🧪 Casos de Prueba Implementados

| Caso | Qué se probó | Resultado Obtenido |
|---|---|---|
| **C1** | Consulta del catálogo comercial en modo desconectado. | **OK:** Muestra productos con `disponible = 1`, `eliminado = 0` y `stock_visto > 0`. |
| **C2** | Suba de precio en el servidor posterior a la creación del borrador. | **CONFLICTO:** Se detecta la diferencia de precio. Tras aceptación del cliente y reenvío con nuevo precio, resulta en `SIMULADO_APROBADO`. |
| **C3** | Solicitud que supera el stock disponible en el servidor. | **RECHAZADO:** Falla por stock insuficiente (pide 30, hay 15). |
| **C4** | Producto dado de baja lógica (`eliminado = 't'`) en el servidor. | **RECHAZADO:** La solicitud se rechaza; al recargar el catálogo, la fila física permanece como lápida pero deja de verse en el catálogo comercial activo. |
| **C5** | Borrador válido con stock y precios idénticos al servidor. | **SIMULADO_APROBADO:** Pasa a verde sin alterar nada en PostgreSQL. |
| **C6** | Reenvío de la misma solicitud con el mismo UUID. | **IDEMPOTENCIA:** La base rechaza la clave primaria duplicada (`solicitud_uuid`) y re-ejecutar el semáforo no reevalúa filas ya procesadas. |
| **C7** | Violaciones de dominio (cantidad = 0 y producto inexistente). | **INTEGRIDAD:** Se disparan las restricciones `CHECK` y `FOREIGN KEY` de SQLite STRICT sin persistir filas corruptas. |

---

## 🎤 Ensayo de Defensa Oral (10 Minutos)

Para la defensa individual en la clase de la semana 13:

1. **Bloque 1: Mapa de la Capa de Datos (3 min)**  
   - Explicar la división de responsabilidades: PostgreSQL es la fuente de verdad (SSOT) para stock, precios maestros y ventas.
   - MongoDB es una vista desnormalizada de pedidos para lectura ágil y analítica.
   - SQLite es una base embebida y descartable en la tablet que opera con borradores locales y previene ventas inválidas mediante el semáforo.

2. **Bloque 2: Demostración de un Caso en Vivo (4 min)**  
   - Ejecutar en vivo el **Caso C2** o **Caso C4** mediante `simulador.py`.
   - Mostrar cómo el semáforo detecta la discrepancia antes de que el pedido llegue al servidor.
   - Demostrar que en PostgreSQL el stock y el contador de pedidos se mantuvieron inmutables tras todas las operaciones de la tablet.

3. **Bloque 3: Hallazgo de la IA y Descarte Crítico (3 min)**  
   - Compartir el hallazgo del Code Review sobre la Unidad 6: la IA propuso incluir `--clean --if-exists` de forma desatendida en el script de restauración sobre producción.
   - Fundamentar por qué se **descartó**: ejecutar un `DROP DATABASE` o limpieza forzada sin validación de bloqueos ni aislamiento previo de conexiones activas es una irresponsabilidad que destruiría transacciones concurrentes legítimas.
