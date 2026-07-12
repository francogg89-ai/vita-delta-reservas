# Kickoff — Vita Delta Reservas · Motor de Precios v2 · **B4 — Wrappers / Gateway / Edge pública**

**Fecha de corte:** 2026-07-12
**Frente:** Motor de Precios v2
**Estado:** B0, B1, B1.1, B2A, B2B, B3 **cerrados en TEST**
**Bloque que abre:** **B4** — exposición segura del motor ya cerrado
**Bloque delegado a otro grupo:** **B3.1** (ver §14 — *diseñado, NO ejecutado*)

---

## 0. Cómo usar este documento

Este kickoff es **auto-contenido**: todos los datos técnicos que trae fueron extraídos del harness/repo reales, no de memoria.

**Aun así, la primera acción de la conversación B4 es LEER EL REPO.** El repo es la autoridad; este documento es un mapa, no un sustituto. Ver §9 para las rutas exactas a inspeccionar y §15 para el prompt de arranque.

---

## 1. Método de trabajo (no negociable)

- Español **rioplatense con voseo**.
- **Claude diseña, inspecciona, valida y genera artefactos. Franco ejecuta TODO**: Supabase, n8n, Vercel, git, TEST/OPS. Claude nunca toca servicios.
- Secuencia estricta: **diagnóstico/diseño → aprobación explícita de Franco → artefactos → Franco ejecuta en TEST → verificación → cierre formal**.
- **No se genera SQL/código antes de la aprobación del diseño.**
- **Clone fresco (`git clone --depth 1`) antes de cualquier spec, inspección o cierre.** Citar rutas y funciones exactas.
- Un bloque por conversación; hard stop antes de que Franco ejecute.
- Validación obligatoria en **harness local PostgreSQL 16.14** antes de entregar artefactos SQL.
- `D-*` / `L-*` no se acuñan hasta el cierre formal del frente. Los satélites (`DECISIONES_NO_REABRIR`, `Lecciones_Aprendidas`, `ESTADO_ACTUAL`, `CLAUDE.md`, `README`, `Pendiente`) se actualizan solo al cierre.

---

## 2. Estado del frente

| Bloque | Contenido | Estado |
|---|---|---|
| **B0** | Diseño conceptual, decisiones de negocio (D-PR-01…D-PR-20) | **cerrado** |
| **B1** | Diagnóstico DB read-only | **cerrado** |
| **B1.1** | Probes catalog-truth (ACL, volatilidad, semánticas) | **cerrado** |
| **B2A** | Estructura + hardening + seeds mínimos | **cerrado en TEST** |
| **B2B** | Seeds de pricing (temporadas + 32 tarifas) | **cerrado en TEST** |
| **B3** | Funciones del motor (13) | **cerrado en TEST** |
| **B3.1** | Override manual de capacidad | **DISEÑADO · NO EJECUTADO · DELEGADO** (§14) |
| **B4** | Wrappers / gateway / Edge pública | **ESTE BLOQUE** |

### Fingerprints verificados (TEST == harness)

```text
B2A  estructura        : da52a16c045689523a5f1f113f513a87   (124 líneas)
B2B  datos             : 6d1653748d68ee9b62aa20aba5f3333d   (40 líneas)
B3   funciones (NORM.) : 098f2fe7916e11ffa78cff37622b9064   (13 funciones)
```

**B3.1 NO tiene fingerprint** — nunca se ejecutó nada. No inventar uno.

**Sobre el fingerprint de B3:** el criterio válido es el **normalizado** (`md5(replace(prosrc, chr(13), ''))`). El **crudo** puede dar `2ff4203a9863702c0043dcd08e82b373` si el `.sql` viajó con line endings CRLF: PostgreSQL guarda `\r\n` dentro de `prosrc` y el md5 cambia **aunque el código sea byte-idéntico** (reproducido y probado). El crudo NO indica divergencia.

### Validación de cierre de B3

```text
VERIFY  9/9   PASS
SMOKES  40/40 PASS   (base limpia y dataset ocupado)
```

---

## 3. ⚠️ RESTRICCIÓN ARQUITECTÓNICA CENTRAL DE B4

**Las 13 funciones del motor son `owner-only`.** Verificado en catálogo:

```text
precios_cotizar.proacl = {postgres=X/postgres}
```

`REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated, service_role` está aplicado a **todas**.

### Consecuencia directa

**La Edge pública NO puede llamar al motor vía `supabase.rpc('precios_cotizar')`.** Ni con `anon`, ni con `authenticated`, ni con `service_role`. Falla con *permission denied*.

**La Edge pública debe usar una conexión PostgreSQL privilegiada server-side** (connection string con rol autorizado), **no** el Data API / PostgREST.

Esto ya estaba decidido en B0:

> **D-PR-06** — La superficie pública (web/bot) es una **Edge Function dedicada**, separada del gateway autenticado, con **conexión server-side privilegiada** (NO anon/service RPC).

**B4 debe partir de acá.** Si el diseño propone RPC vía Data API, está mal.

Alternativa a evaluar en el diseño: crear un **rol PG dedicado** (p. ej. `precios_reader`) con `GRANT EXECUTE` solo sobre `precios_cotizar` / `precios_cotizar_congelar` / `precios_cotizacion_obtener`, y que la Edge use ese rol. Es una **decisión abierta de B4** (§12).

---

## 4. Funciones disponibles — firmas exactas

Extraídas de `pg_proc`. **B4 las consume; no las rediseña** (salvo bug comprobado).

### Núcleo (las 3 que B4 expone)

```text
precios_cotizar(p_payload jsonb) -> jsonb                 STABLE     owner-only
precios_cotizar_congelar(p_payload jsonb) -> jsonb        VOLATILE   owner-only
precios_cotizacion_obtener(p_cotizacion_id uuid) -> jsonb STABLE     owner-only
```

- `precios_cotizar` — **read-only puro**. No escribe, no lockea, **sin `FOR UPDATE`, sin advisory locks**. Probado con oráculo de cero mutación.
- `precios_cotizar_congelar` — **único writer**. Escribe **solo** en `cotizaciones_precio`. **No** crea pre-reserva, **no** crea reserva, **no** toca disponibilidad. Solo congela si `ok && disponible && reservable_online`.
- `precios_cotizacion_obtener` — lectura + validación de vigencia (TTL 30 min, D-PR-07).

### Helpers (10 — NO se exponen; son internos del motor)

```text
precios_config(p_clave text) -> text                                              STABLE
precios_redondear(p_monto numeric, p_base numeric) -> numeric                     IMMUTABLE
precios_money(p_monto numeric) -> text                                            IMMUTABLE
precios_resolver_temporada(p_fecha date) -> text                                  STABLE
precios_clasificar_noche(p_fecha date) -> text                                    STABLE
precios_asignar_ordinales(p_fecha_in date, p_fecha_out date, p_noches_evento date[])
    -> TABLE(fecha date, tipo text, ordinal integer, concepto text)               STABLE
precios_precio_noche(p_perfil text, p_fecha date, p_tipo_noche text, p_concepto text) -> jsonb   STABLE
precios_eventos_interseccion(p_perfil text, p_fecha_in date, p_fecha_out date) -> jsonb          STABLE
precios_extra_persona(p_perfil text, p_personas integer, p_noches_count integer) -> jsonb        STABLE
precios_disponibilidad_noches(p_id_cabana bigint, p_fecha_in date, p_fecha_out date) -> jsonb    STABLE
```

Todas: `SECURITY INVOKER`, `search_path` fijo, `owner-only`.

---

## 5. Contrato JSON real

### Entrada de `precios_cotizar` / `precios_cotizar_congelar`

```json
{
  "id_cabana": 1,
  "fecha_in": "2026-08-03",
  "fecha_out": "2026-08-06",
  "personas": 2,
  "canal": "web",
  "modo": "online"
}
```

- `id_cabana`, `fecha_in`, `fecha_out`, `personas` → **obligatorios**.
- `canal` ∈ `web | whatsapp | bot | portal` (default `web`).
- `modo` ∈ `online | manual` (default `online`).
- **`fecha_out` es EXCLUSIVE.** `2026-08-03 → 2026-08-06` = **3 noches**.
- Cualquier violación → `ok:false, error:"payload_invalido"`.

### Salida — caso feliz (25 claves de nivel superior, shape REAL)

```json
{
  "ok": true,
  "disponible": true,
  "reservable_online": true,
  "motivo_no_reservable": null,
  "modo": "online",
  "canal": "web",
  "id_cabana": 1,
  "perfil_tarifario": "grande",
  "capacidad_max": 5,
  "fecha_in": "2026-08-03",
  "fecha_out": "2026-08-06",
  "personas": 2,
  "noches_count": 3,
  "precio_total": "310000",
  "monto_sena": "155000",
  "monto_saldo": "155000",
  "extra_persona_total": "0",
  "cargo_saldo_transferencia_mp": "7750",
  "precio_source": "motor_estandar",
  "desglose_noches": [ ... ],
  "desglose_eventos": [ ... ],
  "restricciones": [ ... ],
  "warnings": [ ... ],
  "cotizacion_id": null,
  "expires_at": null
}
```

**`desglose_noches[i]`:**
```json
{
  "fecha": "2026-08-03",
  "tipo": "semana",
  "ordinal": 1,
  "concepto": "semana_noche_1",
  "temporada": "baja",
  "precio": "130000",
  "override_id": null
}
```

**⚠️ Los montos viajan como STRING** (`"310000"`, no `310000`). Es un invariante de dinero del proyecto. **El gateway/Edge NO debe castearlos a number.**

`precio_source` ∈ `motor_estandar | evento_especial | mixto | manual_override`.

### Salida — caso `ok=false`

```json
{
  "ok": false,
  "error": "temporada_no_resuelta",
  "detalle": { "ok": false, "error": "temporada_no_resuelta", "fecha": "2031-01-05" },
  "id_cabana": 1,
  "perfil_tarifario": "grande"
}
```

### Salida de `precios_cotizar_congelar`

Devuelve el mismo shape de `precios_cotizar` **más**:
- si congeló: `cotizacion_id` (uuid), `expires_at` (timestamptz), `congelada: true`, `ttl_minutos`
- si no congeló (no vendible online): `congelada: false`, `detalle_congelamiento`

### Salida de `precios_cotizacion_obtener(uuid)`

- Vigente → el snapshot completo + `cotizacion_id`, `expires_at`, `vigente: true`
- Vencida → `{ ok:false, error:"cotizacion_vencida", cotizacion_id, expires_at }`
- Inexistente → `{ ok:false, error:"cotizacion_no_encontrada", cotizacion_id }`

---

## 6. Allowlist de errores — **B4 debe preservar la semántica**

### A) `ok = false` (no se pudo cotizar)
`payload_invalido` · `perfil_desconocido` · `temporada_no_resuelta` · `tarifa_incompleta` · `cotizacion_vencida` · `cotizacion_no_encontrada`

### B) `ok = true` + `reservable_online = false` (deriva a humano)
`no_disponible` · `evento_parcial_no_vendible` · `bloque_finde_obligatorio` · `estadia_larga_derivar` · `excede_capacidad` · `evento_sin_paquete_perfil` · `evento_personas_max_excedido`

### C) `warnings` (informan, no bloquean)
`capacidad_max_override` · `recargo_extra_persona` · `cargo_saldo_transferencia_mp`

### ⚠️ Semántica que B4 NO puede romper

- **`motivo_no_reservable` es "EL PRIMERO GANA"** (COALESCE). La disponibilidad tiene máxima prioridad y **enmascara** al resto.
- **`restricciones[]` es ACUMULATIVO.** Contiene **todas** las reglas violadas.

> Ejemplo real: una estadía de 10 noches sobre fechas ocupadas devuelve
> `motivo_no_reservable = "no_disponible"` pero
> `restricciones = [no_disponible, estadia_larga_derivar]`.

**Si B4 expone solo `motivo_no_reservable`, PIERDE información.** Debe exponer **ambos**.

- En `modo=manual` los motivos de (B) se degradan a **warnings**, **excepto `no_disponible`** (la disponibilidad real nunca se pisa).

**B4 no debe convertir estos errores en errores genéricos ni en HTTP 500.**

---

## 7. Reglas técnicas del frente (invariantes verificados)

1. **`fecha_out` es EXCLUSIVE** en todo el motor.
2. `obtener_disponibilidad_rango(desde, hasta)` → **`hasta` también es exclusive**. Se llama con `(fecha_in, fecha_out)` **tal cual**. Nunca `fecha_out - 1`.
3. Noche vendible ⟺ `estado IN ('disponible','checkout_disponible')`. **`checkout_disponible` SE VENDE.**
4. `paquetes_evento.fecha_in/fecha_out` = `[fecha_in, fecha_out)`.
5. El **5% de transferencia/MP** que devuelve la cotización es **estimativo** (sobre el saldo). El cargo **real** lo calcula A10-MP sobre la porción efectivamente transferida (`Math.round(tr * 0.05)`, al peso), como línea `extra` que **no reduce saldo**.
6. **Montos como STRING.**
7. **Fingerprint de funciones: siempre normalizado** (`replace(prosrc, chr(13), '')`).
8. `bloqueos` y `reservas` tienen **exclusion constraints** — un fixture solapado **aborta la transacción entera** (ERROR, no FAIL).
9. Nodo Postgres de n8n **envuelve el resultado en una columna `resultado`** → leer `item.resultado.ok`, no `item.ok`.
10. Smokes: asertar reglas contra `restricciones[]`, nunca contra `motivo_no_reservable`.

---

## 8. Objetivo de B4

Exponer **de forma segura** el motor ya cerrado, en **dos superficies separadas**:

### Superficie PÚBLICA (web / bot / WhatsApp)
- Edge Function dedicada, **conexión PG privilegiada server-side** (§3).
- **Sin auth de operador.**
- Payload estricto (shape + tipos + rangos).
- Expone **solo cotización**: cotizar / congelar / obtener.
- **Sin** escrituras operativas, **sin** reserva directa, **sin** override manual, **sin** admin de grillas/temporadas/eventos/overrides/config.
- Rate limit + CORS.

### Superficie PORTAL/GATEWAY autenticada (operadores/socios)
- Solo si se decide reutilizar la cotización desde el portal (**decisión abierta**, §12).
- Molde del Carril C: acción en el CATALOG + wrapper n8n + doble allowlist.
- **NO mezclar con A07 / reserva manual.**

---

## 9. Infra existente — rutas a inspeccionar (LEER PRIMERO)

| Qué | Dónde |
|---|---|
| **Gateway (Edge Function `portal-api`)** | `Docs/Supabase/index.ts` — CATALOG de acciones, validadores de payload, HMAC |
| **Wrappers n8n** | `Workflows/n8n/Supabase/portal-*__TEMPLATE.json` |
| **Promoción OPS** | `Docs/Implementacion/Carril_C/PROMOCION_OPS/` |
| **Canónico de schema** | `Docs/Implementacion/6B_SCHEMA_SQL.md` |
| **Bootstrap para harness** | `Docs/Implementacion/bootstrap_entorno_nuevo_v1.12.0/01_BOOTSTRAP_PARTE_B_BASE.sql` |
| **Frontend** | `src/` — `actionRegistry.ts`, `callPortal.ts`, `AuthProvider.tsx` |

### Patrones vigentes del gateway (confirmar en el repo)

- Entrada del CATALOG: `'accion.nombre': { handler, roles, webhook, validate, injectActor, isWrite }`.
- Ejemplo real: `'reserva.crear_manual': { handler:'n8n', roles:['vicky','socio'], webhook:'portal-a07-crear-reserva__OPS', validate: payloadCrearManual, injectActor:true, isWrite:true }`.
- **HMAC sobre raw body + timestamp ±300s + nonce firmado.**
- **Revalidación de 5 dimensiones en el wrapper n8n**: HMAC · timestamp · rol · action · ambiente.
- **Doble allowlist**: gateway CATALOG + wrapper `ROLES_OK`.
- Los validadores usan **allowlist estricta de claves** (`PERMITIDAS`) — clave desconocida = rechazo.
- Wrappers OPS llevan sufijo `__OPS`; los de TEST no.
- **n8n Variables NO están disponibles** en el plan de Franco → HMAC secret embebido (**Modo B**) con guard `SECRET.startsWith('__PEGAR_')`.
- Roles del sistema: `socio` (Franco, Rodrigo, Remo), `vicky` (operaciones), `jenny` (limpieza, acceso restringido).
- **Temporal dead zone**: en el Edge, los `const` de validadores deben declararse **antes** del `CATALOG`.
- Webhook node **typeVersion 2.1** requerido para materializar el body binario.

---

## 10. Entorno

- **Supabase / PostgreSQL 17.6** — TEST (`bdskhhbmcksskkzqkcdp`) y OPS (`lpiatqztudxiwdlcoasv`). **B4 trabaja solo en TEST.**
- **Harness local PostgreSQL 16.14** para pre-validación de SQL.
- **n8n Cloud**: `federicosecchi.app.n8n.cloud`.
- **Vercel** (auto-deploy desde `main`).
- Repo: `github.com/francogg89-ai/vita-delta-reservas`.
- Cabañas: 1=Bamboo, 2=Madre Selva, 3=Arrebol (**grande**, cap. base 3 / máx 5) · 4=Guatemala, 5=Tokio (**chica**, cap. base 2 / máx 4).

---

## 11. Fuera de alcance estricto de B4 — **NO TOCAR**

> **B3.1 y el motor de horarios están siendo trabajados por otro grupo en paralelo.** Tocarlos desde acá **pisaría** su SQL, gateway, wrappers y UI.

- `crear_prereserva` · `confirmar_reserva`
- **A07 / `reserva.crear_manual`**
- Override manual de capacidad (B3.1)
- **Reglas de horarios · motor de horarios**
- **Validaciones de gap**
- **Validaciones de "muy cerca del check-in/check-out"**
- **UI de reserva manual**
- Escritura de reservas · pre-reservas · bloqueos
- Pagos · Mercado Pago
- **OPS** (ningún cambio)
- Canónico / cierre / satélites
- Hardening legacy
- **Núcleo del motor** (B3) — salvo bug comprobado
- **`precios_cotizar_disponibles`** — bloque posterior. Primero se expone sólido el cotizar por cabaña.

---

## 12. Decisiones abiertas de B4 (cerrar ANTES de artefactos)

1. **Rol PG para la Edge pública.** ¿Usar el owner directamente, o crear un rol dedicado (p. ej. `precios_reader`) con `GRANT EXECUTE` solo sobre las 3 funciones del núcleo? (Recomendación esperada: rol dedicado, mínimo privilegio.)
2. **¿El portal autenticado consume el motor en B4, o recién en B5?**
3. **Idempotencia del congelamiento.** ¿Se requiere `idempotency_key`, o se aceptan múltiples cotizaciones equivalentes amparadas por el TTL de 30 min?
4. **Rate limit** de la superficie pública: ¿por IP? ¿por ventana? ¿qué límites?
5. **CORS**: ¿qué orígenes se permiten? (dominio de la web pública).
6. **¿Wrapper n8n o Edge directa?** El motor no necesita orquestación; un wrapper n8n agrega latencia y superficie. Evaluar Edge directa vs molde Carril C.
7. **Shape HTTP**: ¿se devuelve el JSON del motor tal cual, o se envuelve? ¿Qué códigos HTTP para cada categoría de error (§6)?
8. **Exposición de `desglose_noches`** al público: ¿se muestra el detalle noche por noche, o solo el total? (Puede revelar la estructura de la grilla.)

---

## 13. Smokes esperados en B4

**Funcionales:** cotización feliz · no disponible · tarifa incompleta · evento parcial · evento completo · excede capacidad · estadía larga · payload inválido · congelar · obtener vigente · obtener vencida.

**De seguridad / no-regresión:**
- **no crea reserva ni pre-reserva** (oráculo de conteo antes/después)
- **no toca A07 ni `crear_prereserva`**
- **no modifica las funciones del motor** (fingerprint normalizado `098f2fe7…` intacto)
- **estructura B2A intacta** (`da52a16c…`)
- **grilla B2B intacta** (32 tarifas)
- `anon` / `authenticated` / `service_role` **no pueden** ejecutar el motor directamente (ACL intacta)
- la superficie pública **no expone** escrituras operativas ni admin
- rate limit efectivo
- **`restricciones[]` se preserva** en la respuesta HTTP (no se pierde info)
- **montos siguen siendo string** en la respuesta HTTP

---

## 14. ANEXO — Handoff de B3.1 (para el otro grupo)

**Estado: DISEÑADO · NO EJECUTADO · SIN ARTEFACTOS · SIN FINGERPRINT.**

### Hallazgo que condiciona el diseño

`confirmar_reserva` **construye la reserva copiando campos desde `pre_reservas`** (`v_pre.personas`, `v_pre.mascotas`, `v_pre.ninos`, …); no los recibe por payload.

Pero **`pre_reservas` NO tiene columnas de override** (solo `notas` y, desde B2A, `cotizacion_id`). En cambio **`reservas.capacidad_override` SÍ existe** (B2A).

→ **El flag no tiene por dónde viajar de la pre-reserva a la reserva.** B3.1 requiere una micro-migración estructural:
- `pre_reservas.capacidad_override BOOLEAN NOT NULL DEFAULT FALSE`
- `pre_reservas.motivo_override_capacidad TEXT`
- `reservas.motivo_override_capacidad TEXT`

*(El fingerprint B2A `da52a16c…` NO cambia: su alcance no incluye estas columnas. Pero es cambio estructural real y debe declararse.)*

### Punto de parche exacto

`crear_prereserva`, guard actual (**antes** de la validación de disponibilidad, paso 7):

```sql
IF v_personas > v_cabana.capacidad_max THEN
  RETURN jsonb_build_object('ok', false, 'error', 'excede_capacidad',
                            'capacidad_max', v_cabana.capacidad_max);
END IF;
```

Propuesta:

```sql
IF v_personas > v_cabana.capacidad_max THEN
  IF NOT v_override THEN  RETURN 'excede_capacidad';   END IF;   -- comportamiento actual intacto
  IF v_motivo IS NULL OR trim(v_motivo) = '' THEN
                          RETURN 'override_sin_motivo'; END IF;   -- motivo OBLIGATORIO
END IF;
```

Y `confirmar_reserva` propaga `v_pre.capacidad_override` / `v_pre.motivo_override_capacidad` al `INSERT INTO reservas`.

### Barreras que se sostienen solas

- El guard de capacidad está **antes** del paso 7 → **la disponibilidad nunca se pisa**.
- `confirmar_reserva` toma `pg_advisory_xact_lock(10,0)` + `(1, id_cabana)` + `FOR UPDATE`, revalida, y captura `exclusion_violation` → `no_disponible`.
- `exc_reservas_no_overlap` y `exc_bloqueos_no_overlap` son **constraints de DB**: ningún override las saltea.
- `reserva.crear_manual` ya es `roles: ['vicky','socio']` — **jenny excluida**.
- El gateway valida con **allowlist estricta de claves** → hay que sumar las dos nuevas explícitamente.
- El `idem` de A07 se calcula sobre un canon de claves de negocio (`ORDEN`) — evaluar si `override_capacidad` entra al canon.

### Decisiones ABIERTAS (D-CAP-01…06)

1. **D-CAP-01** — ¿Quién ejerce el override: `vicky`+`socio`, o socio-only?
2. **D-CAP-02** — ¿Tope duro (`personas <= capacidad_max + N`) o sin tope?
3. **D-CAP-03** — ¿`override_capacidad` entra al canon de idempotencia de A07?
4. **D-CAP-04** — ¿Auditoría en `precios_auditoria` (`entidad='reserva'`, ya admitido por el CHECK) o en `log_cambios`?
5. **D-CAP-05** — ¿El precio (`cotizacion_id` / `precio_snapshot`) entra en B3.1, o queda para B5?
6. **D-CAP-06** — ¿Se persiste `capacidad_override=true` si el override no se ejerció (personas ≤ máx)? (Recomendación: **no**, para no ensuciar la auditoría.)

**Ninguna está cerrada.** El otro grupo decide.

---

## 15. Prompt de arranque de B4

```markdown
# B4 — Motor de Precios v2 · Wrappers / Gateway / Edge pública

Respondé en español rioplatense con voseo.

Vos diseñás, inspeccionás, validás y generás artefactos. Yo ejecuto todo:
Supabase, n8n, Vercel, git, TEST/OPS. No toques servicios directamente.

## Primera acción OBLIGATORIA: leer el repo

Antes de proponer nada, cloná fresco y citá rutas/funciones exactas:

  git clone --depth 1 https://github.com/francogg89-ai/vita-delta-reservas

Inspeccioná como mínimo:
- Docs/Supabase/index.ts          (Edge Function `portal-api`: CATALOG, validadores, HMAC)
- Workflows/n8n/Supabase/         (wrappers portal-*__TEMPLATE.json)
- Docs/Implementacion/6B_SCHEMA_SQL.md   (canónico)
- src/                            (actionRegistry.ts, callPortal.ts)

No diseñes de memoria. El repo es la autoridad.

## Contexto

Adjunto el kickoff completo (B4_KICKOFF.md). Leelo entero antes de responder.

Puntos que NO podés pasar por alto:

1. Las funciones del motor son **owner-only**
   (`precios_cotizar.proacl = {postgres=X/postgres}`).
   La Edge pública NO puede usar supabase.rpc() con anon/service_role.
   Necesita conexión PG privilegiada server-side (D-PR-06).

2. `motivo_no_reservable` es "el primero gana"; `restricciones[]` es ACUMULATIVO.
   Si exponés solo el motivo, perdés información.

3. Los montos viajan como STRING. No castear a number.

4. `fecha_out` es EXCLUSIVE.

## B3.1 está DELEGADO a otro grupo — NO TOCAR

crear_prereserva · confirmar_reserva · A07 / reserva.crear_manual ·
override manual de capacidad · reglas de horarios · motor de horarios ·
validaciones de gap · validaciones de check-in/check-out próximo ·
UI de reserva manual · escritura de reservas · pagos · OPS.

## Lo que necesito ahora: DISEÑO B4, sin artefactos

Después de leer el repo, respondé:

1. Qué rutas/acciones existen hoy en el gateway.
2. Dónde conviene exponer `precios_cotizar` (Edge pública nueva, acción del
   gateway, wrapper n8n, o combinación) y por qué.
3. Cómo resolvés el problema del ACL owner-only (rol dedicado vs owner).
4. Contrato HTTP/JSON propuesto (request + response + códigos de estado).
5. Mapeo de la allowlist de errores sin perder semántica.
6. Seguridad: payload estricto, rate limit, CORS, HMAC/JWT si corresponde.
7. Idempotencia del congelamiento.
8. Smokes propuestos (incluyendo los de no-regresión: no crea reserva/pre-reserva,
   fingerprints intactos, ACL intacta).
9. Riesgos.
10. Qué archivos tocarías y cuáles NO.

Cerrá las decisiones abiertas (§12 del kickoff) conmigo ANTES de generar código.
Hard stop en el diseño.
```

---

## 16. Archivos a subir a la conversación B4

**Imprescindibles:**
- Este documento (`B4_KICKOFF.md`)
- `Docs/Supabase/index.ts` (gateway actual)
- `Docs/Implementacion/6B_SCHEMA_SQL.md` (canónico)
- `CLAUDE.md`, `README.md`

**Recomendados:**
- `B3_RUNSHEET.md` (v2), `B2A_RUNSHEET.md`, `B2B_RUNSHEET.md`
- `B0_MOTOR_PRECIOS_V2_DECISIONES_CONCEPTUALES.md` (D-PR-01…20)
- `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`
- 1–2 wrappers n8n de ejemplo (p. ej. `portal-a25-ingresos__TEMPLATE.json`) como molde del Carril C
- Salida de cierre de B3 (VERIFY + 40/40)

**No hace falta** subir el portal completo: B4 no toca UI de reserva manual.

---

## 17. Regla principal

```text
B4 CONSUME el motor de precios ya cerrado. No lo modifica.
B4 NO toca reserva manual, A07, crear_prereserva, horarios, gap, pagos ni OPS.
B4 expone: cotizar (read-only) · congelar (solo cotizaciones_precio) · obtener.
La Edge pública usa conexión PG privilegiada, NO el Data API.
```
