# Relevamiento + diseño — Integrar `resolver_horario()` en `obtener_disponibilidad_rango`

**Frente:** Motor formal de horarios — bloque de integración en la función de **LECTURA** `obtener_disponibilidad_rango`.
**Estado:** 🔍 **Relevamiento / diseño. SIN tocar nada.** No hay artefactos ejecutables todavía. Sin `D-*`/`L-*`.
**Entorno objetivo (futuro):** TEST (ref `bdskhhbmcksskkzqkcdp`). OPS y canónico **no se tocan**.
**Fecha:** 2026-07-02 (AR).
**Base leída:** repo clonado fresco (`git clone --depth 1`), commit `d14ab1b`. Canónico **`6B_SCHEMA_SQL.md v1.10.0`** (confirmado en el header; la memoria decía v1.9.0 — estaba drifteada).

---

## 0. Metodología y fuentes leídas

Clonado fresco. Leído en orden:

1. `Docs/Implementacion/Actualizacion_motor_de_horarios/` — carpeta del frente (cierres B2/B3/A07UX, resolver, runsheets, smokes).
2. `HORARIOS_A07UX_CIERRE.md` (el más reciente; enlaza a este bloque).
3. `HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql` (contrato del resolver).
4. `HORARIOS_FASEB_B3_CIERRE.md` (patrón de integración en `crear_prereserva`, a espejar).
5. Canónico `6B_SCHEMA_SQL.md` v1.10.0 — Bloque 12 (`obtener_disponibilidad_rango`) + `vista_disponibilidad`.
6. `bootstrap_entorno_nuevo_v1.9.0/01_BOOTSTRAP_PARTE_B_BASE.sql` (def paralela + hardening).
7. Cadena de consumo hacia el frontend: `portal-a26-disponibilidad__TEMPLATE.json` (SQL + render), `Apps/portal-operativo/src/lib/contratos.ts` y `src/ui/CalendarioRango.tsx`.

**Confirmaciones de arranque:**
- Canónico **v1.10.0**. `resolver_horario` **no** figura en el canónico (`grep` = 0): sigue sin canonizar, como corresponde.
- Def del canónico y del bootstrap para `obtener_disponibilidad_rango`: **idénticas** (sin drift entre ambos). Falta solo confirmar la def **live** de TEST con un `pg_get_functiondef()` (Paso 0 de la futura ejecución).

---

## 1. Qué hardcodea hoy `obtener_disponibilidad_rango`

Firma (no se toca):

```sql
obtener_disponibilidad_rango(p_fecha_desde DATE, p_fecha_hasta DATE, p_id_cabana BIGINT DEFAULT NULL)
RETURNS TABLE (id_cabana BIGINT, fecha DATE, estado TEXT, tipo_dia TEXT, temporada TEXT,
               hora_checkin_base TIME, hora_checkout_base TIME,
               id_reserva_activa BIGINT, id_prereserva_activa BIGINT)
LANGUAGE plpgsql
```

El hardcode de horarios son **exactamente dos `CASE`** dentro del `SELECT` set-based (`RETURN QUERY`), en la sección "Hora base":

```sql
CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '18:00' ELSE TIME '13:00' END AS hora_checkin_base,
CASE WHEN EXTRACT(DOW FROM m.fecha) = 0 THEN TIME '16:00' ELSE TIME '10:00' END AS hora_checkout_base,  -- v1.7.1 (D47)
```

Observaciones:

- Son **los mismos `CASE`** que tenía `crear_prereserva` antes de B3, y coinciden con los **fallbacks base** del resolver (domingo 18:00/16:00, hábil 13:00/10:00).
- Dependen **solo de la fecha** (día de semana / domingo). **Ignoran completamente los overrides** (`overrides_operativos`) y la cabaña. Es decir: hoy la vista **no refleja** overrides operativos, aunque `crear_prereserva` **sí** los aplica desde B3. Hay una divergencia latente entre lo que muestra el calendario y lo que ocurrirá al reservar.
- El comentario "sin escalonamiento — el escalonamiento lo aplica n8n" sigue siendo cierto: el resolver también devuelve **base** (no escalonada), así que es compatible conceptualmente.

**ACL / método de reemplazo.** El bootstrap muestra `REVOKE EXECUTE ON FUNCTION public.obtener_disponibilidad_rango(date,date,bigint) FROM PUBLIC, anon, authenticated, service_role;` → ACL owner-only. Igual que en B3, el reemplazo debe ser **`CREATE OR REPLACE`** (no `DROP`) para preservar ACL, `COMMENT` y ownership. Además, `DROP` está vedado por dependencia: **`vista_disponibilidad` depende de esta función** (ver §4), y un `DROP … CASCADE` la voltearía.

---

## 2. Forma de salida actual + cadena de consumo (el contrato sensible)

La cadena real hacia el frontend es:

```
obtener_disponibilidad_rango  →  [SQL de A26]  →  [render A26]  →  contrato TS  →  CalendarioRango.tsx
```

### 2.1. El SQL de A26 (`PG: disponibilidad`)

De las 9 columnas de la función, A26 consume **5**:

```sql
SELECT f.fecha, f.estado, f.id_cabana, f.hora_checkin_base, f.hora_checkout_base
FROM valida v
CROSS JOIN LATERAL obtener_disponibilidad_rango(
  (($1::jsonb)->>'fecha_desde')::date,
  (($1::jsonb)->>'fecha_hasta')::date,
  v.id_cabana
) AS f
```

`tipo_dia`, `temporada`, `id_reserva_activa`, `id_prereserva_activa` **no** se usan en A26. Además A26 **siempre** pasa una cabaña concreta (`id_cabana` obligatorio, entero > 0 — el modo "todas" **no** se expone en el portal).

### 2.2. El render de A26 (`Code: render envelope`)

Arma `dias[]` con `{fecha, estado, id_cabana, hora_checkin_base, hora_checkout_base}` y — dato clave —:

```js
hora_checkin_base: x.hora_checkin_base ?? null,
hora_checkout_base: x.hora_checkout_base ?? null
```

→ **El render ya tolera horas en NULL sin romperse.** Si la función devuelve `NULL` en una hora, A26 la propaga como `null`.

### 2.3. El contrato TS del frontend (`contratos.ts`)

```ts
export type EstadoDisponibilidad = 'disponible' | 'checkout_disponible' | 'ocupada' | 'bloqueada';
export interface DiaDisponibilidad {
  fecha: string;
  estado: EstadoDisponibilidad;
  id_cabana: number | null;
  hora_checkin_base: string | null;   // ← ya es nullable
  hora_checkout_base: string | null;  // ← ya es nullable
}
```

Y el comentario del propio contrato dice, textual:

> `hora_checkin_base`/`hora_checkout_base` llegan por contrato pero **NO se usan en este bloque** (sin recambio ni validación horaria).

### 2.4. El calendario (`CalendarioRango.tsx`)

Único uso de la respuesta (línea ~128):

```js
for (const d of data.dias) dias.set(d.fecha, d.estado);
```

→ **El frontend consume solo `fecha` y `estado`.** Pinta cada día por su `estado` (`disponible`/`checkout_disponible` blanco, `ocupada` verde, `bloqueada` gris). **Nunca lee las horas base.** Un `estado` desconocido se pinta como "sin cargar".

### 2.5. Conclusión sobre el contrato

El "contrato de salida que no hay que romper" se reduce, en la práctica, a **dos garantías**:

1. **`estado` sigue saliendo correcto** para cada fila (la información crítica del calendario).
2. **Las 9 columnas y la firma no cambian** (nombres/tipos/orden), para no romper a `vista_disponibilidad` (dependiente) ni al SQL de A26/W1.

Las **horas base pueden ir a NULL sin romper nada**: el frontend no las usa, el contrato ya las tipa `string | null`, y el render de A26 ya las tolera. Esto **abre** el diseño (ver §3–§4).

---

## 3. Diferencia central de diseño vs. `crear_prereserva` (B3)

Franco marcó bien el punto: una función de **lectura no puede "rebotar"**. Además hay una diferencia **estructural**:

| | `crear_prereserva` (B3) | `obtener_disponibilidad_rango` (este bloque) |
|---|---|---|
| Naturaleza | Escritura, escalar | Lectura, **set-based** (`RETURN QUERY`, N filas) |
| Llamadas al resolver | 2 escalares: `resolver(fecha_in)`, `resolver(fecha_out)` | **1 por fila** de la matriz cabaña×fecha |
| Reacción al HARD | `RETURN {ok:false}` → **corta toda la operación** | **No puede cortar la vista** por una fila mala |
| Riesgo | Consumir secuencias / crear datos | **Romper el contrato de salida / mentir** |

En B3 el HARD es un corte limpio. Acá, el HARD ocurre **por fila** (una `(cabaña, fecha)` con override corrupto) y hay que decidir qué sale en **esa** fila sin tumbar las demás.

Recordatorio del contrato del resolver: hace un LOOP por `hora_checkin` y `hora_checkout` y **retorna en el primer HARD**. O sea, ante override corrupto retorna `{ok:false, error:'override_hora_invalido', causa, tipo_override, …}` sin necesariamente haber calculado el otro borde. No expone una API "por borde".

---

## 4. Opciones de tratamiento del HARD (con recomendación)

Cuatro opciones para la fila `(cabaña, fecha)` cuyo resolver da `{ok:false}`:

### Opción A — Degradar a base (ignorar el override corrupto)
La fila sale con `estado` real + hora **base** (fallback domingo/hábil), como si el override no existiera.
- ✅ Nunca hay NULL; vista visualmente "normal".
- ❌ **Miente / oculta el problema**: muestra `check-in 13:00` para un día que, al reservar, `crear_prereserva` **rebota** con `override_hora_invalido`. Incoherencia "veo disponible pero no puedo reservar". Nadie se entera del override roto.
- ❌ Contradice la política ya tomada en B3 (donde ese día se bloquea).

### Opción B — Omitir la fila (no devolverla)
- ✅ "Marca" el día como problemático por ausencia.
- ❌ **Rompe el grid**: el frontend arma un `Map fecha→estado`; una fecha faltante cae en `estado === undefined` → se pinta "sin cargar", **igual que un día fuera de rango o no consultado**. Ambiguo y silencioso. Comunica "no existe/sin datos", cuando en realidad el día existe y su ocupación es conocida.

### Opción C — Nuevo estado (`'indeterminado'`/`'no_disponible'`) + horas NULL
- ✅ Explícito sobre el problema.
- ❌ **Rompe el contrato del enum** `EstadoDisponibilidad` (4 valores). Obliga a tocar **frontend** (contrato + tintes + leyenda + `CalendarioRango`). Viola "no romper el contrato" y "no tocar frontend en este bloque". Escalada grande de alcance.

### Opción D — Preservar `estado` real, horas a NULL en la fila con HARD (SIN nuevo estado) ⭐
La fila sale con su `estado` de ocupación **correcto** (disponible/ocupada/bloqueada/checkout_disponible, calculado igual que hoy) pero `hora_checkin_base = NULL` y `hora_checkout_base = NULL`.
- ✅ **No rompe el contrato**: el frontend pinta por `estado` (intacto); las horas NULL las ignora (ya son `string|null`); A26 ya las tolera.
- ✅ **Honesta en el dato horario**: no expone una hora falsa; deja NULL ("sin hora / a confirmar"). Un consumidor futuro que sí lea horas (bot, web pública, panel horario) recibe una señal observable de "override corrupto en este día".
  - ⚠️ **Matiz obligatorio (no sobre-vender):** D1 **preserva la disponibilidad OCUPACIONAL** (reserva/bloqueo/prereserva encima → `estado` veraz), pero **NO garantiza reservabilidad HORARIA**. Un día ocupacionalmente **libre** con override horario **corrupto** saldrá `estado='disponible', horas=NULL`; y como **el frontend actual ignora las horas**, seguirá pintándose **disponible** aunque `crear_prereserva` lo **rechace** con `override_hora_invalido`. Es decir: D1 evita mostrar una hora inventada, pero **no cierra** la incoherencia "disponible-pero-no-reservable" en la capa de presentación. Esa incoherencia vive en el frontend (que no consume la señal NULL) y su cierre real es **trabajo futuro fuera de este bloque** (ver R4). No afirmar "no miente" sin este matiz.
- ✅ **Coherente con B3**: no contradice el rechazo de la escritura (no promete una hora reservable que no existe); y el `estado` —lo crítico del calendario— sigue veraz.
- ✅ **Fail-soft correcto para lectura**: una lectura no debe tumbar la vista por una fecha mala, pero tampoco inventar. NULL es el punto medio honesto ("indeterminado" sin necesidad de un nuevo estado).
- ❌ Introduce NULLs que un consumidor descuidado podría no manejar. Pero **los consumidores actuales ya los manejan** (A26 + frontend + `vista_disponibilidad`, que expone `TIME` nullable de por sí).

**Sub-variante recomendada — D1 (all-or-nothing por fila):** si el resolver da HARD para `(cabaña, fecha)`, **ambas** horas de esa fila → NULL (no intentar salvar el borde no afectado). Es el **espejo exacto** del "over-blocking aceptado" de B3 (R2), donde un override corrupto de cualquier borde bloquea toda la reserva. Simple, coherente, y no requiere una API por-borde que el resolver no ofrece.

> Descarto D2 ("solo el borde afectado a NULL"): el resolver retorna en el primer HARD y no expone resultado por-borde; habría que llamarlo de forma distinta o reparsear. Complejidad sin beneficio real, y rompe la simetría con B3.

### 🎯 Recomendación: **Opción D, variante D1.**
Es la única que (a) no rompe el contrato ni toca el frontend, (b) es honesta en el dato horario (NULL en vez de hora inventada), (c) es coherente con la política ya cerrada en B3, y (d) deja una señal observable del override roto para consumidores futuros. **Con el matiz de arriba**: preserva disponibilidad **ocupacional**, no reservabilidad **horaria**; la incoherencia "disponible-pero-no-reservable" sobre un día libre con override corrupto **persiste** en el frontend actual (que ignora las horas) y se cierra recién como trabajo futuro (R4). El caso solo aparece con **overrides corruptos** (dato de admin mal cargado): situación de error operativo, no de flujo normal.

---

## 5. Cambio de comportamiento colateral (a aprobar explícitamente)

Integrar el resolver **no es solo sacar el hardcode**: también hace que la vista **empiece a respetar `overrides_operativos`** (por cabaña y globales, con la precedencia del resolver). Hoy los ignora.

- Es una **mejora**: alinea el calendario con lo que realmente ocurrirá al reservar (B3 ya los aplica).
- Es **observable**: en un día con override **válido**, `hora_checkin_base`/`hora_checkout_base` pasarán a reflejar el override en lugar del fallback. Como el **frontend hoy no muestra horas**, el efecto visible actual es **nulo** en el calendario; pero `vista_disponibilidad`, W1 y cualquier consumidor futuro de horas **sí** verán el cambio.

Franco debe aprobar este cambio de comportamiento como parte del diseño (no es un efecto secundario accidental).

---

## 6. Borrador del delta (NO es el artefacto final)

**Método:** `CREATE OR REPLACE FUNCTION` (preserva ACL/COMMENT/ownership; no rompe `vista_disponibilidad`). Firma y las 9 columnas de salida **idénticas**.

**Deltas de cuerpo (mínimos):**

- **Δ1 — Fuente de horas por fila.** Agregar al `FROM` un LATERAL que llame al resolver **una vez por fila**:

  ```sql
  ...
  FROM matriz m
  CROSS JOIN LATERAL (SELECT resolver_horario(m.id_cabana, m.fecha) AS rh) hr
  ```

- **Δ2 — Reemplazar los dos `CASE`** de "Hora base" por extracción fail-closed desde `hr.rh` (D1):

  ```sql
  CASE WHEN COALESCE((hr.rh->>'ok')::boolean, false)
       THEN (hr.rh->>'hora_checkin')::TIME  ELSE NULL END AS hora_checkin_base,
  CASE WHEN COALESCE((hr.rh->>'ok')::boolean, false)
       THEN (hr.rh->>'hora_checkout')::TIME ELSE NULL END AS hora_checkout_base,
  ```

  `ok=true` → hora del resolver (base o override válido). `ok=false` **o** clave ausente (`NULL`) → **ambas NULL** (D1, fail-closed, mismo criterio que el `COALESCE(...,false) IS NOT TRUE` de B3).

Todo lo demás (matriz, cálculo de `estado`, `tipo_dia`, `temporada`, `id_reserva_activa`, `id_prereserva_activa`, `generate_series` medio-abierto) queda **igual**.

**Gate anti-OPS embebido** (patrón B3, dentro de `BEGIN…COMMIT`): validar `ambiente='test'` + `current_schema()='public'` + existencia de `resolver_horario(bigint,date)` y de `obtener_disponibilidad_rango(date,date,bigint)` + **fingerprint baseline** de la función; si algo falla, `RAISE EXCEPTION` aborta y el `CREATE` no corre. (Para OPS futuro habrá que adaptar el marcador, como ya está anotado en el frente.)

**Dependencia del resolver:** el gate debe exigir que `resolver_horario` exista en TEST (fingerprint conocido) — es prerequisito duro, igual que B2 lo fue para B3.

---

## 7. Consideraciones y riesgos

- **R1 — Performance (N llamadas al resolver).** Hoy los `CASE` son inline (0 I/O de horario). El resolver hace 1 agregado sobre `configuracion_general` + hasta 2 SELECT sobre `overrides_operativos` **por fila**. En A26 es 1 cabaña × M fechas (calendario), y el span está capeado a 366 días en el wrapper → cota ~366 llamadas. Aceptable para lectura de calendario, pero **conviene medir tiempos en el smoke** (rango real de A26 y un rango grande). Si molestara, hay optimización posterior (precargar config/overrides una vez y resolver en set), pero **no** la propongo ahora: mantiene la simetría con el resolver y evita duplicar su lógica.
- **R2 — Fingerprint baseline impredecible pre-apply** (tubería LF/CRLF + `pg_get_functiondef`), como en B3-R1. **Se mide en el Paso 0** de la ejecución y queda registrado como baseline.
- **R3 — Otros consumidores de las horas.** `vista_disponibilidad` (passthrough de las 9 columnas, `id_cabana=NULL` → todas) y W1 (`vita_w01_consultar_disponibilidad_supabase`, modo "todas" vía `id_cabana=0→NULL`) pasarán a reflejar overrides y posibles NULL. No se rompen (exponen `TIME` nullable), pero **el cambio de comportamiento los alcanza**. A26 y el calendario: sin efecto visible (no muestran horas).
- **R4 — Semántica de NULL + incoherencia residual de presentación.** En esta función `hora_*_base = NULL` significa "override corrupto para esa (cabaña, fecha)" (día resoluble en ocupación, **no** resoluble en hora). Es la contraparte de lectura del HARD de escritura. **Riesgo residual (aceptado, fuera de alcance):** un día ocupacionalmente libre con override horario corrupto sale `estado='disponible', horas=NULL`; el frontend actual **ignora las horas** y lo pinta disponible, aunque `crear_prereserva` lo rechace. D1 no cierra esa incoherencia (vive en la capa de presentación, que no consume la señal NULL). Cierre real = trabajo futuro: que el frontend/A26 interprete `horas=NULL` (p. ej. deshabilitar el día o rotularlo "hora a confirmar"). **No es parte de este bloque** (tocaría frontend, vedado).
- **R5 — Solo TEST.** Promoción a OPS = paquete coordinado futuro (guard B2 + resolver + B3 + wrapper A07 + **esta integración**), con gate adaptado y fingerprint parity. Diferido; no es este bloque.

---

## 8. Consejo de organización de la carpeta (lo que pediste)

Miré cómo quedó **Cuenta Corriente** y **Carril C**: sus cierres, runsheets, SQL de TEST y evidencia viven en **`Docs/Bitacora/`** — CC en `Docs/Bitacora/CARRIL_CUENTA_CORRIENTE/` (con `CIERRE_CARRIL_CUENTA_CORRIENTE_L1_L2.md` adentro), Carril C en `Docs/Bitacora/Carril_C/` con subcarpetas por slice. El `README.md` de `Docs/Implementacion/` explicita la convención: **Implementación** = documentos vigentes + canónico + planes; **Bitácora** = ejecución bloque-por-bloque + evidencia.

Tu carpeta `Docs/Implementacion/Actualizacion_motor_de_horarios/` es material de **ejecución** (cierres, runsheets, smokes, SQL de TEST) → por convención, su lugar natural es **`Docs/Bitacora/`**.

**Recomendación:** mover a `Docs/Bitacora/Actualizacion_motor_de_horarios/` (o `Docs/Bitacora/HORARIOS/`), para quedar consistente con CC y Carril C. Como el frente **aún no cerró formalmente ni se canonizó**, es el mejor momento para fijar la ubicación definitiva antes de que se llene de más artefactos. Si preferís tenerlo en Implementación mientras el frente está **vivo** y moverlo a Bitácora recién en el cierre formal, también es defendible — pero dejaría el frente de horarios como la excepción a la convención. Vos ejecutás git; te lo dejo como decisión, no como bloqueante de este bloque.

---

## 9. Preguntas abiertas para Franco (antes de generar artefactos)

1. **¿Aprobás la Opción D / D1** (preservar `estado`, ambas horas de la fila a NULL ante HARD, all-or-nothing por fila)?
2. **¿Aprobás el cambio de comportamiento colateral** (la vista empieza a respetar `overrides_operativos`)?
3. **¿Ubicación de la carpeta**: la movés a `Docs/Bitacora/` ahora, o la dejás en `Docs/Implementacion/` hasta el cierre del frente?
4. **Alcance del smoke de performance**: ¿con el rango real de A26 alcanza, o querés que incluya un rango grande (p. ej. cercano a 366 días) para medir la cota?
5. **Confirmación de la def live**: ¿corrés el `pg_get_functiondef()` en TEST del Paso 0 para verificar que la def viva coincide con canónico/bootstrap antes de que yo prepare el artefacto? (La fuente real manda.)

---

## 10. Próximo paso

**Espero tu aprobación de este relevamiento.** Recién con el OK sobre §4 (política D/D1), §5 (comportamiento) y las preguntas de §9 paso a generar los artefactos:

- SQL de integración TEST (`CREATE OR REPLACE` + gate anti-OPS embebido).
- Script de fingerprint/verificación (Paso 0 baseline + post-apply).
- Smokes SQL (no-regresión hábil/domingo, override válido por cabaña/global, HARD → horas NULL con `estado` intacto, y medición de tiempos).
- Runsheet de ejecución.

Sin `D-*`/`L-*` hasta el cierre formal del frente completo de horarios.
