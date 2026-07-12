# B0 — Motor de Precios v2 · Diseño conceptual, decisiones de negocio y arquitectura

**Proyecto:** Vita Delta Reservas  
**Frente:** Motor de Precios v2 operativo / Web / WhatsApp / Portal  
**Estado:** B0 cerrado conceptualmente  
**Destino:** Documento base de decisiones para auditoría, desarrollo y continuidad técnica  
**Entorno de trabajo:** TEST-first; OPS fuera de alcance hasta promoción coordinada  

---

## 1. Propósito del B0

Este documento consolida el diseño conceptual del **Motor de Precios v2** para Vita Delta.

El objetivo del B0 es dejar cerradas las decisiones de negocio, arquitectura funcional y reglas operativas antes de construir estructura, funciones, gateway, portal o integración pública.

Este documento no es una migración SQL, no es un patcher y no es un artefacto ejecutable. Es la base conceptual que gobierna los bloques posteriores:

```text
B1    = diagnóstico read-only del repo / DB
B1.1  = probes, riesgos live y cierre pre-DDL
B2A   = estructura + hardening + seeds mínimos
B2B   = seeds de pricing: temporadas + grillas
B3    = funciones del motor
B3.1  = override manual de capacidad
B4    = wrappers / gateway / Edge pública
B5    = portal operativo
B6    = smokes integrales
B7    = canónico / cierre
```

---

## 2. Principio rector

El Motor de Precios v2 abandona la lógica anterior de paquetes estándar por semana, 14 noches, 21 noches, mes o pack 6 noches.

El nuevo motor estándar cotiza **noche por noche**, usando ordinal acumulado por tipo de noche dentro de una misma estadía.

Hay dos contadores independientes:

```text
contador_semana
contador_alta_demanda
```

No se trata de consecutividad estricta calendario. Se trata de ordinal acumulado por tipo dentro de la estadía.

Ejemplo lunes → lunes:

```text
lunes noche      = semana_noche_1
martes noche     = semana_noche_2
miércoles noche  = semana_noche_3
jueves noche     = semana_noche_4
viernes noche    = alta_demanda_noche_1
sábado noche     = alta_demanda_noche_2
domingo noche    = semana_noche_5plus
```

---

## 3. Convención de fechas

La convención formal del motor es:

```text
fecha_in  = inclusive
fecha_out = exclusive
```

Una estadía cotiza las noches desde `fecha_in` hasta el día anterior a `fecha_out`.

La fecha de una noche es la fecha de inicio de esa noche.

Ejemplo:

```text
fecha_in  = 2026-12-24
fecha_out = 2026-12-27
```

Noches cotizadas:

```text
2026-12-24
2026-12-25
2026-12-26
```

---

## 4. Perfiles tarifarios

El motor cotiza por **perfil tarifario**, no por cabaña individual.

Perfiles iniciales:

```text
grande
chica
```

Asignación inicial esperada:

```text
Bamboo       → grande
Madre Selva  → grande
Arrebol      → grande
Guatemala    → chica
Tokio        → chica
```

El diseño debe soportar perfiles futuros, por ejemplo:

```text
nautica
premium
superior
```

Decisión conceptual:

> `perfil_tarifario` puede coincidir inicialmente con `cabanas.tipo`, pero no debe quedar atado para siempre a tipo físico, zona o nombre comercial.

El motor debe leer:

```text
cabanas.perfil_tarifario
```

y no depender directamente de:

```text
cabanas.tipo
```

---

## 5. Recorte: precios sí, alta de cabañas no

Este frente no incluye alta completa, activación ni desactivación de cabañas nuevas.

Crear o activar cabañas nuevas es un frente posterior porque toca:

- disponibilidad operativa;
- calendario;
- limpieza;
- activación/desactivación;
- socio beneficiario;
- pool societario;
- Carril B / contabilidad;
- zonas;
- valor relativo;
- reglas operativas.

Decisión conceptual:

> El motor de precios queda desacoplado del alta operativa de cabañas. Este frente crea la estructura `perfil_tarifario` y permite editar grillas por `perfil + temporada`. El alta/activación/desactivación de cabañas y su integración al pool societario queda fuera de este bloque y será un frente posterior.

Lo que sí debe quedar preparado en este frente:

- tabla `perfiles_tarifarios`;
- `cabanas.perfil_tarifario`;
- grilla por `perfil_tarifario + temporada`;
- edición de precios por `perfil_tarifario + temporada`;
- listado de perfiles existentes aunque no tengan grilla completa;
- error controlado si se intenta cotizar un perfil sin precios completos.

Si en el futuro existe el perfil `nautica`, debe poder aparecer en la pantalla de precios.

Si el perfil no tiene grilla completa, la UI puede mostrar campos vacíos o cero para carga, pero el motor no debe cotizar en cero por accidente.

Error esperado:

```text
tarifa_incompleta
```

---

## 6. Temporadas

Temporadas iniciales:

```text
alta = 15/11 → 15/03 exclusive
baja = 15/03 → 15/11 exclusive
```

Mirada humana:

```text
alta = 15 de noviembre al 14 de marzo inclusive
baja = 15 de marzo al 14 de noviembre inclusive
```

La temporada alta cruza año calendario, por lo que se deben materializar rangos anuales con `fecha_out_excl`.

Ejemplo:

```text
alta 2026/2027 = 2026-11-15 → 2027-03-15
baja 2027      = 2027-03-15 → 2027-11-15
```

Decisión conceptual:

- crear `temporada_vigencia` standalone;
- no depender del modelo legacy de multiplicadores;
- la tabla legacy `temporadas` queda intacta para metadata/usos viejos;
- el motor v2 resuelve temporada contra `temporada_vigencia`.

Cruce de temporada:

- el ordinal no se reinicia al cruzar temporada;
- cada noche toma el precio de su propia temporada.

Ejemplo:

```text
noche 1 en alta = semana_noche_1 con precio alta
noche 2 en baja = semana_noche_2 con precio baja
```

---

## 7. Tipos de noche

Una noche es `alta_demanda` si:

- es viernes;
- es sábado;
- fue marcada manualmente como noche de alta demanda desde portal.

Una noche es `semana` si no es alta demanda.

Las noches de alta demanda manual reemplazan el concepto operativo de “feriado común” dentro del motor de precios.

En UI conviene llamarlas:

```text
Noches de alta demanda
```

No necesariamente “feriados”.

Debe quedar puerta abierta para una futura importación automática o semiautomática desde fuentes oficiales, usando origen:

```text
manual | importado | sugerido
```

---

## 8. Conceptos de tarifa

Por cada combinación:

```text
perfil_tarifario + temporada
```

deben existir 8 conceptos:

```text
semana_noche_1
semana_noche_2
semana_noche_3
semana_noche_4
semana_noche_5plus
alta_demanda_noche_1
alta_demanda_noche_2
alta_demanda_noche_3plus
```

No usar más como conceptos estándar:

```text
pack_6_noches
semana_7_noches
semana_14_noches
semana_21_noches
mes_28_noches
```

El extra por persona no va en la grilla. Es global/configurable.

---

## 9. Precios iniciales confirmados

Estos precios corresponden a B2B, no a B2A.

### 9.1 Grande — alta

| Concepto | Precio ARS |
|---|---:|
| `semana_noche_1` | 165000 |
| `semana_noche_2` | 130000 |
| `semana_noche_3` | 105000 |
| `semana_noche_4` | 105000 |
| `semana_noche_5plus` | 105000 |
| `alta_demanda_noche_1` | 255000 |
| `alta_demanda_noche_2` | 130000 |
| `alta_demanda_noche_3plus` | 190000 |

### 9.2 Grande — baja

| Concepto | Precio ARS |
|---|---:|
| `semana_noche_1` | 130000 |
| `semana_noche_2` | 100000 |
| `semana_noche_3` | 80000 |
| `semana_noche_4` | 80000 |
| `semana_noche_5plus` | 80000 |
| `alta_demanda_noche_1` | 180000 |
| `alta_demanda_noche_2` | 120000 |
| `alta_demanda_noche_3plus` | 150000 |

### 9.3 Chica — alta

| Concepto | Precio ARS |
|---|---:|
| `semana_noche_1` | 140000 |
| `semana_noche_2` | 110000 |
| `semana_noche_3` | 90000 |
| `semana_noche_4` | 90000 |
| `semana_noche_5plus` | 90000 |
| `alta_demanda_noche_1` | 220000 |
| `alta_demanda_noche_2` | 115000 |
| `alta_demanda_noche_3plus` | 165000 |

### 9.4 Chica — baja

| Concepto | Precio ARS |
|---|---:|
| `semana_noche_1` | 110000 |
| `semana_noche_2` | 90000 |
| `semana_noche_3` | 70000 |
| `semana_noche_4` | 70000 |
| `semana_noche_5plus` | 70000 |
| `alta_demanda_noche_1` | 150000 |
| `alta_demanda_noche_2` | 100000 |
| `alta_demanda_noche_3plus` | 125000 |

---

## 10. Extra por persona

Regla confirmada:

- grandes incluyen 4 personas;
- chicas incluyen 3 personas;
- se permite 1 persona extra automática;
- valor global: $20.000 por noche por persona extra;
- debe existir switch para activar/desactivar el cargo;
- si está desactivado, el motor no suma extra y web/bot no muestran recargo;
- si está activado, web/bot deben advertir el recargo.

Advertencias esperadas:

```text
grande: recargo desde 5 personas
chica: recargo desde 4 personas
```

La regla vive en configuración/perfil, no en la grilla de precios.

---

## 11. Override manual de capacidad

### 11.1 Canales automáticos

Web, WhatsApp y bot no pueden superar `capacidad_max` automáticamente.

Si:

```text
personas > capacidad_max
```

entonces:

```text
reservable_online = false
motivo_no_reservable = excede_capacidad
```

El bot debe derivar a humano.

### 11.2 Portal operativo

El portal operativo sí puede superar `capacidad_max`, porque lo maneja el equipo y puede haber excepciones negociadas con el cliente.

Condiciones:

- solo modo manual;
- roles habilitados: `vicky` / `socio`;
- confirmación explícita;
- motivo obligatorio;
- warning `capacidad_max_override`;
- auditoría/traza;
- no modifica `cabanas.capacidad_max`;
- no pisa disponibilidad, bloqueos, reservas ni pre-reservas.

Decisión estructural:

```text
reservas.capacidad_override BOOLEAN DEFAULT FALSE
```

Trazar también en:

- `reservas.precio_snapshot`;
- nota operativa;
- `source_event`;
- `precios_auditoria`.

El parche real a `crear_prereserva`, gateway A07, wrapper y UI queda en micro-bloque posterior.

---

## 12. Redondeo, seña, saldo y recargo por medio de pago

Redondeo:

- al múltiplo de $1.000;
- por línea de noche/evento luego de overrides;
- el desglose debe sumar exactamente `precio_total`.

Seña:

```text
50% default
```

Saldo:

```text
50% default
```

Recargo operativo:

- saldo en efectivo: sin recargo;
- saldo por transferencia bancaria o Mercado Pago: 5% extra sobre saldo;
- no contamina el precio base de alojamiento;
- debe aparecer como cargo/advertencia separado.

---

## 13. Reglas de venta

El motor separa:

```text
precio
reglas de venta
```

### 13.1 Web / WhatsApp / bot

Deben respetar:

- disponibilidad real;
- eventos especiales;
- viernes+sábado obligatorio en alta si el switch está activo;
- derivación a humano por estadías largas;
- no permitir paquetes parciales de evento especial;
- capacidad máxima automática.

### 13.2 Portal manual

Puede pisar:

- precio calculado;
- reglas de venta;
- mínimo de noches;
- evento especial;
- temporada;
- restricciones comerciales online/bot;
- capacidad máxima, con override explícito.

No puede pisar:

- disponibilidad real;
- reserva confirmada;
- pre-reserva vigente;
- bloqueo activo.

---

## 14. Viernes + sábado obligatorio en temporada alta

Regla para canales automáticos:

- en temporada alta, viernes y sábado son bloque obligatorio;
- no se vende solo viernes;
- no se vende solo sábado;
- noches extra de alta demanda pegadas al finde pueden venderse sueltas;
- temporada baja permite viernes o sábado sueltos;
- portal manual puede saltear esta regla;
- evento especial puede imponer paquete exacto distinto.

Debe existir switch editable por socio:

```text
precio_bloque_finde_alta_activo
```

Ejemplo jueves alta demanda + viernes + sábado:

```text
jueves solo       = OK
viernes+sábado    = OK
viernes solo      = NO
sábado solo       = NO
```

Ejemplo viernes + sábado + domingo alta demanda:

```text
viernes+sábado          = OK
domingo solo            = OK
viernes+sábado+domingo  = OK
```

---

## 15. Estadías largas

El motor puede calcular internamente cualquier cantidad de noches.

Pero para web/bot:

```text
noches >= 10 → reservable_online=false
motivo_no_reservable = estadia_larga_derivar
```

Configurable:

```text
precio_estadia_larga_umbral_noches = 10
```

---

## 16. Eventos especiales

Los eventos especiales son paquetes indivisibles, pero pueden formar parte de una estadía más larga.

Regla:

- si una reserva intersecta un evento, debe incluir el paquete completo;
- no se permite reservar solo subrango del evento;
- sí se puede reservar más días antes o después del paquete;
- las noches externas se cotizan con motor estándar.

Ejemplo Navidad:

```text
paquete 24 → 26 = $300.000
```

Consulta:

```text
24 → 26 = válida, precio paquete
24 → 27 = paquete + noche 26→27 estándar
24 → 28 = paquete + 26→27 estándar + 27→28 estándar
25 → 26 = inválida online/bot, evento_parcial_no_vendible
23 → 26 = noche 23→24 estándar + paquete 24→26
```

Ordinal alrededor del evento:

- las noches de evento no cuentan en ningún contador estándar;
- el evento no reinicia el ordinal estándar;
- las noches estándar posteriores continúan el ordinal acumulado previo.

Ejemplo evento jueves/viernes/sábado, con 3 noches antes y 3 después:

```text
lunes      = semana_noche_1
martes     = semana_noche_2
miércoles  = semana_noche_3
jueves/viernes/sábado = evento, no cuenta ordinal
domingo    = semana_noche_4
lunes      = semana_noche_5plus
martes     = semana_noche_5plus
```

---

## 17. Noches de alta demanda desde portal

Debe existir gestión futura para:

- listar;
- crear una noche o rango;
- desactivar/reactivar;
- origen `manual | importado | sugerido`;
- dejar puerta abierta a importación automática.

Ejemplo:

```text
15/05 → 16/05 crea noche alta demanda 2026-05-15
```

---

## 18. Overrides y ajustes de precio

### 18.1 Ajuste porcentual masivo

Debe permitir:

- subir todos los precios 10%;
- bajar todos los precios 5%;
- filtrar por temporada;
- filtrar por perfil;
- filtrar por conceptos;
- redondear a $1.000;
- aplicar desde ahora;
- versionar;
- no tocar reservas/pre-reservas ya creadas.

### 18.2 Ajuste porcentual por rango

Ejemplo vacaciones de invierno:

- rango de fechas;
- perfil todos/grande/chica/futuro;
- tipo de noche semana/alta_demanda/todas;
- porcentaje positivo o negativo;
- no crea evento especial;
- reglas de venta normales.

### 18.3 Precio manual por rango/noche

Permite cambiar precios puntuales sin convertirlos en evento especial.

Diferencias:

```text
override por rango = cambia precio, mantiene reglas normales
evento especial    = paquete indivisible
reserva manual     = precio libre para una reserva concreta
```

---

## 19. Cotizaciones

Diseñar para web y WhatsApp con pago automático.

Decisiones:

- web/WhatsApp usan cotización congelada con TTL;
- TTL default: 30 minutos;
- portal interno puede recalcular;
- creación final siempre revalida disponibilidad con locks;
- cotización pública no toma locks de disponibilidad;
- cotización pública no crea pre-reserva;
- cotización pública no modifica disponibilidad/reservas/bloqueos/pagos;
- sí puede escribir en `cotizaciones_precio`.

Redacción formal:

> La superficie pública no tiene escrituras operativas ni locks de disponibilidad; solo puede persistir cotizaciones congeladas.

Trazabilidad:

- `cotizaciones_precio`;
- `pre_reservas.cotizacion_id`;
- `reservas.cotizacion_id` si no hay vínculo estable reserva→pre-reserva.

---

## 20. Disponibilidad

El motor de precios no inventa disponibilidad.

Decisiones:

- `obtener_disponibilidad_rango` es fuente read-only para cotización;
- no usa `FOR UPDATE`;
- no toma advisory locks;
- `validar_disponibilidad` pertenece al path de escritura;
- locks fuertes quedan al crear pre-reserva/reserva/bloqueo.

La cotización puede quedar desactualizada. La creación final no.

---

## 21. Output esperado de `precios.cotizar`

Debe devolver al menos:

```text
ok
disponible
reservable_online
motivo_no_reservable
id_cabana
perfil_tarifario
fecha_in
fecha_out
noches_count
precio_total
monto_sena
monto_saldo
extra_persona_total
cargo_saldo_transferencia_mp
precio_source
desglose_noches
desglose_eventos
restricciones
warnings
cotizacion_id
expires_at
```

Montos como string cuando pasen por gateway/portal.

---

## 22. Errores y warnings estandarizados

```text
excede_capacidad
capacidad_max_override
tarifa_incompleta
evento_parcial_no_vendible
bloque_finde_obligatorio
estadia_larga_derivar
no_disponible
ocupacion_real
perfil_desconocido
temporada_no_resuelta
cotizacion_vencida
rol_no_permitido
payload_invalido
override_sin_motivo
```

---

## 23. Portal operativo futuro

Roles:

```text
socio = administra precios/eventos/overrides/config
vicky = cotiza y carga reserva manual
jenny = sin acceso a precios
```

Lecturas futuras:

```text
precios.cotizar
precios.config.listado
precios.tarifas.listado
precios.temporadas.listado
precios.alta_demanda.listado
precios.eventos.listado
precios.overrides.listado
```

Escrituras futuras:

```text
precios.tarifas.actualizar
precios.tarifas.ajuste_porcentual
precios.alta_demanda.crear
precios.alta_demanda.desactivar
precios.evento.crear
precios.evento.actualizar
precios.evento.desactivar
precios.evento.reactivar
precios.override_rango.crear
precios.override_rango.desactivar
precios.config.actualizar
```

Pantalla clave:

```text
Precios → Grilla tarifaria
```

Debe permitir:

- elegir perfil;
- elegir temporada;
- ver/editar 8 conceptos;
- update versionado;
- auditoría;
- no tocar reservas/pre-reservas;
- mostrar perfiles sin grilla completa;
- bloquear cotización $0 accidental.

---

## 24. Decisiones D-PR cerradas

| Decisión | Estado |
|---|---|
| D-PR-01 | Nueva grilla `tarifas_motor`; `tarifas` legacy queda deprecated. |
| D-PR-02 | Ajuste masivo versionado. |
| D-PR-03 | `perfiles_tarifarios` + `cabanas.perfil_tarifario`. |
| D-PR-04 | `temporada_vigencia` materializada. |
| D-PR-05 | `noches_alta_demanda`; `feriados` legacy fuera del motor v2. |
| D-PR-06 | Superficie pública separada del gateway autenticado. |
| D-PR-07 | `cotizaciones_precio`, TTL 30 min. |
| D-PR-08 | Redondeo $1.000 por línea. |
| D-PR-09 | Ordinal continuo en cruce de temporada. |
| D-PR-10 | Evento no cuenta ordinal, pero no reinicia contador estándar. |
| D-PR-11 | Extra persona global; grande 4, chica 3. |
| D-PR-12 | Reglas de venta modeladas ahora; viernes+sábado alta configurable. |
| D-PR-13 | Config editable/socio-only vs técnica/seed-only. |
| D-PR-14 | `reservas.capacidad_override BOOLEAN DEFAULT FALSE`. |
| D-PR-15 | Desacople motor de precios vs alta cabañas/pool societario. |

---

## 25. B2A ejecutado y cerrado en TEST

B2A correspondió a:

```text
Estructura + Hardening + Seeds mínimos
```

Resultado en TEST:

```text
Migración: success, no rows returned
VERIFY: fingerprint da52a16c045689523a5f1f113f513a87
SMOKES: 12/12 PASS
```

Fingerprint estructural TEST:

```text
da52a16c045689523a5f1f113f513a87
```

B2A creó:

- `perfiles_tarifarios`;
- `tarifas_motor`;
- `temporada_vigencia`;
- `noches_alta_demanda`;
- `overrides_precio`;
- `cotizaciones_precio`;
- `precios_auditoria`;
- `cabanas.perfil_tarifario`;
- columnas nuevas en `reservas`;
- `pre_reservas.cotizacion_id`;
- config keys de pricing;
- hardening;
- trigger propio de inmutabilidad;
- índice correctivo `idx_paquetes_evento_id_evento`.

B2A no tocó:

- OPS;
- grillas masivas;
- funciones de motor;
- `crear_prereserva`;
- gateway;
- portal;
- hardening legacy.

---

## 26. Próximo paso después de B0/B2A

El próximo bloque lógico es:

```text
B2B — Seeds de pricing
```

Objetivo B2B:

- seed de `temporada_vigencia` alta/baja por al menos 3 años;
- seed de 4 grillas iniciales:
  - grande + alta;
  - grande + baja;
  - chica + alta;
  - chica + baja;
- cada grilla con 8 conceptos;
- respetar versionado de `tarifas_motor`;
- no tocar reservas/pre-reservas existentes;
- no tocar funciones de motor todavía;
- no tocar gateway/portal todavía;
- no tocar OPS.

Smokes B2B esperados:

- temporadas completas;
- grilla completa por perfil+temporada;
- no tarifas en cero;
- unicidad vigente;
- ausencia de celdas faltantes;
- precios exactos cargados;
- hardening no degradado;
- estructura B2A intacta.

---

## 27. Uso de este documento

Este B0 debe usarse como:

- fuente de verdad conceptual;
- guía para auditoría de Claude;
- base para prompts futuros;
- referencia para canónico/cierre;
- control de alcance para evitar mezclar pricing con alta de cabañas, pool societario o portal completo.

Si una respuesta técnica futura contradice este documento, debe marcarse explícitamente y pedirse aprobación antes de cambiar el diseño.
