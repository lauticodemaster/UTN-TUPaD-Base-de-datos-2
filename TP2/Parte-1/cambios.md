# Cambios - Implementación restricciones.md

Script de validación para aplicar las 4 reglas de negocio sobre el esquema `foodstore`.
Ejecutar después de `schema.sql` / `objects.sql` / `data.sql`.

```sql
SET search_path TO foodstore;

-- ============================================================
-- Validación previa: verificar que el seed actual cumple
-- (las 4 consultas deben devolver 0 filas)
-- ============================================================
SELECT * FROM usuario WHERE char_length(trim(mail)) = 0 OR mail NOT LIKE '%@%' OR (char_length(mail) - char_length(replace(mail,'@',''))) <> 1;
SELECT * FROM usuario WHERE celular IS NOT NULL AND celular !~ '^[0-9]+$';
SELECT * FROM producto WHERE precio <= 0;
SELECT * FROM usuario WHERE char_length(contrasena) < 8;

-- ============================================================
-- R1 - restricciones.md:1
-- usuario.mail no puede ser vacío y debe contener exactamente un @
-- Estado actual schema.sql:41 mail VARCHAR(160) NOT NULL UNIQUE sin CHECK
-- ============================================================
ALTER TABLE usuario
  ADD CONSTRAINT chk_usuario_mail_no_vacio
  CHECK (char_length(trim(mail)) > 0);


-- Alternativa estricta email completo:
 ALTER TABLE usuario ADD CONSTRAINT chk_usuario_mail_formato
   CHECK (mail ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- ============================================================
-- R2 - restricciones.md:3
-- usuario.celular solo números
-- Estado actual schema.sql:42 celular VARCHAR(10) nullable sin CHECK
-- Permite NULL (usuario sin celular) pero si tiene valor solo dígitos
-- ============================================================
ALTER TABLE usuario
  ADD CONSTRAINT chk_usuario_celular_solo_numeros
  CHECK (celular IS NULL OR celular ~ '^[0-9]+$');
-- Si se exige exactamente 10 dígitos (coherente con VARCHAR(10) y seed):
-- CHECK (celular IS NULL OR celular ~ '^[0-9]{10}$')

-- ============================================================
-- R3 - restricciones.md:5
-- producto.precio > 0 (actual schema.sql:27 es >= 0)
-- Se añade constraint más estricto; el >=0 existente queda redundante
-- Si se quiere reemplazar, dropear el anterior primero:
-- ALTER TABLE producto DROP CONSTRAINT producto_precio_check; -- nombre autogenerado, verificar con \d producto
-- ============================================================
ALTER TABLE producto
  ADD CONSTRAINT chk_producto_precio_positivo
  CHECK (precio > 0);

-- ============================================================
-- R4 - restricciones.md:7
-- usuario.contrasena al menos 8 caracteres
-- Estado actual schema.sql:43 contrasena VARCHAR(255) NOT NULL sin CHECK
-- ============================================================
ALTER TABLE usuario
  ADD CONSTRAINT chk_usuario_contrasena_min8
  CHECK (char_length(contrasena) >= 8);
```

## Verificación por regla

```sql
-- R1 debe fallar
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1a','','pass1234'); -- vacío
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1b','   ','pass1234'); -- solo espacios
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1c','sinarroba.com','pass1234'); -- sin @
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1d','doble@@test.com','pass1234'); -- dos @
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1e','a@b@c.com','pass1234'); -- dos @
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1f','@test.com','pass1234'); -- vacío a la izq, sigue contando 1 pero falla si usa regex ^[^@]+@

-- R1 debe pasar
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1ok','test@ok.com','pass1234');
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R1ok2','a@b.com','pass1234'); -- exactamente un @

-- R2 debe fallar
INSERT INTO usuario(nombre,apellido,mail,celular,contrasena) VALUES ('Test','R2a','r2a@test.com','261abc1234','pass1234');
INSERT INTO usuario(nombre,apellido,mail,celular,contrasena) VALUES ('Test','R2b','r2b@test.com','261-123456','pass1234');

-- R2 debe pasar (NULL permitido y solo dígitos)
INSERT INTO usuario(nombre,apellido,mail,celular,contrasena) VALUES ('Test','R2c','r2c@test.com',NULL,'pass1234');
INSERT INTO usuario(nombre,apellido,mail,celular,contrasena) VALUES ('Test','R2d','r2d@test.com','2613649945','pass1234');

-- R3 debe fallar
INSERT INTO producto(nombre,precio,stock,categoria_id) VALUES ('TestPrecio0',0,5,1);
INSERT INTO producto(nombre,precio,stock,categoria_id) VALUES ('TestPrecioNeg',-10,5,1);
UPDATE producto SET precio = 0 WHERE id = 1;

-- R3 debe pasar
INSERT INTO producto(nombre,precio,stock,categoria_id) VALUES ('TestPrecioOK',0.01,5,1);

-- R4 debe fallar
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R4a','r4a@test.com','1234567'); -- 7 chars
UPDATE usuario SET contrasena = 'corta' WHERE id = 1;

-- R4 debe pasar
INSERT INTO usuario(nombre,apellido,mail,contrasena) VALUES ('Test','R4b','r4b@test.com','12345678');
```
