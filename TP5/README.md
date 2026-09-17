# TP5 — Unidad 3, Semana 5: índices, vistas y vistas materializadas

**Materia:** Base de Datos II — Tecnicatura Universitaria en Programación (UTN, 2pro1)
**Docente:** Carlos Yácomo
**Grupo H: Saferazi** — Danilo Serrano, Elio Marí, Daniela Díaz, Jesús Ramírez y Lautaro Fernández.

Proyecto integrador **Food Store**. Este trabajo **no modifica el modelo de datos ni las
consultas heredadas**: sólo agrega objetos (índices, vistas y una vista materializada) sobre
el esquema de `TP1/`.

---

## Contenido

```
TP5/
├── indices.sql               Parte A — los CREATE INDEX aceptados, comentados
├── views.sql                 Partes B y C — vista de seguridad + vista materializada
├── specs/                    las especificaciones (una por objeto)
├── duia.md                   bitácora de uso de IA: qué se propuso, qué se aceptó, qué se descartó
├── duia_logs/                transcripciones crudas de cada corrida del agente
├── informe_mediciones.md     EXPLAIN ANALYZE antes/después, costo de escritura, Parte C
├── mediciones/               los scripts con los que se midió y se verificó
│   ├── carga_escritura.sql        costo de los índices sobre las escrituras
│   ├── verificacion_vistas.sql    equivalencia de cada vista contra la consulta manual
│   ├── verificacion_seguridad.sql pruebas de la vista sin la columna contrasena
│   └── medicion_matview.sql       materializada vs. consulta original, y costo del REFRESH
└── README.md                 este archivo
```

Archivos heredados que se usan como punto de partida y **no se tocan**: `TP1/schema.sql`,
`TP1/data.sql`, `TP1/objects.sql`, `TP1/queries.sql`.

---

## Cómo reproducir las pruebas

### 1. Base de datos

PostgreSQL 16 o superior. Las mediciones publicadas se hicieron sobre **PostgreSQL 17.6**.

Se trabaja siempre sobre una copia llamada `foodstore_test`, **nunca sobre `foodstore`**
directo (protocolo de seguridad de la cátedra, `TP1/protocolo_seguridad.md`).

```bash
createdb foodstore_test
psql -d foodstore_test -c "CREATE SCHEMA foodstore;"
```

### 2. Cargar el esquema heredado

El orden importa: `data.sql` depende del trigger `trg_subtotal` que define `objects.sql`.

```bash
psql -d foodstore_test -f TP1/schema.sql
psql -d foodstore_test -f TP1/objects.sql
psql -d foodstore_test -f TP1/data.sql
```

### 3. Ampliar el volumen

Con los datos de ejemplo de `data.sql` **las diferencias de plan no se ven**: PostgreSQL
elige `Seq Scan` sobre cualquier tabla chica y hace bien. Hay que correr la carga masiva de
la Semana 3:

```bash
psql -d foodstore_test -f "TP3/Parte-1/carga_masiva_productos.sql"
psql -d foodstore_test -f "TP3/Parte-1/carga_masiva_usuarios_pedidos.sql"
```

Volumen resultante, que es sobre el que se midió:

| Tabla | Filas |
|---|---:|
| `categoria` | 5 |
| `producto` | 50.012 |
| `usuario` | 20.005 |
| `pedido` | 200.003 |
| `detalle_pedido` | 800.008 |

### 4. Normalizar el punto de partida

Si la base viene de haber corrido la **Parte 4 del TP4**, tiene tres índices *covering* que
eran de aquella competencia y no del esquema del proyecto. Hay que sacarlos, o el "antes" de
este trabajo queda contaminado:

```sql
SET search_path TO foodstore;
DROP INDEX IF EXISTS idx_dp_cov_facturacion;
DROP INDEX IF EXISTS idx_pedido_cov_fecha;
DROP INDEX IF EXISTS idx_producto_cov_categoria;
```

Deben quedar exactamente estos índices no-únicos:
`idx_producto_categoria_id`, `idx_pedido_usuario_id`, `idx_producto_no_eliminado`
(de `schema.sql`), `idx_detalle_pedido_producto_id` e `idx_pedido_fecha` (del TP3).

### 5. Medir el ANTES

```sql
SET search_path TO foodstore;
VACUUM (ANALYZE) categoria;
VACUUM (ANALYZE) producto;
VACUUM (ANALYZE) usuario;
VACUUM (ANALYZE) pedido;
VACUUM (ANALYZE) detalle_pedido;
```

El `VACUUM` no es cosmético: después de una carga masiva el *visibility map* queda vacío, y
sin él ningún `Index Only Scan` puede evitar ir al heap.

Después, correr con `EXPLAIN (ANALYZE, BUFFERS)` las tres consultas de `TP1/queries.sql` que
se indexan (analíticas **A**, **C** y **D**) y la analítica **B** de la Parte C. Los planes
esperados están en `informe_mediciones.md`.

Costo de escritura antes de los índices:

```bash
psql -d foodstore_test -f TP5/mediciones/carga_escritura.sql
```

> **Correr cada medición tres veces y tomar la mediana.** La primera corrida mide caché frío,
> no el plan. El script de escritura revierte su propia transacción: no deja datos.

### 6. Crear los objetos

```bash
psql -d foodstore_test -f TP5/indices.sql
psql -d foodstore_test -f TP5/views.sql
```

`indices.sql` termina con el `VACUUM (ANALYZE)` que hace falta para que los índices nuevos
puedan usarse como *index only*.

### 7. Medir el DESPUÉS y verificar

```bash
# mismas consultas del paso 5, con EXPLAIN (ANALYZE, BUFFERS)
psql -d foodstore_test -f TP5/mediciones/carga_escritura.sql        # escritura después
psql -d foodstore_test -f TP5/mediciones/verificacion_vistas.sql    # equivalencia de las vistas
psql -d foodstore_test -f TP5/mediciones/verificacion_seguridad.sql # vista sin contrasena
psql -d foodstore_test -f TP5/mediciones/medicion_matview.sql       # Parte C
```

**Salidas esperadas:**

- `verificacion_vistas.sql`: **0 filas** en las cinco diferencias simétricas, `coinciden = t`
  en los cinco `COUNT`, y **0 pedidos descuadrados**.
- `verificacion_seguridad.sql`: tienen que aparecer **dos errores**, y que aparezcan es el
  resultado correcto — `column "contrasena" does not exist` y
  `permission denied for table usuario`.

---

## Una nota sobre `random_page_cost`

Dos de los tres índices de la Parte A **no los elige el planificador con la configuración por
defecto**, aunque midiéndolo el plan por índice sea más rápido. El motivo es que
`random_page_cost = 4` describe un disco rígido de platos: le dice al planificador que leer
una página de índice cuesta cuatro veces más que leer una secuencial, lo cual es falso en un
SSD.

Para reproducir los números de la columna "con `rpc = 1.1`" del informe, alcanza con hacerlo
**a nivel de sesión**:

```sql
SET random_page_cost = 1.1;
```

No se dejó puesto a nivel de base porque no es un objeto de este trabajo: es una decisión de
configuración del servidor que corresponde tomar mirando el hardware real de producción. Está
medido y documentado en `informe_mediciones.md` §1.3, con la validación de
`enable_seqscan = off` que prueba que el plan por índice es genuinamente el mejor y no un
artefacto del costo estimado.

---

## Resultados

| Consulta / reporte | Antes | Después | Mejora |
|---|---:|---:|---|
| Top 5 productos más vendidos | 258,9 ms | 222,9 ms | −13,9 % (12,5× menos buffers) |
| Ranking de usuarios por gasto | 135,1 ms | 106,1 ms | −21,5 % |
| Pedidos sobre el promedio | 82,9 ms | 29,1 ms | **−65 %** |
| Facturación por categoría y mes | 279,8 ms | **0,025 ms** | **≈ 11.000×** |
| Carga de 500 `INSERT` | 99,8 ms | 137,8 ms | +38 % (el precio de los índices) |

El detalle, los planes completos y la justificación de cada decisión están en
[`informe_mediciones.md`](informe_mediciones.md); el registro del trabajo con las
herramientas, en [`duia.md`](duia.md).
