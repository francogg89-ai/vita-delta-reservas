# 8D_EJECUCION.md — Bitácora de ejecución de Etapa 8D

# Capa de bloqueos operativos (Form Trigger n8n → `crear_bloqueo`)

**Documento base de diseño:** `Docs/Arquitectura/ARQUITECTURA_ETAPA_8D_BLOQUEOS_OPERATIVOS.md v1.1`.
**Entorno de validación:** Supabase TEST (`vita-delta-test`) + n8n cloud (`federicosecchi.app.n8n.cloud`).
**Entorno de operación:** Supabase OPS (`vita-delta-ops`).
**Schema canónico:** `6B_SCHEMA_SQL.md v1.7.3` (no modificado por 8D: la función `crear_bloqueo` se usa tal cual).
**Contrato verificado:** `crear_bloqueo(payload jsonb)` — read-only contra TEST (2026-06-03).
**Documento de cierre:** `Docs/Bitacora/8D_CIERRE.md` (incluye el cierre de la Etapa 8 completa).

---

## Propósito de este documento

Registrar la ejecución de la Etapa 8D —un único workflow de formulario que crea
bloqueos— con:

- Verificación read-only del contrato real antes de construir.
- Construcción del workflow y de sus nodos Code.
- Incidencias encontradas y cómo se resolvieron.
- Resultado de validación funcional en TEST.
- Promoción y smoke en OPS.

8D cierra con validación completa en TEST y workflow `__OPS` activo y en uso real.
A diferencia de 8C (tres calendarios de solo lectura), 8D es un solo workflow que
**escribe** (vía `crear_bloqueo`), por lo que el smoke OPS es un write real.

---

## Convenciones de la bitácora

- **Estado posible:** `EN PROGRESO`, `OK`, `BLOQUEADO`, `DIFERIDO`.
- **Formato de fechas:** ISO 8601 (`YYYY-MM-DD`).
- **Validación:** ✅ / ❌ / ⏭ (no ejecutado).
- **Decisiones y lecciones reutilizables** se replican en `DECISIONES_NO_REABRIR.md`
  (D-8D-XX) y `Lecciones_Aprendidas.md` (L-8D-XX).
- **Restricción transversal:** 8D escribe SOLO vía `crear_bloqueo()` (sin INSERT directo a
  `bloqueos`); no toca schema ni la función; TEST antes de OPS.

---

## Estado general de la etapa

| Fase | Descripción | Estado | Fecha |
|---|---|---|---|
| 0 | Verificación read-only del contrato de `crear_bloqueo` (TEST) | ✅ OK | 2026-06-03 |
| 1 | Diseño aprobado (v1.1, con ajustes de Franco) | ✅ OK | 2026-06-04 |
| 2 | Construcción del workflow `__TEST` (9 nodos) | ✅ OK | 2026-06-04 |
| 3 | Validación funcional en TEST | ✅ OK | 2026-06-04 |
| 4 | Promoción a OPS + smoke (bloqueo real) | ✅ OK | 2026-06-04 |

---

## Fase 0 — Verificación read-only del contrato (TEST)

Antes de diseñar se inspeccionó, en solo lectura contra TEST, la función y la tabla:

- **`pg_get_functiondef(crear_bloqueo)`:** firma `crear_bloqueo(payload jsonb) → jsonb`;
  7 claves de payload con patrón `NULLIF(TRIM(payload->>'campo'))`; éxito
  `{ ok:true, id_bloqueo, id_cabana, tipo_bloqueo }`; 7 errores
  (`payload_invalido`, `fechas_invalidas`, `motivo_invalido`, `cabana_no_existe`,
  `conflicto_con_reserva`, `conflicto_con_prereserva`, `bloqueo_solapado`).
- **Columnas de `bloqueos`:** 10 (id_cabana/descripcion nullables; activo default true;
  created_at default now()).
- **Constraints:** CHECK `chk_bloqueos_fechas` (hasta>desde), CHECK `chk_bloqueos_motivo`
  (5 valores), FK a cabañas, PK, EXCLUDE `exc_bloqueos_no_overlap`.
- **Índices:** PK; `idx_bloqueos_activo_fechas` (parcial, performance);
  `exc_bloqueos_no_overlap` (GiST, parcial: solo `activo AND id_cabana NOT NULL`).

**Hallazgos que enmarcaron el diseño:** la función valida TODO (cabaña, fechas, motivo y
los tres conflictos) → el formulario es solo UX; un bloqueo NO convive con reservas (las
rechaza); concurrencia ya resuelta (`pg_advisory_xact_lock` global + por cabaña); triple
protección de solapamiento; el bloqueo total (`id_cabana IS NULL`) está soportado por la
función pero se decide NO exponerlo (D-8D-03). Detalle completo en `8D_CIERRE.md` §3.

---

## Fase 2 — Construcción del workflow `vita_w8d_bloqueo__TEST`

**Estado:** ✅ OK — 2026-06-04. Workflow id `GIfBlI6xCnrkH2Y4`, 9 nodos, inactivo.

### Estructura del workflow

```
Form Bloqueo (Form Trigger v2.5, Basic Auth, responseMode: lastNode, path w8d-bloqueo-test)
  → Validar y Normalizar (Code)
  → IF validacion capa (ifElse v2.2)
       ├─ true  → Build Payload (Code) → PG: crear_bloqueo (executeQuery,
       │           Continue On Fail + Always Output Data) → Normalize (Code)
       │           → Build Response (Code) → Form Ending (form completion)
       └─ false → Error Capa (Code) → Build Response → Form Ending
```

Las dos ramas del IF convergen en Build Response (validado: 9 nodos, sin duplicación de
Build Response ni Form Ending).

### Nodos Code

- **Validar y Normalizar:** mapea cabaña→id (Bamboo 1 … Tokio 5), motivo etiqueta→string
  del CHECK, operador→minúscula sin espacios; arma `source_event`
  `n8n_<TEST_OPS>_w8d_bloqueo_<operador>_manual` (constante `TEST_OPS` al inicio del nodo);
  valida capa (cabaña, fechas presentes, orden de fechas, motivo, operador).
- **Build Payload:** arma el jsonb de 7 claves + conserva `ctx` (cabana_label, fechas,
  motivo_label) para el mensaje final.
- **Normalize:** desenvuelve el resultado del nodo Postgres y arma un envelope
  (`exito` / `negocio` con familia `conflicto`|`entrada` / `tecnico`).
- **Error Capa:** mapea el error de capa a un error de entrada y arma el mismo envelope,
  para reusar Build Response.
- **Build Response:** decide título y mensaje únicos. Éxito en lenguaje humano (calcula
  `fecha_hasta − 1` solo para el texto: "último día inclusive"); conflictos unificados;
  errores de entrada diferenciados; técnico genérico.

La lógica de los nodos Code se probó con fixtures antes de crear el workflow (casos:
válido, fechas al revés, payload, éxito/conflicto/entrada/técnico en Normalize, formato de
fechas y "se libera el…" en Build Response).

### Query del nodo Postgres

```sql
SELECT crear_bloqueo('{{ JSON.stringify($json.payload) }}'::jsonb) AS resultado;
```

Nota (L-8D-02): la interpolación funciona; para texto libre con caracteres especiales la
query parametrizada (`$1::jsonb`) es más robusta. La query NO se prueba en el SQL Editor de
Supabase (las `{{ }}` son sintaxis n8n); la prueba real es ejecutar el workflow.

### Incidencias durante la construcción

- **Auto-asignación de credenciales (L-8C-01, recurrente):** al crear vía SDK, n8n asignó
  el Postgres a `vita_supabase_dev` y el Form Trigger a la Basic Auth del formulario 8B
  (`Formulario-reservas`). Corregido a mano: Postgres → `vita_supabase_test`; Form Trigger
  → Basic Auth nueva y propia de 8D (D-8D-07).

---

## Fase 3 — Validación funcional en TEST

**Estado:** ✅ OK — 2026-06-04.

### Incidencia clave resuelta (L-8D-01)

La primera ejecución mostró **"Problema técnico"** en el formulario, pero el bloqueo SÍ se
había creado en la base (el nodo `PG: crear_bloqueo` devolvía `ok: true`,
`tipo_bloqueo: cabana_especifica`, con su `id_bloqueo`). La causa: el nodo Postgres devuelve
el jsonb de la función **envuelto en la columna `resultado`** (`SELECT crear_bloqueo(...) AS
resultado`), y el nodo Normalize leía `item.ok` en vez de `item.resultado.ok`, clasificando
el éxito como error técnico.

**Corrección:** desenvolver la columna en Normalize:
`const item = raw && raw.resultado !== undefined ? raw.resultado : raw;`. Tras el fix, el
caso válido devolvió el mensaje de éxito en lenguaje humano correcto. **La base nunca
falló** en ningún intento.

### Batería funcional

| Caso | Resultado |
|---|---|
| Bloqueo válido en cabaña libre | ✅ creado; mensaje "…bloqueada desde X hasta Y inclusive. Se libera el Z" |
| `fecha_hasta <= fecha_desde` | ✅ rebote "la fecha hasta tiene que ser posterior a la desde" |
| Conflicto con otro bloqueo activo | ✅ mensaje unificado "esas fechas no están disponibles" |
| Conflicto con reserva confirmada/activa | ✅ mensaje unificado |
| Cada motivo del CHECK | ✅ persiste el string correcto |
| Mensaje de éxito en lenguaje humano | ✅ último día inclusive + día de liberación |
| Verificación `[)` | ✅ el día `fecha_hasta` aparece libre en el calendario 8C |
| Trazabilidad | ✅ `creado_por` y `source_event` correctos |

Nota operativa: las pruebas dejaron varios bloqueos de prueba en TEST (cada "Problema
técnico" igual había creado el bloqueo). Se decidió dejarlos (TEST, no molestan). Ilustra el
riesgo documentado en D-8D-09 (8D no tiene desbloqueo; corregir es manual).

---

## Fase 4 — Promoción a OPS y smoke

**Estado:** ✅ OK — 2026-06-04. Workflow `vita_w8d_bloqueo__OPS` activo y en uso real.

### Cambios aplicados al duplicar a OPS (L-8D-03)

| # | Cambio | Valor |
|---|---|---|
| 1 | Credencial Postgres | `vita_supabase_ops` |
| 2 | Marcador de entorno `TEST_OPS` (nodo Validar) | `'test'` → `'ops'` |
| 3 | Path del Form Trigger | `w8d-bloqueo-ops` |
| 4 | Basic Auth | propia de OPS |

El #2 es exclusivo de 8D (escribe): si se olvida, los registros reales quedan con
`source_event` "test". Un bloqueo OPS temprano se creó antes de cambiar el marcador y quedó
etiquetado `n8n_test_...`; se aceptó como está (un solo registro; corregirlo implicaría
escritura directa a OPS y el `log_cambios` quedaría con la etiqueta vieja igual).

### Smoke OPS

Workflow activado (Publish). Se creó un **bloqueo real** desde el formulario OPS, verificado
en el calendario operativo de OPS (aparece en gris). El smoke de 8D es un write real, por
diseño (a diferencia de los HTML de 8C, de solo lectura).

---

## Cierre de la etapa

8D quedó **validada en TEST y operativa en OPS**. Con 8D se cierra la **Etapa 8 completa**
(8A entorno + 8B reservas + 8C calendarios + 8D bloqueos): el equipo opera el complejo con
tres acciones autoservicio sobre OPS. Decisiones D-8D-01 a D-8D-09.

**Lecciones replicadas a `Lecciones_Aprendidas.md`:**
- L-8D-01 — el nodo Postgres devuelve el resultado de la función envuelto en la columna
  (`item.resultado`); desenvolver antes de leer. Un éxito leído en el nivel equivocado se
  confunde con error técnico; verificar el OUTPUT del nodo Postgres antes de concluir que
  "el motor falló".
- L-8D-02 — interpolación de JSON funciona, pero parametrizado (`$1::jsonb`) es más robusto
  ante caracteres especiales.
- L-8D-03 — al promover a OPS revisar marcadores de entorno embebidos (`TEST_OPS`), el path
  y la Basic Auth, no solo la credencial.

**Artefactos:** `vita_w8d_bloqueo__TEST` (id `GIfBlI6xCnrkH2Y4`),
`vita_w8d_bloqueo__OPS` (activo), `vita_w8d_bloqueo__TEMPLATE.json` (sanitizado),
nodos Code versionados. Documento de cierre: `8D_CIERRE.md`.

*Fin de la bitácora de ejecución de 8D.*
