# PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
# Plan Operativo — Implementación Real del Sistema de Reservas

**Versión:** 1.0
**Fecha:** Mayo 2026
**Estado:** Aprobado — activo
**Tipo de documento:** Plan de ejecución (no arquitectura)
**Depende de:** ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md v1.0 y ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md v1.1
**Autores:** Franco (titular) + Claude (copiloto técnico)

---

## ÍNDICE

1. Propósito y alcance de este documento
2. Separación de entornos
3. Fase 1 — Crear los Sheets
4. Fase 2 — Crear todas las hojas
5. Fase 3 — Cargar datos mínimos
6. Fase 4 — Validaciones de datos
7. Fase 5 — Protecciones por entorno
8. Fase 6 — Verificación final
9. Qué errores evitar
10. Próximo paso: n8n
11. Checklist de cierre de jornada

---

## 1. PROPÓSITO Y ALCANCE

Este documento es un plan de ejecución paso a paso para implementar lo ya definido en las Etapas 5A y 5B. No introduce arquitectura nueva ni reabre decisiones cerradas.

El objetivo de esta etapa de implementación es crear los Google Sheets `VITA_DELTA_DEV` y `VITA_DELTA_TEST` con la estructura y datos mínimos necesarios para ejecutar el primer workflow de n8n: `db_recalcular_disponibilidad`.

### Qué incluye este documento

- Instrucciones concretas para crear y configurar los Sheets
- Datos exactos a cargar hoja por hoja
- Validaciones y protecciones diferenciadas por entorno
- Checklist de verificación antes de avanzar a n8n

### Qué no incluye

- Implementación de workflows de n8n
- Conexión con WhatsApp, Instagram, MercadoPago o Claude API
- Arquitectura nueva o modificación de decisiones cerradas
- Configuración del entorno PROD (se activa solo cuando TEST está validado)

---

## 2. SEPARACIÓN DE ENTORNOS

### Los tres Sheets del sistema

| Entorno | Nombre del Sheets | Propósito | Estado en esta jornada |
|---|---|---|---|
| DEV | `VITA_DELTA_DEV` | Sandbox de desarrollo. Datos ficticios. Se puede romper sin consecuencias. | Crear y poblar |
| TEST | `VITA_DELTA_TEST` | Pruebas controladas del flujo completo. Datos realistas pero no productivos. | Crear y poblar |
| PROD | `VITA_DELTA_PROD` | Producción real con clientes. Solo se activa cuando TEST está validado. | No tocar en esta jornada |

### Regla absoluta de entornos

Nunca ejecutar workflows de DEV o TEST apuntando al Sheets ID de PROD. Nunca copiar datos productivos de PROD a DEV sin anonimizarlos. La separación es permanente e innegociable.

### Variables de entorno en n8n (referencia — se configuran en la siguiente jornada)

| Variable | DEV | TEST | PROD |
|---|---|---|---|
| `ENTORNO` | `dev` | `test` | `prod` |
| `SHEETS_ID` | ID del Sheets DEV | ID del Sheets TEST | ID del Sheets PROD |
| `LOG_NIVEL_MINIMO` | `info` | `info` | `warning` |

El ID de un Sheets se obtiene de su URL: `https://docs.google.com/spreadsheets/d/**ID_ACA**/edit`

---

## 3. FASE 1 — CREAR LOS SHEETS

### Acción

Crear dos Google Sheets nuevos desde cero en Google Drive.

### Nombres exactos

- `VITA_DELTA_DEV`
- `VITA_DELTA_TEST`

Los nombres deben ser exactamente iguales, incluyendo mayúsculas y guiones bajos. Son los identificadores internos del sistema.

### Accesos iniciales

Compartir cada Sheets con:
- Cuenta personal de Franco: editor
- Cuenta de Rodrigo: editor
- Cuenta de Vicky: editor (con restricciones según permisos de Etapa 5A)

La cuenta de servicio de n8n se agrega cuando se configura n8n en la jornada siguiente.

### Convenciones que aplican a todos los Sheets

- **Nombres de hojas:** Respetar exactamente los nombres definidos en los documentos de arquitectura, incluyendo tildes y caracteres especiales cuando corresponda (ej: `CABAÑAS`, `HUÉSPEDES`). Los nombres de hojas son identificadores visibles para el equipo y deben coincidir con la arquitectura.
- **Nombres de columnas:** Siempre en snake_case, sin tildes, sin espacios y sin caracteres especiales (ej: `id_huesped`, `fecha_checkin`). Los nombres de columnas los consume n8n directamente; cualquier tilde o caracter especial rompe las queries.
- **Fechas:** Siempre en texto YYYY-MM-DD, nunca como tipo Fecha de Sheets. **Instrucción práctica:** antes de pegar fechas en cualquier columna de fecha, seleccionar esa columna completa y aplicar Formato → Número → Texto sin formato. Esto evita que Google Sheets convierta automáticamente las fechas a su formato interno al momento de pegar.
- **Timestamps:** texto ISO 8601 — solo escribe n8n; en hojas manuales se puede dejar vacío o poner la fecha de creación a mano en formato `YYYY-MM-DDTHH:MM:SSZ`
- **Montos:** número sin símbolo de moneda y sin puntos de miles (ej: `350000`, no `$350.000`)
- **Booleanos:** `TRUE` o `FALSE` en mayúsculas (tipo Booleano de Sheets, no texto)
- **Nulos:** celda vacía — nunca escribir "null", "-", "N/A" o "ninguno"

---

## 4. FASE 2 — CREAR TODAS LAS HOJAS

### Orden de creación

Crear las hojas en este orden exacto dentro de cada Sheets. El orden respeta las dependencias del sistema y facilita la navegación del equipo.

**Hojas fuente (datos primarios):**

```
1.  CABAÑAS
2.  HUÉSPEDES
3.  FERIADOS
4.  TARIFAS
5.  TEMPORADAS
6.  EVENTOS_ESPECIALES
7.  PAQUETES_EVENTO
8.  CONSULTAS
9.  PRE_RESERVAS
10. RESERVAS
11. PAGOS
12. DISPONIBILIDAD_CACHE
13. BLOQUEOS
14. OVERRIDES_OPERATIVOS
15. CONFIGURACION_GENERAL
16. PLANTILLAS_MENSAJES
17. CUENTAS_COBRO
18. GASTOS
19. DESCUENTOS
20. SOCIOS
21. LOG_CAMBIOS
```

**Hojas auxiliares y vistas:**

```
22. VISTA_CALENDARIO
23. VISTA_PRERESERVAS_ACTIVAS
24. VISTA_OCUPACION
```

### Formato de encabezados (aplica a todas las hojas)

1. Escribir los nombres de columna exactamente como se especifican abajo (snake_case, sin tildes)
2. Aplicar negrita a la fila 1 completa
3. Aplicar color de fondo a la fila 1 para distinguirla visualmente (gris claro o azul claro)
4. Inmovilizar la fila 1: Menú Ver → Inmovilizar → 1 fila

### Encabezados por hoja

A continuación están los encabezados exactos de cada hoja. Copiar tal cual, sin modificar el orden ni los nombres.

---

#### CABAÑAS
```
id_cabana | nombre | tipo | capacidad_base | capacidad_max | activa | bloqueada | motivo_bloqueo | orden_limpieza | descripcion | fotos_urls | created_at
```

#### HUÉSPEDES
```
id_huesped | nombre | apellido | dni | telefono | email | canal_preferido | primera_reserva_fecha | total_reservas | notas_internas | created_at | updated_at
```

#### FERIADOS
```
fecha | nombre | tipo | activo
```

#### TARIFAS
```
id_tarifa | tipo_cabana | concepto | precio | descripcion | activa | valida_desde | valida_hasta | created_at | updated_at
```

#### TEMPORADAS
```
id_temporada | nombre | fecha_desde | fecha_hasta | multiplicador | activa | created_at
```

#### EVENTOS_ESPECIALES
```
id_evento | nombre | fecha_desde | fecha_hasta | modo_precio | reglas_especiales | activa | source_event | created_at
```

#### PAQUETES_EVENTO
```
id_paquete | id_evento | tipo_cabana | nombre_paquete | fecha_in | fecha_out | precio_total | personas_max | incluye | notas | activo | created_at
```

#### CONSULTAS
```
id_consulta | canal | id_contacto_externo | id_huesped | estado_conversacion | id_cabana_tentativa | fecha_in_tentativa | fecha_out_tentativa | personas_tentativa | ultimo_mensaje_at | contexto_json | tokens_json | motivo_derivacion | source_event | created_at | updated_at
```

#### PRE_RESERVAS
```
id_prereserva | id_consulta | id_cabana | id_huesped | fecha_in | fecha_out | hora_checkin | hora_checkout | personas | monto_total | monto_sena | estado | expira_en | canal_pago_esperado | canal_origen | intentos_pago | referencia_mp | notas | source_event | created_at | updated_at
```

#### RESERVAS
```
id_reserva | id_prereserva | id_cabana | id_huesped | fecha_checkin | fecha_checkout | hora_checkin | hora_checkout | personas | estado | canal_origen | id_tarifa_aplicada | monto_total | monto_sena | monto_saldo | mascotas | detalle_mascotas | ninos | encargado_semana | notas | created_by | source_event | created_at | updated_at
```

#### PAGOS
```
id_pago | id_prereserva | id_reserva | tipo | medio_pago | proveedor | cuenta_destino | monto_esperado | monto_recibido | moneda | estado | es_automatico | comprobante_url | referencia_externa | tx_hash | validado_por | validado_en | motivo_rechazo | notas | source_event | created_at | updated_at
```

#### DISPONIBILIDAD_CACHE
```
id_cabana | fecha | estado | hora_checkin_minima | hora_checkin_maxima | hora_checkout_maxima | hora_checkout_minima | tipo_dia | temporada | es_ultimo_dia_bloque | minimo_noches | id_reserva_activa | id_prereserva_activa | recalculado_en
```

#### BLOQUEOS
```
id_bloqueo | id_cabana | fecha_desde | fecha_hasta | motivo | descripcion | creado_por | activo | source_event | created_at
```

#### OVERRIDES_OPERATIVOS
```
id_override | fecha_desde | fecha_hasta | id_cabana | tipo_override | valor | motivo | creado_por | activo | source_event | created_at
```

#### CONFIGURACION_GENERAL
```
clave | valor | descripcion
```

#### PLANTILLAS_MENSAJES
```
id_plantilla | nombre | canal | evento_disparador | texto | keywords | score_minimo | destinatario | activa | created_at
```

#### CUENTAS_COBRO
```
id_cuenta | nombre | medio | proveedor | datos_cobro | titular | instrucciones | activa | created_at
```

#### GASTOS
```
id_gasto | fecha | categoria | descripcion | monto | id_cabana | pagado_por | reembolsable | comprobante_url | created_at
```

#### DESCUENTOS
```
id_descuento | nombre | tipo | valor | aplica_a | aplica_sobre | fecha_desde | fecha_hasta | codigo | usos_maximos | usos_actuales | minimo_noches | monto_minimo | prioridad | combinable | requiere_aprobacion | activo | source_event | created_at | updated_at
```

#### SOCIOS
```
id_socio | nombre | porcentaje_utilidades | whatsapp | activo
```

#### LOG_CAMBIOS
```
id_log | fecha_hora | tabla_afectada | id_registro | campo_modificado | valor_anterior | valor_nuevo | modificado_por | source_event | nivel | detalle
```

#### VISTA_CALENDARIO
```
id_cabana | nombre_cabana | fecha | estado_display | id_reserva | nombre_huesped | hora_checkin | hora_checkout | encargado_semana
```

#### VISTA_PRERESERVAS_ACTIVAS
```
id_prereserva | nombre_cabana | nombre_huesped | telefono | fecha_in | fecha_out | monto_sena | canal_pago_esperado | expira_en
```

#### VISTA_OCUPACION
```
(hoja vacía — n8n genera la estructura dinámica)
```

---

## 5. FASE 3 — CARGAR DATOS MÍNIMOS

Las siguientes hojas necesitan datos cargados antes del primer workflow. El resto puede quedar vacío.

### Criterio de precios para DEV y TEST

Los precios en DEV y TEST deben ser valores ficticios pero mayores a 0. El precio 0 está reservado exclusivamente para `PAQUETES_EVENTO`, donde el sistema ya tiene una regla de bloqueo explícita. En cualquier otra hoja, precio 0 produce errores silenciosos o comportamientos inesperados en el motor de precios.

**Regla:** En DEV usar precios ficticios reducidos (ej: 1000, 2000) para facilitar cálculos mentales durante pruebas. En TEST usar precios representativos reales (los que el complejo cobra actualmente).

---

### CABAÑAS — 5 filas

Datos fijos y reales. No varían entre DEV y TEST.

| id_cabana | nombre | tipo | capacidad_base | capacidad_max | activa | bloqueada | motivo_bloqueo | orden_limpieza | descripcion | fotos_urls | created_at |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Bamboo | grande | 3 | 5 | TRUE | FALSE | | 1 | | | |
| 2 | Madre Selva | grande | 3 | 5 | TRUE | FALSE | | 2 | | | |
| 3 | Arrebol | grande | 3 | 5 | TRUE | FALSE | | 3 | | | |
| 4 | Guatemala | chica | 2 | 4 | TRUE | FALSE | | 4 | | | |
| 5 | Tokio | chica | 2 | 4 | TRUE | FALSE | | 5 | | | |

El campo `created_at` se puede dejar vacío en esta carga manual. n8n no lo escribe en esta hoja (la escribe solo el operador); si querés completarlo, usá el formato `2026-05-10T12:00:00Z`.

---

### TARIFAS — mínimo 10 conceptos

Los conceptos obligatorios para el flujo mínimo son `semana_1`, `semana_2`, `semana_3`, `finde_completo` y `semana_completa` para ambos tipos de cabaña, más `extra_persona_noche`.

**Precios para DEV (ficticios, mayores a 0):**

| id_tarifa | tipo_cabana | concepto | precio | descripcion | activa | valida_desde | valida_hasta | created_at | updated_at |
|---|---|---|---|---|---|---|---|---|---|
| 1 | grande | semana_1 | 1000 | 1 noche semana — grande | TRUE | | | | |
| 2 | grande | semana_2 | 1800 | 2 noches semana — grande | TRUE | | | | |
| 3 | grande | semana_3 | 2500 | 3 noches semana — grande | TRUE | | | | |
| 4 | grande | finde_completo | 2200 | Finde vie+sáb — grande | TRUE | | | | |
| 5 | grande | semana_completa | 5000 | 7 noches — grande | TRUE | | | | |
| 6 | grande | extra_persona_noche | 100 | Persona extra por noche | TRUE | | | | |
| 7 | chica | semana_1 | 800 | 1 noche semana — chica | TRUE | | | | |
| 8 | chica | semana_2 | 1400 | 2 noches semana — chica | TRUE | | | | |
| 9 | chica | finde_completo | 1800 | Finde vie+sáb — chica | TRUE | | | | |
| 10 | chica | semana_completa | 4000 | 7 noches — chica | TRUE | | | | |
| 11 | chica | extra_persona_noche | 100 | Persona extra por noche | TRUE | | | | |

**Precios para TEST:** Reemplazar con los precios reales actuales del complejo. La estructura de filas y conceptos es idéntica.

Los conceptos de TARIFAS que no están cargados en esta fase simplemente no se usan en el flujo mínimo. Se pueden agregar más adelante sin romper nada.

---

### TEMPORADAS — 2 filas iniciales

Aplican igual en DEV y TEST. Revisar que las fechas cubran el período en el que se van a ejecutar las pruebas.

| id_temporada | nombre | fecha_desde | fecha_hasta | multiplicador | activa | created_at |
|---|---|---|---|---|---|---|
| 1 | Temporada media 2026 | 2026-05-01 | 2026-11-30 | 1.00 | TRUE | |
| 2 | Temporada alta verano 2026-2027 | 2026-12-01 | 2027-02-28 | 1.20 | TRUE | |

**Verificación crítica:** Las fechas no deben solaparse. Si la fecha de hoy cae fuera de ambos rangos, el motor de precios no va a encontrar temporada y va a fallar. Si se necesita un rango adicional (por ejemplo, baja temporada), agregarlo ahora.

---

### CONFIGURACION_GENERAL — lista completa de claves

Esta hoja tiene exactamente 3 columnas: `clave`, `valor`, `descripcion`. Cargar todas las filas de la tabla siguiente. El valor de la columna `descripcion` es opcional pero muy recomendado para que el equipo entienda qué hace cada parámetro.

**Horarios:**

| clave | valor | descripcion |
|---|---|---|
| hora_checkin_default | 13:00 | Check-in estándar |
| hora_checkout_default | 10:00 | Check-out estándar |
| hora_checkin_domingo | 18:00 | Check-in cuando domingo es primer día |
| hora_checkout_ultimo_dia_bloque | 16:00 | Check-out del último día del bloque |
| hora_checkin_max_cliente | 22:00 | Hora máxima de entrada que puede elegir el cliente |
| hora_checkout_min_cliente | 07:00 | Hora mínima de salida que puede elegir el cliente |

**Escalonamiento:**

| clave | valor | descripcion |
|---|---|---|
| escalonamiento_activo | true | Master switch del escalonamiento |
| escalonamiento_umbral_checkout | 3 | Checkouts simultáneos que activan escalonamiento de checkin |
| escalonamiento_umbral_checkin | 3 | Checkins simultáneos que activan escalonamiento de checkout |
| escalonamiento_minutos | 45 | Minutos de ajuste por cabaña adicional |
| escalonamiento_checkin_max | 22:00 | Límite máximo de check-in por escalonamiento |
| escalonamiento_checkout_min | 09:00 | Límite mínimo de checkout por escalonamiento |
| escalonamiento_checkout_max_minutos | 60 | Máximo minutos de adelanto en checkout |
| escalonamiento_checkout_tramo_minutos | 30 | Minutos por tramo en escalonamiento de checkout |

**Flexibilidad del cliente:**

| clave | valor | descripcion |
|---|---|---|
| checkin_flexible_activo | true | Si el cliente puede elegir hora de entrada |
| checkout_flexible_activo | true | Si el cliente puede elegir hora de salida |

**Temporada:**

| clave | valor | descripcion |
|---|---|---|
| temporada_alta_inicio | 12-01 | MM-DD inicio temporada alta |
| temporada_alta_fin | 02-28 | MM-DD fin temporada alta |
| finde_minimo_noches_temp_alta | 2 | Mínimo de noches en finde durante temporada alta |

**Precios:**

| clave | valor | descripcion |
|---|---|---|
| sena_porcentaje | 50 | % de seña sobre el total |
| precio_redondeo_base | 1000 | Redondear al millar más cercano |
| precio_descuento_minimo | 10000 | Precio mínimo permitido post-descuento |

**Estadía larga:**

| clave | valor | descripcion |
|---|---|---|
| estadia_larga_minimo_noches | 28 | Mínimo noches para nivel estadía larga |
| estadia_larga_permitida_temp_alta | true | Si se permiten en temporada alta |
| estadia_larga_max_noches_temp_alta | | Vacío = sin límite |
| estadia_larga_cobra_sobrantes_temp_alta | false | |
| estadia_larga_permitida_temp_media | true | |
| estadia_larga_cobra_sobrantes_temp_media | false | |
| estadia_larga_permitida_temp_baja | true | |
| estadia_larga_cobra_sobrantes_temp_baja | false | |

**Pre-reservas y reservas:**

| clave | valor | descripcion |
|---|---|---|
| prereserva_expiracion_minutos | 60 | Tiempo de vida de una PRE_RESERVA sin pago |
| prereserva_notificacion_vencimiento_umbral | 200000 | Monto desde el que se notifica al vencer |
| prereserva_recordatorio_minutos_antes | 15 | Minutos antes del vencimiento para recordatorio |
| prereserva_pago_en_revision_alerta_horas | 2 | Horas con pago en revisión antes de escalar alerta a Franco/Rodrigo |
| diferencia_pago_tolerancia | 5000 | Diferencia máxima de monto aceptable sin consultar |

**Checkout tardío:**

| clave | valor | descripcion |
|---|---|---|
| checkout_recordatorio_horas_despues | 2 | Horas post-checkout sin registrar para enviar recordatorio |

**Encargado semanal:**

| clave | valor | descripcion |
|---|---|---|
| encargado_ciclo_inicio_fecha | 2026-05-11 | Fecha inicio del ciclo Franco/Rodrigo — completar con fecha real |
| encargado_ciclo_inicio_nombre | Franco | Quién arranca el ciclo — completar con nombre real |

**Conversaciones (Bot — referencia futura):**

| clave | valor | descripcion |
|---|---|---|
| conversacion_expiracion_horas | 24 | Horas de inactividad para cerrar una CONSULTA |
| contexto_max_turnos | 20 | Máximo de turnos en la ventana activa del contexto |
| contexto_max_chars | 8000 | Máximo de caracteres en el JSON de contexto |
| contexto_resumen_trigger | 15 | Turnos desde los que se genera resumen |
| clasificador_faq_umbral | 0.85 | Confianza mínima para responder FAQ sin IA |
| clasificador_activo | true | Master switch del clasificador previo |

**Cache:**

| clave | valor | descripcion |
|---|---|---|
| cache_horizonte_meses | 18 | Meses hacia adelante que mantiene la cache |
| cache_recalculo_masivo_hora | 03:00 | Hora del recálculo nocturno |

**Sistema general:**

| clave | valor | descripcion |
|---|---|---|
| max_cabanas_sistema | 10 | Límite configurable de cabañas |
| whatsapp_franco | +549XXXXXXXXXX | Número de WhatsApp de Franco — cargar directamente en Sheets, no en el repositorio |
| whatsapp_rodrigo | +549XXXXXXXXXX | Número de WhatsApp de Rodrigo — cargar directamente en Sheets, no en el repositorio |
| whatsapp_jennifer | +549XXXXXXXXXX | Número de WhatsApp de Jennifer — cargar directamente en Sheets, no en el repositorio |
| sheets_url | (completar con la URL del Sheets correspondiente al entorno) | URL del Sheets activo. En VITA_DELTA_DEV cargar la URL del Sheet DEV; en VITA_DELTA_TEST cargar la URL del Sheet TEST. |

**Alertas:**

| clave | valor | descripcion |
|---|---|---|
| alerta_derivacion_tasa_umbral | 0.40 | Tasa de derivación que dispara alerta a Franco |
| alerta_errores_api_por_hora | 5 | Errores técnicos por hora que disparan alerta |
| alerta_costo_diario_usd | 5 | Costo diario estimado que dispara alerta |

**Nota sobre DEV:** En el Sheets DEV se puede ajustar `prereserva_expiracion_minutos` a un valor bajo (ej: 2) para facilitar las pruebas de vencimiento sin esperar 60 minutos.

---

### CUENTAS_COBRO — mínimo 1 fila activa

Al menos una cuenta activa de tipo `transferencia_bancaria`. Sin esta fila, n8n no puede armar el mensaje de instrucciones de pago.

| id_cuenta | nombre | medio | proveedor | datos_cobro | titular | instrucciones | activa | created_at |
|---|---|---|---|---|---|---|---|---|
| 1 | Transferencia bancaria | transferencia_bancaria | (nombre del banco) | CBU/CVU o alias real | (titular de la cuenta) | Transferir exactamente el monto indicado con el nombre del titular como referencia | TRUE | |

Completar `datos_cobro` y `titular` con los datos reales del complejo. Para DEV se puede usar un alias ficticio.

---

### PLANTILLAS_MENSAJES — mínimo 2 filas

Las dos plantillas mínimas para el flujo de Etapa 5B. El texto puede ser un borrador; se refina antes de conectar WhatsApp.

| id_plantilla | nombre | canal | evento_disparador | texto | keywords | score_minimo | destinatario | activa | created_at |
|---|---|---|---|---|---|---|---|---|---|
| 1 | prereserva_creada | todos | prereserva_created | Hola {nombre}! Te confirmamos la pre-reserva para {nombre_cabana} del {fecha_in} al {fecha_out} para {personas} personas. El monto de la seña es ${monto_sena}. Te enviamos los datos de pago en el próximo mensaje. Tenés {expiracion_minutos} minutos para completarla. | | | huesped | TRUE | |
| 2 | nueva_reserva_equipo | whatsapp | reserva_confirmed | RESERVA CONFIRMADA — Cabaña: {nombre_cabana} / Fechas: {fecha_checkin} → {fecha_checkout} / Huésped: {nombre} / Personas: {personas} / Encargado semana: {encargado_semana} / Saldo pendiente: ${saldo} | | | equipo | TRUE | |

---

### SOCIOS — 3 filas

| id_socio | nombre | porcentaje_utilidades | whatsapp | activo |
|---|---|---|---|---|
| 1 | Franco | (% real) | +549... | TRUE |
| 2 | Rodrigo | (% real) | +549... | TRUE |
| 3 | (nombre del tercer socio) | (% real) | +549... | TRUE |

Los porcentajes deben sumar 100. Decisión de Franco antes de cargar.

---

### Hojas que quedan vacías (obligatorio)

Las siguientes hojas deben existir pero no tener datos al arrancar:

```
HUÉSPEDES · FERIADOS · EVENTOS_ESPECIALES · PAQUETES_EVENTO
CONSULTAS · PRE_RESERVAS · RESERVAS · PAGOS
DISPONIBILIDAD_CACHE · BLOQUEOS · OVERRIDES_OPERATIVOS
GASTOS · DESCUENTOS · LOG_CAMBIOS
VISTA_CALENDARIO · VISTA_PRERESERVAS_ACTIVAS · VISTA_OCUPACION
```

`DISPONIBILIDAD_CACHE` y `LOG_CAMBIOS` se poblan exclusivamente con el primer workflow de n8n. Si tienen datos cargados manualmente antes de eso, el primer recálculo va a producir resultados inconsistentes.

---

## 6. FASE 4 — VALIDACIONES DE DATOS

Configurar validaciones de lista en las siguientes columnas. En Google Sheets: seleccionar la columna (desde fila 2 hacia abajo), ir a Datos → Validación de datos → Lista de elementos.

| Hoja | Columna | Valores válidos |
|---|---|---|
| CABAÑAS | `tipo` | `grande, chica` |
| CABAÑAS | `activa` | `TRUE, FALSE` |
| CABAÑAS | `bloqueada` | `TRUE, FALSE` |
| TARIFAS | `tipo_cabana` | `grande, chica` |
| TARIFAS | `concepto` | `semana_1, semana_2, semana_3, semana_4, semana_5, semana_marginal_6plus, finde_1_noche, finde_completo, feriado_aislado, feriado_adicional, semana_completa, semana_adicional, marginal_fijo_finde_semana, extra_persona_noche` |
| TARIFAS | `activa` | `TRUE, FALSE` |
| TEMPORADAS | `activa` | `TRUE, FALSE` |
| RESERVAS | `estado` | `confirmada, activa, completada, cancelada, cancelada_con_cargo, conflicto_pendiente` |
| RESERVAS | `canal_origen` | `whatsapp, instagram, web, airbnb, booking, manual` |
| RESERVAS | `mascotas` | `TRUE, FALSE` |
| RESERVAS | `ninos` | `TRUE, FALSE` |
| RESERVAS | `encargado_semana` | `Franco, Rodrigo` |
| PRE_RESERVAS | `estado` | `pendiente_pago, vencida, convertida, cancelada_por_cliente, cancelada_por_bloqueo, conflicto_pendiente` |
| PRE_RESERVAS | `canal_pago_esperado` | `mp_link, transferencia_bancaria, transferencia_mp, cripto, efectivo` |
| PRE_RESERVAS | `canal_origen` | `whatsapp, instagram, web, manual` |
| PAGOS | `tipo` | `sena, saldo, extra, reembolso` |
| PAGOS | `medio_pago` | `mp_link, transferencia_mp, transferencia_bancaria, tarjeta, efectivo, cripto` |
| PAGOS | `moneda` | `ARS, USD, USDT, BTC` |
| PAGOS | `estado` | `pendiente, en_revision, confirmado, rechazado, reembolsado` |
| PAGOS | `es_automatico` | `TRUE, FALSE` |
| BLOQUEOS | `motivo` | `mantenimiento, uso_propio, tormenta, overbooking, otro` |
| BLOQUEOS | `activo` | `TRUE, FALSE` |
| OVERRIDES_OPERATIVOS | `tipo_override` | `escalonamiento_activo, escalonamiento_umbral_checkout, escalonamiento_umbral_checkin, hora_checkin, hora_checkout, checkin_flexible, checkout_flexible, minimo_noches, disponibilidad_bloqueada` |
| OVERRIDES_OPERATIVOS | `activo` | `TRUE, FALSE` |
| CONSULTAS | `canal` | `whatsapp, instagram, web, manual` |
| CONSULTAS | `estado_conversacion` | `inicio, eligiendo_fechas, cotizando, esperando_pago, pago_en_proceso, cerrada, derivada_a_humano` |
| DISPONIBILIDAD_CACHE | `estado` | `disponible, ocupada, bloqueada, checkout_disponible, limite_escalonamiento` |
| DISPONIBILIDAD_CACHE | `tipo_dia` | `semana, finde, feriado, ano_nuevo` |
| DISPONIBILIDAD_CACHE | `temporada` | `alta, media, baja` |
| DISPONIBILIDAD_CACHE | `es_ultimo_dia_bloque` | `TRUE, FALSE` |
| FERIADOS | `tipo` | `nacional, ano_nuevo, local` |
| FERIADOS | `activo` | `TRUE, FALSE` |
| CUENTAS_COBRO | `medio` | `transferencia_bancaria, transferencia_mp, cripto, efectivo` |
| CUENTAS_COBRO | `activa` | `TRUE, FALSE` |
| PLANTILLAS_MENSAJES | `canal` | `whatsapp, instagram, todos` |
| PLANTILLAS_MENSAJES | `destinatario` | `huesped, equipo, jennifer, franco` |
| PLANTILLAS_MENSAJES | `activa` | `TRUE, FALSE` |
| GASTOS | `categoria` | `limpieza, mantenimiento, servicios, marketing, otro` |
| GASTOS | `reembolsable` | `TRUE, FALSE` |
| DESCUENTOS | `tipo` | `porcentaje, monto_fijo, noche_gratis` |
| DESCUENTOS | `aplica_a` | `todas, grande, chica` |
| DESCUENTOS | `aplica_sobre` | `alojamiento, extras, total` |
| DESCUENTOS | `combinable` | `TRUE, FALSE` |
| DESCUENTOS | `requiere_aprobacion` | `TRUE, FALSE` |
| DESCUENTOS | `activo` | `TRUE, FALSE` |
| LOG_CAMBIOS | `nivel` | `info, warning, error` |
| SOCIOS | `activo` | `TRUE, FALSE` |

**Configuración recomendada de validación:** Activar la opción "Mostrar advertencia" (no rechazar el valor). Esto permite que n8n escriba sin que Sheets bloquee el workflow, pero alerta visualmente cuando un humano ingresa un valor no esperado.

---

## 7. FASE 5 — PROTECCIONES POR ENTORNO

Las protecciones se configuran diferente según el entorno. El objetivo es proteger la integridad sin obstaculizar el trabajo durante el desarrollo.

### DEV — Protecciones mínimas

En DEV la prioridad es poder probar, corregir y experimentar sin fricciones. Las protecciones son orientativas, no bloqueantes.

**Lo que se protege en DEV:**

- CONFIGURACION_GENERAL → proteger solo la columna `clave` (evitar cambios accidentales de nombre de clave). La columna `valor` es libre.
- No aplicar otras protecciones. En DEV todo el equipo puede intervenir en cualquier hoja para corregir datos de prueba.

**Razón:** En DEV se van a ejecutar y depurar los workflows. Si una hoja crítica está protegida, n8n no va a poder escribir hasta que se configure la cuenta de servicio, lo que bloquea el desarrollo antes de tiempo.

---

### TEST — Protecciones moderadas

En TEST el flujo ya debe funcionar correctamente, pero Franco debe poder intervenir manualmente si un workflow produce un resultado incorrecto durante las pruebas.

**Hojas con protección de hoja completa (advertencia, no bloqueo total):**

- DISPONIBILIDAD_CACHE → proteger con advertencia. Franco puede escribir si necesita corregir un estado de prueba, pero la hoja avisa que es una operación inusual.
- LOG_CAMBIOS → proteger con advertencia. No se debe editar manualmente; si se necesita limpiar entre pruebas, hacerlo con conocimiento explícito.

**Hojas con rangos protegidos (sin excepción):**

- CONFIGURACION_GENERAL → proteger columna `clave` (bloqueo total — si se necesita agregar una clave, hacerlo vía este documento)
- RESERVAS → proteger columnas `id_reserva`, `id_prereserva`, `created_at`, `updated_at`, `source_event`
- PAGOS → proteger columnas `id_pago`, `created_at`, `updated_at`, `es_automatico`, `referencia_externa`, `tx_hash`
- DESCUENTOS → proteger columna `usos_actuales` (solo escribe n8n cuando el motor de descuentos esté activo)

**Hojas que quedan sin protección en TEST:**

- CONSULTAS, PRE_RESERVAS (Franco puede limpiar datos entre casos de prueba)
- Todas las hojas de datos de referencia (CABAÑAS, TARIFAS, TEMPORADAS, etc.)

---

### PROD — Protecciones estrictas (referencia futura)

PROD no se configura en esta jornada. Se documenta aquí como referencia para cuando TEST esté validado.

**Hojas con protección total (solo n8n escribe):**

- CONSULTAS → proteger toda la hoja. Solo puede escribir la cuenta de servicio de n8n.
- PRE_RESERVAS → proteger toda la hoja.
- DISPONIBILIDAD_CACHE → proteger toda la hoja.
- LOG_CAMBIOS → proteger toda la hoja.

**Hojas con rangos protegidos:**

- RESERVAS → proteger columnas `id_reserva`, `id_prereserva`, `created_at`, `updated_at`, `source_event`
- PAGOS → proteger columnas `id_pago`, `created_at`, `updated_at`, `es_automatico`, `referencia_externa`, `tx_hash`
- CONFIGURACION_GENERAL → proteger columna `clave`
- DESCUENTOS → proteger columna `usos_actuales`

**Excepción documentada en PROD:**

Las transiciones manuales permitidas por la arquitectura (RESERVAS: `confirmada → activa` y `activa → completada`) las ejecutan Franco o Vicky con acceso de editor. Cualquier otra modificación manual en PROD debe documentarse en LOG_CAMBIOS con el campo `modificado_por` = nombre del operador y `source_event` = `correccion_manual`.

---

### Cómo configurar una protección en Google Sheets

1. Seleccionar la hoja o el rango a proteger
2. Datos → Proteger hoja y rangos
3. Agregar descripción (ej: "Solo escribe n8n — no editar manualmente")
4. Elegir quién puede editar:
   - Para protección blanda (DEV/TEST): "Mostrar advertencia al editar este rango" — cualquiera puede escribir pero recibe aviso
   - Para protección dura (PROD): "Restringir quién puede editar este rango" → Solo vos + cuenta de servicio de n8n

---

## 8. FASE 6 — VERIFICACIÓN FINAL

Antes de declarar los Sheets listos para n8n, verificar manualmente cada punto de esta lista.

### Verificaciones de estructura

- [ ] `VITA_DELTA_DEV` existe y es accesible
- [ ] `VITA_DELTA_TEST` existe y es accesible
- [ ] Ambos Sheets tienen exactamente 24 hojas (21 fuente + 3 vistas)
- [ ] Ninguna hoja tiene espacios, minúsculas o nombres distintos a los definidos por arquitectura. Las tildes y caracteres especiales se aceptan solo cuando forman parte del nombre oficial de la hoja, como `CABAÑAS` y `HUÉSPEDES`.
- [ ] La fila 1 de cada hoja tiene negrita y fila inmovilizada
- [ ] Ninguna hoja tiene columnas sin nombre en la fila 1
- [ ] Los nombres de columnas son exactamente los especificados en la Fase 2 (snake_case, sin tildes)

### Verificaciones de datos

- [ ] CABAÑAS tiene exactamente 5 filas con `activa = TRUE` y `bloqueada = FALSE`
- [ ] TARIFAS tiene al menos 10-11 filas, todas con `activa = TRUE` y precio mayor a 0
- [ ] TEMPORADAS cubre la fecha de hoy (sin gaps entre rangos)
- [ ] CONFIGURACION_GENERAL tiene todas las claves de la Fase 3 (contar: deben ser al menos 40 filas)
- [ ] La clave `sheets_url` en CONFIGURACION_GENERAL tiene la URL del Sheets TEST cargada
- [ ] La clave `encargado_ciclo_inicio_fecha` tiene la fecha real de inicio del ciclo
- [ ] Los números de WhatsApp en CONFIGURACION_GENERAL tienen el formato internacional (+549...)
- [ ] CUENTAS_COBRO tiene al menos 1 fila con `activa = TRUE`
- [ ] PLANTILLAS_MENSAJES tiene al menos 2 filas con `activa = TRUE`
- [ ] SOCIOS tiene 3 filas con porcentajes que suman 100

### Verificaciones de hojas vacías

- [ ] DISPONIBILIDAD_CACHE está vacía (sin ninguna fila de datos)
- [ ] LOG_CAMBIOS está vacío
- [ ] CONSULTAS, PRE_RESERVAS, RESERVAS, PAGOS están vacías

### Verificaciones de validaciones

- [ ] CABAÑAS columna `tipo` tiene lista desplegable
- [ ] RESERVAS columna `estado` tiene lista desplegable con los 6 estados
- [ ] PRE_RESERVAS columna `estado` tiene lista desplegable con los 6 estados
- [ ] PAGOS columna `estado` tiene lista desplegable con los 5 estados
- [ ] PAGOS columna `medio_pago` tiene lista desplegable

### Verificaciones de protecciones (TEST)

- [ ] DISPONIBILIDAD_CACHE tiene protección con advertencia
- [ ] LOG_CAMBIOS tiene protección con advertencia
- [ ] CONFIGURACION_GENERAL columna `clave` está protegida con bloqueo total

---

## 9. QUÉ ERRORES EVITAR

**No usar tildes en nombres de columnas.** La columna `id_huésped` va a romper las queries de n8n. La correcta es `id_huesped`. Lo mismo aplica a todas las columnas: `numero` no `número`, `cabana` no `cabaña`.

**No dejar precios en 0 en TARIFAS en DEV ni TEST.** El precio 0 está reservado exclusivamente para `PAQUETES_EVENTO`. En cualquier otra hoja, el motor de precios retorna error `paquete_sin_precio` al calcular una estadía, lo que bloquea la creación de PRE_RESERVAS.

**No cargar datos en DISPONIBILIDAD_CACHE ni en LOG_CAMBIOS antes del primer workflow.** Esas hojas las pobla exclusivamente n8n. Cualquier dato manual ahí produce inconsistencias en el primer recálculo.

**No dejar gaps en TEMPORADAS.** Si la fecha de hoy no está cubierta por ninguna temporada activa, el motor de precios no va a poder calcular el multiplicador y va a retornar error. Verificar que los rangos son contiguos o solapados.

**No usar tipo Fecha de Google Sheets para las columnas de fecha.** Todas las fechas van como texto en formato YYYY-MM-DD. Si Sheets convierte automáticamente una fecha a su formato interno (ej: "20 May 2026"), n8n no va a poder parsearla. Al pegar fechas, usar formato texto o agregar un apóstrofo delante (`'2026-05-10`).

**No escribir "null", "-", "N/A" en celdas opcionales.** Los campos sin valor van con la celda vacía. n8n interpreta una celda vacía como null correctamente. Un texto como "N/A" se interpreta como string y puede romper validaciones de tipo.

**No hardcodear el Sheets ID en los workflows de n8n.** Cuando se configure n8n, el ID siempre va en la variable de entorno `SHEETS_ID`. Nunca en el código del workflow.

**No compartir el Sheets PROD con la cuenta de DEV/TEST de n8n.** Las cuentas de servicio de n8n deben ser distintas por entorno, o al menos las variables de entorno deben apuntar a los Sheets correctos. Confundir los IDs produce escrituras sobre datos productivos reales.

---

## 10. PRÓXIMO PASO: n8n

Una vez que los Sheets DEV y TEST están verificados con todos los checks de la Fase 6 marcados, el siguiente paso es implementar el primer workflow en n8n.

**Primer workflow a implementar:** `db_recalcular_disponibilidad`

Este workflow se implementa antes que los demás porque todos los otros lo llaman. Sin cache poblada, ningún workflow puede validar disponibilidad.

**Alcance del primer workflow:**
- Input: lista de cabañas y lista de fechas (o vacío para scope total)
- Lógica: consulta BLOQUEOS → RESERVAS → PRE_RESERVAS → determina estado → upsert en DISPONIBILIDAD_CACHE
- Output: `{ ok: true, filas_actualizadas: N, duracion_ms: N }`
- Primera ejecución manual: scope total (todas las cabañas, próximos 60 días)

**Condición para considerar el Sheets listo:** Todos los checks de la Fase 6 están marcados, y al ejecutar `db_recalcular_disponibilidad` con scope total, DISPONIBILIDAD_CACHE queda poblada con filas para las 5 cabañas × 60 días sin errores en LOG_CAMBIOS.

La especificación completa del workflow está en `ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md`, Sección 12.

---

## 11. CHECKLIST DE CIERRE DE JORNADA

Este checklist se completa al final de la jornada de implementación del Sheets. Cada ítem debe estar verificado antes de avanzar a n8n.

### Sheets creados

- [ ] `VITA_DELTA_DEV` creado en Google Drive
- [ ] `VITA_DELTA_TEST` creado en Google Drive
- [ ] Accesos de equipo configurados en ambos Sheets

### Hojas creadas

- [ ] Las 21 hojas fuente existen en DEV con nombre exacto en MAYUSCULAS_GUION_BAJO
- [ ] Las 3 hojas de vista existen en DEV (VISTA_CALENDARIO, VISTA_PRERESERVAS_ACTIVAS, VISTA_OCUPACION)
- [ ] Las 21 hojas fuente existen en TEST con nombre exacto en MAYUSCULAS_GUION_BAJO
- [ ] Las 3 hojas de vista existen en TEST

### Encabezados cargados

- [ ] Fila 1 de cada hoja en DEV tiene los encabezados snake_case especificados en Fase 2
- [ ] Fila 1 de cada hoja en TEST tiene los encabezados snake_case especificados en Fase 2
- [ ] Todas las filas 1 tienen negrita y están inmovilizadas

### Datos mínimos cargados

- [ ] CABAÑAS: 5 filas cargadas en DEV
- [ ] CABAÑAS: 5 filas cargadas en TEST
- [ ] TARIFAS: mínimo 10 filas cargadas en DEV (precios ficticios > 0)
- [ ] TARIFAS: mínimo 10 filas cargadas en TEST (precios reales > 0)
- [ ] TEMPORADAS: 2 filas cargadas, cubre la fecha actual, en DEV y TEST
- [ ] CONFIGURACION_GENERAL: todas las claves cargadas en DEV y TEST (mínimo 40 filas)
- [ ] CONFIGURACION_GENERAL: clave `sheets_url` tiene la URL de cada Sheets correspondiente
- [ ] CONFIGURACION_GENERAL: claves de WhatsApp tienen números reales
- [ ] CUENTAS_COBRO: al menos 1 fila activa en DEV y TEST
- [ ] PLANTILLAS_MENSAJES: al menos 2 filas activas (`prereserva_creada` y `nueva_reserva_equipo`) en DEV y TEST
- [ ] SOCIOS: 3 filas con porcentajes que suman 100 en DEV y TEST

### Validaciones aplicadas

- [ ] Validaciones de lista configuradas en CABAÑAS (tipo, activa, bloqueada)
- [ ] Validaciones de lista configuradas en RESERVAS (estado, canal_origen)
- [ ] Validaciones de lista configuradas en PRE_RESERVAS (estado, canal_pago_esperado)
- [ ] Validaciones de lista configuradas en PAGOS (tipo, medio_pago, estado, es_automatico)
- [ ] Validaciones de lista configuradas en TARIFAS (tipo_cabana, concepto, activa)
- [ ] Validaciones de lista configuradas en BLOQUEOS (motivo, activo)
- [ ] Validaciones de lista configuradas en DISPONIBILIDAD_CACHE (estado, tipo_dia, temporada)
- [ ] Validaciones de lista configuradas en LOG_CAMBIOS (nivel)
- [ ] Validaciones de lista configuradas en las demás hojas de la Fase 4

### Protecciones aplicadas

- [ ] DEV: columna `clave` de CONFIGURACION_GENERAL protegida
- [ ] TEST: DISPONIBILIDAD_CACHE con protección de advertencia
- [ ] TEST: LOG_CAMBIOS con protección de advertencia
- [ ] TEST: columna `clave` de CONFIGURACION_GENERAL con bloqueo total
- [ ] TEST: rangos de columnas de sistema protegidos en RESERVAS y PAGOS
- [ ] TEST: columna `usos_actuales` de DESCUENTOS protegida

### Estructura verificada

- [ ] Ninguna hoja tiene columnas sin nombre en fila 1
- [ ] DISPONIBILIDAD_CACHE está vacía (sin datos)
- [ ] LOG_CAMBIOS está vacío
- [ ] CONSULTAS, PRE_RESERVAS, RESERVAS, PAGOS están vacías
- [ ] TEMPORADAS no tiene gaps que dejen fechas sin cobertura
- [ ] TARIFAS no tiene ningún precio igual a 0

### Listo para implementar `db_recalcular_disponibilidad`

- [ ] Todos los checks anteriores están marcados
- [ ] Se tiene el ID del Sheets TEST (para configurar como variable de entorno en n8n)
- [ ] Se tiene el ID del Sheets DEV (ídem)
- [ ] La especificación del workflow `db_recalcular_disponibilidad` (Etapa 5B, Sección 12) fue leída y está clara
- [ ] Se eligió con qué entorno arrancar (recomendado: DEV para el primer intento)

---

*Documento generado como parte del proceso de implementación del sistema Complejo Vita Delta.*
*Este documento no reemplaza ni modifica ningún documento de arquitectura de las Etapas 1 a 5B.*
*Siguiente: implementación de `db_recalcular_disponibilidad` en n8n.*
