# KICKOFF — B1.3 "Vigencias Semanales" (conversación nueva)

> Pegá este documento al abrir la conversación nueva. Es el punto de arranque de B1.3. La conversación anterior (cascade) queda cerrada; este kickoff + la evaluación son autosuficientes.

---

## 0. Insumo obligatorio (leer PRIMERO)

`EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md` — diagnóstico del modelo actual, arquitectura objetivo y los cuatro caminos. **Leerla antes de proponer nada.** Este kickoff asume ese diagnóstico como base.

---

## 1. Contexto y decisión tomada

Pivoteamos el Motor de Horarios de un modelo de vigencia **default/domingo** (2 tipos de día) a **vigencias semanales completas** (7 días × 2 bordes). Decisión cerrada: **Camino B (evolucionar sobre B1.2-core, NO reconstruir) vía Camino D (conversación fresca)**.

- **B1.2-cascade queda PAUSADO.** No se generan sus patchers. Su diseño quedó documentado en `DISENO_DETALLADO_B1_2_CASCADE.md` por si el pivote no procediera. La deuda de cascade se **absorbe** en el cierre de B1.3 (una sola realineación de fingerprints, con los valores finales).
- **B1.3 evoluciona sobre B1.2-core.** Superseder **solo** la capa de vigencia; conservar todo lo demás.

---

## 2. Restricciones DURAS (no negociables)

- **NO tocar OPS.**
- **NO tocar portal-api, frontend, n8n, Vercel ni canónico.**
- **NO generar SQL en el primer paso.** El primer paso es **diseño técnico**, no artefactos.
- **Primer paso: diseño técnico de B1.3 con CLONE FRESCO** del repo (`git clone --depth 1` de `github.com/francogg89-ai/vita-delta-reservas`; el remoto commiteado/pusheado es la autoridad).
- **Un bloque por conversación.** Hard stop antes de artefactos: diseño → aprobación explícita de Franco → recién ahí artefactos.
- **Idioma: rioplatense con voseo**, en toda la interacción.
- Verificar el estado real de B1.2-core en TEST contra el código (no asumir el canónico, que puede estar rezagado).

---

## 3. Qué se CONSERVA (no reabrir)

- **Arquitectura del resolver — 3 funciones:** interno `_resolver_horario(cab,fecha,flag)` (flag ciego true/false), wrapper `resolver_horario(cab,fecha)` (pass-through a interno(...,true); **su cuerpo no cambia con semanal ⇒ fingerprint `1bd96c89` sobrevive**), y el helper.
- **INV-1 (anti-autorreferencia):** el helper llama al interno ciego (`...,false`). Invariante de arquitectura, independiente de la forma de la vigencia. **Se conserva intacto.**
- **Precedencia:** `config(fallback) → vigencia → override_global → override_cabana`, por tipo. Reutilizable tal cual.
- **Subsistema de overrides completo:** tabla `overrides_operativos` (per-cabaña/global, rango, tipo, valor); validadores S0 (`validar_estado_horario_final`, `validar_no_eventos_comprometidos`, `validar_estado_override`); guard S2 `crear_override_horario` (borde único, `cabana`/`global_estricto`); guard S3 `crear_paquete_dia_especial` (checkout+checkin conjunto, 5 alcances `cabana`/`grupo_estricto`/`grupo_posibles`/`global_estricto`/`todas_posibles`, con `ids_cabanas`).
- **R0** (resolver base) y patrones de infraestructura (EXCLUDE GiST no-solapamiento, ventana [07:00,22:00], gap G2 ≥2h, auditoría no-blanca, anti-ambiente gate, hardening REVOKE, regla de disponibilidad same-day).

## 4. Qué se SUPERSEDE / REDISEÑA

Contenido a la capa de vigencia:
- Tabla `vigencias_horario_base` (4 columnas `default/domingo`) → **cabecera + detalle por día de semana**.
- Guard `crear_vigencia_horario(jsonb)` → versión semanal (payload de 7 días).
- **Paso A del interno** (lookup de vigencia): de leer columnas `default/domingo` a `JOIN` al detalle por `EXTRACT(DOW)` ⇒ **nuevo fingerprint del interno**.
- **Firma/cuerpo del helper G1** (evaluar valor por día de semana) ⇒ **nuevo fingerprint del helper**. INV-1 sobrevive.

---

## 5. Definiciones de producto CERRADAS

### 5.1 Convención `dia_semana`
`EXTRACT(DOW)` de PostgreSQL: **0=domingo, 1=lunes, 2=martes, 3=miércoles, 4=jueves, 5=viernes, 6=sábado**. Detalle con **7 filas OBLIGATORIAS**. **Sin fallback parcial a config por día faltante.** Una vigencia semanal se crea completa y auditable, o no se crea.

### 5.2 Cambiar horarios puntuales (acción independiente)
MVP reutilizando lo existente donde sirva. Debe cubrir **bordes independientes** (solo check-in / solo check-out / ambos) y **día puntual** con alcances:
- **una cabaña** → si está comprometida, **falla**.
- **grupo de cabañas** → **estricto**: si alguna del grupo está comprometida, **falla completo**.
- **todas** → aplica a las **libres**, excluye las comprometidas y **reporta explícitamente** las excluidas.

Rango de fechas: **MVP ampliado** (priorizar día puntual bien resuelto para una/grupo/todas). Dejar **evaluado cómo se extiende a rango sin rediseñar** (no implementarlo si complica).

### 5.3 Reserva manual con horario pactado (MVP OBLIGATORIO)
El override automático nacido de "Crear reserva manual con horario especial acordado" se diferencia conceptualmente de un override operativo independiente. Convención inicial:
- `source_event = 'reserva_manual_horario_pactado'`
- `motivo = 'Horario especial pactado al crear reserva manual'`

Regla:
- alcance **siempre una cabaña específica**;
- **operación atómica** (todo o nada);
- cambia solo check-in → crea **1 override** (esa cabaña, fecha_checkin, tipo check-in);
- cambia solo check-out → crea **1 override** (esa cabaña, fecha_checkout, tipo check-out);
- cambia ambos → crea **2 overrides**;
- luego crea la reserva con esas horas **congeladas**;
- si algo falla, **no se crea nada**.

Flujo: en "Crear reserva manual", Vicky carga todo como hoy (cabaña, fecha check-in, fecha check-out, huésped, personas, monto/seña/saldo, notas). Antes de crear aparece la opción conceptual `[ ] Usar horario especial acordado`. Si se activa, se muestran solo los bordes de esa reserva (check-in del día de entrada, check-out del día de salida); puede completar uno o ambos. Para Vicky es **una sola acción "Crear reserva"**; los overrides nacen por detrás, sin pasos manuales.

### 5.4 Invariantes que NO se rompen
- Reservas/pre-reservas ya creadas conservan sus **horas congeladas**.
- Cambiar vigencias u overrides **no modifica** reservas ya creadas.
- Regla de disponibilidad: una reserva puede **entrar el mismo día que otra sale**, y **salir el mismo día que otra entra**, siempre que los horarios sean **compatibles** (gap same-day ≥2h).
- En reserva manual con horario pactado, si el horario especial **pisa** una reserva/pre-reserva anterior o posterior de la misma cabaña en el **mismo día de borde**, **falla** (ej.: otra sale lunes 10:00 ⇒ no se puede entrar lunes 08:00).
- No tocar OPS / portal-api / frontend / n8n / Vercel / canónico.

---

## 6. Entregables ANTES de artefactos (lo que Franco quiere ver)

En el primer paso (diseño, sin SQL), presentar:
1. **Arquitectura de tablas** — cabecera + detalle por día de semana (columnas, constraints, EXCLUDE, PK/FK).
2. **Cambios exactos de resolver/helper** — qué cambia en el Paso A del interno; nueva firma/cuerpo del helper; qué NO cambia (wrapper).
3. **Impacto sobre smokes/gates/fingerprints** — qué fingerprints cambian (interno, helper), cuáles sobreviven (wrapper `1bd96c89`, gates de overrides S0–S3), qué smokes/gates se rearman.
4. **Plan de migración/supersesión de B1.1 default/domingo** — orden seguro (crear tablas nuevas → reworkear interno/helper → dropear tabla/guard viejos), sin romper dependencias del interno; qué pasa con datos de TEST.
5. **Plan para conservar/reutilizar overrides S0–S3** — cómo encajan validadores/S2/S3 en el modelo nuevo, con qué extensiones mínimas.
6. **Plan para "Cambiar horarios puntuales" día puntual una/grupo/todas** — cómo se cubren los bordes independientes × alcances (ver decisión abierta §7).
7. **Plan para reserva manual con horario pactado** — el guard de composición atómica, reutilizando la validación per-cabaña, con el anti-pisar de bordes.

---

## 7. Decisiones de DISEÑO a resolver PRIMERO (abiertas)

Estas quedan para el arranque de la conversación nueva; conviene cerrarlas antes de detallar el diseño:

1. **Hueco S2/S3 para "Cambiar horarios puntuales" (la tensión principal).** El MVP pide **borde independiente × una/grupo/todas**. S2 hace borde único pero solo `cabana`/`global_estricto` (no grupo, no todas-parcial). S3 tiene los 5 alcances pero hace **checkout+checkin juntos**. Ninguno cubre "solo check-in × grupo/todas". **Lean:** generalizar S3 a **borde seleccionable** (checkin-only / checkout-only / ambos) reutilizando su motor de alcances probado (`cabana`/`grupo_estricto`/`todas_posibles`), o extraer ese motor a un guard puntual unificado. Definir cuál.
2. **Firma del helper G1 semanal.** Cómo recibe los valores por día de la vigencia prospectiva: mapa jsonb `dias: {0:{ci,co},…,6:{ci,co}}` (lean), 14 params, o lectura de detalle prospectivo. Impacta el fingerprint y los smokes.
3. **Shape del payload del guard semanal de vigencia** (`crear_vigencia_horario` v2): estructura de las 7 filas de detalle + modos A (`abierta`) / B (rango).
4. **Naming y migración de la tabla:** ¿cabecera evoluciona `vigencias_horario_base` en su lugar (quitando las 4 columnas) o nombre nuevo + detalle nuevo? ¿DROP+CREATE en TEST (datos descartables) o ALTER? Orden respecto del rework del interno.
5. **Etiqueta de origen del resolver para vigencia semanal.** Hoy el interno emite `'vigencia'` (no-domingo) / `'vigencia_domingo'` (domingo). Con semanal cada día es explícito: definir si queda `'vigencia'` uniforme (lean) o por día. Afecta el matching del helper y los smokes.
6. **Composición atómica de la reserva pactada.** ¿El guard llama a `crear_override_horario` (S2) por dentro, o reimplementa la lógica per-cabaña inline dentro de la transacción? Cuidado con lock re-entrante y subtx anidada; y con que la validación de bordes contemple la reserva que se está creando.
7. **Extensión a rango de "Cambiar horarios puntuales"** (evaluación, no implementación): cómo se generaliza el día puntual a rango sin rediseñar el guard.

---

## 8. Orden de arranque sugerido

1. Leer `EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md`.
2. Clone fresco; verificar estado real de B1.2-core en TEST (interno/wrapper/helper/overrides).
3. Cerrar las decisiones abiertas de §7.
4. Diseño de tablas (cabecera + detalle) → precedencia → helper/INV-1 → guards (vigencia semanal, puntual una/grupo/todas, reserva pactada) → impacto en smokes/gates/fingerprints → plan de migración/supersesión.
5. Presentar los 7 entregables de §6. **Hard stop.** Aprobación de Franco antes de cualquier artefacto.

---

## 9. Metodología (recordatorio)

Diseño → aprobación explícita de Franco → artefactos → **Franco ejecuta en TEST/Supabase/n8n/Vercel/git** (Claude nunca toca OPS, canónico, n8n, Vercel ni git directo) → Claude verifica → doc de cierre → propagación a satélites (solo al cierre formal). Validación SQL en capas: pglast → harness PostgreSQL 16.14 local → TEST → smokes. Sin acuñar D-*/L-* hasta el cierre formal. LF puro en todo el repo.
