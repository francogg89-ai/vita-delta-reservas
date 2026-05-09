# ARQUITECTURA_ETAPA_2_FUTURO.md

## Estado actual de la Etapa 2

La Etapa 2 dejó definido el motor completo de disponibilidad del sistema Vita Delta.

Incluye:
- reglas de horarios,
- último día del bloque,
- escalonamiento operativo,
- flexibilidad de check-in/check-out,
- overrides operativos,
- DISPONIBILIDAD_CACHE,
- triggers de recálculo,
- edge cases,
- race conditions,
- límites operativos,
- precedencia de reglas.

El sistema ya tiene separación correcta entre:
- lógica determinística,
- configuración,
- excepciones operativas,
- interfaz conversacional.

La arquitectura actual es suficiente para operar un complejo pequeño/mediano de forma robusta.

---

# Riesgos futuros identificados

## 1. Sobrecomplejidad operacional

El mayor riesgo no es técnico sino operativo.

Demasiadas reglas especiales pueden:
- volver difícil explicar disponibilidad al huésped,
- generar confusión en el equipo,
- aumentar overrides manuales,
- volver difícil debuggear casos raros.

Especial atención a:
- escalonamientos,
- bloques extendidos por feriados,
- horarios personalizados,
- excepciones manuales.

---

## 2. Escalonamiento excesivo

Si el complejo crece o aumenta la rotación:
- Jennifer podría no absorber la carga,
- los horarios podrían volverse comercialmente incómodos.

Especialmente:
- checkouts demasiado temprano,
- checkins demasiado tarde.

La arquitectura ya prevé:
- límites,
- overrides,
- desactivación completa.

Pero eventualmente puede requerirse:
- más personal,
- más automatización operativa,
- dividir horarios por zonas o tipos de cabaña.

---

## 3. Dependencia de DISPONIBILIDAD_CACHE

La cache es correcta arquitectónicamente.

Pero a futuro:
- el recálculo masivo podría crecer,
- demasiados triggers simultáneos podrían generar latencia,
- Google Sheets podría limitar throughput.

Señales de alerta:
- workflows lentos,
- inconsistencias frecuentes,
- recalculados acumulados,
- delays visibles para el huésped.

---

## 4. Riesgo de overrides excesivos

Los OVERRIDES_OPERATIVOS son necesarios.

Pero si empiezan a utilizarse demasiado:
- indican que la lógica base no representa la operación real,
- o que el negocio se volvió demasiado complejo para la arquitectura actual.

Métrica importante futura:
- cantidad de overrides por mes,
- tipos más usados,
- overrides repetitivos.

Si ciertos overrides se repiten constantemente:
→ probablemente deban convertirse en reglas reales del motor.

---

# Testing futuro necesario

## Testing crítico

### Race conditions
Probar:
- dos clientes reservando simultáneamente,
- pagos simultáneos,
- expiración de pre-reservas durante checkout.

---

### Escalonamiento
Probar:
- múltiples checkouts el mismo día,
- múltiples checkins el mismo día,
- límites operativos,
- aceptación explícita del huésped.

---

### Último día del bloque
Validar:
- feriados largos,
- feriados cruzados,
- fines de semana extendidos,
- reservas parciales.

---

### Overrides
Validar:
- precedencia,
- conflictos,
- rangos de fechas,
- desactivación.

---

### Cache
Validar:
- consistencia,
- recálculo parcial,
- recálculo masivo,
- sincronización con reservas reales.

---

# Mejoras futuras posibles

## 1. Redis o cache real

Actualmente DISPONIBILIDAD_CACHE vive en Sheets.

A futuro podría migrarse a:
- Redis,
- PostgreSQL materialized views,
- Supabase cache layer.

No es necesario hoy.

---

## 2. Observabilidad

Agregar:
- métricas,
- logs centralizados,
- dashboards,
- alertas automáticas,
- historial de recalculados.

Especialmente útil si el sistema se vuelve multi-complejo.

---

## 3. Simulador de carga operativa

Futuro posible:
- visualizar cuántas limpiezas hay por día,
- detectar cuellos de botella,
- sugerir bloqueos automáticos,
- predecir saturación.

---

## 4. Overrides inteligentes

Futuro posible:
- sugerencias automáticas,
- overrides temporales generados por IA,
- detección de días problemáticos.

IMPORTANTE:
La IA puede sugerir overrides.
Nunca aplicarlos automáticamente sin validación humana.

---

# Límites actuales conocidos

## Google Sheets

Suficiente para:
- 5–10 cabañas,
- automatización mediana,
- tráfico moderado.

Puede empezar a sufrir con:
- demasiadas escrituras concurrentes,
- miles de recalculados diarios,
- múltiples complejos.

---

## n8n

Excelente para esta etapa.

Pero eventualmente:
- podría requerir colas reales,
- workers separados,
- manejo más avanzado de concurrencia.

---

## Meta API

WhatsApp e Instagram dependen de:
- políticas externas,
- límites de conversación,
- cambios de API,
- tiempos de aprobación de Meta.

Nunca asumir estabilidad absoluta.

---

# Señales de que la arquitectura necesita evolucionar

- demasiados overrides manuales,
- conflictos frecuentes,
- tiempos de respuesta altos,
- recálculos lentos,
- demasiadas reservas simultáneas,
- debugging difícil,
- operaciones imposibles de explicar al huésped,
- demasiada intervención manual.

---

# Decisiones arquitectónicas que NO deberían romperse

## 1. Backend determinístico

La disponibilidad nunca debe depender de IA.

---

## 2. DISPONIBILIDAD_CACHE como resultado derivado

Nunca escribir disponibilidad manualmente.

---

## 3. Una sola fuente de verdad

La disponibilidad siempre deriva de:
- reservas,
- pre-reservas,
- bloqueos,
- configuración.

---

## 4. Separación entre lógica y conversación

El bot conversa.
El backend decide.

---

## 5. Escalabilidad sin rehacer arquitectura

Agregar una cabaña nunca debería requerir cambios estructurales.

---

# Ideas futuras no prioritarias

- pricing dinámico por ocupación,
- predicción de demanda,
- sugerencias automáticas de disponibilidad,
- optimización automática de horarios,
- IA predictiva,
- panel visual de carga operativa,
- simulación de ocupación futura,
- recomendaciones automáticas de bloqueos.

---

# Prioridad real

## Crítico
- consistencia,
- race conditions,
- integridad,
- estabilidad operativa.

## Importante
- UX,
- velocidad,
- observabilidad,
- debugging.

## Futuro
- IA avanzada,
- optimización,
- automatización predictiva.

## Experimental
- disponibilidad inteligente,
- autoajuste operativo,
- IA operativa autónoma.