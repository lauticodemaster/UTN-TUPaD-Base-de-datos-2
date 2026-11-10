# Ejercicio 4.2, parte 2.
## C) Determinar si `control_lote_almacen` cumple o no la FNBC.
El esquema dado en el ejemplo no cumple con la FNBC, puesto que `deposito_id`, parte de la clave primaria, en realidad depende funcionalmente de `responsable_control_id` (recordemos que, de acuerdo al contexto proporcionado, el responsable de control pertenece a un único depósito), el cual `control_lote_almacen` afirma erróneamente que es dependiente de `deposito_id`. Esta mala implementación es notoria en la inserción de datos, que muestra cómo el responsable 802 está asignado a más de un lote, por lo que su valor no es único en la tabla y `responsable_control_id` no es una superclave.

## D) Anomalías habilitadas por la violación del ejemplo.
- **Inserción:** No se puede registrar a un nuevo responsable de control junto con su depósito asignado (por ejemplo, un nuevo responsable 803 que trabaja en el depósito 32) hasta que no controle efectivamente un lote, ya que el campo `lote_id` es parte de la clave primaria y no admite valores nulos.
- **Borrado:** Si se elimina el registro correspondiente al lote 503 (la tupla con valores 503, 31, 802) porque su control finalizó o se canceló, se perderá permanentemente la información de que el responsable 802 pertenece al depósito 31, borrando un dato maestro de personal de manera involuntaria.
- **Actualización:** Si el responsable 801 fuese reasignado a otro depósito (o si hubo un error de carga y debe corregirse), será necesario modificar múltiples registros simultáneamente (actualmente los de los lotes 501 y 502). Si la actualización falla y solo se modifica un registro, la base de datos quedará inconsistente, indicando que el responsable 801 pertenece a dos depósitos distintos.

## E) Descomposición sin pérdida.
Por algoritmo con violatoria R->D: R1={R,D}, R2={L,R}.

-- R1: dato maestro responsable->deposito.

    CREATE TABLE responsable_deposito(
      responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
      deposito_id BIGINT NOT NULL REFERENCES deposito(id),
      PRIMARY KEY(responsable_control_id)
    );

-- R2: hecho operativo lote-responsable.

    CREATE TABLE control_lote(
      lote_id BIGINT NOT NULL REFERENCES lote(id),
      responsable_control_id BIGINT NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
      PRIMARY KEY(lote_id, responsable_control_id)
    );

-- Vista compatibilidad: reconstruye original por reunión natural.

    CREATE OR REPLACE VIEW v_control_lote_almacen AS
    SELECT cl.lote_id, rd.deposito_id, cl.responsable_control_id
    FROM control_lote cl
    JOIN responsable_deposito rd
      ON cl.responsable_control_id = rd.responsable_control_id;
    lote(id), deposito(id) se asumen existentes; usuario(id) existe en Food Store.

## F) Sin pérdida y migración.

    Teorema de Heath: R->{R1,R2} es sin pérdida ssi el atributo común es superclave de algún Ri.
    Común = responsable_control_id, que es PK —luego superclave— de R1(responsable_deposito).
    Por tanto R1 ⋈ R2 reconstruye exactamente R sin tuplas espurias ni pérdidas.

-- Maestras mínimas para ejemplo (si no existen).

    INSERT INTO lote(id) VALUES (501),(502),(503) ON CONFLICT DO NOTHING;
    INSERT INTO deposito(id) VALUES (30),(31) ON CONFLICT DO NOTHING;

-- R1: un registro por responsable.

    INSERT INTO responsable_deposito(responsable_control_id,deposito_id) VALUES
     (801,30),(802,31) ON CONFLICT DO NOTHING;

-- R2: un registro por (lote,responsable).

    INSERT INTO control_lote(lote_id,responsable_control_id) VALUES
     (501,801),(502,801),(503,802) ON CONFLICT DO NOTHING;

-- Verificación equivalencia

    SELECT * FROM v_control_lote_almacen ORDER BY lote_id;

-- Debe devolver las 3 tuplas originales (501,30,801),(502,30,801),(503,31,802).
Efecto: 803->32 se inserta solo en R1; borrar un lote solo toca R2; cambiar depósito de 801 es una sola fila en R1.
