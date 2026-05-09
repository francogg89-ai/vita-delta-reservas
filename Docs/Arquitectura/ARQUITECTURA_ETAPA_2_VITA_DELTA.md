# ARQUITECTURA_ETAPA_2_VITA_DELTA.md
# Motor de Disponibilidad — Diseño Completo

**Versión:** 1.1  
**Fecha:** Mayo 2026  
**Estado:** Aprobado — CERRADO  
**Depende de:** ARQUITECTURA_ETAPA_1_VITA_DELTA.md v1.1  
**Autores:** Franco (titular) + Claude (arquitecto)

**Historial de versiones:**
- v1.0 — Motor de disponibilidad completo, escalonamiento, horarios, cache, edge cases
- v1.1 — Ajustes: escalonamiento checkout limitado, OVERRIDES_OPERATIVOS, race conditions documentadas, DISPONIBILIDAD_CACHE simplificada

---

## ÍNDICE

1. Objetivo del motor de disponibilidad
2. Principios del motor
3. Reglas de horarios
4. Motor de escalonamiento *(actualizado en v1.1)*
5. Reglas del último día del bloque
6. Checkin y checkout flexible por el cliente
7. Overrides operativos *(nuevo en v1.1)*
8. Algoritmo completo de disponibilidad
9. Estructura de DISPONIBILIDAD_CACHE *(simplificada en v1.1)*
10. Triggers de recálculo
11. Configuración del motor (todo en CONFIGURACION_GENERAL)
12. Edge cases documentados *(race conditions agregadas en v1.1)*
13. Pendientes para Etapa 3

---

## 1. OBJETIVO DEL MOTOR DE DISPONIBILIDAD

El motor de disponibilidad es el componente que responde a una pregunta simple:

> **¿Puede el huésped X reservar la cabaña Y desde la fecha A hasta la fecha B, y si puede, a qué horario entra y sale?**

Para responder esa pregunta, el motor combina:
- Estado de ocupación de la cabaña (reservas, pre-reservas, bloqueos)
- Reglas de horarios según tipo de día y temporada
- Escalonamiento según carga operativa de Jennifer
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

### 4.1 Concepto

El escalonamiento existe para dar tiempo a Jennifer de limpiar y preparar cabañas cuando hay alta concentración de movimientos el mismo día. Hay dos direcciones:

- **Escalonamiento de check-in:** se retrasa la entrada cuando hay muchos checkouts el mismo día
- **Escalonamiento de check-out:** se adelanta la salida cuando hay muchos check-ins el mismo día

### 4.2 Parámetros configurables

Todos en CONFIGURACION_GENERAL:

| Clave | Valor actual | Descripción |
|---|---|---|
| `escalonamiento_activo` | true | Master switch. Si es false, el motor ignora todo el escalonamiento |
| `escalonamiento_umbral_checkout` | 3 | Número de checkouts simultáneos que activa escalonamiento de checkin |
| `escalonamiento_umbral_checkin` | 3 | Número de check-ins simultáneos que activa escalonamiento de checkout |
| `escalonamiento_minutos` | 45 | Minutos de ajuste por cabaña adicional sobre el umbral |

**Nota crítica:** Para desactivar el escalonamiento completamente (por ejemplo, al contratar más personal), basta con cambiar `escalonamiento_activo = false`. Ningún horario se modifica, el sistema funciona con horarios base puros.

### 4.3 Escalonamiento de check-in (dirección normal)

**Condición de activación:** El número de checkouts a las 10:00hs ese día supera el umbral.

**Lógica:**

```
checkouts_ese_dia = contar reservas con checkout = fecha_checkin_nueva
                    Y hora_checkout = 10:00

SI checkouts_ese_dia <= umbral (3):
    hora_checkin = hora_checkin_base (13:00 o 18:00 según reglas)

SI checkouts_ese_dia = 4 (umbral + 1):
    hora_checkin = hora_checkin_base + 45 min

SI checkouts_ese_dia = 5 (umbral + 2):
    hora_checkin = hora_checkin_base + 90 min

SI checkouts_ese_dia = N (umbral + X):
    hora_checkin = hora_checkin_base + (X * 45 min)
```

**Ejemplos con umbral = 3 y base = 13:00:**

| Checkouts ese día | Check-in calculado | Ajuste |
|---|---|---|
| 1, 2 o 3 | 13:00 | Sin ajuste |
| 4 | 13:45 | +45 min |
| 5 | 14:30 | +90 min |
| 6 | 15:15 | +135 min |

**Ejemplos con domingo (base = 18:00):**

| Checkouts ese día | Check-in calculado | Ajuste |
|---|---|---|
| 1, 2 o 3 | 18:00 | Sin ajuste |
| 4 | 18:45 | +45 min |
| 5 | 19:30 | +90 min |

### 4.4 Escalonamiento de check-out (dirección inversa)

**Condición de activación:** El número de check-ins a las 13:00hs ese día supera el umbral, Y la cabaña nueva tiene checkout ese mismo día.

**Lógica:**

```
checkins_ese_dia = contar reservas con checkin = fecha_checkout_nueva
                   Y hora_checkin = 13:00 (o ajustada)

SI checkins_ese_dia <= umbral (3):
    hora_checkout = hora_checkout_base (10:00 o 16:00 según reglas)

SI checkins_ese_dia = 4 (umbral + 1):
    hora_checkout = hora_checkout_base - 45 min

SI checkins_ese_dia = 5 (umbral + 2):
    hora_checkout = hora_checkout_base - 90 min

SI checkins_ese_dia = N (umbral + X):
    hora_checkout = hora_checkout_base - (X * 45 min)
```

**Ejemplos con umbral = 3 y base = 10:00:**

| Check-ins ese día | Check-out calculado | Ajuste |
|---|---|---|
| 1, 2 o 3 | 10:00 | Sin ajuste |
| 4 | 09:15 | -45 min |
| 5 | 08:30 | -90 min |
| 6 | 07:45 | -135 min |

### 4.5 Aceptación explícita del cliente para checkout adelantado

Cuando el motor calcula un checkout adelantado por escalonamiento, el bot debe:

1. Informar al cliente el horario ajustado antes de crear la pre-reserva
2. Pedir confirmación explícita: *"El checkout ese día sería a las 09:30hs. ¿Lo aceptás?"*
3. Solo si el cliente acepta → crear PRE_RESERVA con el horario ajustado
4. Si el cliente no acepta → informar que ese día no hay disponibilidad con checkout estándar

Esta aceptación queda registrada en el campo `notas` de PRE_RESERVAS y en LOG_CAMBIOS.

---

### 4.6 Interacción entre ambos escalonamientos

Cuando ambas condiciones se activan el mismo día (muchos checkouts Y muchos check-ins), el motor aplica **el escalonamiento según el rol de la cabaña en la nueva reserva**:

- Si la nueva reserva **entra** ese día → aplica escalonamiento de check-in
- Si la nueva reserva **sale** ese día → aplica escalonamiento de check-out
- Nunca se aplican ambos a la misma cabaña en la misma reserva

### 4.7 Límites de seguridad

| Límite | Check-in | Check-out | Clave |
|---|---|---|---|
| Máximo permitido automático | 22:00 | — | `escalonamiento_checkin_max` |
| Mínimo permitido automático | — | 09:00 | `escalonamiento_checkout_min` |
| Máximo adelanto checkout | — | 60 min | `escalonamiento_checkout_max_minutos` |

Si el cálculo supera estos límites:
1. n8n asigna estado `limite_operativo` a esa combinación (cabaña, fecha)
2. Notifica a Franco y Rodrigo por WhatsApp con el detalle
3. El equipo decide manualmente si confirmar, bloquear o escalar
4. Queda registrado en LOG_CAMBIOS

---

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
2. Escalonamiento (reglas de sección 4) → puede modificar el base
3. Preferencia del cliente → puede ajustar dentro del margen resultante
```

El cliente **nunca puede reducir** el horario base calculado para check-in, ni **adelantar** el checkout más allá de lo que el escalonamiento ya determinó.

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
hora_checkout_maxima = MIN(hora_checkout_base, hora_checkout_escalonamiento)
hora_checkout_minima = hora_checkout_min_cliente (configurable, default: 07:00)

El cliente puede elegir cualquier hora entre hora_checkout_minima y hora_checkout_maxima
```

**Ejemplos:**

| Escalonamiento calcula | Cliente pide | Resultado |
|---|---|---|
| 10:00 (sin ajuste) | 10:00 | 10:00 ✓ |
| 10:00 (sin ajuste) | 08:00 | 08:00 ✓ |
| 09:15 (ajustado) | 10:00 | Rechazado → máximo es 09:15 |
| 09:15 (ajustado) | 08:00 | 08:00 ✓ |
| 09:15 (ajustado) | 07:30 | 07:30 ✓ |

### 6.4 Impacto en el escalonamiento

La hora preferida por el cliente **no modifica el cálculo de escalonamiento de otras cabañas**. El motor siempre cuenta checkouts/checkins usando los horarios base calculados, no los horarios elegidos por el cliente.

Esto es importante: si un cliente elige entrar a las 17:00 en vez de 13:45, eso no "libera" tiempo para otra cabaña. El escalonamiento se basa en la carga de trabajo potencial de Jennifer, que se calcula con los horarios base.

### 6.5 Configuración

| Clave | Valor | Descripción |
|---|---|---|
| `checkin_flexible_activo` | true | Si el cliente puede elegir su hora de entrada |
| `checkout_flexible_activo` | true | Si el cliente puede elegir su hora de salida |
| `hora_checkin_max_cliente` | 22:00 | Hora máxima de entrada permitida |
| `hora_checkout_min_cliente` | 07:00 | Hora mínima de salida permitida |

---

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
| `escalonamiento_activo` | `true` / `false` | Activa o desactiva escalonamiento para esas fechas |
| `escalonamiento_umbral_checkout` | Número entero | Sobreescribe umbral de checkouts |
| `escalonamiento_umbral_checkin` | Número entero | Sobreescribe umbral de check-ins |
| `hora_checkin` | `HH:MM` | Fuerza hora de check-in específica |
| `hora_checkout` | `HH:MM` | Fuerza hora de check-out específica |
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

### 7.1 Consulta de disponibilidad para una reserva nueva

```
FUNCIÓN calcular_disponibilidad(id_cabana, fecha_in, fecha_out, personas):

  // PASO 1: Verificar que la cabaña existe y está activa
  cabana = CABAÑAS WHERE id = id_cabana AND activa = true
  SI cabana no existe: RETORNAR { disponible: false, motivo: "cabaña_inactiva" }

  // PASO 2: Verificar bloqueos
  bloqueo = BLOQUEOS WHERE (id_cabana = id_cabana OR id_cabana IS NULL)
                       AND activo = true
                       AND fecha_desde <= fecha_in
                       AND fecha_hasta >= fecha_out
  SI bloqueo existe: RETORNAR { disponible: false, motivo: "bloqueada", detalle: bloqueo.motivo }

  // PASO 3: Verificar ocupación (reservas y pre-reservas)
  // Rango a verificar: desde fecha_in+1 hasta fecha_out-1 (los días intermedios)
  // + verificar que fecha_in no sea checkout de otra reserva con nueva reserva encima
  ocupacion = DISPONIBILIDAD_CACHE WHERE id_cabana = id_cabana
                                    AND fecha BETWEEN fecha_in AND fecha_out
                                    AND estado IN ('ocupada', 'bloqueada')
  SI ocupacion existe:
    // Excepción: fecha_in puede coincidir con checkout de otra reserva (checkout_disponible)
    SI ocupacion.fecha = fecha_in AND ocupacion.estado = 'checkout_disponible':
      CONTINUAR (es válido)
    SINO:
      RETORNAR { disponible: false, motivo: "fechas_ocupadas" }

  // PASO 4: Verificar mínimo de noches
  noches = dias entre fecha_in y fecha_out
  minimo = calcular_minimo_noches(fecha_in, temporada_actual)
  SI noches < minimo:
    RETORNAR { disponible: false, motivo: "minimo_noches", minimo: minimo }

  // PASO 5: Calcular horario de check-in
  hora_checkin_base = calcular_hora_checkin_base(fecha_in)
  hora_checkin_final = aplicar_escalonamiento_checkin(id_cabana, fecha_in, hora_checkin_base)

  // PASO 6: Calcular horario de check-out
  hora_checkout_base = calcular_hora_checkout_base(fecha_out, fecha_in)
  hora_checkout_final = aplicar_escalonamiento_checkout(id_cabana, fecha_out, hora_checkout_base)

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

### 7.2 Función: calcular_hora_checkin_base

```
FUNCIÓN calcular_hora_checkin_base(fecha):

  // ¿Es domingo Y es el primer día de la reserva?
  SI dia_semana(fecha) = domingo:
    RETORNAR hora_checkin_domingo (18:00)

  // Cualquier otro día
  RETORNAR hora_checkin_default (13:00)
```

### 7.3 Función: calcular_hora_checkout_base

```
FUNCIÓN calcular_hora_checkout_base(fecha_checkout, fecha_checkin):

  // ¿Es el último día del bloque?
  SI es_ultimo_dia_bloque(fecha_checkout):
    RETORNAR hora_checkout_ultimo_dia_bloque (16:00)

  // Cualquier otro día
  RETORNAR hora_checkout_default (10:00)
```

### 7.4 Función: aplicar_escalonamiento_checkin

```
FUNCIÓN aplicar_escalonamiento_checkin(id_cabana, fecha, hora_base):

  // ¿Está activo el escalonamiento?
  SI escalonamiento_activo = false:
    RETORNAR hora_base

  // Contar checkouts ese día (excluyendo la cabaña actual)
  checkouts = contar RESERVAS WHERE fecha_checkout = fecha
                                AND hora_checkout = hora_checkout_default
                                AND id_cabana != id_cabana
                                AND estado IN ('confirmada', 'activa')

  SI checkouts <= escalonamiento_umbral_checkout:
    RETORNAR hora_base

  // Calcular ajuste
  cabanas_extra = checkouts - escalonamiento_umbral_checkout
  minutos_extra = cabanas_extra * escalonamiento_minutos
  hora_ajustada = hora_base + minutos_extra

  // Verificar límite de seguridad
  SI hora_ajustada > escalonamiento_checkin_max:
    // No puede absorber más → notificar al equipo
    disparar_notificacion("limite_escalonamiento_alcanzado", fecha, id_cabana)
    RETORNAR null // Disponibilidad bloqueada

  RETORNAR hora_ajustada
```

### 7.5 Función: aplicar_escalonamiento_checkout

```
FUNCIÓN aplicar_escalonamiento_checkout(id_cabana, fecha, hora_base):

  // ¿Está activo el escalonamiento? Verificar override primero
  activo = obtener_valor_con_override('escalonamiento_activo', id_cabana, fecha)
  SI activo = false: RETORNAR hora_base

  // Contar check-ins ese día (excluyendo la cabaña actual)
  checkins = contar RESERVAS WHERE fecha_checkin = fecha
                               AND hora_checkin IN (hora_checkin_default, hora_checkin_domingo)
                               AND id_cabana != id_cabana
                               AND estado IN ('confirmada', 'pre_reserva')

  umbral = obtener_valor_con_override('escalonamiento_umbral_checkin', id_cabana, fecha)
  SI checkins <= umbral: RETORNAR hora_base

  // Calcular ajuste (tramos de 30 min, máximo 60 min = 2 tramos)
  cabanas_extra = MIN(checkins - umbral, 2)  // cap en 2 tramos
  minutos_menos = cabanas_extra * 30         // 30 min por tramo
  hora_ajustada = hora_base - minutos_menos

  // Verificar límite mínimo (09:00)
  SI hora_ajustada < escalonamiento_checkout_min (09:00):
    estado = 'limite_operativo'
    disparar_notificacion("limite_operativo_checkout", fecha, id_cabana)
    RETORNAR { estado: 'limite_operativo' }

  // Marcar que requiere aceptación explícita del cliente
  RETORNAR { hora: hora_ajustada, requiere_aceptacion_cliente: true }
```

---

## 9. ESTRUCTURA DE DISPONIBILIDAD_CACHE

Un registro por combinación (cabaña, fecha). Se mantiene para todas las fechas desde hoy hasta 18 meses adelante.

**Principio:** La cache guarda resultados operativos finales, no inputs ni cálculos intermedios. El bot y la web solo necesitan saber qué puede hacer el huésped, no cómo se llegó a ese resultado.

| Campo | Tipo | Descripción |
|---|---|---|
| id_cabana | Integer | FK → CABAÑAS |
| fecha | Date | YYYY-MM-DD |
| estado | String | `disponible`, `ocupada`, `bloqueada`, `checkout_disponible`, `limite_escalonamiento` |
| hora_checkin_minima | Time | Mínimo permitido considerando escalonamiento |
| hora_checkin_maxima | Time | Máximo permitido (de CONFIGURACION_GENERAL) |
| hora_checkout_maxima | Time | Máximo permitido considerando escalonamiento |
| hora_checkout_minima | Time | Mínimo permitido (de CONFIGURACION_GENERAL) |
| tipo_dia | String | `semana`, `finde`, `feriado`, `ano_nuevo` |
| temporada | String | `alta`, `media`, `baja` |
| es_ultimo_dia_bloque | Boolean | Si aplica la regla de checkout 16:00 |
| minimo_noches | Integer | Mínimo de noches desde este día |
| id_reserva_activa | Integer | FK → RESERVAS si está ocupada |
| id_prereserva_activa | Integer | FK → PRE_RESERVAS si está en proceso |
| recalculado_en | Timestamp | Última vez que se calculó |

**Clave primaria compuesta:** (id_cabana, fecha)

### Estados de la cache

| Estado | Descripción | El bot puede mostrar |
|---|---|---|
| `disponible` | Libre y sin restricciones | Sí |
| `checkout_disponible` | Es el día de checkout de otra reserva — puede ser checkin nuevo | Sí, con nota |
| `ocupada` | Reserva confirmada o pre-reserva activa | No |
| `bloqueada` | Bloqueo manual activo | No |
| `limite_escalonamiento` | El escalonamiento alcanzó el límite de seguridad | No (equipo decide) |

---

## 10. TRIGGERS DE RECÁLCULO

### 9.1 Recálculo parcial (por evento)

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

### 9.2 Recálculo masivo (programado)

Se ejecuta todos los días a las 03:00am. Recalcula todas las combinaciones (cabaña, fecha) para el rango hoy + 18 meses. Sirve para:
- Corregir cualquier inconsistencia acumulada
- Aplicar cambios de configuración que no dispararon recálculo parcial
- Extender el horizonte de la cache

### 9.3 Workflow de recálculo en n8n

```
WORKFLOW: db_recalcular_disponibilidad

INPUT: { id_cabanas: [array], fechas: [array], source_event: string }

PASOS:
  1. Para cada (id_cabana, fecha):
     a. Ejecutar algoritmo completo (sección 7)
     b. Escribir resultado en DISPONIBILIDAD_CACHE
     c. Registrar en LOG_CAMBIOS si hubo cambio de estado
  2. Si alguna fecha alcanzó limite_escalonamiento:
     a. Notificar a Franco y Rodrigo por WhatsApp
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
| `escalonamiento_activo` | true | Master switch del escalonamiento completo |
| `escalonamiento_umbral_checkout` | 3 | Checkouts simultáneos que activan escalonamiento de checkin |
| `escalonamiento_umbral_checkin` | 3 | Check-ins simultáneos que activan escalonamiento de checkout |
| `escalonamiento_minutos` | 45 | Minutos de ajuste por cabaña adicional |
| `escalonamiento_checkin_max` | 22:00 | Límite máximo de check-in por escalonamiento |
| `escalonamiento_checkout_min` | 09:00 | Límite mínimo de checkout por escalonamiento (nunca debajo de esto) |
| `escalonamiento_checkout_max_minutos` | 60 | Máximo minutos de adelanto permitido en checkout |
| `escalonamiento_checkout_tramo_minutos` | 30 | Minutos por tramo en escalonamiento de checkout |

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

**Regla:** Válido. El día 15 tiene estado `checkout_disponible` en DISPONIBILIDAD_CACHE.

**Horarios:**
- Checkout Reserva A: calculado normalmente (10:00 o ajustado)
- Checkin Reserva B: calculado normalmente (13:00 o ajustado)

**Escalonamiento:** El checkout de la Reserva A **cuenta** para el escalonamiento de checkin del día 15. Si ya hay 3 checkouts ese día, la Reserva B entra con +45 min.

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
2. Notifica a Franco con el detalle: "Hay una pre-reserva activa (ID, cliente, fechas) que conflictúa con el bloqueo"
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

### Edge case 5 — Escalonamiento alcanza el límite

**Situación:** Un día tiene 7 cabañas con checkout a las 10:00. La 8va cabaña querría entrar ese día.

**Cálculo:** 7 checkouts > umbral (3). Cabanas extra = 4. Ajuste = 4 × 45 = 180 min = 16:00hs.

**Si 16:00 < escalonamiento_checkin_max (22:00):** Se permite, check-in a las 16:00.

**Si el ajuste supera 22:00:** n8n bloquea esa fecha para esa cabaña y notifica al equipo. El equipo decide manualmente.

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
  → Notificar INMEDIATAMENTE a Franco y Vicky por WhatsApp:
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
---

## 13. PENDIENTES PARA ETAPA 3

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
- Recargo año nuevo (+20%, configurable)

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*  
*Siguiente: ARQUITECTURA_ETAPA_3_VITA_DELTA.md — Motor de Precios*
