## DUIA 

| Campo | Completar |
| --- | --- |
| Herramienta | Se utilizó OpenCode con el modelo de Muse Spark 1.2 en su modo plan y build |
| Spec o prompt utilizado | Revisa el esquema SQL actual del proyecto y las restricciones ubicada en el archivo restricciones.md. No modifiques ningun archivo. Generá únicamente un plan detallado para implementar las reglas de negocio indicadas, incluyendo el archivo que deberia modificarse, la restricción SQL propuesta y las pruebas necesarias para validar la regla |
| Qué generó | Generó el siguiente plan de ejecución:<br/>1. Validar seed sin violar: ejecutar las 4 SELECT de verificación arriba antes de alterar.<br/>2. Aplicar cambios en schema.sql:18-70 (4 líneas) — preferible recrear DB de prueba; si es en caliente usar bloque ALTER TABLE con transacción.<br/>3. Re-ejecutar data.sql y transacciones.sql:91-107 (ya prueba CHECK de cantidad/precio) para regresión.<br/>4. Ejecutar batería de pruebas positivas/negativas por regla (usar DO $$ EXCEPTION WHEN check_violation como en transacciones.sql:92 para no abortar suite).<br/>5. Verificar que objects.sql:43-58 fn_set_subtotal no inserte precio_unitario=0 (ahora bloqueado por R3 si viene de producto). |
| Qué se aceptó | Se aceptaron la mayoría de los cambios realizados pero se pidió modificar uno en específico |
| Qué se modificó o descartó, y por que | Se pidió modificar la regla de negocio en la que un email no puede estar vacío y debe contener @, la modificación fue que la restricción permitía poner mas de un @, así que se le pidió modificar esa restricción para que sea mas completa la validación del mail |
| Verificación realizada | Se probaron todos los cambios propuestos por la IA (en el script cambios.md) en una base de datos de prueba, y una vez confirmado que funciona correctamente se aplicaron en la base de datos original |
