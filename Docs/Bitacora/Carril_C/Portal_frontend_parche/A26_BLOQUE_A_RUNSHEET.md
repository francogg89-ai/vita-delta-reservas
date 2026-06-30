# Bloque A — A26 `disponibilidad.cabana` · Runsheet (import + validación en TEST) · **Opción B**

**Etapa:** Carril C / Portal Operativo Interno — frente UX guardrails A07/A08, **Bloque A** (lectura nueva A26).
**Ámbito:** 100% **TEST**. Wrapper n8n directo. **Sin gateway, sin frontend, sin DDL, sin tocar `6B_SCHEMA_SQL.md v1.9.0`, sin OPS, sin react-day-picker.**
**Rol:** Claude diseñó/validó/generó; **Franco ejecuta** (import en n8n, pega secreto, corre smoke/evidencia). Frená al terminar para Bloque B.

> **Corrección de topología (auditoría de Franco):** la versión anterior cableaba `PG: precheck → PG: disponibilidad` con `alwaysOutputData=true`, así que la función `obtener_disponibilidad_rango(...)` se invocaba igual aunque la cabaña no existiera. **Opción B lo arregla**: una sola query con compuerta SQL (CTE + `CROSS JOIN LATERAL`) que **no evalúa la función** si la cabaña no existe/está inactiva. Demostrado con `EXPLAIN ANALYZE` (`Function Scan ... (never executed)`).

---

## 1. Qué entrega el Bloque A

| Artefacto | Para qué |
|---|---|
| `portal-a26-disponibilidad__TEST.json` | Wrapper n8n a importar (**8 nodos**, 1 sola query PG con compuerta). |
| `build_a26_wrapper.py` | Builder self-contained que lo regenera (escaping garantizado). |
| `A26_smoke_directo.ps1` | Smoke directo al webhook (sin gateway), PS5.1 ASCII-puro. |
| `A26_smoke_oracle.sql` | Oráculo **read-only**: verdad de referencia + ayuda para elegir rango con ocupación. |
| `A26_evidencia_no_ejecuta.sql` | **Evidencia read-only** (EXPLAIN ANALYZE) de que con cabaña inválida/inactiva la función NO se ejecuta. |

**Validación en build (toda verde):** JSON parsea (8 nodos); los 3 nodos JS pasan `node --check`; las **2** queries SQL (`leer_ambiente` + `disponibilidad` con compuerta) pasan `pglast`; el orden de args es `fecha_desde, fecha_hasta, id_cabana`; y la query exacta probada contra mocks da: cabaña activa → `cabana_existe=t` + N días + **1** invocación; inactiva/inexistente → `cabana_existe=f` + sin días + **0** invocaciones.

---

## 2. Anatomía del wrapper (Opción B)

`Webhook (rawBody)` → `validar_firma_ts_rol` (HMAC-SHA256 sobre bytes crudos + ventana ts 300s + rol `vicky`/`socio` + action binding `disponibilidad.cabana` + payload) → `leer_ambiente` (anti-OPS) → `verificar_acceso` → `IF acceso` → `PG: disponibilidad` → `Code: render envelope` → `Respond`.

- **Validación de payload (`validar_firma_ts_rol`):** `id_cabana` entero positivo **obligatorio**; `fecha_desde`/`fecha_hasta` YMD reales con `hasta > desde`; **span ≤ 366 días**. Violación → `payload_invalido`. No valida "fecha pasada" (guard UX del frontend) ni existencia de cabaña (eso lo hace la compuerta SQL).
- **Compuerta SQL (una sola query, `PG: disponibilidad`):**
  ```sql
  WITH valida AS (
    SELECT c.id_cabana FROM cabanas c
    WHERE c.id_cabana = (($1::jsonb)->>'id_cabana')::bigint AND c.activa = TRUE
  ),
  existe AS ( SELECT EXISTS(SELECT 1 FROM valida) AS cabana_existe ),
  disp AS (
    SELECT f.fecha, f.estado, f.id_cabana, f.hora_checkin_base, f.hora_checkout_base
    FROM valida v
    CROSS JOIN LATERAL obtener_disponibilidad_rango(
      (($1::jsonb)->>'fecha_desde')::date, (($1::jsonb)->>'fecha_hasta')::date, v.id_cabana
    ) AS f
  )
  SELECT e.cabana_existe, d.fecha, d.estado, d.id_cabana, d.hora_checkin_base, d.hora_checkout_base
  FROM existe e LEFT JOIN disp d ON TRUE ORDER BY d.fecha NULLS LAST;
  ```
  - `valida` tiene **0 filas** si la cabaña no existe/está inactiva. La función toma `id_cabana` **desde `valida`** (`v.id_cabana`): con 0 filas, el `LATERAL` no itera y la función **nunca se evalúa** (`Function Scan ... never executed`).
  - `cabana_existe` es el **marcador explícito**: el `LEFT JOIN existe×disp` garantiza **≥1 fila** siempre. Inválida/inactiva → 1 fila `{cabana_existe:false, fecha:null}`. Activa → N filas (1 por noche) con `cabana_existe:true`.
  - Orden y casts exactos: `obtener_disponibilidad_rango(fecha_desde::date, fecha_hasta::date, id_cabana::bigint)` = `(p_fecha_desde, p_fecha_hasta, p_id_cabana)`. **No** toca la función ni el schema.
- **Render (`Code: render envelope`):** lee solo `PG: disponibilidad`. `cabana_existe=false` → **`no_encontrado`** (nunca `ok:true` con `dias:[]`). `cabana_existe=true` → mapea `data.dias` (filas con `fecha` no nula). Fallo de lectura DB/n8n → `error_interno`.
- **Flags del PG:** `alwaysOutputData=true` + `executeOnce=true` + `onError=continueRegularOutput` (el render corre siempre y distingue `error_interno`).
- **Respuesta OK:** `{ ok:true, data:{ dias:[ { fecha, estado, id_cabana, hora_checkin_base, hora_checkout_base } ] } }`, una entrada por **noche** de `[fecha_desde, fecha_hasta)`.

---

## 3. Pasos de import en n8n (TEST)

1. **Importar** `portal-a26-disponibilidad__TEST.json` en `federicosecchi.app.n8n.cloud` (Workflows → Import from File).
2. **Credencial Postgres:** en los **2** nodos PG (`leer_ambiente`, `PG: disponibilidad`) seleccionar la credencial real de TEST (`vita_supabase_test`); el template trae `REEMPLAZAR_POR_CRED_TEST`.
3. **Secreto HMAC (Modo B, L-C-10):** en `validar_firma_ts_rol`, reemplazar `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el mismo `VITA_HMAC_SECRET` de TEST. (El assert por prefijo `__PEGAR_` aborta si quedó sin reemplazar.)
4. **Webhook:** confirmar `Raw Body = ON` (viene `options.rawBody=true`) y el path `portal-a26-disponibilidad`. URL: `https://federicosecchi.app.n8n.cloud/webhook/portal-a26-disponibilidad`.
5. **Activar** el workflow (o `webhook-test` con "Listen" según tu flujo de smokes).

> El wrapper **no** se cablea al gateway en este bloque (eso es Bloque B). Es alcanzable solo por su webhook firmado.

---

## 4. Validación (evidencia de compuerta + oráculo + smoke)

1. **Evidencia de no-ejecución:** corré `A26_evidencia_no_ejecuta.sql` en el SQL Editor de TEST (read-only). En el bloque **[INVALIDA]**, en el `Function Scan` de `obtener_disponibilidad_rango` debe leerse **`(never executed)`**; en **[VALIDA]**, `loops=1`. (Ajustá el id válido a una cabaña activa real de TEST.)
2. **Oráculo:** corré `A26_smoke_oracle.sql` (L-8A-01: el editor ejecuta solo lo seleccionado) → elegí una ventana con ocupación y una fecha `checkout_disponible`. Anotá la salida del bloque [D] como verdad de referencia.
3. **Smoke:** editá la cabecera de `A26_smoke_directo.ps1`: `$Secret` (el de TEST), `$CabValida`/`$CabInvalida` si en TEST no son `1`/`999999`, y —para activar **T5/T6**— `$CabOcup`/`$OcupDesde`/`$OcupHasta`/`$FechaCheckout`. Si dejás esos vacíos, **T5/T6 quedan en SKIP** (no fallan). Corré el smoke (PS 5.1).
4. **Paridad:** el volcado de `dias` de T5 debe coincidir fila por fila con el bloque [D] del oráculo.

---

## 5. Casos cubiertos (tus 7 + defensas) — 15 checks

| # | Caso (tu lista) | Cómo se verifica |
|---|---|---|
| 1 | cabaña válida sin ocupación → días `disponible` | T1: rango futuro libre → `ok:true`, `dias` no vacío, todos `disponible` |
| 2 | cabaña inexistente/inactiva → `no_encontrado` | T2: `id_cabana` inexistente → `no_encontrado` (y la función **no se evalúa**, ver §4.1) |
| 3a | rango inválido → `payload_invalido` | T3: `fecha_hasta < fecha_desde` → `payload_invalido` |
| 3b | span > 366 → `payload_invalido` | T4: `desde + 400 días` → `payload_invalido` |
| 4 | reserva/bloqueo/prereserva vigente reflejados | T5: rango con ocupación → invariantes (count==span, enum, contiguo, `[)`) + paridad con oráculo |
| 5 | `[fecha_in, fecha_out)` con checkout disponible | T6: fecha de checkout elegida → `estado='checkout_disponible'` |
| — | seguridad/forma (defensa en profundidad) | T7 firma mala→`firma_invalida`; T8 jenny→`rol_no_permitido`; T9 action mala→`accion_desconocida`; T10 ambiente `ops`→`ambiente_incorrecto`; T11 clave desconocida→`payload_invalido`; T12 `id_cabana` 0/negativo/string→`payload_invalido`; T13 falta `fecha_hasta`→`payload_invalido` |

> **Nota anti-secuencias (D-PROMO-09):** smoke y evidencia son **read-only**; no crean reservas/bloqueos/prereservas ni consumen secuencias. El smoke usa la ocupación que ya existe en TEST; el oráculo te ayuda a ubicarla.

---

## 6. Verdict row

| Gate | Estado |
|---|---|
| Artefactos generados y validados (JSON 8 nodos / 3 JS `node --check` / 2 SQL `pglast`) | ✅ (en build) |
| Compuerta: con cabaña inválida la función **no se evalúa** (`never executed`) | ✅ demostrado (local + script para TEST) |
| Query exacta contra mocks: activa→1 invocación / inválida→0 | ✅ |
| Import + credencial + secreto + evidencia + smoke | ⏳ **lo ejecutás vos** |
| Smoke en verde (15 checks; T5/T6 en SKIP hasta cargar el oráculo) + paridad | ⏳ pendiente de tu corrida |

---

## 7. Qué NO toca este bloque

OPS · gateway `portal-api` · frontend · DDL · `6B_SCHEMA_SQL.md v1.9.0` · la función `obtener_disponibilidad_rango` (se **consume**) · A07/A08 (escritura) · react-day-picker.

---

**Handoff:** importá, pegá el secreto, corré la **evidencia** (confirmá `never executed` en el caso inválido), después el **oráculo** y el **smoke**. Cuando tengas el smoke **en verde (T5/T6 incluidos, con la ventana del oráculo cargada) + paridad OK**, pasame el resultado y recién ahí armo el **Bloque B** (exponer A26 en el `CATALOG` del gateway + smoke vía gateway), frenando de nuevo para tu ejecución.
