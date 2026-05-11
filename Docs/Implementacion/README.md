# Implementación — Vita Delta Reservas

Este directorio contiene los documentos operativos para implementar el sistema de reservas de Vita Delta.

A diferencia de `Docs/Arquitectura`, esta carpeta no redefine decisiones conceptuales. Su función es guiar la ejecución práctica de lo ya diseñado.

---

## Estado

La arquitectura base del sistema ya fue definida en:

```txt
Docs/Arquitectura/
```

La implementación comienza desde la Etapa 5, con foco en construir primero una base mínima, controlada y verificable.

---

## Documento principal

El documento operativo principal es:

```txt
PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
```

Este plan guía la primera jornada de implementación real.

---

## Objetivo inmediato

Crear y preparar los dos Google Sheets iniciales:

```txt
VITA_DELTA_DEV
VITA_DELTA_TEST
```

Estos Sheets serán la base para probar el primer workflow real de n8n:

```txt
db_recalcular_disponibilidad
```

---

## Qué se implementa primero

La secuencia inmediata es:

```txt
Crear Sheets DEV / TEST
→ Crear hojas
→ Cargar encabezados exactos
→ Cargar datos mínimos
→ Configurar validaciones
→ Configurar protecciones
→ Verificar estructura
→ Implementar db_recalcular_disponibilidad
```

---

## Qué NO se implementa todavía

En esta fase todavía no se implementa:

- WhatsApp Cloud API.
- Instagram Graph API.
- Claude API.
- Bot conversacional.
- MercadoPago automático.
- Frontend público.
- Pagos automáticos.
- Coordinación automática con Jennifer.
- Google Calendar.
- Contabilidad.
- Distribución entre socios.
- Migración a Supabase/PostgreSQL.

---

## Principio de implementación

```txt
Primero consistencia.
Después automatización.
Después canales externos.
Después inteligencia conversacional.
```

No se debe conectar WhatsApp, Instagram, MercadoPago ni Claude API hasta que el corazón transaccional esté validado.

---

## Flujo mínimo a validar

La Etapa 5B define el primer flujo operativo completo:

```txt
CONSULTA
→ PRE_RESERVA
→ PAGO manual validado
→ RESERVA confirmada
→ recálculo de DISPONIBILIDAD_CACHE
→ LOG_CAMBIOS
```

Este flujo debe funcionar primero de forma interna, manual y controlada.

---

## Entornos

La implementación contempla tres entornos:

| Entorno | Nombre | Uso |
|---|---|---|
| DEV | `VITA_DELTA_DEV` | Desarrollo y pruebas libres |
| TEST | `VITA_DELTA_TEST` | Validación controlada |
| PROD | `VITA_DELTA_PROD` | Producción futura |

En esta fase solo se crean y usan:

```txt
VITA_DELTA_DEV
VITA_DELTA_TEST
```

`PROD` no debe activarse hasta que TEST esté validado.

---

## Regla crítica

Nunca ejecutar workflows de prueba contra datos productivos.

Los IDs de Sheets deben configurarse por entorno y nunca hardcodearse dentro de los workflows de n8n.

---

## Primer workflow

El primer workflow real será:

```txt
db_recalcular_disponibilidad
```

Debe leer:

- `CABAÑAS`
- `BLOQUEOS`
- `RESERVAS`
- `PRE_RESERVAS`
- `OVERRIDES_OPERATIVOS`
- `CONFIGURACION_GENERAL`

y escribir:

- `DISPONIBILIDAD_CACHE`
- `LOG_CAMBIOS`

---

## Criterio para avanzar

No se debe avanzar a otros workflows hasta que:

- `VITA_DELTA_DEV` esté creado.
- `VITA_DELTA_TEST` esté creado.
- Ambas estructuras estén verificadas.
- Los datos mínimos estén cargados.
- Las validaciones principales estén configuradas.
- Las protecciones mínimas estén aplicadas.
- `db_recalcular_disponibilidad` funcione en DEV.
- `DISPONIBILIDAD_CACHE` se pueble correctamente.
- No haya errores críticos en `LOG_CAMBIOS`.

---

## Relación con arquitectura

Este directorio depende de:

```txt
Docs/Arquitectura/ARQUITECTURA_ETAPA_5A_MODELO_DATOS_REAL.md
Docs/Arquitectura/ARQUITECTURA_ETAPA_5B_IMPLEMENTACION_VERTICAL_MINIMA.md
```

Si aparece una contradicción entre implementación y arquitectura, prevalecen los documentos de arquitectura cerrados, salvo que se documente explícitamente una corrección posterior.

---

## Próximo paso

Seguir:

```txt
PLAN_ETAPA_5_IMPLEMENTACION_REAL.md
```

y completar el checklist de cierre de jornada.

Cuando el checklist esté completo, comenzar la implementación de:

```txt
db_recalcular_disponibilidad
```

en n8n.
