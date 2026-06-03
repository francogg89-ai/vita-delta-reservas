# Pendientes Pre-Producción

Lista de cambios y configuraciones a aplicar antes del despliegue de
producción. Incluye pendientes que no se hicieron en DEV, ajustes ya cerrados en DEV que deben replicarse en TEST/PROD, y decisiones postergadas explícitamente.

**Estado del archivo:** actualizado al cierre de Etapa 8C (sesión 2026-06-01).
Items cerrados durante Etapas 6D, 7A, 7B, 8A, 8B y 8C listados en los resúmenes de abajo;
detalle histórico de los items 6D en el Apéndice al final del documento.

---

## Items cerrados en Etapa 6D — resumen

| Item | Estado | Bloque que lo cerró | Apéndice |
|---|---|---|---|
| Hardening de validación SQL en funciones write | ✅ Cerrado | H2, H3, H4, H4-bis, H4-ter | A.1 |
| Fix `vista_ocupacion` (rango 25 → 24 meses) | ✅ Cerrado | H5 | A.2 |
| Espacio colgando en concatenación nombre + apellido | ✅ Cerrado | H6, H6-bis | A.3 |
| Tests de concurrencia C-1 a C-6 | ✅ Cerrado | H7 | A.5 |

## Items cerrados en Etapa 7A — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| 1.1 — Horizonte de disponibilidad/calendario configurable (60 → 120) | ✅ Cerrado | PreOPS-A6 | D-7A-03, `7A_CIERRE.md` |
| 1.2 — Alineación de tipo `ninos` (función vs columnas) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 | D-7A-02, `7A_CIERRE.md` |
| 1.3 — Contrato de `canal_pago_esperado` (validación manual) | ✅ Cerrado | Patch `crear_prereserva` v1.7.3 | D-7A-01, `7A_CIERRE.md` |

## Items cerrados en Etapa 7B — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Creación del entorno TEST (proyecto Supabase independiente) | ✅ Cerrado | 7B-1 | D-7B-01, `7B_CIERRE.md` |
| Paridad estructural TEST vs DEV (schema v1.7.3, 10/10) | ✅ Cerrado | 7B-2 | `7B_CIERRE.md` sección 5 |
| Seeds mínimos en TEST | ✅ Cerrado | 7B-3 | `7B_CIERRE.md` sección 6 |
| `pg_cron` activo en TEST con ejecuciones reales | ✅ Cerrado | 7B-3-cron | `7B_CIERRE.md` sección 7 |
| Permisos Data API normalizados en TEST (REVOKE EXECUTE) | ✅ Cerrado | 7B-GRANTS | D-7B-03, D-7B-05 |
| Workflows `__TEST` importados y validados (happy path 8/8) | ✅ Cerrado | 7B-4 | D-7B-04, `7B_CIERRE.md` sección 9 |
| Cadena transaccional end-to-end W2→W3→W4 en TEST | ✅ Cerrado | 7B-4 | `7B_CIERRE.md` sección 10 |

## Items cerrados en Etapa 8A — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Creación del entorno OPS (proyecto Supabase independiente) | ✅ Cerrado | 8A Bloques 1-2 | `8A_CIERRE.md` |
| Replicación del schema desde canónico v1.7.3 (paridad P01-P10 10/10) | ✅ Cerrado | 8A Bloque 4 | `8A_CIERRE.md` sección 3.1 |
| Seeds reales mínimos en OPS (item 4.1 — cabañas reales con IDs propios) | ✅ Cerrado | 8A Bloque 5 | `8A_CIERRE.md` sección 3.2 |
| Grants mínimos en OPS (OPS nació cerrado; REVOKE idempotente Opción B) | ✅ Cerrado | 8A Bloque 6 | confirmación D-8-03 |
| Default privileges de OPS (objetos futuros nacen cerrados) | ✅ Cerrado | 8A Bloque 7 | D-8-13, `8A_CIERRE.md` |
| `pg_cron` activo en OPS con corrida real verificada | ✅ Cerrado | 8A Bloque 8 | `8A_CIERRE.md` |
| Credencial n8n `vita_supabase_ops` verificada por identidad | ✅ Cerrado | 8A Bloques 10-11 | `8A_CIERRE.md` |

**Items pendientes activos:** ver secciones 1 a 8 abajo. **Nota:** las secciones 1.1, 1.2 y 1.3 quedaron cerradas en Etapa 7A (detalle conservado abajo con marca de cierre). Los items cerrados en 7B (entorno TEST levantado) se registran en el resumen de arriba; detalle completo en `7B_CIERRE.md`, no se duplica aquí.

## Items cerrados en Etapa 8B — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Capa de carga interna (Form Trigger n8n encadenando las 3 funciones) | ✅ Cerrado | 8B, validado en TEST | `8B_CIERRE.md` |
| Verificación de contratos reales de funciones contra OPS (read-only) | ✅ Cerrado | 8B sección 2 | `8B_CIERRE.md` §4 |
| Primer write real en OPS (smoke con reserva real, id 1) | ✅ Cerrado | 8B smoke OPS | `8B_CIERRE.md` §8 |
| Trazabilidad multiusuario verificada en producción (`created_by`/`validado_por`/`source_event`) | ✅ Cerrado | 8B smoke OPS | D-8B-04 |

**Pendiente operativo nuevo (no de schema/seguridad):** activar el workflow
`vita_w8b_carga_reserva__OPS` en n8n para que el equipo cargue por la URL del
formulario sin ejecución manual. El smoke se hizo con ejecución observada (correcto
para el primer write); para uso diario el workflow debe quedar activo. Ver
`8B_CIERRE.md` §10.

**Bitácora / cierres recientes:** `8A_CIERRE.md` (entorno OPS), `8B_CIERRE.md` (capa de carga).

## Items cerrados / tocados en Etapa 8C — resumen

| Item | Estado | Bloque que lo cerró | Referencia |
|---|---|---|---|
| Calendarios visuales (HTML operativo + HTML limpieza + Sheet resguardo, solo lectura) | ✅ Cerrado en TEST | 8C, validado en TEST | `8C_CIERRE.md` |
| Resguardo vía n8n+HTTP a API REST de Sheets, NO Apps Script | ✅ Decidido | 8C Bloque 3 | D-8C-22 |
| Item 3.1 (notificación a Jennifer por reserva próxima) → formalizado como 8C-bis | 🟡 Diferido | 8C diseño | D-8C-21, §3.1 |

**Pendiente nuevo de 8C (no de schema):** **smoke read-only en OPS** de los tres
calendarios (derivar a OPS, verificar con datos reales, decidir activación). Los tres
workflows quedan validados en TEST e inactivos. 8C no escribe en tablas
transaccionales, así que el smoke es de bajo riesgo. Ver `8C_CIERRE.md` §8.

**Pendiente diferido de 8C:** **8C-bis — Alerta por reserva próxima** (recoge el item
3.1 de este documento), trabajo posterior independiente con documento propio; canal
mail o Telegram a decidir. Ver §3.1 actualizado y `8C_CIERRE.md` §10.

**Bitácora del hardening:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` (H1-H7 cerrados; H8 cerrado).
**Cierre Etapa 7A:** `7A_CIERRE.md`.
**Cierre Etapa 7B:** `7B_CIERRE.md`.

---

## 1. Configuración de schema

### 1.1 Horizonte de disponibilidad — pasar de hardcoded a configurable

> **✅ CERRADO en Etapa 7A (PreOPS-A6, 2026-05-28).** El horizonte de
> `vista_disponibilidad` y `vista_calendario` ahora se lee desde
> `configuracion_general.horizonte_disponibilidad_dias` (valor `120`) con
> fallback `120`. La clave se agregó al seed del Bloque 21. Decisión D-7A-03.
> Ver `7A_CIERRE.md`. El contenido original se conserva abajo como referencia
> histórica del diseño.

**Estado actual (DEV):** `vista_disponibilidad` y `vista_calendario` tienen
el horizonte hardcoded a 60 días forward.

**Cambio para producción:**

Paso 1 — Agregar clave a `configuracion_general` (junto con el seed productivo):
- clave: `horizonte_disponibilidad_dias`
- valor: `120` (sugerido)
- tipo_valor: `integer`
- descripcion: `Horizonte forward en días para vista_disponibilidad y vista_calendario`

Paso 2 — Modificar las 2 vistas para leer desde config:

```sql
-- vista_disponibilidad con horizonte configurable
CREATE OR REPLACE VIEW vista_disponibilidad AS
SELECT *
FROM obtener_disponibilidad_rango(
  CURRENT_DATE,
  (CURRENT_DATE + COALESCE(
    (SELECT valor::INTEGER FROM configuracion_general
     WHERE clave = 'horizonte_disponibilidad_dias'),
    120
  ))::DATE,
  NULL
);

-- vista_calendario con horizonte configurable
-- Nota: el TRIM en huesped_nombre ya fue aplicado en H6 (Etapa 6D).
CREATE OR REPLACE VIEW vista_calendario AS
SELECT
  c.id_cabana, c.nombre AS cabana, r.id_reserva,
  r.fecha_checkin, r.fecha_checkout, r.hora_checkin, r.hora_checkout,
  r.personas, r.estado AS estado_reserva,
  TRIM(h.nombre || ' ' || COALESCE(h.apellido, '')) AS huesped_nombre,
  h.telefono AS huesped_telefono,
  r.monto_total, r.monto_saldo, r.encargado_semana
FROM reservas r
JOIN cabanas c ON c.id_cabana = r.id_cabana
JOIN huespedes h ON h.id_huesped = r.id_huesped
WHERE r.estado IN ('confirmada', 'activa')
  AND r.fecha_checkout >= CURRENT_DATE
  AND r.fecha_checkin <= (CURRENT_DATE + COALESCE(
    (SELECT valor::INTEGER FROM configuracion_general
     WHERE clave = 'horizonte_disponibilidad_dias'),
    120
  ))::DATE
ORDER BY r.fecha_checkin, c.id_cabana;
```

**Por qué `COALESCE` con default 120:** si la clave no existe por algún motivo,
la vista sigue funcionando con un valor sensato en vez de fallar.

**Cambio futuro del valor sin redeploy:**

```sql
UPDATE configuracion_general
SET valor = '90'  -- o '150' o lo que decidan
WHERE clave = 'horizonte_disponibilidad_dias';
```

**Origen:** decisión del Bloque 20, Fase 3.

### 1.2 Alineación de tipo `ninos` entre función y tablas

> **✅ CERRADO en Etapa 7A (patch `crear_prereserva` v1.7.3, 2026-05-28).**
> Resuelto con Opción 2: variable `v_ninos` alineada a `TEXT` en
> `crear_prereserva` (extract `NULLIF(TRIM(payload->>'ninos'), '')`, sin cast a
> BOOLEAN). Semántica: `NULL`=no informado, texto libre=detalle operativo.
> Los 3 registros legacy con `'false'` migrados a `NULL` (limpieza puntual).
> Decisión D-7A-02. Ver `7A_CIERRE.md`. Contenido original abajo como referencia.

**Estado actual (DEV):** ⏳ Pendiente liviano, no bloqueante.

**Contexto:** `crear_prereserva` declara la variable local `v_ninos` como `BOOLEAN` y aplica `(NULLIF(TRIM(payload->>'ninos'), ''))::BOOLEAN` en el extract. Sin embargo, las columnas `pre_reservas.ninos` y `reservas.ninos` son `TEXT nullable`. PostgreSQL aplica cast implícito BOOLEAN→TEXT al INSERT, persistiendo el valor textual `"false"` (observado empíricamente en los 3 registros existentes en DEV).

**Por qué es pendiente liviano:** funcionalmente inocuo hoy. No genera errores, no afecta operación, no se cruza con otras funciones. Pero la desalineación de tipo entre función y tablas es ruido documental que conviene resolver antes de TEST/PROD para evitar confusión futura.

**Opciones a evaluar:**
1. Alinear columnas a `BOOLEAN nullable` (cambio estructural en `pre_reservas` y `reservas`).
2. Alinear variable a `TEXT` (cambio en `crear_prereserva`).
3. Mantener desalineado y documentar como decisión definitiva.

**Origen:** hallazgo gestionado durante H8 Frente A (snapshot C.4). Documentado en changelog del bump v1.7.2 y en `H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md`.

### 1.3 Contrato de `canal_pago_esperado` — validación manual vs schema

> **✅ CERRADO en Etapa 7A (patch `crear_prereserva` v1.7.3, 2026-05-28).**
> Resuelto con Opción 1: restaurada la validación manual de
> `canal_pago_esperado` en el IF de obligatorios de `crear_prereserva` →
> rebota `payload_invalido` para ausente/vacío/whitespace. La columna sigue
> `TEXT NOT NULL`; el CHECK de 5 valores se mantiene. Validación de valores
> fuera del CHECK queda fuera de alcance. Decisión D-7A-01. Ver `7A_CIERRE.md`.
> Contenido original abajo como referencia.

**Estado actual (DEV):** ⏳ Pendiente liviano, no bloqueante.

**Contexto:** el extract de `crear_prereserva` aplica el patrón canónico `NULLIF(TRIM(payload->>'canal_pago_esperado'), '')`, pero `canal_pago_esperado` no aparece en la validación manual post-extract de campos obligatorios. La columna `pre_reservas.canal_pago_esperado` sigue siendo `TEXT NOT NULL`. Si llega ausente, vacío o whitespace, la variable queda NULL y el INSERT falla por constraint `NOT NULL` con error crudo de PostgreSQL, no con `payload_invalido` controlado.

**Por qué es pendiente liviano:** los workflows reales de n8n hoy aplican `nv()` defensivo en Build Payload, así que el escenario no es operativo en DEV. Pero para TEST/PROD con consumidores reales (webhook MP, bot, frontend), conviene decidir un contrato explícito.

**Opciones a evaluar:**
1. Restaurar validación manual de `canal_pago_esperado` en `crear_prereserva` con rebote controlado `payload_invalido`.
2. Hacer la columna nullable a nivel schema y aceptar pre-reservas sin canal preferido.
3. Mantener comportamiento actual y documentar como decisión definitiva.

**Origen:** hallazgo gestionado post-revisión del bump v1.7.2 durante H8 Frente A. Documentado en changelog del bump v1.7.2 y en `H8_SNAPSHOTS_SCHEMA_v1.7.2_WORKING_NOTES.md`.

### 1.4 `tipo_valor` sin poblar en `configuracion_general`

**Estado actual (DEV):** ⏳ Observación liviana, no bloqueante.

**Contexto:** las 10 claves de `configuracion_general` en DEV tienen
`tipo_valor = NULL` sin excepción (incluye enteros como `prereserva_expiracion_minutos=60`
y `horizonte_disponibilidad_dias=120`, booleanos como `escalonamiento_activo=true`,
y horas como `hora_checkin_default=13:00`). El campo `tipo_valor` existe en el
schema pero nunca se pobló. Hallazgo surgido en PreOPS-A6 (Etapa 7A) al
inspeccionar la tabla completa.

**Por qué es observación, no bloqueo:** ninguna función ni vista depende de
`tipo_valor` — los casts (`valor::INTEGER`, `valor::TIME`, etc.) son explícitos
en cada query. El sistema funciona correctamente con `tipo_valor=NULL`.

**Cuándo conviene resolverlo:** antes de construir el dashboard operativo (OPS)
si el dashboard va a usar `tipo_valor` para decidir cómo renderizar inputs de
configuración (un campo de texto vs un selector de hora vs un toggle booleano).

**Opción sugerida (no decidida):** poblar `tipo_valor` en las 10 claves con un
UPDATE puntual, con valores como `integer`, `boolean`, `time` según corresponda.
No se hizo en 7A para no abrir un mini-proyecto de normalización fuera del
alcance del horizonte configurable.

**Origen:** hallazgo de PreOPS-A6 (Etapa 7A, 2026-05-28).

### 1.5 Endurecimiento de permisos Data API en DEV (paridad con TEST)

> **✅ CERRADO en Etapa 7E (2026-05-28).** Se aplicó a DEV el `REVOKE EXECUTE`
> sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/
> `service_role`, dejando owner `postgres` intacto. Verificado: 0 fugas de
> EXECUTE, owner intacto, `postgres` ejecuta por ownership (n8n no afectado),
> schema sin cambios (201/6/19), residual de tablas intacto (480 grants).
> Decisiones D-7E-01, D-7E-02. Ver `7E_CIERRE.md`. El hallazgo A5 (residual
> amplio de permisos de tabla a roles Data API) quedó fuera de alcance por
> decisión (Opción 1 — 7E estricta) y se registró como pendiente nuevo 1.7. El
> contenido original se conserva abajo como referencia histórica del diseño.

**Estado actual (DEV):** ⏳ Pendiente. No diseñado ni planificado todavía.

**Contexto:** durante Etapa 7B se aplicó en TEST un modelo de grants mínimo
(REVOKE EXECUTE a `PUBLIC`/`anon`/`authenticated`/`service_role` sobre las 13
funciones del proyecto; sin grants Data API útiles para roles no-owner; `Dxtm`
residual documentado como aceptado — ver D-7B-03 y D-7B-05).

**DEV no se tocó durante 7B** (por decisión explícita) y queda más abierto que
TEST: en DEV las 13 funciones siguen invocables vía Data API por roles
`PUBLIC`/`anon`/`authenticated`/`service_role`. Esto no es bug de DEV — es el
default de PostgreSQL/Supabase aplicado al crear cada función — pero rompe la
simetría con TEST.

**Por qué es pendiente, no urgencia:** mientras DEV no tenga frontend público ni
consumidores Data API externos, no es un riesgo activo (n8n entra por pooler
como `postgres` owner y no depende de `EXECUTE` para invocar funciones). El
endurecimiento de DEV conviene **antes de cualquier integración que exponga
Data API en DEV** y **antes del diseño de OPS/PROD** (para no propagar la
asimetría).

**Alcance esperado (a diseñar en una etapa propia):**
1. Diagnóstico read-only equivalente al G1-G5 de 7B-GRANTS aplicado a DEV.
2. Verificación previa de que el REVOKE no rompe consumidores existentes (n8n,
   posibles otros).
3. REVOKE EXECUTE sobre las 13 funciones a `PUBLIC` + roles Data API,
   idempotente.
4. Verificación posterior (G3 sin filas + owner intacto).
5. Decisión sobre el `Dxtm` residual de DEV (probablemente igual criterio que
   TEST: aceptado, no tocado).

No diseñar ni ejecutar ahora — queda como pendiente futuro registrado.

**Origen:** decisión explícita de 7B de no tocar DEV; D-7B-03; `7B_CIERRE.md`
sección 14.

### 1.6 Contrato SQL de `registrar_pago` frente a entradas no-vacías mal tipadas

**Estado actual:** ⏳ Pendiente liviano, no bloqueante.

Revisión futura del contrato SQL de `registrar_pago` frente a entradas no-vacías
mal tipadas; hoy mitigado en workflows por `nv()` defensivo para
vacíos/undefined.

**Contexto:** el patrón canónico `NULLIF(TRIM(payload->>'campo'), '')` aplicado en
6D (item A.1, cerrado) cubre vacíos y whitespace en los campos obligatorios. Lo
que queda fuera de esa defensa son las entradas **no-vacías pero mal tipadas**
(ej. un `monto_esperado:"abc"` que no es vacío pero tampoco casteable a NUMERIC),
que siguen rompiendo con error crudo de PostgreSQL en lugar de un JSONB
controlado. En 7C esto se confirmó como comportamiento conocido (L-7C-03 para el
caso análogo de fecha en W1) y no se ejercitó como caso propio sobre W3 (fuera de
alcance del hardening por strings/whitespace).

**Por qué no es urgente:** los workflows reales aplican `nv()` defensivo para
vacíos/undefined, y los consumidores actuales (n8n manual) no generan entradas
mal tipadas. El endurecimiento conviene antes de conectar consumidores reales que
puedan enviar payloads arbitrarios (webhook MP, bot, frontend).

**Origen:** `7B_CIERRE.md` sección 14 (hardening SQL de `registrar_pago`);
reformulado tras 7C.

### 1.7 Residual amplio de permisos de tabla a roles Data API en DEV

**Estado actual (DEV):** ⏳ Pendiente. Hallazgo de Etapa 7E (snapshot A5), no
tratado por decisión de alcance.

**Contexto:** durante el snapshot read-only de 7E (Bloque A, query A5) se detectó
que en DEV los roles `anon`/`authenticated`/`service_role` tienen sobre **todas
las tablas y vistas** el set **completo** de privilegios
(`SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN`) y
sobre las secuencias `SELECT, UPDATE, USAGE`. El conteo de referencia (C5) fue
**480** grants de tabla a roles Data API. Esto es mucho más amplio que el `Dxtm`
residual de TEST (solo `TRUNCATE/REFERENCES/TRIGGER`, sin SELECT ni escritura —
ver D-7B-03). Es el default histórico de Supabase para proyectos creados antes
del cambio del 30/05/2026, no un bug introducido.

**Por qué 7E no lo tocó:** 7E se ejecutó en alcance estricto (Opción 1 — solo
`REVOKE EXECUTE` sobre funciones, que era el pendiente explícito 1.5). Revocar
los permisos de tabla habría excedido el alcance acordado, por lo que se decidió
documentarlo aquí y no tocarlo. Ver D-7E-01 y `7E_CIERRE.md` sección 8.

**Por qué no es urgencia:** no hay consumidores Data API/PostgREST activos en DEV
(sin frontend público, bot real, MercadoPago real, dashboard externo); n8n entra
como `postgres` owner por pooler y no usa estos grants; RLS sigue postergado
hasta tener frontend público.

**A decidir en etapa futura separada:** o se revoca el set de escritura/lectura
sobre tablas/vistas y los grants de secuencias a los roles Data API para alinear
DEV con el modelo mínimo de TEST, o se acepta y documenta como definitivo. En
cualquier caso, conviene resolverlo **antes de cualquier integración que exponga
Data API en DEV** y **antes del diseño de OPS/PROD** (para no propagar la
asimetría).

**Origen:** hallazgo A5 del snapshot de Etapa 7E; `7E_CIERRE.md` sección 8.

> **Actualización (Etapa 8A, 2026-05-29):** OPS **nació sin este problema**. Al
> crear `vita-delta-ops` con el switch "Automatically expose new tables = OFF"
> desde el día cero, el diagnóstico del Bloque 6 confirmó **0 grants
> SELECT/INSERT/UPDATE/DELETE a roles Data API sobre tablas** (solo el `Dxtm`
> inocuo, igual que TEST). Es decir, la asimetría A5 quedó **acotada a DEV** y no
> se propagó a OPS. La regla derivada para PROD (ver `8A_CIERRE.md` y
> `DECISIONES_NO_REABRIR.md` sección 8A) es crear el proyecto con los mismos
> switches que OPS para nacer cerrado. El item 1.7 sigue abierto **solo para DEV**:
> decidir si se revoca el residual amplio de DEV o se acepta como definitivo. No
> urgente (sin consumidores Data API activos en DEV).

### 2.1 Schedule pg_cron — expirar_prereservas_vencidas

**Estado actual (DEV):** ✅ Cerrado / activo. El job `expirar_prereservas`
está programado en pg_cron con schedule `*/5 * * * *` y validado end-to-end
(verificado 2026-05-27: 12 ejecuciones consecutivas con status `succeeded`
en una hora, una pre-reserva real procesada durante 6C).

**Pendiente pre-producción:** replicar y verificar el schedule cuando se
cree el ambiente PROD. _(TEST y OPS ya tienen los 2 jobs activos: TEST verificado
en 7B; OPS verificado en 8A Bloque 8 con una corrida real `succeeded`.)_

**Query a aplicar en TEST/PROD:**

```sql
SELECT cron.schedule(
  'expirar_prereservas',
  '*/5 * * * *',  -- cada 5 minutos
  'SELECT expirar_prereservas_vencidas()'
);
```

**Verificación post-schedule en TEST/PROD:**

```sql
SELECT * FROM cron.job WHERE jobname = 'expirar_prereservas';
```

**Cambio futuro de frecuencia (si fuera necesario):**

```sql
SELECT cron.unschedule('expirar_prereservas');
SELECT cron.schedule('expirar_prereservas', '*/10 * * * *',
                     'SELECT expirar_prereservas_vencidas()');
```

**Nota adicional:** en DEV también está activo el job `cleanup_cron_history`
(día 1 de cada mes a las 03:00 UTC) para purgar registros viejos de
`cron.job_run_details`. Replicar también en TEST/PROD.

**Origen:** decisión del Bloque 18, Fase 2. Ejecutado en Bloque 22 (Fase 3).

---

## 3. Notificaciones operativas (n8n)

### 3.1 Notificación a Jennifer cuando pre-reserva se convierte a reserva dentro del horizonte de limpieza

**Contexto:** `vista_limpieza_semana` muestra check-ins y check-outs de los
próximos 7 días. `vista_calendario_semanal` muestra estado día por día.
Ambas SOLO consideran reservas confirmadas y bloqueos (decisión de diseño:
no incluir pre-reservas que son "posibilidades", no certezas).

**Problema operativo:** si Jennifer mira la vista el lunes y planifica la
semana, una pre-reserva que se confirme el miércoles para el viernes
NO aparecerá en lo que ya consultó.

**Mitigación propuesta vía n8n:**

Workflow disparado cuando se crea una reserva (vía evento de
`confirmar_reserva`):
SI fecha_checkin de la nueva reserva está dentro de los próximos 7 días
ENTONCES enviar notificación a Jennifer (WhatsApp/Email) con:

Cabaña, fecha, hora checkin
Datos del huésped (nombre, teléfono, personas, mascotas)
Tipo: "Reserva nueva confirmada dentro de tu semana"


**Origen:** discusión del Bloque 20, Fase 3 (decisión de diseño confirmada
por Franco — Jennifer necesita updates cuando la semana cambia).

**Actualización (8C, 2026-06-01):** este pendiente quedó formalizado en el diseño de 8C como **Bloque 4 opcional / 8C-bis — Alerta por reserva próxima** (D-8C-21), explícitamente fuera del alcance del cierre de 8C (`8C_CIERRE.md`) y como trabajo posterior independiente con documento propio. Definiciones acordadas en 8C: dispara post-`confirmar_reserva` OK si `fecha_checkin ∈ [hoy, hoy+7]`; destinatarios equipo operativo y Jennifer; **no toca schema**. Canal a decidir entre **mail** (con regla de notificación en el celular de cada uno) o **Telegram** (push vía bot, nodo nativo de n8n) — NO requiere esperar la decisión de WhatsApp, que es comunicación externa con huéspedes (no la alerta interna). Engancha en el punto de extensión de 8B, junto con el disparo automático del Sheet de resguardo de 8C (Forma A: 8B invoca el workflow). Nota: los calendarios HTML de 8C (operativo y limpieza) **no** dependen de esta alerta ni de ningún disparo — son ventanas en vivo que se arman al abrir la URL y siempre muestran el estado actual; la alerta es una mejora de robustez (que algo avise sin tener que mirar), no un requisito de los calendarios.

### 3.2 Endpoint obligatorio antes de web pública — `consultar_disponibilidad_precio`

**Estado actual:** no implementado en DEV.

**Motivo:** antes de exponer una web pública, el cliente debe poder elegir cabaña, fechas y cantidad de personas, y recibir disponibilidad + precio sin crear una pre-reserva todavía.

**Cambio antes de producción web:**

Crear un endpoint backend —inicialmente en n8n o Supabase Edge Function— que:

- recibe `id_cabana`, `fecha_in`, `fecha_out`, `personas`;
- valida disponibilidad;
- calcula `monto_total` y `monto_sena`;
- devuelve desglose de precio;
- NO crea pre-reserva;
- NO permite que el frontend sea fuente de verdad del precio.

**Regla:** la web puede mostrar el precio, pero nunca calcularlo como autoridad final.

**Origen:** decisión D40 del schema 6B.

---

## 4. Configuración futura del seed productivo

### 4.1 Cabañas reales

**Estado actual:** ✅ Cerrado en DEV, TEST y OPS. Las 5 cabañas reales de
Vita Delta están cargadas en los tres entornos, con IDs propios de cada uno:
- **DEV (IDs 17-21):** Bamboo=17, Madre Selva=18, Arrebol=19, Guatemala=20, Tokio=21.
- **TEST (IDs 1-5):** Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5.
- **OPS (IDs 1-5):** Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5 (sembradas en Etapa 8A, Bloque 5).

Capacidades en los tres: grandes (Bamboo, Madre Selva, Arrebol) 3-5; chicas (Guatemala, Tokio) 2-4.

**Aprendizaje consolidado (D-7B-02):** los IDs **no son portables** entre
entornos. Cada workflow usa los IDs reales del ambiente al que apunta. En el form
de carga de 8B la cabaña se elige **por nombre**, no por ID (D-8-10), lo que hace
irrelevante el valor concreto del ID para el operador.

**Pendiente pre-producción:** replicar el mismo seed en PROD cuando se cree ese
ambiente, con IDs propios (no asumir secuencia desde 1 ni copiar de otro entorno).

### 4.2 Tarifas reales por temporada

Pendiente acordar con Franco y socios:
- Tarifas base por tipo (grande / chica)
- Tarifas por temporada (alta / media / baja)
- Tarifas por evento especial (años nuevo, semana santa, etc.)

**Estado actual:** DEV tiene solo una temporada baseline con multiplicador
neutro (no productiva).

### 4.3 Configuración productiva en `configuracion_general`

Valores sugeridos para producción (ajustar según decisión operativa):
- `hora_checkin_default`: 13:00
- `hora_checkin_domingo`: 18:00
- `hora_checkin_max_cliente`: 22:00
- `hora_checkout_min_cliente`: 07:00
- `hora_checkout_default`: 10:00
- `hora_checkout_domingo`: 16:00 (ver 4.4)
- `prereserva_expiracion_minutos`: 60 (revisable según patrones reales)
- `horizonte_disponibilidad_dias`: 120 (ver punto 1.1)

### 4.4 Agregar clave `hora_checkout_domingo` al seed productivo

**Estado actual (DEV):** ✅ Parcialmente cerrado. Clave cargada en DEV vía
hotfix v1.7 con valor `16:00`. Función `crear_prereserva` v1.7 ya la usa.

**Pendiente pre-producción:** agregar al seed productivo cuando se cree
PROD. Snippet:

```sql
INSERT INTO configuracion_general (clave, valor, descripcion, categoria) VALUES
  ('hora_checkout_domingo', '16:00',
   'Check-out cuando domingo es último día (vs default 10:00)', 'horarios');
```

**Razón operativa:** los clientes que se van un domingo se quedan hasta las
16:00 (última lancha colectiva). Sin esta clave, `crear_prereserva` usaría el
default hardcoded 16:00 (vía COALESCE) y funcionaría igual, pero queda registro
explícito en `configuracion_general`.

**Función dependiente:** `crear_prereserva` v1.7 lee esta clave en sección 2.
Si la clave no existe, se genera un warning en `log_cambios` pero la función
no falla.

**Origen:** Hotfix v1.7 (Fase 3, post-cierre).

### 4.5 Completar seed productivo no técnico

Antes de producción, completar y verificar datos reales de:

- `socios`: nombres reales y porcentajes definitivos.
- `cuentas_cobro`: alias, medio, titular, detalle y estado activo/inactivo.
- `temporadas`: alta, media, baja, fechas y multiplicadores.
- `feriados`: feriados nacionales/provinciales/locales relevantes.
- `eventos_especiales`: Año Nuevo, Semana Santa u otros eventos con reglas propias.
- `plantillas_mensajes`: textos reales para huéspedes/equipo.

**Regla:** no subir datos sensibles reales a GitHub. El documento puede decir qué cargar, pero no debe contener CBU, alias reales sensibles, wallets, teléfonos privados ni credenciales.

**Origen:** preparación de seed productivo posterior a Fase 3.

---

## 5. Seguridad

### 5.1 Row Level Security (RLS)

**Estado actual (DEV):** todas las tablas creadas con "Run without RLS".
Razón: n8n usa `service_role_key` que bypassea RLS de todas formas.

**Cambio para producción:**

Cuando se sume frontend público (web pública con login de huéspedes), se
deberán definir policies RLS sobre:

- `huespedes`: usuarios solo ven su propio registro.
- `pre_reservas`: usuarios solo ven las suyas.
- `reservas`: usuarios solo ven las suyas + staff ve todas.
- `pagos`: usuarios solo ven los suyos + staff ve todos.

**Decisión registrada en bitácora:** "RLS implementación pospuesta hasta
que haya frontend público. n8n con service_role_key no la necesita."

---

## 6. Validaciones empíricas pendientes

### 6.1 Tests de concurrencia — H7 de Etapa 6D ✅ CERRADO

**Estado:** ✅ Cerrado en bloque H7 de Etapa 6D (sesión 2026-05-27).
**Resultado:** 6 tests de concurrencia real en DEV aprobados (C-1, C-2, C-5, C-3, C-4, C-6). Sin deadlocks, sin races, sin doble booking, sin falsos positivos. Cero side effects persistentes post-cleanup.

**Detalle histórico completo:** ver Apéndice A.5 al final de este documento.

**Bitácora detallada:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md` sección H7.

### 6.2 Tests de carga real (post-tests-de-concurrencia)

Pendiente histórico. Validar comportamiento del sistema bajo carga real:

- 2 clientes intentando reservar la misma cabaña simultáneamente.
- Webhook MP llegando mientras Vicky confirma manualmente.
- Cron de expiración corriendo mientras hay pago en proceso.

Estos no reemplazan H7. H7 validó concurrencia controlada con SQL y locks; 6.2 queda como validación posterior de carga/uso real cuando existan consumidores reales conectados.

**Origen:** plan de Fase 4 según `6B_PLAN_FASES.md`.

### 6.3 Cobertura empírica de ramas `pre_lock` y `unique_violation` de idempotencia

**Estado:** ⏳ Pendiente opcional, no bloqueante. **`pre_lock` cubierto en 7C; resta solo `unique_violation`.**

**Contexto:** C-6 de H7 observó empíricamente la rama `post_lock` del detector de idempotencia de `crear_prereserva`. La rama `pre_lock` quedó **cubierta empíricamente en Etapa 7C** (caso A-W2-15): re-ejecución secuencial de W2 con la misma `idempotency_key` que la fixture ya existente devolvió `idempotent_match:true, recovery_path:'pre_lock'`, con el estado actual de la pre-reserva, sin crear duplicado. Resta solo `unique_violation`.

**Para gatillar `unique_violation`:** escenario más difícil de reproducir manualmente — requeriría que B pase el pre-check y el double-check post-lock pero choque con la constraint unique en el INSERT. Solo gatillable si ambas transacciones se cruzan dentro de una ventana muy estrecha entre el double-check y el INSERT.

**Decisión:** `unique_violation` queda como cobertura opcional pre-PROD si se considera necesario. No bloqueante para avanzar a TEST o a integraciones reales. No se intentó en 7C por requerir concurrencia pesada, que está fuera del alcance de esa etapa (H7 ya cubrió la concurrencia crítica).

**Origen:** observación empírica en C-6 de H7; `pre_lock` cerrado en A-W2-15 de 7C (`7C_CIERRE.md` sección 4).

### 6.4 Validación funcional ampliada sobre TEST (casos de error)

> **✅ CERRADO en Etapa 7C (2026-05-28).** La batería de caminos no-felices de
> los 8 workflows `__TEST` se ejecutó sistemáticamente sobre TEST: **48 casos
> funcionales (Grupo A) + 6 verificaciones transversales (TR-01/TR-02) = 54
> verificaciones conformes, 0 fallos inesperados, 1 mutación no planificada pero
> válida y comprendida (bloqueo id 2).** Idempotencia: rama `pre_lock` cubierta
> (resta `unique_violation`, ver 6.3). Ver `7C_CIERRE.md`. El contenido original
> se conserva abajo como referencia histórica del alcance planificado.

**Estado original (pre-7C):** ⏳ Pendiente. No diseñado todavía.

**Contexto:** Etapa 7B cerró con happy paths como evidencia suficiente para
validar el levantamiento del entorno TEST. Los casos de error de los 8
workflows no fueron ejercitados sobre TEST.

**Por qué no es bloqueante para avanzar:** la validez estructural y los happy
paths están confirmados (paridad 10/10 vs DEV; cadena W2→W3→W4 end-to-end OK).
Los casos de error están cubiertos a nivel SQL por las decisiones D-HARD-01 a
D-HARD-06 (patrón canónico de validación) y por los tests de hardening 6D
ejecutados en DEV. Ejercitarlos en TEST es validación de regresión sobre el
ambiente nuevo, no validación de un riesgo abierto.

**Alcance esperado:** ejecutar sobre TEST la batería de casos de error que
cubren los caminos no-felices de las funciones write y read-only. TEST es el
ambiente seguro para esto: aislado de DEV, sin consumidores reales, con la
cadena W2→W3→W4 y el bloqueo W6 ya validados como base.

**Casos a ejercitar (lista completa en `7B_CIERRE.md` sección 14):**

- cabaña inexistente (W1, W2, W6);
- solapamientos (reserva sobre bloqueo, bloqueo sobre reserva, pre-reserva
  sobre pre-reserva activa);
- doble pre-reserva con misma `idempotency_key` (idempotencia bajo colisión —
  ramas `pre_lock`/`post_lock`/`unique_violation` de `crear_prereserva`);
- re-confirmación de reserva ya convertida (W4 → `estado_invalido`);
- cancelación de estados no cancelables (W5 sobre pre-reserva ya terminal);
- payloads inválidos (campos obligatorios faltantes);
- campos vacíos / whitespace puro en obligatorios (validación del hardening
  D-HARD-01 y D-HARD-02);
- motivos inválidos (W5 con motivo fuera del enum; W6 con motivo fuera del
  enum);
- normalización defensiva (W3/W4/W5/W6) — verificar comportamiento con
  `""`/`"   "` en campos obligatorios de texto;
- pagos tardíos o inconsistentes (caso v1.3 de `registrar_pago`:
  `prereserva_no_activa` con `warning`).

**Datos de prueba en TEST como base:** la pre-reserva 2 ya convertida, la
reserva 1, el pago 1 y el bloqueo 1 conservados desde 7B sirven como fixtures
para algunos de estos casos (re-confirmación, re-cancelación, solapamiento con
bloqueo activo).

**Origen:** `7B_CIERRE.md` sección 14; cierre de 7B con scope acotado a happy
paths.

### 6.5 Diseño del bloque de limpieza/reset de TEST

**Estado:** ✅ Cerrado en Etapa 7D (2026-05-28). Ver `7D_CIERRE.md`.

**Contexto:** las Etapas 7B y 7C dejaron datos vivos en TEST que se conservaron
como evidencia (decisión D-7C-01, no-limpieza). 7D diseñó y ejecutó el bloque
dedicado de reset con SQL explícito y aprobado.

**Qué se ejecutó:**

1. Snapshot read-only pre-reset (Bloque A), con preflight anti-error-de-entorno
   por identidad exacta de las 5 cabañas TEST.
2. Limpieza transaccional atómica (Bloque B): `DELETE` explícito en orden seguro
   por FKs (`pagos` → `reservas` → `pre_reservas` → `bloqueos` → `huespedes` →
   `log_cambios`), sin `DROP/TRUNCATE ... CASCADE`, con re-gate dentro de la
   transacción.
3. Reset de secuencias a 1 (`ALTER SEQUENCE ... RESTART WITH 1`) solo en las 6
   tablas vaciadas con datos (D-7D-01).
4. Vaciado de `log_cambios` con evidencia documentada en el cierre (D-7D-02).
5. Verificación posterior (Bloque C): transaccionales en 0, seed intacto,
   secuencias reseteadas, cron intacto, vistas operativas ejecutando.

**Resultado:** TEST quedó como entorno limpio (schema v1.7.3 + seed estructural +
cron + grants + funciones/vistas/triggers + workflows `__TEST`, sin datos
transaccionales). Las 3 condicionales (`consultas`, `overrides_operativos`,
`gastos`) estaban en 0 y no entraron al borrado.

**Decisiones generadas:** D-7D-01 (reset de secuencias), D-7D-02 (vaciado de
`log_cambios` con evidencia documentada) — ver `DECISIONES_NO_REABRIR.md`.

**Verificación n8n (cerrada):** confirmado que los 8 workflows `__TEST` siguen
con la credencial `vita_supabase_test` apuntando a TEST (Franco, 2026-05-28).

**Origen:** D-7C-01 (`DECISIONES_NO_REABRIR.md`); `7C_CIERRE.md` secciones 8 y 9.
**Cierre:** `7D_CIERRE.md`.

---

## 7. Backup y rollback

### 7.1 Backup antes de aplicar schema en producción

Antes de ejecutar cualquier bloque o migración en PROD:

- exportar backup desde Supabase;
- guardar dump SQL o snapshot disponible;
- verificar que se puede restaurar o recrear el entorno;
- registrar commit exacto del repo usado para deploy.

### 7.2 Plan de rollback

Para cada ejecución productiva:

- definir hasta qué punto se puede revertir;
- no usar `DROP ... CASCADE` sin revisión explícita;
- documentar qué datos podrían perderse;
- si ya hay reservas reales cargadas, priorizar migraciones reversibles o scripts correctivos.

**Origen:** control mínimo de riesgo antes de producción.

---

## 8. Secrets y credenciales

### 8.1 Variables de entorno productivas

Antes de producción, verificar que las credenciales reales estén fuera de GitHub:

- Supabase Project URL.
- Supabase anon key, si aplica.
- Supabase service role key para n8n.
- Credenciales n8n.
- MercadoPago access token / webhook secret.
- WhatsApp / Meta tokens.
- Credenciales de email, si aplica.

**Regla:** ningún secret real debe commitearse. Usar `.env`, gestor de secretos o variables del entorno de n8n.

### 8.2 Archivo `.env.example`

Mantener solo placeholders:

```text
SUPABASE_URL=__SUPABASE_URL__
SUPABASE_SERVICE_ROLE_KEY=__SUPABASE_SERVICE_ROLE_KEY__
MERCADOPAGO_ACCESS_TOKEN=__MERCADOPAGO_ACCESS_TOKEN__
```

---

## Cómo usar este archivo

- **Cuando se identifica un nuevo pendiente:** agregar acá con título,
  estado actual, cambio para producción, y origen.
- **Cuando se completa un pendiente:** marcar como cerrado y, si genera
  contexto histórico relevante, mover a `Apéndice histórico` al final.
- **En la revisión pre-deploy:** verificar que TODOS los items se hayan
  resuelto o tengan decisión explícita de postergación.

---

# Apéndice histórico — items cerrados en Etapa 6D

Esta sección preserva el contexto técnico de los items resueltos durante
Etapa 6D (Hardening pre-producción). Las secciones que siguen describen
cómo fueron descubiertos los problemas y qué se decidió en cada caso.
**Para detalle de ejecución, ver `HARDENING_PRE_PRODUCCION_EJECUCION.md`.**

---

## A.1 [CERRADO en H2-H4-ter] Hardening de validación en funciones SQL write

**Descubierto durante:** 6C — implementación de W3 (registrar_pago).
**Fecha de descubrimiento:** 2026-05-25.
**Estado:** ✅ Cerrado en bloques H2, H3, H4, H4-bis, H4-ter de Etapa 6D
(sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W3,
sección "Hallazgo importante". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

Las funciones de escritura del schema no eran uniformes en cómo manejaban
strings vacíos en campos obligatorios. Específicamente, `registrar_pago()`
extraía los campos obligatorios `tipo` y `medio_pago` así:

```sql
v_tipo := payload->>'tipo';
v_medio_pago := payload->>'medio_pago';
```

Sin `NULLIF` y sin `TRIM`. Si el payload traía estos campos como `""`
(string vacío), la validación posterior:

```sql
IF v_tipo IS NULL OR v_medio_pago IS NULL OR ... THEN
  RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
END IF;
```

No los detectaba como faltantes, porque `""` no es `NULL`. La función
avanzaba hasta el INSERT y chocaba contra los CHECK constraints
(`chk_pagos_tipo`, `chk_pagos_medio`), generando un error crudo de Postgres
en vez de un JSONB estructurado.

### Mitigación temporal aplicada en 6C

En W3 — Build Payload, n8n normalizaba con `nv()` los campos obligatorios
antes de mandarlos al payload (convertía `""` a `null` explícito). Esto
hacía que `payload->>'campo'` devolviera NULL real y la validación de la
función rebotara limpio.

**Limitación de la mitigación:** solo cubría el camino de W3. Si otro
consumidor de la función (otro workflow, llamada directa SQL, bot, etc.)
mandaba payload con string vacío, el agujero seguía.

### Fix definitivo aplicado en Etapa 6D

Patrón canónico unificado aplicado al extract de payload de las 5
funciones write críticas:

```sql
v_campo := NULLIF(TRIM(payload->>'campo'), '')::TIPO;
```

Cubre vacíos y whitespace antes del cast. Aplicado a las asignaciones de extract en las funciones:
- `registrar_pago` (H2)
- `confirmar_reserva` (H3)
- `crear_prereserva` (H4)
- `cancelar_prereserva` (H4-bis)
- `crear_bloqueo` (H4-ter)

`upsert_huesped` ya cumplía el patrón desde antes.

**101 tests de hardening** sobre las 5 funciones, todos con `ok=true`. Cero
side effects: conteos de DEV idénticos pre y post hardening.

**Mitigación defensiva `nv()` en n8n:** se mantiene como defensa en
profundidad. No se removió.

---

## A.2 [CERRADO en H5] Vista_ocupacion devuelve 25 meses en vez de 24

**Descubierto durante:** 6C — implementación de W7 (vistas operativas),
Test 4.
**Fecha de descubrimiento:** 2026-05-26.
**Estado:** ✅ Cerrado en bloque H5 de Etapa 6D (sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W7,
sección "Test 4". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

`vista_ocupacion` estaba definida con:

```sql
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval,
  '1 mon'
)
```

`generate_series` con paso temporal incluye ambos extremos, generando 25
puntos en vez de 24. Esto resultaba en 25 meses × 5 cabañas = 125 filas en
el output, en vez del valor teóricamente esperado de 120.

**Impacto:**
- Funcional: ninguno. Los cálculos de `noches_ocupadas` para cada mes
  seguían siendo correctos.
- Operativo: una fila más por cabaña por consulta. En reportes que
  consumían la vista, podía causar confusión si alguien esperaba
  "exactamente 24 meses" para gráficos.

### Fix aplicado en Etapa 6D

Una sola línea modificada — al límite superior del `generate_series` se le
resta `'1 mon'::interval`:

```sql
generate_series(
  date_trunc('month', CURRENT_DATE) - '1 year'::interval,
  date_trunc('month', CURRENT_DATE) + '1 year'::interval - '1 mon'::interval,
  '1 mon'
)
```

Resultado: 120 filas (24 meses × 5 cabañas). 7 tests con `ok=true`.
Cálculos de `noches_ocupadas` idénticos a los previos.

---

## A.3 [CERRADO en H6, H6-bis] Espacio colgando en concatenación nombre + apellido

**Descubierto durante:** 6C — implementación de W7 (vistas operativas),
Test 3.
**Fecha de descubrimiento:** 2026-05-26.
**Estado:** ✅ Cerrado en bloques H6 y H6-bis de Etapa 6D (sesión 2026-05-26).
**Bitácora detallada:** `Docs/Bitacora/6C_EJECUCION.md` — entrada W7,
sección "Test 3". Ejecución del fix en
`Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`.

### Problema original (pre-hardening)

Las vistas `vista_calendario`, `vista_limpieza_semana` y
`vista_prereservas_activas` concatenaban el nombre del huésped así:

```sql
nombre || ' ' || COALESCE(apellido, '')
```

Cuando `apellido` era string vacío `""` (no NULL), `COALESCE(apellido, '')`
devolvía `""` sin reemplazar. La concatenación quedaba como
`"Juan Pérez Test "` con espacio al final.

**Impacto:**
- Funcional: ninguno.
- UX/Cosmético: strings con espacios colgando se veían mal en UI / mensajes
  a clientes. Si una plantilla hacía `"Hola {huesped_nombre},"` quedaba
  `"Hola Juan Pérez Test ,"` con espacio antes de la coma.

### Fix aplicado en Etapa 6D

Reemplazo en las 3 vistas afectadas:

```sql
TRIM(nombre || ' ' || COALESCE(apellido, ''))
```

Aplicado a `vista_calendario`, `vista_limpieza_semana` (2 ocurrencias por
UNION ALL), y `vista_prereservas_activas` (1 ocurrencia).

PostgreSQL al persistir normalizó `TRIM(...)` a `TRIM(BOTH FROM ...)`.
Sintaxis equivalente.

H6: 7 tests con `ok=true`. H6-bis: 5 tests con `ok=true`. Categoría
cosmética cerrada.

**Parte 6.2 (UPDATE de huéspedes):** NO ejecutado. DEV ya tiene
`apellido = NULL` en los 2 huéspedes existentes (limpieza pre-hardening
eliminó los problemáticos). `upsert_huesped` aplica `NULLIF(TRIM(...))` para
casos futuros.

---

## A.4 [CONSOLIDADO en A.5] Tests de concurrencia Sección 6.8

**Descubierto durante:** preparación del cierre formal post-6C.
**Fecha de registro:** 2026-05-26.
**Estado:** ✅ Cerrado en H7. Detalle consolidado en **Apéndice A.5**.

Este item originalmente migró desde la Sección 10 del archivo a la
Sección 6.1 para evitar duplicación. La ejecución se hizo en H7 (sesión
2026-05-27) con scope ampliado: además de los 4 tests originales del
plan 6B (C-1 a C-4), se agregaron dos legacy complementarios (C-5
regresión v1.5 y C-6 idempotencia). El detalle completo de los 6 tests
ejecutados está en A.5.

---

## A.5 [CERRADO en H7] Tests de concurrencia C-1 a C-6

**Descubierto durante:** plan original 6B Sección 6.8 + consolidación
post-6C en Sección 6.1 + ajuste de nomenclatura al inicio de H7.
**Fecha de ejecución:** 2026-05-27.
**Estado:** ✅ Cerrado en bloque H7 de Etapa 6D.
**Bitácora detallada:** `Docs/Bitacora/HARDENING_PRE_PRODUCCION_EJECUCION.md`
sección H7.

### Contexto

Los tests de concurrencia con `pg_sleep` se difirieron durante 6B (foco en
"función compila y se comporta") y durante 6C (n8n manual no permite
reproducir la condición de carrera con sleep). Operativamente no eran
bloqueantes hasta tener consumidores reales que generaran concurrencia
(webhook MP, bot multicanal, frontend público), pero el riesgo de que el
primer evento de concurrencia real en producción fuera también el primer
test del sistema motivó ejecutarlos en DEV controlado antes de TEST/PROD.

### Alcance ejecutado

6 tests con paralelismo real en DEV usando dos tabs separadas del
navegador (no la opción "+" interna del SQL Editor que comparte runner):

| Test | Funciones | Cabaña | Rango | Tipo |
|---|---|---|---|---|
| C-1 | `crear_prereserva` + `crear_bloqueo total` | 17 | 2027-03 | Consolidado |
| C-2 | `cancelar_prereserva` + `crear_bloqueo total` | 18 | 2027-04 | Consolidado |
| C-5 | `confirmar_reserva` + `cancelar_prereserva` | 19 | 2027-05 | Legacy v1.5 (regresión deadlock) |
| C-3 | `confirmar_reserva` + `crear_bloqueo específico` | 20 | 2027-06 | Consolidado |
| C-4 | Doble `confirmar_reserva` | 21 | 2027-07 | Consolidado |
| C-6 | Doble `crear_prereserva` + `idempotency_key` | 17 | 2027-08 | Legacy idempotencia |

### Resultado

| Métrica | Valor |
|---|---|
| Tests aprobados | 6 de 6 |
| Deadlocks `40P01` | 0 |
| Races / doble booking / falsos positivos | 0 |
| Rango de `B.elapsed` | 6.058s a 6.539s (lock global serializa consistentemente) |
| Residuos `test_H7_%` en DEV post-cleanup | 0 |
| Schema | Sin cambios (H7 es validación, no modifica SQL) |

### Confirmaciones estructurales

1. **Invariante de locks v1.5 vigente en DEV.** El orden "lock global SIEMPRE primero antes de cualquier FOR UPDATE / lock por cabaña" funciona correctamente bajo concurrencia real.
2. **Lock global serializa.** `B.elapsed` consistente entre 6.06s y 6.54s, con `B.ts_post ≈ A.ts_post`.
3. **EXCLUDE constraints no fueron necesarios.** Los chequeos aplicativos rebotaron antes del INSERT en todos los casos.
4. **Visibilidad post-COMMIT consistente.** B siempre vio los cambios de A después del COMMIT.
5. **Idempotencia de `crear_prereserva` funcional.** Rama `post_lock` observada empíricamente en C-6.
6. **Doble logging confirmado en las transiciones de estado observadas durante H7** (trigger automático `trg_log_*_estado` + log explícito de la función cuando aplica).

### Lecciones operativas surgidas en H7

1. SQL Editor "+" interno comparte runner; dos tabs separadas del navegador permiten paralelismo real.
2. Mini-test de PIDs con `pg_sleep(5)` valida paralelismo antes de tests críticos.
3. CTEs encadenadas (`MATERIALIZED` + `FROM`) necesarias para tests con `pg_sleep` en transacción.
4. `registrar_pago` requiere `estado_inicial='confirmado'` + `monto_recibido=monto_esperado` para pago `confirmado` directo (default es `en_revision`).
5. Trigger `trg_log_*_estado` sobre `pagos` solo dispara en UPDATE OF estado, no en UPDATE de `id_reserva`.
6. `crear_prereserva` ejecuta `upsert_huesped` antes del lock global; bajo concurrencia con idempotencia, B puede crear huésped huérfano que queda para cleanup.
7. `bloqueos.activo` BOOLEAN (no enum `estado`) — divergencia de patrón con otras tablas operativas.
8. `cabanas.capacidad_max` (no `capacidad_maxima`) — naming real confirmado; revisar documentación si corresponde en H8.
9. `confirmar_reserva` retorna `estado_invalido` cuando estado terminal (no `estado_no_confirmable`).
10. `telefono_normalizado` preserva el `+` del prefijo internacional.

Estas lecciones se consolidan en `Lecciones_Aprendidas.md` durante H8, agrupadas por tema para no crear entradas redundantes.

### Cobertura parcial documentada

H7 observó empíricamente la rama `post_lock` del detector de idempotencia
de `crear_prereserva` (C-6). Las ramas `pre_lock` y `unique_violation`
están vigentes en el cuerpo de la función y son alcanzables por diseño,
pero no fueron gatilladas en H7 por el timing del test. Queda como
cobertura opcional no bloqueante (ver Sección 6.3 arriba).

### Decisiones cerradas durante H7

- Mantener nomenclatura consolidada C-1 a C-4 (de este documento) + agregar
  C-5 y C-6 como complementarios legacy (del plan 6B original), no
  reemplazar.
- Convención `source_event = 'test_H7_C{N}_{ROL}'`.
- Cleanup por test con filtro específico `LIKE 'test_H7_C{N}_%'`, no
  cleanup global al final.
- Mecánica de paralelismo: dos tabs del navegador + CTEs encadenadas
  MATERIALIZED + `clock_timestamp()` + `pg_backend_pid()`.
- Freno duro ante cualquier `40P01` (frenos especiales en C-5 y C-3 no se
  activaron).

Estas decisiones se consolidan en `DECISIONES_NO_REABRIR.md` como D-HARD-07
en adelante durante H8.
