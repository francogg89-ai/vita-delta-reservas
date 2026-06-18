# Runsheet — Carril C / Slice 0 / Fase A: `portal_usuarios` + usuarios de Auth (TEST)

**Entorno:** Supabase **TEST** únicamente. **OPS no se toca.**
**Objetivo:** dejar creada y sembrada `portal_usuarios` en TEST, con los 5 usuarios del portal en Supabase Auth.
**Decisiones:** D-C-14 (identidad por tabla), D-C-22 (nombre = persona), D-C-32 (seed por email), D-C-34 (interna, no vía Data API).
**Artefactos:** `C_SLICE0_A1_DDL_portal_usuarios.sql`, `C_SLICE0_A2_SEED_portal_usuarios.sql`.

---

## Orden de ejecución (importa)

1. **Paso 1 — Crear la tabla.** Correr `C_SLICE0_A1_DDL_portal_usuarios.sql` en el SQL Editor de **TEST** (nada seleccionado, todo de una). Todas las filas de veredicto deben dar **PASS**. La tabla nace **vacía**.
2. **Paso 2 — Crear los 5 usuarios en Auth** (sección de abajo). Va en el medio a propósito: el seed resuelve `user_id` por email y necesita que existan.
3. **Paso 3 — Sembrar.** Correr `C_SLICE0_A2_SEED_portal_usuarios.sql` en el SQL Editor de **TEST**. Todas las filas de veredicto en **PASS** (total=5, 3 socios, 1 vicky, 1 jenny, todos activos).

Si invertís el orden (seed antes de crear usuarios), el seed **aborta solo** y te lista los emails faltantes. No rompe nada.

---

## Crear los 5 usuarios en Supabase Auth (TEST)

En el **Dashboard del proyecto TEST**: **Authentication → Users → Add user → Create new user**.

| nombre  | email (exacto)            | rol que tendrá |
|---------|---------------------------|----------------|
| franco  | `franco@vitadelta.test`   | socio          |
| rodrigo | `rodrigo@vitadelta.test`  | socio          |
| remo    | `remo@vitadelta.test`     | socio          |
| vicky   | `vicky@vitadelta.test`    | vicky          |
| jenny   | `jenny@vitadelta.test`    | jenny          |

Por cada usuario:
- **Email:** el de la tabla, tal cual.
- **Password:** la elegís vos. **No la compartas ni la pegues en el repo / chat.** Guardala en tu gestor: la vas a necesitar en **Fase D** para loguearte y obtener el JWT de prueba.
- **Auto Confirm User: ON.** Clave, porque `@vitadelta.test` no recibe mails: sin Auto Confirm el usuario queda sin confirmar y no puede loguearse. (Si el panel no muestra el toggle al crear, creá el usuario y luego "Confirm email" desde su fila.)

### Verificación rápida (opcional) en SQL Editor TEST
```sql
SELECT email, (email_confirmed_at IS NOT NULL) AS confirmado
FROM auth.users
WHERE email LIKE '%@vitadelta.test'
ORDER BY email;
```
Esperado: 5 filas, `confirmado = true` en todas.

---

## Qué NO va al repo
- Las **contraseñas** de los 5 usuarios.
- Los **UUID** (`user_id`) — el seed los resuelve solo por email.
- Cualquier **service_role key / anon key / connection string** del proyecto TEST.

Los `.sql` de Fase A **sí** pueden ir al repo: contienen solo emails operativos de TEST (no secretos), nombres y roles.

---

## Notas de diseño (por qué así)
- **Gate de entorno:** ambos `.sql` exigen `configuracion_general('ambiente') = 'test'` antes de tocar nada. Es el único discriminador fiable TEST/OPS (los ids de cabaña 1-5 son idénticos en ambos, L-7B-01). Corrido por error contra OPS, aborta.
- **D-C-34 (interna, no vía Data API):** la tabla vive en `public` (como las 9 del Carril B) pero con permisos **revocados** a `anon` y `authenticated` (los roles del navegador) y **solo SELECT** a `service_role` (el lector server-side de la Edge Function `portal-api`). A1 trae un **assert duro**: si por algún residual de Supabase el navegador pudiera leerla, **aborta**. En una frase para los socios: *"misma estrategia que las tablas de contabilidad — vive en public pero el Data API no la ve; solo la lee el gateway."*
- **FK a `auth.users` + `ON DELETE CASCADE`:** patrón Supabase clásico; borrar un usuario de Auth limpia su fila del portal.
- **Re-ejecución:** A1 aborta si la tabla ya existe (no la pisa); A2 no re-siembra si ya hay filas. Para recrear de cero, usar el bloque de **teardown consciente** comentado al pie de A1 (con su propio gate de ambiente).

---

## Al terminar
Avisame y arrancamos **Fase B — Edge Function `portal-api`**: validación JWT (`supabase.auth.getUser`, D-C-30), lookup en `portal_usuarios`, allowlist rol×action como constante versionada (D-C-31), armado + firma HMAC (D-C-29, bytes literales del body), y `sesion.contexto` (A02) como primer vertical end-to-end que **no toca n8n**.
