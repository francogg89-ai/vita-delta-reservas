# ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md
# Modelo de Datos Real — Google Sheets

**Versión:** 1.0
**Fecha:** Mayo 2026
**Estado:** Aprobado — CERRADO
**Depende de:** ARQUITECTURA_ETAPA_1 v1.1 / ETAPA_2 v1.1 / ETAPA_3 v3.0 / ETAPA_4A v1.0 / ETAPA_4B v1.0
**Autores:** Franco (titular) + Claude (arquitecto)

---

## ÍNDICE

1. Objetivo de esta etapa
2. Principios del modelo de datos
3. Convenciones globales
4. Mapa general del Sheets
5. Hoja: CABAÑAS
6. Hoja: HUÉSPEDES
7. Hoja: FERIADOS
8. Hoja: TARIFAS
9. Hoja: TEMPORADAS
10. Hoja: EVENTOS_ESPECIALES
11. Hoja: PAQUETES_EVENTO
12. Hoja: CONSULTAS
13. Hoja: PRE_RESERVAS
14. Hoja: RESERVAS
15. Hoja: PAGOS
16. Hoja: DISPONIBILIDAD_CACHE
17. Hoja: BLOQUEOS
18. Hoja: OVERRIDES_OPERATIVOS
19. Hoja: CONFIGURACION_GENERAL
20. Hoja: PLANTILLAS_MENSAJES
21. Hoja: CUENTAS_COBRO
22. Hoja: DESCUENTOS
23. Hoja: GASTOS
24. Hoja: SOCIOS
25. Hoja: LOG_CAMBIOS
26. Hojas auxiliares y vistas operativas
27. Permisos y protección de hojas
28. Trazabilidad entre etapas
29. Checklist de creación

---

## 1. OBJETIVO DE ESTA ETAPA

Transformar toda la arquitectura definida en las Etapas 1 a 4B en una estructura real, operativa y completamente especificada de Google Sheets.

El resultado de esta etapa es un documento de referencia que permite crear el Sheets desde cero sin ambigüedad, sin romper la arquitectura futura y sin necesidad de consultar los documentos anteriores para entender qué va en cada columna.

### Qué incluye esta etapa
- Estructura completa de cada hoja (columnas, tipos, obligatoriedad, estados)
- Convenciones globales de nombrado y formato
- Permisos por hoja y por rol
- Ejemplos reales mínimos para cada hoja principal
- Checklist de creación ordenado

### Qué NO incluye esta etapa
- Implementación de workflows de n8n
- Apps Script
- Conexión con APIs externas
- Carga masiva de datos productivos (feriados completos, tarifas exhaustivas)
- Frontend

---

## 2. PRINCIPIOS DEL MODELO DE DATOS

**1. Una hoja, un propósito.** Cada hoja tiene un rol único y bien definido. No hay hojas que mezclen datos de distintas entidades.

**2. Tres categorías de hoja.** Toda hoja es una de estas:
- **Fuente:** contiene datos primarios, es la fuente de verdad para esa entidad
- **Derivada:** calculada a partir de fuentes, nunca editable manualmente (ej: DISPONIBILIDAD_CACHE)
- **Auxiliar/Vista:** facilita la operación del equipo, no es fuente de verdad (ej: calendario visual)

**3. Solo n8n escribe en hojas críticas.** Las hojas transaccionales (CONSULTAS, PRE_RESERVAS, RESERVAS, PAGOS, DISPONIBILIDAD_CACHE, LOG_CAMBIOS) solo reciben escrituras desde n8n. La edición manual está permitida solo para correcciones documentadas en LOG_CAMBIOS.

**4. Los IDs nunca se reutilizan.** Una vez asignado un ID a un registro, ese ID pertenece a ese registro para siempre, aunque el registro sea eliminado o marcado como inactivo.

**5. Los estados son listas cerradas.** Cada hoja con estados tiene un conjunto fijo de valores permitidos. No se inventan estados nuevos sin modificar la arquitectura.

**6. Campos JSON en celdas de texto.** Cuando un campo necesita estructura interna (como `contexto_json`), se almacena como texto JSON en una celda. n8n se encarga de parsear y serializar. Sheets no valida el contenido interno.

**7. Nulos son celdas vacías.** Nunca se escribe "null", "N/A", "-" o "ninguno" como valor. Si un campo no tiene valor, la celda queda vacía.

**8. Migrabilidad desde el día uno.** Toda columna tiene nombre en snake_case compatible con SQL. Toda FK se llama `id_[entidad]`. Toda fecha es YYYY-MM-DD. El día que se migre a Supabase, los nombres de columnas no cambian.

---

## 3. CONVENCIONES GLOBALES

### Nombres
| Elemento | Convención | Ejemplo |
|---|---|---|
| Nombre de hoja | MAYUSCULAS_CON_GUION_BAJO | `RESERVAS`, `LOG_CAMBIOS` |
| Nombre de columna | snake_case | `fecha_checkin`, `id_huesped` |
| FK | `id_` + nombre de entidad en singular | `id_cabana`, `id_huesped` |
| Estados | snake_case, sin espacios | `pendiente_pago`, `confirmada` |
| Booleanos | `TRUE` / `FALSE` en mayúsculas | `TRUE`, `FALSE` |

### Tipos de datos
| Tipo lógico | Cómo se almacena en Sheets | Validación |
|---|---|---|
| Fecha | Texto YYYY-MM-DD | Validación de formato |
| Hora | Texto HH:MM | Validación de formato |
| Timestamp | Texto ISO 8601: YYYY-MM-DDTHH:MM:SSZ | Solo escribe n8n |
| Entero | Número sin decimales | Tipo número en Sheets |
| Decimal | Número con punto como separador | Tipo número en Sheets |
| Monto | Número sin símbolo, sin puntos de miles | Ej: `350000` no `$350.000` |
| Booleano | TRUE / FALSE | Lista desplegable |
| Estado | Texto de lista cerrada | Lista desplegable o validación |
| JSON | Texto plano | Sin validación interna |
| URL | Texto | Sin validación |

### Columnas presentes en todas las hojas fuente
| Columna | Tipo | Descripción |
|---|---|---|
| `created_at` | Timestamp | Cuándo se creó el registro. Solo escribe n8n o fórmula de Sheets en hojas manuales |
| `updated_at` | Timestamp | Última modificación. Solo escribe n8n |

---

## 4. MAPA GENERAL DEL SHEETS

| Hoja | Categoría | Escribe | Lee | Etapa origen |
|---|---|---|---|---|
| CABAÑAS | Fuente | Franco/Rodrigo | Todos | 1 |
| HUÉSPEDES | Fuente | n8n / Vicky | Todos | 1 |
| FERIADOS | Fuente | Franco/Rodrigo | Todos | 1 |
| TARIFAS | Fuente | Franco/Rodrigo | Todos | 1+3 |
| TEMPORADAS | Fuente | Franco/Rodrigo | Todos | 3 |
| EVENTOS_ESPECIALES | Fuente | Franco/Rodrigo | Todos | 3 |
| PAQUETES_EVENTO | Fuente | Franco/Rodrigo | Todos | 3 |
| CONSULTAS | Fuente | n8n | Equipo (solo lectura) | 1+4A+4B |
| PRE_RESERVAS | Fuente | n8n | Equipo (solo lectura) | 1+4A |
| RESERVAS | Fuente | n8n / Vicky (transiciones) | Todos | 1+4A |
| PAGOS | Fuente | n8n / Vicky (validaciones) | Equipo | 1+4A |
| DISPONIBILIDAD_CACHE | Derivada | n8n únicamente | Bot / Web / Equipo | 1+2 |
| BLOQUEOS | Fuente | Franco/Rodrigo/Vicky | Todos | 1 |
| OVERRIDES_OPERATIVOS | Fuente | Franco/Rodrigo | Todos | 2 |
| CONFIGURACION_GENERAL | Fuente | Franco/Rodrigo | Todos | 1+2+3+4A+4B |
| PLANTILLAS_MENSAJES | Fuente | Franco/Rodrigo/Vicky | n8n / Bot | 4A+4B |
| CUENTAS_COBRO | Fuente | Franco/Rodrigo | n8n / Bot | 4A |
| GASTOS | Fuente | Franco/Rodrigo/Vicky | Franco/Rodrigo | 1 |
| DESCUENTOS | Fuente | Franco/Rodrigo | n8n (futuro) | 3 (prevista) |
| SOCIOS | Fuente | Franco/Rodrigo | Franco/Rodrigo | 1 |
| LOG_CAMBIOS | Fuente | n8n únicamente | Franco/Rodrigo | 1+ todas |
| VISTA_CALENDARIO | Auxiliar/Vista | n8n | Equipo operativo | 4A |
| VISTA_PRERESERVAS_ACTIVAS | Auxiliar/Vista | n8n | Vicky / Franco | 4A |
| VISTA_OCUPACION | Auxiliar/Vista | n8n | Franco/Rodrigo | 4A |

---

## 5. HOJA: CABAÑAS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** Todos (n8n, bot, web, equipo)
**Etapa origen:** 1 — sin cambios estructurales

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_cabana` | Entero | Sí | ID único autoincremental. Nunca cambia |
| 2 | `nombre` | Texto | Sí | Nombre de la cabaña |
| 3 | `tipo` | Texto | Sí | `grande` o `chica` |
| 4 | `capacidad_base` | Entero | Sí | Personas incluidas en precio base |
| 5 | `capacidad_max` | Entero | Sí | Máximo absoluto de personas |
| 6 | `activa` | Booleano | Sí | FALSE = no existe más en el sistema |
| 7 | `bloqueada` | Booleano | Sí | TRUE = existe pero no disponible temporalmente |
| 8 | `motivo_bloqueo` | Texto | No | Solo si bloqueada = TRUE |
| 9 | `orden_limpieza` | Entero | Sí | Prioridad para Jennifer (1 = primero) |
| 10 | `descripcion` | Texto | No | Para bot y web |
| 11 | `fotos_urls` | Texto | No | URLs separadas por coma |
| 12 | `created_at` | Timestamp | Sí | |

### Estados de `tipo`
`grande` / `chica`

### Datos iniciales reales

| id_cabana | nombre | tipo | capacidad_base | capacidad_max | activa | bloqueada | orden_limpieza |
|---|---|---|---|---|---|---|---|
| 1 | Bamboo | grande | 3 | 5 | TRUE | FALSE | 1 |
| 2 | Madre Selva | grande | 3 | 5 | TRUE | FALSE | 2 |
| 3 | Arrebol | grande | 3 | 5 | TRUE | FALSE | 3 |
| 4 | Guatemala | chica | 2 | 4 | TRUE | FALSE | 4 |
| 5 | Tokio | chica | 2 | 4 | TRUE | FALSE | 5 |

---

## 6. HOJA: HUÉSPEDES

**Categoría:** Fuente
**Escribe:** n8n (creación automática) / Vicky (correcciones manuales)
**Lee:** Todos
**Etapa origen:** 1 — sin cambios estructurales

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_huesped` | Entero | Sí | ID único autoincremental |
| 2 | `nombre` | Texto | Sí | |
| 3 | `apellido` | Texto | No | |
| 4 | `dni` | Texto | No | |
| 5 | `telefono` | Texto | Sí | Con código de país: +5491158297725 |
| 6 | `email` | Texto | No | |
| 7 | `canal_preferido` | Texto | No | `whatsapp` / `instagram` / `web` |
| 8 | `primera_reserva_fecha` | Fecha | No | YYYY-MM-DD. Calculado al confirmar |
| 9 | `total_reservas` | Entero | No | Actualizado por n8n al confirmar |
| 10 | `notas_internas` | Texto | No | "Cliente VIP", "Siempre trae perro", etc. |
| 11 | `created_at` | Timestamp | Sí | |
| 12 | `updated_at` | Timestamp | Sí | |

### Unicidad
El campo `telefono` debe ser único en la tabla. n8n verifica antes de crear un registro nuevo: si el teléfono ya existe, actualiza el registro existente en lugar de crear uno nuevo.

### Ejemplo real

| id_huesped | nombre | apellido | telefono | canal_preferido | total_reservas |
|---|---|---|---|---|---|
| 1 | Juan | García | +5491158297725 | whatsapp | 2 |

---

## 7. HOJA: FERIADOS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (motor de disponibilidad y precios)
**Etapa origen:** 1 — sin cambios estructurales

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `fecha` | Fecha | Sí | YYYY-MM-DD. Clave única |
| 2 | `nombre` | Texto | Sí | "Día del Trabajador" |
| 3 | `tipo` | Texto | Sí | `nacional` / `ano_nuevo` / `local` |
| 4 | `activo` | Booleano | Sí | FALSE = ignorado por el motor |

### Nota de carga
Los feriados nacionales de Argentina se cargan manualmente al inicio de cada año. Los feriados de Año Nuevo tienen tipo `ano_nuevo` para que el motor los derive a EVENTOS_ESPECIALES. No incluir aquí los días de Año Nuevo que ya están en PAQUETES_EVENTO: el motor consulta primero EVENTOS_ESPECIALES.

---

## 8. HOJA: TARIFAS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (motor de precios)
**Etapa origen:** 1 — ampliada por Etapa 3

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_tarifa` | Entero | Sí | ID único autoincremental |
| 2 | `tipo_cabana` | Texto | Sí | `grande` / `chica` |
| 3 | `concepto` | Texto | Sí | Ver valores válidos abajo |
| 4 | `precio` | Monto | Sí | Precio base en ARS (temporada media, multiplicador 1.00) |
| 5 | `descripcion` | Texto | Sí | Descripción legible para auditoría |
| 6 | `activa` | Booleano | Sí | FALSE = ignorada por el motor |
| 7 | `valida_desde` | Fecha | No | Null = siempre válida |
| 8 | `valida_hasta` | Fecha | No | Null = siempre válida |
| 9 | `created_at` | Timestamp | Sí | |
| 10 | `updated_at` | Timestamp | Sí | |

### Valores válidos de `concepto`

| Concepto | Descripción |
|---|---|
| `semana_1` | 1 noche de semana |
| `semana_2` | 2 noches de semana (precio total del bloque) |
| `semana_3` | 3 noches de semana |
| `semana_4` | 4 noches de semana |
| `semana_5` | 5 noches de semana |
| `semana_marginal_6plus` | Precio por noche adicional desde la 6ta noche de semana |
| `finde_1_noche` | 1 noche de finde (vie→sáb o sáb→dom) |
| `finde_completo` | Finde completo vie→dom (2 noches) |
| `feriado_aislado` | 1 feriado no pegado a finde |
| `feriado_adicional` | Cada noche de feriado sobre el finde |
| `semana_completa` | 7 noches consecutivas |
| `semana_adicional` | Cada semana completa después de la primera |
| `marginal_fijo_finde_semana` | Noche de semana en combinación con finde completo |
| `extra_persona_noche` | Cargo por persona sobre capacidad base, por noche |

### Ejemplos reales (cabañas grandes, temporada media)

| id_tarifa | tipo_cabana | concepto | precio | descripcion | activa |
|---|---|---|---|---|---|
| 1 | grande | semana_1 | 150000 | 1 noche semana — grande | TRUE |
| 2 | grande | semana_2 | 280000 | 2 noches semana — grande | TRUE |
| 3 | grande | semana_3 | 400000 | 3 noches semana — grande | TRUE |
| 4 | grande | finde_completo | 350000 | Finde vie+sáb — grande | TRUE |
| 5 | grande | semana_completa | 800000 | 7 noches — grande | TRUE |
| 6 | grande | extra_persona_noche | 10000 | Por persona extra por noche | TRUE |
| 7 | chica | semana_1 | 130000 | 1 noche semana — chica | TRUE |
| 8 | chica | finde_completo | 300000 | Finde vie+sáb — chica | TRUE |
| 9 | chica | semana_completa | 700000 | 7 noches — chica | TRUE |
| 10 | chica | extra_persona_noche | 10000 | Por persona extra por noche | TRUE |

---

## 9. HOJA: TEMPORADAS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (motor de precios)
**Etapa origen:** 3 (nueva)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_temporada` | Entero | Sí | ID único autoincremental |
| 2 | `nombre` | Texto | Sí | "Temporada alta verano 2026-2027" |
| 3 | `fecha_desde` | Fecha | Sí | Inicio del rango (inclusive) |
| 4 | `fecha_hasta` | Fecha | Sí | Fin del rango (inclusive) |
| 5 | `multiplicador` | Decimal | Sí | 1.00 = base / 1.20 = +20% / 0.85 = -15% |
| 6 | `activa` | Booleano | Sí | |
| 7 | `created_at` | Timestamp | Sí | |

### Regla de solapamiento
No deben existir dos temporadas activas con rangos que se solapen. n8n detecta el solapamiento al consultar y usa la temporada con `id_temporada` mayor (más reciente) si ocurre. Se recomienda que Franco verifique la consistencia al cargar temporadas nuevas.

### Ejemplos reales iniciales

| id_temporada | nombre | fecha_desde | fecha_hasta | multiplicador | activa |
|---|---|---|---|---|---|
| 1 | Temporada media 2026 | 2026-05-01 | 2026-11-30 | 1.00 | TRUE |
| 2 | Temporada alta verano 2026-2027 | 2026-12-01 | 2027-02-28 | 1.20 | TRUE |

---

## 10. HOJA: EVENTOS_ESPECIALES

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (motor de precios)
**Etapa origen:** 3 (nueva)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_evento` | Entero | Sí | ID único autoincremental |
| 2 | `nombre` | Texto | Sí | "Año Nuevo 2026/2027" |
| 3 | `fecha_desde` | Fecha | Sí | Inicio del evento (inclusive) |
| 4 | `fecha_hasta` | Fecha | Sí | Fin del evento (inclusive) |
| 5 | `modo_precio` | Texto | Sí | `paquetes_fijos` / `precio_por_noche` / `consultar` |
| 6 | `reglas_especiales` | JSON | No | Reglas propias del evento en formato JSON |
| 7 | `activa` | Booleano | Sí | |
| 8 | `source_event` | Texto | Sí | Origen del registro |
| 9 | `created_at` | Timestamp | Sí | |

### Ejemplo real

| id_evento | nombre | fecha_desde | fecha_hasta | modo_precio | activa |
|---|---|---|---|---|---|
| 1 | Año Nuevo 2026/2027 | 2026-12-30 | 2027-01-02 | paquetes_fijos | TRUE |

`reglas_especiales` para Año Nuevo:
```json
{
  "minimo_noches": 1,
  "checkout_maximo": "2027-01-02",
  "nota": "Precios por paquete según combinación de noches"
}
```

---

## 11. HOJA: PAQUETES_EVENTO

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (motor de precios para eventos especiales)
**Etapa origen:** 3 (nueva)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_paquete` | Entero | Sí | ID único autoincremental |
| 2 | `id_evento` | Entero | Sí | FK → EVENTOS_ESPECIALES |
| 3 | `nombre` | Texto | Sí | "31 solo", "30+31+1", etc. |
| 4 | `fecha_in` | Fecha | Sí | Fecha de checkin del paquete |
| 5 | `fecha_out` | Fecha | Sí | Fecha de checkout (exclusive) |
| 6 | `tipo_cabana` | Texto | Sí | `grande` / `chica` / `todas` |
| 7 | `precio` | Monto | Sí | Precio fijo del paquete en ARS |
| 8 | `minimo_noches` | Entero | Sí | Mínimo de noches obligatorio |
| 9 | `activo` | Booleano | Sí | |
| 10 | `created_at` | Timestamp | Sí | |

### Ejemplo real (Año Nuevo 2026/2027 — cabañas grandes, precios a definir)

| id_paquete | id_evento | nombre | fecha_in | fecha_out | tipo_cabana | precio | minimo_noches | activo |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | Solo 31 dic | 2026-12-31 | 2027-01-01 | grande | 0 | 1 | TRUE |
| 2 | 1 | 30+31 dic | 2026-12-30 | 2027-01-01 | grande | 0 | 2 | TRUE |
| 3 | 1 | 31 dic + 1 ene | 2026-12-31 | 2027-01-02 | grande | 0 | 2 | TRUE |
| 4 | 1 | 30+31+1 | 2026-12-30 | 2027-01-02 | grande | 0 | 3 | TRUE |

*Nota: precios en 0 como placeholder. Franco carga los precios reales antes de la temporada.*

### Regla: paquetes con precio 0

Si `precio = 0`, el paquete se considera incompleto. El motor de precios no puede cotizarlo ni permitir su venta automática. Ante una consulta que intersecte un EVENTO_ESPECIAL con paquetes en precio 0, el sistema deriva inmediatamente a humano con el motivo `paquete_sin_precio`. Esta regla aplica aunque el paquete tenga `activo = TRUE`. La activación real del paquete para venta automática requiere que `precio > 0`.

---

## 12. HOJA: CONSULTAS

**Categoría:** Fuente
**Escribe:** n8n únicamente (lectura del equipo permitida, sin edición)
**Lee:** n8n / equipo (solo lectura)
**Etapa origen:** 1 — ampliada por Etapas 4A y 4B

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_consulta` | Entero | Sí | ID único autoincremental |
| 2 | `canal` | Texto | Sí | `whatsapp` / `instagram` / `web` |
| 3 | `id_contacto_externo` | Texto | Sí | ID del usuario en la plataforma (teléfono o ID de IG) |
| 4 | `id_huesped` | Entero | No | FK → HUÉSPEDES. Null si aún no identificado |
| 5 | `estado_conversacion` | Texto | Sí | Ver estados abajo |
| 6 | `id_cabana_tentativa` | Entero | No | FK → CABAÑAS |
| 7 | `fecha_in_tentativa` | Fecha | No | YYYY-MM-DD |
| 8 | `fecha_out_tentativa` | Fecha | No | YYYY-MM-DD |
| 9 | `personas_tentativa` | Entero | No | |
| 10 | `ultimo_mensaje_at` | Timestamp | Sí | Para detectar conversaciones inactivas |
| 11 | `contexto_json` | JSON | No | Historial y datos recopilados. Ver estructura en Etapa 4B |
| 12 | `tokens_json` | JSON | No | Registro de tokens consumidos por llamada a Claude API |
| 13 | `motivo_derivacion` | Texto | No | Motivo si estado = derivada_a_humano |
| 14 | `source_event` | Texto | Sí | Origen del primer mensaje |
| 15 | `created_at` | Timestamp | Sí | |
| 16 | `updated_at` | Timestamp | Sí | |

### Estados de `estado_conversacion`
`inicio` / `eligiendo_fechas` / `cotizando` / `esperando_pago` / `pago_en_proceso` / `cerrada` / `derivada_a_humano`

### Ejemplo real

| id_consulta | canal | id_contacto_externo | id_huesped | estado_conversacion | fecha_in_tentativa | fecha_out_tentativa | personas_tentativa |
|---|---|---|---|---|---|---|---|
| 1 | whatsapp | +5491158297725 | 1 | esperando_pago | 2026-06-20 | 2026-06-22 | 3 |

`contexto_json` ejemplo:
```json
{
  "turnos": [
    { "rol": "cliente", "texto": "Hola quiero reservar para el 20 de junio", "timestamp": "2026-06-05T14:23:00Z" },
    { "rol": "bot", "texto": "Para ese fin de semana tenemos Bamboo disponible...", "timestamp": "2026-06-05T14:23:05Z", "via": "ia" }
  ],
  "datos_recopilados": {
    "fecha_in": "2026-06-20",
    "fecha_out": "2026-06-22",
    "personas": 3,
    "cabana_preferida": null,
    "tipo_cabana_preferida": "grande",
    "canal_pago_elegido": "transferencia_bancaria"
  },
  "estado_flujo": "esperando_pago",
  "intentos_sin_clasificar": 0,
  "intentos_sin_avance": 0,
  "derivacion_ofrecida": false,
  "reserva_anterior": false
}
```

---

## 13. HOJA: PRE_RESERVAS

**Categoría:** Fuente
**Escribe:** n8n únicamente
**Lee:** n8n / equipo (solo lectura)
**Etapa origen:** 1 — ampliada por Etapa 4A

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_prereserva` | Entero | Sí | ID único autoincremental |
| 2 | `id_consulta` | Entero | No | FK → CONSULTAS |
| 3 | `id_cabana` | Entero | Sí | FK → CABAÑAS |
| 4 | `id_huesped` | Entero | Sí | FK → HUÉSPEDES |
| 5 | `fecha_in` | Fecha | Sí | YYYY-MM-DD (inclusive) |
| 6 | `fecha_out` | Fecha | Sí | YYYY-MM-DD (exclusive) |
| 7 | `hora_checkin` | Hora | Sí | HH:MM calculado con escalonamiento |
| 8 | `hora_checkout` | Hora | Sí | HH:MM calculado con escalonamiento |
| 9 | `personas` | Entero | Sí | |
| 10 | `monto_total` | Monto | Sí | Precio total calculado |
| 11 | `monto_sena` | Monto | Sí | 50% del total por defecto |
| 12 | `estado` | Texto | Sí | Ver estados abajo |
| 13 | `expira_en` | Timestamp | Sí | Cuándo vence si no paga |
| 14 | `canal_pago_esperado` | Texto | Sí | `mp_link` / `transferencia_bancaria` / `transferencia_mp` / `cripto` / `efectivo` |
| 15 | `canal_origen` | Texto | Sí | `whatsapp` / `instagram` / `web` |
| 16 | `intentos_pago` | Entero | Sí | Default 0. Incrementa por n8n |
| 17 | `referencia_mp` | Texto | No | preference_id de MercadoPago si aplica |
| 18 | `notas` | Texto | No | |
| 19 | `source_event` | Texto | Sí | |
| 20 | `created_at` | Timestamp | Sí | |
| 21 | `updated_at` | Timestamp | Sí | |

### Estados de `estado`
`pendiente_pago` / `vencida` / `convertida` / `cancelada_por_cliente` / `cancelada_por_bloqueo` / `conflicto_pendiente`

### Ejemplo real

| id_prereserva | id_consulta | id_cabana | id_huesped | fecha_in | fecha_out | hora_checkin | hora_checkout | personas | monto_total | monto_sena | estado | expira_en |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 1 | 2026-06-20 | 2026-06-22 | 13:00 | 16:00 | 3 | 350000 | 175000 | pendiente_pago | 2026-06-05T15:23:00Z |

---

## 14. HOJA: RESERVAS

**Categoría:** Fuente
**Escribe:** n8n (creación y transiciones automáticas) / Vicky o Franco (transiciones manuales documentadas: activa, completada)
**Lee:** Todos
**Etapa origen:** 1 — ampliada por Etapa 4A

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_reserva` | Entero | Sí | ID único autoincremental |
| 2 | `id_prereserva` | Entero | No | FK → PRE_RESERVAS (trazabilidad) |
| 3 | `id_cabana` | Entero | Sí | FK → CABAÑAS |
| 4 | `id_huesped` | Entero | Sí | FK → HUÉSPEDES |
| 5 | `fecha_checkin` | Fecha | Sí | YYYY-MM-DD |
| 6 | `fecha_checkout` | Fecha | Sí | YYYY-MM-DD |
| 7 | `hora_checkin` | Hora | Sí | HH:MM |
| 8 | `hora_checkout` | Hora | Sí | HH:MM |
| 9 | `personas` | Entero | Sí | |
| 10 | `estado` | Texto | Sí | Ver estados abajo |
| 11 | `canal_origen` | Texto | Sí | `whatsapp` / `instagram` / `web` / `airbnb` / `booking` / `manual` |
| 12 | `id_tarifa_aplicada` | Entero | Sí | FK → TARIFAS (tarifa base usada) |
| 13 | `monto_total` | Monto | Sí | |
| 14 | `monto_sena` | Monto | Sí | |
| 15 | `monto_saldo` | Monto | Sí | |
| 16 | `mascotas` | Booleano | No | |
| 17 | `detalle_mascotas` | Texto | No | |
| 18 | `ninos` | Booleano | No | |
| 19 | `encargado_semana` | Texto | Sí | `Franco` / `Rodrigo` |
| 20 | `notas` | Texto | No | También usado para trazabilidad de modificaciones: `modificacion_de:#ID` o `reemplazada_por:#ID` |
| 21 | `created_by` | Texto | Sí | `bot` / `vicky` / `web` / `franco` / `rodrigo` |
| 22 | `source_event` | Texto | Sí | |
| 23 | `created_at` | Timestamp | Sí | |
| 24 | `updated_at` | Timestamp | Sí | |

### Estados de `estado`
`confirmada` / `activa` / `completada` / `cancelada` / `cancelada_con_cargo` / `conflicto_pendiente`

### Transiciones manuales permitidas
Vicky o Franco pueden cambiar manualmente:
- `confirmada` → `activa` (al registrar checkin)
- `activa` → `completada` (al registrar checkout)

Cualquier otra transición debe pasar por n8n. El cambio manual debe registrarse en LOG_CAMBIOS.

### Ejemplo real

| id_reserva | id_prereserva | id_cabana | id_huesped | fecha_checkin | fecha_checkout | hora_checkin | hora_checkout | personas | estado | encargado_semana | monto_total | monto_sena | monto_saldo |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 142 | 1 | 1 | 1 | 2026-06-20 | 2026-06-22 | 13:00 | 16:00 | 3 | confirmada | Franco | 350000 | 175000 | 175000 |

---

## 15. HOJA: PAGOS

**Categoría:** Fuente
**Escribe:** n8n (creación y actualización automática) / Vicky o Franco (validaciones manuales de comprobantes)
**Lee:** n8n / equipo
**Etapa origen:** 1 — rediseñada por Etapa 4A (arquitectura multicanal)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_pago` | Entero | Sí | ID único autoincremental |
| 2 | `id_prereserva` | Entero | Sí | FK → PRE_RESERVAS |
| 3 | `id_reserva` | Entero | No | FK → RESERVAS (se llena al confirmar) |
| 4 | `tipo` | Texto | Sí | `sena` / `saldo` / `extra` / `reembolso` |
| 5 | `medio_pago` | Texto | Sí | Ver valores válidos abajo |
| 6 | `proveedor` | Texto | No | `mercadopago` / `banco_galicia` / `binance` / etc. |
| 7 | `cuenta_destino` | Texto | No | CBU, alias, dirección cripto o cuenta MP |
| 8 | `monto_esperado` | Monto | Sí | Monto que el sistema espera recibir |
| 9 | `monto_recibido` | Monto | No | Monto real recibido |
| 10 | `moneda` | Texto | Sí | `ARS` / `USD` / `USDT` / `BTC` |
| 11 | `estado` | Texto | Sí | Ver estados abajo |
| 12 | `es_automatico` | Booleano | Sí | TRUE = validado por webhook / FALSE = validación manual |
| 13 | `comprobante_url` | Texto | No | Link a imagen o PDF del comprobante |
| 14 | `referencia_externa` | Texto | No | ID de la transacción en MP u otro proveedor |
| 15 | `tx_hash` | Texto | No | Hash de transacción para pagos cripto |
| 16 | `validado_por` | Texto | No | `bot_mp` / `vicky` / `franco` / `rodrigo` |
| 17 | `validado_en` | Timestamp | No | Cuándo se confirmó |
| 18 | `motivo_rechazo` | Texto | No | Por qué fue rechazado |
| 19 | `notas` | Texto | No | |
| 20 | `source_event` | Texto | Sí | |
| 21 | `created_at` | Timestamp | Sí | |
| 22 | `updated_at` | Timestamp | Sí | |

### Estados de `estado`
`pendiente` / `en_revision` / `confirmado` / `rechazado` / `reembolsado`

### Valores válidos de `medio_pago`
`mp_link` / `transferencia_mp` / `transferencia_bancaria` / `tarjeta` / `efectivo` / `cripto`

### Ejemplo real — pago manual por transferencia bancaria

| id_pago | id_prereserva | id_reserva | tipo | medio_pago | proveedor | cuenta_destino | monto_esperado | monto_recibido | moneda | estado | es_automatico | validado_por | validado_en |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 142 | sena | transferencia_bancaria | banco_galicia | CVU: 000xxxxx | 175000 | 175000 | ARS | confirmado | FALSE | vicky | 2026-06-05T15:45:00Z |

---

## 16. HOJA: DISPONIBILIDAD_CACHE

**Categoría:** Derivada
**Escribe:** n8n únicamente — NUNCA editar manualmente
**Lee:** Bot / Web / n8n / equipo (solo lectura)
**Etapa origen:** 1 — especificada en Etapa 2

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_cabana` | Entero | Sí | FK → CABAÑAS. Parte de la clave primaria compuesta |
| 2 | `fecha` | Fecha | Sí | YYYY-MM-DD. Parte de la clave primaria compuesta |
| 3 | `estado` | Texto | Sí | Ver estados abajo |
| 4 | `hora_checkin_minima` | Hora | No | Mínimo permitido considerando escalonamiento |
| 5 | `hora_checkin_maxima` | Hora | No | Máximo permitido (de CONFIGURACION_GENERAL) |
| 6 | `hora_checkout_maxima` | Hora | No | Máximo permitido considerando escalonamiento |
| 7 | `hora_checkout_minima` | Hora | No | Mínimo permitido (de CONFIGURACION_GENERAL) |
| 8 | `tipo_dia` | Texto | No | `semana` / `finde` / `feriado` / `ano_nuevo` |
| 9 | `temporada` | Texto | No | `alta` / `media` / `baja` |
| 10 | `es_ultimo_dia_bloque` | Booleano | No | Si aplica checkout 16:00 |
| 11 | `minimo_noches` | Entero | No | Mínimo de noches desde este día |
| 12 | `id_reserva_activa` | Entero | No | FK → RESERVAS si está ocupada |
| 13 | `id_prereserva_activa` | Entero | No | FK → PRE_RESERVAS si está en proceso |
| 14 | `recalculado_en` | Timestamp | Sí | Última vez que se calculó |

### Estados de `estado`
`disponible` / `ocupada` / `bloqueada` / `checkout_disponible` / `limite_escalonamiento`

### Clave primaria compuesta
El par (`id_cabana`, `fecha`) es único. Cada fila representa un día específico para una cabaña específica.

### Ejemplo real

| id_cabana | fecha | estado | hora_checkin_minima | hora_checkin_maxima | hora_checkout_maxima | tipo_dia | temporada | es_ultimo_dia_bloque | minimo_noches |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-06-20 | disponible | 13:00 | 22:00 | 10:00 | finde | media | FALSE | 2 |
| 1 | 2026-06-21 | disponible | 13:00 | 22:00 | 16:00 | finde | media | TRUE | 1 |
| 1 | 2026-06-22 | disponible | 13:00 | 22:00 | 10:00 | semana | media | FALSE | 1 |

---

## 17. HOJA: BLOQUEOS

**Categoría:** Fuente
**Escribe:** Franco / Rodrigo / Vicky (con permiso)
**Lee:** n8n / equipo
**Etapa origen:** 1 — sin cambios estructurales

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_bloqueo` | Entero | Sí | ID único autoincremental |
| 2 | `id_cabana` | Entero | No | FK → CABAÑAS. Null = todas las cabañas |
| 3 | `fecha_desde` | Fecha | Sí | YYYY-MM-DD |
| 4 | `fecha_hasta` | Fecha | Sí | YYYY-MM-DD |
| 5 | `motivo` | Texto | Sí | `mantenimiento` / `uso_propio` / `tormenta` / `overbooking` / `otro` |
| 6 | `descripcion` | Texto | No | Detalle libre |
| 7 | `creado_por` | Texto | Sí | Quién lo creó |
| 8 | `activo` | Booleano | Sí | FALSE = desactivado sin borrar |
| 9 | `source_event` | Texto | Sí | |
| 10 | `created_at` | Timestamp | Sí | |

### Bloqueo total
`id_cabana` vacío (null) significa que el bloqueo aplica a todas las cabañas del complejo simultáneamente.

---

## 18. HOJA: OVERRIDES_OPERATIVOS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (motor de disponibilidad, con prioridad sobre CONFIGURACION_GENERAL)
**Etapa origen:** 2 (nueva)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_override` | Entero | Sí | ID único autoincremental |
| 2 | `fecha_desde` | Fecha | Sí | Inicio del rango (o fecha puntual si fecha_hasta vacío) |
| 3 | `fecha_hasta` | Fecha | No | Fin del rango. Vacío = aplica solo a fecha_desde |
| 4 | `id_cabana` | Entero | No | FK → CABAÑAS. Vacío = aplica a todas las cabañas |
| 5 | `tipo_override` | Texto | Sí | Ver valores válidos abajo |
| 6 | `valor` | Texto | Sí | Nuevo valor para ese tipo (hora, número, booleano como texto) |
| 7 | `motivo` | Texto | Sí | Razón del override |
| 8 | `creado_por` | Texto | Sí | |
| 9 | `activo` | Booleano | Sí | |
| 10 | `source_event` | Texto | Sí | |
| 11 | `created_at` | Timestamp | Sí | |

### Valores válidos de `tipo_override`
`escalonamiento_activo` / `escalonamiento_umbral_checkout` / `escalonamiento_umbral_checkin` / `hora_checkin` / `hora_checkout` / `checkin_flexible` / `checkout_flexible` / `minimo_noches` / `disponibilidad_bloqueada`

### Ejemplo real

| id_override | fecha_desde | fecha_hasta | id_cabana | tipo_override | valor | motivo | creado_por | activo |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-06-14 | | | escalonamiento_activo | false | Personal extra contratado para evento 14/06 | franco | TRUE |

---

## 19. HOJA: CONFIGURACION_GENERAL

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n / todos los motores
**Etapa origen:** 1 — ampliada por Etapas 2, 3, 4A y 4B

### Estructura de la hoja

Tres columnas fijas:

| Columna | Tipo | Descripción |
|---|---|---|
| `clave` | Texto | Identificador único de la configuración |
| `valor` | Texto | Valor actual (siempre texto; n8n convierte al tipo correcto) |
| `descripcion` | Texto | Para qué sirve, quién lo usa, qué impacto tiene cambiarlo |

### Lista consolidada de claves

#### Horarios (Etapa 2)
| Clave | Valor actual | Descripción |
|---|---|---|
| `hora_checkin_default` | 13:00 | Check-in estándar |
| `hora_checkout_default` | 10:00 | Check-out estándar |
| `hora_checkin_domingo` | 18:00 | Check-in cuando domingo es primer día |
| `hora_checkout_ultimo_dia_bloque` | 16:00 | Check-out del último día del bloque |
| `hora_checkin_max_cliente` | 22:00 | Hora máxima de entrada que puede elegir el cliente |
| `hora_checkout_min_cliente` | 07:00 | Hora mínima de salida que puede elegir el cliente |

#### Escalonamiento (Etapa 2)
| Clave | Valor actual | Descripción |
|---|---|---|
| `escalonamiento_activo` | true | Master switch del escalonamiento |
| `escalonamiento_umbral_checkout` | 3 | Checkouts simultáneos que activan escalonamiento de checkin |
| `escalonamiento_umbral_checkin` | 3 | Checkins simultáneos que activan escalonamiento de checkout |
| `escalonamiento_minutos` | 45 | Minutos de ajuste por cabaña adicional |
| `escalonamiento_checkin_max` | 22:00 | Límite máximo de check-in por escalonamiento |
| `escalonamiento_checkout_min` | 09:00 | Límite mínimo de checkout por escalonamiento |
| `escalonamiento_checkout_max_minutos` | 60 | Máximo minutos de adelanto en checkout |
| `escalonamiento_checkout_tramo_minutos` | 30 | Minutos por tramo en escalonamiento de checkout |

#### Flexibilidad del cliente (Etapa 2)
| Clave | Valor actual | Descripción |
|---|---|---|
| `checkin_flexible_activo` | true | Si el cliente puede elegir hora de entrada |
| `checkout_flexible_activo` | true | Si el cliente puede elegir hora de salida |

#### Temporada (Etapa 2 y 3)
| Clave | Valor actual | Descripción |
|---|---|---|
| `temporada_alta_inicio` | 12-01 | MM-DD inicio temporada alta |
| `temporada_alta_fin` | 02-28 | MM-DD fin temporada alta |
| `finde_minimo_noches_temp_alta` | 2 | Mínimo de noches en finde durante temporada alta |

#### Precios (Etapa 3)
| Clave | Valor actual | Descripción |
|---|---|---|
| `sena_porcentaje` | 50 | % de seña sobre el total |
| `precio_redondeo_base` | 1000 | Redondear al millar más cercano |
| `precio_descuento_minimo` | 10000 | Precio mínimo permitido post-descuento |

#### Estadía larga (Etapa 3)
| Clave | Valor actual | Descripción |
|---|---|---|
| `estadia_larga_minimo_noches` | 28 | Mínimo noches para nivel estadía larga |
| `estadia_larga_permitida_temp_alta` | true | Si se permiten en temporada alta |
| `estadia_larga_max_noches_temp_alta` | | Vacío = sin límite |
| `estadia_larga_cobra_sobrantes_temp_alta` | false | |
| `estadia_larga_permitida_temp_media` | true | |
| `estadia_larga_cobra_sobrantes_temp_media` | false | |
| `estadia_larga_permitida_temp_baja` | true | |
| `estadia_larga_cobra_sobrantes_temp_baja` | false | |

#### Pre-reservas y reservas (Etapa 4A)
| Clave | Valor actual | Descripción |
|---|---|---|
| `prereserva_expiracion_minutos` | 60 | Tiempo de vida de una PRE_RESERVA sin pago |
| `prereserva_notificacion_vencimiento_umbral` | 200000 | Monto desde el que se notifica al vencer |
| `prereserva_recordatorio_minutos_antes` | 15 | Minutos antes del vencimiento para recordatorio |
| `diferencia_pago_tolerancia` | 5000 | Diferencia máxima de monto aceptable sin consultar |

#### Checkout tardío (Etapa 4A)
| Clave | Valor actual | Descripción |
|---|---|---|
| `checkout_recordatorio_horas_despues` | 2 | Horas post-checkout sin registrar para enviar recordatorio |

#### Encargado semanal (Etapa 4A)
| Clave | Valor actual | Descripción |
|---|---|---|
| `encargado_ciclo_inicio_fecha` | 2026-05-11 | Fecha inicio del ciclo Franco/Rodrigo |
| `encargado_ciclo_inicio_nombre` | Franco | Quién arranca el ciclo |

#### Conversaciones (Etapa 4B)
| Clave | Valor actual | Descripción |
|---|---|---|
| `conversacion_expiracion_horas` | 24 | Horas de inactividad para cerrar una CONSULTA |
| `contexto_max_turnos` | 20 | Máximo de turnos en la ventana activa del contexto |
| `contexto_max_chars` | 8000 | Máximo de caracteres en el JSON de contexto |
| `contexto_resumen_trigger` | 15 | Turnos desde los que se genera resumen |
| `clasificador_faq_umbral` | 0.85 | Confianza mínima para responder FAQ sin IA |
| `clasificador_activo` | true | Master switch del clasificador previo |

#### Cache (Etapa 2)
| Clave | Valor actual | Descripción |
|---|---|---|
| `cache_horizonte_meses` | 18 | Meses hacia adelante que mantiene la cache |
| `cache_recalculo_masivo_hora` | 03:00 | Hora del recálculo nocturno |

#### Sistema general (Etapa 1)
| Clave | Valor actual | Descripción |
|---|---|---|
| `max_cabanas_sistema` | 10 | Límite configurable de cabañas |
| `whatsapp_franco` | +5491158297725 | |
| `whatsapp_rodrigo` | +5491135659035 | |
| `whatsapp_jennifer` | +5491151789772 | Si aún no existe, agregar |

#### Alertas y métricas (Etapa 4B)
| Clave | Valor actual | Descripción |
|---|---|---|
| `alerta_derivacion_tasa_umbral` | 0.40 | Tasa de derivación que dispara alerta a Franco |
| `alerta_errores_api_por_hora` | 5 | Errores técnicos por hora que disparan alerta |
| `alerta_costo_diario_usd` | 5 | Costo diario estimado que dispara alerta |

---

## 20. HOJA: PLANTILLAS_MENSAJES

**Categoría:** Fuente
**Escribe:** Franco / Rodrigo / Vicky (con cuidado — el texto impacta directamente en lo que reciben los clientes)
**Lee:** n8n / bot
**Etapa origen:** 4A y 4B (nueva)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_plantilla` | Entero | Sí | ID único |
| 2 | `nombre` | Texto | Sí | Identificador interno único (snake_case) |
| 3 | `canal` | Texto | Sí | `whatsapp` / `instagram` / `todos` |
| 4 | `evento_disparador` | Texto | Sí | Cuándo se usa esta plantilla |
| 5 | `texto` | Texto | Sí | Texto con variables entre llaves: {nombre}, {fecha_checkin} |
| 6 | `keywords` | Texto | No | Palabras clave separadas por coma para detección de FAQ por clasificador |
| 7 | `score_minimo` | Decimal | No | Umbral de confianza para esta FAQ. Default del sistema si vacío |
| 8 | `destinatario` | Texto | Sí | `huesped` / `equipo` / `jennifer` / `franco` |
| 9 | `activa` | Booleano | Sí | |
| 10 | `created_at` | Timestamp | Sí | |

### Variables disponibles para sustitución
`{nombre}` `{apellido}` `{nombre_cabana}` `{fecha_in}` `{fecha_out}` `{fecha_checkin}` `{fecha_checkout}` `{hora_checkin}` `{hora_checkout}` `{personas}` `{monto_total}` `{monto_sena}` `{saldo}` `{expiracion_minutos}` `{encargado_semana}` `{instrucciones_llegada}` `{nota_proxima_reserva}` `{canal}`

### Ejemplos de filas

| id | nombre | canal | destinatario | evento_disparador | keywords |
|---|---|---|---|---|---|
| 1 | bienvenida | todos | huesped | primer_contacto | hola, buenas, buen dia, buenos dias, hi |
| 2 | prereserva_creada | todos | huesped | prereserva_created | |
| 3 | instrucciones_pago | todos | huesped | prereserva_created | |
| 4 | reserva_confirmada | todos | huesped | reserva_confirmed | |
| 5 | recordatorio_checkin | whatsapp | huesped | 24h_antes_checkin | |
| 6 | faq_mascotas | todos | huesped | faq | mascota, perro, gato, animal, pet |
| 7 | faq_wifi | todos | huesped | faq | wifi, starlink, internet, señal, conexion |
| 8 | faq_kayaks | todos | huesped | faq | kayak, kayaks, actividad, rio, remar |
| 9 | faq_llegada | todos | huesped | faq | llegar, como llego, como se llega, lancha, muelle |
| 10 | nueva_reserva_equipo | whatsapp | equipo | reserva_confirmed | |
| 11 | coordinacion_jennifer_checkin | whatsapp | jennifer | reserva_confirmed | |
| 12 | coordinacion_jennifer_checkout | whatsapp | jennifer | checkout_registrado | |

---

## 21. HOJA: CUENTAS_COBRO

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n / bot (para presentar datos de pago al cliente)
**Etapa origen:** 4A (nueva)

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_cuenta` | Entero | Sí | ID único |
| 2 | `nombre` | Texto | Sí | Nombre descriptivo |
| 3 | `medio` | Texto | Sí | `transferencia_bancaria` / `transferencia_mp` / `cripto` / `efectivo` |
| 4 | `proveedor` | Texto | No | `mercadopago` / `banco_galicia` / `binance` / etc. |
| 5 | `datos_cobro` | Texto | Sí | CBU, alias, dirección cripto, cuenta MP, etc. |
| 6 | `titular` | Texto | No | Nombre del titular de la cuenta |
| 7 | `instrucciones` | Texto | No | Instrucciones adicionales para el cliente |
| 8 | `activa` | Booleano | Sí | Solo las activas se presentan al cliente |
| 9 | `created_at` | Timestamp | Sí | |

### Ejemplo

| id_cuenta | nombre | medio | proveedor | datos_cobro | titular | activa |
|---|---|---|---|---|---|---|
| 1 | MP Vita Delta | transferencia_mp | mercadopago | Alias: vitadelta.mp | Franco G. | TRUE |
| 2 | Transferencia Galicia | transferencia_bancaria | banco_galicia | CVU: 000-xxx-xxx | Franco G. | TRUE |
| 3 | USDT TRC20 | cripto | | Dirección: TXxx... | | TRUE |

---

## 22. HOJA: DESCUENTOS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** n8n (en etapa posterior — no participa del flujo mínimo de Etapa 5B)
**Etapa origen:** 3 (prevista) — **creada para compatibilidad futura**

> **Nota:** DESCUENTOS queda creada en el Sheets desde esta etapa para no tener que agregar la hoja más adelante y romper la estructura. No participa del flujo mínimo de Etapa 5B. n8n la ignorará hasta que el motor de descuentos sea implementado en una etapa posterior.

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_descuento` | Entero | Sí | ID único autoincremental |
| 2 | `nombre` | Texto | Sí | "Descuento cliente frecuente" |
| 3 | `tipo` | Texto | Sí | `porcentaje` / `monto_fijo` / `noche_gratis` |
| 4 | `valor` | Decimal | Sí | % o monto según tipo |
| 5 | `aplica_a` | Texto | Sí | `todas` / `grande` / `chica` |
| 6 | `aplica_sobre` | Texto | Sí | `alojamiento` / `extras` / `total` |
| 7 | `fecha_desde` | Fecha | No | Inicio de vigencia. Vacío = siempre |
| 8 | `fecha_hasta` | Fecha | No | Fin de vigencia. Vacío = siempre |
| 9 | `codigo` | Texto | No | Código del cliente. Vacío = descuento automático |
| 10 | `usos_maximos` | Entero | No | Vacío = ilimitado |
| 11 | `usos_actuales` | Entero | Sí | Contador. Default 0. Solo escribe n8n |
| 12 | `minimo_noches` | Entero | No | Mínimo de noches para que aplique |
| 13 | `monto_minimo` | Monto | No | Monto mínimo de reserva para que aplique |
| 14 | `prioridad` | Entero | Sí | Orden de aplicación si hay varios (menor = primero) |
| 15 | `combinable` | Booleano | Sí | Si puede combinarse con otros descuentos |
| 16 | `requiere_aprobacion` | Booleano | Sí | Si requiere validación manual antes de aplicar |
| 17 | `activo` | Booleano | Sí | |
| 18 | `source_event` | Texto | Sí | Origen del registro |
| 19 | `created_at` | Timestamp | Sí | |
| 20 | `updated_at` | Timestamp | Sí | |

### Estados y validaciones

- `usos_actuales` solo lo escribe n8n. Franco y Rodrigo no deben modificarlo manualmente.
- Si `usos_maximos` tiene valor y `usos_actuales >= usos_maximos`, el descuento se considera agotado aunque `activo = TRUE`.
- La columna `usos_actuales` debe estar protegida contra edición manual en Sheets.

---

## 23. HOJA: GASTOS

**Categoría:** Fuente
**Escribe:** Franco / Rodrigo / Vicky
**Lee:** Franco / Rodrigo
**Etapa origen:** 1 — sin cambios estructurales

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_gasto` | Entero | Sí | ID único |
| 2 | `fecha` | Fecha | Sí | YYYY-MM-DD |
| 3 | `categoria` | Texto | Sí | `limpieza` / `mantenimiento` / `servicios` / `marketing` / `otro` |
| 4 | `descripcion` | Texto | Sí | |
| 5 | `monto` | Monto | Sí | |
| 6 | `id_cabana` | Entero | No | FK → CABAÑAS. Vacío si es gasto general del complejo |
| 7 | `pagado_por` | Texto | Sí | `Franco` / `Rodrigo` / nombre del socio |
| 8 | `reembolsable` | Booleano | Sí | Si se descuenta de utilidades |
| 9 | `comprobante_url` | Texto | No | |
| 10 | `created_at` | Timestamp | Sí | |

---

## 24. HOJA: SOCIOS

**Categoría:** Fuente
**Escribe:** Franco o Rodrigo manualmente
**Lee:** Franco / Rodrigo
**Etapa origen:** 1 — sin cambios estructurales

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_socio` | Entero | Sí | ID único |
| 2 | `nombre` | Texto | Sí | |
| 3 | `porcentaje_utilidades` | Decimal | Sí | Porcentaje de distribución |
| 4 | `whatsapp` | Texto | No | Con código de país |
| 5 | `activo` | Booleano | Sí | |

---

## 25. HOJA: LOG_CAMBIOS

**Categoría:** Fuente
**Escribe:** n8n únicamente — NUNCA editar manualmente
**Lee:** Franco / Rodrigo (auditoría)
**Etapa origen:** 1 — ampliada por todas las etapas

### Columnas

| # | Columna | Tipo | Obligatorio | Descripción |
|---|---|---|---|---|
| 1 | `id_log` | Entero | Sí | ID único autoincremental |
| 2 | `fecha_hora` | Timestamp | Sí | ISO 8601 |
| 3 | `tabla_afectada` | Texto | Sí | Nombre de la hoja afectada |
| 4 | `id_registro` | Entero | No | ID del registro modificado |
| 5 | `campo_modificado` | Texto | No | Nombre de la columna modificada |
| 6 | `valor_anterior` | Texto | No | Valor antes del cambio |
| 7 | `valor_nuevo` | Texto | No | Valor después del cambio |
| 8 | `modificado_por` | Texto | Sí | Usuario o proceso que generó el cambio |
| 9 | `source_event` | Texto | Sí | Origen del evento |
| 10 | `nivel` | Texto | Sí | `info` / `warning` / `error` |
| 11 | `detalle` | Texto | No | Información adicional en texto libre o JSON |

### Qué eventos generan log obligatoriamente

| Evento | Nivel |
|---|---|
| RESERVA creada | info |
| RESERVA cambia de estado | info |
| PRE_RESERVA creada | info |
| PRE_RESERVA vencida | info |
| PRE_RESERVA en conflicto | warning |
| PAGO confirmado | info |
| PAGO rechazado | warning |
| BLOQUEO creado o eliminado | info |
| OVERRIDE_OPERATIVO creado | info |
| Conflicto de reserva detectado | error |
| Error de API (Claude, MP, Meta) | error |
| Cambio en TARIFAS | info |
| Cambio en CONFIGURACION_GENERAL | info |
| Loop conversacional detectado | warning |
| Derivación a humano | info |
| Webhook duplicado ignorado | warning |
| Modificación manual en hoja crítica detectada | warning |

### Política de retención
LOG_CAMBIOS crece indefinidamente. No se borran registros. Si el volumen crece demasiado para Sheets, se archivan filas antiguas en una hoja `LOG_CAMBIOS_ARCHIVO` y se mantiene solo el año en curso en la hoja principal.

### Ejemplo real

| id_log | fecha_hora | tabla_afectada | id_registro | campo_modificado | valor_anterior | valor_nuevo | modificado_por | source_event | nivel |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-06-05T15:45:00Z | RESERVAS | 142 | estado | | confirmada | n8n | webhook_mp | info |
| 2 | 2026-06-05T15:45:01Z | DISPONIBILIDAD_CACHE | | | | | n8n | n8n_recalculo | info |

---

## 26. HOJAS AUXILIARES Y VISTAS OPERATIVAS

Estas hojas no son fuente de verdad. Son vistas generadas por n8n para facilitar la operación del equipo. No se editan manualmente: se regeneran automáticamente.

### VISTA_CALENDARIO

**Propósito:** Calendario visual de ocupación para el equipo (Franco, Rodrigo, Vicky, Jennifer).
**Actualiza:** n8n al confirmar, cancelar o completar una reserva.
**Contenido:** Una fila por reserva activa o futura. Columnas: cabaña, huésped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout, personas, encargado, estado, monto_total, canal_origen.
**No incluye:** Reservas canceladas o completadas hace más de 30 días.

### VISTA_PRERESERVAS_ACTIVAS

**Propósito:** Panel para Vicky de pre-reservas pendientes de pago.
**Actualiza:** n8n cada vez que cambia el estado de una PRE_RESERVA.
**Contenido:** Solo PRE_RESERVAS en estado `pendiente_pago`. Columnas: id, cabaña, huésped, teléfono, fechas, monto_sena, canal_pago_esperado, expira_en, minutos_restantes (columna calculada en Sheets).
**Uso:** Vicky ve de un vistazo qué pre-reservas están por vencer y puede actuar.

### VISTA_OCUPACION

**Propósito:** Dashboard de ocupación para Franco y Rodrigo.
**Actualiza:** n8n una vez por día en el recálculo masivo.
**Contenido:** Resumen de disponibilidad por cabaña para los próximos 30 días. Formato de grilla: filas = cabañas, columnas = días, celdas = estado (disponible / ocupada / bloqueada).

---

## 27. PERMISOS Y PROTECCIÓN DE HOJAS

### Matriz de permisos

| Hoja | Franco/Rodrigo | Vicky | n8n | Bot/Web |
|---|---|---|---|---|
| CABAÑAS | R+W | R | R | R |
| HUÉSPEDES | R+W | R+W | R+W | R (crear) |
| FERIADOS | R+W | R | R | — |
| TARIFAS | R+W | R | R | R |
| TEMPORADAS | R+W | R | R | R |
| EVENTOS_ESPECIALES | R+W | R | R | R |
| PAQUETES_EVENTO | R+W | R | R | R |
| CONSULTAS | R | R | R+W | — |
| PRE_RESERVAS | R | R | R+W | — |
| RESERVAS | R+W* | R+W* | R+W | — |
| PAGOS | R+W* | R+W* | R+W | — |
| DISPONIBILIDAD_CACHE | R | R | R+W | R |
| BLOQUEOS | R+W | R+W** | R | — |
| OVERRIDES_OPERATIVOS | R+W | R | R | — |
| CONFIGURACION_GENERAL | R+W | R | R | — |
| PLANTILLAS_MENSAJES | R+W | R+W | R | — |
| CUENTAS_COBRO | R+W | R | R | R |
| GASTOS | R+W | R+W | — | — |
| DESCUENTOS | R+W | R | R (futuro) | — |
| SOCIOS | R+W | — | — | — |
| LOG_CAMBIOS | R | — | W | — |
| VISTAS | R | R | W | — |

*Solo transiciones específicas documentadas en Sección 14 y 15.
**Vicky puede crear bloqueos con motivos operativos; bloqueos de uso propio los crean Franco o Rodrigo.

### Protecciones a configurar en Sheets

**Hojas de solo lectura para edición humana (solo escribe n8n):**
- CONSULTAS → proteger toda la hoja
- PRE_RESERVAS → proteger toda la hoja
- DISPONIBILIDAD_CACHE → proteger toda la hoja
- LOG_CAMBIOS → proteger toda la hoja

**Hojas con rangos protegidos parcialmente:**
- RESERVAS → proteger columnas id_reserva, id_prereserva, created_at, updated_at, source_event
- PAGOS → proteger columnas id_pago, created_at, updated_at, es_automatico, referencia_externa, tx_hash
- CONFIGURACION_GENERAL → proteger columna `clave` (solo se edita `valor` y `descripcion`)

**Hojas libremente editables por el equipo autorizado:**
- CABAÑAS, FERIADOS, TARIFAS, TEMPORADAS, BLOQUEOS, GASTOS, PLANTILLAS_MENSAJES, CUENTAS_COBRO

---

## 28. TRAZABILIDAD ENTRE ETAPAS

| Hoja / Campo | Etapa que lo originó | Motivo |
|---|---|---|
| CABAÑAS | 1 | Entidad base del sistema |
| HUÉSPEDES | 1 | Entidad base del sistema |
| FERIADOS | 1 | Necesario para motor de disponibilidad |
| TARIFAS — estructura base | 1 | Motor de precios básico |
| TARIFAS — conceptos completos | 3 | Motor de precios con jerarquía completa |
| TEMPORADAS | 3 | Multiplicadores de precio por temporada |
| EVENTOS_ESPECIALES | 3 | Motor separado para Año Nuevo y similares |
| PAQUETES_EVENTO | 3 | Precios fijos de eventos especiales |
| CONSULTAS — estructura base | 1 | Flujo de conversación |
| CONSULTAS — contexto_json, tokens_json, motivo_derivacion | 4A+4B | Motor de reservas y bot conversacional |
| PRE_RESERVAS — estructura base | 1 | Bloqueo temporal |
| PRE_RESERVAS — intentos_pago, canal_pago_esperado | 4A | Arquitectura multicanal de pagos |
| RESERVAS — estructura base | 1 | Reserva confirmada |
| RESERVAS — encargado_semana, monto_saldo, campo notas para trazabilidad | 4A | Operación del equipo y modificaciones |
| PAGOS — estructura base | 1 | Pagos simples |
| PAGOS — arquitectura multicanal completa | 4A | Soporte para transferencia, MP, cripto, efectivo |
| DISPONIBILIDAD_CACHE | 1+2 | Precálculo de disponibilidad |
| BLOQUEOS | 1 | Bloqueos manuales |
| OVERRIDES_OPERATIVOS | 2 | Excepciones operativas sin tocar código |
| CONFIGURACION_GENERAL — claves base | 1 | Parámetros del sistema |
| CONFIGURACION_GENERAL — escalonamiento | 2 | Motor de disponibilidad |
| CONFIGURACION_GENERAL — precios y estadía larga | 3 | Motor de precios |
| CONFIGURACION_GENERAL — pre-reservas y encargado | 4A | Motor de reservas |
| CONFIGURACION_GENERAL — bot y clasificador | 4B | Bot conversacional |
| PLANTILLAS_MENSAJES | 4A+4B | Mensajes automáticos y FAQ del bot |
| CUENTAS_COBRO | 4A | Medios de pago presentados al cliente |
| GASTOS | 1 | Contabilidad de egresos |
| DESCUENTOS | 3 (prevista) | Compatibilidad futura — no activa en Etapa 5B |
| SOCIOS | 1 | Distribución de utilidades |
| LOG_CAMBIOS | 1+ todas | Auditoría de todo el sistema |
| VISTAS | 4A | Panel operativo del equipo |

---

## 29. CHECKLIST DE CREACIÓN

Orden recomendado para crear el Sheets desde cero. Cada paso depende del anterior.

### Fase 1 — Estructura base

- [ ] Crear el Google Sheets con nombre: "Vita Delta — Sistema de Reservas"
- [ ] Crear todas las hojas en el orden del Mapa General (Sección 4)
- [ ] En cada hoja: escribir los nombres de columnas en la fila 1 exactamente como se especifica en este documento (snake_case, sin espacios, sin tildes)
- [ ] Aplicar formato de encabezado a la fila 1 de cada hoja (negrita, color de fondo para distinguir)
- [ ] Congelar la fila 1 en todas las hojas

### Fase 2 — Datos iniciales obligatorios

- [ ] Cargar las 5 cabañas en CABAÑAS (datos de Sección 5)
- [ ] Cargar los 3 socios en SOCIOS
- [ ] Cargar temporadas iniciales en TEMPORADAS (al menos temporada media y alta del año en curso)
- [ ] Cargar evento Año Nuevo en EVENTOS_ESPECIALES (con precios en 0 como placeholder)
- [ ] Cargar paquetes de Año Nuevo en PAQUETES_EVENTO (con precios en 0)
- [ ] Cargar tarifas base en TARIFAS (al menos los conceptos de Sección 8 para grande y chica)
- [ ] Cargar CONFIGURACION_GENERAL con todas las claves de Sección 19
- [ ] Cargar CUENTAS_COBRO con los medios de pago activos (Sección 21)
- [ ] Cargar PLANTILLAS_MENSAJES con las plantillas mínimas (Sección 20)
- [ ] Dejar DESCUENTOS vacía — no requiere datos iniciales (Sección 22)

### Fase 3 — Validaciones de datos

- [ ] En CABAÑAS: validación de lista para columna `tipo` (grande / chica)
- [ ] En CABAÑAS: validación de lista para columnas booleanas (TRUE / FALSE)
- [ ] En TARIFAS: validación de lista para `concepto` con todos los valores válidos
- [ ] En TARIFAS: validación de lista para `tipo_cabana`
- [ ] En RESERVAS: validación de lista para `estado` con todos los estados válidos
- [ ] En PRE_RESERVAS: validación de lista para `estado`
- [ ] En PAGOS: validación de lista para `estado` y `medio_pago`
- [ ] En BLOQUEOS: validación de lista para `motivo`
- [ ] En OVERRIDES_OPERATIVOS: validación de lista para `tipo_override`
- [ ] En CONFIGURACION_GENERAL: proteger columna `clave` contra edición

### Fase 4 — Protecciones

- [ ] Proteger hoja completa: CONSULTAS, PRE_RESERVAS, DISPONIBILIDAD_CACHE, LOG_CAMBIOS
- [ ] Proteger rangos de columnas de sistema en RESERVAS y PAGOS (ver Sección 27)
- [ ] Proteger columna `usos_actuales` en DESCUENTOS contra edición manual
- [ ] Verificar que Vicky tiene acceso de editor solo a las hojas que le corresponden
- [ ] Verificar que la cuenta de servicio de n8n tiene acceso de editor al Sheets completo

### Fase 5 — Datos de feriados

- [ ] Cargar los feriados nacionales del año en curso en FERIADOS
- [ ] Verificar que el tipo `ano_nuevo` está asignado correctamente a 31 dic y 1 ene

### Fase 6 — Verificación final

- [ ] Revisar que ninguna hoja tenga columnas sin nombre en la fila 1
- [ ] Revisar que los IDs iniciales estén en 1 (o en el valor correcto si se importan datos de un sistema previo)
- [ ] Revisar que DISPONIBILIDAD_CACHE esté vacía (se poblará con el primer recálculo masivo de n8n)
- [ ] Revisar que LOG_CAMBIOS esté vacía
- [ ] Compartir el Sheets con todos los miembros del equipo según los permisos de Sección 26
- [ ] Documentar la URL del Sheets en CONFIGURACION_GENERAL como clave `sheets_url`

---

*Documento generado como parte del proceso de diseño del sistema Complejo Vita Delta.*
*Siguiente: ETAPA_5B — Implementación de workflows base en n8n.*
