# ARQUITECTURA_ETAPA_2_VITA_DELTA.md
# Motor de Disponibilidad — Diseño Completo

**Versión:** 1.3  
**Fecha:** Mayo 2026  
**Estado:** Aprobado — CERRADO  
**Depende de:** ARQUITECTURA_ETAPA_1_VITA_DELTA.md v1.1  
**Autores:** Franco (titular) + Claude (arquitecto)

**Historial de versiones:**
- v1.0 — Motor de disponibilidad completo, escalonamiento, horarios, cache, edge cases
- v1.1 — Ajustes: escalonamiento checkout limitado, OVERRIDES_OPERATIVOS, race conditions documentadas, DISPONIBILIDAD_CACHE simplificada
- v1.2 — Corrección crítica: intervalo semiabierto `[fecha_in, fecha_out)`, condición canónica de solapamiento, condición de bloqueos parciales, eliminación de `BETWEEN` incorrecto en `calcular_disponibilidad`
- v1.3 — Decisión operativa: eliminado escalonamiento automático de checkout. Solo existe escalonamiento de check-in. El checkout mantiene siempre su horario base (10:00 / 16:00 último día de bloque / override manual). Renombrada clave `escalonamiento_umbral_checkout` a `escalonamiento_umbral_checkins_dia`. Eliminadas claves `escalonamiento_umbral_checkin`, `escalonamiento_checkout_min`, `escalonamiento_checkout_max_minutos`, `escalonamiento_checkout_tramo_minutos` y función `aplicar_escalonamiento_checkout`. `hora_checkout_minima` en cache redefinida como mínimo por configuración, no por escalonamiento.

---

## ÍNDICE

1. Objetivo del motor de disponibilidad
2. Principios del motor
3. Reglas de horarios
4. Motor de escalonamiento *(actualizado en v1.1 — escalonamiento de checkout eliminado en v1.3)*
5. Reglas del último día del bloque
6. Checkin y checkout flexible por el cliente
7. Overrides operativos *(nuevo en v1.1)*
8. Algoritmo completo de disponibilidad *(condición de solapamiento corregida en v1.2)*
9. Estructura de DISPONIBILIDAD_CACHE *(simplificada en v1.1)*
10. Triggers de recálculo
11. Configuración del motor (todo en CONFIGURACION_GENERAL)
12. Edge cases documentados *(race conditions agregadas en v1.1)*
13. Continuidad hacia Etapa 3

---

## 1. OBJETIVO DEL MOTOR DE DISPONIBILIDAD

El motor de disponibilidad es el componente que responde a una pregunta simple:

> **¿Puede el huésped X reservar la cabaña Y desde la fecha A hasta la fecha B, y si puede, a qué horario entra y sale?**

Para responder esa pregunta, el motor combina:
- Estado de ocupación de la cabaña (reservas, pre-reservas, bloqueos)
- Reglas de horarios según tipo de día y temporada
- Escalonamiento según carga operativa del equipo de limpieza
- Preferencias del cliente (dentro de los márgenes permitidos)

El resultado de todo este cálculo se almacena en **DISPONIBILIDAD_CACHE** y se recalcula por eventos, no en tiempo real durante las consultas.

---

## 2. PRINCIPIOS DEL MOTOR

1. **El bot y la web nunca calculan — solo consultan.** Toda la lógica vive en n8n y el resultado en DISPONIBILIDAD_CACHE.

2. **El escalonamiento es configurable y desactivable.** Si en algún momento se contrata más personal de limpieza, se cambia un valor en CONFIGURACION_GENERAL y el motor se adapta automáticamente.

3. **Los horarios tienen una jerarquía clara.** El sistema calcula un horario base. El escalonamiento puede modificarlo. El cliente puede ajustarlo dentro del margen resultante.

4. **El último día del bloque tiene reglas propias.** No depende del tipo de día sino de su posición en el bloque de reserva.

5. **Toda regla tiene su fuente en CONFIGURACION_GENERAL.** Ningún horario, umbral o margen está hardcodeado.

---

## 3. REGLAS DE HORARIOS

### 3.1 Horarios base (default)

Aplican a cualquier día que no tenga una excepción específica.

| Evento | Horario | Clave en CONFIGURACION_GENERAL |
|---|---|---|
| Check-in estándar | 13:00 | `hora_checkin_default` |
| Check-out estándar | 10:00 | `hora_checkout_default` |

### 3.2 Excepción — Domingo como primer día de reserva

El domingo tiene check-in a las 18:00 **siempre que sea el primer día de la reserva**, independientemente de la temporada.

| Condición | Check-in | Clave |
|---|---|---|
| Domingo = primer día de reserva | 18:00 | `hora_checkin_domingo` |

**Importante:** Si el domingo es un día intermedio o el último de una reserva más larga, no aplica esta excepción. Se comporta como día normal.

### 3.3 Excepción — Último día del bloque

El "bloque" es el conjunto continuo de días reservados incluyendo feriados pegados al fin de semana.

| Condición | Check-out | Clave |
|---|---|---|
| Último día del bloque (domingo o feriado extendido) | 16:00 | `hora_checkout_ultimo_dia_bloque` |

**Cómo se determina el último día del bloque:**

```
1. El bloque base es viernes + sábado + domingo
2. Si el lunes es feriado → el bloque se extiende al lunes
3. Si el lunes Y el martes son feriados → el bloque se extiende al martes
4. El checkout de 16:00 aplica SOLO al último día del bloque
5. Los días anteriores del bloque mantienen checkout estándar (10:00) si hay reservas encima
```

**Ejemplos:**

| Situación | Último día del bloque | Checkout |
|---|---|---|
| Fin de semana normal | Domingo | 16:00 |
| Finde + lunes feriado | Lunes | 16:00 |
| Finde + lunes y martes feriados | Martes | 16:00 |

### 3.4 Temporada alta — Fin de semana completo obligatorio

En temporada alta (configurable, default: 1 diciembre — 28 febrero):

- **Mínimo obligatorio en fin de semana:** viernes + sábado + domingo (2 noches)
- **Check-in del viernes:** 13:00 (o el elegido por el cliente si es mayor)
- **Check-out del domingo:** 16:00 (último día del bloque)
- **No se puede reservar 1 sola noche de fin de semana en temporada alta**

Esta restricción se configura en TARIFAS con `minimo_noches_obligatorio = 2` para el tipo `finde` en temporada `alta`.

### 3.5 Resumen de horarios por escenario

| Escenario | Check-in | Check-out |
|---|---|---|
| Día de semana estándar | 13:00 | 10:00 |
| Domingo como primer día | 18:00 | 10:00 (si no es último del bloque) |
| Domingo como último del bloque | — | 16:00 |
| Lunes feriado como último del bloque | 13:00 | 16:00 |
| Viernes en temporada alta (finde completo) | 13:00 | — |
| Domingo en finde completo temp. alta | — | 16:00 |

---

## 4. MOTOR DE ESCALONAMIENTO

> **v1.3 — Escalonamiento de checkout eliminado.** El checkout mantiene siempre su horario base según reglas normales (10:00 estándar, 16:00 último día de bloque, o override manual). No existe adelanto automático de checkout. El único escalonamiento operativo es sobre el check-in.

### 4.1 Concepto

El escalonamiento existe para dar tiempo al equipo de limpieza a limpiar y preparar cabañas cuando hay alta concentración de ingresos el mismo día.

**Dirección única implementada: escalonamiento de check-in.**

Cuando se acumulan muchos check-ins el mismo día, las cabañas que ingresan después del umbral tienen su horario de entrada retrasado en tramos de 45 minutos. El huésped puede llegar al complejo a cualquier hora, usar los espacios comunes y dejar equipaje bajo cuidado, pero el acceso formal a la cabaña es a partir del horario confirmado.

El escalonamiento de checkout (adelantar la salida) fue evaluado y descartado por razones comerciales y operativas: genera fricción con los huéspedes y es difícil de comunicar. Si en el futuro se necesita un ajuste puntual de checkout, se usa `OVERRIDES_OPERATIVOS`.

### 4.2 Parámetros configurables

Todos en CONFIGURACION_GENERAL:

| Clave | Valor default | Descripción |
|---|---|---|
| `escalonamiento_activo` | true | Master switch. Si es false, el motor ignora el escalonamiento y usa horarios base puros |
| `escalonamiento_umbral_checkins_dia` | 3 | Cantidad de check-ins del mismo día que mantienen horario base antes de empezar a escalonar |
| `escalonamiento_minutos` | 45 | Minutos de retraso adicional por cada check-in sobre el umbral |
| `escalonamiento_checkin_max` | 22:00 | Límite máximo de check-in por escalonamiento |

**Nota:** Para desactivar el escalonamiento completamente (por ejemplo, al contratar más personal), basta con cambiar `escalonamiento_activo = false`. Ningún horario de checkin se modifica y el sistema usa horarios base puros.

### 4.3 Escalonamiento de check-in

**Condición de activación:** El orden del check-in de esta cabaña en el día supera el umbral.

**Fórmula:**
```
SI orden_checkin_dia <= escalonamiento_umbral_checkins_dia:
    hora_checkin = hora_checkin_base

SI orden_checkin_dia > escalonamiento_umbral_checkins_dia:
    hora_checkin = hora_checkin_base
                   + ((orden_checkin_dia - escalonamiento_umbral_checkins_dia) × escalonamiento_minutos)
```

Donde `orden_checkin_dia` es la posición de esta cabaña entre todas las que hacen check-in ese día (1 = primera, 2 = segunda, etc.), ordenadas por momento de confirmación de reserva.

**Ejemplos con umbral = 3, base = 13:00, minutos = 45:**

| orden_checkin_dia | Check-in calculado | Ajuste |
|---|---|---|
| 1, 2 o 3 | 13:00 | Sin ajuste |
| 4 | 13:45 | +45 min |
| 5 | 14:30 | +90 min |
| 6 | 15:15 | +135 min |

**Ejemplos con domingo (base = 18:00):**

| orden_checkin_dia | Check-in calculado | Ajuste |
|---|---|---|
| 1, 2 o 3 | 18:00 | Sin ajuste |
| 4 | 18:45 | +45 min |
| 5 | 19:30 | +90 min |

**Límite de seguridad:** Si `hora_checkin_calculada > escalonamiento_checkin_max (22:00)`, n8n asigna estado `limite_escalonamiento` a esa combinación (cabaña, fecha), notifica al equipo responsable definido en CONFIGURACION_GENERAL, y el equipo decide manualmente.

### 4.4 Escalonamiento de check-out — fuera de alcance

> El escalonamiento automático de checkout **no está implementado** en esta versión.
>
> El checkout siempre respeta su horario base:
> - 10:00 estándar
> - 16:00 si aplica último día de bloque (ver Sección 5)
> - Horario especial solo mediante `OVERRIDES_OPERATIVOS` (intervención manual)
>
> Las claves `escalonamiento_umbral_checkin`, `escalonamiento_checkout_min`, `escalonamiento_checkout_max_minutos` y `escalonamiento_checkout_tramo_minutos` fueron eliminadas del sistema en v1.3. No deben cargarse en CONFIGURACION_GENERAL.

### 4.5 Límite de seguridad del check-in

Si el cálculo de escalonamiento produce una hora mayor a `escalonamiento_checkin_max`:

1. n8n asigna estado `limite_escalonamiento` a esa combinación (cabaña, fecha)
2. Notifica al equipo responsable definido en CONFIGURACION_GENERAL por WhatsApp con el detalle
3. El equipo decide manualmente si confirmar, bloquear o reasignar
4. Queda registrado en LOG_CAMBIOS



## 5. REGLAS DEL ÚLTIMO DÍA DEL BLOQUE

### 5.1 Algoritmo de detección del último día

```
FUNCIÓN ultimo_dia_bloque(fecha_checkout):

  // fecha_checkout es el día en que el huésped se va
  dia = fecha_checkout

  // ¿Es domingo o sábado?
  SI dia_semana(dia) NO ES domingo Y NO ES sábado:
    RETORNAR { es_ultimo_bloque: false }

  // Buscar extensión por feriados consecutivos
  siguiente = dia + 1 día

  MIENTRAS siguiente ES feriado:
    dia = siguiente
    siguiente = siguiente + 1 día

  RETORNAR {
    es_ultimo_bloque: true,
    ultimo_dia: dia,
    hora_checkout: hora_checkout_ultimo_dia_bloque (16:00)
  }
```

### 5.2 Casos documentados

**Caso A — Fin de semana simple:**
```
Reserva: viernes → domingo
Domingo = último día del bloque
→ Checkout domingo: 16:00
```

**Caso B — Fin de semana + lunes feriado:**
```
Reserva: viernes → lunes
Lunes = feriado → último día del bloque
→ Checkout lunes: 16:00
→ Domingo: si hay checkout ese domingo, checkout estándar 10:00
```

**Caso C — Fin de semana + lunes y martes feriados:**
```
Reserva: viernes → martes
Martes = último feriado consecutivo → último día del bloque
→ Checkout martes: 16:00
→ Lunes: checkout estándar 10:00 si hay reserva encima
→ Domingo: checkout estándar 10:00 si hay reserva encima
```

**Caso D — Domingo solo (sin viernes/sábado):**
```
Reserva: domingo → lunes (2 noches)
Domingo = primer día → check-in 18:00
Lunes = último día → si lunes es feriado, checkout 16:00; si no, checkout 10:00
```

---

## 6. CHECK-IN Y CHECK-OUT FLEXIBLE POR EL CLIENTE

### 6.1 Principio de jerarquía

El horario final resulta de aplicar, en orden:

```
1. Horario base (reglas de sección 3)
2. Escalonamiento de check-in (reglas de sección 4) → puede retrasar la entrada
3. Preferencia del cliente → puede ajustar dentro del margen resultante
```

El checkout no tiene escalonamiento automático. Su horario máximo es siempre el calculado por las reglas base (10:00 o 16:00 último día de bloque). El cliente puede elegir salir antes de ese máximo, dentro del mínimo configurado.

### 6.2 Margen permitido para check-in

```
hora_checkin_minima = MAX(hora_checkin_base, hora_checkin_escalonamiento)
hora_checkin_maxima = hora_checkin_max_cliente (configurable, default: 22:00)

El cliente puede elegir cualquier hora entre hora_checkin_minima y hora_checkin_maxima
```

**Ejemplos:**

| Escalonamiento calcula | Cliente pide | Resultado |
|---|---|---|
| 13:00 (sin ajuste) | 13:00 | 13:00 ✓ |
| 13:00 (sin ajuste) | 17:00 | 17:00 ✓ |
| 13:45 (ajustado) | 13:00 | Rechazado → mínimo es 13:45 |
| 13:45 (ajustado) | 15:00 | 15:00 ✓ |
| 13:45 (ajustado) | 17:00 | 17:00 ✓ |

### 6.3 Margen permitido para check-out

```
hora_checkout_maxima = hora_checkout_base
                       (10:00 estándar, 16:00 si es último día de bloque, o override manual)
hora_checkout_minima = hora_checkout_min_cliente (configurable, default: 07:00)

El cliente puede elegir cualquier hora entre hora_checkout_minima y hora_checkout_maxima.
No existe escalonamiento automático que adelante este máximo.
```

**Ejemplos:**

| hora_checkout_maxima | Cliente pide | Resultado |
|---|---|---|
| 10:00 (día normal) | 10:00 | 10:00 ✓ |
| 10:00 (día normal) | 08:00 | 08:00 ✓ |
| 10:00 (día normal) | 11:00 | Rechazado → máximo es 10:00 |
| 16:00 (último día de bloque) | 14:00 | 14:00 ✓ |
| 16:00 (último día de bloque) | 16:00 | 16:00 ✓ |

### 6.4 Impacto en el escalonamiento

La hora preferida por el cliente **no modifica el cálculo de escalonamiento de otras cabañas**. El motor siempre cuenta check-ins usando los horarios base, no los horarios elegidos por el cliente.

Esto es importante: si un cliente elige entrar a las 17:00 en vez de 13:45, eso no altera el orden de check-ins del día ni cambia el escalonamiento de las cabañas siguientes.

### 6.5 Configuración

| Clave | Valor | Descripción |
|---|---|---|
| `checkin_flexible_activo` | true | Si el cliente puede elegir su hora de entrada |
| `checkout_flexible_activo` | true | Si el cliente puede elegir su hora de salida |
| `hora_checkin_max_cliente` | 22:00 | Hora máxima de entrada permitida |
| `hora_checkout_min_cliente` | 07:00 | Hora mínima de salida permitida |

---

## 7. OVERRIDES OPERATIVOS

### 7.1 Propósito

Los overrides permiten modificar el comportamiento del motor para una fecha específica o rango de fechas, sin tocar CONFIGURACION_GENERAL ni el código. Son la válvula de escape del sistema para excepciones operativas reales.

**Ejemplos de uso:**
- Desactivar escalonamiento un día puntual porque hay personal extra
- Aumentar el umbral de limpieza para un evento especial
- Bloquear flexibilidad de check-in/check-out por tormenta o mantenimiento
- Forzar horario especial por decisión comercial
- Cambiar mínimo de noches para una fecha específica

### 7.2 Tabla OVERRIDES_OPERATIVOS

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| id_override | Integer | Sí | ID único autoincremental |
| fecha_desde | Date | Sí | Inicio del rango (o fecha puntual si fecha_hasta es null) |
| fecha_hasta | Date | No | Fin del rango. Null = aplica solo a fecha_desde |
| id_cabana | Integer | No | FK → CABAÑAS. Null = aplica a todas las cabañas |
| tipo_override | String | Sí | Tipo de regla a sobreescribir. Ver valores válidos abajo |
| valor | String | Sí | Nuevo valor para ese tipo. Puede ser hora, número, boolean o texto |
| motivo | String | Sí | Razón del override (visible en logs y notificaciones) |
| creado_por | String | Sí | Quién lo creó |
| activo | Boolean | Sí | Para desactivar sin borrar |
| source_event | String | Sí | Origen: "admin_manual", "bot_emergencia", etc. |
| created_at | Timestamp | Sí | |

### 7.3 Valores válidos de `tipo_override`

| Tipo | Valor esperado | Descripción |
|---|---|---|
| `escalonamiento_activo` | `true` / `false` | Activa o desactiva escalonamiento de check-in para esas fechas |
| `escalonamiento_umbral_checkins_dia` | Número entero | Sobreescribe el umbral de check-ins del día para activar escalonamiento de check-in |
| `hora_checkin` | `HH:MM` | Fuerza hora de check-in específica |
| `hora_checkout` | `HH:MM` | Fuerza hora de check-out específica (única vía de ajuste manual de checkout) |
| `checkin_flexible` | `true` / `false` | Activa o desactiva flexibilidad de check-in |
| `checkout_flexible` | `true` / `false` | Activa o desactiva flexibilidad de check-out |
| `minimo_noches` | Número entero | Sobreescribe mínimo de noches |
| `disponibilidad_bloqueada` | `true` | Bloquea toda disponibilidad (alternativa ligera a BLOQUEOS) |

### 7.4 Orden de precedencia del motor

Cuando el motor calcula disponibilidad, consulta en este orden:

```
1. OVERRIDES_OPERATIVOS activos para esa (cabana, fecha)
   → Si existe override aplicable, usa ese valor
   → Si no, continúa

2. CONFIGURACION_GENERAL
   → Valores base del sistema

3. Reglas hardcodeadas en n8n
   → Lógica que no cambia (estructura del algoritmo)
```

### 7.5 Comportamiento ante overrides múltiples

Si hay dos overrides activos para la misma (cabaña, fecha) con el mismo tipo:
- Tiene prioridad el override más específico: cabaña específica > todas las cabañas
- Si son del mismo nivel, tiene prioridad el creado más recientemente
- n8n loguea el conflicto en LOG_CAMBIOS con nivel `warning`

### 7.6 Ejemplo de uso

**Situación:** El sábado 14 de junio hay un evento especial. Se contrató personal extra. Se quiere desactivar el escalonamiento solo ese día para todas las cabañas.

```
OVERRIDES_OPERATIVOS:
  fecha_desde: 2026-06-14
  fecha_hasta: null          // solo ese día
  id_cabana: null            // todas las cabañas
  tipo_override: escalonamiento_activo
  valor: false
  motivo: Personal extra contratado para evento 14/06
  creado_por: franco
  source_event: admin_manual
```

El motor ese día ignora todo el cálculo de escalonamiento y usa horarios base puros.

---

## 8. ALGORITMO COMPLETO DE DISPONIBILIDAD

Este es el algoritmo que n8n ejecuta cada vez que necesita calcular o recalcular disponibilidad para una combinación (cabaña, fecha).

> **v1.2 — Correcciones aplicadas:**
> - **PASO 2 (bloqueos):** la condición anterior (`fecha_desde <= fecha_in AND fecha_hasta >= fecha_out`) solo detectaba bloqueos que cubrían el rango completo. La condición correcta detecta cualquier solapamiento parcial o total.
> - **PASO 3 (ocupación):** el `BETWEEN fecha_in AND fecha_out` era incorrecto porque incluía `fecha_out`, impidiendo reservas encadenadas. La condición correcta usa el intervalo semiabierto `[fecha_in, fecha_out)`.
> - **`checkout_disponible` no es conflicto:** este estado indica que hay un checkout ese día pero la noche de esa fecha está libre. No bloquea disponibilidad y no debe incluirse en la consulta de conflictos. Solo son conflicto los estados `ocupada`, `bloqueada` y `limite_escalonamiento`.

### 8.1 Consulta de disponibilidad para una reserva nueva

```
FUNCIÓN calcular_disponibilidad(id_cabana_solicitada, fecha_in, fecha_out, personas):

  // PASO 1: Verificar que la cabaña existe y está activa
  cabana = CABAÑAS WHERE id = id_cabana_solicitada AND activa = true
  SI cabana no existe: RETORNAR { disponible: false, motivo: "cabaña_inactiva" }

  // PASO 2: Verificar bloqueos
  // Condición canónica de solapamiento: detecta cualquier intersección parcial o total
  // entre el bloqueo y el rango solicitado, incluyendo bloqueos que empiezan en el medio.
  // Un bloqueo que termina exactamente en fecha_in NO genera conflicto (intervalo semiabierto).
  // BLOQUEOS.id_cabana IS NULL significa bloqueo total del complejo (todas las cabañas).
  bloqueo = BLOQUEOS WHERE (BLOQUEOS.id_cabana = id_cabana_solicitada OR BLOQUEOS.id_cabana IS NULL)
                       AND activo = true
                       AND fecha_desde < fecha_out
                       AND fecha_hasta > fecha_in
  SI bloqueo existe: RETORNAR { disponible: false, motivo: "bloqueada", detalle: bloqueo.motivo }

  // PASO 3: Verificar ocupación usando DISPONIBILIDAD_CACHE
  // Principio: una reserva ocupa noches en el intervalo semiabierto [fecha_in, fecha_out).
  // → fecha_in está ocupada como noche.
  // → fecha_out NO está ocupada como noche: es el día de salida y puede recibir un nuevo checkin.
  // Por lo tanto: se verifica el rango [fecha_in, fecha_out - 1 día] inclusive,
  // es decir, las fechas donde fecha >= fecha_in AND fecha < fecha_out.
  //
  // 'checkout_disponible' no bloquea disponibilidad porque la noche de esa fecha está libre.
  // Indica movimiento operativo de salida, no ocupación nocturna. No se incluye en la consulta.
  // Solo son conflicto: 'ocupada', 'bloqueada', 'limite_escalonamiento'.
  ocupacion = DISPONIBILIDAD_CACHE WHERE DISPONIBILIDAD_CACHE.id_cabana = id_cabana_solicitada
                                    AND fecha >= fecha_in
                                    AND fecha < fecha_out
                                    AND estado IN ('ocupada', 'bloqueada', 'limite_escalonamiento')
  SI ocupacion existe:
    RETORNAR { disponible: false, motivo: "fechas_ocupadas", fechas_conflicto: [lista de fechas] }

  // PASO 4: Verificar mínimo de noches
  noches = dias entre fecha_in y fecha_out
  minimo = calcular_minimo_noches(fecha_in, temporada_actual)
  SI noches < minimo:
    RETORNAR { disponible: false, motivo: "minimo_noches", minimo: minimo }

  // PASO 5: Calcular horario de check-in
  hora_checkin_base = calcular_hora_checkin_base(fecha_in)
  hora_checkin_final = aplicar_escalonamiento_checkin(id_cabana_solicitada, fecha_in, hora_checkin_base)

  // PASO 6: Calcular horario de check-out
  // No existe escalonamiento automático de checkout.
  // El horario lo determina exclusivamente calcular_hora_checkout_base.
  // Cualquier ajuste especial de checkout solo puede provenir de OVERRIDES_OPERATIVOS.
  hora_checkout_final = calcular_hora_checkout_base(fecha_out, fecha_in)

  // PASO 7: Verificar capacidad
  SI personas > cabana.capacidad_max:
    RETORNAR { disponible: false, motivo: "capacidad_excedida" }

  RETORNAR {
    disponible: true,
    hora_checkin_minima: hora_checkin_final,
    hora_checkin_maxima: hora_checkin_max_cliente,
    hora_checkout_maxima: hora_checkout_final,
    hora_checkout_minima: hora_checkout_min_cliente,
    noches: noches,
    temporada: temporada_actual
  }
```

### 8.2 Función: calcular_hora_checkin_base

```
FUNCIÓN calcular_hora_checkin_base(fecha):

  // ¿Es domingo Y es el primer día de la reserva?
  SI dia_semana(fecha) = domingo:
    RETORNAR hora_checkin_domingo (18:00)

  // Cualquier otro día
  RETORNAR hora_checkin_default (13:00)
```

### 8.3 Función: calcular_hora_checkout_base

```
FUNCIÓN calcular_hora_checkout_base(fecha_checkout, fecha_checkin):

  // ¿Es el último día del bloque?
  SI es_ultimo_dia_bloque(fecha_checkout):
    RETORNAR hora_checkout_ultimo_dia_bloque (16:00)

  // Cualquier otro día
  RETORNAR hora_checkout_default (10:00)
```

### 8.4 Función: aplicar_escalonamiento_checkin

```
FUNCIÓN aplicar_escalonamiento_checkin(id_cabana, fecha, hora_base):

  // ¿Está activo el escalonamiento? Verificar override primero.
  activo = obtener_valor_con_override('escalonamiento_activo', id_cabana, fecha)
  SI activo = false:
    RETORNAR hora_base

  // Calcular el orden de check-in de esta cabaña en el día.
  // Se combinan RESERVAS confirmadas/activas y PRE_RESERVAS vigentes (pendientes de pago),
  // porque ambas representan ingresos reales esperados para ese día.
  // Las pre-reservas vencidas, canceladas y convertidas no cuentan.
  checkins_del_dia = UNION(
    RESERVAS WHERE fecha_checkin = fecha
              AND estado IN ('confirmada', 'activa'),

    PRE_RESERVAS WHERE fecha_in = fecha
                  AND estado = 'pendiente_pago'
                  AND expira_en > ahora
  ) ORDENADAS POR created_at ASC

  orden_checkin_dia = posicion_de(id_cabana, checkins_del_dia)
  // Si esta cabaña no está en la lista aún (evaluación previa a escribir en PRE_RESERVAS),
  // usar count(checkins_del_dia) + 1 como su orden tentativo.

  umbral = obtener_valor_con_override('escalonamiento_umbral_checkins_dia', id_cabana, fecha)

  SI orden_checkin_dia <= umbral:
    RETORNAR hora_base

  // Calcular ajuste por posición sobre el umbral
  posiciones_sobre_umbral = orden_checkin_dia - umbral
  minutos_extra = posiciones_sobre_umbral × escalonamiento_minutos
  hora_ajustada = hora_base + minutos_extra

  // Verificar límite de seguridad
  SI hora_ajustada > escalonamiento_checkin_max:
    disparar_notificacion("limite_escalonamiento_alcanzado", fecha, id_cabana)
    RETORNAR { estado: 'limite_escalonamiento' }

  RETORNAR hora_ajustada
```

### 8.5 Función: aplicar_escalonamiento_checkout — eliminada en v1.3

> Esta función fue eliminada. El checkout no tiene escalonamiento automático.
> El horario de checkout lo determina `calcular_hora_checkout_base` (sección 8.3).
> Cualquier ajuste puntual de checkout se realiza mediante `OVERRIDES_OPERATIVOS`.



## 9. ESTRUCTURA DE DISPONIBILIDAD_CACHE

Un registro por combinación (cabaña, fecha). Se mantiene para todas las fechas desde hoy hasta 18 meses adelante.

**Principio:** La cache guarda resultados operativos finales, no inputs ni cálculos intermedios. El bot y la web solo necesitan saber qué puede hacer el huésped, no cómo se llegó a ese resultado.

> **v1.2 — Columnas operativas agregadas:** se incorporan `tiene_checkout`, `id_reserva_checkout`, `tiene_checkin` e `id_reserva_checkin` para registrar movimientos del día independientemente del estado de disponibilidad. Esto permite que el estado principal (`ocupada` / `checkout_disponible`) sea correcto desde el punto de vista de reservas, mientras que el equipo operativo puede ver en un mismo registro si hay rotación ese día. Ver especificación completa en `ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md`.

| Campo | Tipo | Descripción |
|---|---|---|
| id_cabana | Integer | FK → CABAÑAS |
| fecha | Date | YYYY-MM-DD |
| estado | String | `disponible`, `ocupada`, `bloqueada`, `checkout_disponible`, `limite_escalonamiento` |
| hora_checkin_minima | Time | Mínimo permitido considerando escalonamiento |
| hora_checkin_maxima | Time | Máximo permitido (de CONFIGURACION_GENERAL) |
| hora_checkout_maxima | Time | Hora límite de salida según regla base u override |
| hora_checkout_minima | Time | Mínimo permitido por CONFIGURACION_GENERAL u override |
| tipo_dia | String | `semana`, `finde`, `feriado`, `ano_nuevo` |
| temporada | String | `alta`, `media`, `baja` |
| es_ultimo_dia_bloque | Boolean | Si aplica la regla de checkout 16:00 |
| minimo_noches | Integer | Mínimo de noches desde este día |
| id_reserva_activa | Integer | FK → RESERVAS si está ocupada |
| id_prereserva_activa | Integer | FK → PRE_RESERVAS si está en proceso |
| tiene_checkout | Boolean | TRUE si una reserva confirmada/activa hace checkout ese día |
| id_reserva_checkout | Integer | FK → RESERVAS. ID de la reserva que hace checkout ese día, si aplica |
| tiene_checkin | Boolean | TRUE si una reserva confirmada/activa hace checkin ese día |
| id_reserva_checkin | Integer | FK → RESERVAS. ID de la reserva que hace checkin ese día, si aplica |
| recalculado_en | Timestamp | Última vez que se calculó |

**Clave primaria compuesta:** (id_cabana, fecha)

> **Nota sobre campos operativos:** `tiene_checkout`, `id_reserva_checkout`, `tiene_checkin` e `id_reserva_checkin` reflejan movimientos operativos confirmados asociados a RESERVAS confirmadas o activas. No se generan para PRE_RESERVAS. Una PRE_RESERVA vigente bloquea disponibilidad (via `id_prereserva_activa` y `estado = ocupada`), pero no representa todavía movimiento operativo real de limpieza: el equipo de limpieza no prepara ni limpia una cabaña hasta que la reserva esté confirmada. No se agregan columnas de pre-reserva en esta etapa.

### Estados de la cache

| Estado | Descripción | El bot puede mostrar |
|---|---|---|
| `disponible` | Libre y sin restricciones. La noche de esta fecha no está ocupada. | Sí |
| `checkout_disponible` | Hay checkout de una reserva este día, pero la noche de esta fecha no está ocupada por ninguna otra reserva o pre-reserva. Puede recibir un nuevo checkin. | Sí, con nota |
| `ocupada` | La noche de esta fecha está ocupada por una reserva confirmada/activa o por una pre-reserva pendiente. Puede haber también un checkout ese mismo día (ver `tiene_checkout`). | No |
| `bloqueada` | Bloqueo manual activo para esta fecha. | No |
| `limite_escalonamiento` | El escalonamiento alcanzó el límite de seguridad. | No (equipo decide) |

---

## 10. TRIGGERS DE RECÁLCULO

### 10.1 Recálculo parcial (por evento)

Se ejecuta en n8n cada vez que ocurre un evento que modifica disponibilidad.

| Evento | Cabañas afectadas | Fechas afectadas |
|---|---|---|
| Nueva reserva confirmada | La reserva + todas las del mismo día (recalcular escalonamiento) | fecha_in - 2 días hasta fecha_out + 2 días |
| Reserva cancelada | Ídem | Ídem |
| Pre-reserva creada | La cabaña de la pre-reserva | fecha_in hasta fecha_out |
| Pre-reserva vencida | Ídem + todas del mismo día | Ídem |
| Bloqueo creado | Cabañas bloqueadas (o todas si es bloqueo total) | fecha_desde hasta fecha_hasta |
| Bloqueo eliminado | Ídem | Ídem |
| Cambio de feriado | Todas las cabañas | Fecha del feriado ± 3 días |
| Cambio de configuración de temporada | Todas las cabañas | Todo el rango afectado |
| Cambio de umbral de escalonamiento | Todas las cabañas | Próximos 30 días |

### 10.2 Recálculo masivo (programado)

Se ejecuta todos los días a las 03:00am. Recalcula todas las combinaciones (cabaña, fecha) para el rango hoy + 18 meses. Sirve para:
- Corregir cualquier inconsistencia acumulada
- Aplicar cambios de configuración que no dispararon recálculo parcial
- Extender el horizonte de la cache

### 10.3 Workflow de recálculo en n8n

```
WORKFLOW: db_recalcular_disponibilidad

INPUT: { id_cabanas: [array], fechas: [array], source_event: string }

PASOS:
  1. Para cada (id_cabana, fecha):
     a. Ejecutar algoritmo completo (sección 8)
     b. Escribir resultado en DISPONIBILIDAD_CACHE
     c. Registrar en LOG_CAMBIOS si hubo cambio de estado
  2. Si alguna fecha alcanzó limite_escalonamiento:
     a. Notificar al equipo responsable definido en CONFIGURACION_GENERAL por WhatsApp
  3. Actualizar timestamp recalculado_en
```

---

## 11. CONFIGURACIÓN COMPLETA DEL MOTOR

Todos estos valores viven en CONFIGURACION_GENERAL y son modificables sin tocar código.

### Horarios

| Clave | Valor default | Descripción |
|---|---|---|
| `hora_checkin_default` | 13:00 | Check-in estándar |
| `hora_checkout_default` | 10:00 | Check-out estándar |
| `hora_checkin_domingo` | 18:00 | Check-in cuando domingo es primer día |
| `hora_checkout_ultimo_dia_bloque` | 16:00 | Check-out del último día del bloque |

### Escalonamiento

| Clave | Valor default | Descripción |
|---|---|---|
| `escalonamiento_activo` | true | Master switch. Si es false, el motor usa horarios base puros |
| `escalonamiento_umbral_checkins_dia` | 3 | Cantidad de check-ins del mismo día que mantienen horario base antes de escalonar |
| `escalonamiento_minutos` | 45 | Minutos de retraso por cada check-in sobre el umbral |
| `escalonamiento_checkin_max` | 22:00 | Límite máximo de check-in por escalonamiento |

> **v1.3 — Claves eliminadas:** `escalonamiento_umbral_checkout`, `escalonamiento_umbral_checkin`, `escalonamiento_checkout_min`, `escalonamiento_checkout_max_minutos`, `escalonamiento_checkout_tramo_minutos`. No deben cargarse en CONFIGURACION_GENERAL.

### Flexibilidad del cliente

| Clave | Valor default | Descripción |
|---|---|---|
| `checkin_flexible_activo` | true | Si el cliente puede elegir hora de entrada |
| `checkout_flexible_activo` | true | Si el cliente puede elegir hora de salida |
| `hora_checkin_max_cliente` | 22:00 | Hora máxima de entrada que puede elegir el cliente |
| `hora_checkout_min_cliente` | 07:00 | Hora mínima de salida que puede elegir el cliente |

### Temporada

| Clave | Valor default | Descripción |
|---|---|---|
| `temporada_alta_inicio` | 12-01 | MM-DD inicio temporada alta |
| `temporada_alta_fin` | 02-28 | MM-DD fin temporada alta |
| `finde_minimo_noches_temp_alta` | 2 | Mínimo de noches en finde durante temporada alta |

### Cache

| Clave | Valor default | Descripción |
|---|---|---|
| `cache_horizonte_meses` | 18 | Meses hacia adelante que mantiene la cache |
| `cache_recalculo_masivo_hora` | 03:00 | Hora del recálculo nocturno |
| `prereserva_expiracion_minutos` | 60 | Tiempo de vida de una pre-reserva sin pago |

---

## 12. EDGE CASES DOCUMENTADOS

### Edge case 1 — Checkout y checkin el mismo día, misma cabaña

**Situación:** Reserva A sale el día 15. Reserva B quiere entrar el día 15.

**Regla:** Válido. La noche del día 15 pertenece a la Reserva B, no a la Reserva A. La Reserva A ocupa en el intervalo `[fecha_in_A, 15)`, es decir, su última noche es el 14. El día 15 es solo el día de salida.

**Estado en DISPONIBILIDAD_CACHE antes de confirmar Reserva B:**
- El día 15 tiene `estado = checkout_disponible` (la Reserva A sale ese día, la noche no está ocupada).

**Estado en DISPONIBILIDAD_CACHE después de confirmar Reserva B:**
- El día 15 tiene `estado = ocupada` (la noche del 15 pertenece a la Reserva B).
- `tiene_checkout = TRUE`, `id_reserva_checkout = id_Reserva_A` (el equipo de limpieza sabe que hay rotación ese día).
- `tiene_checkin = TRUE`, `id_reserva_checkin = id_Reserva_B`.

**Horarios:**
- Checkout Reserva A: calculado normalmente según reglas base (10:00 o 16:00 último día de bloque). Sin escalonamiento automático.
- Checkin Reserva B: calculado según su orden en el día. Si es el 4.º o posterior check-in, se aplica escalonamiento.

**Escalonamiento:** La Reserva B suma al conteo de check-ins del día 15. Si ya hay 3 check-ins ese día antes que ella, su horario de entrada se retrasa 45 minutos por cada posición adicional.

---

### Edge case 2 — Pre-reserva vence y hay reserva en cola

**Situación:** PRE_RESERVA_1 expira. En ese momento hay una CONSULTA_2 esperando esas fechas.

**Comportamiento:**
1. n8n detecta vencimiento de PRE_RESERVA_1 → cambia estado a `vencida`
2. Recalcula DISPONIBILIDAD_CACHE → fechas pasan a `disponible`
3. Si CONSULTA_2 tiene `estado_conversacion = esperando_disponibilidad`, n8n le avisa al bot
4. Bot notifica al cliente de CONSULTA_2 que las fechas están disponibles

**Nota:** n8n no crea la PRE_RESERVA_2 automáticamente. Solo notifica. El cliente debe confirmar.

---

### Edge case 3 — Bloqueo sobre pre-reserva activa

**Situación:** Admin crea un bloqueo en fechas donde ya hay una PRE_RESERVA activa.

**Comportamiento:**
1. n8n detecta el conflicto al crear el bloqueo
2. Notifica al equipo responsable definido en CONFIGURACION_GENERAL con el detalle: "Hay una pre-reserva activa (ID, cliente, fechas) que conflictúa con el bloqueo"
3. El bloqueo se crea igual (tiene prioridad sobre pre-reservas)
4. La PRE_RESERVA pasa a estado `cancelada_por_bloqueo`
5. n8n notifica al cliente que su pre-reserva fue cancelada y las fechas no están disponibles

---

### Edge case 4 — Cambio de temporada en medio de una reserva

**Situación:** Una reserva va del 28 de noviembre al 3 de diciembre (cruza inicio de temporada alta).

**Comportamiento:**
- Los días 28, 29, 30 de noviembre → reglas de temporada baja
- Los días 1, 2, 3 de diciembre → reglas de temporada alta
- El precio se calcula proporcionalmente según cada tramo
- El mínimo de noches en finde aplica solo a los días de temporada alta

---

### Edge case 5 — Escalonamiento de check-in alcanza el límite

**Situación:** Un día tiene 7 cabañas con check-in confirmado. La 8va cabaña quiere entrar ese mismo día.

**Cálculo:** orden_checkin_dia = 8. Umbral = 3. Posiciones sobre el umbral = 5. Ajuste = 5 × 45 = 225 min. Hora base 13:00 + 225 min = 16:45.

**Si 16:45 ≤ escalonamiento_checkin_max (22:00):** Se permite, check-in a las 16:45.

**Si el ajuste supera 22:00:** n8n asigna estado `limite_escalonamiento` a esa combinación (cabaña, fecha), notifica al equipo responsable definido en CONFIGURACION_GENERAL por WhatsApp, y el equipo decide manualmente si confirmar, bloquear o reasignar.

---

### Edge case 6 — Feriado que convierte un miércoles en "último día del bloque"

**Situación:** Hay un feriado el miércoles, y el cliente quiere reservar lunes, martes, miércoles.

**Análisis:** El miércoles es feriado pero no está pegado a un fin de semana. No es "último día del bloque" según la definición (el bloque es viernes/sábado/domingo + feriados consecutivos pegados).

**Resultado:** El miércoles feriado tiene checkout estándar (10:00). La regla de 16:00 solo aplica cuando el feriado extiende un fin de semana.


### Edge case 7 — Race condition: dos clientes reservan la misma cabaña simultáneamente ⚠️ CRÍTICO

**Situación:** Dos clientes diferentes (Canal A y Canal B) intentan reservar Bamboo para las mismas fechas casi al mismo tiempo. Ambos llegan al paso de pago.

**Por qué es crítico:** Sin control explícito, ambos podrían pagar y quedar confirmados para las mismas fechas — double booking real.

**Solución implementada — Workflow secuencial con revalidación:**

```
WORKFLOW: db_confirmar_reserva (secuencial, una ejecución a la vez)

PASO 1: Recibir solicitud de confirmación
  Input: { id_prereserva, id_pago, source_event }

PASO 2: Revalidar disponibilidad completa
  → Consultar RESERVAS: ¿hay reserva confirmada para (cabana, fechas)?
  → Consultar PRE_RESERVAS: ¿hay otra pre-reserva vigente (no vencida) para (cabana, fechas)?
  → Consultar BLOQUEOS: ¿hay bloqueo activo para (cabana, fechas)?

PASO 3a: Si disponibilidad OK
  → Convertir PRE_RESERVA a RESERVA con estado 'confirmada'
  → Recalcular DISPONIBILIDAD_CACHE
  → Notificar al cliente y al equipo
  → Registrar en LOG_CAMBIOS

PASO 3b: Si hay conflicto
  → NO confirmar la reserva
  → Cambiar estado de la PRE_RESERVA a 'conflicto_pendiente'
  → Registrar conflicto en LOG_CAMBIOS con todos los detalles:
      { prereserva_original, prereserva_conflictante, timestamp, source_event }
  → Notificar INMEDIATAMENTE al equipo responsable (definido en CONFIGURACION_GENERAL):
      "⚠️ Conflicto de reserva: [cabaña] [fechas]. Cliente [nombre] pagó pero hay conflicto.
       Revisar manualmente. ID: [id_prereserva]"
  → El pago queda registrado pero la reserva en estado manual
```

**Garantía técnica:** n8n ejecuta este workflow con concurrencia = 1 (una ejecución a la vez). Si llegan dos solicitudes simultáneas, la segunda espera en cola hasta que la primera termine. La revalidación en el Paso 2 garantiza que la segunda solicitud vea el estado actualizado.

**Estado `conflicto_pendiente`:** Requiere resolución manual del equipo. Opciones:
- Confirmar la reserva si el primer pago fue el válido
- Cancelar y reembolsar si corresponde
- Reasignar a otra cabaña disponible (con acuerdo del cliente)

---

## 13. CONTINUIDAD HACIA ETAPA 3

La Etapa 3 es el **Motor de Precios**. Incluye:

- [ ] Algoritmo completo de selección de tarifa según tipo de día, temporada y cantidad de noches
- [ ] Cálculo de precio para reservas que cruzan tramos de temporada
- [ ] Cálculo de extras por persona
- [ ] Cálculo de descuentos y promociones
- [ ] Cálculo de seña y saldo pendiente
- [ ] Integración del precio calculado con DISPONIBILIDAD_CACHE
- [ ] Estructura de la respuesta del motor de precios al bot y a la web

**Lo que ya está definido y alimenta la Etapa 3:**
- Tabla TARIFAS con todos los campos (Etapa 1)
- Precios actuales cargados (5 cabañas × tipos de día × temporadas)
- Lógica de personas extra ($10.000/noche por persona sobre capacidad base)
- Porcentaje de seña configurable (50%, en CONFIGURACION_GENERAL)
- Año Nuevo y fechas especiales se derivan a EVENTOS_ESPECIALES según Etapa 3 v3.0

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*  
*Siguiente: ver ARQUITECTURA_ETAPA_3_VITA_DELTA.md v3.0 — Motor de Precios*
