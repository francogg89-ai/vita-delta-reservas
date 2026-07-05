# Vita Delta Reservas

Sistema de automatización integral para el complejo de cabañas Vita Delta.

---

## Qué es este proyecto

Vita Delta Reservas es un sistema de gestión operativa para un complejo de 5 cabañas (Bamboo, Madre Selva, Arrebol, Guatemala, Tokio). Centraliza disponibilidad, reservas, pricing, pagos, operación interna y comunicación con huéspedes en una arquitectura automatizable, trazable y escalable.

El stack actual es **Supabase / PostgreSQL** como base de datos y fuente de verdad, **n8n** como orquestador de workflows, y **Claude API** como capa conversacional futura. El proyecto migró desde un stack inicial sobre Google Sheets; esa migración (Etapa 6B) está ejecutada y cerrada en el entorno DEV, y el sistema cuenta además con un entorno TEST levantado y validado, y un entorno **OPS de operación real interna** levantado, paritario, seguro y conectado a n8n (Etapa 8A). Sobre OPS ya funciona la **capa de carga interna de reservas** (Etapa 8B): un formulario n8n con el que el equipo carga reservas reales en una acción. El sistema **ya está tomando reservas reales** (primera reserva real cargada en el smoke de 8B). Sobre esa base se construyó la **capa de calendarios visuales** (Etapa 8C): tres vistas de solo lectura — calendario operativo del equipo, calendario de limpieza para Jennifer (sin montos) y un Sheet de resguardo — que presentan el estado del sistema sin tocar el motor, hoy activas y en uso real. Por último, la **capa de bloqueos operativos** (Etapa 8D) agrega un formulario n8n para que el equipo bloquee una cabaña (mantenimiento, uso propio, clima) en una acción. **Con 8D se cierra la Etapa 8 (operación real interna):** el equipo opera el complejo con tres acciones autoservicio sobre OPS — cargar reservas, ver el estado y crear bloqueos —, todo sobre Supabase como fuente de verdad. Sobre esa base se sumó la **sub-etapa 8C-bis** (alerta por reserva próxima): un aviso automático por mail al equipo y a Jennifer cuando se confirma una reserva con check-in dentro de los próximos 7 días, disparado en rama lateral desde el formulario de carga sin afectar la reserva si el envío falla.

En paralelo a la operación, la **contabilidad operativa interna (Carril B)** —separada de la fiscal/legal (AFIP/ARCA/IVA quedan fuera)— se **completó en TEST** a lo largo de seis sub-etapas: **9C** (catálogo de cabañas enriquecido, zonas y titularidad), **9D** (activación operativa por rango), **9E** (matriz dinámica de participación), **9F** (gasto interno rediseñado), **9G** (cascada de liquidación read-only, validada al centavo) y **9H** (cuenta corriente interna de socios: snapshots congelados, mayor de movimientos y revaluación ARS→USD), todas cerradas y verificadas en TEST y luego **promovidas a OPS** (2026-06-14, promoción coordinada por DDL sin copiar datos). El schema canónico quedó **bumpeado a v1.8.0** con esa promoción, y las dos decisiones de negocio del carril quedaron cerradas: **% operativo 25%** e **inicio oficial contable 2026-07-01** (los períodos anteriores quedan fuera de alcance contable operativo).

> La IA conversa. n8n orquesta. PostgreSQL decide y persiste. Los humanos auditan.

---

## Estado actual

**Al 2026-07-05:** el sistema opera sobre **OPS** (operación real interna) con **dos carriles promovidos**: el **Carril B** (contabilidad operativa interna entre socios) y el **Carril C — Portal Operativo Interno** (hub de operación con login único, gateway `portal-api`, 13 wrappers n8n y frontend). El **schema canónico está en v1.11.0** (Carril B = **PARTE C**; Carril C / Portal = **PARTE D** + §25; la capa de escritura del retiro suma `portal_usuarios.id_socio`, `portal_idempotencia_cc` y 2 funciones) y el **bootstrap kit vigente es `bootstrap_entorno_nuevo_v1.9.0/`**. OPS opera reservas reales (8B), calendarios visuales (8C), bloqueos (8D), avisos por mail (8C-bis) y ahora el **Portal Operativo Interno** (lecturas + escrituras por rol: reservas, cobranzas multi-porción, gastos internos, saldos a cobrar, históricos e ingresos), con **paridad estructural TEST↔OPS del portal certificada por fingerprint**. Los tres entornos **DEV/TEST/OPS** están alineados sobre el canónico (DEV reconstruido desde cero, cerrado como OPS). Sobre esa base se sumó el **frente Cuenta Corriente de socios**: dos lecturas read-only socio-only en el portal (**L1** saldo al día por socio, **L2** drill-down mensual) que componen el motor del Carril B, promovidas a OPS y consolidadas en el canónico **v1.10.0** (con `pct_operativo` movido a `configuracion_general` en v1.10.1). Como **lado escritura**, se sumó el **retiro desde saldo vivo** (backend/gateway: `registrar_retiro_desde_saldo_vivo` valida contra el saldo vivo y escribe append-only en `movimientos_socio`; wrapper `portal_registrar_retiro(jsonb)` + acción `cuenta_corriente.retirar` socio-only), promovido a OPS con verificación **read-only** (0 escrituras / 0 secuencias) y consolidado en el canónico **v1.11.0** (ver `CIERRE_RETIRO_SALDO_VIVO_OPS.md`). **Próxima etapa:** el **próximo frente backend contable** es el **snapshot mensual / foto congelada + L3 histórico** (la foto mes-a-mes de la cuenta corriente, que habilita la lectura L3; hoy diferida por D-CC-11). La **UI del retiro** en el portal (botón "Retirar saldo") queda **después**, como **frente frontend posterior** — el backend/gateway del retiro ya está en OPS, pero todavía no hay UI. **Mercado Pago** (pagos autónomos), la **web pública** de reservas y el **bot conversacional** quedan como **frentes grandes posteriores**, no como próxima etapa inmediata. El recorrido del Carril C (diseño → slices → frontend → promoción) está detallado en la sección «Próximas etapas» y en `Docs/Bitacora/PROMOCION_CARRIL_C_OPS_CIERRE.md`.

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
| 9B / 3b | Cobranza posterior multi-porción (Form Trigger transaccional) — *Carril A* | Cerrada **en TEST** (2026-06-07); **promovida a OPS** (2026-06-14) |
| 9C | Carril B — catálogo enriquecido, zonas y titularidad (seam `resolver_beneficiario`) | Cerrada **en TEST** (2026-06-10); **promovida a OPS** (2026-06-14) |
| 9D | Carril B — activación operativa por rango (`activaciones_operativas`, `[)` + EXCLUDE) | Cerrada **en TEST** (2026-06-10); **promovida a OPS** (2026-06-14) |
| 9E | Carril B — matriz dinámica de participación (read-only, deriva sin persistir) | Cerrada **en TEST** (2026-06-10); **promovida a OPS** (2026-06-14) |
| 9F | Carril B — gasto interno rediseñado (`gastos_internos`: la clase A/C/D/E define momento y alcance) | Cerrada **en TEST** (2026-06-10); **promovida a OPS** (2026-06-14) |
| 9G | Carril B — cascada de liquidación read-only (6 funciones, 11 pasos, validación 40/40) | Cerrada **en TEST** (2026-06-11); **promovida a OPS** (2026-06-14) — **cierra la capa derivada del Carril B** |
| 9H | Carril B — cuenta corriente interna / capa con estado (5 tablas append-only, 10 triggers de inmutabilidad, 9 funciones; snapshots congelados, mayor, revaluación ARS→USD) | Cerrada **en TEST** (2026-06-12); **promovida a OPS** (2026-06-14) — **cierra el Carril B completo** |
| Promoción Carril B → OPS | Promoción coordinada de todo el Carril B (9C-9H + helper 9B) a OPS por DDL + bump del canónico a **v1.8.0** | Cerrada (2026-06-14); paridad estructural TEST↔OPS por huella, smokes 18/18 read-only, workflow de cobranza activo en OPS |

**Schema canónico actual:** `6B_SCHEMA_SQL.md v1.11.0` — incorpora, además de la **capa de escritura de la cuenta corriente / retiro desde saldo vivo** (v1.11.0: `portal_usuarios.id_socio`, `portal_idempotencia_cc`, `registrar_retiro_desde_saldo_vivo` + `portal_registrar_retiro(jsonb)`, D5 extendido) y las **2 funciones de lectura de la cuenta corriente de socios** en la PARTE C (v1.10.0), el **Carril B** como capa real (sección 24 conceptual + **PARTE C** ejecutable) y el **Carril C / Portal Operativo Interno** (**PARTE D** ejecutable —`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno(jsonb)`— + **§25** conceptual), ambos **promovidos a OPS** (Carril B 2026-06-14; Carril C 2026-06-29). **TEST y OPS tienen ambos carriles vivos**, con **paridad estructural certificada por huella** (Carril B `TOTAL_CARRIL`, 31 objetos; portal `TOTAL_PORTAL`, 3 objetos — idénticas entre ambos entornos). El **bootstrap kit vigente es `bootstrap_entorno_nuevo_v1.9.0/`** (9 archivos, verify final estricto); el kit `bootstrap_entorno_nuevo_v1.8.1/` se **retiró del árbol** como limpieza del cierre del Carril C (evitar doble fuente ejecutable; queda en el historial de git). El núcleo previo sigue vigente: TEST se reconstruyó desde el canónico en 7B (paridad 10/10 vs DEV) y OPS en 8A (paridad P01-P10 10/10); 8B/8C/8D/8C-bis no tocaron el schema. La `gastos` legacy quedó **conservada/congelada** (D-9F-01); el Carril B opera sobre `gastos_internos`. Las funciones y objetos del Carril B (capa derivada 9C–9G + capa con estado 9H) y los 3 objetos del portal viven en TEST, OPS y el canónico, **cerrados al Data API** (sin grants ni RLS).

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
- **Estado:** validado en TEST con batería completa (incluido el caso de reversión) y luego **promovido a OPS** (2026-06-14) dentro del **paquete de promoción coordinada del Carril B** (9C-9H + helper 9B), por DDL sin copiar datos; el workflow de cobranza posterior quedó **activo en OPS**. Variantes: workflow + plantillas sanitizadas reutilizables.

### Contabilidad operativa interna — Carril B (Etapas 9C-9H)

La capa de **contabilidad operativa interna** entre socios, **separada de la fiscal/legal** (AFIP/ARCA/IVA quedan fuera) y distinta del Carril A (que fue diagnóstico 9A + cobranza 9B). Construye, paso a paso, los insumos y el cálculo del reparto del pool entre socios. Todo **validado en TEST y promovido a OPS** (2026-06-14, promoción coordinada por DDL sin copiar datos); el canónico quedó **bumpeado a v1.8.0**. La metodología fue la de siempre: diagnóstico read-only → diseño aprobado bloque por bloque → ejecución en TEST por Franco → verificación → cierre parcial documentado.

- **9C — Catálogo enriquecido, zonas y titularidad.** Se agregaron a `cabanas` el `valor_relativo` y el `id_socio_beneficiario` (FK a `socios`); se creó el catálogo plano `zonas` y la pertenencia muchos-a-muchos `cabana_zona` (seed `grandes`/`chicas`); y el **punto único de resolución de titularidad** como función `resolver_beneficiario(id_cabana, fecha)` — el *seam*: hoy devuelve el beneficiario estable, mañana habilita titularidad por rango sin tocar a sus consumidores. (Detección lateral: hubo que completar el placeholder `Socio 3` → `Remo` antes del seed.)
- **9D — Activación operativa por rango.** Tabla `activaciones_operativas` con rango `[)` (`fecha_hasta NULL` = abierta/indefinida) y un `EXCLUDE` que impide solapamientos por cabaña — primer rango/EXCLUDE del Carril B. Modelo presencia/ausencia: rango = "en el pool", hueco = "afuera"; desactivar es dejar un hueco, reactivar es un rango nuevo. Composición real cargada: Bamboo, Madre Selva, Arrebol y Tokio activas desde `2026-07-01`; **Guatemala desactivada jul-oct 2026 y activa desde `2026-11-01`** (fechas reales, también para OPS). La política mensual ("cubre el mes completo") se aplica al derivar, no en el schema.
- **9E — Matriz dinámica de participación (read-only).** Tres funciones que **derivan, sin persistir nada**: `matriz_participacion` (proporción de cada socio en el pool del mes), `repartir_por_matriz` (reparte un monto dado por la matriz, con el **centavo residual** al socio de mayor participación; en empate, a Rodrigo solo si está en él, si no al menor `id_socio`) y `detalle_participacion` (matriz a nivel cabaña, para auditoría). No leen `pagos`: el ingreso entra en la cascada (9G). Validadas con datos reales (p. ej. julio: pool 378, Remo 0.4709; noviembre: pool 456, empate Franco/Remo 0.3904).
- **9F — Gasto interno rediseñado.** Tabla `gastos_internos` (17 columnas, 18 constraints nombradas): la **clase A/C/D/E define a la vez el momento de la cascada y el alcance** (D ⇒ zona, E ⇒ cabaña, A/C ⇒ general), imposible de violar por constraint; `clase_sugerida` + override **derivado** con comentario obligatorio; `periodo` normalizado a día 1 ("cuándo se pagó" ≠ "a qué liquidación entra"); pagador `socio|caja` (las horas de socio entran como gasto E valorizado a mano). La `gastos` legacy quedó **congelada e intacta**. Fixture técnico de 5 gastos (ids 30–34) para validar la incidencia.
- **9G — Cascada de liquidación read-only.** Seis funciones `sql STABLE` que **derivan la liquidación mensual completa sin persistir nada**: `cascada_periodo` (los 11 pasos), `saldo_socios_periodo`, `incidencia_gasto` y tres reportes (overrides, 5%-vs-fiscal, gastos sin incidencia derivable). El **% operativo es parámetro explícito** (no se congeló: el valor real lo definen los socios); **criterio de caja percibida** (período = mes de `created_at`); `GREATEST(base,0)` solo en el paso 4 (debajo, matemática con signo); lo no derivable **se reporta sin restarse** (pool vacío / zona sin activas). Validación **40/40 en TEST** reproduciendo el ejemplo canónico al centavo; junio 2026 quedó como **anomalía de arranque real** ($1.345.000 percibidos con pool vacío, sin destinatarios), hoy **fuera de alcance contable operativo** por D-NEG-02 (inicio oficial del Carril B: 2026-07-01). El único write de la etapa fue un seed de 5 pagos de laboratorio que, junto al fixture de 9F, queda como **banco de prueba hasta la promoción coordinada** (fixture técnico, no datos reales, **no viaja a OPS**).
- **9H — Cuenta corriente interna de socios (capa con estado).** Cierra el Carril B. Cinco tablas **append-only** (`liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio`, `revaluaciones`) con **inmutabilidad por diez triggers** (BEFORE UPDATE/DELETE por fila + BEFORE TRUNCATE) y una **cadena de supersesión lineal**: la liquidación de un período se **congela** como foto (re-snapshot sin borrar; una raíz y una sola vigente por período). Nueve funciones: cuatro de lectura `STABLE` (saldo vivo, mayor, retribución, liquidación vigente) y cinco de escritura **solo-INSERT** con *advisory locks* (snapshot, retiro, movimiento manual, reversa, revaluación). El **saldo vivo es derivado** (`saldo_final + desembolsado + Σ movimientos`, nunca almacenado); el **paso 4 / retribución operativa no tiene beneficiario predefinido** (se congela y se muestra, el destino se registra después con un movimiento manual). La **revaluación ARS→USD** es un evento aparte que no re-contabiliza el saldo en pesos. Validación en **seis bloques verdes** (diagnóstico, estructura, funciones, smokes 20/20, carga y validación 38 OK), reproduciendo al centavo los períodos de 9G una vez congelados (julio/agosto/noviembre) y los saldos vivos finales (Franco $24.158,16 · Rodrigo $351.957,49 · Remo $213.284,35). La capa es inmutable: la limpieza es por **teardown DROP**, nunca DELETE. La carga de laboratorio (`seed_9h_d`) se conserva con el banco de 9F/9G y **no viaja a OPS**.

Con 9H el Carril B quedó completo en TEST y luego **promovido a OPS** (2026-06-14). Las dos decisiones de negocio que quedaban servidas se **cerraron**: **% operativo = 25%** (sobre los ingresos cobrados del período, después de restar gastos operativos/Carril B — D-NEG-01) e **inicio oficial contable = 2026-07-01** (los períodos anteriores quedan fuera de alcance contable operativo: no se liquidan, no se arrastran, no se recontabilizan — D-NEG-02, que cierra la cuestión del arranque de junio). Ambas son revisables por decisión de socios más adelante, pero no son pendientes para operar. La promoción se hizo por **un único DDL** sin copiar datos de TEST, con el **bump del canónico a v1.8.0**; el detalle y la evidencia están en `Docs/Bitacora/Promocion/PROMOCION_CARRIL_B_OPS_CIERRE.md`.

---

## Entornos

| Entorno | Proyecto Supabase | Estado |
|---|---|---|
| DEV | `VITA_DELTA_DEV` (ref `wsrdzjmvnzxidjlovlja`) | **Reconstruido desde cero desde el canónico v1.8.1** en un proyecto Supabase **nuevo**, **cerrado como OPS** (Data API ON, expose new tables OFF, RLS OFF). Marcador `ambiente='dev'`, IDs de cabaña **1-5**, **Carril B completo** (9C-9H + helper 9B) y hardening del motor (Bloque 23). **Paritario con TEST/OPS.** El DEV viejo (`vita-delta-dev`, v1.7.3 sin Carril B, IDs 17-21, residual A5 de permisos) quedó **congelado**. |
| TEST | `vita-delta-test` | Schema reconstruido desde canónico, paritario, validado y reseteado a estado limpio (7D). IDs de cabaña 1-5. **Además, TEST contiene el schema completo del Carril B (9C-9H):** catálogo enriquecido, zonas, activación operativa, gasto interno rediseñado, las funciones de matriz y cascada, y la cuenta corriente interna con estado — **promovido a OPS y reflejado en el canónico v1.8.0** (paridad estructural TEST↔OPS por huella `TOTAL_CARRIL`). |
| OPS | `vita-delta-ops` | **Operación real interna.** Levantado en 8A: schema paritario (P01-P10 10/10), seeds reales, seguridad cerrada (nació más cerrado que TEST), `pg_cron` activo, credencial n8n `vita_supabase_ops` verificada por identidad. IDs de cabaña 1-5. **Capa de carga 8B operativa** (primera reserva real, id 1, Tokio), **calendarios 8C activos** (operativo y limpieza en uso real), **bloqueos 8D activos** (formulario en uso) y **alerta 8C-bis activa** (aviso por mail al confirmar reserva próxima). **Carril B promovido (2026-06-14):** 9 tablas + 2 columnas en `cabanas` + 21 funciones + 10 triggers de inmutabilidad + 6 secuencias + marcador `'ambiente'='ops'`, todo cerrado al Data API; workflow de cobranza `vita_w09_cobranza_posterior` + listado de saldos activos. Las tablas con estado de 9H arrancan vacías (primera liquidación real en id 1). |
| PROD | — | No creado. Etapa futura (público). |

**Los tres entornos usan IDs de cabaña 1-5** (el DEV nuevo nace 1-5, igual que TEST y OPS, cada uno en su propia base). El **discriminador de entorno** ya no es el ID de cabaña sino el marcador `configuracion_general('ambiente')` (`dev`/`test`/`ops`). Cada workflow apunta a su ambiente; en el form de carga de 8B la cabaña se elige por nombre, no por ID.

---

## Workflows legacy (Google Sheets)

Los workflows originales contra Google Sheets (`db_*`) y los archivos Apps Script se conservan como **referencia histórica congelada**. No son la ruta productiva actual, no se mantienen y no deben usarse como fuente de verdad. Google Sheets ya no es backend operativo; puede usarse para reportería de lectura.

Ubicación típica: `Workflows/n8n/db_*__TEMPLATE.json` (directamente, sin subcarpeta `Supabase/`).

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
11. Los tres entornos (DEV/TEST/OPS) usan IDs de cabaña 1-5 cada uno en su propia base; el discriminador de entorno es el marcador `configuracion_general('ambiente')`, no el ID de cabaña.
12. No limpiar fixtures de un entorno de prueba fuera de un bloque de reset dedicado con SQL aprobado (`D-7C-01`); la limpieza es snapshot → borrado atómico → verificación, con doble gate anti-error-de-entorno (`D-7D-01`, `D-7D-02`).

**Documento de referencia:** `Docs/Operacional/DECISIONES_NO_REABRIR.md`.

---

## Pendientes activos pre-PROD

Pendientes activos pre-PROD / frentes abiertos vigentes al 2026-07-05:

**Frentes abiertos / pendientes vigentes (al 2026-07-05):**

- **Bootstrap kit rezagado (P-CC-4).** El kit vigente es `bootstrap_entorno_nuevo_v1.9.0/`, **rezagado respecto del canónico v1.11.0** (deuda acumulada: v1.10.0 lecturas CC + v1.10.1 `pct_operativo` + v1.11.0 SB0/SB1 del retiro). Se **regenera recién al cerrar el frente completo de cuenta corriente** (snapshot mensual/congelado + L3), no antes.
- **Snapshot mensual / foto congelada + L3 histórico.** Próximo frente backend contable: la foto mes-a-mes de la cuenta corriente que habilita la lectura L3 (hoy diferida por D-CC-11).
- **UI del retiro (frente frontend posterior).** El backend/gateway `cuenta_corriente.retirar` ya está en OPS; falta el botón/formulario "Retirar saldo" en el portal.
- **Reembolsos.** Pendiente de negocio/backend dentro del remanente de **P-CC-2** (registro/exposición de reembolsos, análogo al retiro), aún sin implementar.

**Pendientes históricos (de fondo, se conservan si siguen aplicando):**

- **✅ Promoción coordinada del Carril B a OPS — hecha (2026-06-14).** Paquete único por DDL (objetos 9C-9H + `public.abortar_si_falla(jsonb)` + workflow de cobranza a OPS), con **bump del canónico a v1.8.0**, marcador `'ambiente'='ops'`, **GRANTs/RLS cerrados sin exposición** y **paridad estructural TEST↔OPS por huella**. Los fixtures de laboratorio no viajaron (estructura recreada, datos no copiados). Cierre: `Docs/Bitacora/Promocion/PROMOCION_CARRIL_B_OPS_CIERRE.md`.
- **✅ Reconstrucción de DEV — hecha (2026-06-15).** DEV se rearmó de cero desde el canónico (Parte B + Parte C) en un proyecto Supabase **nuevo** (`VITA_DELTA_DEV`), **cerrado como OPS**, `ambiente='dev'`, IDs 1-5, **paritario con TEST/OPS**. El DEV viejo quedó congelado. Cierre: `Docs/Implementacion/Reconstruccion_DEV_v1.8.0/RECONSTRUCCION_DEV_v1.8.0_CIERRE.md`.
- **✅ Residual amplio de permisos de tabla a roles Data API en DEV (A5 / 1.7) — resuelto por construcción.** El hallazgo de 7E quedaba acotado al DEV viejo; el **DEV nuevo nació cerrado** (switch "expose new tables" OFF + REVOKE del motor, paridad con OPS/TEST), por lo que el residual ya no aplica. Persiste solo como histórico del DEV viejo congelado. `Pendiente_pre_produccion.md` 1.7.
- **Contrato SQL de `registrar_pago` frente a entradas no-vacías mal tipadas** (hoy mitigado por `nv()` en n8n). `Pendiente_pre_produccion.md` 1.6.
- `tipo_valor` sin poblar en `configuracion_general` (1.4).
- Validaciones para tipos inválidos no vacíos (heredado de 6D).
- Cobertura empírica opcional de la rama `unique_violation` de idempotencia (6.3).
- RLS final para frontend público (pendiente histórico).
- Tarifas reales productivas y feriados productivos (pendientes históricos).

> **Cerrado en 7E:** el endurecimiento de permisos EXECUTE en DEV (REVOKE EXECUTE sobre las 13 funciones del proyecto a `PUBLIC`/`anon`/`authenticated`/`service_role`, paridad con TEST). Ver `Pendiente_pre_produccion.md` 1.5 y `7E_CIERRE.md`.

> **Canonizado en v1.8.1 (2026-06-15):** ese mismo hardening del motor (REVOKE EXECUTE de las 13 funciones base) quedó incorporado a la **PARTE B** del canónico como **Bloque 23**; antes se aplicaba fuera de banda por entorno (7E/8A/7B-GRANTS). Un bootstrap fresco ahora nace cerrado sin paso manual. Los artefactos repetibles de ese bootstrap viven en `Docs/Implementacion/bootstrap_entorno_nuevo_v1.9.0/` (regenerado en el bump a v1.9.0; el kit `v1.8.1/` se retiró del árbol — ver Documentación viva).

**Documento de referencia:** `Docs/Operacional/Pendiente_pre_produccion.md`.

---

## Próximas etapas — opciones disponibles

Con DEV, TEST, OPS, 6C, 6D, 7A-7E, **8A-8D cerradas y la Etapa 8 (operación real interna) completa**, la **sub-etapa 8C-bis** cerrada y activa en OPS, y la **Etapa 9 en marcha** (Carril A: diagnóstico 9A + listado de saldos + cobranza posterior 9B/3b validada en TEST; **Carril B completo (9C-9H) promovido a OPS** (canónico v1.8.0; capa derivada con cascada validada 40/40 + capa con estado)), el sistema está **operativo**: el equipo carga reservas, ve el estado en los calendarios y crea bloqueos (autoservicio sobre OPS), y recibe avisos automáticos por mail. Las opciones a priorizar de acá en más (orden sugerido, no comprometidas):

- **✅ Promoción coordinada del Carril B a OPS — hecha (2026-06-14).** Operación única por DDL (objetos 9C-9H + `abortar_si_falla(jsonb)` + workflow de cobranza), con bump del canónico a v1.8.0, marcador `'ambiente'='ops'`, GRANTs/RLS cerrados sin exposición, paridad estructural TEST↔OPS por huella y **sin datos de TEST**. Lo que sigue del carril es **operarlo a partir de julio 2026** (carga real de gastos, snapshots y movimientos) y, si los socios lo deciden, revisar el % operativo (hoy 25%) o el inicio contable. Cierre: `Docs/Bitacora/Promocion/PROMOCION_CARRIL_B_OPS_CIERRE.md`.
- **Contabilidad — capa fiscal/legal (futuro lejano):** facturación AFIP/ARCA/IVA, separada por completo de la contabilidad interna del Carril B (el muro interno↔fiscal se mantiene). Fuera del MVP.
- **Registrar la primera ejecución real de 8C-bis** con la próxima reserva en ventana y verificar la entrega; luego, migrar el remitente SMTP al mail propio de las cabañas (sin rediseño).
- **Edición / baja de bloqueos:** hoy 8D solo crea; levantar o corregir un bloqueo es manual. Si se vuelve frecuente, sería una capa posterior con su propio formulario.
- **Carril C — Portal Operativo Interno (diseño de Backend/API + Slice 0 + Slice 1 + Slice 2 + Slice 3a + Slice 3b cerrados sobre TEST):** hub único con una sola autenticación (Supabase Auth), gateway server-side (Edge Function `portal-api`) que firma HMAC a n8n, y menú por rol (socio amplio; Vicky reservas + lecturas operativas; Jenny limpieza) con **permisos reales** y datos sensibles ocultos por rol. Cerrados: el **diseño de Backend/API** (catálogo de 25 acciones A01–A25, matriz rol×endpoint, modelo de identidad/seguridad, MVP por slices; D-C-01…28), el **Slice 0** (espina de seguridad: `portal_usuarios` + `portal-api` + revalidación HMAC en n8n; D-C-29…35) , el **Slice 1** (las 5 lecturas operativas A03/A04/A05/A06/A12 vía wrappers n8n firmados; D-C-36…49 / L-C-10…15) , el **Slice 2** (las 3 escrituras operativas A07 `reserva.crear_manual` / A08 `bloqueo.crear_manual` / A10 `cobranza.registrar_saldo` vía wrappers n8n firmados con **actor inyectado server-side** y reuse de los flujos del motor de 8B/8D/9B; A10 con escritura transaccional **advisory lock** + idempotencia por `idempotency_key`, D-C-50/51 / L-C-16/17) y el **Slice 3a** (las 2 lecturas nuevas A24 `historico.reservas` —buscador operativo de reservas— y A25 `ingresos.cobrados_periodo` —caja percibida: solo `sena`+`saldo`, suma sobre `pagos`, `periodo_hasta` híbrido con gateway que **preserva su ausencia**—, `SELECT` inline sin `injectActor`/`isWrite`; CATALOG de **11 acciones**; D-C-52…54 / L-C-18/19) y el **Slice 3b** (el **gasto interno**: A11 `cargar.gasto_interno` —**primera escritura no-idempotente** del portal, guard de **dos capas en UNA txn** dentro de `portal_cargar_gasto_interno`: anti-replay `UNIQUE(nonce)` con `nonce` derivado de la firma HMAC + idempotencia de negocio `UNIQUE(action,idempotency_key)` comparando `payload_norm`+`actor`— y A13 `gastos.listado` —lectura por **período contable**, `SELECT` inline, bordes truncados a primer día de mes, gateway que espeja la semántica mensual—, cada una por wrapper n8n directo **y** por gateway; infra de idempotencia `portal_idempotencia` + `portal_cargar_gasto_interno` **TEST-only fuera del canónico** (precedente `portal_usuarios`), `gastos_internos` sin DDL; CATALOG de **13 acciones**; **cumple P-C-9** en TEST; D-C-55…60 / L-C-20…23). **OPS y schema quedaron intactos durante toda la fase TEST** (canónico **v1.8.1** entonces; el Carril C fue **TEST-only** hasta la promoción coordinada a OPS del 2026-06-29, abajo). Carril **independiente del Carril B**. Cierres: `Docs/Bitacora/Carril_C/C_SLICE_1/C_SLICE1_CIERRE.md`, `Docs/Bitacora/Carril_C/C_SLICE_2/C_SLICE2_CIERRE.md`, `Docs/Bitacora/Carril_C/C_SLICE_3/C_SLICE3A_CIERRE.md` y `Docs/Bitacora/Carril_C/C_SLICE_3/C_SLICE3B_CIERRE.md`. Sobre eso se **aprobó el Contrato Frontend ↔ Portal v1** (2026-06-22): API reference del portal contra el gateway real (CATALOG 13), decisiones D-FE-01…08, en `Docs/Implementacion/Carril_C/Portal_Frontend/CONTRATO_FRONTEND_PORTAL_v1.md`; backend/n8n/OPS/canónico intactos (cierre `CONTRATO_FRONTEND_PORTAL_CIERRE.md`). Sobre eso arrancó el **Frontend TEST** (`apps/portal-operativo/`, React+Vite+TS+Tailwind): el **sub-slice 0 (shell)** —auth + `sesion.contexto` + menú por rol desde `acciones` + placeholder por acción + `no_autorizado`→re-login— quedó **validado en TEST** (2026-06-23) con evidencia visual de menú por rol, sin tocar backend/n8n/OPS/canónico (**D-FE-09/10/11 / L-FE-01**; cierre `FRONTEND_SUBSLICE0_CIERRE.md`). **sub-slice 1 (las 8 lecturas)** cerrado (2026-06-24; A03/A04/A05/A06/A12/A24/A25/A13 sobre el shell; router + `useAction` + `DataTable`/`Paginador`; parche de consistencia A04/A12 en n8n **D-C-61/62/63**; **D-FE-12…18 / L-FE-02**; `FRONTEND_SUBSLICE1_CIERRE.md`). Sobre eso cerró el **sub-slice 2 (las 4 escrituras)** (2026-06-25): A07/A08/A11 + **A10-MP `cobranza.registrar_cobro`** (cobranza multi-porción + recargo 5% + **bloqueo de sobrepago** UI+backend), **W10 `cobranza.registrar_saldo` deprecated-in-place** (oculto del frontend por tolerancia-forward); patrón `useEnviar` + idempotencia por intento + `estado_incierto`; **D-FE-19…28 / L-FE-03…07** (`FRONTEND_SUBSLICE2_CIERRE.md`). Sobre eso cerró el **sub-slice 3 (publicación TEST + piloto operativo)** (2026-06-26): portal **publicado en Vercel** (link TEST real, build estático + fallback SPA) con **banner de ambiente** "AMBIENTE DE PRUEBA · TEST" derivado de la URL (D-FE-29/30) y **piloto OK** con usuarios reales (7 gates en verde, cero blockers, sin fixes; L-FE-08/09); único pendiente nuevo **P-FE-09** (banner al ref OPS); sin tocar backend/n8n/OPS/canónico (`FRONTEND_SUBSLICE3_CIERRE.md`). **✅ Promoción coordinada del Carril C a OPS — hecha (2026-06-29):** el portal completo (gateway `portal-api`, 13 wrappers n8n, frontend) quedó promovido a OPS por DDL sin copiar datos de TEST, con paridad estructural del portal por fingerprint (`TOTAL_PORTAL` idéntica) + smokes read-only end-to-end por rol 14/14, el canónico bumpeado a **v1.9.0** (portal como PARTE D) y el bootstrap kit regenerado a v1.9.0. CORS por env var (P-C-7), HMAC propio de OPS (P-C-8) y banner OPS (P-FE-09) resueltos; W10 deprecated-in-place (no es deuda). Decisiones D-PROMO-C-01…14, lecciones L-PROMO-C-01…08; deuda D-C-64…70 saldada. Cierre: `Docs/Bitacora/PROMOCION_CARRIL_C_OPS_CIERRE.md`.
- **Carril D — Tech-Scout Bot / Radar Tecnológico (diseño conceptual, sin empezar):** radar que, conociendo el stack y el estado de cada proyecto, detecte novedades relevantes (releases de n8n/Supabase/Postgres, cambios de precio o reglas en pagos/Meta API, alertas de seguridad, modelos de IA más baratos) y las traduzca en decisiones posibles, con reglas **anti-FOMO** y el principio "el humano decide". Pensado reutilizable por perfiles de proyecto (Vita Delta y futuros). **No interrumpe el roadmap principal salvo seguridad crítica.** Brief de diseño en `Docs/Prompts/Prompt_Tech-Scout_Bot.md`. A abrir en conversación propia, en paralelo, cuando convenga.
- **Apertura al exterior (etapas futuras grandes, sobre TEST primero):** webhook MercadoPago real, bot conversacional (Claude API), web pública de reservas, WhatsApp/Instagram (Meta API), y eventualmente el entorno PROD público. Es el salto más ambicioso del proyecto.
- **✅ Residual de permisos de tabla en DEV (A5 / 1.7) — resuelto por construcción.** Al reconstruir DEV en un proyecto nuevo cerrado (expose OFF + REVOKE del motor), el residual dejó de aplicar; persiste solo como histórico del DEV viejo congelado.

No avanzar a PROD público, MercadoPago real, bot o frontend público sin decisión explícita.

---

## Qué no está implementado todavía

- Webhook real de MercadoPago.
- Integración real con WhatsApp / Instagram (Meta API).
- Bot conversacional conectado a canales reales.
- Web pública de reservas conectada al backend.
- Panel administrativo y dashboard operativo.
- **Contabilidad — estado al 2026-07-05.** Ya promovido a OPS: el **Carril B completo (9C-9H)** (catálogo, activación, matriz, gasto rediseñado, **cascada de liquidación validada al centavo (9G)** y **cuenta corriente interna con snapshots congelados, mayor de movimientos y conversión ARS→USD (9H)**; reglas cerradas **% operativo = 25%** e **inicio contable = 2026-07-01**, D-NEG-01/02); las **lecturas L1/L2** de la cuenta corriente (saldo al día + drill-down mensual, canónico v1.10.0/v1.10.1); y el **retiro desde saldo vivo backend/gateway** (acción `cuenta_corriente.retirar`, canónico v1.11.0). **Pendiente backend inmediato:** el **snapshot mensual / foto congelada + L3 histórico**. **Pendiente frontend:** la **UI del retiro** (botón "Retirar saldo"). **Pendiente de negocio/backend:** los **reembolsos** (remanente de P-CC-2). La estructura contable vive en OPS (tablas arrancando vacías); la **carga operativa real** corre desde julio 2026. La facturación **fiscal/legal (AFIP/ARCA/IVA)** sigue **fuera** del Carril B (muro interno↔fiscal).
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
- `Docs/Implementacion/6B_SCHEMA_SQL.md` — schema canónico SQL vigente (**v1.11.0**: v1.8.0 incorporó el Carril B, v1.8.1 el hardening del motor (Bloque 23), v1.9.0 el Carril C / Portal Operativo Interno como PARTE D, v1.10.0 las 2 lecturas de la cuenta corriente, v1.10.1 el `pct_operativo` a `configuracion_general`, y **v1.11.0 la capa de escritura del retiro desde saldo vivo** —`portal_usuarios.id_socio`, `portal_idempotencia_cc`, `registrar_retiro_desde_saldo_vivo` + `portal_registrar_retiro(jsonb)`, D5 extendido— + §25; ver `Docs/Bitacora/CIERRE_RETIRO_SALDO_VIVO_OPS.md` y `PROMOCION_CARRIL_C_OPS_CIERRE.md`).
- `Docs/Implementacion/Reconstruccion_DEV_v1.8.0/RECONSTRUCCION_DEV_v1.8.0_CIERRE.md` — cierre de la reconstrucción de DEV desde cero (proyecto nuevo cerrado como OPS; tres entornos alineados; decisiones D-RDEV-01…06, lecciones L-RDEV-01…04).
- `Docs/Implementacion/bootstrap_entorno_nuevo_v1.9.0/` — juego **repetible** (9 archivos) para levantar un entorno de cero desde el canónico **v1.9.0**: `00_PRECHECK` → `01_BOOTSTRAP_PARTE_B_BASE` → `01_VERIFY` → `02_BOOTSTRAP_PARTE_C_CARRIL_B` → `02_VERIFY_PARTE_C_CARRIL_B` → `03_BOOTSTRAP_PARTE_D_PORTAL` → `03_VERIFY_FINAL_ENTORNO`, con `README_EJECUCION_BOOTSTRAP.md`. Extracción **literal** del canónico, **fijada a v1.9.0** (regenerar en cada bump para no divergir de la paridad); el verify final es **estricto** (FKs por tabla/columna incl. ON DELETE CASCADE/RESTRICT, CHECK/UNIQUE por relación, firma de función, hardening por ACL real vía `aclexplode`, RLS off + 0 policies). Validado de punta a punta contra un PostgreSQL limpio (aún **no ejecutado sobre un Supabase real**). **El kit anterior `bootstrap_entorno_nuevo_v1.8.1/` se retiró del árbol** (decisión de limpieza del cierre del Carril C, para evitar doble fuente ejecutable; queda en el historial de git). Solo sobre base vacía; no correr sobre un entorno poblado (el precheck lo gatea).
- `Docs/Implementacion/6B_PLAN_FASES.md` — plan de ejecución, conservado como referencia.
- `Docs/Arquitectura/` — documentos de arquitectura de Etapas 1-6B, `ARQUITECTURA_ETAPA_8_ARRANQUE_OPS.md` (diseño del arranque OPS), `ARQUITECTURA_ETAPA_8B_CAPA_CARGA.md` (diseño de la capa de carga, v3.5), `ARQUITECTURA_ETAPA_8C_CALENDARIOS_VISUALES.md` (diseño de los calendarios visuales, v1.3), `ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md` (diseño de la capa de bloqueos, v1.1) y los conceptuales del **Carril B**: `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (base conceptual v0.8), `ARQUITECTURA_ETAPA_9C_CATALOGO_ZONAS_TITULARIDAD.md` (conceptual de 9C) y `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md` (diseño de la cobranza, Carril A).
- `Docs/Bitacora/` — cierres formales (`6C_CIERRE`, `6D_CIERRE`, `7A_CIERRE`, `7B_CIERRE`, `7C_CIERRE`, `7D_CIERRE`, `7E_CIERRE`, `8A_CIERRE`, `8B_CIERRE`, `8C_CIERRE`, `8D_CIERRE`, `8C-bis_CIERRE`, y de la Etapa 9: `9A_DIAGNOSTICO_INGRESOS`, `9B_CIERRE`, `9C_CIERRE`, `9D_CIERRE`, `9E_CIERRE`, `9F_CIERRE`; **la Etapa 9G vive en su propia subcarpeta `Docs/Bitacora/9G/`**, con `9G_CIERRE.md` y los cinco bloques SQL de la etapa: `9G_BLOQUE_A_DIAGNOSTICO.sql`, `9G_BLOQUE_B_SEED_v2.sql`, `9G_BLOQUE_C_FUNCIONES_v2.sql`, `9G_BLOQUE_D_VALIDACION.sql`, `9G_BLOQUE_E_NO_REGRESION.sql`; **la Etapa 9H vive en su propia subcarpeta `Docs/Bitacora/9H/`**, con `9H_CIERRE.md` y los bloques SQL de la etapa con sus verificaciones: `9H_BLOQUE_C_FUNCIONES_v3.sql`, `9H_BLOQUE_C_VERIFICACION_v2.sql`, `9H_BLOQUE_C3_SMOKES.sql`, `9H_BLOQUE_C3_POSTCHECK.sql`, `9H_BLOQUE_D_CARGA.sql`, `9H_BLOQUE_E_VALIDACION.sql`; **la promoción del Carril B vive en su propia subcarpeta `Docs/Bitacora/Promocion/`**, con `PROMOCION_CARRIL_B_OPS_CIERRE.md` y los bloques SQL de la promoción `PROMO_BLOQUE_*.sql`) y bitácoras de ejecución (`6B_EJECUCION_DEV`, `6C_EJECUCION`, `8C_EJECUCION`, `8D_EJECUCION`, `HARDENING_PRE_PRODUCCION_EJECUCION`).
- `Docs/Arquitectura/PENDIENTE_CARRIL_B_9H_SALDOS_RETIROS_REVALUACION.md` — breadcrumb que encuadró la cuenta corriente interna de socios (saldos acumulados, retiros/cobros, conversión ARS→USD). **Ya implementado y cerrado en 9H** (2026-06-12, ver `Docs/Bitacora/9H/`); se conserva como referencia histórica del alcance. No toca el canónico ni los satélites.
- `Docs/Prompts/` — briefs de diseño conceptual de carriles **futuros e independientes**, a abrir cada uno en su propia conversación cuando se decida: `Prompt_Portal_Operativo_Interno.md` (**Carril C** — Portal Operativo Interno: hub de operación, roles y permisos) y `Prompt_Tech-Scout_Bot.md` (**Carril D** — Tech-Scout Bot / Radar Tecnológico). Son **disparadores de diseño, no etapas implementadas ni diseñadas**: no tocan el canónico, el schema ni OPS, y no se mezclan con el Carril B (9C-9H).
- `Workflows/n8n/Supabase/` — **plantillas sanitizadas (`__TEMPLATE.json`)** de todos los workflows contra Supabase: los del motor (`vita_w00`–`vita_w07`), la cobranza posterior (`vita_w09_cobranza_posterior`, `vita_w09_listado_saldos`), la capa de carga (`vita_w8b_carga_reserva`), los calendarios (`vita_w8c_html_operativo`, `vita_w8c_html_limpieza`, `vita_w8c_sheet_resguardo`), la alerta (`vita_w8cbis_alerta`) y los bloqueos (`vita_w8d_bloqueo`), más un `README`. **Solo se commitean las versiones sanitizadas**; los `__TEST`/`__OPS` (con credenciales reales) se mantienen fuera del repo.
- `Workflows/n8n/db_*__TEMPLATE.json` — los 7 workflows **legacy** contra Google Sheets (`db_*`), congelados como referencia histórica.
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
