# ARQUITECTURA_ETAPA_3_VITA_DELTA.md
# Motor de Precios — Versión Final

**Versión:** 3.0  
**Fecha:** Mayo 2026  
**Estado:** Aprobado — CERRADO  
**Depende de:** ARQUITECTURA_ETAPA_1_VITA_DELTA.md v1.1 / ARQUITECTURA_ETAPA_2_VITA_DELTA.md v1.1  
**Autores:** Franco (titular) + Claude (arquitecto)

**Historial de versiones:**
- v1.0 — Motor de precios inicial
- v2.0 — Reescritura con 7 correcciones: fecha_out exclusive, jerarquía reordenada, multiplicador por noche en bloques, prioridad año nuevo, estadía larga, precios en TARIFAS, descuentos completos
- v3.0 — Versión final: (1) Año Nuevo sale del motor estándar → EVENTOS_ESPECIALES, (2) orden definitivo del techo explicitado, (3) estadía larga como decisión comercial con configuración por temporada, (4) CAPA_DE_CARGOS prevista como expansión futura

---

## CONVENCIÓN FUNDAMENTAL — NOCHES

> **Las noches van desde `fecha_in` inclusive hasta `fecha_out` exclusive.**
>
> `fecha_out` es el día de salida, no una noche adicional.
>
> **Ejemplos:**
> - "28 nov → 3 dic": noches son 28, 29, 30 nov y 1, 2 dic. **5 noches.** El 3 dic es salida.
> - "Martes → Viernes": noches son mar, mié, jue. **3 noches.** Viernes es salida — no hay noche de viernes.
> - "Viernes → Domingo": noches son vie y sáb. **2 noches.** Domingo es salida.

Esta convención aplica en todo el documento, en todos los algoritmos y en todos los ejemplos sin excepción.

---

## ÍNDICE

1. Objetivo del motor de precios
2. Principios del motor
3. Arquitectura general — dos motores
4. Estructura de tipos de cabaña
5. Clasificación de noches (motor estándar)
6. Motor de temporadas y multiplicadores
7. Tabla de precios base — TARIFAS
8. Jerarquía de cálculo (motor estándar)
9. Algoritmo completo — motor estándar
10. Precio marginal y combinaciones
11. Feriados — lógica completa
12. Estadía larga — decisión comercial
13. Personas extra
14. Descuentos y promociones
15. Seña y saldo
16. EVENTOS_ESPECIALES — motor separado
17. Configuración del motor
18. CAPA_DE_CARGOS — expansión futura prevista
19. Edge cases documentados
20. Pendientes para Etapa 4

---

## 1. OBJETIVO DEL MOTOR DE PRECIOS

El motor de precios responde a una pregunta simple:

> **¿Cuánto cuesta reservar la cabaña Y desde la fecha A hasta la fecha B para N personas?**

Para responderla, el sistema determina primero si la reserva intersecta un evento especial. Si lo hace, deriva al motor de eventos especiales. Si no, usa el motor estándar.

El resultado final siempre incluye:
- Precio total de la reserva
- Monto de la seña
- Saldo a pagar al llegar
- Desglose por tramos para transparencia con el cliente

---

## 2. PRINCIPIOS DEL MOTOR

1. **Los precios viven en TARIFAS, no en CONFIGURACION_GENERAL ni en código.** Toda modificación de precios se hace en la tabla TARIFAS.

2. **CONFIGURACION_GENERAL contiene solo reglas, porcentajes, switches y parámetros operativos.** Nunca precios de alojamiento.

3. **El tipo de cabaña determina el precio, no la cabaña específica.** Agregar una cabaña nueva no requiere nuevas tarifas si el tipo ya existe.

4. **La jerarquía de bloques tiene prioridad sobre el cálculo noche a noche.** Si la reserva califica para semana completa, se aplica ese precio directamente.

5. **El multiplicador de temporada se aplica por noche, siempre.** Para bloques con precio fijo: distribuir el precio base entre las noches del bloque, multiplicar cada noche por su factor de temporada y sumar. Esto resuelve correctamente las reservas que cruzan temporadas.

6. **fecha_out es siempre exclusive.** Las noches van desde fecha_in inclusive hasta fecha_out exclusive.

7. **Orden definitivo de cálculo:**
   1. Calcular alojamiento base (motor estándar o motor evento especial)
   2. Aplicar regla de techo sobre el alojamiento base
   3. Aplicar descuentos y promociones
   4. Agregar extras por personas
   5. Redondear al millar
   6. Calcular seña y saldo

   **El techo protege la estructura tarifaria del alojamiento base.** Los descuentos son estrategia comercial posterior. Los extras son costos reales adicionales que no entran dentro del techo.

8. **Eventos especiales tienen su propio motor.** Año Nuevo, Carnaval, Semana Santa y cualquier fecha con lógica comercial distinta al motor estándar se manejan en EVENTOS_ESPECIALES.

9. **Toda modificación de precios queda en LOG_CAMBIOS.** Con timestamp, valor anterior y valor nuevo.

---

## 3. ARQUITECTURA GENERAL — DOS MOTORES

```
FUNCIÓN calcular_precio(tipo_cabana, fecha_in, fecha_out, personas):

  // PASO 0: ¿La reserva intersecta un evento especial?
  evento = buscar_evento_especial(fecha_in, fecha_out)

  SI evento existe Y evento.activa = true:
    RETORNAR motor_evento_especial(evento, tipo_cabana, fecha_in, fecha_out, personas)
  SINO:
    RETORNAR motor_estandar(tipo_cabana, fecha_in, fecha_out, personas)
```

El motor estándar cubre toda la lógica de precios habitual (secciones 5-15). El motor de eventos especiales se describe en la sección 16.

---

## 4. ESTRUCTURA DE TIPOS DE CABAÑA

El campo `tipo` en CABAÑAS es texto libre. El sistema soporta cualquier tipo nuevo sin modificar código — solo requiere crear las filas correspondientes en TARIFAS.

### Tipos actuales

| Tipo | Cabañas | Cap. base | Cap. máx |
|---|---|---|---|
| `grande` | Bamboo, Madre Selva, Arrebol | 3 personas | 5 personas |
| `chica` | Guatemala, Tokio | 2 personas | 4 personas |

### Agregar un tipo nuevo

1. Agregar la cabaña en CABAÑAS con el `tipo` nuevo
2. Crear todas las filas de TARIFAS para ese tipo
3. El motor lo detecta automáticamente

---

## 5. CLASIFICACIÓN DE NOCHES (MOTOR ESTÁNDAR)

Esta función se ejecuta solo cuando no hay evento especial activo. Recibe el rango y devuelve el tipo de cada noche.

### 5.1 Tipos de noche en el motor estándar

| Tipo | Descripción | Prioridad |
|---|---|---|
| `feriado` | Día en tabla FERIADOS (activo=true) | 1 |
| `finde` | Viernes o sábado | 2 |
| `semana` | Cualquier otro día | 3 — Default |

> **Nota:** Esta función solo se ejecuta cuando el motor estándar ya verificó que la reserva no intersecta ningún EVENTO_ESPECIAL.

### 5.2 Algoritmo de clasificación

```
FUNCIÓN clasificar_noches(fecha_in, fecha_out):
  // Esta función solo se llama desde el motor estándar
  // Si hay evento especial, no se llega aquí
  noches = []
  cur = fecha_in

  MIENTRAS cur < fecha_out:  // exclusive

    // PRIORIDAD 1: Feriado
    SI existe_en_FERIADOS(fecha=cur, activo=true):
      tipo = 'feriado'

    // PRIORIDAD 2: Fin de semana
    SINO SI dia_semana(cur) EN [viernes, sabado]:
      tipo = 'finde'

    // PRIORIDAD 3: Semana (default)
    SINO:
      tipo = 'semana'

    noches.append({ fecha: cur, tipo: tipo })
    cur = cur + 1 día

  RETORNAR noches
```

### 5.3 Ejemplos de clasificación

| fecha_in | fecha_out | Noches clasificadas | Total |
|---|---|---|---|
| Mar 10 jun | Vie 13 jun | Mar(sem), Mié(sem), Jue(sem) | 3 — Vie es salida |
| Vie 13 jun | Dom 15 jun | Vie(finde), Sáb(finde) | 2 — Dom es salida |
| Dom 7 jun | Vie 12 jun | Dom(sem), Lun(sem), Mar(sem), Mié(sem), Jue(sem) | 5 — Vie es salida |
| Lun 1 jun | Lun 8 jun | Lun,Mar,Mié,Jue(sem), Vie,Sáb(finde), Dom(sem) | 7 |

*Estas clasificaciones aplican solo dentro del motor estándar. Si fecha_in o fecha_out intersectan un EVENTO_ESPECIAL, la reserva se deriva antes de llegar a esta función.*

---

## 6. MOTOR DE TEMPORADAS Y MULTIPLICADORES

### 6.1 Tabla TEMPORADAS

| Campo | Tipo | Descripción |
|---|---|---|
| id_temporada | Integer | ID único |
| nombre | String | "Temporada alta verano 2026" |
| fecha_desde | Date | Inicio del rango (inclusive) |
| fecha_hasta | Date | Fin del rango (inclusive) |
| multiplicador | Decimal | 1.00=base, 1.20=+20%, 0.85=-15% |
| activa | Boolean | |
| created_at | Timestamp | |

### 6.2 Temporadas iniciales sugeridas

| Nombre | Desde | Hasta | Multiplicador |
|---|---|---|---|
| Temporada media | 2026-05-01 | 2026-11-30 | 1.00 |
| Temporada alta verano | 2026-12-01 | 2027-02-28 | 1.20 |
| Temporada media | 2027-03-01 | 2027-06-30 | 1.00 |
| Vacaciones invierno | 2027-07-05 | 2027-07-20 | 1.20 |
| Temporada baja | 2027-07-21 | 2027-11-30 | 0.85 |
| Temporada alta verano | 2027-12-01 | 2028-02-28 | 1.20 |

### 6.3 Aplicación del multiplicador en bloques

El multiplicador siempre se aplica **por noche**, incluso en bloques con precio fijo.

```
FUNCIÓN aplicar_multiplicador_bloque(precio_base_bloque, noches):
  precio_por_noche_base = precio_base_bloque / noches.length

  total = 0
  PARA CADA noche EN noches:
    mult = obtener_multiplicador_temporada(noche.fecha)
    total += precio_por_noche_base × mult

  RETORNAR total
```

**Ejemplo — Semana completa que cruza inicio de temporada alta:**
```
Reserva: lunes 29 nov → lunes 6 dic (7 noches, fecha_out exclusive)
Noches: 29, 30 nov (×1.00) + 1, 2, 3, 4, 5 dic (×1.20)
Base semana completa: $800.000 / 7 = $114.286 por noche

  29 nov ×1.00 = $114.286
  30 nov ×1.00 = $114.286
  01 dic ×1.20 = $137.143
  02 dic ×1.20 = $137.143
  03 dic ×1.20 = $137.143
  04 dic ×1.20 = $137.143
  05 dic ×1.20 = $137.143

Total: $1.014.286 → $1.014.000
```

### 6.4 Redondeo

Todos los precios finales se redondean al millar más cercano.
Configurable: `precio_redondeo_base = 1000`

---

## 7. TABLA DE PRECIOS BASE — TARIFAS

Todos los precios viven en TARIFAS. CONFIGURACION_GENERAL no contiene precios de alojamiento.

### 7.1 Estructura de TARIFAS

| Campo | Tipo | Descripción |
|---|---|---|
| id_tarifa | Integer | ID único |
| tipo_cabana | String | `grande`, `chica`, o tipo futuro |
| concepto | String | Identificador del precio |
| precio | Number | Precio base en ARS (temporada media, mult=1.00) |
| descripcion | String | Descripción legible |
| activa | Boolean | |
| valida_desde | Date | Null = siempre |
| valida_hasta | Date | Null = siempre |
| created_at | Timestamp | |

### 7.2 Conceptos del motor estándar

| concepto | Descripción |
|---|---|
| `semana_1` | 1 noche de semana |
| `semana_2` | 2 noches de semana (precio total del bloque) |
| `semana_3` | 3 noches de semana (precio total del bloque) |
| `semana_4` | 4 noches de semana (precio total del bloque) |
| `semana_5` | 5 noches de semana (precio total del bloque) |
| `semana_marginal_6plus` | Precio por noche adicional desde la 6ta de semana |
| `finde_1_noche` | 1 noche de finde (vie→sáb o sáb→dom) |
| `finde_completo` | Finde completo vie→dom (2 noches) |
| `feriado_aislado` | 1 feriado no pegado a finde |
| `feriado_adicional` | Cada noche de feriado sobre el finde |
| `semana_completa` | 7 noches consecutivas (cualquier día de inicio) |
| `semana_adicional` | Cada semana completa después de la primera |
| `marginal_fijo_finde_semana` | Noche de semana en combinación con finde completo |
| `extra_persona_noche` | Cargo por persona sobre capacidad base, por noche |

**Nota:** Las noches de 31 dic y 1 ene no tienen filas en TARIFAS. Sus precios viven exclusivamente en PAQUETES_EVENTO dentro de EVENTOS_ESPECIALES.

### 7.3 Precios base actuales (temporada media, multiplicador 1.00)

#### Cabañas grandes

| concepto | Precio base |
|---|---|
| `semana_1` | $150.000 |
| `semana_2` | $280.000 |
| `semana_3` | $400.000 |
| `semana_4` | $500.000 |
| `semana_5` | $550.000 |
| `semana_marginal_6plus` | $50.000/noche |
| `finde_1_noche` | $200.000 |
| `finde_completo` | $350.000 |
| `feriado_aislado` | $200.000 |
| `feriado_adicional` | $160.000/noche |
| `semana_completa` | $800.000 |
| `semana_adicional` | $600.000 |
| `marginal_fijo_finde_semana` | $100.000/noche |
| `extra_persona_noche` | $10.000 |

#### Cabañas chicas

| concepto | Precio base |
|---|---|
| `semana_1` | $130.000 |
| `semana_2` | $240.000 |
| `semana_3` | $340.000 |
| `semana_4` | $400.000 |
| `semana_5` | $450.000 |
| `semana_marginal_6plus` | $50.000/noche |
| `finde_1_noche` | $180.000 |
| `finde_completo` | $300.000 |
| `feriado_aislado` | $180.000 |
| `feriado_adicional` | $140.000/noche |
| `semana_completa` | $700.000 |
| `semana_adicional` | $500.000 |
| `marginal_fijo_finde_semana` | $60.000/noche |
| `extra_persona_noche` | $10.000 |

---

## 8. JERARQUÍA DE CÁLCULO (MOTOR ESTÁNDAR)

El motor aplica niveles en orden estricto. El primer nivel que aplica determina el método.

```
NIVEL 1 — Estadía larga (28+ noches)
  ¿total_noches >= 28?
  → Ver Sección 12 para lógica completa y configuración por temporada

NIVEL 2 — Semanas completas (7 a 27 noches)
  ¿total_noches >= 7 Y < 28?
  → FLOOR(noches/7) semanas al precio correspondiente
  → Días sobrantes (noches MOD 7): calcular con reglas de niveles 3-8

NIVEL 3 — Finde completo + feriados (sin noches de semana pura)
  ¿tiene_finde_completo Y n_feriado > 0 Y n_semana = 0 Y total < 7?
  → Precio fijo según tabla finde + feriados

NIVEL 4 — Finde completo solo
  ¿tiene_finde_completo Y total = 2 Y n_semana = 0 Y n_feriado = 0?
  → finde_completo

NIVEL 5 — Finde completo + noches de semana extra
  ¿tiene_finde_completo Y n_semana > 0 Y total < 7?
  → finde_completo + (n_semana × marginal_fijo_finde_semana)
  → + feriados adicionales si los hay

NIVEL 6 — Feriado aislado (no pegado a finde completo)
  ¿n_feriado > 0 Y NOT tiene_finde_completo?
  → Cada feriado: feriado_aislado
  → Noches de semana del mismo rango: precio semana según cantidad

NIVEL 7 — Solo noches de semana pura
  ¿n_semana > 0 Y n_finde = 0 Y n_feriado = 0?
  → semana_N según cantidad

NIVEL 8 — Una sola noche de finde
  ¿total = 1 Y n_finde = 1?
  → finde_1_noche

REGLA DE TECHO — Aplica inmediatamente después del cálculo base:
  SI alojamiento_base > semana_completa × semanas_equivalentes:
    alojamiento_base = semana_completa × semanas_equivalentes
  → Los descuentos y extras se aplican DESPUÉS del techo (ver Sección 9.1)
```

---

## 9. ALGORITMO COMPLETO — MOTOR ESTÁNDAR

### 9.1 Función principal con orden definitivo

```
FUNCIÓN motor_estandar(tipo_cabana, fecha_in, fecha_out, personas):

  // PASO 1: Clasificar noches (fecha_out EXCLUSIVE)
  noches = clasificar_noches(fecha_in, fecha_out)

  // PASO 2: Determinar nivel de jerarquía
  nivel = determinar_nivel(noches)

  // PASO 3: Calcular alojamiento base
  alojamiento_base = calcular_por_nivel(nivel, noches, tipo_cabana)

  // PASO 4: Aplicar multiplicadores de temporada por noche
  alojamiento_con_temporada = aplicar_multiplicador_bloque(alojamiento_base, noches)

  // PASO 5: Aplicar regla de techo sobre alojamiento
  // El techo protege la estructura tarifaria base.
  // Los descuentos y extras se aplican DESPUÉS del techo.
  alojamiento_final = aplicar_techo(alojamiento_con_temporada, noches, tipo_cabana)

  // PASO 6: Aplicar descuentos y promociones
  precio_con_descuento = aplicar_descuentos(alojamiento_final, fecha_in, fecha_out, tipo_cabana)

  // PASO 7: Agregar extras por personas
  // Los extras no entran dentro del techo — son costos reales adicionales.
  extra = calcular_extra_personas(personas, tipo_cabana, noches.length)

  // PASO 8: Redondear al millar
  precio_final = redondear(precio_con_descuento + extra)

  // PASO 9: Calcular seña y saldo
  sena  = redondear(precio_final × sena_porcentaje / 100)
  saldo = precio_final - sena

  RETORNAR {
    precio_total: precio_final,
    sena:         sena,
    saldo:        saldo,
    noches_count: noches.length,
    desglose:     generar_desglose(noches, alojamiento_base, extra)
  }
```

### 9.2 Función: determinar_nivel

```
FUNCIÓN determinar_nivel(noches):
  total     = noches.length
  n_semana  = contar(noches, tipo='semana')
  n_finde   = contar(noches, tipo='finde')
  n_feriado = contar(noches, tipo='feriado')
  // Las noches de 31 dic y 1 ene nunca llegan a esta función.
  // Son interceptadas en PASO 0 y gestionadas por EVENTOS_ESPECIALES.
  tiene_finde_completo = tiene_viernes_y_sabado_consecutivos(noches)

  SI total >= 28:                                        RETORNAR 'estadia_larga'
  SI total >= 7:                                         RETORNAR 'semanas'
  SI tiene_finde_completo Y n_feriado > 0
     Y n_semana = 0:                                    RETORNAR 'finde_con_feriados'
  SI tiene_finde_completo Y total = 2
     Y n_semana = 0 Y n_feriado = 0:                   RETORNAR 'finde_completo'
  SI tiene_finde_completo Y n_semana > 0:               RETORNAR 'finde_con_extras'
  SI n_feriado > 0 Y NOT tiene_finde_completo:          RETORNAR 'feriado_aislado'
  SI n_semana > 0 Y n_finde = 0 Y n_feriado = 0:       RETORNAR 'semana_pura'
  SI total = 1 Y n_finde = 1:                           RETORNAR 'finde_1_noche'
  RETORNAR 'semana_pura'
```

### 9.3 Función: calcular_por_nivel

```
FUNCIÓN calcular_por_nivel(nivel, noches, tipo):
  T = precios_de_TARIFAS(tipo)

  SEGÚN nivel:

    CASO 'estadia_larga':
      // Ver Sección 12 para lógica completa
      RETORNAR calcular_estadia_larga(noches, tipo)

    CASO 'semanas':
      semanas   = FLOOR(noches.length / 7)
      sobrantes = noches.length MOD 7
      precio = T.semana_completa + MAX(0, semanas-1) × T.semana_adicional
      SI sobrantes > 0:
        noches_sob = ultimas_N(noches, sobrantes)
        precio += calcular_sobrantes(noches_sob, tipo)
      RETORNAR precio

    CASO 'finde_con_feriados':
      // Solo feriados del motor estándar (no año nuevo, que va por EVENTOS_ESPECIALES)
      n_fer = contar(noches, tipo='feriado')
      RETORNAR T.finde_completo + n_fer × T.feriado_adicional

    CASO 'finde_completo':
      RETORNAR T.finde_completo

    CASO 'finde_con_extras':
      n_sem = contar(noches, tipo='semana')
      n_fer = contar(noches, tipo='feriado')
      RETORNAR T.finde_completo
             + n_sem × T.marginal_fijo_finde_semana
             + n_fer × T.feriado_adicional

    CASO 'feriado_aislado':
      // Solo feriados del motor estándar (no año nuevo)
      n_fer = contar(noches, tipo='feriado')
      n_sem = contar(noches, tipo='semana')
      precio = n_fer × T.feriado_aislado
      SI n_sem <= 5: precio += T['semana_' + n_sem]
      SINO:          precio += T.semana_5 + (n_sem-5) × T.semana_marginal_6plus
      RETORNAR precio

    CASO 'semana_pura':
      n = noches.length
      SI n <= 5: RETORNAR T['semana_' + n]
      RETORNAR T.semana_5 + (n-5) × T.semana_marginal_6plus

    CASO 'finde_1_noche':
      RETORNAR T.finde_1_noche
```

### 9.4 Función: aplicar_techo

```
FUNCIÓN aplicar_techo(alojamiento_con_temporada, noches, tipo):
  T = precios_de_TARIFAS(tipo)

  // Calcular el precio techo equivalente para la cantidad de noches
  semanas_equiv = FLOOR(noches.length / 7)
  SI semanas_equiv > 0:
    precio_techo = T.semana_completa
    SI semanas_equiv > 1:
      precio_techo += (semanas_equiv - 1) × T.semana_adicional
    // Aplicar multiplicador de temporada al techo también
    precio_techo = aplicar_multiplicador_bloque(precio_techo, noches)

    SI alojamiento_con_temporada > precio_techo:
      RETORNAR precio_techo

  RETORNAR alojamiento_con_temporada
```

### 9.5 Función: calcular_sobrantes

```
FUNCIÓN calcular_sobrantes(noches_sobrantes, tipo):
  // Reclasificar sobrantes y aplicar jerarquía de niveles 3-8
  nivel_sob = determinar_nivel(noches_sobrantes)
  RETORNAR calcular_por_nivel(nivel_sob, noches_sobrantes, tipo)
```

---

## 10. PRECIO MARGINAL Y COMBINACIONES

### 10.1 Precios marginales por noche de semana

| Noche | Grande | Chica |
|---|---|---|
| 1ra | $150.000 | $130.000 |
| 2da | $130.000 | $110.000 |
| 3ra | $120.000 | $100.000 |
| 4ta | $100.000 | $60.000 |
| 5ta | $50.000 | $50.000 |
| 6ta+ | $50.000 | $50.000 |

### 10.2 Precio marginal fijo para combinaciones con finde

Noches de semana combinadas con finde completo (sin llegar a 7 noches) entran al precio de la **4ta noche**:

| Tipo | Precio fijo |
|---|---|
| Grande | $100.000/noche |
| Chica | $60.000/noche |

### 10.3 Ejemplos completos verificados (grandes, temporada media)

**A — Martes → Viernes (3 noches de semana):**
```
Noches: mar, mié, jue (vie es salida)
Nivel: semana_pura → semana_3 = $400.000
```

**B — Viernes → Domingo (finde completo):**
```
Noches: vie(finde), sáb(finde) (dom es salida)
Nivel: finde_completo = $350.000
```

**C — Miércoles → Domingo (3 noches semana + finde):**
```
Noches: mié(sem), jue(sem), vie(finde), sáb(finde) — 4 noches
Nivel: finde_con_extras
Precio: $350.000 + 2 × $100.000 = $550.000
Techo ($800.000): no aplica
```

**D — Lunes → Lunes siguiente (7 noches, semana completa):**
```
Noches: lun,mar,mié,jue(sem), vie,sáb(finde), dom(sem) — 7 noches
Nivel: semanas → semana_completa = $800.000
```

**E — Lunes → Jueves semana siguiente (10 noches):**
```
Noches: 10 → 1 semana + 3 sobrantes (lun,mar,mié)
Semana: $800.000 + sobrantes semana_3: $400.000 = $1.200.000
```

**F — 14 noches (2 semanas):**
```
Primera semana: $800.000 + Segunda: $600.000 = $1.400.000
```

**G — Viernes → Lunes feriado (finde + 1 feriado):**
```
Noches: vie(finde), sáb(finde), dom(feriado) — lunes es salida
Nivel: finde_con_feriados
Precio: $350.000 + $160.000 = $510.000
```

**H — Miércoles feriado → Jueves (1 noche feriado aislado):**
```
Noches: mié(feriado) — jueves es salida
Nivel: feriado_aislado = $200.000
```

---

## 11. FERIADOS — LÓGICA COMPLETA

### 11.1 Tabla de precios con feriados (grandes)

| Combinación | Noches | Precio base |
|---|---|---|
| 1 feriado aislado | 1 | $200.000 |
| Finde completo | 2 | $350.000 |
| Finde + 1 feriado | 3 | $510.000 |
| Finde + 2 feriados | 4 | $670.000 |
| Finde + N feriados | N+2 | $350.000 + (N × $160.000) |
| Semana completa (con o sin feriados) | 7 | $800.000 |

### 11.2 Tabla de precios con feriados (chicas)

| Combinación | Noches | Precio base |
|---|---|---|
| 1 feriado aislado | 1 | $180.000 |
| Finde completo | 2 | $300.000 |
| Finde + 1 feriado | 3 | $440.000 |
| Finde + 2 feriados | 4 | $580.000 |
| Finde + N feriados | N+2 | $300.000 + (N × $140.000) |
| Semana completa (con o sin feriados) | 7 | $700.000 |

### 11.3 Semana completa con feriados

Una semana completa vale $800.000 / $700.000 **siempre**, independientemente de si incluye feriados dentro. Los feriados dentro de una semana completa no generan cargo adicional.

---

## 12. ESTADÍA LARGA — DECISIÓN COMERCIAL

### 12.1 Definición

Una estadía larga es cualquier reserva de **28 o más noches** consecutivas.

### 12.2 Lógica de cálculo

```
FUNCIÓN calcular_estadia_larga(noches, tipo, temporada_activa):
  T = precios_de_TARIFAS(tipo)

  // Verificar si la estadía larga está permitida en esta temporada
  SI NOT estadia_larga_permitida(temporada_activa):
    RETORNAR error('estadia_larga_no_disponible_temporada')

  semanas   = FLOOR(noches.length / 7)
  sobrantes = noches.length MOD 7

  precio = T.semana_completa + MAX(0, semanas-1) × T.semana_adicional

  // ¿Se cobran los sobrantes en esta temporada?
  SI estadia_larga_cobra_sobrantes(temporada_activa) Y sobrantes > 0:
    noches_sob = ultimas_N(noches, sobrantes)
    precio += calcular_sobrantes(noches_sob, tipo)
  // Si no cobra sobrantes → los días sobrantes van incluidos sin costo adicional

  RETORNAR precio
```

### 12.3 Decisión comercial — por qué los sobrantes no se cobran

**En temporada media y baja, los días sobrantes sobre semanas completas no se cobran.** Esta no es una omisión ni un error — es una decisión comercial deliberada orientada a:

- **Ocupación sostenida:** una cabaña ocupada durante semanas reduce el riesgo de períodos vacíos.
- **Menor rotación:** menos cambios de huésped implica menos coordinación operativa.
- **Menor carga de limpieza:** menos checkouts y checkins por período.
- **Estabilidad de ingresos:** ingresos predecibles durante la temporada baja.
- **Atractivo competitivo:** facilita el home office, retiros, coworking y estancias extendidas.

### 12.4 Configuración por temporada

En temporada alta puede no ser conveniente permitir estadías largas porque la demanda es mayor, la rotación tiene más valor y bloquear una cabaña durante semanas puede no ser óptimo comercialmente.

Las siguientes configuraciones quedan **previstas** en CONFIGURACION_GENERAL para ser activadas cuando sea necesario:

| Clave | Valor default | Descripción |
|---|---|---|
| `estadia_larga_permitida_temp_alta` | true | Si se permiten estadías largas en temporada alta |
| `estadia_larga_max_noches_temp_alta` | null | Máximo de noches en temp. alta (null = sin límite) |
| `estadia_larga_cobra_sobrantes_temp_alta` | false | Si los sobrantes se cobran en temp. alta |
| `estadia_larga_permitida_temp_media` | true | Si se permiten estadías largas en temporada media |
| `estadia_larga_cobra_sobrantes_temp_media` | false | Si los sobrantes se cobran en temp. media |
| `estadia_larga_permitida_temp_baja` | true | Si se permiten en temporada baja |
| `estadia_larga_cobra_sobrantes_temp_baja` | false | Si los sobrantes se cobran en temp. baja |

**Ejemplo de uso:** Para temporada alta de enero/febrero, se podría configurar:
```
estadia_larga_max_noches_temp_alta = 14
estadia_larga_cobra_sobrantes_temp_alta = true
```
Resultado: en temporada alta, máximo 2 semanas y los sobrantes sí se cobran. En el resto del año, la lógica estándar sin límite y sin cobro de sobrantes.

---

## 13. PERSONAS EXTRA

### 13.1 Regla

El precio base incluye la capacidad base del tipo. Cada persona adicional genera cargo por noche. Este cargo **no** se multiplica por el factor de temporada y **no** entra dentro de la regla de techo — es un costo real adicional.

| Tipo | Cap. base | Precio extra/persona/noche |
|---|---|---|
| Grande | 3 | $10.000 |
| Chica | 2 | $10.000 |

### 13.2 Cálculo

```
FUNCIÓN calcular_extra_personas(personas, tipo_cabana, n_noches):
  cap_base     = TARIFAS[tipo_cabana]['capacidad_base']
  precio_extra = TARIFAS[tipo_cabana]['extra_persona_noche']
  extras = MAX(0, personas - cap_base)
  RETORNAR extras × precio_extra × n_noches
```

### 13.3 Ejemplos

| Tipo | Personas | Noches | Extra |
|---|---|---|---|
| Grande | 3 | 2 | $0 |
| Grande | 5 | 3 | $60.000 (2×$10k×3) |
| Chica | 4 | 5 | $100.000 (2×$10k×5) |

---

## 14. DESCUENTOS Y PROMOCIONES

### 14.1 Tabla DESCUENTOS

| Campo | Tipo | Descripción |
|---|---|---|
| id_descuento | Integer | ID único |
| nombre | String | "Descuento cliente frecuente" |
| tipo | String | `porcentaje`, `monto_fijo`, `noche_gratis` |
| valor | Decimal | % o monto según tipo |
| aplica_a | String | `todas`, `grande`, `chica`, tipo específico |
| aplica_sobre | String | `alojamiento`, `extras`, `total` |
| fecha_desde | Date | Inicio de vigencia |
| fecha_hasta | Date | Fin de vigencia |
| codigo | String | Código del cliente. Null = automático |
| usos_maximos | Integer | Null = ilimitado |
| usos_actuales | Integer | Contador con control de concurrencia |
| minimo_noches | Integer | Mínimo de noches para aplicar |
| monto_minimo | Number | Monto mínimo de reserva para aplicar |
| prioridad | Integer | Orden si hay varios (menor = primero) |
| combinable | Boolean | Si puede combinarse con otros descuentos |
| requiere_aprobacion | Boolean | Si requiere validación manual |
| activo | Boolean | |
| source_event | String | |
| created_at | Timestamp | |

### 14.2 Orden de aplicación

Los descuentos se aplican **después del techo** y **antes de sumar extras**.

```
1. alojamiento_base calculado
2. Techo aplicado → alojamiento_final
3. Descuentos ordenados por prioridad (ASC)
4. Para cada descuento:
   a. Verificar elegibilidad
   b. Si combinable=false y ya hay otro aplicado → saltar
   c. Aplicar sobre aplica_sobre (alojamiento, extras o total)
5. Sumar extra personas
6. Redondear
```

### 14.3 Control de concurrencia en usos_actuales

Workflow secuencial con concurrencia = 1. Mismo patrón que reservas (Etapa 2).

---

## 15. SEÑA Y SALDO

### 15.1 Cálculo

```
sena  = redondear(precio_final × sena_porcentaje / 100)
saldo = precio_final - sena
```

### 15.2 Desglose para el cliente

```
Ejemplo — Finde completo, 3 personas (base grandes), temporada media:
  Finde completo (vie 13 → dom 15 jun, 2 noches): $350.000
  Temporada media (×1.00):                        $350.000
  Techo: no aplica
  Descuentos: ninguno
  Personas (3, sin extra sobre base):             $0
  ─────────────────────────────────────────────
  Total:                                          $350.000
  Seña (50%):                                    $175.000
  Saldo al llegar (efectivo):                    $175.000
```

---

## 16. EVENTOS_ESPECIALES — MOTOR SEPARADO

### 16.1 Por qué existe este motor

Ciertos períodos tienen lógica comercial completamente distinta al motor estándar:
- La demanda y los patrones de reserva son diferentes
- Los paquetes no encajan en la jerarquía estándar
- Los precios, mínimos y restricciones son propios de cada evento
- Mezclarlos con el motor estándar genera ambigüedad y casos especiales que complican la lógica

Año Nuevo es el caso más claro: alguien puede querer solo el 31, solo el 1, el 30+31, el 31+1, o el 30+31+1. Ninguna de estas combinaciones encaja limpiamente en la jerarquía estándar.

### 16.2 Tabla EVENTOS_ESPECIALES

| Campo | Tipo | Descripción |
|---|---|---|
| id_evento | Integer | ID único |
| nombre | String | "Año Nuevo 2026/2027", "Carnaval 2027" |
| fecha_desde | Date | Inicio del evento (inclusive) |
| fecha_hasta | Date | Fin del evento (inclusive) |
| modo_precio | String | `paquetes_fijos`, `precio_por_noche`, `consultar` |
| reglas_especiales | JSON | Reglas propias del evento (mínimos, restricciones, etc.) |
| activa | Boolean | |
| source_event | String | |
| created_at | Timestamp | |

### 16.3 Tabla PAQUETES_EVENTO

Para eventos con `modo_precio = 'paquetes_fijos'`:

| Campo | Tipo | Descripción |
|---|---|---|
| id_paquete | Integer | ID único |
| id_evento | Integer | FK → EVENTOS_ESPECIALES |
| nombre | String | "31 solo", "30+31+1", "Finde completo año nuevo" |
| fecha_in | Date | Fecha de checkin del paquete |
| fecha_out | Date | Fecha de checkout del paquete (exclusive) |
| tipo_cabana | String | `grande`, `chica`, `todas` |
| precio | Number | Precio fijo del paquete |
| minimo_noches | Integer | Mínimo obligatorio |
| activo | Boolean | |

### 16.4 Paquetes de Año Nuevo (ejemplo de carga)

Año Nuevo 2026/2027 — Cabañas grandes:

| Paquete | fecha_in | fecha_out | Precio |
|---|---|---|---|
| Solo 31 | 31 dic | 1 ene | A definir |
| 30+31 | 30 dic | 1 ene | A definir |
| 31+1 | 31 dic | 2 ene | A definir |
| 30+31+1 | 30 dic | 2 ene | A definir |

*Los precios de estos paquetes se cargan en PAQUETES_EVENTO antes de cada temporada.*

### 16.5 Motor de eventos especiales

```
FUNCIÓN motor_evento_especial(evento, tipo_cabana, fecha_in, fecha_out, personas):

  SI evento.modo_precio = 'paquetes_fijos':
    paquete = buscar_paquete(evento.id, tipo_cabana, fecha_in, fecha_out)
    SI paquete no existe:
      RETORNAR error('paquete_no_disponible', evento.nombre)
    alojamiento_base = paquete.precio

  SI evento.modo_precio = 'precio_por_noche':
    // Lógica propia del evento, definida en reglas_especiales
    alojamiento_base = calcular_precio_evento(evento, tipo_cabana, fecha_in, fecha_out)

  SI evento.modo_precio = 'consultar':
    // El sistema no calcula — deriva a revisión manual
    RETORNAR { requiere_consulta: true, mensaje: "Este período requiere consulta directa" }

  // El resto del flujo es igual al motor estándar
  extra         = calcular_extra_personas(personas, tipo_cabana, noches(fecha_in, fecha_out))
  precio_final  = redondear(alojamiento_base + extra)
  sena          = redondear(precio_final × sena_porcentaje / 100)
  saldo         = precio_final - sena

  RETORNAR { precio_total: precio_final, sena: sena, saldo: saldo }
```

### 16.6 Ejemplos de eventos futuros previstos

| Evento | Modo | Descripción |
|---|---|---|
| Año Nuevo | paquetes_fijos | Paquetes predefinidos por combinación de noches |
| Carnaval | paquetes_fijos | Finde largo con precio propio |
| Semana Santa | paquetes_fijos | Finde largo con precio propio |
| Evento privado | consultar | Requiere acuerdo manual |
| Fechas especiales futuras | precio_por_noche | Precio propio por noche |

---

## 17. CONFIGURACIÓN DEL MOTOR

Solo reglas, porcentajes y parámetros operativos. **Ningún precio de alojamiento.**

### General

| Clave | Valor default | Descripción |
|---|---|---|
| `sena_porcentaje` | 50 | % de seña sobre el total |
| `precio_redondeo_base` | 1000 | Redondear al millar más cercano |
| `precio_descuento_minimo` | 10000 | Precio mínimo permitido post-descuento |

### Estadía larga (ver Sección 12.4 para detalle completo)

| Clave | Valor default | Descripción |
|---|---|---|
| `estadia_larga_minimo_noches` | 28 | Mínimo noches para nivel estadía larga |
| `estadia_larga_permitida_temp_alta` | true | Si se permiten en temporada alta |
| `estadia_larga_max_noches_temp_alta` | null | Máximo noches en temp. alta |
| `estadia_larga_cobra_sobrantes_temp_alta` | false | Si cobran sobrantes en temp. alta |
| `estadia_larga_permitida_temp_media` | true | Si se permiten en temporada media |
| `estadia_larga_cobra_sobrantes_temp_media` | false | |
| `estadia_larga_permitida_temp_baja` | true | |
| `estadia_larga_cobra_sobrantes_temp_baja` | false | |

### Temporadas

| Clave | Valor default | Descripción |
|---|---|---|
| `temporada_finde_minimo_noches_alta` | 2 | Mínimo noches finde en temporada alta |

---

## 18. CAPA_DE_CARGOS — EXPANSIÓN FUTURA PREVISTA

### 18.1 Propósito

En el futuro puede existir una capa posterior al cálculo principal del motor de precios que modifique el total según canal, plataforma o método de pago. Esta capa es independiente del motor de precios y no mezcla su lógica con TARIFAS ni CONFIGURACION_GENERAL.

### 18.2 Casos de uso previstos

| Cargo | Descripción | Aplica cuando |
|---|---|---|
| Comisión Airbnb | % sobre el total | Canal de origen = Airbnb |
| Comisión Booking | % sobre el total | Canal de origen = Booking |
| Recargo MercadoPago | % por uso de tarjeta | Método de pago = MP link con tarjeta |
| IVA | % según corresponda | Según normativa fiscal vigente |
| Tasa municipal | Monto fijo o % | Si corresponde en el delta |
| Cargo de limpieza | Monto fijo | Estadías largas u operaciones especiales |
| Recargo por canal | % | Diferenciación por canal de venta |

### 18.3 Estructura prevista

```
FLUJO CON CAPA_DE_CARGOS (futuro):

precio_alojamiento = motor_estandar() o motor_evento_especial()
precio_con_cargos  = CAPA_DE_CARGOS.aplicar(precio_alojamiento, canal, metodo_pago)
precio_final       = precio_con_cargos
```

### 18.4 Principio de separación

La CAPA_DE_CARGOS nunca modifica la lógica del motor de precios. El motor siempre calcula el precio base del alojamiento de la misma forma, independientemente del canal o método de pago. Los cargos adicionales se aplican como una capa externa y transparente.

---

## 19. EDGE CASES DOCUMENTADOS

### Edge case 1 — Semana completa que cruza inicio de temporada alta

```
Reserva: lunes 29 nov → lunes 6 dic (7 noches)
Noches: 29, 30 nov (×1.00) + 1, 2, 3, 4, 5 dic (×1.20)
Base: $800.000 / 7 = $114.286/noche
  2 noches ×1.00 = $228.572
  5 noches ×1.20 = $685.715
Total: $914.287 → $914.000
```

### Edge case 2 — Semana completa con feriados dentro

```
Reserva: lunes 28 abr → lunes 5 may (7 noches, incluye Semana Santa)
Nivel: semanas → semana_completa
Precio: $800.000 (fijo, los feriados dentro no generan cargo adicional)

Nota: si la semana incluyera 31 dic o 1 ene, la reserva habría sido
interceptada en PASO 0 y derivada a motor_evento_especial() antes de
llamar a clasificar_noches(). Nunca llegaría aquí.
```

### Edge case 3 — Reserva que intersecta un EVENTO_ESPECIAL

```
Ejemplo: viernes 28 dic → martes 2 ene

→ PASO 0 (antes de cualquier lógica estándar):
  buscar_evento_especial(fecha_in=28 dic, fecha_out=2 ene)
  → Evento "Año Nuevo 2026/2027" encontrado (cubre 30 dic → 1 ene)
  → Intersecta → derivar COMPLETAMENTE a motor_evento_especial()
  → El motor estándar NO se ejecuta en ningún paso

→ motor_evento_especial() busca paquete para (28 dic → 2 ene):
  → Si existe paquete → aplicar precio del paquete
  → Si no existe paquete → modo_precio = "consultar"
  → Sistema informa al cliente que esas fechas requieren contacto directo

Este edge case confirma que año nuevo nunca pasa por clasificar_noches()
ni por la jerarquía estándar.
```

### Edge case 4 — Estadía larga en temporada alta con límite configurado

```
Configuración: estadia_larga_max_noches_temp_alta = 14
Reserva: 35 noches en enero (temporada alta)
→ Motor detecta estadia_larga Y temporada alta
→ 35 > 14 → error('estadia_larga_excede_maximo_temporada')
→ n8n notifica al admin para resolución manual
```

### Edge case 5 — Tipo de cabaña sin tarifas definidas

```
Cabaña tipo 'suite' agregada sin filas en TARIFAS:
→ error('tarifa_no_encontrada')
→ Notificación al admin
→ Cabaña inactiva hasta cargar tarifas
→ Registrar en LOG_CAMBIOS
```

### Edge case 6 — Techo en acción

```
Reserva: miércoles → domingo (4 noches, finde completo + 2 semana)
Nivel: finde_con_extras
Precio base: $350.000 + 2 × $100.000 = $550.000
Techo: no aplica ($550.000 < $800.000)

Caso extremo — si marginal_fijo fuera $250.000:
Precio base: $350.000 + 2 × $250.000 = $850.000
Techo: $800.000 → precio queda en $800.000
Luego: descuentos sobre $800.000, extras se suman después
```

### Edge case 7 — Descuento lleva precio bajo el mínimo

```
precio_con_descuento < precio_descuento_minimo:
→ Se aplica precio_descuento_minimo
→ Registrar en LOG_CAMBIOS
→ Si fue ingresado por cliente → notificar al admin
```

### Edge case 8 — Dos clientes usan el mismo código de descuento simultáneamente

```
→ Workflow secuencial, concurrencia = 1
→ El segundo espera en cola
→ Si el primero agotó los usos → error 'codigo_agotado' al segundo
```

### Edge case 9 — Finde + semana que llega exactamente a 7 noches

```
Reserva: lunes → lunes siguiente (7 noches)
Nivel: semanas (7 >= 7, prioridad sobre finde_con_extras)
Precio: semana_completa = $800.000
```

---

## 20. PENDIENTES PARA ETAPA 4

La Etapa 4 debe diseñar el **Motor de Reservas + Bot Conversacional**, dividido en dos subetapas:

- **Etapa 4A — Motor de Reservas Determinístico**
- **Etapa 4B — Bot Conversacional con IA**

Esta división es importante porque la IA no debe ser la fuente de verdad operacional.  
El bot puede conversar, interpretar y guiar al cliente, pero la creación de pre-reservas, validación de disponibilidad, pagos, confirmaciones y actualización del sistema deben pasar por workflows determinísticos en n8n.

### Etapa 4A — Motor de Reservas Determinístico

- [ ] Definir estados de CONSULTAS
- [ ] Definir estados de PRE_RESERVAS
- [ ] Definir estados de RESERVAS
- [ ] Definir estados de PAGOS
- [ ] Flujo consulta → cotización → pre-reserva → pago → confirmación
- [ ] Creación de PRE_RESERVA con expiración automática
- [ ] Revalidación de disponibilidad antes de confirmar una reserva
- [ ] Confirmación automática con MercadoPago
- [ ] Confirmación manual con comprobante validado por Vicky
- [ ] Manejo de transferencias bancarias, MercadoPago, efectivo y cripto
- [ ] Cancelaciones, modificaciones y conflictos
- [ ] Actualización automática de DISPONIBILIDAD_CACHE
- [ ] Actualización del calendario visual operativo
- [ ] Mensajes automáticos al huésped
- [ ] Mensajes automáticos al grupo operativo
- [ ] Asignación automática del encargado semanal Franco/Rodrigo
- [ ] Coordinación automática con Jennifer para limpieza
- [ ] Registro de LOG_CAMBIOS y source_event
- [ ] Workflows internos n8n para operaciones críticas
- [ ] Edge cases de pagos, vencimientos, doble reserva y errores de sincronización

### Etapa 4B — Bot Conversacional con IA

- [ ] System prompt base con toda la info del complejo
- [ ] Estructura del historial de conversación en CONSULTAS.contexto_json
- [ ] Matriz de intenciones del cliente
- [ ] Flujo conversacional: saludo → fechas → cabaña → precio → pre-reserva → pago
- [ ] FAQ sin llamar a la IA para preguntas frecuentes
- [ ] Cuándo llamar a IA y cuándo responder con reglas fijas
- [ ] Cuándo y cómo derivar a Vicky, Franco o Rodrigo
- [ ] Integración del motor de disponibilidad en respuestas
- [ ] Integración del motor de precios en respuestas
- [ ] Manejo de EVENTOS_ESPECIALES en el flujo del bot
- [ ] Formato de presentación del desglose al cliente
- [ ] Respuestas sobre mascotas, niños, cómo llegar, Starlink, restaurante, kayaks y servicios adicionales
- [ ] Manejo de negociación de precio o casos especiales
- [ ] Prompt caching para reducir costos
- [ ] Estrategia de reducción de tokens
- [ ] Handoff humano claro y trazable

**Lo que ya está definido y alimenta la Etapa 4:**

- Motor de disponibilidad completo con DISPONIBILIDAD_CACHE (Etapa 2)
- Motor de precios estándar + motor de eventos especiales (Etapa 3)
- Tabla CONSULTAS con contexto_json (Etapa 1)
- Flujo CONSULTAS → PRE_RESERVAS → RESERVAS (Etapa 1)
- OVERRIDES_OPERATIVOS para excepciones (Etapa 2)
- Principios de consistencia y source_event (Etapa 1)
- Regla de revalidación antes de confirmar reservas (Etapa 2)
- Convención fecha_in inclusive / fecha_out exclusive (Etapa 3)

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*  
*Siguiente: ARQUITECTURA_ETAPA_4A_MOTOR_RESERVAS.md — Motor de Reservas Determinístico*