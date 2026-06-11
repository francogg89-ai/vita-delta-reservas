# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas (Bamboo, Madre Selva, Arrebol, Guatemala, Tokio). Centraliza disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack actual es **Supabase / PostgreSQL** como base de datos y fuente de verdad, **n8n** como orquestador de workflows, y **Claude API** como capa conversacional futura. El proyecto migró desde un stack inicial sobre Google Sheets; esa migración (Etapa 6B) está ejecutada y cerrada en el entorno DEV, y el sistema cuenta además con un entorno TEST levantado y validado, y un entorno **OPS de operación real interna** levantado, paritario, seguro y conectado a n8n (Etapa 8A). Sobre OPS ya funciona la **capa de carga interna de reservas** (Etapa 8B): un formulario n8n con el que el equipo carga reservas reales en una acción. El sistema **ya está tomando reservas reales** (primera reserva real cargada en el smoke de 8B). Sobre esa base se construyó la **capa de calendarios visuales** (Etapa 8C): tres vistas de solo lectura — calendario operativo del equipo, calendario de limpieza para Jennifer (sin montos) y un Sheet de resguardo — que presentan el estado del sistema sin tocar el motor, hoy activas y en uso real. Por último, la **capa de bloqueos operativos** (Etapa 8D) agrega un formulario n8n para que el equipo bloquee una cabaña (mantenimiento, uso propio, clima) en una acción. **Con 8D se cierra la Etapa 8 (operación real interna):** el equipo opera el complejo con tres acciones autoservicio sobre OPS — cargar reservas, ver el estado y crear bloqueos —, todo sobre Supabase como fuente de verdad. Sobre esa base se sumó la **sub-etapa 8C-bis** (alerta por reserva próxima): un aviso automático por mail al equipo y a Jennifer cuando se confirma una reserva con check-in dentro de los próximos 7 días, disparado en rama lateral desde el formulario de carga sin afectar la reserva si el envío falla.

En paralelo a la operación, la **contabilidad operativa interna (Carril B)** —separada de la fiscal/legal (AFIP/ARCA/IVA quedan fuera)— avanzó en TEST con las sub-etapas **9C** (catálogo de cabañas enriquecido, zonas y titularidad), **9D** (activación operativa por rango) y **9E** (matriz dinámica de participación), todas cerradas y verificadas en TEST y **aún no promovidas a OPS**. El schema canónico **no se bumpea** por esto: se actualizará una sola vez, en la promoción coordinada de todo el Carril B.

> La IA conversa. n8n orquesta. PostgreSQL decide y persiste. Los humanos auditan.

---

## Estado actual

### Arquitectura — Completada y aprobada

Todas las etapas de diseño están cerradas. No se reabren.

| Etapa | Descripción | Estado |
|---|---|---|
| 1 | Arquitectura base | Cerrada |
| 2 | Motor de disponibilidad | Cerrada |
| 3 | Motor de precios | Cerrada |
| 4A | Motor de reservas determinístico | Cerrada |
| 4B | Bot conversacional con IA | Cerrada |
| 5A | Modelo de datos real | Cerrada |
| 5B | Implementación vertical mínima | Cerrada |
| 6A | Decisión de migración a base relacional | Cerrada |
| 6B | Migración a Supabase / PostgreSQL | Cerrada (diseño + ejecución en DEV) |

### Implementación — Backend Supabase + workflows n8n

| Etapa | Descripción | Estado |
|---|---|---|
| 6B (Fases 0-3) | Schema, funciones, triggers, vistas, seed, `pg_cron` en DEV | Cerrada |
| 6C | Reescritura de workflows n8n contra Supabase DEV | Cerrada (2026-05-26) |
| 6D | Hardening pre-producción (validación SQL, concurrencia) | Cerrada (2026-05-27) |
| 7A | Correcciones pre-TEST / pre-OPS | Cerrada (2026-05-28) |
| 7B | Levantamiento del entorno TEST | Cerrada (2026-05-28) |
| 7C | Validación funcional ampliada sobre TEST | Cerrada (2026-05-28) |
| 7D | Limpieza/reset del entorno TEST | Cerrada (2026-05-28) |
| 7E | Endurecimiento de permisos Data API en DEV (paridad con TEST) | Cerrada (2026-05-28) |
| 8A | Levantamiento del entorno OPS (operación real interna) | Cerrada (2026-05-29) |
| 8B | Capa de carga interna de reservas (Form Trigger n8n) | Cerrada (2026-05-30) |
| 8C | Calendarios visuales por evento (HTML operativo + limpieza + Sheet resguardo) | Cerrada (2026-06-01, TEST + OPS) |
| 8D | Capa de bloqueos operativos (Form Trigger n8n) | Cerrada (2026-06-04, TEST + OPS) — **cierra la Etapa 8** |
| 8C-bis | Alerta por reserva próxima por mail (sub-workflow, rama lateral en 8B) | Cerrada (2026-06-04, TEST + OPS activo) |
| 9A | Diagnóstico de ingresos (read-only) | Cerrada |
| 9B / 3b | Cobranza posterior multi-porción (Form Trigger transaccional) — *Carril A* | Cerrada **en TEST** (2026-06-07); **no promovida a OPS** |
| 9C | Carril B — catálogo enriquecido, zonas y titularidad (seam `resolver_beneficiario`) | Cerrada **en TEST** (2026-06-10); **no promovida a OPS** |
| 9D | Carril B — activación operativa por rango (`activaciones_operativas`, `[)` + EXCLUDE) | Cerrada **en TEST** (2026-06-10); **no promovida a OPS** |
| 9E | Carril B — matriz dinámica de participación (read-only, deriva sin persistir) | Cerrada **en TEST** (2026-06-10); **no promovida a OPS** |
| 9F | Carril B — gasto interno rediseñado (`gastos_internos`: la clase A/C/D/E define momento y alcance) | Cerrada **en TEST** (2026-06-10); **no promovida a OPS** |
| 9G | Carril B — cascada de liquidación read-only (6 funciones, 11 pasos, validación 40/40) | Cerrada **en TEST** (2026-06-11); **no promovida a OPS** — **cierra la capa derivada del Carril B** |

**Schema canónico actual:** `6B_SCHEMA_SQL.md v1.7.3`. DEV, TEST y OPS están alineados funcionalmente: TEST se reconstruyó desde el canónico en 7B (paridad 10/10 vs DEV) y OPS en 8A (paridad P01-P10 10/10). 8B no modificó el schema: la capa de carga usa las funciones existentes tal cual. 8C tampoco lo modificó: los calendarios son de solo lectura. 8D tampoco: la capa de bloqueos usa la función `crear_bloqueo()` existente tal cual. 8C-bis tampoco: es solo lectura (consulta una reserva por id) + envío de mail. **9B / 3b tampoco modifica el canónico:** la única adición es la función de orquestación `public.abortar_si_falla(jsonb)`, aditiva y **solo en TEST** (no toca tablas, enums ni `registrar_pago()`); su incorporación al canónico se evaluará en el trabajo de schema de contabilidad. **Las sub-etapas 9C-9G del Carril B sí agregaron objetos de schema, pero solo en TEST:** las columnas `valor_relativo` e `id_socio_beneficiario` en `cabanas`; las tablas `zonas`, `cabana_zona`, `activaciones_operativas` y `gastos_internos` (la `gastos` legacy quedó **congelada e intacta**; su destino se decide en la promoción — D-9F-01); **diez funciones read-only** (`resolver_beneficiario`, las tres de matriz/reparto de 9E y las seis de la cascada de 9G); y un marcador de entorno en `configuracion_general`. **El canónico no se bumpea por esto:** se actualizará una sola vez, en la promoción coordinada de todo el Carril B a OPS (junto con `abortar_si_falla`). Por eso **TEST hoy va por delante de DEV y OPS** en el schema de contabilidad operativa interna.

---

## Cómo funciona el sistema

```text
La IA conversa.
n8n orquesta.
PostgreSQL decide y persiste.
Los humanos auditan.
```

**Supabase / PostgreSQL** es la fuente de verdad. Las reglas críticas de disponibilidad, reservas, pagos y bloqueos viven en funciones SQL con locks, idempotencia y validación estructural (EXCLUDE constraints anti-double-booking).

**n8n** orquesta: recibe eventos, arma payloads, llama a las funciones SQL y maneja respuestas. No replica lógica interna de las funciones ni decide disponibilidad por su cuenta.

**Claude / IA** es la capa conversacional futura. Conversa con el huésped y llama a los workflows determinísticos. No confirma reservas, pagos ni disponibilidad por sí sola.

### Flujo base de una reserva

```text
Consulta entrante
  → vita_w01_consultar_disponibilidad_supabase
  → vita_w02_crear_prereserva_supabase     (bloqueo temporal + verificación bajo locks)
  → vita_w03_registrar_pago_supabase       (pago reportado → pre-reserva en revisión)
  → vita_w04_confirmar_reserva_supabase    (validación + confirmación → reserva definitiva)
```

La pre-reserva bloquea disponibilidad temporalmente y expira si no se confirma. La reserva se confirma solo después de validar pago y disponibilidad bajo locks.

### Operaciones adicionales

- `vita_w00_smoke_test_supabase` — verificación de conexión.
- `vita_w05_cancelar_prereserva_supabase`
- `vita_w06_crear_bloqueo_supabase`
- `vita_w07_vistas_operativas_supabase` — lectura de vistas operativas.

### Capa de carga interna (Etapa 8B)

- `vita_w8b_carga_reserva` — Form Trigger n8n (usable desde celular, Basic Auth) que encadena `crear_prereserva` → `registrar_pago` → `confirmar_reserva` en **una sola acción**, con compensación vía `cancelar_prereserva` ante fallo parcial. El operador elige cabaña por nombre, carga monto total y seña (vacía/0 → 50% automático), y recibe un resultado único (confirmada / error claro / revisión manual). Variantes `__TEST` (validado), `__OPS` (productivo) y `__TEMPLATE` (sanitizado reutilizable).

### Capa de calendarios visuales (Etapa 8C)

Tres vistas **derivadas de solo lectura** desde Supabase, sin tocar el motor ni el schema. Ninguna escribe en tablas transaccionales.

- `vita_w8c_html_operativo` — calendario del equipo (Franco/Rodrigo/Vicky/Remo). Grilla día×cabaña de 120 días con pestañas por mes; reservas confirmadas/activas + bloqueos, con montos, horarios y teléfono. HTML servido por n8n con Basic Auth propia. Es una **ventana en vivo**: se arma en cada visita a la URL, siempre muestra el estado actual.
- `vita_w8c_html_limpieza` — calendario de Jennifer. Grilla de 7 días **sin montos**, con mascotas y notas operativas. Basic Auth propia y separada de la del operativo y la del formulario 8B. También ventana en vivo.
- `vita_w8c_sheet_resguardo` — el calendario operativo volcado a un Google Sheet como respaldo offline (grilla con meses apilados, sin colores). A diferencia de los HTML, es una **foto estática** que se regenera por ejecución (hoy por disparo manual); se escribe vía HTTP a la API REST de Google Sheets. Diseñado autónomo para que el punto de extensión de 8B pueda invocarlo a futuro.

Pintado en la capa de presentación (no se lee 1:1 del campo `estado`): operativo **rojo > gris > verde > blanco**; limpieza **rojo > gris > amarillo (salida) > verde > blanco**. Validados en TEST y activos en OPS (los HTML en uso real por el equipo; el resguardo es manual). La alerta por reserva próxima (8C-bis) se resolvió después como sub-etapa propia (ver abajo).

### Capa de bloqueos operativos (Etapa 8D)

Un formulario n8n (Form Trigger, Basic Auth propia, usable desde celular) para que el equipo bloquee una cabaña en una acción, invocando la función `crear_bloqueo()`.

- `vita_w8d_bloqueo` — el operador elige cabaña por nombre, fecha desde, fecha hasta/liberación (modelo `[)`, exclusive), motivo (mantenimiento / uso propio / tormenta / overbooking / otro) y descripción opcional; recibe un resultado único en lenguaje humano ("Bamboo bloqueada desde el 10/06 hasta el 12/06 inclusive. Se libera el 13/06."). El bloqueo aparece en gris en los calendarios de 8C. Variantes `__TEST` (validado), `__OPS` (activo, en uso real) y `__TEMPLATE` (sanitizado).

La función `crear_bloqueo()` valida todo (cabaña, fechas, motivo, y los conflictos con reservas, pre-reservas y otros bloqueos), así que el formulario es solo capa de UX. Un bloqueo no convive con reservas: si hay una reserva en esas fechas, se rechaza. **8D solo crea bloqueos**: corregir o levantar uno requiere intervención manual (no hay desbloqueo desde el formulario). Una cabaña por vez; no hay bloqueo total del complejo ni selección múltiple en esta versión.

### Alerta por reserva próxima (Sub-etapa 8C-bis)

Un sub-workflow n8n (`vita_w8cbis_alerta`) que avisa por mail cuando se confirma una reserva con check-in dentro de los próximos 7 días.

- **Disparo en rama lateral desde el formulario de carga 8B:** al confirmarse una reserva, el punto de extensión de 8B invoca el sub-workflow en paralelo a la respuesta al operador. Si el envío del mail falla, la reserva confirmada no se ve afectada — el operador siempre recibe su "Reserva confirmada". Validado end-to-end.
- **Solo lectura + envío:** consulta la reserva por `id_reserva` (sin tocar el motor ni el schema) y manda dos correos de texto plano: uno al equipo operativo (Franco + Rodrigo, enlaza al calendario operativo) y uno a Jennifer (enlaza al calendario de limpieza).
- **Privacidad por construcción:** el mail solo informa cabaña, entrada y salida, más el enlace al calendario; no incluye montos, datos del huésped, teléfono ni notas. El detalle se ve abriendo el calendario, que ya tiene su propio control de acceso.
- **Canal = mail** (no Telegram ni WhatsApp). Remitente temporal sobre un Gmail propio del proyecto, migrable al mail de las cabañas sin rediseño. Variantes `__TEST` (validado con envío real) y `__OPS` (publicado y activo, con destinatarios reales). La primera ejecución real quedará registrada con la próxima reserva en ventana.

### Cobranza posterior multi-porción (Etapa 9B / Fase 3b)

Un formulario n8n (`vita_w09_cobranza_posterior`) con el que el equipo registra el **saldo cobrado después** de confirmada una reserva. Es la primera pieza de la etapa de contabilidad que escribe pagos (el diagnóstico 9A y el listado de saldos eran de solo lectura).

- **Hasta tres porciones en una sola carga:** efectivo, transferencia (bancaria o MercadoPago) y "otros" (USD/cripto/otro, registrado por su equivalente en pesos). La transferencia aplica un **recargo interno del 5%** que se registra como una línea separada y **no reduce** el saldo de alojamiento (es entrada de caja aparte).
- **Todo o nada:** todas las líneas de una cobranza se registran dentro de una sola transacción. Si cualquier línea falla, se revierte la cobranza completa y no queda ningún pago a medias. El operador recibe un mensaje claro: cobranza registrada (con saldo anterior → nuevo, e indica si la reserva quedó saldada), o un aviso de que la operación se revirtió.
- **Verificación posterior:** tras registrar, el sistema relee los pagos de esa cobranza y recalcula el saldo real desde la base, confirmando que el recargo no contaminó el saldo y que todo quedó confirmado.
- **Selección por listado:** el operador identifica la reserva desde un listado HTML interno de reservas con saldo pendiente (workflow `vita_w09_listado_saldos`), y carga su número en el formulario.
- **Estado:** validado en TEST con batería completa (incluido el caso de reversión). **No promovido a OPS todavía** — la promoción es un paso posterior con su propia preparación. Variantes: workflow validado en TEST + plantillas sanitizadas reutilizables.

### Contabilidad operativa interna — Carril B (Etapas 9C-9G)

La capa de **contabilidad operativa interna** entre socios, **separada de la fiscal/legal** (AFIP/ARCA/IVA quedan fuera) y distinta del Carril A (que fue diagnóstico 9A + cobranza 9B). Construye, paso a paso, los insumos y el cálculo del reparto del pool entre socios. Todo **validado en TEST y aún no promovido a OPS**; el canónico **no se bumpea** hasta la promoción coordinada de todo el Carril B. La metodología fue la de siempre: diagnóstico read-only → diseño aprobado bloque por bloque → ejecución en TEST por Franco → verificación → cierre parcial documentado.

- **9C — Catálogo enriquecido, zonas y titularidad.** Se agregaron a `cabanas` el `valor_relativo` y el `id_socio_beneficiario` (FK a `socios`); se creó el catálogo plano `zonas` y la pertenencia muchos-a-muchos `cabana_zona` (seed `grandes`/`chicas`); y el **punto único de resolución de titularidad** como función `resolver_beneficiario(id_cabana, fecha)` — el *seam*: hoy devuelve el beneficiario estable, mañana habilita titularidad por rango sin tocar a sus consumidores. (Detección lateral: hubo que completar el placeholder `Socio 3` → `Remo` antes del seed.)
- **9D — Activación operativa por rango.** Tabla `activaciones_operativas` con rango `[)` (`fecha_hasta NULL` = abierta/indefinida) y un `EXCLUDE` que impide solapamientos por cabaña — primer rango/EXCLUDE del Carril B. Modelo presencia/ausencia: rango = "en el pool", hueco = "afuera"; desactivar es dejar un hueco, reactivar es un rango nuevo. Composición real cargada: Bamboo, Madre Selva, Arrebol y Tokio activas desde `2026-07-01`; **Guatemala desactivada jul-oct 2026 y activa desde `2026-11-01`** (fechas reales, también para OPS). La política mensual ("cubre el mes completo") se aplica al derivar, no en el schema.
- **9E — Matriz dinámica de participación (read-only).** Tres funciones que **derivan, sin persistir nada**: `matriz_participacion` (proporción de cada socio en el pool del mes), `repartir_por_matriz` (reparte un monto dado por la matriz, con el **centavo residual** al socio de mayor participación; en empate, a Rodrigo solo si está en él, si no al menor `id_socio`) y `detalle_participacion` (matriz a nivel cabaña, para auditoría). No leen `pagos`: el ingreso entra en la cascada (9G). Validadas con datos reales (p. ej. julio: pool 378, Remo 0.4709; noviembre: pool 456, empate Franco/Remo 0.3904).
- **9F — Gasto interno rediseñado.** Tabla `gastos_internos` (17 columnas, 18 constraints nombradas): la **clase A/C/D/E define a la vez el momento de la cascada y el alcance** (D ⇒ zona, E ⇒ cabaña, A/C ⇒ general), imposible de violar por constraint; `clase_sugerida` + override **derivado** con comentario obligatorio; `periodo` normalizado a día 1 ("cuándo se pagó" ≠ "a qué liquidación entra"); pagador `socio|caja` (las horas de socio entran como gasto E valorizado a mano). La `gastos` legacy quedó **congelada e intacta**. Fixture técnico de 5 gastos (ids 30–34) para validar la incidencia.
- **9G — Cascada de liquidación read-only.** Seis funciones `sql STABLE` que **derivan la liquidación mensual completa sin persistir nada**: `cascada_periodo` (los 11 pasos), `saldo_socios_periodo`, `incidencia_gasto` y tres reportes (overrides, 5%-vs-fiscal, gastos sin incidencia derivable). El **% operativo es parámetro explícito** (no se congeló: el valor real lo definen los socios); **criterio de caja percibida** (período = mes de `created_at`); `GREATEST(base,0)` solo en el paso 4 (debajo, matemática con signo); lo no derivable **se reporta sin restarse** (pool vacío / zona sin activas). Validación **40/40 en TEST** reproduciendo el ejemplo canónico al centavo; junio 2026 quedó como **anomalía de arranque real** ($1.345.000 percibidos con pool vacío, sin destinatarios — decisión de socios pendiente). El único write de la etapa fue un seed de 5 pagos de laboratorio que, junto al fixture de 9F, queda como **banco de prueba hasta 9H** (fixture técnico, no datos reales, **no viaja a OPS**).

Pendiente del Carril B: **9H** — la cuenta corriente interna de socios (saldos acumulados entre períodos, retiros, revaluación/conversión ARS→USD y la **compensación pagador↔incidido** que 9G dejó a la vista: Rodrigo↔Franco por el termotanque, Remo↔Rodrigo por las horas) — capa **posterior con estado**, encuadrada en `PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md`, **sin diseñar todavía**. Dos decisiones de negocio quedaron servidas para los socios: el **valor real del % operativo** (la cascada lo recibe por parámetro; 0,25 fue valor de trabajo, sin carácter normativo) y la **política de arranque** para lo percibido con pool vacío.

---

## Entornos

| Entorno | Proyecto Supabase | Estado |
|---|---|---|
| DEV | `vita-delta-dev` | Backend completo v1.7.3 + hardening + 8 workflows validados + permisos EXECUTE endurecidos (7E). IDs de cabaña 17-21. |
| TEST | `vita-delta-test` | Schema reconstruido desde canónico, paritario, validado y reseteado a estado limpio (7D). IDs de cabaña 1-5. **Además, TEST contiene el schema del Carril B (9C-9E):** catálogo enriquecido, zonas, activación operativa y funciones de matriz — aún no promovido a OPS ni reflejado en el canónico. |
| OPS | `vita-delta-ops` | **Operación real interna.** Levantado en 8A: schema paritario (P01-P10 10/10), seeds reales, seguridad cerrada (nació más cerrado que TEST), `pg_cron` activo, credencial n8n `vita_supabase_ops` verificada por identidad. IDs de cabaña 1-5. **Capa de carga 8B operativa** (primera reserva real, id 1, Tokio), **calendarios 8C activos** (operativo y limpieza en uso real), **bloqueos 8D activos** (formulario en uso) y **alerta 8C-bis activa** (aviso por mail al confirmar reserva próxima). |
| PROD | — | No creado. Etapa futura (público). |

**IDs de cabaña no portables entre entornos** (DEV 17-21; TEST y OPS 1-5 cada uno en su propia base). Cada workflow usa los IDs del ambiente al que apunta. En el form de carga de 8B la cabaña se elige por nombre, no por ID.

---

## Workflows legacy (Google Sheets)

Los workflows originales contra Google Sheets (`db_*`) y los archivos Apps Script se conservan como **referencia histórica congelada**. No son la ruta productiva actual, no se mantienen y no deben usarse como fuente de verdad. Google Sheets ya no es backend operativo; puede usarse para reportería de lectura.

Ubicación típica: `Workflows/n8n/*.template.json` (sin subcarpeta `supabase/`).

---

## Principios operativos

Decisiones que **no deben reabrirse** salvo contradicción crítica explícita:

1. Supabase / PostgreSQL es la fuente de verdad.
2. Google Sheets no es backend operativo.
3. n8n orquesta; PostgreSQL decide y persiste.
4. La IA no confirma reservas, pagos ni disponibilidad real por sí sola.
5. Toda reserva confirmada pasa por `confirmar_reserva()`.
6. Toda pre-reserva se crea por `crear_prereserva()`.
7. No hay `INSERT` directo a `reservas` desde workflows.
8. No usar `DROP ... CASCADE` ni `TRUNCATE ... CASCADE` sin decisión explícita.
9. Mantener `nv()` defensivo en workflows n8n como defensa en profundidad.
10. `fecha_in` inclusive, `fecha_out` exclusive; modelo daterange `[)`.
11. IDs de cabaña no portables entre entornos (DEV 17-21; TEST y OPS 1-5 cada uno en su base).
12. No limpiar fixtures de un entorno de prueba fuera de un bloque de reset dedicado con SQL aprobado (`D-7C-01`); la limpieza es snapshot → borrado atómico → verificación, con doble gate anti-error-de-entorno (`D-7D-01`, `D-7D-02`).

**Documento de referencia:** `Docs/Operacional/DECISIONES_NO_REABRIR.md`.

---

## Pendientes activos pre-PROD

Pendientes documentados al cierre de 7E:

- **Promoción coordinada del Carril B a OPS (incluye 9B / 3b)** — paquete único por DDL: objetos 9C/9D/9E/9F/9G + `public.abortar_si_falla(jsonb)` + el workflow de cobranza apuntando a OPS, con **bump único del canónico**, marcador `'ambiente'='ops'`, GRANTs/RLS a decidir y prueba con datos reales. **Los fixtures de laboratorio no viajan** (se recrea estructura, no se copian datos). `Pendiente_pre_produccion.md`, sección de promoción coordinada.
- **Residual amplio de permisos de tabla a roles Data API en DEV** — hallazgo de 7E (snapshot A5): `anon`/`authenticated`/`service_role` tienen SELECT/escritura completos sobre todas las tablas/vistas de DEV, más amplio que el `Dxtm` de TEST. Fuera de alcance de 7E por decisión (Opción 1). **Acotado a DEV:** OPS nació sin este problema (switch correcto desde el día cero, confirmado en 8A). A decidir solo para DEV: revocar para alinear con TEST/OPS o aceptar como definitivo. `Pendiente_pre_produccion.md` 1.7.
- **Contrato SQL de `registrar_pago` frente a entradas no-vacías mal tipadas** (hoy mitigado por `nv()` en n8n). `Pendiente_pre_produccion.md` 1.6.
- `tipo_valor` sin poblar en `configuracion_general` (1.4).
- Validaciones para tipos inválidos no vacíos (heredado de 6D).
- Cobertura empírica opcional de la rama `unique_violation` de idempotencia (6.3).
- RLS final para frontend público (pendiente histórico).
- Tarifas reales productivas y feriados productivos (pendientes históricos).

> **Cerrado en 7E:** el endurecimiento de permisos EXECUTE en DEV (REVOKE EXECUTE sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/`service_role`, paridad con TEST). Ver `Pendiente_pre_produccion.md` 1.5 y `7E_CIERRE.md`.

**Documento de referencia:** `Docs/Operacional/Pendiente_pre_produccion.md`.

---

## Próximas etapas — opciones disponibles

Con DEV, TEST, OPS, 6C, 6D, 7A-7E, **8A-8D cerradas y la Etapa 8 (operación real interna) completa**, la **sub-etapa 8C-bis** cerrada y activa en OPS, y la **Etapa 9 en marcha** (Carril A: diagnóstico 9A + listado de saldos + cobranza posterior 9B/3b validada en TEST; **Carril B: capa derivada completa, 9C-9G cerradas y verificadas en TEST**, cascada validada 40/40), el sistema está **operativo**: el equipo carga reservas, ve el estado en los calendarios y crea bloqueos (autoservicio sobre OPS), y recibe avisos automáticos por mail. Las opciones a priorizar de acá en más (orden sugerido, no comprometidas):

- **Etapa 9H — Carril B, capa acumulada:** saldos acumulados entre períodos, retiros, revaluación/conversión y compensación pagador↔incidido. Insumos listos: las 6 funciones de cascada, el banco de laboratorio (fixtures 9F+9G) y su breadcrumb. Conversación nueva.
- **Promoción coordinada del Carril B a OPS (incluye 9B/3b):** operación única por DDL — objetos 9C→9G + `abortar_si_falla(jsonb)` + workflow de cobranza — con bump único del canónico, marcador `'ambiente'='ops'`, GRANTs/RLS a decidir, verificación de socios reales y **sin datos de TEST** (los fixtures no viajan). Antes o después de 9H, a decisión.
- **Contabilidad — capa fiscal/legal (futuro lejano):** facturación AFIP/ARCA/IVA, separada por completo de la contabilidad interna del Carril B (el muro interno↔fiscal se mantiene). Fuera del MVP.
- **Registrar la primera ejecución real de 8C-bis** con la próxima reserva en ventana y verificar la entrega; luego, migrar el remitente SMTP al mail propio de las cabañas (sin rediseño).
- **Edición / baja de bloqueos:** hoy 8D solo crea; levantar o corregir un bloqueo es manual. Si se vuelve frecuente, sería una capa posterior con su propio formulario.
- **Carril C — Portal Operativo Interno (diseño conceptual, sin empezar):** hub único de operación con login por usuario y menú por rol (Franco/Rodrigo/Remo amplio; Vicky reservas; Jennifer limpieza) que agrupe los formularios n8n, los calendarios y los reportes hoy dispersos, con **permisos reales** (no solo de interfaz) y datos sensibles (DNI, mail, montos) ocultos por rol. Carril **independiente del Carril B**; no toca schema ni OPS. Brief de diseño en `Docs/Prompts/Prompt_Portal_Operativo_Interno.md`. A abrir en conversación propia, en paralelo, cuando convenga.
- **Carril D — Tech-Scout Bot / Radar Tecnológico (diseño conceptual, sin empezar):** radar que, conociendo el stack y el estado de cada proyecto, detecte novedades relevantes (releases de n8n/Supabase/Postgres, cambios de precio o reglas en pagos/Meta API, alertas de seguridad, modelos de IA más baratos) y las traduzca en decisiones posibles, con reglas **anti-FOMO** y el principio "el humano decide". Pensado reutilizable por perfiles de proyecto (Vita Delta y futuros). **No interrumpe el roadmap principal salvo seguridad crítica.** Brief de diseño en `Docs/Prompts/Prompt_Tech-Scout_Bot.md`. A abrir en conversación propia, en paralelo, cuando convenga.
- **Apertura al exterior (etapas futuras grandes, sobre TEST primero):** webhook MercadoPago real, bot conversacional (Claude API), web pública de reservas, WhatsApp/Instagram (Meta API), y eventualmente el entorno PROD público. Es el salto más ambicioso del proyecto.
- **Residual de permisos de tabla en DEV** (hallazgo A5 / pendiente 1.7): revocar el set amplio de SELECT/escritura a roles Data API para alinear con TEST, o aceptarlo y documentarlo como definitivo. No urgente; OPS ya nació sin ese problema.

No avanzar a PROD público, MercadoPago real, bot o frontend público sin decisión explícita.

---

## Qué no está implementado todavía

- Webhook real de MercadoPago.
- Integración real con WhatsApp / Instagram (Meta API).
- Bot conversacional conectado a canales reales.
- Web pública de reservas conectada al backend.
- Panel administrativo y dashboard operativo.
- Contabilidad automatizada completa. *Avance del **Carril B** en TEST: **capa derivada completa** — catálogo, activación, matriz, gasto rediseñado y **cascada de liquidación validada al centavo (9C-9G)**; faltan la cuenta corriente de socios con saldos acumulados, retiros y conversión de monedas (9H, encuadrada pero sin diseñar) y que los socios fijen el % operativo real. La cobranza posterior 9B/3b (Carril A) es el primer ladrillo que escribe pagos, validado en TEST. **Nada de esto está en OPS ni en el canónico todavía.*** La facturación fiscal (AFIP/ARCA/IVA) queda fuera del Carril B.
- RLS final para frontend público.
- Tarifas y feriados productivos completos.
- Entorno PROD (público). _(OPS, operación interna, ya está levantado en 8A.)_

**El sistema no está en producción pública.** OPS es operación real interna y **ya está tomando reservas reales** mediante la capa de carga interna de 8B (carga manual del equipo por formulario n8n). Falta la integración con consumidores externos automáticos (webhook MP, bot, web pública) y el entorno PROD público.

---

## Sobre `index.html` y prototipos

- **`index.html`** — presentación visual estática del estado del sistema, para explicar el proyecto a socios o colaboradores. No es una web pública de reservas ni está conectada al backend.
- **`Prototipos/prototipo_web_reservas.html`** — boceto visual de la futura web de reservas. No consulta disponibilidad real, no crea pre-reservas, no registra pagos y no está conectado a Supabase.

---

## Documentación viva

- `Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md` — estado vigente del proyecto.
- `Docs/Operacional/DECISIONES_NO_REABRIR.md` — decisiones cerradas no reabribles.
- `Docs/Operacional/Pendiente_pre_produccion.md` — pendientes para deploy a PROD.
- `Docs/Operacional/Lecciones_Aprendidas.md` — gotchas operativos.
- `Docs/Implementacion/6B_SCHEMA_SQL.md` — schema canónico SQL vigente (v1.7.3).
- `Docs/Implementacion/6B_PLAN_FASES.md` — plan de ejecución, conservado como referencia.
- `Docs/Arquitectura/` — documentos de arquitectura de Etapas 1-6B, `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md` (diseño del arranque OPS), `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md` (diseño de la capa de carga, v3.5), `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md` (diseño de los calendarios visuales, v1.3), `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md` (diseño de la capa de bloqueos, v1.1) y los conceptuales del **Carril B**: `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (base conceptual v0.8), `ARQUITECTURA_ETAPA_9C_CATALOGO_ZONAS_TITULARIDAD.md` (conceptual de 9C) y `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md` (diseño de la cobranza, Carril A).
- `Docs/Bitacora/` — cierres formales (`6C_CIERRE`, `6D_CIERRE`, `7A_CIERRE`, `7B_CIERRE`, `7C_CIERRE`, `7D_CIERRE`, `7E_CIERRE`, `8A_CIERRE`, `8B_CIERRE`, `8C_CIERRE`, `8D_CIERRE`, `8C-bis_CIERRE`, y de la Etapa 9: `9A_DIAGNOSTICO_INGRESOS`, `9B_CIERRE`, `9C_CIERRE`, `9D_CIERRE`, `9E_CIERRE`, `9F_CIERRE`; **la Etapa 9G vive en su propia subcarpeta `Docs/Bitacora/9G/`**, con `9G_CIERRE.md` y los cinco bloques SQL de la etapa: `9G_BLOQUE_A_DIAGNOSTICO.sql`, `9G_BLOQUE_B_SEED_v2.sql`, `9G_BLOQUE_C_FUNCIONES_v2.sql`, `9G_BLOQUE_D_VALIDACION.sql`, `9G_BLOQUE_E_NO_REGRESION.sql`) y bitácoras de ejecución (`6B_EJECUCION_DEV`, `6C_EJECUCION`, `8C_EJECUCION`, `8D_EJECUCION`, `HARDENING_PRE_PRODUCCION_EJECUCION`).
- `Docs/Operacional/PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md` — breadcrumb de alcance posterior del Carril B: cuenta corriente interna de socios (saldos acumulados, retiros/cobros, conversión ARS→USD). **Encuadrado, sin diseñar todavía**; capa con estado (append-only) que se retoma recién después de 9G. No toca el canónico ni los satélites.
- `Docs/Prompts/` — briefs de diseño conceptual de carriles **futuros e independientes**, a abrir cada uno en su propia conversación cuando se decida: `Prompt_Portal_Operativo_Interno.md` (**Carril C** — Portal Operativo Interno: hub de operación, roles y permisos) y `Prompt_Tech-Scout_Bot.md` (**Carril D** — Tech-Scout Bot / Radar Tecnológico). Son **disparadores de diseño, no etapas implementadas ni diseñadas**: no tocan el canónico, el schema ni OPS, y no se mezclan con el Carril B (9F/9G).
- `Workflows/n8n/supabase/*.template.json` — 8 templates sanitizados de los workflows contra Supabase.
- `Workflows/n8n/8B/` — workflows de la capa de carga: `vita_w8b_carga_reserva__TEST.json` (validado), `__OPS.json` (productivo), `__TEMPLATE.json` (sanitizado).
- `Workflows/n8n/8C/` — workflows de los calendarios visuales: `vita_w8c_html_operativo__TEST.json`, `vita_w8c_html_limpieza__TEST.json`, `vita_w8c_sheet_resguardo__TEST.json` (los tres validados en TEST, inactivos) y los templates sanitizados `vita_w8c_html_operativo__TEMPLATE.json` y `vita_w8c_sheet_resguardo__TEMPLATE.json`.
- `Workflows/n8n/8D/` — workflows de la capa de bloqueos: `vita_w8d_bloqueo__TEST.json` (validado), `__OPS.json` (activo en producción) y `__TEMPLATE.json` (sanitizado).
- `Workflows/n8n/8Cbis/` — workflows de la alerta por reserva próxima: `vita_w8cbis_alerta__TEST.json` (validado con envío real) y `vita_w8cbis_alerta__OPS.json` (activo en producción).
- `CLAUDE.md` — reglas de trabajo y orden de lectura para Claude.

---

## Principios de trabajo

Antes de agregar cualquier automatización o integración, verificar:

1. Si ya existe una fuente de verdad para ese dato (Supabase).
2. Si la lógica pertenece a una función SQL determinística o a la IA.
3. Si afecta disponibilidad, reservas, pagos o pricing.
4. Si necesita trazabilidad en `log_cambios` (`source_event`).
5. Si puede romper una validación ya cerrada.
6. Primero diseñar, después documentar, recién después implementar.

Si hay contradicción entre implementación y arquitectura, prevalecen los documentos de arquitectura cerrados. Nunca ejecutar workflows o SQL de prueba contra datos productivos.
