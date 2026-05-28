# 7B_CIERRE.md — Cierre formal Etapa 7B

**Etapa:** 7B — Levantamiento del entorno TEST
**Estado:** ✅ Cerrada (cierre funcional con happy paths)
**Fecha de cierre:** 2026-05-28
**Entorno creado:** Supabase TEST (`vita-delta-test`, región sa-east-1 São Paulo, Free tier)
**Schema canónico replicado:** `6B_SCHEMA_SQL.md v1.7.3`
**Autores:** Franco (titular) + Claude (arquitecto)

---

## 1. Resumen ejecutivo

La Etapa 7B levantó un entorno **TEST completo, separado, paritario, seguro y
operativo**, como segundo entorno de la estrategia DEV → TEST → OPS → PROD.

TEST se construyó como **proyecto Supabase independiente** (no un clon físico de
DEV): el schema se reconstruyó desde el canónico `6B_SCHEMA_SQL.md v1.7.3`, se
sembraron los seeds mínimos, se activó `pg_cron`, se normalizaron los permisos
de la Data API y se importaron los 8 workflows n8n con credencial propia
(`vita_supabase_test`) y sufijo `__TEST`.

Se validó la operación end-to-end de los 8 workflows contra TEST, incluyendo la
**cadena transaccional completa** crear_prereserva → registrar_pago →
confirmar_reserva, con verificación posterior de que el motor de disponibilidad
refleja la transición de estado.

**DEV no se tocó durante 7B** salvo consultas read-only aprobadas al inicio
(diagnóstico de paridad y verificación del rol de conexión n8n). TEST quedó
aislado de DEV por credencial propia y por workflows separados.

El objetivo de 7B era **levantar** TEST, no ejecutar una batería exhaustiva de
casos de error. Los happy paths se consideran evidencia suficiente para el
cierre. La validación funcional ampliada (casos de error) queda como pendiente
explícito para una etapa posterior.

---

## 2. Estado inicial (pre-7B)

| Recurso | Estado pre-7B |
|---|---|
| Schema canónico | `6B_SCHEMA_SQL.md v1.7.3` (resultante de 7A) |
| Entorno operativo | DEV único (alineado a v1.7.3) |
| Etapas cerradas | 6B, 6C, 6D, 7A |
| TEST / OPS / PROD | No existían |
| Workflows n8n | 8 workflows cableados a credencial DEV (`vita_supabase_dev`) |

Estrategia vigente confirmada: DEV → TEST → OPS → PROD.

---

## 3. Alcance y bloques

La etapa se ejecutó con disciplina de bloques numerados, cada uno con snapshot
read-only previo, diseño aprobado, ejecución y verificación.

| Bloque | Descripción | Estado |
|---|---|---|
| 7B-0 | Diagnóstico de paridad DEV (read-only) | ✅ |
| 7B-1 | Creación del proyecto TEST | ✅ |
| 7B-2 | Replicación del schema v1.7.3 (Bloques 1-20) | ✅ |
| 7B-3 | Seeds mínimos (Bloque 21) | ✅ |
| 7B-3-cron | Activación de `pg_cron` (Bloque 22) + ejecuciones reales | ✅ |
| 7B-GRANTS | Normalización de permisos Data API | ✅ |
| 7B-4 | Parametrización n8n DEV/TEST + smokes de los 8 workflows | ✅ |
| 7B-CIERRE | Cierre formal (este documento) | ✅ |

---

## 4. Creación de TEST (7B-1)

Proyecto `vita-delta-test`, región sa-east-1 (São Paulo), Free tier.

Configuración de creación clave:
- **"Enable Data API"**: ON.
- **"Automatically expose new tables to Data API"**: **DESTILDADO** (decisión
  central: las tablas nuevas no se exponen automáticamente a PostgREST).
- **"Enable automatic RLS"**: OFF (RLS postergado, ver decisiones).

Snapshot de nacimiento (read-only) confirmó:
- Extensiones de fábrica: `pg_stat_statements`, `pgcrypto`, `plpgsql`,
  `supabase_vault`, `uuid-ossp` (faltaban `btree_gist` y `pg_cron`, creadas en
  Bloque 1).
- Roles idénticos a DEV (`service_role`/`postgres` con `bypassrls=true`).
- Tablas del proyecto vacías; default privileges sin SELECT/escritura para roles
  Data API.

**Conexión n8n:** Shared Pooler IPv4, host `aws-1-sa-east-1.pooler.supabase.com`,
puerto `6543`, database `postgres`, user `postgres.<TEST_REF>`, Ignore SSL Issues
ON (regla L-6C-01).

---

## 5. Paridad estructural con DEV (7B-2)

El schema se reconstruyó **desde el canónico v1.7.3** (no dump/restore, no desde
DEV), en 6 tandas (Bloques 1-20): extensiones + enums, tablas, EXCLUDE, funciones
+ triggers (dos tandas), y vistas.

**Paridad demostrada (no asumida):** script comparativo P01-P10 corrido en ambos
entornos (read-only), resultado **10/10 idéntico**:

| Métrica | DEV | TEST |
|---|---|---|
| Extensiones del proyecto | `btree_gist`, `pg_cron` | idem |
| Enums | 4 | 4 |
| Tablas | 20 | 20 |
| Vistas | 6 | 6 |
| Funciones del proyecto | 13 | 13 |
| Triggers | 13 | 13 |
| Constraints EXCLUDE | 2 | 2 |
| Constraints CHECK | 38 | 38 |
| Foreign Keys | 15 | 15 |
| Índices únicos | 27 | 27 |

---

## 6. Seeds cargados (7B-3)

Bloque 21 (solo INSERTs, sin TRUNCATE de rollback). Verificado:

| Tabla | Filas | Detalle |
|---|---|---|
| `cabanas` | 5 | grandes cap 3/5 = 3; chicas cap 2/4 = 2 |
| `socios` | 3 | suma de participación = 100.00 |
| `configuracion_general` | 10 | incluye `horizonte_disponibilidad_dias=120`, `hora_checkout_domingo=16:00` |
| `cuentas_cobro` | 1 | inactiva |
| `temporadas` | 1 | multiplicador 1.000 |
| `plantillas_mensajes` | 1 | — |

**IDs reales de cabaña en TEST:** `1=Bamboo, 2=Madre Selva, 3=Arrebol,
4=Guatemala, 5=Tokio`. **No coinciden con DEV, que conserva IDs históricos
`17-21`.** Los inputs de prueba deben ajustarse por ambiente: lo portable es la
estructura lógica de los workflows, no los valores de input.

---

## 7. Cron activo y ejecuciones reales (7B-3-cron)

Bloque 22 creó 2 jobs `pg_cron`:
- `expirar_prereservas` — `*/5 * * * *` (cada 5 min), active=true.
- `cleanup_cron_history` — `0 3 1 * *` (mensual), active=true.

**Ejecuciones reales verificadas** en `cron.job_run_details`: `expirar_prereservas`
corriendo cada 5 minutos con `status=succeeded` y `return_message="1 row"`
(intervalos confirmados 14:30, 14:35, 14:40 y posteriores). Paridad de
comportamiento con DEV.

---

## 8. Permisos Data API normalizados (7B-GRANTS)

TEST adoptó un **modelo de grants mínimo y cerrado**, no paridad de grants con DEV.

Diagnóstico (script G1-G5 read-only) reveló que tras crear los objetos, los
defaults de PostgreSQL/Supabase habían aplicado:
- `Dxtm` residual (TRUNCATE/REFERENCES/TRIGGER) a roles Data API sobre
  tablas/vistas — **sin SELECT/INSERT/UPDATE/DELETE**.
- `EXECUTE` a `PUBLIC` sobre las 13 funciones del proyecto (default PostgreSQL).

**Acción aplicada:** `REVOKE EXECUTE` sobre las 13 funciones a `PUBLIC`, `anon`,
`authenticated`, `service_role` (idempotente). Verificación posterior:
- G3 post-revoke: **sin filas** (ninguna función invocable por esos roles vía
  RPC/Data API).
- Owner de funciones: `postgres` (intacto) → n8n sigue ejecutando por ownership.

**Verificación previa de seguridad:** se confirmó que n8n conecta con rol
`postgres` (owner) por pooler, por lo que el REVOKE no afecta la invocación de
funciones desde los workflows. Probado empíricamente después: W1 (read-only) y
W2-W6 (writes) invocaron funciones sin problema tras el REVOKE.

`Dxtm` residual se dejó documentado e intacto (no incluye lectura/escritura; no
habilita Data API; revocarlo agrega complejidad sin cerrar riesgo real).
`sequences` sin grants. Default privileges sin SELECT/escritura automática.

---

## 9. Workflows W0-W7 importados y validados (7B-4)

Los 8 workflows se duplicaron con sufijo `__TEST`, credencial reasignada a
`vita_supabase_test`, y se les eliminó `id`/`versionId`/`meta` para que n8n
crease workflows nuevos sin pisar los de DEV.

| Workflow | Tipo | Smoke | Resultado |
|---|---|---|---|
| W0 smoke_test | estructural | conexión + `ok=1` | ✅ |
| W1 consultar_disponibilidad | read-only | 5 cabañas, rango | ✅ |
| W7 vistas_operativas | read-only | `vista_disponibilidad`, 500 filas | ✅ |
| W2 crear_prereserva | write | pre-reserva creada | ✅ |
| W5 cancelar_prereserva | write | cancelada_por_cliente | ✅ |
| W6 crear_bloqueo | write | bloqueo específico Arrebol | ✅ |
| W3 registrar_pago | write | pago en_revision | ✅ |
| W4 confirmar_reserva | write | reserva creada | ✅ |

Convenciones aplicadas en los workflows TEST:
- `source_event` con marcador de ambiente: `n8n_test_w0X_..._manual` (se persiste
  en `log_cambios` para los writes; en read-only es solo trazabilidad n8n).
- `idempotency_key` de W2 con prefijo `manual_test` (se persiste en la
  pre-reserva → inequívoca de TEST).
- `id_evento_dev` → `id_evento_test` (renombrado en W5, W6, W3, W4; W2 no lo usa).
- `canal: manual_test` en los writes.
- IDs de cabaña reales de TEST (1-5).

---

## 10. Cadena end-to-end W2 → W3 → W4 validada

Prueba transaccional completa (la más exigente del sistema), ejecutada contra
TEST:

| Paso | Workflow | Resultado |
|---|---|---|
| 1 | W2 crear_prereserva | pre-reserva `id 2`, estado `pendiente_pago` |
| 2 | W3 registrar_pago | pago `id 1` sobre pre-reserva 2, estado `en_revision` |
| 3 | W4 confirmar_reserva | reserva `id 1` creada desde pre-reserva 2 (camino combinado: tomó el pago `en_revision`, lo confirmó, convirtió) |
| 4 | W1 verificación | días 10-12 jul / Bamboo en `ocupada` con `id_reserva_activa=1` y `id_prereserva_activa=null` |

El paso 4 confirma que la transición pre-reserva → reserva impacta la fuente de
verdad y el motor de disponibilidad la refleja (el cache derivado pasó de mostrar
`id_prereserva_activa` a `id_reserva_activa`).

Adicionalmente se validó el ciclo crear → cancelar (W2 id 1 → W5
`cancelada_por_cliente`) y la creación de bloqueo independiente (W6 id 1, Arrebol,
nov-2026).

---

## 11. Decisiones tomadas en 7B

- **Modelo de grants mínimo en TEST:** no paridad de grants con DEV; roles Data
  API (`anon`/`authenticated`/`service_role`) sin grants útiles; `PUBLIC` sin
  EXECUTE sobre funciones del proyecto; RLS postergado.
- **Reconstrucción desde el canónico**, no dump/restore ni copia desde DEV.
- **"Automatically expose new tables" DESTILDADO** en la creación del proyecto.
- **Workflows duplicados con sufijo `__TEST`** (Opción A), DEV intacto;
  eliminación de `id`/`versionId`/`meta` como mecanismo de no-pisado.
- **Credencial separada `vita_supabase_test`** (creada por Franco; Claude nunca
  maneja passwords).
- **Marcador de ambiente en `source_event` e `idempotency_key`** de los writes
  (persisten en tablas) para trazabilidad inequívoca TEST vs DEV.
- **Cierre con happy paths** como evidencia suficiente; casos de error a etapa
  posterior.
- **No limpiar los datos de prueba de TEST** ahora; conservarlos como
  fixtures/evidencia.

---

## 12. Hallazgos / aprendizajes

- **`current_database()` no discrimina ambiente en Supabase:** tanto DEV como
  TEST tienen la base llamada `postgres`. El chequeo de ambiente vía `db` era
  flojo; el ambiente se confirmó por convergencia (credencial al ref de TEST +
  lectura de los IDs de seed propios de TEST + IDs de secuencia arrancando en 1).
- **"TEST nació cerrado" era cierto solo para el snapshot pre-objetos:** los
  defaults de PostgreSQL/Supabase aplican `Dxtm` + `EXECUTE`-PUBLIC al *crear*
  cada objeto. Regla operativa derivada: cada función nueva en `public` deberá
  revisarse/normalizarse (REVOKE EXECUTE).
- **n8n conecta como `postgres` (owner) por pooler:** el user del pooler tiene
  forma `postgres.<ref>` pero el rol efectivo es `postgres`; ejecuta funciones por
  ownership, sin depender de `EXECUTE`. Confirmado empíricamente tras el REVOKE.
- **IDs de cabaña NO portables entre DEV y TEST:** DEV usa IDs históricos
  `17-21`; TEST usa `1-5`. Aprendizaje: nunca asumir portabilidad de IDs entre
  ambientes; cada workflow debe usar los IDs reales del entorno al que apunta.
  Lo portable es la estructura lógica de los workflows, no los valores de input.
- **El literal `"Baseline DEV 2026-2028"` en `temporadas`** quedó replicado en
  TEST con el nombre heredado del canónico. Es cosmético, no implica consulta a
  DEV; renombrarlo es opcional y no bloqueante.
- **Para contar triggers** usar `pg_trigger` con `NOT tgisinternal` (no
  `information_schema.triggers`, que multiplica por evento).
- **Pop-up "Run without RLS"** al crear tablas/triggers: respuesta correcta
  mientras RLS siga postergado.

(Lecciones previas relevantes ya cubiertas: L-6C-01 Ignore SSL en pooler;
L-6C-02 user pooler = rol postgres; L-6C-03 Query Params n8n sin NULL →
`0=todas` + NULLIF.)

---

## 13. Datos de prueba que quedan en TEST

No se limpiaron (decisión explícita). Conservados como evidencia/fixtures:

| Dato | Estado |
|---|---|
| Pre-reserva id 1 (Bamboo, 10-13 jul) | `cancelada_por_cliente` (ciclo W2→W5) |
| Pre-reserva id 2 (Bamboo, 10-13 jul) | convertida a reserva (cadena W2→W3→W4) |
| Reserva id 1 | confirmada, desde pre-reserva 2 |
| Pago id 1 | confirmado (vía camino combinado de W4) |
| Bloqueo id 1 (Arrebol, 20-22 nov) | activo, `cabana_especifica` |
| Huésped id 1 | "Juan Pérez Test" (reutilizado por idempotencia de upsert) |
| Logs / source_events | entradas con marcador de ambiente `n8n_test_w0X_...` |

Un eventual reseteo de TEST se diseñará como bloque específico de limpieza/reset
con SQL aprobado (no se improvisa).

---

## 14. Pendientes fuera de alcance de 7B

**Validación funcional ampliada (casos de error)** — a ejecutar en una etapa
posterior sobre TEST:
- cabaña inexistente;
- solapamientos;
- doble pre-reserva (idempotencia bajo colisión);
- re-confirmación de reserva ya convertida;
- cancelación de estados no cancelables;
- payloads inválidos;
- campos vacíos / whitespace;
- motivos inválidos;
- normalización defensiva (W3/W4/W5/W6);
- casos de pago tardío o inconsistente.

**Otros pendientes (fuera de 7B):**
- Endurecimiento equivalente de DEV (los grants de DEV no se tocaron; quedan más
  abiertos que TEST). Registrar en `Pendiente_pre_produccion.md`.
- Hardening SQL de `registrar_pago` (NULLIF/TRIM en campos obligatorios de texto;
  hoy la defensa está en n8n).
- Poblar `tipo_valor` en `configuracion_general` si el dashboard OPS lo requiere
  (heredado de 7A).
- Diseño de bloque de limpieza/reset de TEST si se quiere un entorno reseteado.

---

## 15. Próximo paso recomendado

Con TEST levantado y operativo, el siguiente paso natural (a decidir por Franco,
no comprometido en este cierre) es la **validación funcional ampliada**: ejecutar
sobre TEST la batería de casos de error listada en la sección 14, aprovechando
que es un entorno seguro y aislado donde los datos de prueba no tienen
consecuencias operativas.

Alternativamente, podría priorizarse el endurecimiento de DEV o el diseño del
entorno OPS, según la prioridad del negocio.

No avanzar a OPS/PROD, MercadoPago real, bot o frontend público sin decisión
explícita.

---

## 16. Aislamiento DEV / TEST (constancia)

- **DEV no se modificó durante 7B.** Las únicas operaciones contra DEV fueron
  consultas read-only aprobadas al inicio (diagnóstico de paridad estructural y
  verificación del rol de conexión de n8n).
- **TEST quedó separado por:**
  - proyecto Supabase independiente (`vita-delta-test`);
  - credencial n8n propia (`vita_supabase_test`), distinta de `vita_supabase_dev`;
  - workflows con sufijo `__TEST`, objetos nuevos en n8n (no modificaciones de
    los de DEV);
  - marcadores de ambiente en `source_event` e `idempotency_key`.

---

_Cierre formal de Etapa 7B — 2026-05-28._
