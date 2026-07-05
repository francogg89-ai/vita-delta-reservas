# S2 — Puerta sancionada simple `crear_override_horario(jsonb)` — RUNSHEET

**Sub-bloque S2. Solo la función de alta individual.** No incluye
`crear_paquete_dia_especial`, función de grupo/`todas_posibles`, gateway, frontend ni n8n.

- **Alcance:** SOLO **TEST** (`bdskhhbmcksskkzqkcdp`). **NO** OPS/canónico/gateway/frontend/workflows.
- **Sin acuñar `D-*`/`L-*`.** Ejecutás vos; yo no toco TEST/OPS/n8n/Vercel/git.

---

## Contrato del payload

```json
{
  "fecha_desde":   "2026-08-01",     // REQ, DATE
  "fecha_hasta":   "2026-08-05",     // opc, DATE (null/omitido = solo fecha_desde, R0)
  "id_cabana":     3,                 // opc/null (null/omitido = global estricto)
  "tipo_override": "hora_checkin",   // REQ, solo hora_checkin | hora_checkout (S2)
  "valor":         "15:00",           // REQ, TEXT
  "motivo":        "...",             // REQ, TEXT
  "creado_por":    "...",             // REQ, TEXT
  "activo":        true,              // opc, default true
  "source_event":  "..."              // opc, TEXT
}
```

- **`created_at` e `id_override` NO son parámetros** (los asigna la DB por default). Si vienen en
  el payload → `payload_invalido`.
- **S2 solo horarios** (tu preferencia): cualquier otro `tipo_override` de la tabla →
  `tipo_override_no_soportado`. Justificación de dejarlo acotado: los demás tipos
  (`minimo_noches`, `disponibilidad_bloqueada`, `escalonamiento_*`, `checkin/checkout_flexible`)
  tienen semántica y validación propias que exceden esta puerta; meterlos acá mezclaría contratos
  y validadores. Quedan para bloques posteriores.

### Semánticas
- `fecha_hasta NULL` = solo `fecha_desde` (**R0**).
- `id_cabana NULL` = **global estricto**: valida **todas las cabañas activas**; si una falla, falla todo.
- `id_cabana` específico = valida **solo esa cabaña**.
- `activo=false` se inserta **sin validar** horarios (no dispara incompatibilidad); el retorno lo
  marca con `activo:false` + `nota`. Se revalida cuando se lo active (por el trigger S1).
- `motivo`/`creado_por`/`source_event` son metadata; no afectan horarios.

### Retorno
- OK: `{ok:true, id_override, id_cabana, alcance, tipo_override, valor, fecha_desde, fecha_hasta, activo, nota}`.
- Error: `{ok:false, error, ...}` con `error` ∈ `{payload_invalido, tipo_override_no_soportado,
  cabana_no_encontrada, override_pisa_reserva, override_pisa_prereserva,
  override_incompatible_same_day, override_hora_invalido}` (más `detalle`/`detalle_validador`).
  `error_interno` no se usa salvo error real inesperado (esos propagan y abortan todo).

---

## Flujo interno (patrón obligatorio)

1. `pg_advisory_xact_lock(10,0)` **primero**.
2. Parsear payload; validar requeridos y casts → `payload_invalido` / `tipo_override_no_soportado`
   / `cabana_no_encontrada` según corresponda (antes de tocar la tabla).
3. **INSERT tentativo** en `overrides_operativos` dentro de una **subtransacción `BEGIN…EXCEPTION`**
   (no savepoints literales).
4. Validar los pares afectados (`applied_set`) con **`validar_estado_override` (S0)** — sin
   reimplementar el resolver. Solo si `activo=true`.
5. OK → persiste, devuelve `{ok:true, id_override, …}`.
6. Falla esperada → el `RAISE`/`EXCEPTION` revierte **solo el insert tentativo**; se recupera el
   verdict del `DETAIL` y se devuelve `{ok:false, error, …}`.
7. Errores inesperados propagan y abortan todo.
8. El **trigger diferido `trg_ov_guard` (S1)** queda como red final no evitable y revalida en el commit.

---

## Orden de ejecución (Supabase SQL Editor, **sin selección parcial** — L-8A-01)

1. **`HORARIOS_GUARD_S2_FUNCION_TEST.sql`** — gate (`ambiente=test` + resolver `58d75c1b` +
   ODR `37009a32154f93b80520500c0f15b46b` + 3 validadores S0 + `trg_guard_overrides()` +
   `trg_ov_guard`). Último SELECT → `funcion_ok = true`.
2. **`HORARIOS_GUARD_S2_SMOKES_TEST.sql`** — esperado:
   **`SMOKE S2 VALIDADO: compuerta 12/12 PASS, 0 FAIL`** con los cuatro residuales = 0.

**Rollback (si hace falta):** **`HORARIOS_GUARD_S2_ROLLBACK_TEST.sql`** — dropea solo
`crear_override_horario(jsonb)`; confirma `funcion_ausente` + R0/S0/S1 intactos.

---

## Cobertura de smokes (12 casos)

`1` alta válida cabaña `hora_checkin` libre → ok:true **e inserta** · `2` alta válida global
estricto → ok:true **e inserta global** · `3` same-day inválido (`co16` solo) → ok:false
`override_incompatible_same_day` **y NO inserta** · `4` reserva comprometida → ok:false
`override_pisa_reserva` **y NO inserta** · `5` pre-reserva vigente → ok:false
`override_pisa_prereserva` **y NO inserta** · `6` tipo no soportado → ok:false
`tipo_override_no_soportado` · `7a` fecha inválida → ok:false `payload_invalido` · `7b`
`fecha_hasta < fecha_desde` → ok:false `payload_invalido` · `8` `id_cabana` inexistente →
ok:false `cabana_no_encontrada` · `9` `fecha_hasta NULL` con comprometido en `+5` → ok:true
(solo afecta `fecha_desde`) · `10` `activo=false` → ok:true inactivo, sin incompatibilidad, e
inserta inactivo · `11` **trigger S1 sigue activo**: INSERT directo inválido (fuera de la
función) → FALLA.

Cada caso `ok:false` chequea además que **no quedó fila** en el ancla; los `ok:true` chequean que
**la fila existe**. El caso 11 corre temprano para aislar su `SET CONSTRAINTS trg_ov_guard IMMEDIATE`.

> **Patrón de dos fases (por qué):** la función inserta dentro de su propia subtransacción, y esa
> fila **no es visible** para un `EXISTS` del **mismo statement** (usa el snapshot del statement).
> Por eso el smoke separa: **fase 1** llama la función una vez por caso en su propio statement
> (guarda el jsonb en `_raw`); **fase 2**, en un statement aparte, computa el verdict con `EXISTS`
> (ya ve las filas insertadas). Materializar con CTE `MATERIALIZED` **no** alcanza —sigue siendo el
> mismo statement—; hacen falta statements separados.

---

## Validación previa (mi parte del split)

- **pglast** `parse_sql` + `parse_plpgsql` → **OK** en los dos SQL de S2.
- **Harness PostgreSQL 16 fiel** (schema real + resolver R0 + validadores S0 + trigger S1):
  **12/12 PASS, 0 FAIL**, residuales **0**; confirmado que la función **no deja override cuando
  devuelve `{ok:false}`**, que el **trigger S1 sigue disparando** tras crear S2, y que el rollback
  S2 elimina solo la función dejando R0/S0/S1 intactos.

---

**Freno acá.** No generé `crear_paquete_dia_especial`, función de grupo/`todas_posibles`,
gateway, frontend ni n8n. Cuando corras la función + smokes y me confirmes 13/13 verde en TEST,
seguimos con **S3** (`crear_paquete_dia_especial(jsonb)`: paquetes checkout+checkin y alcances
grupo/`todas_posibles`) o con lo que definas.
