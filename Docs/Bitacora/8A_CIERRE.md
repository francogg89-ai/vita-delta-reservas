# 8A_CIERRE.md — Cierre formal Etapa 8A

**Etapa:** 8A — Entorno OPS operativo desde cero (`vita-delta-ops`)
**Estado:** ✅ Cerrada (cierre funcional con smoke de solo lectura)
**Fecha de cierre:** 2026-05-29
**Entorno creado:** Supabase OPS (`vita-delta-ops`, región sa-east-1 São Paulo, Free tier)
**Schema canónico replicado:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)
**Decisiones registradas en esta etapa:** D-8-13 (y confirmación de cumplimiento de D-8-03)

---

## 1. Resumen ejecutivo

La Etapa 8A creó **`vita-delta-ops`**, el tercer entorno de la estrategia
DEV → TEST → OPS → PROD, y el **primer entorno de operación real interna** del
sistema Vita Delta (D-8-09). No es un entorno de prueba: es donde van a vivir los
datos reales de reservas del complejo.

OPS se construyó como **proyecto Supabase independiente**, reconstruido desde el
canónico `6B_SCHEMA_SQL.md v1.7.3` (no es un clon físico de DEV ni de TEST). Se
sembraron los seeds reales mínimos, se aplicó el modelo de grants mínimo, se
verificaron los default privileges, se activó `pg_cron` y se conectó n8n con
credencial propia (`vita_supabase_ops`).

Resultado clave de seguridad: **OPS nació más cerrado que TEST**. Gracias a haber
creado el proyecto con el switch "Automatically expose new tables" en OFF desde el
día cero, las funciones nacieron sin EXECUTE a roles Data API y las tablas sin
SELECT/escritura para esos roles — sin necesidad de remediar nada después. El
objetivo de D-8-03 quedó cumplido por nacimiento, no por corrección posterior.

El objetivo de 8A era **dejar el entorno OPS listo y verificado** (schema paritario,
seguro, con cron y conectado a n8n para lectura). NO incluía la capa de carga ni
los calendarios (eso es 8B/8C). El smoke de cierre fue **solo lectura** por decisión
explícita (D-8-12): el primer write real será una reserva real futura cargada por
el flujo de 8B, para no ensuciar OPS desde el inicio.

---

## 2. Ficha del entorno OPS

- **Proyecto:** `vita-delta-ops`
- **Project ref (OPS_REF):** `lpiatqztudxiwdlcoasv`
- **Región:** sa-east-1 (São Paulo) — misma que DEV/TEST
- **Tier:** Free (decisión: revisar upgrade si aparecen límites reales de uso,
  backups, performance, o antes de PROD público)
- **PostgreSQL:** 17.6
- **Switches de creación:** Data API ON · "Automatically expose new tables" OFF ·
  "Enable automatic RLS" OFF
- **Conexión (pooler):**
  - Host: `aws-1-sa-east-1.pooler.supabase.com`
  - Puerto: `6543` (Transaction mode)
  - Database: `postgres`
  - User: `postgres.lpiatqztudxiwdlcoasv`
- **Credencial n8n:** `vita_supabase_ops` (Postgres, Ignore SSL Issues ON — regla
  L-6C-01). Test de conexión OK + verificación de identidad por convergencia.
- **Modelo de acceso:** Opción A — n8n entra como `postgres` por pooler. Sin
  consumidores Data API. RLS postergado (no es Opción B).

---

## 3. Trabajo realizado por bloque

| Bloque | Contenido | Verificación |
|---|---|---|
| 1-2 | Creación del proyecto + snapshot de nacimiento read-only | Entorno limpio: extensiones de fábrica, roles intactos (postgres/service_role bypassrls), 0 objetos del proyecto, defaults base capturados |
| 4 | Replicación del schema desde canónico v1.7.3, en 7 tandas (4.1 a 4.7) | Paridad estructural total P01-P10 |
| 5 | Seeds reales mínimos | Conteos OK + IDs de cabaña reales leídos |
| 6 | Grants mínimos (REVOKE EXECUTE idempotente, Opción B) | 0 EXECUTE a Data API; owner ejecuta; 13 funciones intactas |
| 7 | Default privileges (mini-disciplina propia) | Cerrado sin ejecución (D-8-13) |
| 8 | Schedule pg_cron (2 jobs) | 2 jobs activos + 1 corrida real `succeeded` |
| 9 | Verificación consolidada read-only | 17/17 checks OK |
| 10 | Credencial n8n `vita_supabase_ops` | Conexión OK + identidad por convergencia |
| 11 | Preparación n8n mínima de verificación (read-only) | Nodo Postgres lee OPS correctamente |
| 12 | Cierre formal | Este documento |

### 3.1 Paridad estructural (P01-P10) — schema idéntico al canónico

| Check | Obtenido | Esperado |
|---|---|---|
| Extensiones (btree_gist, pg_cron) | 2 | 2 |
| Enums | 4 | 4 |
| Tablas | 20 | 20 |
| Vistas | 6 | 6 |
| Funciones propias (excl. extensiones) | 13 | 13 |
| Triggers | 13 | 13 |
| EXCLUDE constraints | 2 | 2 |
| CHECK constraints (chk_*) | 38 | 38 |
| Foreign keys | 15 | 15 |
| Índices (5 uq_* + 22 idx_*) | 27 | 27 |

### 3.2 Seeds reales sembrados

- **5 cabañas reales** (IDs 1-5, secuencia natural):
  - 1 Bamboo (grande, 3/5, limpieza 1)
  - 2 Madre Selva (grande, 3/5, limpieza 2)
  - 3 Arrebol (grande, 3/5, limpieza 3)
  - 4 Guatemala (chica, 2/4, limpieza 4)
  - 5 Tokio (chica, 2/4, limpieza 5)
- **3 socios:** Franco 33.33, Rodrigo 33.34, Remo 33.33 (suma 100.00)
- **configuracion_general:** 10 claves operativas (incluye
  `horizonte_disponibilidad_dias=120`)
- **cuentas_cobro:** 1 real y activa — alias `playario`, transferencia_mp,
  CVU 0000003100010587293072, titular Franco Guaglianone
- **temporadas:** 1 baseline neutra "Baseline OPS 2026-2028" (NO productiva; evita
  gaps de cálculo). Sin tarifas reales (monto manual en 8B, D-8-04).
- **plantillas_mensajes:** 1 mínima (`prereserva_creada`)

### 3.3 Seguridad verificada

- Funciones con EXECUTE a roles Data API/PUBLIC: **0** (REVOKE idempotente aplicado
  como red de seguridad + paridad con 7B; OPS ya nació cerrado).
- Grants SELECT/INSERT/UPDATE/DELETE a roles Data API sobre tablas: **0**.
- Residual sobre tablas a roles Data API: solo `Dxtm`
  (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN), inocuo — igual que TEST.
- Default privileges del rol `postgres` (los que rigen objetos creados por el
  proyecto): conceden solo `Dxtm` inocuo a Data API → objetos futuros nacen
  cerrados. Ver D-8-13.

---

## 4. Decisiones registradas

### D-8-13 — Default privileges: cerrado sin ejecución
El diagnóstico del Bloque 7 (snapshot `pg_default_acl`) mostró que los defaults del
rol `postgres` —los únicos que rigen los objetos que crea el proyecto— conceden a
los roles Data API solo el residual inocuo `Dxtm`, sin SELECT/INSERT/UPDATE/DELETE/
EXECUTE. Por lo tanto, todo objeto futuro creado por el proyecto nace cerrado y
**D-8-03 queda cumplida sin necesidad de `ALTER DEFAULT PRIVILEGES`**.

Los 21 defaults "amplios" detectados pertenecen al rol de plataforma
`supabase_admin`, **no aplican a objetos creados por el proyecto** y no se
modifican. Se mantiene la línea de 7B: cerrar lo propio, no reconfigurar la
plataforma. Tocar los defaults de `supabase_admin` sería riesgo sin beneficio de
seguridad real (Opción A: la Data API no está en uso).

### Confirmación de cumplimiento de D-8-03
OPS nació con grants mínimos por efecto del switch correcto de creación. El REVOKE
EXECUTE del Bloque 6 se aplicó igual como barrera explícita e intencional (Opción B
elegida por Franco), no porque hubiera EXECUTE que quitar.

---

## 5. Aprendizajes operativos (para futuras réplicas, p. ej. PROD)

- **El SQL Editor de Supabase ejecuta solo lo seleccionado.** Si hay texto
  resaltado, "Run" corre únicamente esa porción. Ejecutar siempre con NADA
  seleccionado para correr el panel completo. (Causó varios falsos "0 filas" al
  inicio del Bloque 4.)
- **El conteo de funciones debe excluir las de extensiones.** `btree_gist` instala
  188 funciones en `public`. Sin filtrar por `NOT EXISTS (pg_depend deptype='e')`,
  el conteo da 201 en vez de 13. `pg_cron` instala las suyas en el schema `cron`,
  no en `public`.
- **El conteo de enums debe filtrar por `n.nspname='public' AND t.typtype='e'`,**
  no por `LIKE '%_enum'` (colisiona con tipos de sistema `pg_enum`, `_pg_enum`,
  `anyenum`).
- **"Run without RLS" es esperado y correcto** al crear tablas/triggers con RLS
  automático OFF. Aceptar y continuar.
- **Verificaciones grandes: evitar `UNION ALL` con comentarios intercalados entre
  ramas.** Es frágil. Preferir una sola consulta con subqueries escalares por
  columna (más robusta y legible). (Causó un error de sintaxis en la v1 del
  Bloque 9.)
- **`current_database()` devuelve `postgres` en los tres entornos:** no sirve para
  distinguir OPS de DEV/TEST. La identidad se confirma por convergencia (datos
  sembrados: 5 cabañas con nombres reales).
- **OPS nació más cerrado que TEST** gracias al switch "exponer tablas nuevas" en
  OFF desde la creación. En PROD, replicar esos mismos switches de creación.

---

## 6. Lo que NO se hizo en 8A (alcance respetado)

- **Sin capa de carga (Form Trigger):** es 8B.
- **Sin calendarios visuales:** es 8C.
- **Sin bloqueos operativos de uso real:** es 8D.
- **Sin write transaccional en OPS:** smoke de cierre solo lectura (D-8-12). El
  primer write será una reserva real futura por el flujo de 8B.
- **Sin workflows de escritura `__OPS`:** solo se preparó el nodo mínimo de
  verificación read-only (Bloque 11).
- **Sin tarifas reales:** monto manual (D-8-04).
- **Sin tocar DEV ni TEST.** DEV no se usó en toda la etapa (criterio de Franco:
  DEV queda en pausa hasta abordar sus pendientes 1.7).

---

## 7. Estado del entorno al cierre

OPS = schema completo y paritario (P01-P10 10/10) + seeds reales + seguridad
cerrada (grants mínimos + defaults seguros) + pg_cron activo (corrida real
verificada) + n8n conectado por credencial propia y verificado por identidad.

**OPS está listo para 8B** (capa de carga de Vicky: Form Trigger n8n que encadena
crear_prereserva → registrar_pago → confirmar_reserva, con elección de cabaña por
nombre — los IDs reales son 1-5).

---

## 8. Próximos pasos (post-8A)

1. **8B — Capa de carga de Vicky.** Form Trigger n8n, encadenado de las 3 funciones
   en una acción, montos editables (total + seña 50% editable), campo `operador`/
   `cargado_por` (mapeo técnico a verificar por contrato real con
   `pg_get_functiondef` antes de implementar), manejo claro de colisión.
2. **8C — Calendarios visuales por evento** (nuestro + Jenny). Formato de 8C
   (Sheet repintado vs HTML) sigue pendiente, se decide al diseñar 8C.
3. **8D — Bloqueos operativos + cierre de Etapa 8.**

**Pendientes que no bloquean 8B:** residual A5 en DEV (pendiente 1.7), RLS (solo si
OPS pasara a Opción B), tarifas reales, frontend de carga "de verdad".

---

*Fin del cierre formal de 8A. Entorno `vita-delta-ops` operativo, paritario, seguro
y conectado. Listo para iniciar 8B.*
