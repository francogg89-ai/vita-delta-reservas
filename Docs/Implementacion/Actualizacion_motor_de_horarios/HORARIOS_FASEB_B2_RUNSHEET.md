# HORARIOS_FASEB_B2 — Runsheet (resolver_horario standalone, SOLO TEST)

**Alcance:** crear `resolver_horario()` (función pura, sin writes) + hardening + comment. **NO** integra con `crear_prereserva` ni `obtener_disponibilidad_rango`. **NO** toca ninguna función existente.
**Entorno:** TEST. **NO OPS.**
**Artefacto SQL:** `HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql`.
**Ejecutor:** Franco. Claude no escribe en ninguna DB.
**Pre-validación:** la función se corrió contra un PostgreSQL 16 local con los 11 casos de prueba → **11/11 verde** (resultados embebidos abajo como esperado).

---

## Reglas futuras registradas, fuera de alcance de Fase B standalone

Estas reglas quedan **registradas para no perder contexto**, pero **NO** se implementan acá. `resolver_horario()` no las contempla.

### RF-1 — Excepción operativa por fecha/cabaña (par de overrides explícito)
Si operativamente se define un check-out tardío para una fecha (ej. `hora_checkout = 16:00`), normalmente el check-in de esa misma fecha debería moverse a `check-out + buffer_operativo`. Buffer de referencia actual: **2 horas** (ej. check-out 16:00 → check-in 18:00).
- En Fase B, `resolver_horario()` **NO infiere** el check-in desde el check-out.
- Preferencia de diseño: guardar **ambos overrides explícitos** (`hora_checkout = 16:00` **y** `hora_checkin = 18:00`).
- Más adelante el portal operativo puede ayudar a **autogenerar el par**, pero la base debe quedar **explícita y auditable** en `overrides_operativos`.

### RF-2 — Override manual por reserva puntual (afecta el recambio del día)
Si Vicky acuerda que una reserva concreta de una cabaña salga más tarde (ej. martes 16:00), eso debe afectar el **próximo check-in posible de esa misma cabaña ese mismo día**.
- Regla futura esperada: `próximo check-in mínimo = checkout real anterior + buffer_operativo`.
- Ejemplo: reserva A en Bamboo sale martes 16:00 → nueva reserva en Bamboo ese martes no debería entrar antes de las 18:00.
- Esto **NO** pertenece a `resolver_horario()`. Pertenece a una futura **`validar_recambio_horario()`**, que mirará reservas/pre-reservas existentes y sus **horarios reales persistidos**.

### RF-3 — Separación conceptual (tres responsabilidades distintas)
- **`resolver_horario()`** = reglas generales por fecha/cabaña: base, patrón domingo, `overrides_operativos`. (Esto es Fase B.)
- **Override manual por reserva** = horario real pactado para una reserva puntual. (Capa superior futura.)
- **Validación de recambio horario** = evita que una nueva reserva entre antes de que haya tiempo operativo entre salida y entrada. (Futura `validar_recambio_horario()`, post-A26.)

---

## Paso 0 — Baseline READ-ONLY (antes de aplicar; cero writes)

```sql
-- 0.1 La función todavía NO existe (esperado: t)
SELECT to_regprocedure('public.resolver_horario(bigint, date)') IS NULL AS resolver_ausente;

-- 0.2 Tablas y config presentes (esperado: filas > 0 en config; overrides vacía)
SELECT (SELECT count(*) FROM configuracion_general WHERE clave LIKE 'hora_%') AS claves_hora,
       (SELECT count(*) FROM overrides_operativos) AS overrides_filas;   -- esperado overrides_filas = 0

-- 0.3 Schema/session sanity (esperado: current_schema = public; si no, FRENAR antes del Paso 1)
SELECT current_setting('search_path') AS search_path, current_schema() AS current_schema;

-- 0.4 Sanidad exacta de config horaria (esperado: los 6 valores de abajo)
SELECT clave, valor
FROM configuracion_general
WHERE clave IN (
  'hora_checkin_default','hora_checkin_domingo',
  'hora_checkout_default','hora_checkout_domingo',
  'hora_checkin_max_cliente','hora_checkout_min_cliente'
)
ORDER BY clave;
-- Esperado: hora_checkin_default=13:00, hora_checkin_domingo=18:00, hora_checkout_default=10:00,
--           hora_checkout_domingo=16:00, hora_checkin_max_cliente=22:00, hora_checkout_min_cliente=07:00.
-- Si current_schema != public (0.3) o algún valor de 0.4 difiere => FRENAR (no ejecutar Paso 1).
```

**Gate del Paso 0:** seguir al Paso 1 **solo si** `resolver_ausente=t`, `overrides_filas=0`, `current_schema=public`, y los 6 valores de 0.4 coinciden. Cualquier desvío → frenar.

## Paso 1 — Aplicar el SQL (sin writes de datos)

Ejecutar **`HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql` completo**, sin selección parcial. Es DDL puro: `CREATE OR REPLACE FUNCTION` + `REVOKE` + `COMMENT`. **No inserta filas. No consume secuencias.** La función es nueva → `CREATE OR REPLACE` la crea; el `REVOKE` la cierra (proacl IS NULL ⇒ PUBLIC).

## Paso 2 — Verificación

### 2.A — Atributos de la función (read-only)
```sql
SELECT proname, prosecdef AS definer, provolatile AS volat, proacl IS NOT NULL AS acl_cerrado
FROM pg_proc WHERE proname='resolver_horario';
-- Esperado: definer=f (INVOKER), volat=s (STABLE), acl_cerrado=t.
```

### 2.B — Base / domingo / fechas distintas (READ-ONLY, cero writes)
Asume `overrides_operativos` vacía (0 filas). Usá una cabaña real (ej. 4) y una fecha hábil + un domingo.
```sql
-- Caso 1 BASE (lunes)
SELECT resolver_horario(4, DATE '2026-07-06');
-- Esperado: {"ok":true,"hora_checkin":"13:00:00","hora_checkout":"10:00:00","origen_checkin":"base","origen_checkout":"base"}

-- Caso 2 DOMINGO
SELECT resolver_horario(4, DATE '2026-07-05');
-- Esperado: {"ok":true,"hora_checkin":"18:00:00","hora_checkout":"16:00:00","origen_checkin":"patron_domingo","origen_checkout":"patron_domingo"}

-- Caso 10 CHECK-IN/CHECK-OUT POR FECHAS DISTINTAS
SELECT (resolver_horario(4, DATE '2026-07-05')->>'hora_checkin')  AS checkin_domingo,   -- 18:00:00
       (resolver_horario(4, DATE '2026-07-06')->>'hora_checkout') AS checkout_lunes;    -- 10:00:00
```

### 2.C — Overrides (con fixtures; CONSUME `id_override`)
**Consumo explícito:** estos casos hacen `INSERT` real a `overrides_operativos` → consumen `id_override` (BIGSERIAL, **no transaccional**: el `ROLLBACK` borra los datos pero la secuencia queda avanzada ~7 valores). Si te molesta el consumo, sabé que es inevitable para probar overrides reales; el `ROLLBACK` igual deja la tabla limpia (0 filas).

```sql
BEGIN;
INSERT INTO overrides_operativos (fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por) VALUES
 (DATE '2026-08-10', DATE '2026-08-14', NULL, 'hora_checkin', '16:00', 'fixture global',  'smoke_faseb'),
 (DATE '2026-08-10', DATE '2026-08-10', 4,    'hora_checkin', '17:00', 'fixture cabana',  'smoke_faseb'),
 (DATE '2026-09-10', DATE '2026-09-10', 4,    'hora_checkin', '25:99', 'fixture cast',    'smoke_faseb'),
 (DATE '2026-09-20', DATE '2026-09-20', 4,    'hora_checkin', '23:30', 'fixture ventana', 'smoke_faseb'),
 (DATE '2026-09-25', DATE '2026-09-25', 4,    'hora_checkin', '7:00',  'fixture formato', 'smoke_faseb');
-- Empate: mismo created_at, gana mayor id_override (12:00)
INSERT INTO overrides_operativos (fecha_desde,fecha_hasta,id_cabana,tipo_override,valor,motivo,creado_por,created_at) VALUES
 (DATE '2026-09-01', DATE '2026-09-01', 4, 'hora_checkout', '11:00', 'fixture empate viejo', 'smoke_faseb', TIMESTAMPTZ '2026-01-01 00:00:00+00'),
 (DATE '2026-09-01', DATE '2026-09-01', 4, 'hora_checkout', '12:00', 'fixture empate nuevo', 'smoke_faseb', TIMESTAMPTZ '2026-01-01 00:00:00+00');

-- Caso 3 GLOBAL (cabana 5, sin especifico) -> checkin 16:00 override_global
SELECT resolver_horario(5, DATE '2026-08-10');
-- Caso 4 CABANA gana a global -> cab4 17:00 override_cabana ; cab5 16:00 override_global
SELECT resolver_horario(4, DATE '2026-08-10') AS cab4, resolver_horario(5, DATE '2026-08-10') AS cab5;
-- Caso 5/6 MULTIPLE + EMPATE (checkout cabana 4) -> 12:00 override_cabana (mayor id_override)
SELECT resolver_horario(4, DATE '2026-09-01');
-- Caso 7 VALOR INVALIDO (cast) -> ok:false cast_invalido
SELECT resolver_horario(4, DATE '2026-09-10');
-- Caso 8 FUERA DE VENTANA -> ok:false fuera_de_ventana
SELECT resolver_horario(4, DATE '2026-09-20');
-- Caso 9 RANGO INCLUSIVO -> D+4 (08-14) aplica 16:00 ; D+6 (08-16) base/patron
SELECT resolver_horario(5, DATE '2026-08-14') AS dentro, resolver_horario(5, DATE '2026-08-16') AS fuera;
-- Caso 11 FORMATO ESTRICTO -> '7:00' (PG lo parsearia como 07:00, en ventana) -> ok:false formato_invalido
SELECT resolver_horario(4, DATE '2026-09-25');
ROLLBACK;  -- limpia los fixtures (id_override queda avanzado; es lo unico que persiste)
```

**Esperado (validado contra PG16 local):**
- Caso 3: `{"ok":true,"hora_checkin":"16:00:00","hora_checkout":"10:00:00","origen_checkin":"override_global","origen_checkout":"base"}`
- Caso 4: cab4 `...,"hora_checkin":"17:00:00",...,"origen_checkin":"override_cabana",...` ; cab5 `...,"16:00:00",...,"override_global",...`
- Caso 5/6: `{"ok":true,...,"hora_checkout":"12:00:00","origen_checkout":"override_cabana"}` (gana `id_override` mayor)
- Caso 7: `{"ok":false,"causa":"cast_invalido","error":"override_hora_invalido","valor":"25:99","id_override":<n>,"ventana_min":"07:00:00","ventana_max":"22:00:00","tipo_override":"hora_checkin"}`
- Caso 8: `{"ok":false,"causa":"fuera_de_ventana",...,"valor":"23:30",...}`
- Caso 9: `dentro` → `16:00:00 override_global` ; `fuera` → `18:00:00/16:00:00 patron_domingo` (08-16 es domingo)
- Caso 11: `{"ok":false,"causa":"formato_invalido","error":"override_hora_invalido","valor":"7:00","id_override":<n>,"ventana_min":"07:00:00","ventana_max":"22:00:00","tipo_override":"hora_checkin"}`

Casos 7/8/11 ejercen las **tres causas HARD**: `cast_invalido` (`25:99` pasa la regex pero el cast falla), `fuera_de_ventana` (`23:30` castea pero excede), `formato_invalido` (`7:00` ni siquiera matchea `^\d{2}:\d{2}(:\d{2})?$`).

## Evidencia para aprobar
1. 0.1/0.2/0.3/0.4 → resolver ausente, overrides en 0, `current_schema=public`, y los 6 valores de config correctos.
2. 2.A → `definer=f`, `volat=s`, `acl_cerrado=t`.
3. 2.B → casos 1, 2, 10 con el JSON esperado (read-only).
4. 2.C → casos 3–9 y 11 con el JSON esperado (con fixtures; tabla vuelve a 0 tras ROLLBACK).

## Reversión

`DROP FUNCTION public.resolver_horario(bigint, date);`
No hay datos que revertir (la función es pura, no escribió nada). Si corriste 2.C con `ROLLBACK`, `overrides_operativos` ya quedó en 0 filas; solo la secuencia `id_override` quedó avanzada (inocuo).

## Confirmación — NO se toca ninguna función existente

- `crear_prereserva`, `crear_bloqueo`, `confirmar_reserva`, `obtener_disponibilidad_rango`, `fecha_hoy_ar`: **intactas** (sus fingerprints no cambian; `resolver_horario` es nueva y nadie la llama todavía).
- EXCLUDE, modelo `[fecha_in, fecha_out)`, A07/A08, gateway, frontend, override manual, recambio: **sin tocar**.
- Canónico y OPS: **sin tocar**. Sin acuñar `D-*`/`L-*`.
- La integración (cablear el resolver en `crear_prereserva`/`obtener_disponibilidad_rango`) es un **bloque aparte, posterior**.
