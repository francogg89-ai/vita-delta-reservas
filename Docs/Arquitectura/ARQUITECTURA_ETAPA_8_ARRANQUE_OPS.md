# ARQUITECTURA ETAPA 8 — ARRANQUE OPS OPERATIVO DESDE CERO

**Estado:** Diseño — pendiente de validación de Franco.
**Tipo:** Documento de diseño. **No contiene SQL ni configuración de workflows.**
**Fecha de redacción:** 2026-05-29.
**Versión:** v2 (parches 1–7 aplicados sobre v1).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`.
**Entornos previos:** DEV (operativo), TEST (levantado y limpio, 7D). OPS y PROD aún no existen.

---

## 0. Cómo leer este documento

Este documento distingue de forma explícita, en cada sección, entre:

- **🔒 CERRADO** — decisión tomada y fijada. No se reabre salvo contradicción crítica. Condiciona la implementación.
- **🟡 OPCIÓN PENDIENTE** — alternativa que se decide **sobre el diseño de su propia sección, antes de implementarla**, no ahora. El documento NO asume silenciosamente ninguna opción. Se elige cuando se trabaje esa subetapa.

Esta distinción responde a un criterio acordado con Franco: **toda decisión que condicione cómo nace un entorno o un workflow se cierra antes de construirlo** (para no tener que modificar después un archivo ya hecho). Las decisiones que son elecciones internas de una subetapa todavía no construida se toman informadas, sobre el texto de diseño de esa sección, sin riesgo de retrabajo porque no hay nada escrito aún.

---

## 1. Contexto y encuadre

### 1.1 Qué es esta etapa

La Etapa 8 es el **primer uso operativo real** del sistema Vita Delta: el momento en que datos reales y productivos entran a la base por primera vez y en que el equipo (Franco, Vicky, Rodrigo) empieza a operar sobre el sistema en lugar de solo validarlo.

Es un **arranque desde cero**, no una migración. Esta caracterización es producto de una aclaración explícita de Franco: no hay un calendario histórico complejo que migrar ni un volumen de reservas pasadas que cargar. El sistema arranca prácticamente vacío y se puebla de ahora en adelante.

El MVP de la etapa tiene tres entregables encadenados, en orden de prioridad:

1. **Carga de reservas futuras reales vigentes** desde el día de arranque, usando el flujo determinístico ya existente.
2. **Capa de carga simple para Vicky**, que encadena el flujo completo en una sola acción.
3. **Dos calendarios visuales auto-actualizados**: uno operativo/comercial (Franco, Vicky, Rodrigo) y uno de limpieza (Jenny).

### 1.2 Qué queda explícitamente FUERA de esta etapa

Para evitar sobreingeniería y mantener el MVP acotado, quedan **fuera de alcance**:

- **Migración histórica / backfill.** No se diseña ni se ejecuta. El pasado no importa para este MVP.
- **Carga de reservas pasadas.** Solo se cargan reservas futuras vigentes desde el día de arranque.
- **Tarifas reales cargadas.** El monto se ingresa manualmente por reserva (ver sección 2). Las tarifas quedan como mejora futura.
- **Frontend de carga "de verdad".** Es el norte a mediano plazo (ver 1.4), pero no se construye en esta etapa.
- **Bot conversacional.** Etapa futura.
- **MercadoPago real / webhook MP.** Etapa futura, siempre sobre TEST primero.
- **RLS y cierre del residual A5 en DEV.** No se tocan en esta etapa (ver 1.3). El residual A5 de DEV sigue siendo el pendiente 1.7, con su propio tratamiento futuro.

### 1.3 Principios heredados que enmarcan la etapa

Estos principios vienen de decisiones cerradas en etapas anteriores y NO se reabren:

- **Opción A (acceso por `postgres`/n8n vía pooler).** El único consumidor de la base es n8n, que entra como `postgres.<ref>` por el pooler. No hay consumidores Data API/PostgREST activos. Esto es lo que permite mantener RLS postergado y el residual A5 sin tocar.
- **El MVP NO requiere RLS ni cierre de A5 para funcionar.** Mientras lectura y escritura pasen por `postgres`, el residual es irrelevante. RLS solo se vuelve no-postergable si OPS resultara ser "Opción B" (frontend interno con login que entra como `authenticated`) — y el MVP descrito **no lo es**.
- **Puertas únicas, sin INSERT directo.** Toda reserva confirmada pasa por `confirmar_reserva()`. Toda pre-reserva pasa por `crear_prereserva()`. Todo bloqueo pasa por `crear_bloqueo()`. No existe INSERT/UPDATE manual a `reservas`/`pre_reservas`/`bloqueos` desde n8n. El EXCLUDE constraint es protección estructural adicional.
- **La separación de pasos del motor no se toca.** `crear_prereserva → registrar_pago → confirmar_reserva` siguen siendo tres funciones separadas en el motor; lo que se construye encima es una capa de orquestación, no una fusión de las funciones.
- **RESERVAS es la fuente final de verdad.** Los calendarios son lectura derivada de vistas, nunca fuente autoritativa.

### 1.4 El norte futuro que esta etapa NO debe pisar

El ideal a mediano plazo es un **frontend de carga** donde el equipo cargue las reservas directamente y la mayoría de las reservas entren por ahí, manteniendo siempre los dos calendarios. **Ninguna decisión de esta etapa debe cerrarle la puerta a ese frontend.**

Consecuencia de diseño: el día que se construya ese frontend con login real (entrando como `authenticated` por Data API), recién ahí habrá que cerrar A5 y diseñar RLS. Por eso conviene **no adelantar ese trabajo** para un calendario interno de tres personas: se haría una sola vez, con propósito, cuando exista el frontend de verdad.

---

## 2. Criterio de carga de datos reales

Regla de decisión para qué entra como qué:

### 2.1 🔒 CERRADO — Reserva real con datos suficientes → flujo normal completo

Si una ocupación futura tiene **cliente identificado y datos suficientes** (seña/pago, teléfono, nombre, apellido, cantidad de personas), entra como **reserva real** recorriendo el flujo determinístico completo:

```
crear_prereserva()  →  registrar_pago()  →  confirmar_reserva()
```

Con seña confirmada, teléfono, nombre, apellido y personas alcanza para recorrer las tres puertas. Como las reservas llegan **ya cerradas y con la seña confirmada por WhatsApp**, el camino de confirmación es el **estricto** (pago ya confirmado), no el combinado (pago en revisión + validación humana). Vicky no valida pagos: transcribe una reserva ya cerrada.

### 2.2 🔒 CERRADO — Ocupación sin datos de cliente → bloqueo

Si la ocupación futura **no tiene datos de cliente** (uso propio, mantenimiento, corte operativo, o cualquier caso donde no haya datos suficientes de reserva), entra como **bloqueo** vía `crear_bloqueo()`. Los motivos válidos del schema son `mantenimiento`, `uso_propio`, `tormenta`, `overbooking`, `otro`.

### 2.3 🔒 CERRADO — Sin INSERT directo

Nunca se inserta directo a `reservas`, `pre_reservas` ni `bloqueos`. Todo pasa por las funciones del schema. (Heredado, no se reabre.)

### 2.4 🔒 CERRADO — Manejo del monto y la seña

Vicky **carga el monto total**. El sistema **pre-rellena la seña como 50% del total**, pero la seña **queda editable** porque en la práctica puede variar (el propio boceto del calendario muestra señas de 66% y 62%, no 50% exacto). Esto cubre el caso normal sin fricción y el caso real donde la seña fue otra.

El saldo se deriva: `monto_saldo = monto_total − seña`. Sin tarifas reales en esta etapa: el monto no se calcula desde una tabla de precios, lo ingresa el operador.

---

## 3. Etapa 8A — Entorno `vita-delta-ops` limpio

### 3.1 Objetivo

Crear el cuarto entorno de la estrategia DEV → TEST → OPS → PROD: un proyecto Supabase nuevo, **reconstruido desde el canónico v1.7.3** (no clonado de DEV), siguiendo el mismo método validado en 7B para levantar TEST. Este entorno es donde nacerán los primeros datos reales, por lo que debe nacer correcto desde el día cero.

**Qué es OPS (y qué no es).** OPS **no es un entorno de prueba más**. Es el **entorno real interno** donde van a vivir los datos reales de reservas del complejo. La jerarquía de entornos queda así:

- **DEV** — desarrollo.
- **TEST** — entorno donde se prueban cambios futuros **antes** de pasarlos a OPS. Toda prueba funcional completa vive acá.
- **OPS** — **operación real interna**. Datos reales. **No se hacen pruebas destructivas ni experimentos.** Cualquier verificación en OPS es smoke mínimo, controlado y justificado (ver 6.3).
- **PROD** — futuro, público.

OPS **todavía no es PROD público**, pero sí es **operación real interna** desde el inicio. Esta distinción es deliberada: justifica por qué OPS debe nacer correcto (sección 3.2) y por qué no se ensucia con experimentos (sección 6.3).

### 3.2 🔒 CERRADO — OPS nace con grants mínimos (modelo TEST), sin heredar la deuda de DEV

`vita-delta-ops` nace con el modelo de permisos mínimo, **cerrando el equivalente al residual A5 desde el día cero**. Esto incluye:

- **No exposición automática de tablas nuevas a Data API.** Los roles `anon`/`authenticated`/`service_role` no reciben el set amplio de SELECT/escritura sobre tablas/vistas que sí tiene DEV (los 480 grants del hallazgo A5). El residual aceptable es a lo sumo el `Dxtm` (`TRUNCATE/REFERENCES/TRIGGER`) que es el default de Supabase y es inocuo (modelo de TEST, D-7B-03).
- **`REVOKE EXECUTE` sobre las funciones del proyecto** para `PUBLIC`, `anon`, `authenticated` y `service_role`, como paso de creación (regla D-7B-05 / D-7E-01). Incluye las 3 funciones de trigger por paridad (inocuo, D-7E-02).
- **Revisión de `ALTER DEFAULT PRIVILEGES` / `pg_default_acl`,** no solo los grants actuales, para que **cada objeto nuevo nazca cerrado** y no reabra la asimetría. Esta es la lección clave: si solo se cierran los grants existentes pero los defaults siguen abiertos, cada tabla/función nueva vuelve a nacer abierta (análogo a lo observado con EXECUTE-PUBLIC por default en 7E/L-7B-02).
- **n8n entra por pooler como `postgres`,** no por Data API. El owner `postgres` queda intacto y ejecuta funciones por ownership; el REVOKE EXECUTE no lo afecta.

**Diferencia explícita con DEV:** el residual A5 de DEV (pendiente 1.7) **no se toca en esta etapa** y sigue su propio curso. OPS simplemente no nace con ese problema. No se "arregla DEV"; se "nace bien en OPS".

### 3.3 🔒 CERRADO — Reconstrucción desde el canónico, método 7B

OPS se levanta desde `6B_SCHEMA_SQL.md v1.7.3` con el mismo procedimiento de 7B: extensiones, enums, tablas, constraints, índices, EXCLUDE, funciones, triggers, vistas. Se busca paridad estructural con DEV/TEST (el mismo tipo de verificación 10/10 de 7B). **No es un clon de DEV** (no arrastra datos ni la deuda de grants de DEV).

### 3.4 🔒 CERRADO — Seeds reales mínimos

OPS se siembra con los datos estructurales reales mínimos para operar:

- **5 cabañas reales.** Nota crítica heredada: **los IDs de cabaña no son portables entre entornos** (DEV usa 17-21, TEST usa 1-5). OPS tendrá sus propios IDs, que habrá que determinar empíricamente al crear el entorno. Lo portable es la estructura lógica, no los valores. Cualquier workflow `__OPS` debe usar los IDs reales de OPS.
- **3 socios** (Franco, Rodrigo, Remo).
- **Cuenta(s) de cobro real(es).**
- **Claves de `configuracion_general`** (incluida `horizonte_disponibilidad_dias`).
- **Sin tarifas reales** (decisión de esta etapa: monto manual). Si el seed estructural requiere al menos una temporada baseline para no romper, se siembra una baseline neutra como en DEV/TEST, pero no es fuente de precios.
- **Plantilla(s) de mensaje** si aplica.

### 3.5 🔒 CERRADO — pg_cron y workflows `__OPS`

- **`pg_cron` activo en OPS**: `expirar_prereservas` (cada 5 min) y `cleanup_cron_history` (mensual), igual que DEV/TEST.
- **Workflows n8n con sufijo `__OPS` y credencial propia** (análogo a `vita_supabase_test` de 7B). Aislamiento por credencial, objetos n8n nuevos (no modificaciones de los de DEV/TEST), y marcadores de ambiente en `source_event`.

### 3.6 🟡 Nota — no hay opciones pendientes en 8A

Todo lo que condiciona cómo nace OPS está cerrado en esta sección. 8A es íntegramente implementable una vez validado el documento.

---

## 4. Etapa 8B — Capa de carga de Vicky

### 4.1 Objetivo

Que Vicky (y Franco, y Rodrigo) puedan cargar una reserva ya cerrada en **una sola acción**, sin tener que ejecutar ni esperar paso por paso el flujo `crear_prereserva → registrar_pago → confirmar_reserva`. La complejidad del encadenado queda escondida en n8n.

### 4.2 🔒 CERRADO — El encadenado vive en n8n, no en el motor

El motor mantiene las tres funciones separadas (es lo que protege locks, idempotencia y revalidación). La **capa de carga** las encadena: el operador completa los datos + "seña confirmada" y dispara una sola acción; n8n orquesta los tres llamados en secuencia y devuelve un resultado único ("Reserva confirmada ✅" o un error claro). El operador no ve pre-reserva, pago ni confirmación como pasos separados.

### 4.3 🔒 CERRADO — Camino estricto

Como el pago/seña llega ya confirmado por WhatsApp, la confirmación usa el **camino estricto** (`confirmar_reserva` con pago confirmado), no el combinado. (Ver 2.1.)

### 4.4 🔒 CERRADO — Montos

Vicky carga el total; seña pre-rellenada al 50% pero editable; saldo derivado. (Ver 2.4.)

### 4.5 🔒 CERRADO (concepto) / 🟡 mapeo técnico por verificar — Trazabilidad por "cargado por"

La acción de carga captura un campo **`operador`** (o `cargado_por`): Franco / Vicky / Rodrigo. La **idea de trazabilidad multiusuario queda cerrada**.

El **mapeo técnico exacto** de ese campo a los campos reales de cada función o log se define **en el diseño técnico de cada workflow de 8B**, contra el contrato real verificado. Candidatos según la función: `created_by`, `creado_por`, `validado_por`, `modificado_por`, `source_event`, o `set_config('app.modificado_por', ...)` / `set_config('app.source_event', ...)`.

**Antes de implementar 8B se verifica el contrato real** de las funciones con `pg_get_functiondef` / inspección de schema. **No se asumen nombres de campos.** (Lección heredada: no dar por sentado contratos sin verificarlos.)

### 4.6 🔒 CERRADO — Manejo claro de colisión de disponibilidad

Si dos personas cargan la misma cabaña para fechas que se solapan casi simultáneamente, el motor ya impide el doble-booking (locks validados en H7 + EXCLUDE constraint: es estructuralmente imposible). Lo que 8B debe garantizar es que el **segundo** operador reciba un mensaje claro de negocio ("esa cabaña ya está ocupada esas fechas") en lugar de un error técnico crudo. Esto es UX de la capa de carga, no un cambio en el motor.

### 4.7 🔒 CERRADO — Primera interfaz de carga: n8n Form Trigger

La primera interfaz de carga de 8B es un **formulario n8n (Form Trigger)**. Decisión cerrada.

- **Usable desde el celular** por Vicky, Rodrigo y Franco.
- El formulario dispara el workflow que encadena las 3 funciones; la carga entra por n8n y n8n llama las funciones SQL por pooler como `postgres`.
- **El Form Trigger no abre Data API/RLS.** El formulario habla con n8n, n8n habla con Supabase por pooler. No aparece ningún consumidor Data API. Se mantiene Opción A, igual que el calendario.
- **Sheet queda descartado como interfaz de escritura crítica** para este MVP, para evitar que vuelva a sentirse como base operativa o fuente de verdad. (Nota: esto descarta el Sheet como *puerta de escritura*; **no** lo descarta como posible formato de *visualización* en 8C, que es lectura derivada y no fuente de verdad — decisión aparte, ver 5.6.)
- **Pantalla mínima propia** queda como **evolución futura posterior**, no como primera implementación. Es el escalón hacia el frontend de carga (norte de 1.4), no parte de este MVP.

### 4.8 🟡 OPCIÓN PENDIENTE — Política de seña (profundización)

Franco dejó abierta la posibilidad de profundizar la regla de seña. La decisión base está cerrada (total cargado, seña 50% editable). Si en 8B surge necesidad de afinar (p. ej. validaciones sobre el porcentaje, o registrar el motivo cuando la seña no es 50%), se trata ahí. No bloquea el diseño.

---

## 5. Etapa 8C — Calendarios visuales por evento

### 5.1 Objetivo

Dos calendarios que "se actualizan solos":

- **Calendario operativo/comercial** (Franco, Vicky, Rodrigo): formato del boceto aportado por Franco — grilla mensual, filas por cabaña con sub-filas huésped·personas·horario / teléfono / pagado·pendiente, columnas día por día, banda continua para estadías multi-día, marca de mismo-día (salida+entrada), horas de check-in/check-out y "Pagado $X · Debe $Y". Fuente: **`vista_calendario`** (ya contiene cabaña, huésped, personas, horarios, monto_total, monto_saldo, teléfono).
- **Calendario de limpieza** (Jenny): **sin datos sensibles** — solo horarios de check-in/check-out y cantidad de personas. Fuente: **`vista_limpieza_semana`** (ya trae exactamente eso: tipo de movimiento, hora, personas, sin exponer monto; nombre/teléfono se omiten en el render).

### 5.2 🔒 CERRADO — Actualización por evento, no por reloj

Observación de Franco que define el patrón: el calendario solo tiene algo nuevo que mostrar **cuando se concreta una reserva (o un bloqueo)**. Por lo tanto **no hay polling ni cron de calendario**. El repintado es el **último paso del workflow de escritura**: cuando el encadenado de 8B confirma una reserva con éxito, dispara el repintado del calendario como consecuencia natural. Lo mismo para `crear_bloqueo` en 8D.

### 5.3 🔒 CERRADO — El repintado se mantiene en Opción A

El repintado lo ejecuta **n8n corriendo como `postgres` por el pooler**, leyendo las vistas. El calendario **no es un consumidor externo que consulta la base por Data API**; es una salida que n8n genera al final de cada operación de escritura. Esto mantiene el sistema firmemente en Opción A: **sin Data API, sin RLS, sin tocar A5.** Es la razón por la que esta vía se eligió frente a "web que lee Supabase directo" (que habría obligado a cerrar A5 y diseñar RLS antes de tiempo — sobreingeniería para un calendario interno de tres personas).

### 5.4 🔒 CERRADO — Workflow manual de repintado completo (herramienta de reparación)

Además del repintado por evento (patrón normal), existe un **workflow manual de "repintar calendario ahora"**.

- **No es cron, no es polling, no cambia la fuente de verdad.** Regenera el calendario completo leyendo Supabase (vistas) por pooler como `postgres`.
- **Para qué sirve:** reparación operativa. Si falló el último repintado por evento, si se cambió el diseño visual, si hubo un error de Google/hosting, o si se quiere regenerar el calendario desde cero desde Supabase.
- **Quién lo activa:** Franco, Vicky o Rodrigo. **El disparador vive dentro de n8n** (un Form Trigger mínimo o disparo desde la interfaz de n8n), reutilizando la misma credencial y aislamiento del resto de workflows `__OPS`. **No** se expone como endpoint público suelto: aunque el repintado es inofensivo para la integridad (no toca la fuente de verdad), un acceso sin fricción quedaría expuesto a disparos innecesarios o no controlados. Si más adelante se quiere un acceso más cómodo, se evalúa como evolución; para el MVP el disparador es n8n.

### 5.5 🔒 CERRADO — Criterio "todo workflow que toca disponibilidad confirmada, repinta al final"

No solo el alta de reserva dispara repintado. Cualquier workflow que **modifique disponibilidad confirmada** (alta de reserva, alta de bloqueo, cancelación de reserva confirmada) termina con el mismo paso de repintado. Casos que NO requieren repintar el calendario operativo: la expiración de una pre-reserva por el cron (el calendario nuestro muestra reservas confirmadas, no pre-reservas, así que una pre-reserva que expira no cambia lo que se ve). Este criterio se aplica de forma uniforme para evitar calendarios desactualizados por caminos que no pasan por la capa de carga.

### 5.6 🟡 OPCIÓN PENDIENTE — Destino del repintado: Sheet vs HTML

**No se decide en este documento.** Se decide sobre el diseño de 8C, antes de construirlo. Las dos opciones realistas:

- **(a) Google Sheet repintado**: n8n escribe las celdas con el estilo del boceto (verde ocupado, rojo mismo-día, etc.). Pro: formato del boceto directo, familiar, compartible por permisos de Google. Contra: límites de formato/estilo vía API. (Nota: aquí el Sheet es **lectura derivada/visualización**, no escritura crítica — es un uso permitido, distinto del descartado en 4.7.)
- **(b) HTML servido**: n8n regenera un archivo HTML que se sirve en algún lado. Pro: control total del diseño. Contra: hay que definir dónde se hostea y mantenerlo.

Ambas se mantienen en Opción A (n8n lee por pooler como `postgres`). La elección no afecta a 8A ni 8B. **El documento no asume ningún formato.** Hasta que se elija, 8C no se construye.

### 5.7 Nota sobre el boceto

El boceto aportado (`calendario_vita_delta_v2`) es la **referencia de presentación** del calendario operativo, no la fuente de datos. La fuente es `vista_calendario`. El boceto define cómo se ve; la vista define qué se ve. La pieza a construir en 8C es solo el render (de filas de la vista → grilla pintada).

---

## 6. Etapa 8D — Bloqueos operativos + cierre

### 6.1 Objetivo

Completar el arranque con la carga de ocupaciones sin cliente y cerrar formalmente la etapa.

### 6.2 🔒 CERRADO — Bloqueos vía `crear_bloqueo`

Uso propio, mantenimiento, cortes operativos y casos sin datos suficientes de cliente entran por `crear_bloqueo()` (motivos válidos: `mantenimiento`, `uso_propio`, `tormenta`, `overbooking`, `otro`). Incluye el repintado del calendario al final (criterio 5.5).

### 6.3 🔒 CERRADO — Validación: completa en TEST, smoke mínimo en OPS

- **Las pruebas funcionales completas** de workflows nuevos o cambios se hacen **primero en TEST**.
- **En OPS solo se hace smoke mínimo controlado y justificado:** cargar una reserva real por la capa de 8B, ver que aparece correctamente en ambos calendarios, cargar un bloqueo, y verificar que el calendario de Jenny no expone datos sensibles.
- **Si el smoke usa una reserva**, debe ser una **reserva real futura válida** (no inventada).
- **Si excepcionalmente se usa un dato ficticio en OPS**, debe quedar **explícitamente marcado** y limpiarse con **procedimiento aprobado**, no de forma improvisada.
- Objetivo: **no ensuciar OPS desde el inicio.**

### 6.4 🔒 CERRADO — Cierre formal

La etapa se cierra con un documento de cierre formal (`8_CIERRE.md` o equivalente), registro de decisiones D-8-XX, actualización de `ESTADO_ACTUAL_VITA_DELTA.md`, `CLAUDE.md`, `DECISIONES_NO_REABRIR.md` y `Pendiente_pre_produccion.md`, siguiendo la disciplina de cierre de etapas anteriores.

---

## 7. Decisiones a registrar (D-8-XX) y pendientes que quedan abiertos

### 7.1 Decisiones cerradas en este documento (a formalizar como D-8-XX en el cierre)

- **D-8-01** — Etapa 8 es arranque OPS desde cero, no migración. Sin backfill, sin reservas pasadas.
- **D-8-02** — Reserva real con datos → flujo `crear_prereserva → registrar_pago → confirmar_reserva` (camino estricto). Ocupación sin cliente → `crear_bloqueo`. Sin INSERT directo.
- **D-8-03** — OPS nace con grants mínimos (modelo TEST): no exposición automática de tablas a Data API, REVOKE EXECUTE sobre funciones para PUBLIC/anon/authenticated/service_role, revisión de DEFAULT PRIVILEGES para que objetos nuevos nazcan cerrados. n8n entra por pooler como `postgres`. El residual A5 de DEV no se toca.
- **D-8-04** — Vicky carga el total; seña pre-rellenada 50% editable; saldo derivado. Sin tarifas reales en esta etapa.
- **D-8-05** — Capa de carga encadena las 3 funciones en n8n; el motor mantiene los pasos separados.
- **D-8-06** — Trazabilidad multiusuario mediante campo `operador`/`cargado_por` capturado en la carga. El mapeo a campos reales (`created_by`, `creado_por`, `modificado_por`, `validado_por`, `source_event`, `set_config`, etc.) se define por contrato real verificado antes de implementar 8B, sin asumir nombres.
- **D-8-07** — Calendarios se actualizan por evento (post-escritura), no por polling/cron. Repintado vía n8n/pooler como `postgres` (Opción A, sin Data API/RLS).
- **D-8-08** — Criterio uniforme: todo workflow que modifica disponibilidad confirmada repinta el calendario al final.
- **D-8-09** — OPS es operación real interna desde el inicio (no entorno de prueba). TEST es el entorno de prueba de cambios futuros. En OPS no se hacen pruebas destructivas; solo smoke mínimo controlado.
- **D-8-10** — Primera interfaz de carga de 8B = n8n Form Trigger, usable desde celular. Sheet descartado como interfaz de escritura crítica (no como visualización). Pantalla propia = evolución futura.
- **D-8-11** — Existe un workflow manual de repintado completo (reparación), disparado desde n8n, que no es cron/polling y no altera la fuente de verdad.
- **D-8-12** — Validación: completa en TEST, smoke mínimo controlado en OPS; datos ficticios en OPS solo marcados y con limpieza aprobada.

(La numeración definitiva se fija en el cierre.)

### 7.2 Pendientes que quedan abiertos al terminar la etapa

- **Formato de 8C** (Sheet repintado vs HTML servido) — se decide al diseñar 8C.
- **Profundización de la política de seña** — opcional, se trata en 8B si surge.
- **Tarifas reales** — fuera de alcance; mejora futura.
- **Frontend de carga "de verdad"** (y la pantalla mínima propia como escalón previo) — norte a mediano plazo; cuando se construya con login real, recién ahí se cierra A5 y se diseña RLS.
- **Residual A5 en DEV (pendiente 1.7)** — sigue su propio curso, no se toca en esta etapa.
- **IDs de cabaña reales de OPS** — se determinan empíricamente al crear el entorno (no portables desde DEV/TEST).

---

## 8. Multi-usuario

### 8.1 🔒 CERRADO (concepto) — Trazabilidad por "cargado por"

Que cada operador ponga su nombre al cargar es la solución correcta y suficiente para el MVP. La carga captura un campo `operador`/`cargado_por` (Franco / Vicky / Rodrigo). El **mapeo técnico** de ese campo se resuelve al campo que corresponda según el **contrato real de cada función** (verificado con `pg_get_functiondef` antes de implementar 8B): `created_by`, `creado_por`, `modificado_por`, `validado_por`, `source_event`, `set_config(...)`, según el caso. **No se asumen nombres de campos de forma uniforme.** El concepto de trazabilidad está cerrado; el mapeo exacto es trabajo de diseño técnico de 8B.

### 8.2 🔒 CERRADO — Concurrencia destructiva ya resuelta en el motor

Tres personas cargando en paralelo no generan doble-booking: los locks (lock global → lock por cabaña, orden invariante) y el EXCLUDE constraint sobre `reservas` lo impiden estructuralmente. Validado empíricamente en H7 (6 tests de concurrencia real, sin deadlocks ni races ni doble booking).

### 8.3 Lo que multi-usuario NO resuelve por sí solo (se cubre en 8B)

El campo "cargado por" no resuelve la **presentación de la colisión**: cuando el segundo operador intenta cargar una cabaña/fecha ya tomada, debe recibir un mensaje de negocio claro, no un error técnico. Eso es UX de 8B (ver 4.6). No es un problema de integridad —que ya está resuelto— sino de experiencia de uso.

### 8.4 Profundización pendiente

Franco indicó que quiere hablar el multi-usuario en profundidad. La base está cerrada (campo "cargado por" + concurrencia resuelta por motor). Cualquier refinamiento adicional (identidades por operador en la capa de carga, permisos diferenciados, etc.) se discute al diseñar 8B, sin bloquear este documento.

---

## 9. Resumen: qué está cerrado y qué queda abierto

| Punto | Estado |
|---|---|
| Etapa = arranque desde cero, sin migración | 🔒 Cerrado |
| Criterio reserva real → flujo / sin cliente → bloqueo / sin INSERT directo | 🔒 Cerrado |
| Monto: total cargado, seña 50% editable | 🔒 Cerrado |
| OPS = operación real interna; TEST = pruebas completas; OPS = solo smoke mínimo | 🔒 Cerrado |
| OPS nace con grants mínimos (modelo TEST), defaults cerrados, n8n por pooler | 🔒 Cerrado |
| OPS reconstruido desde canónico v1.7.3 + seeds reales mínimos + pg_cron + workflows `__OPS` | 🔒 Cerrado |
| Encadenado de 3 funciones en n8n, camino estricto | 🔒 Cerrado |
| Primera interfaz de carga = n8n Form Trigger (Sheet descartado como escritura crítica) | 🔒 Cerrado |
| Trazabilidad "cargado por" | 🔒 Cerrado (concepto); mapeo técnico por contrato real en 8B |
| Manejo claro de colisión (UX) | 🔒 Cerrado (se implementa en 8B) |
| Calendarios por evento, en Opción A, sin Data API/RLS | 🔒 Cerrado |
| Workflow manual de repintado (reparación, desde n8n) | 🔒 Cerrado |
| Criterio "repinta al final" uniforme | 🔒 Cerrado |
| Validación TEST-completo / OPS-smoke | 🔒 Cerrado |
| **Formato de 8C** (Sheet repintado vs HTML servido) | 🟡 Opción pendiente — se decide sobre el diseño de 8C |
| Profundización de seña / multi-usuario | 🟡 Se trata en 8B, no bloquea |

**Ningún punto marcado 🟡 implica modificar un archivo ya construido**, porque las subetapas a las que pertenecen no se construyen hasta que su opción se decida sobre el diseño de esa sección.

---

*Fin del documento de diseño de la Etapa 8 (v2). Pendiente de validación de Franco antes de iniciar implementación (que arrancaría por 8A). No se ha generado SQL ni configuración de workflows.*
