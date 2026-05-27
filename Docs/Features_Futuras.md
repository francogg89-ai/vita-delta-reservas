# Features Futuras — Vita Delta Reservas

Este documento lista funcionalidades **identificadas como deseables** pero **no implementadas todavía**. No son pendientes técnicos de hardening (esos viven en `Pendiente_pre_produccion.md`) ni decisiones cerradas (esas viven en `DECISIONES_NO_REABRIR.md`).

Son features que en algún momento van a tener sentido implementar, pero que **no tienen un caso real urgente todavía**, así que se difieren hasta que aparezca el caso o se decida priorizarlas.

---

## Convención

Cada feature se documenta con:

- **Qué hace.**
- **Por qué se difiere.**
- **Cuándo conviene implementarlo.**
- **Workaround actual** (si existe).
- **Esbozo técnico** (suficiente para retomar sin re-pensar de cero).

---

## Feature 1 — Cambio de horarios de check-in / check-out por cabaña + rango

**Identificada:** 2026-05-26.
**Origen:** conversación operativa post-cierre 6C.

### Qué hace

Permite a un operador (Franco/Rodrigo) **redefinir los horarios de check-in y/o check-out** de una cabaña específica, varias cabañas o todas, durante un rango de fechas determinado, sin afectar reservas existentes.

Ejemplos de uso:
- "La cabaña 17 entre el 15 y el 30 de septiembre va a tener check-out a las 16:00 y check-in a las 18:00 por mantenimiento del muelle."
- "Todas las cabañas el fin de semana del 20 al 22 de diciembre van a tener check-in a las 15:00 (sin la regla habitual de domingo)."

**Características requeridas:**
- Aplicable a 1, varias o todas las cabañas.
- Con `fecha_desde` y `fecha_hasta` (rango).
- Override solo afecta **pre-reservas/reservas nuevas** posteriores al override; reservas ya confirmadas no se modifican.
- Si vos cambiás check-out a las 16:00, el sistema **automáticamente** asegura que el check-in_min de esa cabaña en ese rango sea posterior (ej. 18:00) para evitar overlap.
- Si al crear el override hay reservas existentes con horarios incompatibles, la función rebota con `conflicto_con_reserva` listando qué reservas estarían afectadas.

### Por qué se difiere

1. **No es bloqueante.** El sistema funciona correctamente con los horarios default + regla de domingo (D47).
2. **Es un feature poco frecuente.** Franco lo identificó como "voy a usarlo pocas veces, pero quiero tener la opción".
3. **Construirlo sin un caso real concreto** tiene alto riesgo de generar un diseño con huecos que solo aparecen al usarlo en producción.
4. **Hay workaround actual** que cubre los casos operativos más típicos (ver abajo).

### Cuándo conviene implementarlo

Cuando aparezca **uno de estos escenarios reales**:

- Mantenimiento programado que requiere check-in tarde (no se puede hacer con un bloqueo porque la cabaña sí está disponible, solo con horario reducido).
- Evento puntual (ej. boda en el complejo) donde varias cabañas necesitan horarios coordinados distintos al default.
- Reglas estacionales sostenidas (ej. "en enero el check-in default es a las 14:00 en vez de 13:00" para todo un mes).

**Antes de implementarlo**, revisar:
- Si el caso se resuelve con `cabanas.hora_checkin_*` actuales (cambio permanente, no por rango).
- Si el caso se resuelve con un bloqueo (ver workaround abajo).
- Si el caso justifica abrir el feature completo.

### Workaround actual

**Para el caso operativo más típico — "huésped pidió quedarse el feriado, quiero dejar un día de margen"** — el workaround es **crear un bloqueo del día siguiente al check-out tardío**:

Ejemplo: reserva del 14 al 16 de junio (check-out el 16 a la mañana). Para evitar que entre alguien el 16 a la tarde:

```json
{
  "id_cabana": <id>,
  "fecha_desde": "2026-06-16",
  "fecha_hasta": "2026-06-17",
  "motivo": "uso_propio",
  "descripcion": "Día de transición tras checkout tardío del huésped X"
}
```

Esto cubre la noche del 16 al 17. La cabaña queda libre para reservas que empiecen el 17 o después.

**Comportamiento del daterange `[fecha_desde, fecha_hasta)`:**
- Reserva `[14, 16)` cubre noches 14→15 y 15→16. Termina con check-out el 16 a la mañana.
- Bloqueo `[16, 17)` cubre noche 16→17.
- No se solapan: el 16 está excluido de la reserva e incluido en el bloqueo.
- El día 17 a partir del horario de check-in del default, otro huésped puede entrar.

**Limitaciones del workaround:**
- No sirve para cambios de horario sostenidos (ej. "todo el mes de enero").
- No sirve para cambios de horario que **mantienen disponibilidad** (la cabaña sí se reserva, pero con horarios distintos).
- Para esos casos, el workaround no alcanza y conviene implementar el feature real.

### Esbozo técnico

Cuando llegue el momento de implementar:

#### Nueva tabla

```sql
CREATE TABLE cabanas_horarios_override (
  id_override          BIGSERIAL PRIMARY KEY,
  id_cabana            BIGINT REFERENCES cabanas(id_cabana),  -- NULL = todas
  fecha_desde          DATE NOT NULL,
  fecha_hasta          DATE NOT NULL,                          -- exclusive
  hora_checkin         TIME,                                   -- NULL = no override
  hora_checkout        TIME,                                   -- NULL = no override
  motivo               TEXT NOT NULL,
  descripcion          TEXT,
  creado_por           TEXT NOT NULL,
  activo               BOOLEAN NOT NULL DEFAULT TRUE,
  source_event         TEXT NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CHECK (fecha_hasta > fecha_desde),
  CHECK (hora_checkin IS NOT NULL OR hora_checkout IS NOT NULL),
  CHECK (
    hora_checkin IS NULL
    OR hora_checkout IS NULL
    OR hora_checkin > hora_checkout
  )
);
```

El último CHECK previene overlap: si se definen ambos horarios, check-in debe ser **posterior** al check-out (para evitar que dos huéspedes coincidan).

#### Función nueva

`crear_horario_override(payload jsonb) → jsonb` con patrón análogo a `crear_bloqueo`:

1. Validar payload.
2. Lock global + por cabaña.
3. Verificar conflictos con reservas existentes (si hay reserva confirmada con horarios incompatibles en el rango → rebotar con `conflicto_con_reserva`).
4. Verificar conflictos con otros overrides activos.
5. INSERT en `cabanas_horarios_override`.
6. Log en `log_cambios`.

Códigos de error esperados:
- `payload_invalido`
- `fechas_invalidas`
- `horarios_overlap` (si check-in <= check-out cuando ambos se proveen)
- `cabana_no_existe`
- `conflicto_con_reserva`
- `override_solapado`

#### Modificación de funciones existentes

`crear_prereserva()` y `obtener_disponibilidad_rango()` deben consultar `cabanas_horarios_override` **antes** de aplicar los defaults de `configuracion_general` y la regla D47.

Orden de prioridad:
1. ¿Hay override activo para esa cabaña + fecha? → Usar el override.
2. Si no, ¿es domingo y aplica D47? → Usar regla D47.
3. Si no, usar default de `configuracion_general`.

#### Workflow n8n nuevo

`vita_w08_crear_horario_override_supabase` con patrón análogo a W6.

Probablemente también:
- `vita_w09_desactivar_horario_override_supabase` para anular un override activo (sin perderlo del histórico, solo `activo=false`).
- Eventual extensión de W7 con una vista nueva `vista_horarios_override_activos`.

### Vinculación con `DECISIONES_NO_REABRIR.md`

Cuando este feature se implemente, agregar a "Decisiones aprobadas con código de referencia":

- **DXX** — Horarios de cabaña pueden tener overrides por rango de fechas vía `cabanas_horarios_override`. La función `crear_prereserva` y la vista de disponibilidad consultan esta tabla antes de aplicar defaults y D47.

---

## Convenciones para agregar features nuevos a este archivo

1. **Numerar secuencialmente** (Feature 2, Feature 3, etc.).
2. **Incluir fecha de identificación** y origen (qué conversación lo disparó).
3. **Documentar el workaround actual** si existe — es importante para saber cuándo conviene implementar vs cuándo se puede seguir con el workaround.
4. **Esbozo técnico suficiente para retomar sin re-pensar.** No tiene que ser el diseño final, pero sí tener una idea concreta del enfoque.
5. **Mantener este documento corto.** Si una feature crece mucho, sacarla a su propio archivo en `Docs/Arquitectura/` cuando se priorice.
