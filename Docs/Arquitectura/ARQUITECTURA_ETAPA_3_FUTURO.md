# ARQUITECTURA_ETAPA_3_FUTURO.md

## Estado actual de la Etapa 3

La Etapa 3 dejó definido el motor completo de precios del sistema Vita Delta.

Incluye:
- jerarquía tarifaria,
- temporadas,
- multiplicadores,
- reglas marginales,
- semanas completas,
- estadías largas,
- feriados,
- eventos especiales,
- descuentos,
- extras por personas,
- señas,
- techos tarifarios,
- redondeo,
- separación entre motor estándar y EVENTOS_ESPECIALES.

La arquitectura actual separa correctamente:
- reglas comerciales,
- reglas operativas,
- precios,
- configuración,
- eventos especiales,
- cargos futuros,
- descuentos,
- cálculo determinístico.

El motor quedó preparado para:
- escalabilidad,
- migración futura,
- automatización,
- integración con bots,
- integración web,
- múltiples tipos de cabaña,
- expansión comercial.

---

# Riesgos futuros identificados

## 1. Sobrecomplejidad comercial

El mayor riesgo futuro no es técnico sino comercial.

Demasiadas:
- promociones,
- descuentos,
- eventos especiales,
- excepciones,
- combinaciones,
- reglas temporales,

pueden volver:
- difícil entender precios,
- difícil explicarlos,
- difícil debuggear resultados,
- difícil mantener coherencia comercial.

La arquitectura soporta mucha complejidad.
Eso no significa que deba usarse toda.

---

## 2. Eventos especiales excesivos

EVENTOS_ESPECIALES resolvió correctamente el problema de Año Nuevo.

Pero si demasiadas fechas:
- salen del motor estándar,
- usan lógica propia,
- tienen paquetes únicos,

el sistema puede fragmentarse demasiado.

El motor estándar debe seguir siendo:
- la regla general,
- la lógica principal,
- la base comercial.

EVENTOS_ESPECIALES debería usarse solo cuando:
- la lógica realmente cambia,
- el comportamiento comercial es distinto,
- o el pricing estándar deja de representar la realidad.

---

## 3. Dependencia de configuración manual

Actualmente:
- temporadas,
- tarifas,
- descuentos,
- paquetes,
- promociones,

dependen de carga manual correcta.

Errores humanos pueden generar:
- precios incoherentes,
- descuentos excesivos,
- techos mal aplicados,
- inconsistencias comerciales.

Será importante:
- validar datos,
- versionar cambios,
- auditar modificaciones,
- mantener LOG_CAMBIOS sólido.

---

## 4. Multiplicadores cruzados

La lógica por noche resolvió correctamente:
- temporadas cruzadas,
- semanas parciales,
- bloques híbridos.

Pero puede volverse difícil de explicar al huésped si:
- el precio cambia demasiado dentro de una misma estadía,
- hay múltiples temporadas en pocos días,
- existen demasiados multiplicadores activos.

Importante mantener:
- transparencia,
- desglose claro,
- comunicación simple.

---

## 5. Riesgo de descuentos acumulativos

El sistema ya prevé:
- prioridad,
- combinabilidad,
- mínimos,
- concurrencia.

Pero si en el futuro:
- se agregan demasiados descuentos,
- promociones automáticas,
- campañas temporales,
- cupones,
- beneficios por canal,

la complejidad puede crecer rápidamente.

El pricing debe seguir siendo:
- entendible,
- predecible,
- controlable.

---

# Testing futuro necesario

## Testing crítico

### Temporadas cruzadas
Validar:
- reservas que cruzan temporadas,
- múltiples multiplicadores,
- cambios de temporada dentro de semanas completas,
- redondeos.

---

### Regla de techo
Validar:
- casos extremos,
- descuentos posteriores,
- extras posteriores,
- semanas parciales,
- combinaciones raras.

---

### EVENTOS_ESPECIALES
Validar:
- derivación correcta,
- intersección de fechas,
- paquetes inexistentes,
- fallback a “consultar”.

---

### Estadías largas
Validar:
- máximos por temporada,
- sobrantes incluidos,
- sobrantes cobrados,
- cambios de política según temporada.

---

### Descuentos
Validar:
- concurrencia,
- prioridad,
- combinabilidad,
- vencimientos,
- límites máximos.

---

### Personas extra
Validar:
- capacidad máxima,
- cálculo correcto por noche,
- integración con descuentos,
- integración con eventos especiales.

---

# Mejoras futuras posibles

## 1. Pricing dinámico

Futuro posible:
- subir precios por ocupación,
- bajar precios automáticamente en baja demanda,
- reglas automáticas por anticipación,
- yield management básico.

IMPORTANTE:
El pricing dinámico debe seguir siendo determinístico y auditable.

---

## 2. Dashboard comercial

Visualizar:
- ocupación,
- revenue,
- ADR,
- RevPAR,
- ingresos por canal,
- descuentos aplicados,
- conversión.

---

## 3. Simulación comercial

Poder simular:
- impacto de precios,
- impacto de promociones,
- impacto de temporadas,
- escenarios de ocupación.

---

## 4. Motor multi-complejo

La arquitectura ya permite:
- múltiples tipos de cabaña,
- múltiples temporadas,
- múltiples reglas.

A futuro podría expandirse a:
- múltiples complejos,
- múltiples marcas,
- múltiples ubicaciones.

---

## 5. Integración fiscal

La CAPA_DE_CARGOS futura podría incorporar:
- IVA,
- percepciones,
- facturación,
- conciliación,
- comisiones automáticas.

---

# Límites actuales conocidos

## Google Sheets

Suficiente para:
- operación inicial,
- pocas propiedades,
- automatización moderada.

Puede complicarse con:
- demasiadas tarifas,
- demasiados eventos especiales,
- demasiados descuentos,
- alta concurrencia.

---

## Mantenimiento manual

La arquitectura es robusta.

Pero requiere:
- disciplina operativa,
- mantenimiento de precios,
- revisión de temporadas,
- limpieza de promociones vencidas.

---

## Complejidad comunicacional

Aunque el motor sea correcto matemáticamente:
el huésped no debe sentir que el pricing es complicado.

La UX siempre debe simplificar:
- el precio final,
- el desglose,
- la explicación.

---

# Señales de que la arquitectura necesita evolucionar

- demasiados overrides comerciales,
- demasiados descuentos simultáneos,
- eventos especiales constantes,
- dificultad para explicar precios,
- demasiadas excepciones,
- conflictos manuales frecuentes,
- errores recurrentes de configuración.

---

# Decisiones arquitectónicas que NO deberían romperse

## 1. Backend determinístico

El precio nunca debe depender de IA.

---

## 2. Separación entre TARIFAS y CONFIGURACION_GENERAL

Los precios viven en TARIFAS.
Las reglas viven en configuración.

---

## 3. Separación entre motor estándar y EVENTOS_ESPECIALES

No volver a mezclar Año Nuevo ni eventos especiales dentro de la lógica principal.

---

## 4. Aplicación por noche de multiplicadores

Nunca volver a multiplicadores “globales” por reserva.

La lógica por noche resuelve correctamente:
- temporadas cruzadas,
- semanas híbridas,
- combinaciones complejas.

---

## 5. Regla de techo antes de descuentos

El techo protege el alojamiento base.
Los descuentos son estrategia comercial posterior.

---

## 6. Extras fuera del techo

Los extras representan costos reales adicionales.

No deben ser absorbidos por promociones generales.

---

# Ideas futuras no prioritarias

- pricing inteligente,
- IA comercial,
- recomendaciones automáticas,
- sugerencias de promociones,
- predicción de demanda,
- ajuste automático de temporadas,
- benchmarking con competencia,
- simulación de revenue.

---

# Prioridad real

## Crítico
- coherencia comercial,
- integridad matemática,
- determinismo,
- transparencia.

## Importante
- UX,
- dashboards,
- mantenimiento,
- observabilidad.

## Futuro
- pricing dinámico,
- automatización comercial,
- analytics avanzados.

## Experimental
- IA predictiva,
- optimización automática,
- pricing autónomo.

---

# Principio final de la Etapa 3

El motor de precios debe ser:
- consistente,
- entendible,
- auditable,
- configurable,
- escalable,
- comercialmente lógico.

La complejidad interna nunca debe trasladarse al huésped.