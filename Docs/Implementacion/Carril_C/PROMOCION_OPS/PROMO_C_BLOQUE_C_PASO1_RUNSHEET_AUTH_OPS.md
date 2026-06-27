# Bloque C · Paso 1 — Runsheet: crear los 5 usuarios en Supabase Auth (OPS)

**Etapa:** Promoción coordinada del Carril C a OPS — Bloque C, paso 1 de 2 (manual).
**Proyecto:** Supabase **OPS** (`lpiatqztudxiwdlcoasv`). No confundir con TEST.
**Quién ejecuta:** Franco (Dashboard de Supabase). Claude no toca Auth.
**Decisiones:** D-C-32 (seed por email, sin UUIDs), D-C-22 (nombre = persona).

Este paso crea las **identidades** en Supabase Auth de OPS. El paso 2 (`PROMO_C_BLOQUE_C_SEED_USUARIOS_OPS.sql`) las mapea a un rol resolviendo `user_id` **por email**. Por eso este paso va **primero**: el SQL aborta si falta algún email.

---

## Qué vas a crear

5 usuarios. El **email lo elegís vos** (probablemente el email real de cada persona). El **nombre lógico** y el **rol** son fijos (son los que ya usa todo el sistema como `creado_por`/`validado_por`).

| # | Persona | Nombre lógico (fijo) | Rol en el portal (fijo) | Email (lo definís vos) |
|---|---------|----------------------|--------------------------|------------------------|
| 1 | Franco  | `franco`  | `socio` | `__PEGAR_EMAIL_FRANCO`  |
| 2 | Rodrigo | `rodrigo` | `socio` | `__PEGAR_EMAIL_RODRIGO` |
| 3 | Remo    | `remo`    | `socio` | `__PEGAR_EMAIL_REMO`    |
| 4 | Vicky   | `vicky`   | `vicky` | `__PEGAR_EMAIL_VICKY`   |
| 5 | Jenny   | `jenny`   | `jenny` | `__PEGAR_EMAIL_JENNY`   |

> **Anotá los 5 emails que uses.** Son los mismos que vas a pegar en el SQL del paso 2 (en un solo lugar). Si en Auth ponés un email y en el SQL otro, el seed aborta (no matchea `auth.users`).

---

## Procedimiento (por cada uno de los 5)

1. Entrá al Dashboard de Supabase, **proyecto OPS**. Verificá arriba que el ref sea `lpiatqztudxiwdlcoasv` (no el de TEST).
2. **Authentication → Users → Add user → Create new user.**
3. Completá:
   - **Email:** el email que elegiste para esa persona.
   - **Password:** una contraseña fuerte. **No la anotes en ningún archivo del repo ni me la pases.** Si vas a usar reset/invitación, está bien también; lo único que el seed necesita es que el usuario exista y esté confirmado.
   - **Auto Confirm User: ON** (✅). Sin esto, el usuario queda sin confirmar y el login del portal no funcionaría.
4. **Create user.**
5. Repetí para los 5.

> **Contraseñas:** quedan solo en tu gestor / en manos de cada persona. El sistema no las almacena en `portal_usuarios` (ahí va solo `user_id`, `nombre`, `rol`). Para distribuirlas, preferí el flujo de invitación/reset de Supabase antes que mandar contraseñas en texto.

---

## Verificación antes de pasar al SQL

En **Authentication → Users** confirmá:

- [ ] Aparecen **5 usuarios** con los emails que elegiste.
- [ ] Los 5 figuran **confirmados** (columna de confirmación con fecha, no "Waiting for verification").
- [ ] No hay **emails repetidos** (cada persona, un email distinto).
- [ ] No quedó ningún usuario de prueba de más mezclado (esto es OPS, identidades reales).

Opcional — verificación por SQL (read-only, no siembra nada). Reemplazá los 5 emails y corré en el SQL Editor de OPS:

```sql
SELECT email,
       (email_confirmed_at IS NOT NULL) AS confirmado
FROM auth.users
WHERE email IN (
  '__PEGAR_EMAIL_FRANCO', '__PEGAR_EMAIL_RODRIGO', '__PEGAR_EMAIL_REMO',
  '__PEGAR_EMAIL_VICKY',  '__PEGAR_EMAIL_JENNY'
)
ORDER BY email;
```

Esperado: **5 filas**, todas con `confirmado = true`. Si ves menos de 5 o algún `false`, corregí en Auth antes de seguir.

---

## Qué NO hacer en este paso

- No tocar **n8n**, el **gateway** (`portal-api`) ni **Vercel**: eso es de bloques posteriores (D/E/F/G).
- No crear roles ni permisos a mano en la base: el rol lo asigna el SQL del paso 2 por la columna `rol` de `portal_usuarios`.
- No editar `portal_usuarios` a mano: dejá que el seed del paso 2 la complete (nació vacía en el Bloque B).

---

## Siguiente

Con los 5 usuarios creados y confirmados, corré **`PROMO_C_BLOQUE_C_SEED_USUARIOS_OPS.sql`** (paso 2): reemplazás los 5 emails **en un solo lugar** (el INSERT a `_seed_usuarios`), lo corrés entero en el SQL Editor de OPS, y esperás la tabla de veredicto con la fila **TOTAL en VERDE** (5 filas, roles 3/1/1). Si algún email falta o está duplicado, el SQL aborta sin tocar nada y te dice cuál.
