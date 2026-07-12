# QAGAP_B_RUNBOOK_PORTAL.md

Runbook de verificación del **gap de turno de punta a punta en TEST** (SP → A07 → gateway → frontend → calendario), reutilizando un único fixture de vecinos sembrado fuera de banda.

**Alcance:** SOLO TEST. No toca OPS, canónico, bootstrap, `configuracion_general`, vigencias ni overrides. No crea funciones operativas nuevas.
**Artefactos hermanos:** `QAGAP_A_SEED_TEST.sql` (siembra) · `QAGAP_C_CLEANUP_TEST.sql` (teardown).

---

## 0. Por qué hace falta un fixture

El portal **no puede** producir la geometría de gap por sí solo. El conflicto exige un **vecino con horas congeladas fuera de la ventana de cliente** (checkout tardío / check-in temprano), y la UI clampea a `checkout ≤ ~10:00` y `check-in ≥ ~13:00`. Con dos reservas por defecto adyacentes el gap da ≥ 3 h y nunca colisiona. Por eso el vecino se siembra por SQL, mientras que **la candidata sí se crea desde el portal** — que es lo que queremos probar.

Geometría (validador `validar_gap_bordes_congelados`, umbral `< 2h` conflicta, `>= 2h` permite):

| Caso | Condición | Fixture |
|---|---|---|
| `checkin_pisa_checkout_anterior` | `checkin_candidata − checkout_anterior < 2h` | vecino sale el día `dA` a `bciA − 1h` ⇒ gap **60 min** |
| `checkout_pisa_checkin_posterior` | `checkin_posterior − checkout_candidata < 2h` | vecino entra el día `dB+3` a `bcoB + 1h` ⇒ gap **60 min** |

---

## 1. Paso 0 — Elegir las dos islas (read-only)

`CalendarioRango` navega **mes a mes** (sin input de fecha), y `validarRango` exige que **todas** las noches del rango estén cargadas ⇒ la isla debe caer **dentro de un mismo mes** y a pocos clics. Este buscador devuelve rachas libres de ≥ 7 días que cumplen ambas cosas.

```sql
WITH p AS (
  SELECT (SELECT id_cabana FROM public.cabanas WHERE nombre = '<CABANA>') AS cab
),
dias AS (
  SELECT gs::date AS d
    FROM generate_series(CURRENT_DATE + 7, CURRENT_DATE + 75, INTERVAL '1 day') AS gs
),
ocupados AS (
  SELECT d.d
    FROM dias d CROSS JOIN p
   WHERE EXISTS (SELECT 1 FROM public.reservas r
                  WHERE r.id_cabana = p.cab
                    AND r.estado IN ('confirmada','activa','completada')
                    AND d.d BETWEEN r.fecha_checkin AND r.fecha_checkout)
      OR EXISTS (SELECT 1 FROM public.pre_reservas pr
                  WHERE pr.id_cabana = p.cab
                    AND ((pr.estado = 'pendiente_pago' AND pr.expira_en > NOW())
                          OR pr.estado = 'pago_en_revision')
                    AND d.d BETWEEN pr.fecha_in AND pr.fecha_out)
      OR EXISTS (SELECT 1 FROM public.bloqueos b
                  WHERE b.activo
                    AND (b.id_cabana = p.cab OR b.id_cabana IS NULL)
                    AND d.d BETWEEN b.fecha_desde AND b.fecha_hasta)
),
libres AS (
  SELECT d.d,
         (d.d - (ROW_NUMBER() OVER (ORDER BY d.d))::int) AS grp,
         date_trunc('month', d.d)::date AS mes
    FROM dias d
   WHERE NOT EXISTS (SELECT 1 FROM ocupados o WHERE o.d = d.d)
),
rachas AS (
  SELECT mes, MIN(d) AS desde, MAX(d) AS hasta, count(*) AS dias_libres
    FROM libres
   GROUP BY grp, mes          -- por racha Y por mes => la isla nunca cruza mes
  HAVING count(*) >= 7
)
SELECT mes, desde, hasta, dias_libres,
       (12 * EXTRACT(YEAR  FROM AGE(date_trunc('month', desde), date_trunc('month', CURRENT_DATE)))
          +  EXTRACT(MONTH FROM AGE(date_trunc('month', desde), date_trunc('month', CURRENT_DATE)))
       )::int AS clics_mes_siguiente
  FROM rachas
 ORDER BY desde;
```

De dos rachas `R1` y `R2` (idealmente en el mismo mes ⇒ una sola navegación):

- **`dA = R1.desde + 2`** → vecino `[dA−2, dA)`, candidata `[dA, dA+3)`
- **`dB = R2.desde + 1`** → candidata `[dB, dB+3)`, vecino `[dB+3, dB+5)`

Si una sola racha tiene ≥ 16 días, sirve para las dos islas separadas.

---

## 2. Paso 1 — Sembrar

Completá en `QAGAP_A_SEED_TEST.sql`: `<RUNID>` (solo `[a-z0-9_]`, ej. `qagap_20260712_01`), `<CABANA>`, `<dA>`, `<dB>`. Ejecutá el script **entero**.

Debe terminar en `SEED OK` con los `NOTICE` que imprimen los `id_reserva` de los vecinos y las horas congeladas. Cualquier gate que falle ⇒ `ROLLBACK` total (no quedan fixtures parciales).

Anotá **`T0` = timestamp del momento de sembrar** (para el barrido de inspección del paso 6).

---

## 3. Paso 2 — Caso A por el portal (`gap_checkin`)

En **Crear reserva**:

| Campo | Valor |
|---|---|
| Cabaña | la del seed |
| Rango | `dA` → `dA+3` |
| **Horas check-in / check-out** | **VACÍAS** ← crítico |
| Personas | 2 |
| Monto total | cualquiera > 0 |
| Huésped · nombre | `QAGAP <RUNID> candidataA` |
| Huésped · **teléfono** | **VACÍO** |
| Huésped · email | `qagap+<RUNID>.candidataa@example.invalid` |

> **Por qué las horas vacías:** el frontend solo envía `hora_checkin_solicitada` si el campo tiene valor (`if (form.hora_checkin) payload.hora_checkin_solicitada = …`). Vacío ⇒ el SP resuelve `NULL` ⇒ **congela el horario base** ⇒ el gap queda en exactamente 60 min. Si tipeás otra hora, el gap cambia y puede no dispararse.
>
> **Por qué email-only:** con teléfono vacío, `upsert_huesped` saltea el match por `telefono_normalizado` y matchea **solo por `lower(email)`**. Cero ambigüedad de normalización. Validado en las tres capas: frontend (`if (!telOk && !(emailPresente && emailOk))`), gateway (`if (telVal === null && emaVal === null) return bad(...)`) y SP (nombre + teléfono **o** email).

**Asserts:**

| Capa | Qué verificar |
|---|---|
| A07 (`Code: render`) | `ok: false` |
| A07 | `error.code === 'conflicto'` |
| A07 | `error.message` **empieza con** `gap_checkin:` |
| A07 | `error.detail === null` |
| A07 | **NO** `estado_incierto` · **NO** `error_interno` · **NO** `error_entorno` |
| UI | muestra **solo la frase humana, sin prefijo**: *"El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde."* |
| UI | **NO** aparece el banner de estado incierto |
| UI | tono **aviso** (no "Error del sistema" ni "Respuesta con formato inesperado") |
| Calendario | la candidata **NO** aparece en `dA..dA+3`; el vecino A **sí** en `dA−2..dA` |

---

## 4. Paso 3 — Caso B por el portal (`gap_checkout`)

Idéntico, con rango `dB` → `dB+3`, nombre `QAGAP <RUNID> candidataB` y email `qagap+<RUNID>.candidatab@example.invalid`.

> El checkout `dB+3` **es seleccionable** aunque el vecino ocupe esa noche: `maxFinSeleccionable` camina noches elegibles y **frena en la primera no elegible, y ese día es el checkout máximo** — comentario literal del código: *"habilita el back-to-back: salir el dia en que entra el siguiente"*.

**Asserts:** espejo del Paso 2, con prefijo `gap_checkout:` y la frase *"El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano."*

---

## 5. Paso 4 — Estado esperado antes del teardown

| Objeto | Esperado |
|---|---|
| Huéspedes vecinos | **2** |
| Huéspedes candidatas | **2** |
| Reservas | **2** — exclusivamente las vecinas (`source_event = RUNID`) |
| Pre-reservas QA | **0** |
| Pagos QA | **0** |

> **Los huéspedes candidatos quedan persistidos aunque el gap rechace.** No es un error del fixture: `crear_prereserva` llama a `upsert_huesped` **antes** de validar disponibilidad, ventana y gap, y el rechazo es un `RETURN` normal (sin excepción) en autocommit. Es una deuda real, registrada aparte.

---

## 6. Paso 5 — Inspección adicional (opcional, no bloqueante)

Detecta cualquier identidad creada durante la corrida que no siga el patrón (p. ej. un email mal tipeado en la UI). **El cleanup NO depende de esto**: identifica por email exacto.

```sql
SELECT id_huesped, nombre, email, created_at
  FROM public.huespedes
 WHERE created_at >= TIMESTAMPTZ '<T0>'
 ORDER BY created_at;
```

---

## 7. Paso 6 — Teardown

Ejecutá `QAGAP_C_CLEANUP_TEST.sql` (mismos `<RUNID>` / `<CABANA>`), entero.

- Si corriste **A y B**: dejá `c_candidatas_esperadas := 2` (default).
- Si abortaste **antes** de tocar el portal: poné `c_candidatas_esperadas := 0`.

**El cleanup aborta y preserva la evidencia** si encuentra: una candidata persistida como reserva o pre-reserva (⇒ **el gap no cortó**: eso es el hallazgo, no se limpia), un pago QA, un huésped con el tag del RUNID fuera de las cuatro identidades, o cardinalidades distintas de las esperadas.

**Residuo aceptado y declarado:** secuencias, logs de ejecución de n8n y `portal_idempotencia` (append-only). Nada más: `reservas` y `huespedes` no tienen triggers de `INSERT`/`DELETE` que escriban `log_cambios`, y el gap corta antes del `INSERT INTO log_cambios` de `crear_prereserva`.

---

## 8. Fuera de alcance de este runbook

**Las regresiones `no_disponible` y `excede_capacidad` NO se corren acá.** Esos rechazos también pasan por `upsert_huesped` antes de validar, así que **también dejan huéspedes huérfanos** y contaminarían las cardinalidades del fixture (que asertan exactamente 2 candidatas). Si las querés, necesitan **identidades QA propias** (`qagap+<RUNID>.regresion1@example.invalid`, etc.) y **cleanup explícito** para esas identidades — es un bloque aparte.

También fuera de alcance: `router3_confirmar` por gateway (el gap corta en `crear_prereserva`, PG-1, y el flujo nunca llega a PG-3). Su cobertura es el harness aislado ya validado y el smoke `B1_3_D_SMOKE_TEST.sql`.
