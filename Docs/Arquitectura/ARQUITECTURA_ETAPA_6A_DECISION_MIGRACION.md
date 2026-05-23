# ARQUITECTURA_ETAPA_6A_DECISION_MIGRACION.md

**Versión:** 1.1
**Fecha:** Mayo 2026
**Estado:** Aprobado — CERRADO
**Proyecto:** Sistema de gestión y automatización — Complejo Vita Delta
**Autores:** Franco (titular) + Claude (arquitecto)

**Tipo de documento:** Decisión arquitectónica
**Predecesora:** Etapa 5B — Implementación Vertical Mínima
**Sucesora:** Etapa 6B — Migración del Núcleo a Supabase

**Historial de versiones:**
- v1.0 — Primera redacción.
- v1.1 — Precisiones: relación con Etapa 1 explicitada; tratamiento de `DISPONIBILIDAD_CACHE` flexibilizado; dato de 44 segundos marcado como estimación; argumento de costos reformulado; cronograma desdoblado en MVP y migración productiva; terminología homogeneizada.

---

## ÍNDICE

1. Propósito de este documento
2. Contexto y momento de la decisión
3. Línea base medida
4. Análisis de cuellos de botella
5. Palancas de optimización evaluadas
6. Techo realista calculado
7. Por qué el techo es insuficiente
8. Alternativas consideradas
9. Decisión adoptada
10. Relación con Etapa 1 — Coherencia arquitectónica
11. Por qué Supabase
12. Por qué ahora
13. Qué se preserva del trabajo previo
14. Terminología — Roles después de la migración
15. Implicancias para etapas futuras
16. Criterios de éxito de la migración
17. Cronograma estimado
18. Riesgos de la migración
19. Decisión — Registro formal
20. Próximo paso

---

## 1. PROPÓSITO DE ESTE DOCUMENTO

Este documento registra la decisión arquitectónica de **no continuar optimizando la base de datos sobre Google Sheets y migrar el núcleo del sistema a Supabase (PostgreSQL gestionado)**.

No es un plan de implementación. Es el registro de la deliberación: qué se midió, qué se evaluó, por qué se descartó optimizar, por qué se eligió migrar y por qué este momento.

El plan de implementación vive en el documento sucesor: Etapa 6B — Migración del Núcleo a Supabase.

---

## 2. CONTEXTO Y MOMENTO DE LA DECISIÓN

### Estado del proyecto al tomar la decisión

- Siete etapas de arquitectura cerradas (1, 2, 3, 4A, 4B, 5A, 5B).
- Seis workflows core validados en DEV y TEST: `db_recalcular_disponibilidad` v8, `db_crear_consulta` v3, `db_crear_prereserva` v2/v3, `db_registrar_pago` v1, `db_confirmar_reserva` v1, `sistema_expirar_prereservas` v1.
- Workflow auxiliar `db_crear_huesped` v1.1 funcionando como subworkflow desde `db_crear_prereserva` v3.
- Dos Google Sheets (DEV y TEST) con 24 hojas, validaciones, protecciones y auditoría completada.
- Apps Scripts auxiliares para validaciones, protecciones y auditoría.
- Repositorio GitHub al día con docs, contratos, workflows y prototipos.
- Web pública de reservas **no construida todavía**.
- Bot conversacional **no implementado todavía**.
- MercadoPago **no integrado todavía**.
- Ninguna reserva real procesada — sistema completo en fase pre-producción.

### Disparador de la deliberación

Al medir el tiempo de ejecución de `db_crear_prereserva` v3 (workflow más crítico del sistema), los resultados estuvieron consistentemente en el rango de **23 a 26 segundos por ejecución aislada**, con un **ciclo completo desde frontend simulado/proyectado estimado en ~44 segundos** (proyección del flujo web a partir de tiempos parciales medidos; la web pública aún no existe, por lo que este número no proviene de una medición de frontend productivo real).

Esta latencia, aceptable para pruebas internas, no es adecuada para una experiencia de reserva web profesional, donde el huésped espera respuesta inmediata después de confirmar fechas y datos de pago.

---

## 3. LÍNEA BASE MEDIDA

| Métrica | Valor observado |
|---|---|
| `db_crear_prereserva` v3 (aislado, p50 observado) | 23 segundos |
| `db_crear_prereserva` v3 (aislado, máximo observado) | 26 segundos |
| Ciclo completo desde frontend (proyectado/estimado) | ~44 segundos |
| `db_recalcular_disponibilidad` v8 invocado como subworkflow | ~2 segundos |
| Operaciones de red en camino crítico exitoso | 14 |

> **Nota sobre la medición:** los tiempos de `db_crear_prereserva` provienen de ejecuciones manuales sobre el entorno DEV con datos de prueba. El "ciclo completo desde frontend" es una proyección del flujo web completo a partir de tiempos parciales medidos en n8n, no una medición de frontend productivo real. La web pública aún no está construida.

### Desglose del camino crítico de `db_crear_prereserva` v3

Operaciones serializadas en el caso exitoso (sin conflicto):

| # | Operación | Tipo | Latencia estimada (ms) |
|---|---|---|---|
| 1 | Resolver Input + validaciones | JS puro | < 50 |
| 2 | Llamar `db_crear_huesped` (subworkflow completo) | Subworkflow + 3-5 ops Sheets | 4.000 – 6.000 |
| 3 | Leer CABAÑAS | Read Sheets | 500 – 1.500 |
| 4 | Leer CONFIGURACION_GENERAL | Read Sheets | 500 – 1.500 |
| 5 | Leer DISPONIBILIDAD_CACHE | Read Sheets | 800 – 2.000 |
| 6 | Leer PRE_RESERVAS | Read Sheets | 500 – 1.500 |
| 7 | Leer RESERVAS | Read Sheets | 500 – 1.500 |
| 8 | Leer BLOQUEOS | Read Sheets | 500 – 1.500 |
| 9 | Verificar Cabaña + Capa 1 + Capa 2 | JS puro | < 50 |
| 10 | Leer PRE_RESERVAS (fresh) | Read Sheets | 500 – 1.500 |
| 11 | Leer RESERVAS (fresh) | Read Sheets | 500 – 1.500 |
| 12 | Leer BLOQUEOS (fresh) | Read Sheets | 500 – 1.500 |
| 13 | Revalidación final | JS puro | < 50 |
| 14 | Escribir PRE_RESERVAS (append) | Write Sheets | 600 – 1.500 |
| 15 | LOG PRE_RESERVA (append) | Write Sheets | 600 – 1.500 |
| 16 | Ejecutar `db_recalcular_disponibilidad` | Subworkflow | ~2.000 |
| | **Total estimado** | | **12.000 – 25.000 ms** |

Este rango coincide con la latencia observada en producción de pruebas.

---

## 4. ANÁLISIS DE CUELLOS DE BOTELLA

El cuello de botella **no es n8n** ni la lógica de negocio. La lógica en JavaScript se ejecuta en menos de 100ms acumulados.

El cuello de botella es la **latencia inherente del API de Google Sheets**, que oscila entre 500 y 2.000 milisegundos por operación independientemente del tamaño de la hoja. Con 14 operaciones serializadas en el camino crítico exitoso, la latencia mínima alcanzable está estructuralmente limitada.

### Origen de la latencia

1. **Google Sheets no fue diseñado como base de datos transaccional.** Cada operación atraviesa el API de Google con autenticación, cuotas, y procesamiento batch.
2. **No existen índices.** Cada lectura es un scan completo de la hoja.
3. **No es transaccional.** La ausencia de transacciones obliga a implementar verificación en capas (Capa 1, Capa 2, Revalidación Final), cada una con sus propias lecturas.
4. **No hay constraints estructurales.** La prevención de double booking depende de concurrencia=1 a nivel n8n, no de garantías del motor.
5. **El recálculo de disponibilidad requiere reescritura completa.** No hay forma de mantener una vista calculada que se actualice por trigger.

---

## 5. PALANCAS DE OPTIMIZACIÓN EVALUADAS

Antes de tomar la decisión, se evaluaron las siguientes palancas concretas con su ahorro estimado:

| # | Palanca | Ahorro estimado | Riesgo |
|---|---|---|---|
| 1 | Paralelizar las 6 lecturas iniciales | 4 – 5 segundos | Bajo |
| 2 | Paralelizar las 3 lecturas fresh de revalidación | 1.5 – 2 segundos | Bajo |
| 3 | Mover LOG de `db_crear_huesped` a fire-and-forget | 0.5 – 1 segundo | Bajo |
| 4 | Implementar recálculo parcial en `db_recalcular_disponibilidad` v9 | 0.5 – 1 segundo | Medio |
| 5 | Eliminar lecturas iniciales redundantes con las fresh | (descartado, riesgo race condition) | Alto |
| | **Ahorro total estimado p50** | **7 – 9 segundos** | |

### Cálculo del techo realista

Partiendo de 23 segundos p50 y aplicando todas las palancas evaluadas:

- Mejor escenario: 23 – 9 = **14 segundos**
- Peor escenario: 26 – 7 = **19 segundos**
- **Estimación realista p50 post-optimización: 10 – 12 segundos**

---

## 6. TECHO REALISTA CALCULADO

**El techo realista alcanzable manteniendo Google Sheets como backend transitorio es aproximadamente 10–12 segundos en p50, con p95 alrededor de 14–16 segundos.**

Este techo no se puede romper sin migrar a una base de datos transaccional, porque:

- Las 14 operaciones de red del camino crítico no pueden reducirse a menos de 6-7 sin perder garantías de integridad.
- Cada operación de Sheets tiene un piso de latencia de ~500ms que no depende de la lógica del workflow.

---

## 7. POR QUÉ EL TECHO ES INSUFICIENTE

10–12 segundos podría ser aceptable para un sistema interno de carga manual. Es **claramente insuficiente** para una experiencia de reserva web profesional por las siguientes razones:

1. **Referencia de mercado.** Plataformas con las que el huésped compara mentalmente (Airbnb, Booking, Despegar) responden en 1–3 segundos.
2. **Momento crítico de UX.** La latencia ocurre exactamente en el paso de cierre de venta, donde la duda mata la conversión.
3. **Sin margen para imprevistos.** Si Google Sheets tiene un día lento (varianza de 30-40% es habitual), 10 segundos pasan a 15 sin causa identificable.
4. **No escala con la concurrencia.** Concurrencia=1 obliga a serializar reservas. Tres huéspedes simultáneos esperan 30+ segundos el último.
5. **Compromete la confianza del usuario.** Un sistema lento se percibe como improvisado, independientemente de la calidad real de la arquitectura.

---

## 8. ALTERNATIVAS CONSIDERADAS

### 8.1 Optimizar Sheets y postergar la migración

**Descartada.** El techo realista no resuelve el problema de fondo. Implica invertir 7-10 días de trabajo en mejoras que serán deprecadas al migrar. No genera aprendizaje transferible: optimizar latencia de Sheets API no enseña nada útil para producción real.

### 8.2 Migrar a Airtable

**Descartada.** Mejora la UX para el equipo operativo pero no resuelve el problema estructural: sigue siendo una API con latencia, sin transacciones reales, con cuotas estrictas y costo a partir de cierto volumen. No es PostgreSQL ni se acerca.

### 8.3 Migrar a Firebase/Firestore (noSQL)

**Descartada.** El modelo de datos del proyecto está diseñado como relacional desde Etapa 1 (IDs, FKs, snake_case, tipos consistentes). Forzarlo a un modelo de documentos noSQL implicaría pelear con el diseño existente y perder garantías relacionales que ya son parte de la arquitectura.

### 8.4 Migrar a Supabase (PostgreSQL gestionado)

**Adoptada.** Justificación detallada en sección 11.

### 8.5 Construir backend custom con PostgreSQL en VPS

**Descartada por el momento.** Mayor curva de aprendizaje, costos de DevOps, gestión de backups, certificados, seguridad. Supabase ofrece todo eso ya resuelto con curva de entrada baja.

---

## 9. DECISIÓN ADOPTADA

**Se migra el núcleo de datos del sistema Vita Delta de Google Sheets a Supabase (PostgreSQL gestionado).**

La migración se planifica e implementa en la Etapa 6B subsiguiente. La presente etapa 6A solo registra la decisión.

La decisión no se toma por preferencia técnica ni por moda, sino por tres motivos concretos y acumulativos:

1. **Conversión.** Una latencia de 10+ segundos en el cierre de venta web compromete materialmente la tasa de conversión.
2. **Confianza del usuario.** Un sistema percibido como lento se asocia inmediatamente a "improvisado", independientemente de la calidad de la arquitectura.
3. **Consistencia operativa.** Sin garantías transaccionales reales, el riesgo de double booking crece con cada canal nuevo que se conecte (web, WhatsApp, Instagram, MercadoPago).

---

## 10. RELACIÓN CON ETAPA 1 — COHERENCIA ARQUITECTÓNICA

**Esta decisión no contradice la Etapa 1. La complementa.**

La Etapa 1 (sección 5, "Google Sheets vs Supabase/PostgreSQL") estableció:

> *"Arrancar con Google Sheets. Diseñar como SQL desde el día uno. Migrar a Supabase cuando el volumen lo justifique."*

Y definió como punto de quiebre indicativo:

> *"Más de 50 reservas por mes procesadas automáticamente en simultáneo, o necesidad de reportes contables cruzados en tiempo real."*

La Etapa 6A **adelanta** la migración porque apareció antes un punto de quiebre distinto, no previsto en Etapa 1 pero perfectamente consistente con su lógica: **la latencia del flujo crítico de pre-reserva web y la necesidad de garantías transaccionales antes de construir la web pública**.

El principio rector de Etapa 1 era "migrar cuando el costo de no migrar supere el costo de migrar". Ese umbral se alcanzó por una métrica distinta a la prevista (latencia y transaccionalidad en lugar de volumen). Pero el criterio de decisión es el mismo.

Más aún: la propia Etapa 1 estableció en su sección 13 (Principios de Migrabilidad Futura) un plan de migración con cinco pasos concretos a Supabase. La Etapa 6A activa ese plan diseñado desde el primer día. **No improvisa, ejecuta.**

---

## 11. POR QUÉ SUPABASE

### Razones técnicas

1. **Latencia.** Las operaciones tipo SELECT/INSERT contra Postgres rondan los 20–100ms desde n8n, contra los 500–2000ms de Sheets API. Reducción de un orden de magnitud.

2. **Transacciones ACID.** Una sola transacción cubre lo que hoy requiere triple capa de verificación. `BEGIN; SELECT FOR UPDATE; INSERT; COMMIT;` garantiza consistencia sin lógica defensiva en n8n.

3. **Constraint de exclusión para prevenir double booking.** PostgreSQL ofrece un tipo `daterange` y una extensión `btree_gist` que permiten declarar:

   *No pueden existir dos reservas activas para la misma cabaña cuyas fechas se solapen.*

   El motor lo hace cumplir por diseño. **Esto es estructuralmente imposible en Sheets.**

4. **Disponibilidad calculada con autoridad real en PostgreSQL.** `DISPONIBILIDAD_CACHE` deja de existir como hoja de Google Sheets. La disponibilidad pasa a resolverse desde PostgreSQL mediante el mecanismo que se decida en Etapa 6B (funciones SQL, views, materialized views o tabla cache interna). La elección entre estas opciones se evalúa según performance y patrones de consulta reales. Cualquiera que sea la implementación elegida, **la autoridad real es PostgreSQL**; si existe una cache, será derivada, no fuente de verdad, y no requerirá un workflow de recálculo manual como `db_recalcular_disponibilidad` actual.

5. **Concurrencia real.** Múltiples reservas simultáneas se procesan en paralelo sin riesgo de double booking gracias a las garantías del motor.

6. **Row Level Security.** Permisos por rol al nivel de la base, sin requerir Apps Script para protecciones.

### Razones de costo

El costo inicial esperado de Supabase es **bajo**. El plan gratuito o un plan inicial pago cubren razonablemente la etapa de desarrollo, validación y primeras pruebas productivas para un proyecto del tamaño de Vita Delta.

**La decisión, sin embargo, no depende de los límites específicos del free tier actual** (que pueden cambiar y suelen revisarse anualmente). La decisión depende de que **PostgreSQL gestionado resuelve problemas estructurales que Sheets no puede resolver**, independientemente de los detalles de pricing del proveedor en cada momento.

Si en algún punto el costo de Supabase deja de ser razonable, los datos en PostgreSQL son portables a cualquier otro proveedor gestionado o a un VPS propio sin reescribir lógica. **Sin lock-in.**

### Razones de aprendizaje

1. **PostgreSQL es estándar de la industria.** Aprenderlo es transferible a cualquier proyecto futuro (incluido Bemvelon).

2. **Las decisiones tomadas en Etapas 1–5B se traducen 1 a 1.** Tablas, columnas, IDs, estados, source_event, todo viaja sin cambios de nomenclatura.

---

## 12. POR QUÉ AHORA

La decisión se toma en este momento específico por las siguientes razones acumuladas:

1. **La web pública aún no está construida.** No hay frontend que rehacer ni huéspedes esperando reservas.

2. **El bot conversacional aún no está implementado.** No hay integración externa que romper.

3. **MercadoPago aún no está conectado.** No hay flujo de pagos en marcha.

4. **No hay reservas reales registradas.** La migración no debe respetar datos productivos. Solo datos de prueba.

5. **El equipo operativo (Vicky, Rodrigo) aún no entrenó hábitos sobre Sheets como entrada operativa.** Es el mejor momento para definir nueva UX.

6. **Cada workflow nuevo que se sume antes de migrar es deuda técnica.** Posponer la decisión solo incrementa el costo.

7. **El aprendizaje de Sheets ya fue capitalizado.** Modelado de datos, estados, validaciones, contratos técnicos: todo eso vive en la arquitectura cerrada, no en los workflows. La migración preserva el aprendizaje y reescribe la implementación.

---

## 13. QUÉ SE PRESERVA DEL TRABAJO PREVIO

La migración **no tira el trabajo de las Etapas 1–5B**. Lo que se preserva:

### Arquitectura (100% reusable)
- Modelo de datos completo de Etapa 5A → schema SQL casi 1 a 1.
- Estados de PRE_RESERVAS y RESERVAS → enumerados PostgreSQL idénticos.
- Reglas de disponibilidad (intervalo semiabierto, escalonamiento, overrides) → lógica viaja a funciones, vistas o materialized views SQL.
- Principios de Etapa 1 (fuente única de verdad, n8n como cerebro, IA no decide, etc.) → siguen vigentes.

### Convenciones (100% reusables)
- Nombres en snake_case.
- IDs numéricos con FKs explícitas.
- Fechas en formato `YYYY-MM-DD`.
- Timestamps en ISO 8601.
- `source_event` como campo de trazabilidad universal.

### Contratos técnicos (90% reusables)
- Inputs y outputs de cada workflow se mantienen.
- Solo cambia la implementación interna del workflow.
- Quien consume la API de n8n no nota la diferencia.

### Lógica de validación (95% reusable)
- Validaciones de input (`fecha_in < fecha_out`, capacidad, formatos) → viajan como código JavaScript en n8n o como CHECK constraints en SQL.
- Idempotencia → se mantiene como principio.

### n8n como cerebro lógico (100% preservado)
- n8n no se reemplaza. Sigue siendo el motor de workflows.
- Solo se reemplazan los nodos de Google Sheets por nodos que comunican con PostgreSQL.

### Apps Scripts (deprecados)
- Las validaciones y protecciones de Sheets ya no aplican como sistema crítico.
- Se reemplazan por constraints, CHECK y RLS en Supabase.
- Pueden seguir existiendo en el Sheets-espejo si aporta valor operativo, pero ya no son la línea de defensa.

### Lo que sí cambia
- `DISPONIBILIDAD_CACHE` deja de existir como hoja de Google Sheets. La disponibilidad pasa a resolverse desde PostgreSQL (función, view, materialized view o tabla cache derivada — a definir en 6B).
- `db_recalcular_disponibilidad` como workflow de recálculo masivo deja de tener sentido en la forma actual. Si se necesita refresco explícito, será de una estructura derivada, no de la fuente de verdad.
- Reducción significativa de operaciones por workflow → menos lecturas, lógica más simple.
- Google Sheets pasa de ser **backend transitorio** a ser **vista operativa de solo lectura sincronizada** (Sheets-espejo). Deja de ser fuente de verdad.

---

## 14. TERMINOLOGÍA — ROLES DESPUÉS DE LA MIGRACIÓN

Para mantener consistencia en toda la documentación del proyecto desde Etapa 6B en adelante:

| Componente | Rol antes (Etapas 1–5B) | Rol después (Etapa 6B en adelante) |
|---|---|---|
| Google Sheets | Backend transitorio / prototipo funcional / fuente de verdad operativa | Sheets-espejo: vista operativa de solo lectura sincronizada |
| Supabase / PostgreSQL | (no existía) | Fuente de verdad del sistema |
| `DISPONIBILIDAD_CACHE` | Hoja de Sheets calculada por workflow de recálculo | Concepto derivado: función / view / materialized view / tabla cache en PostgreSQL — implementación a definir en 6B |
| n8n | Cerebro lógico | Cerebro lógico (sin cambios) |
| Apps Scripts | Validaciones, protecciones y auditoría de Sheets | Auxiliares opcionales sobre Sheets-espejo, no críticos |

---

## 15. IMPLICANCIAS PARA ETAPAS FUTURAS

### Etapa 6B (inmediata)
- Migración del núcleo a Supabase.
- Reescritura de los 6 workflows core sobre el nuevo backend.
- Definición concreta del mecanismo de disponibilidad (función, view, materialized view o cache derivada).
- Implementación de sincronización Sheets-espejo.
- Documentación actualizada.

### Etapa 7 (posterior)
- Decisión sobre UX de carga manual para el equipo: planilla con trigger, Google Form o UI propia.
- Web pública conectada al backend Supabase.
- Integración MercadoPago.

### Etapa 8 y siguientes (más adelante)
- Bot conversacional sobre la base Supabase.
- Coordinación con limpieza.
- Contabilidad automatizada.
- Distribución entre socios.

### Reutilización para otros negocios (Bemvelon)
- La arquitectura sobre Supabase es 100% portable.
- Solo cambia: nombres del negocio, configuración de cabañas/unidades, branding.
- La lógica de reservas, pagos, disponibilidad es transferible.

---

## 16. CRITERIOS DE ÉXITO DE LA MIGRACIÓN

La Etapa 6B se considerará exitosa cuando:

| Criterio | Umbral |
|---|---|
| `db_crear_prereserva` (nueva versión, p50) | ≤ 3 segundos |
| `db_crear_prereserva` (nueva versión, p95) | ≤ 5 segundos |
| Pruebas de concurrencia simultánea | 0 double bookings sobre 50 ejecuciones |
| Workflows reescritos sin pérdida de funcionalidad | 6 de 6 |
| Sheets-espejo sincronizado | < 5 minutos de delay |
| Equipo operativo mantiene capacidad de carga manual | Sí (vía Sheets-espejo o UI) |

Si cualquiera de estos criterios falla en TEST, la migración no avanza a producción.

---

## 17. CRONOGRAMA ESTIMADO

El cronograma se desdobla en dos hitos diferenciados para ser honesto sobre la diferencia entre "que funcione" y "que esté terminado profesionalmente":

| Hito | Duración estimada (full focus) | Qué incluye |
|---|---|---|
| **MVP técnico funcional Supabase** | 7 – 15 días intensivos | Schema básico, datos seed, workflows core reescritos funcionando, pruebas en DEV |
| **Migración productiva completa** | 3 – 4 semanas | MVP + tests exhaustivos en TEST + sincronización Sheets-espejo + documentación + plan de rollback + criterios de éxito validados |

"MVP funcional" significa que el sistema corre punta a punta sobre Supabase con los workflows reescritos, pero todavía sin todo el blindaje de tests y procedimientos.

"Migración productiva" significa que el sistema está listo para operar como backend de la web pública: testeado, documentado, con rollback definido y validado contra los criterios de éxito.

No saltar de MVP a producción sin completar el segundo hito.

---

## 18. RIESGOS DE LA MIGRACIÓN

| Riesgo | Severidad | Mitigación |
|---|---|---|
| Curva de aprendizaje PostgreSQL | Media | Fase 1 de Etapa 6B dedicada solo a aprender con tablas estáticas (CABAÑAS, TARIFAS) antes de tocar lo crítico. |
| Reescritura introduce bugs nuevos | Media | Pruebas exhaustivas en TEST antes de tocar DEV operativo. Mantener workflows v3 activos en paralelo durante toda la transición. |
| Sheets-espejo se desincroniza | Baja | Workflow de sincronización con manejo de errores explícito y LOG. |
| Pérdida de visibilidad para equipo operativo | Baja | Sheets-espejo + posible UI mínima en Etapa 7. |
| Dependencia de Supabase como SaaS | Baja | Datos exportables a cualquier PostgreSQL en cualquier momento. Sin lock-in. |
| Aprendizaje subestimado en tiempo | Media | Cronograma honesto en dos hitos (MVP + producción) en lugar de un solo número global. |

---

## 19. DECISIÓN — REGISTRO FORMAL

Fecha de decisión: Mayo 2026
Tomada por: Franco (titular del proyecto)
Asistencia técnica: Claude (arquitecto)

**Resolución:** Se aprueba la migración del núcleo de datos del sistema Vita Delta de Google Sheets a Supabase (PostgreSQL gestionado), bajo el plan que se documenta en `ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md`.

Esta decisión es coherente con el principio de migrabilidad establecido en Etapa 1 (sección 13) y con el patrón de "API interna" diseñado desde el día uno para facilitar este tipo de transición. Adelanta el momento de migración previsto en Etapa 1, no lo contradice.

---

## 20. PRÓXIMO PASO

Lectura, validación y aprobación de:

```
Docs/Arquitectura/ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md
```

Este documento describirá:
- Schema SQL completo.
- Fases de implementación (MVP y producción).
- Decisión técnica concreta sobre cómo se resuelve la disponibilidad (función / view / materialized view / cache derivada).
- Plan de convivencia Sheets-Supabase durante la transición.
- Reescritura de cada workflow.
- Criterios de cierre por hito.

---

*Fin del documento*
*Siguiente: ARQUITECTURA_ETAPA_6B_MIGRACION_SUPABASE.md — Migración del Núcleo a Supabase*
