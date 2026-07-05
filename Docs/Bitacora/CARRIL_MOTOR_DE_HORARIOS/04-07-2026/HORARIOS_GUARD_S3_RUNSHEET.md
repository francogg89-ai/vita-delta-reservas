# RUNSHEET — Motor de Horarios / Guard · Sub-bloque S3

**Función:** `crear_paquete_dia_especial(jsonb)` — puerta sancionada de **paquete de día especial**.
**Ámbito:** SOLO TEST. No toca OPS, canónico, gateway, frontend ni workflows. No acuña `D-*`/`L-*`.
**Depende de (deben estar verdes en TEST):** R0 (resolver), S0 (validadores), S1 (`trg_guard_overrides` + constraint trigger `trg_ov_guard`), S2 (`crear_override_horario`).

---

## Qué hace

Carga un **paquete**: override `hora_checkout` **+** override `hora_checkin` en **una sola operación lógica**, con **dos** validaciones:

1. **Estado final válido** (validadores S0): el estado resuelto no pisa reservas/pre-reservas y respeta el gap same-day.
2. **Efecto pretendido** (postcondición de precedencia): que el paquete quede como **horario ganador** del resolver para cada cabaña/fecha aplicada.

El trigger diferido `trg_ov_guard` (S1) revalida el estado en el `COMMIT`.

**Por qué no reutiliza S2 internamente** (decisión aprobada): dos altas ingenuas a `crear_override_horario(jsonb)` validarían una mitad **antes** de que exista la otra. Con solo `hora_checkout=16:00` presente, el check-in vigente sería el base (13:00) → gap negativo → `override_incompatible_same_day`, y rechazaría la mitad antes de tiempo. S3 inserta **ambas mitades tentativas** en su propia subtransacción y recién ahí valida.

### Chequeo de efecto pretendido (nuevo)

El resolver ordena `(id_cabana IS NOT NULL) DESC, created_at DESC, id_override DESC`: **una cabaña específica gana sobre global**, y a igual especificidad gana el `created_at` más nuevo. Consecuencia: al insertar un paquete **global**, una cabaña que ya tiene un override **específico** para esa fecha/tipo **sigue ganando** con su hora vieja — el estado final puede ser válido (S0 pasa) pero el paquete **no quedó aplicado**. Para cerrar ese agujero, después de insertar y después de S0, para cada cabaña/fecha aplicada se exige:

```
resolver_horario(id_cabana, fecha).hora_checkout = hora_checkout solicitada
resolver_horario(id_cabana, fecha).hora_checkin  = hora_checkin  solicitada
```

Si no coincide → **`paquete_no_aplicado_efectivamente`** (con `detalle_validador` que incluye `esperado`/`obtenido`). Esto **no reemplaza** S0/S1; es una validación adicional. Para paquetes **per-cabaña** el override insertado es el más específico y más nuevo → normalmente gana (el chequeo es defensa en profundidad y garantiza la postcondición); para **global**, el chequeo es la corrección central.

## Contrato del payload

```json
{
  "fecha":         "2026-12-25",   // REQ, DATE (fecha_desde)
  "fecha_hasta":   null,            // opc, DATE (null = solo fecha)
  "hora_checkout": "16:00",         // REQ, TEXT(TIME)
  "hora_checkin":  "18:00",         // opc; si falta => checkout + gap_minutos
  "gap_minutos":   120,             // opc, default 120; < 120 => payload_invalido
  "alcance":       "cabana",        // REQ: cabana | grupo_estricto | grupo_posibles | global_estricto | todas_posibles
  "id_cabana":     3,               // REQ si alcance=cabana
  "ids_cabanas":   [1,2,3],         // REQ si alcance in (grupo_estricto, grupo_posibles); sin duplicados
  "motivo":        "...",           // REQ
  "creado_por":    "...",           // REQ
  "source_event":  "..."            // opc; deriva hijos deterministas
}
```

`created_at` / `id_override` **no** son parámetros (los asigna la DB) → `payload_invalido`.

### Reglas de gap (cerradas)

1. `gap_minutos` falta → default **120**.
2. `gap_minutos < 120` → **`payload_invalido`** (antes de insertar; no depende de S0/S1). La barrera DB exige mínimo 2 h; S3 no intenta un paquete con gap menor esperando que S0/S1 lo frenen después.
3. `hora_checkin` falta → derivar `hora_checkout + gap_minutos`.
4. `hora_checkin` explícita → validar `hora_checkin − hora_checkout >= gap_minutos`.
5. Como `gap_minutos >= 120`, queda garantizado `hora_checkin − hora_checkout >= interval '2 hours'`.
6. Check-in (derivado o explícito) `<= hora_checkout` (cruza medianoche) → `payload_invalido`.

### `ids_cabanas`

Requerido para `grupo_estricto`/`grupo_posibles`, y validado de forma **robusta y parseable** antes de tocar `jsonb_array_elements_text`/`v_ids`:

- **Forma mal formada** → `payload_invalido`: clave **ausente**, JSON **null**, **no-array** (object/string/number) o **array vacío**. La condición usa `NOT (p_payload ? 'ids_cabanas') OR jsonb_typeof(...) IS DISTINCT FROM 'array'` y recién tras confirmar que es array llama `jsonb_array_length` — así no depende del short-circuit del `OR` ni arriesga el error `cannot get array length of a scalar`, y evita el `FOREACH expression must not be null` que se daba con la clave ausente.
- **Contenido inválido** → `ids_cabanas_invalidos`: **duplicados** (ej. `[1,1,2]`) o **id inexistente**. Motivo: `ids_cabanas` es un **conjunto** de cabañas objetivo; un duplicado insertaría dos paquetes para la misma cabaña.

### `source_event` — hijos deterministas

Si viene `source_event`, cada mitad se marca:
`<source_event>:checkout:<id_cabana|global>` y `<source_event>:checkin:<id_cabana|global>`. Si no viene, las mitades quedan con `source_event NULL`.

## Arquitectura de transacción por alcance

| alcance | transacción | resultado si conflicto o sin efecto | `modo_aplicacion_real` |
|---|---|---|---|
| `cabana` | all-or-nothing (1 subtx) | no queda ninguna mitad | `cabana_unica` |
| `grupo_estricto` | all-or-nothing (1 subtx) | no queda nada del grupo | `expandido_por_cabana` |
| `global_estricto` | all-or-nothing (1 subtx), **2 overrides globales reales** (`id_cabana NULL`) si todas las activas quedan válidas y **efectivas** | no queda ningún global; **no expande** | `global_real` |
| `grupo_posibles` | subtx **por cabaña** | aplica válidas/efectivas, excluye el resto con reporte; nunca global | `expandido_por_cabana` |
| `todas_posibles` | subtx **por cabaña** (todas las activas) | aplica válidas/efectivas, excluye el resto; **nunca global** | `expandido_por_cabana` |

- Siempre `pg_advisory_xact_lock(10,0)` **primero** (Capa 0).
- Subtransacciones `BEGIN … EXCEPTION` (no savepoints literales).
- En modos "posibles", si **ninguna** cabaña aplica → `ok:false` `sin_cabanas_aplicables`.
- Rango multi-día: la exclusión es **a nivel cabaña completa** (si falla en cualquier fecha del rango, se excluye entera).

## Retorno

`ok:true`:
```
{ ok, alcance_solicitado, modo_aplicacion_real, fecha_desde, fecha_hasta,
  hora_checkout, hora_checkin, gap_minutos,
  cabanas_aplicadas[], cabanas_excluidas[{id_cabana,error,detalle}],
  overrides_creados[{id_cabana,id_override_checkout,id_override_checkin}] }
```
`ok:false` (estricto): `{ ok:false, error, alcance_solicitado, id_cabana, fecha, detalle_validador }`.
`ok:false` (`sin_cabanas_aplicables`): `{ ok:false, error, alcance_solicitado, cabanas_excluidas[] }`.

**Errores parseables:** `payload_invalido, cabana_no_encontrada, ids_cabanas_invalidos, alcance_no_soportado, sin_cabanas_aplicables, paquete_no_aplicado_efectivamente, override_pisa_reserva, override_pisa_prereserva, override_incompatible_same_day, override_hora_invalido`.

---

## Orden de ejecución en TEST

Correr **el script completo** (no seleccionar texto; el gate protege — L-8A-01).

1. **`HORARIOS_GUARD_S3_FUNCION_TEST.sql`**
   - Gate: `ambiente=test`, `public`, fingerprints resolver `58d75c1b…` + ODR `37009a32154f93b80520500c0f15b46b`, presencia de S0 + S1 + S2.
   - Crea la función (`CREATE OR REPLACE`), `REVOKE` espejo Bloque 23, `COMMENT`.
   - **Esperado:** `funcion_ok = true`.

2. **`HORARIOS_GUARD_S3_SMOKES_TEST.sql`**
   - Todo en `BEGIN … ROLLBACK`. No persiste nada.
   - **Esperado:** `NOTICE: SMOKE S3 OK: 22/22 PASS, 0 FAIL` y la fila final `overrides_residual = 0`, `reservas_residual = 0`, `prereservas_residual = 0`, `huespedes_residual = 0`.
   - Si la compuerta falla, aborta con el detalle de los casos no-PASS (jsonb incluido).

**Rollback (si hace falta revertir S3):** `HORARIOS_GUARD_S3_ROLLBACK_TEST.sql`
   - Dropea **solo** `crear_paquete_dia_especial(jsonb)`.
   - **Esperado:** `s3_ausente = true` y `r0_ok = s0_ok = s1_fn_ok = s1_trg_ok = s2_ok = true` (R0/S0/S1/S2 intactos).

---

## Cobertura de smokes (22 aserciones + residuales)

| # | caso | espera |
|---|---|---|
| 1 | cabana válido `co16+ci18` | `ok:true`, crea 2 overrides |
| 2 | cabana `gap_minutos=90` (<120) | `ok:false payload_invalido`, **no deja mitades** |
| 3 | cabana con reserva comprometida | `ok:false override_pisa_reserva`, **no deja mitades** |
| 4 | `global_estricto` todas libres | `ok:true global_real`, 2 overrides globales (`id_cabana NULL`) |
| 5 | `global_estricto` con 1 comprometida | `ok:false override_pisa_reserva`, **no deja globales** |
| 6 | `todas_posibles` con 1 comprometida | `ok:true expandido_por_cabana`, aplica al resto per-cabaña, excluye 1, **no crea global** |
| 7 | `todas_posibles` todas comprometidas | `ok:false sin_cabanas_aplicables`, no deja overrides |
| 8 | `grupo_estricto` con 1 conflictiva | `ok:false override_pisa_reserva`, **no deja nada del grupo** |
| 9 | `grupo_posibles` mismo grupo | `ok:true`, aplica `[1,3]`, excluye `2` |
| 10 | `ids_cabanas` con id inexistente | `ok:false ids_cabanas_invalidos` |
| 11 | `fecha_hasta NULL` solo afecta `fecha` (comprometido en +5 no bloquea) | `ok:true` |
| 12 | `source_event` trazable en checkout/checkin (hijos deterministas) | `ok:true` + hijos `…:checkout:<cab>` / `…:checkin:<cab>` |
| 13 | trigger S1 sigue activo: INSERT directo inválido (fuera de la función) | **FALLA** (constraint trigger dispara) |
| 14 | **efecto** — `global_estricto` con cabaña que ya tiene override **específico** distinto | `ok:false paquete_no_aplicado_efectivamente`, **no deja globales** |
| 15 | **efecto** — `todas_posibles` con cabaña sombreada por específico de **mayor precedencia** (`created_at` futuro) | `ok:true`, **excluye** esa cabaña con `paquete_no_aplicado_efectivamente`, aplica el resto, **no crea global** |
| 16 | **efecto** — `cabana` sombreada por específico de mayor precedencia (`created_at` futuro) | `ok:false paquete_no_aplicado_efectivamente`, **no deja mitades** |
| 17 | **control positivo** — sin sombra (seed global de **menor** precedencia) | `ok:true`, el paquete queda efectivo |
| 18 | `ids_cabanas` con duplicados `[1,1,2]` | `ok:false ids_cabanas_invalidos` |
| 19 | `grupo_estricto` **sin** `ids_cabanas` (clave ausente) | `ok:false payload_invalido` (antes: error `FOREACH ... must not be null`) |
| 20 | `grupo_posibles` con `ids_cabanas: null` (JSON null) | `ok:false payload_invalido` |
| 21 | `grupo_estricto` con `ids_cabanas` **string** (escalar no-array) | `ok:false payload_invalido` (antes: riesgo de error en `jsonb_array_length`) |
| 22 | `grupo_estricto` con `ids_cabanas: []` (array vacío) | `ok:false payload_invalido` |

**Nota — construcción del sombreado en los smokes de efecto:** para `global_estricto` (#14) la sombra es **natural** (una cabaña específica gana sobre el global, con `created_at` normal). Para los casos per-cabaña (#15, #16), el paquete inserta overrides específicos que son los más nuevos y por defecto **ganan**; para forzar la sombra, el seed específico se inserta con `created_at` **futuro** (vence por `created_at DESC`). Esto ejercita el chequeo de efecto como defensa en profundidad de la postcondición.

**Nota metodológica — patrón de dos fases:** los smokes de funciones que insertan y luego chequean con `EXISTS` fallan por **visibilidad intra-statement** (la fila insertada dentro de la subtransacción de la función no es visible a un `EXISTS` del mismo statement). Por eso: **Fase 1** = una llamada por caso en su propio statement (guardada en `_raw`); **Fase 2** = el verdict con `EXISTS` en statements separados. Las **anclas de fecha** se espacian de a **30 días** (los seeds llegan hasta +7; con ese aire, tras el redondeo a lunes de `_nextmon`, no hay colisión entre casos). El caso #13 (trigger directo con `SET CONSTRAINTS IMMEDIATE`) corre **antes** de sembrar overrides, para que su `IMMEDIATE` valide solo su propio insert malo.

## Validación previa (hecha antes de la entrega)

- `pglast` `parse_sql` + `parse_plpgsql` OK en los 3 artefactos.
- Harness PostgreSQL 16 (con S1 + S2 + S3 cargados): **22/22 PASS, 0 FAIL, residuales 0**.
- Verificado empíricamente: efecto pretendido cerrado (global_estricto no deja global si un específico lo sombrea; todas_posibles excluye la cabaña sombreada y aplica el resto sin global; cabana estricta falla si no gana; control positivo pasa); no quedan mitades ante `ok:false`; `ids_cabanas` mal formado (ausente/null/escalar/vacío) → `payload_invalido` sin error inesperado, y con duplicados/inexistente → `ids_cabanas_invalidos`; `gap_minutos < 120` → `payload_invalido`; rollback dropea solo `crear_paquete_dia_especial` dejando R0/S0/S1/S2 intactos.
