# Parte C — Simulacro de incidente de acceso indebido

> Ejecutado **solo** contra el clúster de desarrollo propio (`foodstore_test`), con usuarios
> sintéticos de la carga masiva de TP03.

| Artefacto | Archivo |
|---|---|
| Script del simulacro | [`../sql/simulacro_incidente.sql`](../sql/simulacro_incidente.sql) (orquestado por [`simulacro_incidente.sh`](../sql/simulacro_incidente.sh)) |
| Anonimizador de log | [`../sql/anonimizar_log.py`](../sql/anonimizar_log.py) |
| Salida y log anonimizado, corrida 1 (antes de corregir) | [`salida_simulacro_1.txt`](salida_simulacro_1.txt), [`log_simulacro_1_anonimizado.txt`](log_simulacro_1_anonimizado.txt) ← **es el que se le entrega a la IA** |
| Salida y log anonimizado, corrida 2 (después de corregir) | [`salida_simulacro_2.txt`](salida_simulacro_2.txt), [`log_simulacro_2_anonimizado.txt`](log_simulacro_2_anonimizado.txt) |
| Prueba de fuga de claves en el log | [`prueba_fuga_claves_log.txt`](prueba_fuga_claves_log.txt) |
| Prompt para la reconstrucción con IA | [`prompt_reconstruccion_ia.md`](prompt_reconstruccion_ia.md) |

## 1. Qué se ejecutó (la verdad de referencia)
| # | Credencial | Acción | Resultado (corrida 1) |
|---|---|---|---|
| 1 | `app_web` | 4 llamadas a `fn_autenticar` con claves incorrectas para un cliente | 4 × NULL (fallo) |
| 2 | `app_web` | 5.ª llamada con la clave correcta | devuelve `usuario_id = 10` |
| 3 | `soporte_ops` | `SELECT id, nombre, apellido, mail, celular FROM usuario` | **20.005 filas leídas** (lo permite el GRANT por columna de soporte) |
| 4 | `soporte_ops` | `SELECT … contrasena FROM usuario` | `permission denied` ✔ |
| 5 | `soporte_ops` | `GRANT admin_datos TO soporte_ops` | `permission denied to grant role` ✔ |
| 6 | `soporte_ops` | `SET ROLE admin_datos` | `permission denied to set role` ✔ |
| 7 | `soporte_ops` | `fn_resetear_password(25)` sobre un usuario **ADMIN** de la aplicación | **devolvió una clave temporal** ✘ |
| 8 | `app_web` | `fn_autenticar` del ADMIN con esa clave temporal | **login exitoso como ADMIN (id 25)** ✘ |

## 2. ¿El escalamiento falla? (C.2)
- **A nivel motor, sí.** Ni `GRANT` ni `SET ROLE` sobre `admin_datos` funcionan, porque nadie tiene `ADMIN OPTION` y `soporte_ops` no es miembro.
- **A nivel aplicación, no: HALLAZGO.** `fn_resetear_password` es `SECURITY DEFINER` y no distinguía el tipo de cuenta, así que soporte podía tomar una cuenta ADMIN de la tienda. Es un defecto del esquema de permisos de la Parte A: el privilegio EXECUTE estaba bien acotado, pero la función concedía más de lo que la spec justificaba («destrabar cuentas de clientes»).

**Corrección aplicada antes de continuar** (`sql/funciones_autenticacion.sql`): la función
rechaza a los ADMIN, devuelve NULL y deja el intento en `auditoria_login`
(`RESET_ADMIN_DENEGADO_soporte_ops`). **Corrida 2:** el paso 7 queda
`DENEGADO usuario_id=25 es ADMIN` y el paso 8 no ocurre.

**Efecto colateral observado en la corrida 2:** como los 4 fallos de la corrida 1 seguían
dentro de la ventana de 15 minutos, el primer intento sumó el 5.º fallo y los demás
quedaron `BLOQUEADO`, incluido el que tenía la clave correcta. El bloqueo funciona. Queda
anotado, eso sí, que un login exitoso no reinicia el contador.

## 3. Anonimización del log (C.3)
`anonimizar_log.py` aplica el criterio de `usuario_anon`, con reemplazo determinista:
mails → `cliente_<n>@anon.example`, rutas → `<PGDATA>`, literales de contraseña en
`fn_autenticar` → `'<CLAVE_REDACTADA>'`, `Usuario<n>`/`Apellido<n>` → `Nombre_<n>`/`Apellido_<n>`.
Se dejan sin tocar los roles, las horas, los PID y las IP, porque son la evidencia. El log
crudo no se versiona: el script lo borra al terminar.

**Hallazgo de esta etapa:** el log crudo tenía **las contraseñas probadas en claro**. El
`RAISE LOG` de `fn_autenticar` hace que PostgreSQL agregue la línea `STATEMENT` con los
literales. `prueba_fuga_claves_log.txt` muestra que con consultas parametrizadas no pasa
(`SecretoLiteral99`: 1 aparición; `SecretoBind99`: 0). Medida: la aplicación solo debe
usar sentencias preparadas, que es además la defensa contra la inyección SQL.

## 4. Reconstrucción y validación (C.4 – C.5)
La reconstrucción del log anonimizado (`log_simulacro_1_anonimizado.txt`) se contrastó con la
secuencia realmente ejecutada (tabla de la sección 1), y el equipo la revisó y la validó. Puntos
que se controlaron:
- Se distinguen dos credenciales: `app_web` (la cuenta técnica de la aplicación) y `soporte_ops` (la credencial humana).
- Los fallos de `fn_autenticar` son intentos de login de clientes en la aplicación, no fallos de conexión a la base.
- El log **no** sustenta que se hayan leído contraseñas: ese intento terminó en `permission denied`.
- El escalamiento efectivo fue `fn_resetear_password` → login como ADMIN; `GRANT` y `SET ROLE` fallaron.
- El log no registra cuántas filas devolvió la lectura masiva ni el resultado (COMMIT/ROLLBACK) de las transacciones.

El prompt para repetir la reconstrucción con otro asistente, sin contexto, quedó en
[`prompt_reconstruccion_ia.md`](prompt_reconstruccion_ia.md).

## 5. Decisión de contención (C.6)
**Propuesta técnica basada en la evidencia** (la decisión final es del equipo; ver la firma abajo):
1. **Inmediato:** `ALTER ROLE soporte_ops NOLOGIN` y cortar sus sesiones (`pg_terminate_backend`), porque el log lo vincula sin ambigüedad con la lectura masiva y el reset del ADMIN.
2. **Cuenta ADMIN 25:** forzar un cambio de contraseña controlado por un administrador e invalidar las sesiones de la aplicación.
3. **Cliente 10:** forzar cambio de contraseña (la clave correcta se adivinó al 5.º intento) y avisarle.
4. **Corregir antes de reabrir:** el reset de ADMIN queda bloqueado (ya aplicado); solo consultas parametrizadas; revisar si soporte necesita leer `celular` y `mail` de **todos** los clientes o solo los de un reclamo abierto (candidato a RLS o a una función por ticket).
5. **No se bloquea el origen por IP**: `127.0.0.1` es la propia aplicación y el abuso vino de una credencial interna. Bloquear la IP dejaría la tienda fuera de servicio y no frenaría al actor.

> **Decisión final del equipo:** se adoptan las medidas 1 a 5 tal como están propuestas,
> porque se basan en lo que el log demuestra (la credencial `soporte_ops` y la secuencia
> reset → login ADMIN) y no en supuestos. Es una decisión humana: ninguna medida se
> ejecuta automáticamente a partir de lo que sugiera una IA.
