# HORARIOS_B2 — Runsheet de ejecución y verificación (SOLO TEST)

**Alcance:** helper `fecha_hoy_ar()` + guard temporal en `crear_prereserva` (`fecha_in_pasada`) y `crear_bloqueo` (`rango_pasado`).
**Entorno:** TEST (ref `bdskhhbmcksskkzqkcdp`). **NO ejecutar en OPS.**
**Artefacto SQL:** `HORARIOS_B2_GUARD_HELPER_TEST.sql`.
**Ejecutor:** Franco. Claude no escribe en ninguna DB.

---

## Nota sobre secuencias (importante)

En PostgreSQL las **secuencias NO son transaccionales**: `nextval()` **no se revierte** con `ROLLBACK`. Por eso:

- Los paths de **RECHAZO** del guard (Paso 2.B) retornan **antes** de cualquier `INSERT` (el guard está ubicado antes del upsert de huésped y antes del `INSERT` de pre_reserva/bloqueo). No llaman a `nextval` → **cero consumo de secuencia**, con o sin `ROLLBACK`. Igual los envuelvo en `BEGIN; … ROLLBACK;` por disciplina.
- Un test de **ACEPTACIÓN end-to-end** (fecha_in = hoy/mañana) **sí** insertaría una pre_reserva + huésped y **consumiría** `id_pre_reserva` e `id_huesped` de forma **irreversible** (aunque haya `ROLLBACK`). Por eso **no** incluyo un smoke de aceptación end-to-end: la aceptación se valida por lógica de borde read-only (2.C) + no-regresión (2.D). Si querés un end-to-end de aceptación, queda marcado como opcional y consciente del consumo.

---

## Paso 0 — Baseline READ-ONLY (antes de aplicar; cero writes)

```sql
-- 0.1 Timezone baseline
SHOW timezone;
SELECT current_date AS hoy_sesion, (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS hoy_ar;

-- 0.2 Fingerprint de las funciones ANTES (guardar estos dos md5)
SELECT 'crear_prereserva' AS fn, md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) AS fp
UNION ALL
SELECT 'crear_bloqueo',          md5(pg_get_functiondef('public.crear_bloqueo(jsonb)'::regprocedure));

-- 0.3 EXCLUDE baseline (guardar estos constraintdef)
SELECT conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conname IN ('exc_reservas_no_overlap','exc_bloqueos_no_overlap')
ORDER BY conname;

-- 0.4 El helper todavía NO existe (esperado: t)
SELECT to_regprocedure('public.fecha_hoy_ar()') IS NULL AS helper_ausente;

-- 0.5 Sanidad de contexto: overrides_operativos sigue vacía y NO la tocamos (esperado: 0)
SELECT count(*) AS overrides_filas FROM overrides_operativos;
```

**Esperado Paso 0:** `helper_ausente = t`; `overrides_filas = 0`; dos fingerprints y dos constraintdef guardados como baseline. Si `hoy_sesion ≠ hoy_ar`, estás cerca de medianoche AR/UTC — el guard igual usará `hoy_ar` (eso es justo lo que queremos).

---

## Paso 0.6 — Precheck READ-ONLY: propagación de errores en wrappers/gateway

No es SQL: es revisión de código del repo (`c4f27ec`). Cero writes, cero cambios. Evidencia verificable en los archivos citados. Objetivo: saber si `fecha_in_pasada`/`rango_pasado` llegan al frontend como error controlado o como un genérico (`error_interno`/`estado_incierto`).

### 0.6.1 — Wrapper A07 (`Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`, nodo `router1_crear`)

`router1_crear` mapea `resultado.error` de `crear_prereserva` con `mapErr(e)`:
- `conflicto` ← `['no_disponible']`
- `payload_invalido` ← `['cabana_no_existe','cabana_inactiva','excede_capacidad','fechas_invalidas','precio_requerido','huesped_nombre_requerido','huesped_contacto_requerido','hora_fuera_de_rango','payload_invalido']`
- `estado_incierto` ← `['unique_violation_inesperado']`
- **default (cualquier otro) → `error_interno`** ("no se pudo crear la prereserva")

`fecha_in_pasada` no está en ninguna lista → cae al **default → `error_interno`**. El guard dispara en PG-1, que es justo lo que lee `router1_crear`.
Nota: `validar_firma_ts_rol` pre-valida fechas, pero solo `fecha_out > fecha_in` (no contra hoy), así que una `fecha_in` pasada **pasa el wrapper** y llega al guard SQL → no hay doble rechazo.

### 0.6.2 — Wrapper A08 (`Workflows/n8n/Supabase/portal-a08-crear-bloqueo__TEMPLATE.json`, nodo `router_bloqueo`)

`router_bloqueo` mapea `resultado.error` de `crear_bloqueo`:
- `conflicto` ← `['conflicto_con_reserva','conflicto_con_prereserva','bloqueo_solapado']`
- `payload_invalido` ← `['payload_invalido','fechas_invalidas','motivo_invalido','cabana_no_existe']`
- **default → `error_interno`** ("no se pudo crear el bloqueo")

`rango_pasado` no está en ninguna lista → **default → `error_interno`**. Mismo comportamiento que A07.

### 0.6.3 — Gateway `portal-api` (`Docs/Supabase/index.ts`, `dispatchN8n` + allowlist)

- Allowlist `CODIGOS_ERROR_PERMITIDOS` (13 códigos): `payload_invalido, no_autorizado, rol_no_permitido, accion_desconocida, no_encontrado, conflicto, error_entorno, error_interno, estado_incierto, firma_invalida, ts_fuera_de_ventana, raw_body_ausente, ambiente_incorrecto`.
- Ante código NO allowlisted en escritura: el gateway lo enmascara vía `noConfiable`, que para `isWrite=true` (A07/A08) devuelve **`estado_incierto`**. **Pero esto NO aplica acá**: el wrapper ya tradujo el código SQL a `error_interno`, que **sí** está en la allowlist.
- Resultado al frontend: como el wrapper manda `error_interno` (allowlisted, código de infra), el gateway lo **propaga** e **impone** el mensaje fijo `'error interno'`, `detail:null`. El frontend recibe `{ok:false, error:{code:'error_interno', message:'error interno', detail:null}}` — error **controlado y genérico**, NO `estado_incierto`.

### 0.6.4 — ¿Hace falta tocar alguna allowlist?

- **Gateway (`CODIGOS_ERROR_PERMITIDOS`): NO.** Los códigos SQL nuevos nunca necesitan estar acá; el wrapper traduce. `payload_invalido` ya está allowlisted.
- **Wrappers (listas de `mapErr`): SÍ, pero solo para UX y más adelante.** Agregar `fecha_in_pasada` a `payloadInv` de A07 y `rango_pasado` a `payloadInv` de A08 → los convierte en `payload_invalido` con mensaje específico (`'datos de reserva rechazados: fecha_in_pasada'` / `'datos de bloqueo rechazados: rango_pasado'`), que el gateway conserva por no ser código de infra. **No bloqueante.**

### 0.6.5 — VEREDICTO

**(b) El DDL bloquea bien en backend, y los errores pasan CONTROLADOS (`error_interno`, allowlisted) — NO `estado_incierto`. Se puede ejecutar el DDL sin tocar gateway ni wrappers.**

El único faltante es **UX**: hoy el frontend ve un genérico `'error interno'` en vez del motivo real. Se resuelve con un mini-ajuste **posterior y opcional en los wrappers** (no en el gateway): mapear `fecha_in_pasada`/`rango_pasado` a `payload_invalido`. **No frena la ejecución del Bloque 2.**

**NO es el escenario (c):** el gateway NO convierte estos errores en `estado_incierto`, porque el wrapper los traduce a `error_interno` (allowlisted) antes de llegar al gateway. El falso "verificá antes de reintentar" no se materializa, y como el guard retorna antes del INSERT, no hay write ni riesgo de double-booking.

---

## Paso 1 — Aplicar el DDL (único write estructural)

Ejecutar **`HORARIOS_B2_GUARD_HELPER_TEST.sql` completo**, sin selección parcial (L-8A-01). Es DDL puro: `CREATE OR REPLACE FUNCTION` ×3 + `REVOKE` + `COMMENT`. **No inserta filas. No consume secuencias de negocio.** Las dos funciones usan `CREATE OR REPLACE` (no `DROP`) → preservan el ACL del Bloque 23.

---

## Paso 2 — Verificación POST-aplicación

### 2.A — READ-ONLY (cero writes, cero secuencias)

```sql
-- 2.A.1 Helper existe + hardening correcto
SELECT p.proname,
       p.prosecdef          AS es_definer,   -- esperado: f  (SECURITY INVOKER)
       p.provolatile        AS volatilidad,  -- esperado: s  (STABLE)
       p.proacl IS NOT NULL AS acl_cerrado   -- esperado: t  (REVOKE materializó el ACL; ya no PUBLIC)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='fecha_hoy_ar';

-- 2.A.2 Helper correcto e INDEPENDIENTE del timezone de sesión
SET TimeZone='UTC';
SELECT fecha_hoy_ar() AS hoy_ar_desde_utc, current_date AS current_date_utc;
SET TimeZone='America/Argentina/Buenos_Aires';
SELECT fecha_hoy_ar() AS hoy_ar_desde_ar,  current_date AS current_date_ar;
RESET TimeZone;
-- Esperado: hoy_ar_desde_utc = hoy_ar_desde_ar (mismo día AR en ambas sesiones).
--           current_date puede diferir entre ambas cerca de medianoche → prueba el punto.

-- 2.A.3 Fingerprint DESPUÉS (debe diferir del baseline 0.2: agregamos el guard)
SELECT 'crear_prereserva' AS fn, md5(pg_get_functiondef('public.crear_prereserva(jsonb)'::regprocedure)) AS fp
UNION ALL
SELECT 'crear_bloqueo',          md5(pg_get_functiondef('public.crear_bloqueo(jsonb)'::regprocedure));
-- Esperado: ambos md5 != baseline. El "qué cambió" está probado por diff de fuente (ver abajo).

-- 2.A.4 EXCLUDE INTACTO (debe ser IDÉNTICO al baseline 0.3)
SELECT conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conname IN ('exc_reservas_no_overlap','exc_bloqueos_no_overlap')
ORDER BY conname;
-- Esperado: def idéntico al baseline. El guard no toca constraints ni el modelo [fecha_in, fecha_out).
```

### 2.B — DESTRUCTIVO controlado: paths de RECHAZO (cero secuencias; retornan antes del INSERT)

```sql
-- 2.B.1 crear_prereserva con fecha_in = AYER → fecha_in_pasada
BEGIN;
SELECT crear_prereserva(jsonb_build_object(
  'id_cabana', 1,
  'fecha_in',  (fecha_hoy_ar() - 1)::text,
  'fecha_out', (fecha_hoy_ar() + 1)::text,
  'personas', 2, 'monto_total', 1000, 'monto_sena', 500,
  'canal_origen', 'test_b2', 'canal_pago_esperado', 'efectivo',
  'source_event', 'b2_smoke_rechazo',
  'huesped', jsonb_build_object('nombre','Smoke B2','telefono','+540000000000')
)) AS resultado;
ROLLBACK;
-- Esperado: resultado->>'error' = 'fecha_in_pasada', con campo/minimo/recibido.

-- 2.B.2 crear_bloqueo con rango COMPLETAMENTE pasado [hoy-3, hoy) → rango_pasado
BEGIN;
SELECT crear_bloqueo(jsonb_build_object(
  'id_cabana', NULL,
  'fecha_desde', (fecha_hoy_ar() - 3)::text,
  'fecha_hasta', (fecha_hoy_ar()    )::text,
  'motivo', 'mantenimiento', 'creado_por', 'smoke_b2',
  'source_event', 'b2_smoke_rechazo'
)) AS resultado;
ROLLBACK;
-- Esperado: resultado->>'error' = 'rango_pasado', con campo/minimo/recibido.
```

### 2.C — Lógica de borde READ-ONLY (prueba aceptación SIN insertar)

```sql
-- 2.C.1 Borde guard pre-reserva (prueba el comparador '<' sin invocar crear_prereserva)
SELECT ((fecha_hoy_ar() - 1) < fecha_hoy_ar()) AS ayer_rechazado,    -- esperado: t
       ((fecha_hoy_ar()    ) < fecha_hoy_ar()) AS hoy_rechazado,     -- esperado: f  (hoy permitido)
       ((fecha_hoy_ar() + 1) < fecha_hoy_ar()) AS manana_rechazado;  -- esperado: f

-- 2.C.2 Borde guard bloqueo (semántica [) exclusiva)
SELECT ((fecha_hoy_ar()    ) <= fecha_hoy_ar()) AS hasta_hoy_rechazado,    -- esperado: t  (rango vencido)
       ((fecha_hoy_ar() + 1) <= fecha_hoy_ar()) AS hasta_manana_rechazado; -- esperado: f  (vigente, pasa)
```

**Aceptación end-to-end (OPCIONAL, consciente del consumo):** si querés probar que una pre-reserva con `fecha_in = hoy` realmente se crea, ejecutá un `crear_prereserva` con datos válidos y una cabaña real; eso **consumirá** `id_pre_reserva` e `id_huesped` (irreversible). Limpiá la fila con `DELETE` después (los datos se van; la secuencia queda avanzada). **No** es necesario para aprobar el guard: la aceptación ya está cubierta por 2.C + no-regresión.

### 2.D — No-regresión `[fecha_in, fecha_out)` y A07/A08

- **Modelo de noche intacto:** confirmado por 2.A.4 (EXCLUDE idéntico). El guard solo rechaza `fecha_in`/rango pasados; **no** toca la adyacencia checkout=checkin. Las pegadas por noche siguen permitidas.
- **A07/A08 no rotos:** re-correr los smokes A07/A08 vigentes del repo (usan fechas futuras → el guard no los afecta) y confirmar verdes. El diff de fuente (abajo) prueba que el delta es puramente aditivo.

---

## Evidencia que tenés que pegar para aprobar

1. **0.1 + 2.A.2** — `SHOW timezone` + tabla `fecha_hoy_ar()` vs `current_date` en sesión UTC y AR (iguales en `hoy_ar`).
2. **2.A.1** — helper `es_definer=f`, `volatilidad=s`, `acl_cerrado=t`.
3. **0.2 vs 2.A.3** — los md5 cambiaron (antes ≠ después).
4. **2.A.4 vs 0.3** — EXCLUDE idéntico (constraintdef before == after).
5. **2.B.1 + 2.B.2** — los dos JSON de rechazo (`fecha_in_pasada`, `rango_pasado`).
6. **2.C.1 + 2.C.2** — bordes: ayer rechazado / hoy y mañana permitidos; bloqueo hasta-hoy rechazado / hasta-mañana permitido.
7. **2.D** — smokes A07/A08 verdes.

**Prueba de "el delta es solo el guard"** (reproducible desde el repo público): clonar `c4f27ec`, extraer los cuerpos de `crear_prereserva`/`crear_bloqueo` del canónico y hacer `diff` contra los del artefacto → solo aparecen los dos bloques `IF` del guard, sin borrados ni cambios en el resto.

---

## Reversión del Bloque 2 (si algo sale mal en TEST)

1. `CREATE OR REPLACE` de `crear_prereserva` y `crear_bloqueo` con los cuerpos **originales** del canónico v1.9.0 (sin guard) → preserva grants, quita el guard.
2. `DROP FUNCTION public.fecha_hoy_ar();`.

Puedo generar el `..._REVERT_TEST.sql` si lo querés; lo dejé fuera de esta tanda para no ampliar alcance.
