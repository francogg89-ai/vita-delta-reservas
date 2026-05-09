# ARQUITECTURA_ETAPA_1_FUTURO.md

# Etapa 1 — Arquitectura Base: Mejoras, Riesgos y Evolución Futura

**Proyecto:** Sistema de gestión y automatización — Complejo Vita Delta  
**Documento relacionado:** `ARQUITECTURA_ETAPA_1_VITA_DELTA.md`  
**Estado de la etapa:** Aprobada — Cerrada  
**Propósito de este documento:** Registrar qué conviene revisar, mejorar o evaluar a futuro sobre la arquitectura base, sin reabrir decisiones fundacionales ya cerradas.

---

## 1. Estado actual de la Etapa 1

La Etapa 1 dejó definida la arquitectura general del sistema:

- Fuente de verdad inicial en Google Sheets.
- n8n como núcleo lógico y de automatización.
- Apps Script limitado a puentes, triggers y endpoints livianos.
- Modelo de datos principal.
- Flujo `CONSULTAS → PRE_RESERVAS → RESERVAS`.
- Principios de consistencia para evitar double bookings.
- DISPONIBILIDAD_CACHE como tabla derivada.
- BLOQUEOS como entidad separada.
- `source_event` para trazabilidad.
- TAREAS_OPERATIVAS prevista para etapas posteriores.
- Migrabilidad futura hacia Supabase/PostgreSQL.

La decisión principal fue construir el sistema como una arquitectura modular, migrable y determinística, no como una simple automatización de planillas.

---

## 2. Decisiones que NO deberían romperse

Estas decisiones son fundacionales. Cualquier evolución futura debería respetarlas salvo que haya una razón técnica fuerte para cambiarlas.

### 2.1 Una sola fuente de verdad

Cada dato importante debe vivir en un único lugar. No debe existir una “verdad paralela” entre Sheets, Calendar, WhatsApp, la web o el bot.

**Regla:** si Google Calendar dice una cosa y RESERVAS dice otra, la verdad es RESERVAS.

---

### 2.2 n8n como núcleo lógico

n8n debe seguir siendo el lugar donde viven las decisiones de negocio, validaciones, automatizaciones y escrituras críticas.

Apps Script no debe transformarse en un segundo backend oculto.

---

### 2.3 Escrituras centralizadas

La web, el bot, formularios internos o integraciones externas no deberían escribir reservas confirmadas directamente.

Toda operación crítica debe pasar por workflows internos tipo:

- `db_crear_prereserva`
- `db_confirmar_reserva`
- `db_recalcular_disponibilidad`
- `db_registrar_pago`
- `db_crear_bloqueo`

Esto permite migrar la base de datos sin reescribir todo el sistema.

---

### 2.4 DISPONIBILIDAD_CACHE como dato derivado

La disponibilidad cacheada no debe editarse manualmente. Si hay un error, se corrige la causa: RESERVAS, PRE_RESERVAS, BLOQUEOS o configuración.

---

### 2.5 Separación IA / lógica core

La IA puede conversar, interpretar y asistir, pero no debe decidir disponibilidad, precios finales, reservas, pagos ni conflictos.

La lógica core debe ser determinística.

---

## 3. Riesgos futuros

### 3.1 Google Sheets como base inicial

Google Sheets es una buena decisión para empezar, pero tiene límites:

- concurrencia,
- control de permisos granular,
- integridad relacional,
- auditoría fuerte,
- performance con muchas operaciones,
- validaciones complejas,
- dificultad para manejar locks reales.

Para 5 a 10 cabañas es suficiente si las escrituras están bien encapsuladas. El riesgo aparece si muchas automatizaciones empiezan a escribir en paralelo.

**Señal de alerta:** errores frecuentes de escritura, workflows lentos o inconsistencias entre RESERVAS y DISPONIBILIDAD_CACHE.

---

### 3.2 n8n Cloud como núcleo operativo

n8n es una herramienta muy adecuada para esta etapa, pero conviene vigilar:

- límites del plan,
- cantidad de ejecuciones,
- velocidad de workflows,
- manejo de colas,
- errores silenciosos,
- dependencia de una instancia cloud.

**Mejora futura:** evaluar self-hosting o plan superior si los costos o límites crecen.

---

### 3.3 Exceso de automatización temprana

El sistema está diseñado para automatizar mucho, pero automatizar demasiado pronto puede generar rigidez.

Riesgos:

- flujos mal validados con clientes reales,
- reglas que parecen correctas pero fallan en operación,
- exceso de edge cases antes de tener datos reales,
- dificultad para corregir rápido.

**Principio recomendado:** automatizar primero los flujos repetitivos y de bajo riesgo; dejar revisión humana en reservas conflictivas, eventos especiales, pagos dudosos y casos no estándar.

---

### 3.4 Dependencia de APIs externas

Futuras integraciones como Meta, MercadoPago, Booking o Airbnb pueden cambiar:

- costos,
- límites,
- políticas,
- formatos de webhook,
- requisitos de verificación.

**Regla:** ninguna API externa debe convertirse en fuente de verdad. Deben actuar como canales o conectores.

---

## 4. Mejoras futuras recomendadas

### 4.1 Migración progresiva a Supabase/PostgreSQL

No es urgente, pero debe seguir siendo la evolución natural si el sistema crece.

Migrar primero:

1. RESERVAS
2. PRE_RESERVAS
3. DISPONIBILIDAD_CACHE
4. PAGOS
5. HUÉSPEDES
6. LOG_CAMBIOS

Mantener Sheets como:

- panel operativo,
- vista de reportes,
- herramienta de edición controlada,
- interfaz para usuarios no técnicos.

---

### 4.2 Panel administrativo propio

A futuro, un panel web interno podría reemplazar parte de la edición manual en Sheets.

Funcionalidades deseables:

- ver calendario,
- crear bloqueos,
- modificar tarifas,
- ver pre-reservas,
- resolver conflictos,
- ver pagos,
- cargar gastos,
- disparar recálculos manuales,
- consultar logs.

Esto reduciría errores manuales y permitiría validaciones más estrictas.

---

### 4.3 Auditoría avanzada

LOG_CAMBIOS está bien definido, pero más adelante podría evolucionar a una auditoría más fuerte:

- guardar payload completo antes/después,
- registrar usuario, IP o canal,
- registrar workflow que generó el cambio,
- severidad del cambio,
- posibilidad de rollback parcial,
- alertas ante cambios sensibles.

---

### 4.4 Gestión avanzada de roles y permisos

La Etapa 1 define permisos conceptuales. A futuro conviene llevarlos a implementación real:

- admin,
- socio,
- encargado de reservas,
- limpieza,
- mantenimiento,
- bot,
- web pública,
- API externa.

Cada rol debería tener permisos estrictos de lectura/escritura.

---

### 4.5 Separar entorno de pruebas y producción

Antes de activar bots y pagos reales, conviene tener:

- base de prueba,
- workflows de prueba,
- modo sandbox de MercadoPago,
- datos ficticios,
- pruebas de reservas simultáneas,
- simulación de cancelaciones.

No conviene probar flujos peligrosos directamente sobre datos reales.

---

## 5. Testing necesario

Antes de pasar a operación real, se deberían probar como mínimo estos escenarios:

### 5.1 Integridad de reservas

- crear una pre-reserva,
- vencer una pre-reserva,
- confirmar una pre-reserva,
- cancelar una reserva,
- modificar fechas,
- bloquear una cabaña,
- bloquear todas las cabañas.

---

### 5.2 Concurrencia

- dos clientes intentando reservar la misma cabaña,
- un pago que llega después de vencer una pre-reserva,
- dos workflows escribiendo sobre el mismo huésped,
- recálculo de disponibilidad mientras se confirma una reserva.

---

### 5.3 Auditoría

- verificar que toda modificación crítica genera LOG_CAMBIOS,
- verificar que `source_event` nunca quede vacío,
- verificar que se pueda reconstruir el origen de una reserva.

---

### 5.4 Migrabilidad

- exportar una tabla a CSV,
- importarla en una base SQL de prueba,
- verificar que IDs, fechas, booleanos y relaciones se mantienen consistentes.

---

## 6. Límites actuales conocidos

### 6.1 La arquitectura todavía no está implementada completamente

El documento define la estructura, pero la validez real aparecerá en implementación.

Habrá que validar:

- rendimiento real de n8n,
- comportamiento de Sheets bajo carga,
- estabilidad de APIs externas,
- calidad de datos cargados manualmente,
- facilidad de uso para Vicky/socios.

---

### 6.2 Google Sheets permite errores humanos

Aunque sea cómodo, Sheets permite:

- borrar filas,
- editar IDs,
- cambiar formatos,
- duplicar registros,
- escribir en columnas incorrectas.

**Mitigación:** proteger rangos, validar datos, bloquear columnas críticas y usar formularios internos siempre que sea posible.

---

### 6.3 El modelo de datos puede requerir ajustes reales

Es probable que aparezcan nuevos campos:

- origen detallado de campaña,
- tipo de huésped,
- mascotas,
- limpieza especial,
- early check-in,
- late checkout,
- condiciones particulares de pago,
- preferencias del cliente.

Esto es normal. La arquitectura permite agregarlos sin romper el sistema.

---

## 7. Señales de que la arquitectura debe evolucionar

Conviene evaluar migración o refactor si aparecen estas señales:

- más de 50 reservas mensuales automatizadas,
- conflictos frecuentes de concurrencia,
- errores repetidos de sincronización,
- n8n tarda demasiado en workflows críticos,
- Sheets se vuelve difícil de mantener,
- demasiadas personas editan manualmente,
- se agregan varios complejos o muchas más cabañas,
- se vuelve necesario reportar contabilidad en tiempo real,
- el bot empieza a manejar volumen alto de consultas.

---

## 8. Deuda técnica prevista

No es deuda negativa: son temas conscientemente postergados.

### 8.1 Supabase/PostgreSQL

Postergado porque Sheets es suficiente para etapa inicial y más práctico para operación manual.

### 8.2 Panel interno propio

Postergado porque Sheets cumple la función inicial de backoffice.

### 8.3 Sistema avanzado de permisos

Postergado hasta que haya más usuarios o riesgo operativo.

### 8.4 Observabilidad avanzada

Postergada hasta que los workflows reales estén activos y se detecten cuellos de botella.

### 8.5 Multi-complejo / SaaS

No debe condicionar la implementación inicial. Primero validar Vita Delta.

---

## 9. Ideas futuras no prioritarias

Estas ideas pueden ser valiosas, pero no deberían distraer de la implementación base:

- convertir el sistema en SaaS para otros complejos,
- pricing dinámico con IA,
- predicción de demanda,
- sugerencias automáticas de descuentos,
- dashboard financiero avanzado,
- integración completa con Booking/Airbnb,
- app interna para limpieza,
- sistema de fidelización,
- automatización de mantenimiento preventivo,
- segmentación de clientes.

---

## 10. Prioridad real de evolución

### Crítico

- mantener una sola fuente de verdad,
- evitar double bookings,
- centralizar escrituras en n8n,
- proteger DISPONIBILIDAD_CACHE,
- registrar LOG_CAMBIOS,
- mantener `source_event`.

### Importante

- proteger Sheets,
- crear workflows API internos,
- definir entorno de pruebas,
- validar permisos reales,
- diseñar buena estrategia de backups.

### Mejora futura

- Supabase,
- panel interno,
- auditoría avanzada,
- dashboards,
- observabilidad.

### Experimental

- IA predictiva,
- pricing dinámico,
- producto SaaS,
- multi-complejo.

---

## 11. Recomendación final

La Etapa 1 está bien cerrada como arquitectura base. No conviene seguir refinándola indefinidamente.

El foco ahora debería estar en:

1. implementar de forma mínima pero correcta,
2. probar flujos reales,
3. detectar fricción operativa,
4. evitar automatización excesiva demasiado pronto,
5. mantener la arquitectura migrable.

El valor principal de esta etapa no es que todo esté automatizado todavía, sino que el sistema ya tiene una estructura coherente para crecer sin rehacerse desde cero.
