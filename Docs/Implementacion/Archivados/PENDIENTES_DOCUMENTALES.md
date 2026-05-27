# Pendientes documentales — Vita Delta Reservas

Este archivo registra aclaraciones o ajustes documentales detectados durante la implementación, para evitar que se pierdan antes de incorporarlos a los documentos fuente correspondientes.

---

## 1. Convención de noche operativa

**Estado:** pendiente de incorporar  
**Prioridad:** alta  
**Afecta a:** pricing, disponibilidad, `DISPONIBILIDAD_CACHE`, `db_recalcular_disponibilidad`

### Documentos donde debe agregarse

- `Docs/Arquitectura/ARQUITECTURA_ETAPA_3_VITA_DELTA.md`
- `Docs/Arquitectura/ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md`

### Texto a incorporar

Toda fecha en `DISPONIBILIDAD_CACHE` representa la noche que comienza en esa fecha.

Por lo tanto:

- Domingo → lunes: noche de semana.
- Lunes → martes: noche de semana.
- Martes → miércoles: noche de semana.
- Miércoles → jueves: noche de semana.
- Jueves → viernes: noche de semana.
- Viernes → sábado: noche de finde.
- Sábado → domingo: noche de finde.

Ejemplo: una reserva con check-in jueves y check-out viernes ocupa la noche del jueves, por lo tanto se clasifica como `tipo_dia = semana`.

Los feriados prevalecen sobre esta clasificación:

- `FERIADOS.tipo = ano_nuevo` → `tipo_dia = ano_nuevo`.
- `FERIADOS.tipo = nacional` o `local` → `tipo_dia = feriado`.

### Motivo

Evitar interpretaciones erróneas donde se clasifique una estadía según el día de checkout.  
La clasificación correcta se hace por la noche vendida, no por el día de salida.

Ejemplo crítico:

- Check-in jueves / check-out viernes = noche del jueves = `semana`.
- Check-in viernes / check-out sábado = noche del viernes = `finde`.