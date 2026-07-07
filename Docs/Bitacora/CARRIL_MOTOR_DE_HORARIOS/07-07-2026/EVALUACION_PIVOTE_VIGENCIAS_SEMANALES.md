# EVALUACIÓN — ¿Pivotear el Motor de Horarios a vigencias semanales ahora?

**Naturaleza:** documento de evaluación (NO artefactos, NO SQL). **Base:** clone fresco confirmado en el HEAD autoritativo `b99a0b9` (local == remoto). **Alcance:** TEST-only en el análisis; no se toca OPS, portal-api, frontend, n8n, Vercel ni canónico.

**Pregunta:** ¿el camino actual B1.1/B1.2-core sirve como base evolutiva, o conviene supersederlo/rediseñarlo ahora?

**Respuesta corta:** El subsistema de **overrides ya cubre casi textualmente** los requisitos 2 y 4 (alcances, anti-comprometidos, compatibilidad de bordes). La arquitectura del **resolver** (3 funciones, INV-1, precedencia) es reutilizable. La **única rigidez real** es el modelo de datos de la vigencia (4 columnas `default/domingo`), que no puede expresar horarios por día de semana. → **No hay que reconstruir; hay que evolucionar la capa de vigencia.** Recomendación: **Camino B**, ejecutado en una **conversación nueva** (Camino D como vehículo). Ver §3–§4.

---

## 1. Diagnóstico del modelo actual

### 1.1 Qué partes SIRVEN (base evolutiva sólida)

**A. Resolver — arquitectura de 3 funciones (B1.2-core).** Reutilizable casi entera:
- Interno `_resolver_horario(cab,fecha,flag)` con flag `true/false` (ciego). El **flag ciego es un invariante que la versión semanal necesita igual** (el helper G1 debe ver config/base sin vigencia).
- Wrapper `resolver_horario(cab,fecha)` = pass-through a interno(...,true). Su cuerpo NO cambia con semanal ⇒ **su fingerprint `1bd96c89` sobrevive** al rediseño.
- Precedencia `config(fallback) → vigencia → override_global → override_cabana`, por tipo (checkin/checkout). **Correcta y reutilizable tal cual.**
- Manejo de overrides (Paso B/C: ganador determinista, HARD de formato/cast/ventana). **Idéntico a lo que se necesita.**

**B. Subsistema de overrides — ya implementa los requisitos 2 y 4 casi textualmente.** Esto es lo más importante del diagnóstico:
- **`overrides_operativos`** (tabla): `id_cabana` nullable (per-cabaña **o** global), `fecha_desde/fecha_hasta` (rango), `tipo_override` (`hora_checkin`/`hora_checkout`), `valor`, auditoría. Sin EXCLUDE (los overrides se solapan; el resolver elige ganador). **Sirve a nivel de datos para punctual y automático.**
- **S0 validadores** (read-only): `validar_estado_horario_final` (resolver ok + gap same-day ≥2h), `validar_no_eventos_comprometidos` (reservas/pre-reservas comprometidas), `validar_estado_override` (orquesta). **Encodean anti-pisar-comprometidos + compatibilidad de bordes** — exactamente tus reglas.
- **S2 `crear_override_horario`**: un override individual, por cabaña o global_estricto, con errores parseables `override_pisa_reserva`, `override_pisa_prereserva`, `override_incompatible_same_day`, `override_hora_invalido`. **Es la lógica exacta del override automático de la reserva pactada** (alcance = una cabaña).
- **S3 `crear_paquete_dia_especial`**: paquete checkout+checkin conjunto con **5 alcances ya implementados** — `cabana | grupo_estricto | grupo_posibles | global_estricto | todas_posibles` — recibiendo `ids_cabanas` (array = tu concepto de "grupo"), con:
  - `cabana / grupo_estricto` → all-or-nothing (falla si una comprometida) = **tu regla "grupo/una cabaña → falla si alguna comprometida"**;
  - `todas_posibles / grupo_posibles` → subtransacción por cabaña, aplica las libres y **reporta las excluidas** = **tu regla "todas → aplica a las libres y reporta excluidas"**;
  - chequeo de EFECTO (el paquete debe quedar ganador del resolver, sino `paquete_no_aplicado_efectivamente`).
  - → **Tu requisito 2 ("Cambiar horarios puntuales" con una/grupo/todas + aplicación parcial) está prácticamente construido.**

**C. Helper G1 — la LÓGICA sirve.** "Turno pegado ≥2h contra la hora congelada del comprometido, solo donde la base gobierna", fail-closed si el resolver no puede determinar provenance. Esa lógica es correcta para semanal; solo cambia de dónde saca el valor de la vigencia (ver §1.2).

**D. INV-1 (anti-autorreferencia).** El helper llama al interno ciego (`...,false`) para no entrar en `resolver → vigencias → resolver`. **Es un invariante de arquitectura, independiente de la forma de la vigencia. Sobrevive intacto.**

**E. Patrones de infraestructura.** EXCLUDE GiST no-solapamiento de vigencias activas; ventana [07:00,22:00]; gap G2 ≥2h; auditoría no-blanca; anti-ambiente gate; hardening REVOKE; regla de disponibilidad same-day (una entra el día que otra sale). **Todo reutilizable.**

### 1.2 Qué partes quedan RÍGIDAS para vigencias semanales

La rigidez está **contenida a la capa de vigencia**. Un solo eslabón y sus dependientes directos:

**A. `vigencias_horario_base` (tabla) — el cuello de botella.** Tiene **exactamente 4 columnas de hora**: `hora_checkin_default`, `hora_checkin_domingo`, `hora_checkout_default`, `hora_checkout_domingo`. Es el modelo binario "default (lun-sáb) + domingo". Su propio comentario lo dice: *"Reemplaza la base completa (default+domingo × checkin+checkout)"*. **No puede expresar 7 días × 2 bordes.** Agregarle 14 columnas sería rígido y feo; la forma correcta es **cabecera + detalle por día de semana** (§2.1).

**B. `crear_vigencia_horario(jsonb)` (guard B1.1).** Su payload y validación asumen 4 horas (default/domingo). Hay que superseder por una versión que reciba 7 días y persista en el detalle. La estructura del guard (lock, validaciones, G1 via helper, fail-closed) se reaprovecha; cambia el shape del payload y el destino de escritura.

**C. Paso A del interno (lookup de vigencia).** Hoy lee las columnas `default/domingo` de la vigencia que cubre la fecha. Semanal: `JOIN` al detalle por `EXTRACT(DOW FROM p_fecha)`. Es un cambio **localizado** dentro del interno (DROP+CREATE ⇒ **nuevo fingerprint del interno**; el wrapper no cambia).

**D. Firma del helper G1.** Hoy recibe 4 valores de vigencia (`ci_def, ci_dom, co_def, co_dom`). Semanal: debe evaluar el valor **por día de semana** de la vigencia prospectiva (recibir un mapa día→{ci,co}, o consultar el detalle prospectivo). Cambia la firma/cuerpo ⇒ **nuevo fingerprint del helper**; INV-1 sobrevive.

### 1.3 Qué deuda genera seguir con cascade AHORA

B1.2-cascade **solo** realinea fingerprints/texto del modelo actual (default/domingo). El rediseño semanal cambia el Paso A del interno y el helper ⇒ **cambian los fingerprints del interno (`566ea522`) y del helper (`871fcde5`)**. Por lo tanto:
- Los pins que cascade ancla para el interno y el helper quedan **superseded** por el rediseño semanal.
- El caso INV-1 comportamental que cascade agrega al smoke B1.1 (interno ciego→base / wrapper→vigencia) tendría que **re-editarse con valores semanales** (por día).
- **Matiz de precisión (para no exagerar):** NO todo cascade es descartable. El **wrapper `1bd96c89` sobrevive** (su cuerpo no cambia con semanal); y los **gates de los smokes S0–S3 de override** gatean el wrapper, así que su realineación a `1bd96c89` es el **mismo target** con o sin semanal (no hay retrabajo ahí). El retrabajo se concentra en la **capa B1.1**: gates/smokes del interno y del helper + la mitad comportamental. Es un chunk significativo, no el 100%.
- **Conclusión:** hacer cascade ahora paga la realineación B1.1 (interno/helper/behavioral) **dos veces**. Conviene absorber esa realineación en el cierre del rediseño semanal (una sola vez, con los fingerprints finales).

### 1.4 ¿Los overrides actuales sirven o hay que rehacerlos?

**Sirven, y con margen.** El modelo de datos (`overrides_operativos`) y los tres guards (S0 validadores, S2 individual, S3 paquete con 5 alcances) cubren tus requisitos 2 y 4. Gaps menores, todos a nivel de guard (no de esquema):
- **Rango de fechas en punctual:** S3 opera sobre `fecha` (día puntual). Tu requisito 2 pide "día puntual **o** rango". Extensión menor (loop de fechas o usar `fecha_desde/fecha_hasta` como en S2, que ya soporta rango).
- **Tag conceptual del override automático:** tu punto de diseño pide diferenciar "override nacido de una reserva pactada" del "Cambiar horarios puntuales" independiente. Se resuelve con convención de `source_event`/`motivo` (o una columna `origen`), no con cambio estructural.
- **Composición atómica reserva+overrides:** es un guard NUEVO (`crear_reserva_con_horario_pactado`) que **reutiliza** la lógica per-cabaña de S2 + la creación de reserva, en una sola transacción. No es infraestructura nueva; es una capa de composición.

---

## 2. Propuesta de arquitectura objetivo

### 2.1 Vigencias: cabecera + detalle por día de semana

**Cabecera** (evoluciona `vigencias_horario_base`, sin las 4 columnas de hora):
`id_vigencia` · `fecha_desde` · `fecha_hasta` · `abierta` · `motivo` · `creado_por` · `activo` · `source_event` · `created_at`. Conserva `exc_vigencias_no_overlap` (EXCLUDE GiST, ≤1 activa por fecha) y `chk_vigencias_abierta`. Modos A/B de tu UI = `abierta=true` (desde fecha en adelante) vs rango cerrado (entre dos fechas).

**Detalle** (nueva tabla, 1 fila por día de semana):
`id_vigencia` (FK ON DELETE CASCADE) · `dia_semana` (0–6; **fijar convención = `EXTRACT(DOW)` de PostgreSQL, 0=domingo**, y documentarla) · `hora_checkin` · `hora_checkout`. PK `(id_vigencia, dia_semana)`. CHECK por fila: gap ≥2h (`hora_checkin - hora_checkout`), ventana [07:00,22:00]. La vigencia se considera completa con las 7 filas (el guard las inserta atómicas; los helpers de UI "copiar L-V / S-D / a todos" solo pueblan el payload, no son lógica de DB).

**Regla de producto respetada:** vigencias **globales** (sin `id_cabana`, no admiten aplicación parcial por cabaña); si pisan comprometidos en el rango, fallan **completas** (G1, §2.5).

### 2.2 Overrides puntuales por alcance (reutilización)

Se conserva `overrides_operativos` + `crear_override_horario` (S2) + `crear_paquete_dia_especial` (S3). Mapeo directo a tu requisito 2:
- "una cabaña" → alcance `cabana`.
- "un grupo" → `grupo_estricto` (all-or-nothing) o `grupo_posibles` (parcial con reporte), vía `ids_cabanas`.
- "todas" → `todas_posibles` (aplica libres, reporta excluidas) o `global_estricto` (all-or-nothing global real).
- Extensión menor: soportar **rango de fechas** además del día puntual (§1.4).
- Componen con vigencias por precedencia (override > vigencia): funcionan **antes, durante y después** de una vigencia (§2.4).

### 2.3 Overrides automáticos al crear reserva manual con horario pactado

**Guard nuevo `crear_reserva_con_horario_pactado(jsonb)`** — capa de composición atómica, conceptualmente distinta de "Cambiar horarios puntuales":
1. Resolver el horario vigente para la cabaña en fecha_checkin y fecha_checkout (via `resolver_horario`).
2. Comparar el pactado (checkin del día de entrada / checkout del día de salida) contra el vigente.
3. Por cada borde que **difiere**, crear **1 override per-cabaña** (alcance siempre `cabana`) reutilizando la validación de S2 (anti-pisar-comprometidos + `override_incompatible_same_day`). 0, 1 o 2 overrides según cambien 0/1/2 bordes.
4. Crear la reserva con `hora_checkin`/`hora_checkout` pactadas.
5. **Todo en una transacción**: o se crean los overrides necesarios y la reserva, o falla todo (atomicidad).
- **Diferenciación conceptual:** marcar estos overrides con `source_event`/`origen` = "reserva_pactada" (o similar), para distinguirlos del alta independiente. Misma infraestructura, semántica distinta.
- **Anti-pisar (tu punto 8):** si el borde pactado pisa una reserva anterior/posterior de la misma cabaña en el mismo día de borde (ej. otra sale lunes 10:00, no se puede entrar lunes 08:00), **falla** — lo cubren `validar_no_eventos_comprometidos` + `override_incompatible_same_day` (mismo gap same-day ≥2h).
- Para Vicky = una sola acción "Crear reserva"; los overrides nacen por detrás.

### 2.4 Resolución de precedencia

Sin cambios conceptuales: **config(fallback) → vigencia[semanal] → override_global → override_cabana**, por tipo. La vigencia aporta la base por día de semana (Paso A reworkeado); los overrides puntuales ganan sobre la vigencia (Paso B/C intactos). Esto garantiza que un override aplique "antes/durante/después de una vigencia" (tu regla): el override siempre sombrea la base vigente para su fecha/cabaña.

### 2.5 Reglas anti-pisar comprometidos

- **Vigencia (G1):** una vigencia prospectiva no puede pisar reservas/pre-reservas comprometidas en check-in/check-out dentro del rango, donde la base gobierna. Falla completa. Lógica del helper actual, con valores por día de semana (§2.6).
- **Override punctual:** S2/S3 ya lo validan por cabaña/alcance (all-or-nothing para grupo/cabaña; parcial+reporte para todas).
- **Reserva pactada:** reutiliza la validación per-cabaña de S2.
- **Congelamiento:** reservas/pre-reservas ya creadas conservan sus horas congeladas; cambiar vigencias u overrides **no** las modifica (invariante mantenido; ninguna acción reescribe reservas existentes).

### 2.6 Impacto sobre helper G1 / no-autorreferencia

- El helper `vigencias_conflictos_comprometidos` cambia de firma/cuerpo: en vez de 4 valores (`ci_def, ci_dom, co_def, co_dom`) evalúa el valor **por día de semana** de la vigencia prospectiva (recibir mapa día→{ci,co} o consultar el detalle prospectivo). ⇒ **nuevo fingerprint del helper**.
- **INV-1 sobrevive intacto:** el helper sigue llamando al interno ciego (`_resolver_horario(...,false)`) — el flag ciego y la anti-autorreferencia son independientes de la forma de la vigencia. La deuda dura B1.2 sigue resuelta.

### 2.7 Impacto sobre smokes / gates

- **Cambian:** el fingerprint del **interno** (Paso A semanal → `566ea522` se supersede) y del **helper** (§2.6). Sus gates y el smoke B1.1 (incluida la mitad comportamental INV-1, ahora con valores por día) se rearman con los fingerprints finales.
- **Sobreviven:** el **wrapper `1bd96c89`** (cuerpo sin cambios) y, por ende, los **gates de los smokes S0–S3 de override** (gatean el wrapper). Su realineación es el mismo target con o sin semanal.
- **Nuevos:** DDL de cabecera/detalle (gates + smokes de la tabla nueva), guard semanal de vigencia, guard de reserva pactada, y extensión de rango en overrides.
- **Neto:** el blast radius de smokes/gates se concentra en la capa vigencia+helper. El subsistema override queda casi intacto.

---

## 3. Caminos posibles

### Camino A — continuar cascade actual y después migrar a semanal

- **Riesgos:** invertir un bloque completo en realinear fingerprints (interno/helper/behavioral) de un modelo que se supersede a las pocas semanas; el estado "cascade-completo" es un checkpoint del modelo equivocado.
- **Costo técnico:** cascade (patchers ~20 archivos) **+** re-realineación de la capa B1.1 (interno/helper/INV-1) al cerrar semanal. Pago doble parcial (el wrapper y los gates S0–S3 no se retrabajan).
- **Riesgo de bloqueo:** bajo (cascade está diseñado y entendido).
- **Qué se conserva:** TEST queda con B1.2-core coherente (deuda de cascade cerrada) como checkpoint intermedio.
- **Qué se descarta:** los pins de interno/helper y el behavioral INV-1 de cascade, al llegar semanal.
- **Recomendación:** **No.** El checkpoint que compra es de un modelo transitorio; el retrabajo B1.1 es evitable.

### Camino B — pausar cascade y diseñar B1.3 semanal ahora (sobre B1.2-core)

- **Riesgos:** durante el diseño semanal, TEST queda con la deuda declarada de B1.2-core (gates/smokes B1.1 gatean `58d75c1b`, resolver es `1bd96c89`). Es una inconsistencia **dormida**: los artefactos viejos de build no se corren durante el diseño de la capa nueva; se resuelve al cierre de B1.3. Riesgo real bajo si no se re-ejecutan los installs viejos.
- **Costo técnico:** diseño + build de cabecera/detalle semanal + rework de Paso A del interno + helper + guard semanal de vigencia + guard de reserva pactada + extensión de rango en overrides. **Absorbe la realineación de cascade** (una sola vez, con fingerprints finales).
- **Riesgo de bloqueo:** medio (diseño más grande), pero **apoyado en una base que ya cubre el 70%** (arquitectura resolver + subsistema override completos).
- **Qué se conserva:** arquitectura de 3 funciones + INV-1; subsistema override entero (validadores S0, S2, S3 con 5 alcances); wrapper `1bd96c89`; R0; patrones de infraestructura.
- **Qué se descarta:** tabla vigencia default/domingo (→ cabecera/detalle); `crear_vigencia_horario` viejo (→ semanal); cascade como bloque separado (su realineación se absorbe en B1.3).
- **Recomendación:** **SÍ (recomendado).** Evoluciona en vez de reconstruir; pago único de realineación; preserva todo lo valioso de B1.2-core; blast radius contenido a vigencia+helper.

### Camino C — rollback/superseder B1.2-core en TEST y reconstruir desde el modelo semanal

- **Riesgos:** descarta el refactor de 3 funciones + INV-1 de B1.2-core, que el modelo semanal **necesita igual** y tendría que reconstruir. Tira trabajo bueno para rehacerlo.
- **Costo técnico:** rollback (core, quizá B1.1) + rebuild completo desde R0. Más piezas móviles que B.
- **Riesgo de bloqueo:** medio-alto (rollback + rebuild encadenados; más superficie de error).
- **Qué se conserva:** R0 (resolver base), subsistema override (S0–S3) si no se rollbackea.
- **Qué se descarta:** el interno ciego / wrapper / helper INV-1 (se rehacen), la tabla vigencia.
- **Recomendación:** **No.** El interno ciego + INV-1 + precedencia de B1.2-core son exactamente lo que semanal reusa; rollbackearlos para reconstruir lo mismo es costo transitorio sin ganancia. Solo tendría sentido si B1.2-core fuera **incompatible** con semanal — y no lo es (semanal cambia el Paso A y el helper, todo lo demás compone).

### Camino D — iniciar conversación nueva con este enfoque

- **Naturaleza:** ortogonal a A/B/C — es el **vehículo de ejecución**, no el path técnico. Esta conversación está cargada con contexto de cascade (inventario, diseño de barrido) que el pivote supersede.
- **Riesgos:** perder hilos finos del contexto de cascade — mitigado porque el repo commiteado es la autoridad y esta evaluación deja el diagnóstico por escrito.
- **Costo técnico:** nulo (setup de kickoff).
- **Riesgo de bloqueo:** nulo.
- **Qué se conserva:** todo (el repo + esta evaluación son el punto de partida).
- **Qué se descarta:** nada.
- **Recomendación:** **SÍ, como vehículo del Camino B.** El diseño B1.3 semanal arranca fresco, con un kickoff que apunte a esta evaluación como diagnóstico base.

---

## 4. Recomendación final

**Camino B ejecutado vía Camino D.** Es decir:

1. **Pausar B1.2-cascade** (no generar los patchers). Queda como deuda declarada de B1.2-core, que se **absorbe** en el cierre de B1.3 semanal (una sola realineación, con los fingerprints finales del interno/helper). No se pierde nada: el diseño de cascade queda documentado en `DISENO_DETALLADO_B1_2_CASCADE.md` por si el pivote no procediera.
2. **Diseñar B1.3 "vigencias semanales"** como capa evolutiva **sobre B1.2-core**, superseding **solo** la capa vigencia: cabecera + detalle por día de semana, guard semanal de vigencia, rework del Paso A del interno y del helper G1. **Conservando** la arquitectura de 3 funciones, INV-1, el wrapper, R0 y **todo el subsistema override** (que ya cubre los requisitos 2 y 4).
3. **Agregar B1.4 (o sub-bloque) "reserva con horario pactado"**: guard de composición atómica que reutiliza S2 per-cabaña + creación de reserva, con tag conceptual del override automático.
4. **Hacerlo en una conversación nueva**, con un kickoff que referencie esta evaluación y fije el orden de diseño (esquema → precedencia → helper/INV-1 → guards → smokes/gates), un bloque por conversación con hard stops, y la metodología de siempre (diseño → aprobación → artefactos → ejecutás en TEST → verificamos → cierre).

**Por qué B y no A/C:** la rigidez está contenida a un solo eslabón (la tabla vigencia default/domingo); todo lo demás —resolver, INV-1, overrides con 5 alcances, validadores— ya sirve y en gran parte ya cubre los requisitos nuevos. Reconstruir (C) tira arquitectura que semanal reusa; terminar cascade primero (A) paga la realineación B1.1 dos veces. Evolucionar la capa vigencia (B) es el camino de menor deuda y menor riesgo de bloqueo.

**Antes de arrancar B1.3, un par de definiciones de producto a cerrar** (para el kickoff de la conversación nueva):
- Convención de `dia_semana` (recomiendo `EXTRACT(DOW)` 0=domingo) y si las 7 filas de detalle son obligatorias o admiten fallback a config para días no seteados.
- Si "Cambiar horarios puntuales" (req 2) usa el paquete conjunto S3 (checkout+checkin juntos) o permite bordes independientes; y si necesita rango de fechas ya en el MVP.
- Confirmar el tag/semántica del override automático de reserva pactada (`source_event`/`origen`) para diferenciarlo del alta independiente.
