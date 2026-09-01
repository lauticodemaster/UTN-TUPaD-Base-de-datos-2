# Protocolo de seguridad para cambios en la base de datos


## 1. Crear y verificar el respaldo

Antes de aplicar cualquier cambio sobre la base de datos, se debe crear una copia de seguridad de la versión actual.

El respaldo se almacena en:

```text
database/backups/
```

Ejemplo:

```text
database/backups/foodstore_backup.sql
```

Desde una terminal de Windows, se puede generar el respaldo utilizando:

```powershell
pg_dump -U postgres -d foodstore > database\backups\foodstore_backup.sql
```

Antes de realizar cambios, se debe verificar que el archivo de respaldo exista y tenga contenido.

Si se utiliza DBeaver, el respaldo también puede crearse mediante:

```text
Base de datos → Tools → Backup
```

El archivo generado debe guardarse dentro de:

```text
database/backups/
```

No se debe aplicar ninguna modificación si no existe un respaldo válido de la base de datos.

---

## 2. Crear una copia de trabajo de la base de datos

Los cambios no deben probarse directamente sobre la base de datos original.

Primero se crea una base de datos de prueba:

```sql
CREATE DATABASE foodstore_test;
```

Luego se restaura el respaldo en la copia de trabajo.

Desde PowerShell:

```powershell
psql -U postgres -d foodstore_test -f database\backups\foodstore_backup.sql
```

La base utilizada para realizar pruebas será:

```text
foodstore_test
```

La base original:

```text
foodstore
```

debe permanecer sin modificaciones durante las pruebas.

Si el respaldo se generó en formato personalizado de PostgreSQL, la restauración debe realizarse con:

```powershell
pg_restore -U postgres -d foodstore_test database\backups\foodstore_backup.dump
```

---


## Flujo obligatorio antes de modificar la base de datos

```text
Base de datos original: foodstore
            │
            ▼
Crear respaldo
database/backups/foodstore_backup.sql
            │
            ▼
Crear base de prueba
foodstore_test
            │
            ▼
Restaurar el respaldo
            │
            ▼
Aplicar cambios en foodstore_test
            │
            ▼
BEGIN
            │
            ▼
Ejecutar pruebas válidas e inválidas
            │
            ▼
COMMIT o ROLLBACK
            │
            ▼
Revisar los resultados
            │
            ▼
Solo entonces aplicar el cambio definitivo
```

---

## Regla de seguridad

Todo cambio en la estructura o los datos de la base de datos debe seguir el siguiente orden:

1. Crear un respaldo de `foodstore`.
2. Crear o restaurar una copia de trabajo llamada `foodstore_test`.
3. Aplicar los cambios primero sobre `foodstore_test`.
4. Ejecutar pruebas con casos válidos e inválidos.
5. Confirmar la transacción únicamente si las pruebas son correctas.
6. Registrar el cambio mediante una migración SQL versionada en Git.
7. Revisar el resultado antes de modificar la base de datos original.

El objetivo de este protocolo es evitar modificaciones accidentales, pérdida de información y cambios no probados en la base de datos principal.
