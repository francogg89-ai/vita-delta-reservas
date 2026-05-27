# H8 — Snapshots Schema v1.7.2 — Working Notes

> # ⚠ DOCUMENTO AUXILIAR TEMPORAL — NO ES FUENTE DE VERDAD ⚠
>
> Esta working note acompaña el Frente A de H8 (bump documental del schema canónico a v1.7.2). **No reemplaza** `6B_SCHEMA_SQL.md`. **No compite** con `6D_CIERRE.md`. **No es canónica.**
>
> Vive durante H8. Se archiva o elimina tras cerrar Frente A + Frente B.

---

## 1. Propósito y reglas de uso

- **Propósito:** registrar snapshots, veredictos, conteos y divergencias durante el Frente A de H8, de forma independiente del contexto del chat.
- **Uso:** consulta operativa durante la sesión, referencia si se cierra/re-abre el chat, y archivo cronológico abreviado.
- **No usar para:** redactar el changelog v1.7.2 directamente (eso va en `6B_SCHEMA_SQL.md` después de aprobar). No usar como fuente para `6D_CIERRE.md` (eso es Frente B).
- **Fecha de apertura:** 2026-05-27.
- **Estado:** vivo (Frente A en curso).

---

## 2. Estado de captura de snapshots

| Snapshot | Objeto | Origen | Veredicto | Estado |
|---|---|---|---|---|
| A.1 | `registrar_pago(jsonb)` | `pg_get_functiondef` | ✅ consistente con H2, sin freno | aprobado |
| A.2 | `confirmar_reserva(jsonb)` | `pg_get_functiondef` | ✅ consistente con H3, sin freno | aprobado |
| A.3 | `crear_prereserva(jsonb)` | `pg_get_functiondef` | ✅ consistente con H4, sin freno | aprobado |
| A.4 | `cancelar_prereserva(jsonb)` | `pg_get_functiondef` | ✅ consistente con H4-bis, sin freno | aprobado |
| A.5 | `crear_bloqueo(jsonb)` | `pg_get_functiondef` | ✅ consistente con H4-ter, sin freno | aprobado |
| B.1 | `vista_ocupacion` | `pg_get_viewdef` | ✅ consistente con H5, sin freno | aprobado |
| B.2 | `vista_calendario` | `pg_get_viewdef` | ✅ consistente con H6, sin freno | aprobado |
| B.3 | `vista_limpieza_semana` | `pg_get_viewdef` | ✅ consistente con H6, sin freno | aprobado |
| B.4 | `vista_prereservas_activas` | `pg_get_viewdef` | ✅ consistente con H6-bis, sin freno | aprobado |
| C.1 | columnas de `cabanas` | `information_schema.columns` | ✅ confirma `capacidad_max` (no `capacidad_maxima`) | aprobado |
| C.2 | columnas de `bloqueos` | `information_schema.columns` | ✅ confirma `activo` BOOLEAN (no `estado` enum) | aprobado |
| C.3.a | columnas de `huespedes` | `information_schema.columns` | ✅ confirma existencia `telefono_normalizado` | aprobado |
| C.3.b | `normalizar_telefono(text)` | `pg_get_functiondef` | ✅ firma `(text)` válida, confirma manejo del `+` | aprobado |
| C.4 | columna `ninos` en `pre_reservas` y `reservas` | `information_schema.columns` | ✅ aprobado con hallazgo gestionado: ambas son TEXT, datos persistidos como `"false"` literal | aprobado |

**Adicional (no snapshot, query auxiliar):** conteo textual de ocurrencias `NULLIF(TRIM(` en las 5 funciones write — pendiente de ejecutar.

---

## 3. Conteos del patrón canónico

Tres métricas distintas, **no intercambiables**:

| Función | Métrica A: asignaciones de extract (conteo manual A.1-A.5) | Métrica B: ocurrencias textuales `NULLIF(TRIM(` (query auxiliar) | Métrica C: ocurrencias textuales `NULLIF(` (query auxiliar) |
|---|---|---|---|
| `registrar_pago` | 17 | 18 | 18 |
| `confirmar_reserva` | 6 | 7 | 7 |
| `crear_prereserva` | 18 | 20 | 22 |
| `cancelar_prereserva` | 4 | 5 | 5 |
| `crear_bloqueo` | 7 | 8 | 8 |
| **TOTAL** | **52** | **58** | **60** |

**Nota importante sobre las métricas textuales:** las métricas B y C cuentan apariciones textuales del fragmento en el cuerpo persistido por `pg_get_functiondef()`. Este cuerpo incluye comentarios además del SQL ejecutable, por lo que **las métricas textuales pueden incluir comentarios y no son equivalentes a asignaciones ejecutables**. La métrica A (conteo manual) es la única que cuenta solo asignaciones de extract a variables locales.

### Observaciones derivadas del conteo

- **B − A = 6 ocurrencias adicionales** del fragmento `NULLIF(TRIM(` fuera del extract de variable local. Incluye: validaciones inline (ej. `NULLIF(TRIM(v_huesped_payload->>'nombre'), '')` en `huesped_nombre_requerido`) y posiblemente referencias en comentarios del cuerpo persistido.
- **C − B = 2 ocurrencias** del fragmento `NULLIF(` sin `TRIM`, ambas en `crear_prereserva`: validación de contacto del huésped (`NULLIF(v_huesped_payload->>'telefono', '')` y `NULLIF(v_huesped_payload->>'email', '')`). El payload anidado `huesped` se trata como excepción del patrón principal porque su normalización vive en `upsert_huesped()`. Queda como observación interna, no como pendiente formal.

### Discrepancia con la cifra histórica "56"

`DECISIONES_NO_REABRIR.md` D-HARD-01 (línea 209), `Pendiente_pre_produccion.md` (línea 460) y `ESTADO_ACTUAL_VITA_DELTA.md` (línea 184) declaran "56 asignaciones unificadas al patrón". Las métricas observadas hoy son 52 (A), 58 (B), 60 (C). **Ninguna coincide con 56.**

Hipótesis no resuelta: el número histórico puede haber sido conteo aproximado en otro momento, métrica intermedia no identificada, o cifra distinta. **No corregir en Frente A.** Eventual corrección de redacción en `DECISIONES_NO_REABRIR.md` (sustituir cifra por redacción sin número) queda como pendiente para Frente B.

### Decisión sobre el changelog

**Camino aprobado: sin cifra.**

Redacción aprobada para el changelog v1.7.2:

> "Patrón defensivo `NULLIF(TRIM(...), '')` aplicado en los extracts de payload de las 5 funciones write críticas: `registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva` y `crear_bloqueo`."

Sin usar 52, 58, 60 ni 56. Las métricas quedan registradas en esta working note como evidencia auxiliar; no se trasladan al canónico.

---

## 4. Divergencias identificadas durante snapshots A.1-A.5

| # | Snapshot | Divergencia | Destino documental |
|---|---|---|---|
| 1 | A.1 | `registrar_pago` log explícito usa `COALESCE(v_validado_por, 'registrar_pago')` para `modificado_por`, y cast `::nivel_log_enum` para el campo `nivel`. No documentado en schema canónico v1.7.1. | changelog v1.7.2 sección b) — corrección documental |
| 2 | A.2 | `confirmar_reserva` retorna `error='estado_invalido'` con campo `estado_actual` cuando la pre-reserva está en estado terminal. Schema canónico v1.7.1 sugería `estado_no_confirmable`. | changelog v1.7.2 sección b) — corrección documental |
| 3 | A.3 | `v_ninos` declarado y usado como **BOOLEAN** en DEV. Schema canónico v1.7.1 lo declaraba TEXT. (Redacción del changelog: "El snapshot A.3 confirma que DEV real declara y usa `v_ninos` como BOOLEAN; el canónico v1.7.1 lo documentaba como TEXT.") **REVISIÓN tras C.4:** la columna `ninos` en `pre_reservas` y `reservas` es `TEXT nullable`. Hay desalineación actual de tipo entre función (BOOLEAN) y tablas (TEXT) — ver divergencia #15. | snapshot-first: reflejar DEV real en canónico v1.7.2. Cuerpo de función con `v_ninos BOOLEAN`, tablas con `ninos TEXT`. |
| 4 | A.3 | `canal_pago_esperado` extract pasó de `payload->>'canal_pago_esperado'` a `NULLIF(TRIM(payload->>'canal_pago_esperado'), '')`. Cambio del hardening. | changelog v1.7.2 sección a) — cambio por hardening |
| 5 | A.3 | `canal_pago_esperado` **no aparece** en la lista de obligatorios de la validación post-extract. Schema canónico v1.7.1 sugería que era obligatorio. | changelog v1.7.2 sección b) — corrección documental |
| 6 | A.5 | Conteo de asignaciones observado en sub-bloque A = 52, no 56 como declara D-HARD-01. Requiere validación con query textual + decisión Franco. | a evaluar — ver sección 3 |
| 7 | A.5 | `bloqueos.activo` BOOLEAN usado consistentemente en `crear_bloqueo` (filtros + INSERT `activo = TRUE`). Confirma L-6D-09 estructuralmente. Snapshot C.2 (pendiente) lo confirma a nivel `information_schema`. | Frente A — pendiente confirmación C.2; después al changelog v1.7.2 sección b) |

**Nota sobre divergencias L-6D-09 todavía no confirmadas por snapshot:**

- `cabanas.capacidad_max` (vs `capacidad_maxima` documentado) — espera C.1.
- `huespedes.telefono_normalizado` preserva `+` — espera C.3.b (cuerpo de `normalizar_telefono`).

### Divergencias adicionales identificadas durante sub-bloque B

| # | Snapshot | Divergencia | Destino documental |
|---|---|---|---|
| 8 | B.1 | Fix H5: `- '1 mon'::interval` al límite superior del `generate_series` reduce el output de 25 a 24 meses. | changelog v1.7.2 sección a) — cambio por hardening |
| 9 | B.1 | Normalizaciones del motor PostgreSQL en el cuerpo persistido: `'1 month'` → `'1 mon'`, `'12 months'` → `'1 year'`, `date_trunc('month', CURRENT_DATE)` → `date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)`. No es cambio del hardening; es normalización del motor (L-6D-02). | criterio aprobado: forma persistida en canónico + nota breve única en changelog sección b) |
| 10 | B.2 | Fix H6 aplicado: `TRIM(BOTH FROM (h.nombre \|\| ' '::text) \|\| COALESCE(h.apellido, ''::text)) AS huesped_nombre`. SELECT con 14 columnas, 2 estados filtrados (`confirmada`, `activa`), horizonte 60 días hardcoded (pendiente pre-producción separado, fuera de H8). | changelog v1.7.2 sección a) — cambio por hardening |
| 11 | B.3 | Fix H6 aplicado en 2 ocurrencias del UNION ALL: `TRIM(BOTH FROM (h.nombre \|\| ' '::text) \|\| COALESCE(h.apellido, ''::text)) AS huesped`. | changelog v1.7.2 sección a) — cambio por hardening. Redacción sugerida agrupada con B.2: "H6 normalizó la concatenación nombre + apellido en `vista_calendario` y `vista_limpieza_semana`." |
| 12 | B.4 | Fix H6-bis aplicado en 1 ocurrencia: `TRIM(BOTH FROM (h.nombre \|\| ' '::text) \|\| COALESCE(h.apellido, ''::text)) AS huesped_nombre`. | changelog v1.7.2 sección a) — cambio por hardening. Redacción final unificada con B.2 + B.3: "H6 y H6-bis normalizaron la concatenación nombre + apellido en `vista_calendario`, `vista_limpieza_semana` y `vista_prereservas_activas`." |

**Observaciones internas del sub-bloque B (no van al changelog):**

- B.3 — diferencia de estados filtrados entre las 2 partes del UNION ALL: checkout incluye `confirmada`, `activa`, `completada` (3 estados); checkin solo `confirmada`, `activa` (2 estados). Pre-hardening, estructural. Worth saber para mantenimiento futuro del cuerpo de la vista; no es divergencia documental.
- B.3 — horizonte 7 días hardcoded en ambas partes del UNION. Comportamiento vigente, fuera de alcance de H8.
- B.4 — columna calculada `minutos_para_vencer` usa `/ 60::numeric` (cast explícito al divisor) para evitar división entera. Forma persistida por PostgreSQL, adoptada según criterio. Defensiva.
- B.4 — `canal_pago_esperado` expuesto como columna. Refuerza la divergencia #5 de A.3 (campo opcional, puede ser NULL), no se registra como divergencia nueva separada.

**Resumen sub-bloque B cerrado (2026-05-27):**

| Vista | Cambio aplicado | Ocurrencias TRIM | Snapshot |
|---|---|---|---|
| `vista_ocupacion` | H5 — rango 25→24 meses (`- '1 mon'::interval`) | n/a | B.1 ✅ |
| `vista_calendario` | H6 — TRIM en concat | 1 | B.2 ✅ |
| `vista_limpieza_semana` | H6 — TRIM en concat (UNION ALL) | 2 | B.3 ✅ |
| `vista_prereservas_activas` | H6-bis — TRIM en concat | 1 | B.4 ✅ |
| **Total ocurrencias TRIM** | — | **4** | — |

Criterio uniforme aplicado: forma persistida de `pg_get_viewdef()` adoptada en canónico v1.7.2.

### Divergencias adicionales identificadas durante sub-bloque C

| # | Snapshot | Divergencia | Destino documental |
|---|---|---|---|
| 13 | C.1 | Columna real `cabanas.capacidad_max` (integer NOT NULL). Schema canónico v1.7.1 la documentaba como `capacidad_maxima`. Búsqueda global en archivo requerida al redactar v1.7.2. | changelog v1.7.2 sección b) — corrección documental |
| 14 | C.2 | Tabla `bloqueos` usa columna `activo` (boolean NOT NULL DEFAULT true), no `estado` enum. Paradigma de modelado de estado distinto al de `reservas/pre_reservas/pagos`. | changelog v1.7.2 sección b) — corrección documental. Búsqueda global durante edición: `bloqueos.estado`, `estado_bloqueo`, `trg_log_bloqueos`, `activo`. |
| 15 | C.4 | **Snapshot confirma:** `pre_reservas.ninos` y `reservas.ninos` son **TEXT nullable** en DEV. `crear_prereserva` v1.7.2 declara `v_ninos BOOLEAN` y lo INSERTA en columna TEXT → cast implícito en PostgreSQL. **Introspección de valores persistidos en DEV (3 registros) muestra el literal `"false"`** (no `'t'`/`'f'` como se había inferido inicialmente). Redacción aprobada: "El snapshot C.4 confirma una desalineación actual entre `v_ninos BOOLEAN` en `crear_prereserva` y columnas `ninos TEXT` en `pre_reservas` / `reservas`; los datos actuales muestran valores textuales como `\"false\"`." No se afirma causa histórica. | Snapshot-first: canónico v1.7.2 refleja DEV tal cual (función con BOOLEAN, tablas con TEXT). Hallazgo gestionado: item nuevo en `Pendiente_pre_produccion.md` durante Frente B con redacción liviana ("Evaluar alineación de tipo de `ninos` entre función y tablas antes de TEST/PROD"). |

**Observaciones internas del sub-bloque C (no van al changelog):**

- C.1 — tabla `cabanas` tiene 10 columnas. No tiene `updated_at` (consistente con tabla catálogo). `fotos_urls` es `text`, no array. Estos detalles quedan como observaciones, no son acciones H8.
- C.2 — `bloqueos.id_cabana` es nullable (YES). Confirma estructuralmente D-HARD-04 (NULL = bloqueo total). No es divergencia nueva.
- C.2 — `bloqueos` no tiene `updated_at`. Paradigma "se crea, se desactiva". No es pendiente ni recomendación H8.
- C.2 — verificación de enum `estado_bloqueo_enum` y trigger `trg_log_bloqueos_estado` postergada a la edición final: solo se actúa si aparecen referencias concretas y ambiguas en el canónico.
- C.3.a — `huespedes.telefono_normalizado` existe como `text` nullable. 13 columnas totales. Sin divergencia documental. **No va al changelog.**
- C.3.b — `normalizar_telefono(text)` es función `IMMUTABLE`. Preserva explícitamente el `+` inicial y convierte prefijo `00` a `+`. Comportamiento ya documentado en L-6D-09. **No va al changelog.** Función no fue modificada por H2-H6-bis. No abrir comparación completa contra el canónico salvo que durante la edición aparezca divergencia crítica evidente.
- C.4 — **desalineación actual confirmada con evidencia empírica:** función declara `v_ninos BOOLEAN`, columnas son TEXT. Introspección de los 3 registros existentes en DEV (pre-reserva 25, pre-reserva 26, reserva 8) muestra el valor `"false"` literal en la columna `ninos`. Cast implícito BOOLEAN→TEXT al INSERT está convirtiendo el `FALSE` de la variable a la representación textual `"false"`. **Corrección de inferencia previa:** no afirmamos `'t'`/`'f'` — el dato real es `"false"`.
- C.4 — **No se afirma causa histórica.** No tenemos evidencia del cuerpo pre-H4 para sostener que el hardening introdujo la desalineación. Redacción aprobada: "El snapshot C.4 confirma una desalineación actual entre `v_ninos BOOLEAN` en `crear_prereserva` y columnas `ninos TEXT` en `pre_reservas` / `reservas`; los datos actuales muestran valores textuales como `\"false\"`."
- C.4 — predicción del análisis A.3 fue equivocada (razonó que la columna debía ser BOOLEAN). Inferencia posterior sobre representación interna (`'t'`/`'f'`) también fue prematura — el dato real es `"false"`. **Aprendizaje:** no inferir representación interna sin verificar empíricamente.
- C.4 — **destino del hallazgo:** snapshot-first en canónico v1.7.2 + item nuevo liviano en `Pendiente_pre_produccion.md` durante Frente B. **No es freno del bump documental.**

---

## 5. Outputs crudos archivados

Bloques `pg_get_functiondef` capturados. Preservados aquí para evitar re-ejecución durante la redacción del archivo v1.7.2.

### A.1 — `registrar_pago(jsonb)`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
CREATE OR REPLACE FUNCTION public.registrar_pago(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id_pre_reserva     BIGINT;
  v_id_reserva         BIGINT;
  v_tipo               TEXT;
  v_medio_pago         TEXT;
  v_monto_esperado     NUMERIC(12,2);
  v_monto_recibido     NUMERIC(12,2);
  v_moneda             TEXT;
  v_es_automatico      BOOLEAN;
  v_estado_inicial     TEXT;
  v_comprobante_url    TEXT;
  v_referencia_externa TEXT;
  v_tx_hash            TEXT;
  v_validado_por       TEXT;
  v_notas              TEXT;
  v_proveedor          TEXT;
  v_cuenta_destino     TEXT;
  v_source_event       TEXT;
  v_estado_final       estado_pago_enum;
  v_id_pago            BIGINT;
  v_validado_en        TIMESTAMPTZ;
  v_prereserva_estado  estado_prereserva_enum;
  v_prereserva_no_activa BOOLEAN := FALSE;
  v_warning            TEXT;
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en numéricos y booleanos
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva     := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_id_reserva         := NULLIF(TRIM(payload->>'id_reserva'), '')::BIGINT;
  v_tipo               := NULLIF(TRIM(payload->>'tipo'), '');
  v_medio_pago         := NULLIF(TRIM(payload->>'medio_pago'), '');
  v_monto_esperado     := NULLIF(TRIM(payload->>'monto_esperado'), '')::NUMERIC(12,2);
  v_monto_recibido     := NULLIF(TRIM(payload->>'monto_recibido'), '')::NUMERIC(12,2);
  v_moneda             := COALESCE(NULLIF(TRIM(payload->>'moneda'), ''), 'ARS');
  v_es_automatico      := COALESCE(NULLIF(TRIM(payload->>'es_automatico'), '')::BOOLEAN, FALSE);
  v_estado_inicial     := NULLIF(TRIM(payload->>'estado_inicial'), '');
  v_comprobante_url    := NULLIF(TRIM(payload->>'comprobante_url'), '');
  v_referencia_externa := NULLIF(TRIM(payload->>'referencia_externa'), '');
  v_tx_hash            := NULLIF(TRIM(payload->>'tx_hash'), '');
  v_validado_por       := NULLIF(TRIM(payload->>'validado_por'), '');
  v_notas              := NULLIF(TRIM(payload->>'notas'), '');
  v_proveedor          := NULLIF(TRIM(payload->>'proveedor'), '');
  v_cuenta_destino     := NULLIF(TRIM(payload->>'cuenta_destino'), '');
  v_source_event       := NULLIF(TRIM(payload->>'source_event'), '');

  -- 1.bis Setear contexto para triggers de log (D38, v1.2)
  IF v_source_event IS NOT NULL THEN
    PERFORM set_config('app.modificado_por', 'registrar_pago', true);
    PERFORM set_config('app.source_event',   v_source_event,   true);
  END IF;

  -- 2. Validaciones
  IF v_id_pre_reserva IS NULL AND v_id_reserva IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'referencia_requerida',
                              'motivo', 'Debe venir id_pre_reserva o id_reserva');
  END IF;

  IF v_tipo IS NULL OR v_medio_pago IS NULL OR v_monto_esperado IS NULL
     OR v_monto_recibido IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- 3. Verificar pre-reserva o reserva existe + capturar estado de la pre-reserva (v1.3)
  IF v_id_pre_reserva IS NOT NULL THEN
    SELECT estado INTO v_prereserva_estado
    FROM pre_reservas
    WHERE id_pre_reserva = v_id_pre_reserva;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
    END IF;

    -- v1.3 (P2): detectar pre-reserva en estado terminal
    IF v_prereserva_estado IN (
      'vencida',
      'cancelada_por_cliente',
      'cancelada_por_bloqueo',
      'conflicto_pendiente'
    ) THEN
      v_prereserva_no_activa := TRUE;
      v_warning              := 'prereserva_no_activa';
    END IF;
  END IF;

  IF v_id_reserva IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM reservas WHERE id_reserva = v_id_reserva) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'reserva_no_existe');
    END IF;
  END IF;

  -- 4. Determinar estado del pago
  IF v_prereserva_no_activa THEN
    v_estado_final := 'en_revision';
    v_validado_en  := NULL;
  ELSIF v_estado_inicial = 'confirmado' AND v_monto_recibido = v_monto_esperado THEN
    v_estado_final := 'confirmado';
    v_validado_en  := NOW();
    IF v_validado_por IS NULL THEN
      v_validado_por := 'sistema_auto';
    END IF;
  ELSE
    v_estado_final := 'en_revision';
    v_validado_en  := NULL;
  END IF;

  -- 5. INSERT
  INSERT INTO pagos (
    id_prereserva, id_reserva, tipo, medio_pago, proveedor, cuenta_destino,
    monto_esperado, monto_recibido, moneda, estado, es_automatico,
    comprobante_url, referencia_externa, tx_hash,
    validado_por, validado_en, notas, source_event
  ) VALUES (
    v_id_pre_reserva, v_id_reserva, v_tipo, v_medio_pago, v_proveedor, v_cuenta_destino,
    v_monto_esperado, v_monto_recibido, v_moneda, v_estado_final, v_es_automatico,
    v_comprobante_url, v_referencia_externa, v_tx_hash,
    v_validado_por, v_validado_en, v_notas, v_source_event
  )
  RETURNING id_pago INTO v_id_pago;

  -- 6. Promover pre-reserva de pendiente_pago → pago_en_revision SOLO si está activa
  IF v_id_pre_reserva IS NOT NULL AND NOT v_prereserva_no_activa THEN
    UPDATE pre_reservas
    SET estado = 'pago_en_revision', updated_at = NOW()
    WHERE id_pre_reserva = v_id_pre_reserva
      AND estado = 'pendiente_pago';
  END IF;

  -- 7. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pagos', v_id_pago::TEXT, COALESCE(v_validado_por, 'registrar_pago'),
    v_source_event,
    CASE WHEN v_prereserva_no_activa THEN 'warning'::nivel_log_enum ELSE 'info'::nivel_log_enum END,
    jsonb_build_object(
      'evento',             'pago_registrado',
      'id_pago',            v_id_pago,
      'id_pre_reserva',     v_id_pre_reserva,
      'id_reserva',         v_id_reserva,
      'tipo',               v_tipo,
      'medio_pago',         v_medio_pago,
      'monto_esperado',     v_monto_esperado,
      'monto_recibido',     v_monto_recibido,
      'estado',             v_estado_final::TEXT,
      'es_automatico',      v_es_automatico,
      'warning',            v_warning,
      'prereserva_estado',  CASE WHEN v_prereserva_no_activa
                                 THEN v_prereserva_estado::TEXT
                                 ELSE NULL END
    )
  );

  -- 8. Retorno
  IF v_prereserva_no_activa THEN
    RETURN jsonb_build_object(
      'ok',                 true,
      'id_pago',            v_id_pago,
      'estado',             v_estado_final::TEXT,
      'warning',            'prereserva_no_activa',
      'prereserva_estado',  v_prereserva_estado::TEXT
    );
  ELSE
    RETURN jsonb_build_object(
      'ok',      true,
      'id_pago', v_id_pago,
      'estado',  v_estado_final::TEXT
    );
  END IF;
END;
$function$
```

</details>

### A.2 — `confirmar_reserva(jsonb)`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
CREATE OR REPLACE FUNCTION public.confirmar_reserva(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id_pre_reserva              BIGINT;
  v_permitir_pago_en_revision   BOOLEAN;
  v_validado_por                TEXT;
  v_encargado_semana            TEXT;
  v_created_by                  TEXT;
  v_source_event                TEXT;
  v_pre                         pre_reservas%ROWTYPE;
  v_pago                        pagos%ROWTYPE;
  v_id_pago_a_confirmar         BIGINT;
  v_disponibilidad              JSONB;
  v_id_reserva                  BIGINT;
  v_huesped                     huespedes%ROWTYPE;
BEGIN
  -- ─── 1. Extraer payload (v1.7.2 — extract defensivo unificado) ──
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT y BOOLEAN
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva            := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_permitir_pago_en_revision := COALESCE(NULLIF(TRIM(payload->>'permitir_pago_en_revision'), '')::BOOLEAN, FALSE);
  v_validado_por              := NULLIF(TRIM(payload->>'validado_por'), '');
  v_encargado_semana          := NULLIF(TRIM(payload->>'encargado_semana'), '');
  v_created_by                := NULLIF(TRIM(payload->>'created_by'), '');
  v_source_event              := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_id_pre_reserva IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log (D38, v1.2) ──
  PERFORM set_config('app.modificado_por', 'confirmar_reserva', true);
  PERFORM set_config('app.source_event',   v_source_event,      true);

  -- ─── 1.ter Lock GLOBAL de disponibilidad (v1.5) ──
  -- INVARIANTE DE LOCKS: tomar SIEMPRE primero el lock global antes de cualquier otro.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- ─── 2. Bloquear y leer pre-reserva (row lock, después del global) ──
  SELECT * INTO v_pre FROM pre_reservas
  WHERE id_pre_reserva = v_id_pre_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
  END IF;

  IF v_pre.estado NOT IN ('pendiente_pago', 'pago_en_revision') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_invalido',
                              'estado_actual', v_pre.estado::TEXT);
  END IF;

  -- ─── 3. Lock por cabaña (con cast a INTEGER — corrección v1.6) ──
  -- NOTA TÉCNICA (v1.6): cast explícito a INTEGER. PostgreSQL no provee
  -- pg_advisory_xact_lock(integer, bigint). Ver Sección 15 del documento.
  PERFORM pg_advisory_xact_lock(1, v_pre.id_cabana::INTEGER);

  -- ─── 4. Verificar pago asociado ────────────────────────
  -- Camino estricto: requiere al menos un pago 'confirmado'
  SELECT * INTO v_pago FROM pagos
  WHERE id_prereserva = v_id_pre_reserva
    AND estado = 'confirmado'
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Sin pago confirmado, ¿podemos usar camino combinado?
    IF v_permitir_pago_en_revision AND v_validado_por IS NOT NULL THEN
      SELECT * INTO v_pago FROM pagos
      WHERE id_prereserva = v_id_pre_reserva
        AND estado = 'en_revision'
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE;

      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'error', 'sin_pago_asociado');
      END IF;

      v_id_pago_a_confirmar := v_pago.id_pago;
    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'sin_pago_confirmado',
                                'motivo', 'No hay pago confirmado y no se permitió usar pago en revisión');
    END IF;
  END IF;

  -- ─── 5. Revalidar disponibilidad excluyendo esta pre-reserva ──
  v_disponibilidad := validar_disponibilidad(
    v_pre.id_cabana, v_pre.fecha_in, v_pre.fecha_out, v_id_pre_reserva
  );

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    -- Conflicto detectado al confirmar — alguien metió bloqueo o reserva
    UPDATE pre_reservas SET estado = 'conflicto_pendiente', updated_at = NOW()
    WHERE id_pre_reserva = v_id_pre_reserva;

    RETURN jsonb_build_object('ok', false, 'error', 'conflicto_al_confirmar',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 6. INSERT en reservas (con captura defensiva de EXCLUDE) ──
  BEGIN
    INSERT INTO reservas (
      id_pre_reserva, id_cabana, id_huesped,
      fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
      personas, estado, canal_origen,
      monto_total, monto_sena, monto_saldo,
      encargado_semana, created_by, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva
    ) VALUES (
      v_id_pre_reserva, v_pre.id_cabana, v_pre.id_huesped,
      v_pre.fecha_in, v_pre.fecha_out, v_pre.hora_checkin, v_pre.hora_checkout,
      v_pre.personas, 'confirmada', v_pre.canal_origen,
      v_pre.monto_total, v_pre.monto_sena, (v_pre.monto_total - v_pre.monto_sena),
      v_encargado_semana, v_created_by, v_source_event,
      v_pre.mascotas, v_pre.detalle_mascotas, v_pre.ninos, v_pre.notas_reserva
    )
    RETURNING id_reserva INTO v_id_reserva;

  EXCEPTION
    WHEN exclusion_violation THEN
      -- Defensivo: no debería pasar por la revalidación + lock, pero por las dudas
      RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                                'motivo', 'EXCLUDE constraint detectó conflicto');
  END;

  -- ─── 7. Marcar pre-reserva como convertida ────────────
  UPDATE pre_reservas
  SET estado = 'convertida', updated_at = NOW()
  WHERE id_pre_reserva = v_id_pre_reserva;

  -- ─── 8. Asociar pago con la nueva reserva ────────────
  UPDATE pagos
  SET id_reserva = v_id_reserva,
      updated_at = NOW()
  WHERE id_prereserva = v_id_pre_reserva;

  -- ─── 9. Si camino combinado: confirmar el pago en_revision ───
  IF v_id_pago_a_confirmar IS NOT NULL THEN
    UPDATE pagos
    SET estado       = 'confirmado',
        validado_por = v_validado_por,
        validado_en  = NOW(),
        updated_at   = NOW()
    WHERE id_pago = v_id_pago_a_confirmar;
  END IF;

  -- ─── 10. Actualizar huésped: total_reservas y primera_reserva_fecha ──
  UPDATE huespedes
  SET total_reservas        = total_reservas + 1,
      primera_reserva_fecha = COALESCE(primera_reserva_fecha, v_pre.fecha_in),
      updated_at            = NOW()
  WHERE id_huesped = v_pre.id_huesped;

  -- ─── 11. Log de creación ────────────────────────────
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'reservas',
    v_id_reserva::TEXT,
    'confirmar_reserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',         'reserva_confirmada',
      'id_reserva',     v_id_reserva,
      'id_pre_reserva', v_id_pre_reserva,
      'id_huesped',     v_pre.id_huesped,
      'id_cabana',      v_pre.id_cabana,
      'camino',         CASE WHEN v_id_pago_a_confirmar IS NOT NULL THEN 'combinado' ELSE 'estricto' END
    )
  );

  RETURN jsonb_build_object(
    'ok',             true,
    'id_reserva',     v_id_reserva,
    'id_pre_reserva', v_id_pre_reserva,
    'id_huesped',     v_pre.id_huesped
  );
END;
$function$
```

</details>

### A.3 — `crear_prereserva(jsonb)`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
CREATE OR REPLACE FUNCTION public.crear_prereserva(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_huesped_payload      JSONB;
  v_id_consulta          BIGINT;
  v_id_cabana            BIGINT;
  v_fecha_in             DATE;
  v_fecha_out            DATE;
  v_personas             INTEGER;
  v_monto_total          NUMERIC(12,2);
  v_monto_sena           NUMERIC(12,2);
  v_canal_origen         TEXT;
  v_canal_pago_esperado  TEXT;
  v_source_event         TEXT;
  v_idempotency_key      TEXT;
  v_notas                TEXT;
  v_mascotas             BOOLEAN;
  v_detalle_mascotas     TEXT;
  v_ninos                BOOLEAN;
  v_notas_reserva        TEXT;
  v_hora_checkin_sol     TIME;
  v_hora_checkout_sol    TIME;
  v_hora_checkin_final   TIME;
  v_hora_checkout_final  TIME;
  v_hora_checkin_min     TIME;
  v_hora_checkin_max     TIME;
  v_hora_checkout_min    TIME;
  v_hora_checkout_max    TIME;
  v_expiracion_minutos   INTEGER;
  v_expira_en            TIMESTAMPTZ;
  v_estado_inicial       estado_prereserva_enum;
  v_id_huesped           BIGINT;
  v_id_pre_reserva       BIGINT;
  v_config               JSONB;
  v_claves_faltantes     TEXT[];
  v_cabana               cabanas%ROWTYPE;
  v_disponibilidad       JSONB;
  v_existente            pre_reservas%ROWTYPE;
  v_upsert_result        JSONB;
BEGIN
  -- ─── 1. Extraer payload y validar ──────────────────────
  -- (v1.7.2) Extract defensivo unificado: todos los campos derivados de
  -- payload->>'...' pasan por NULLIF(TRIM(...),'') antes del cast. Excepción:
  -- v_huesped_payload usa payload->'huesped' (operador JSONB, no texto), no
  -- aplica patrón. La normalización interna del huésped vive en upsert_huesped().
  v_huesped_payload     := payload->'huesped';
  v_id_consulta         := NULLIF(TRIM(payload->>'id_consulta'), '')::BIGINT;
  v_id_cabana           := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_in            := NULLIF(TRIM(payload->>'fecha_in'), '')::DATE;
  v_fecha_out           := NULLIF(TRIM(payload->>'fecha_out'), '')::DATE;
  v_personas            := NULLIF(TRIM(payload->>'personas'), '')::INTEGER;
  v_monto_total         := NULLIF(TRIM(payload->>'monto_total'), '')::NUMERIC(12,2);
  v_monto_sena          := NULLIF(TRIM(payload->>'monto_sena'), '')::NUMERIC(12,2);
  v_canal_origen        := NULLIF(TRIM(payload->>'canal_origen'), '');
  v_canal_pago_esperado := NULLIF(TRIM(payload->>'canal_pago_esperado'), '');
  v_source_event        := NULLIF(TRIM(payload->>'source_event'), '');
  v_idempotency_key     := NULLIF(TRIM(payload->>'idempotency_key'), '');
  v_notas               := NULLIF(TRIM(payload->>'notas'), '');
  v_mascotas            := COALESCE(NULLIF(TRIM(payload->>'mascotas'), '')::BOOLEAN, FALSE);
  v_detalle_mascotas    := NULLIF(TRIM(payload->>'detalle_mascotas'), '');
  v_ninos               := COALESCE(NULLIF(TRIM(payload->>'ninos'), '')::BOOLEAN, FALSE);
  v_notas_reserva       := NULLIF(TRIM(payload->>'notas_reserva'), '');
  v_hora_checkin_sol    := NULLIF(TRIM(payload->>'hora_checkin_solicitada'), '')::TIME;
  v_hora_checkout_sol   := NULLIF(TRIM(payload->>'hora_checkout_solicitada'), '')::TIME;

  IF v_id_cabana IS NULL OR v_fecha_in IS NULL OR v_fecha_out IS NULL
     OR v_personas IS NULL OR v_canal_origen IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_monto_total IS NULL OR v_monto_sena IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'precio_requerido',
                              'motivo', 'monto_total y monto_sena son obligatorios');
  END IF;

  IF v_fecha_out <= v_fecha_in THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF v_huesped_payload IS NULL OR NULLIF(TRIM(v_huesped_payload->>'nombre'), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_nombre_requerido',
                              'motivo', 'El payload del huésped debe traer un nombre no vacío.');
  END IF;

  IF NULLIF(v_huesped_payload->>'telefono', '') IS NULL
     AND NULLIF(v_huesped_payload->>'email', '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'huesped_contacto_requerido',
                              'motivo', 'El payload del huésped debe traer al menos telefono o email.');
  END IF;

  -- ─── 1.bis Setear contexto para triggers de log ──
  PERFORM set_config('app.modificado_por', 'crear_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,    true);

  -- ─── 2. Leer configuración relevante ───────────────────
  SELECT jsonb_object_agg(clave, valor)
  INTO v_config
  FROM configuracion_general
  WHERE clave IN (
    'hora_checkin_default', 'hora_checkin_domingo',
    'hora_checkin_max_cliente', 'hora_checkout_min_cliente',
    'hora_checkout_default', 'hora_checkout_domingo',
    'prereserva_expiracion_minutos'
  );

  v_expiracion_minutos := COALESCE((v_config->>'prereserva_expiracion_minutos')::INTEGER, 60);

  v_claves_faltantes := ARRAY[]::TEXT[];
  IF v_config->>'hora_checkin_default'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_default'); END IF;
  IF v_config->>'hora_checkin_domingo'         IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_domingo'); END IF;
  IF v_config->>'hora_checkin_max_cliente'     IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkin_max_cliente'); END IF;
  IF v_config->>'hora_checkout_min_cliente'    IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_min_cliente'); END IF;
  IF v_config->>'hora_checkout_default'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_default'); END IF;
  IF v_config->>'hora_checkout_domingo'        IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'hora_checkout_domingo'); END IF;
  IF v_config->>'prereserva_expiracion_minutos' IS NULL THEN v_claves_faltantes := array_append(v_claves_faltantes, 'prereserva_expiracion_minutos'); END IF;

  -- ─── 3. Pre-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'pre_lock'
      );
    END IF;
  END IF;

  -- ─── 4. Resolver huésped ──────
  v_upsert_result := upsert_huesped(v_huesped_payload);
  IF NOT (v_upsert_result->>'ok')::BOOLEAN THEN
    RETURN v_upsert_result;
  END IF;
  v_id_huesped := (v_upsert_result->>'id_huesped')::BIGINT;

  -- ─── 5. Locks ──
  PERFORM pg_advisory_xact_lock(10, 0);
  PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

  -- ─── 5.bis Double-check idempotencia ──
  IF v_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existente
    FROM pre_reservas
    WHERE idempotency_key = v_idempotency_key
      AND estado IN ('pendiente_pago', 'pago_en_revision')
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'ok',               true,
        'idempotent_match', true,
        'id_pre_reserva',   v_existente.id_pre_reserva,
        'id_huesped',       v_existente.id_huesped,
        'estado',           v_existente.estado::TEXT,
        'expira_en',        v_existente.expira_en,
        'recovery_path',    'post_lock'
      );
    END IF;
  END IF;

  -- ─── 6. Validar cabaña ──
  SELECT * INTO v_cabana FROM cabanas WHERE id_cabana = v_id_cabana;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
  END IF;

  IF NOT v_cabana.activa THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cabana_inactiva');
  END IF;

  IF v_personas > v_cabana.capacidad_max THEN
    RETURN jsonb_build_object('ok', false, 'error', 'excede_capacidad',
                              'capacidad_max', v_cabana.capacidad_max);
  END IF;

  -- ─── 7. Validar disponibilidad ──
  v_disponibilidad := validar_disponibilidad(v_id_cabana, v_fecha_in, v_fecha_out, NULL);

  IF NOT (v_disponibilidad->>'ok')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', v_disponibilidad->>'error');
  END IF;

  IF NOT (v_disponibilidad->>'disponible')::BOOLEAN THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_disponible',
                              'conflictos', v_disponibilidad->'conflictos');
  END IF;

  -- ─── 8. Calcular horarios finales (v1.7) ──
  v_hora_checkin_min := CASE
    WHEN EXTRACT(DOW FROM v_fecha_in) = 0
      THEN COALESCE((v_config->>'hora_checkin_domingo')::TIME, TIME '18:00')
    ELSE
      COALESCE((v_config->>'hora_checkin_default')::TIME, TIME '13:00')
  END;
  v_hora_checkin_max := COALESCE((v_config->>'hora_checkin_max_cliente')::TIME, TIME '22:00');

  v_hora_checkout_min := COALESCE((v_config->>'hora_checkout_min_cliente')::TIME, TIME '07:00');

  v_hora_checkout_max := CASE
    WHEN EXTRACT(DOW FROM v_fecha_out) = 0
      THEN COALESCE((v_config->>'hora_checkout_domingo')::TIME, TIME '16:00')
    ELSE
      COALESCE((v_config->>'hora_checkout_default')::TIME, TIME '10:00')
  END;

  IF v_hora_checkin_sol IS NULL THEN
    v_hora_checkin_final := v_hora_checkin_min;
  ELSE
    IF v_hora_checkin_sol < v_hora_checkin_min OR v_hora_checkin_sol > v_hora_checkin_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkin',
        'minimo', v_hora_checkin_min, 'maximo', v_hora_checkin_max
      );
    END IF;
    v_hora_checkin_final := v_hora_checkin_sol;
  END IF;

  IF v_hora_checkout_sol IS NULL THEN
    v_hora_checkout_final := v_hora_checkout_max;
  ELSE
    IF v_hora_checkout_sol < v_hora_checkout_min OR v_hora_checkout_sol > v_hora_checkout_max THEN
      RETURN jsonb_build_object(
        'ok', false, 'error', 'hora_fuera_de_rango',
        'campo', 'hora_checkout',
        'minimo', v_hora_checkout_min, 'maximo', v_hora_checkout_max
      );
    END IF;
    v_hora_checkout_final := v_hora_checkout_sol;
  END IF;

  v_expira_en := NOW() + (v_expiracion_minutos || ' minutes')::INTERVAL;
  v_estado_inicial := 'pendiente_pago';

  -- ─── 9. INSERT con manejo defensivo ──
  BEGIN
    INSERT INTO pre_reservas (
      id_consulta, id_cabana, id_huesped,
      fecha_in, fecha_out, hora_checkin, hora_checkout,
      personas, monto_total, monto_sena, estado, expira_en,
      canal_pago_esperado, canal_origen, intentos_pago,
      notas, source_event,
      mascotas, detalle_mascotas, ninos, notas_reserva,
      idempotency_key
    ) VALUES (
      v_id_consulta, v_id_cabana, v_id_huesped,
      v_fecha_in, v_fecha_out, v_hora_checkin_final, v_hora_checkout_final,
      v_personas, v_monto_total, v_monto_sena, v_estado_inicial, v_expira_en,
      v_canal_pago_esperado, v_canal_origen, 0,
      v_notas, v_source_event,
      v_mascotas, v_detalle_mascotas, v_ninos, v_notas_reserva,
      v_idempotency_key
    )
    RETURNING id_pre_reserva INTO v_id_pre_reserva;

  EXCEPTION
    WHEN unique_violation THEN
      IF v_idempotency_key IS NOT NULL THEN
        SELECT * INTO v_existente
        FROM pre_reservas
        WHERE idempotency_key = v_idempotency_key
          AND estado IN ('pendiente_pago', 'pago_en_revision')
        LIMIT 1;

        IF FOUND THEN
          RETURN jsonb_build_object(
            'ok',               true,
            'idempotent_match', true,
            'id_pre_reserva',   v_existente.id_pre_reserva,
            'id_huesped',       v_existente.id_huesped,
            'estado',           v_existente.estado::TEXT,
            'expira_en',        v_existente.expira_en,
            'recovery_path',    'unique_violation'
          );
        END IF;
      END IF;

      RETURN jsonb_build_object('ok', false, 'error', 'unique_violation_inesperado');
  END;

  -- ─── 10. Log de creación ──
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas',
    v_id_pre_reserva::TEXT,
    'crear_prereserva',
    v_source_event,
    'info',
    jsonb_build_object(
      'evento',       'prereserva_creada',
      'id_cabana',    v_id_cabana,
      'id_huesped',   v_id_huesped,
      'fecha_in',     v_fecha_in,
      'fecha_out',    v_fecha_out,
      'monto_total',  v_monto_total,
      'monto_sena',   v_monto_sena,
      'canal_origen', v_canal_origen
    )
  );

  -- ─── 11. Warning de config faltante ──
  IF cardinality(v_claves_faltantes) > 0 THEN
    INSERT INTO log_cambios (
      tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
    ) VALUES (
      'configuracion_general',
      'sistema',
      'crear_prereserva',
      v_source_event,
      'warning',
      jsonb_build_object(
        'evento',           'claves_config_faltantes',
        'claves_faltantes', v_claves_faltantes,
        'motivo',           'crear_prereserva usó valores default para estas claves'
      )
    );
  END IF;

  -- ─── 12. Retorno exitoso ──
  RETURN jsonb_build_object(
    'ok',               true,
    'idempotent_match', false,
    'id_pre_reserva',   v_id_pre_reserva,
    'id_huesped',       v_id_huesped,
    'estado',           v_estado_inicial::TEXT,
    'expira_en',        v_expira_en,
    'hora_checkin',     v_hora_checkin_final,
    'hora_checkout',    v_hora_checkout_final,
    'recovery_path',    NULL
  );
END;
$function$
```

</details>

### A.4 — `cancelar_prereserva(jsonb)`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
CREATE OR REPLACE FUNCTION public.cancelar_prereserva(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id_pre_reserva     BIGINT;
  v_motivo             TEXT;
  v_descripcion        TEXT;
  v_source_event       TEXT;
  v_pre                pre_reservas%ROWTYPE;
  v_estado_nuevo       estado_prereserva_enum;
  v_estado_anterior    estado_prereserva_enum;
  v_pagos_count        INTEGER;
  v_pagos_ids          BIGINT[];
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  v_id_pre_reserva := NULLIF(TRIM(payload->>'id_pre_reserva'), '')::BIGINT;
  v_motivo         := NULLIF(TRIM(payload->>'motivo'), '');
  v_descripcion    := NULLIF(TRIM(payload->>'descripcion'), '');
  v_source_event   := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_id_pre_reserva IS NULL OR v_motivo IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  -- 1.bis Setear contexto para triggers de log (D38, v1.2)
  PERFORM set_config('app.modificado_por', 'cancelar_prereserva', true);
  PERFORM set_config('app.source_event',   v_source_event,        true);

  -- 1.ter Lock global de disponibilidad (D46, v1.4, Q1)
  -- Esta función NO toma lock por cabaña porque solo libera disponibilidad.
  PERFORM pg_advisory_xact_lock(10, 0);

  -- 2. Mapear motivo a estado
  CASE v_motivo
    WHEN 'cliente' THEN v_estado_nuevo := 'cancelada_por_cliente';
    WHEN 'bloqueo' THEN v_estado_nuevo := 'cancelada_por_bloqueo';
    ELSE
      RETURN jsonb_build_object('ok', false, 'error', 'motivo_invalido',
                                'motivos_validos', jsonb_build_array('cliente', 'bloqueo'));
  END CASE;

  -- 3. Bloquear pre-reserva
  SELECT * INTO v_pre FROM pre_reservas
  WHERE id_pre_reserva = v_id_pre_reserva
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'prereserva_no_existe');
  END IF;

  IF v_pre.estado NOT IN ('pendiente_pago', 'pago_en_revision') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estado_no_cancelable',
                              'estado_actual', v_pre.estado::TEXT);
  END IF;

  v_estado_anterior := v_pre.estado;

  -- 4. Cancelar
  UPDATE pre_reservas
  SET estado = v_estado_nuevo, updated_at = NOW()
  WHERE id_pre_reserva = v_id_pre_reserva;

  -- 5. Contar pagos asociados (NO tocarlos)
  SELECT COUNT(*), COALESCE(array_agg(id_pago), ARRAY[]::BIGINT[])
  INTO v_pagos_count, v_pagos_ids
  FROM pagos
  WHERE id_prereserva = v_id_pre_reserva;

  -- 6. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'pre_reservas', v_id_pre_reserva::TEXT, 'cancelar_prereserva',
    v_source_event, 'info',
    jsonb_build_object(
      'evento',           'prereserva_cancelada',
      'id_pre_reserva',   v_id_pre_reserva,
      'estado_anterior',  v_estado_anterior::TEXT,
      'estado_nuevo',     v_estado_nuevo::TEXT,
      'motivo',           v_motivo,
      'descripcion',      v_descripcion,
      'pagos_asociados',  v_pagos_count
    )
  );

  RETURN jsonb_build_object(
    'ok',                    true,
    'id_pre_reserva',        v_id_pre_reserva,
    'estado_anterior',       v_estado_anterior::TEXT,
    'estado_nuevo',          v_estado_nuevo::TEXT,
    'pagos_asociados_count', v_pagos_count,
    'pagos_asociados_ids',   to_jsonb(v_pagos_ids)
  );
END;
$function$
```

</details>

### A.5 — `crear_bloqueo(jsonb)`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
CREATE OR REPLACE FUNCTION public.crear_bloqueo(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id_cabana            BIGINT;
  v_fecha_desde          DATE;
  v_fecha_hasta          DATE;
  v_motivo               TEXT;
  v_descripcion          TEXT;
  v_creado_por           TEXT;
  v_source_event         TEXT;
  v_id_bloqueo           BIGINT;
  v_reservas_ids         BIGINT[];
  v_prereservas_ids      BIGINT[];
  v_bloqueos_ids         BIGINT[];
BEGIN
  -- 1. Extraer payload (v1.7.2 — extract defensivo unificado)
  -- Todos los campos derivados de payload->>'...' pasan por
  -- NULLIF(TRIM(...),'') antes del cast. Esto:
  --   - normaliza "" y whitespace puro ("   ") a NULL real
  --   - evita errores crudos de cast en BIGINT y DATE
  --   - mantiene el contrato: las validaciones siguen rebotando con
  --     payload_invalido cuando un obligatorio queda NULL.
  --
  -- Caso especial v_id_cabana: null significa "bloqueo total" (válido).
  -- Tanto null como "" como "   " se interpretan como bloqueo total.
  v_id_cabana    := NULLIF(TRIM(payload->>'id_cabana'), '')::BIGINT;
  v_fecha_desde  := NULLIF(TRIM(payload->>'fecha_desde'), '')::DATE;
  v_fecha_hasta  := NULLIF(TRIM(payload->>'fecha_hasta'), '')::DATE;
  v_motivo       := NULLIF(TRIM(payload->>'motivo'), '');
  v_descripcion  := NULLIF(TRIM(payload->>'descripcion'), '');
  v_creado_por   := NULLIF(TRIM(payload->>'creado_por'), '');
  v_source_event := NULLIF(TRIM(payload->>'source_event'), '');

  IF v_fecha_desde IS NULL OR v_fecha_hasta IS NULL
     OR v_motivo IS NULL OR v_creado_por IS NULL OR v_source_event IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'payload_invalido');
  END IF;

  IF v_fecha_hasta <= v_fecha_desde THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fechas_invalidas');
  END IF;

  IF v_motivo NOT IN ('mantenimiento', 'uso_propio', 'tormenta', 'overbooking', 'otro') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'motivo_invalido');
  END IF;

  -- 2. Locks (INVARIANTE DE LOCKS v1.5: SIEMPRE primero el global)
  PERFORM pg_advisory_xact_lock(10, 0);

  IF v_id_cabana IS NOT NULL THEN
    -- Bloqueo específico: tomar también lock por cabaña con cast a INTEGER (v1.6)
    PERFORM pg_advisory_xact_lock(1, v_id_cabana::INTEGER);

    -- Verificar cabaña existe
    IF NOT EXISTS (SELECT 1 FROM cabanas WHERE id_cabana = v_id_cabana) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'cabana_no_existe');
    END IF;

    -- 3.A.1 Verificar conflicto con reservas confirmadas/activas en esta cabaña
    SELECT COALESCE(array_agg(id_reserva), ARRAY[]::BIGINT[])
    INTO v_reservas_ids
    FROM reservas
    WHERE id_cabana = v_id_cabana
      AND estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_reservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'conflicto_con_reserva',
        'reservas_en_conflicto', to_jsonb(v_reservas_ids)
      );
    END IF;

    -- 3.A.2 Verificar conflicto con pre-reservas vigentes en esta cabaña
    SELECT COALESCE(array_agg(id_pre_reserva), ARRAY[]::BIGINT[])
    INTO v_prereservas_ids
    FROM pre_reservas
    WHERE id_cabana = v_id_cabana
      AND (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_prereservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                       false,
        'error',                    'conflicto_con_prereserva',
        'prereservas_en_conflicto', to_jsonb(v_prereservas_ids),
        'motivo',                   'Hay pre-reservas vigentes en el rango. Cancelarlas antes de bloquear.'
      );
    END IF;

    -- 3.A.3 Verificar bloqueos solapados (específico vs específico o específico vs total)
    SELECT COALESCE(array_agg(id_bloqueo), ARRAY[]::BIGINT[])
    INTO v_bloqueos_ids
    FROM bloqueos
    WHERE activo = TRUE
      AND (id_cabana = v_id_cabana OR id_cabana IS NULL)
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_bloqueos_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'bloqueo_solapado',
        'bloqueos_en_conflicto', to_jsonb(v_bloqueos_ids),
        'motivo',                'Ya hay un bloqueo activo (específico o total) en el rango'
      );
    END IF;

  ELSE
    -- Bloqueo total (id_cabana IS NULL)
    -- 3.B.1 Verificar conflicto con reservas en cualquier cabaña
    SELECT COALESCE(array_agg(id_reserva), ARRAY[]::BIGINT[])
    INTO v_reservas_ids
    FROM reservas
    WHERE estado IN ('confirmada', 'activa')
      AND daterange(fecha_checkin, fecha_checkout, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_reservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'conflicto_con_reserva',
        'motivo',                'Hay reservas confirmadas en el rango. Resolver antes de bloquear el complejo.',
        'reservas_en_conflicto', to_jsonb(v_reservas_ids)
      );
    END IF;

    -- 3.B.2 Verificar conflicto con pre-reservas vigentes en cualquier cabaña
    SELECT COALESCE(array_agg(id_pre_reserva), ARRAY[]::BIGINT[])
    INTO v_prereservas_ids
    FROM pre_reservas
    WHERE (
        (estado = 'pendiente_pago' AND expira_en > NOW())
        OR estado = 'pago_en_revision'
      )
      AND daterange(fecha_in, fecha_out, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_prereservas_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                       false,
        'error',                    'conflicto_con_prereserva',
        'prereservas_en_conflicto', to_jsonb(v_prereservas_ids),
        'motivo',                   'Hay pre-reservas vigentes en el rango. Cancelarlas antes de bloquear el complejo.'
      );
    END IF;

    -- 3.B.3 Verificar bloqueos solapados (total vs total o total vs específico existente)
    SELECT COALESCE(array_agg(id_bloqueo), ARRAY[]::BIGINT[])
    INTO v_bloqueos_ids
    FROM bloqueos
    WHERE activo = TRUE
      AND daterange(fecha_desde, fecha_hasta, '[)')
          && daterange(v_fecha_desde, v_fecha_hasta, '[)');

    IF cardinality(v_bloqueos_ids) > 0 THEN
      RETURN jsonb_build_object(
        'ok',                    false,
        'error',                 'bloqueo_solapado',
        'bloqueos_en_conflicto', to_jsonb(v_bloqueos_ids),
        'motivo',                'Ya hay bloqueos activos en el rango (totales o específicos)'
      );
    END IF;
  END IF;

  -- 4. INSERT con captura defensiva de exclusion_violation
  BEGIN
    INSERT INTO bloqueos (
      id_cabana, fecha_desde, fecha_hasta, motivo, descripcion,
      creado_por, activo, source_event
    ) VALUES (
      v_id_cabana, v_fecha_desde, v_fecha_hasta, v_motivo, v_descripcion,
      v_creado_por, TRUE, v_source_event
    )
    RETURNING id_bloqueo INTO v_id_bloqueo;

  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('ok', false, 'error', 'bloqueo_solapado',
                                'motivo', 'EXCLUDE detectó conflicto residual');
  END;

  -- 5. Log
  INSERT INTO log_cambios (
    tabla_afectada, id_registro, modificado_por, source_event, nivel, detalle
  ) VALUES (
    'bloqueos', v_id_bloqueo::TEXT, v_creado_por, v_source_event, 'info',
    jsonb_build_object(
      'evento',       'bloqueo_creado',
      'id_bloqueo',   v_id_bloqueo,
      'id_cabana',    v_id_cabana,
      'fecha_desde',  v_fecha_desde,
      'fecha_hasta',  v_fecha_hasta,
      'motivo',       v_motivo,
      'tipo_bloqueo', CASE WHEN v_id_cabana IS NULL THEN 'total' ELSE 'cabana_especifica' END
    )
  );

  RETURN jsonb_build_object(
    'ok',           true,
    'id_bloqueo',   v_id_bloqueo,
    'id_cabana',    v_id_cabana,
    'tipo_bloqueo', CASE WHEN v_id_cabana IS NULL THEN 'total' ELSE 'cabana_especifica' END
  );
END;
$function$
```

</details>

### B.1 — `vista_ocupacion`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
 WITH meses AS (
         SELECT generate_series(date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) - '1 year'::interval, date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 year'::interval - '1 mon'::interval, '1 mon'::interval)::date AS inicio_mes
        ), matriz AS (
         SELECT c.id_cabana,
            c.nombre AS cabana,
            m.inicio_mes,
            (m.inicio_mes + '1 mon'::interval - '1 day'::interval)::date AS fin_mes
           FROM cabanas c
             CROSS JOIN meses m
          WHERE c.activa = true
        )
 SELECT id_cabana,
    cabana,
    inicio_mes,
    fin_mes,
    COALESCE(( SELECT sum(LEAST(r.fecha_checkout, (mx.fin_mes + '1 day'::interval)::date) - GREATEST(r.fecha_checkin, mx.inicio_mes)) AS sum
           FROM reservas r
          WHERE r.id_cabana = mx.id_cabana AND (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum, 'completada'::estado_reserva_enum])) AND r.fecha_checkin < (mx.fin_mes + '1 day'::interval)::date AND r.fecha_checkout > mx.inicio_mes), 0::bigint) AS noches_ocupadas,
    EXTRACT(day FROM fin_mes + '1 day'::interval - inicio_mes::timestamp without time zone)::integer AS dias_del_mes
   FROM matriz mx
  ORDER BY id_cabana, inicio_mes;
```

</details>

### B.2 — `vista_calendario`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
 SELECT c.id_cabana,
    c.nombre AS cabana,
    r.id_reserva,
    r.fecha_checkin,
    r.fecha_checkout,
    r.hora_checkin,
    r.hora_checkout,
    r.personas,
    r.estado AS estado_reserva,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre,
    h.telefono AS huesped_telefono,
    r.monto_total,
    r.monto_saldo,
    r.encargado_semana
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum])) AND r.fecha_checkout >= CURRENT_DATE AND r.fecha_checkin <= (CURRENT_DATE + 60)
  ORDER BY r.fecha_checkin, c.id_cabana;
```

</details>

### B.3 — `vista_limpieza_semana`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
 SELECT r.fecha_checkout AS fecha_movimiento,
    'checkout'::text AS tipo_movimiento,
    c.nombre AS cabana,
    c.id_cabana,
    r.id_reserva,
    r.hora_checkout AS hora,
    r.personas,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped,
    h.telefono AS huesped_telefono,
    r.mascotas,
    r.detalle_mascotas,
    r.notas_reserva
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum, 'completada'::estado_reserva_enum])) AND r.fecha_checkout >= CURRENT_DATE AND r.fecha_checkout <= (CURRENT_DATE + 7)
UNION ALL
 SELECT r.fecha_checkin AS fecha_movimiento,
    'checkin'::text AS tipo_movimiento,
    c.nombre AS cabana,
    c.id_cabana,
    r.id_reserva,
    r.hora_checkin AS hora,
    r.personas,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped,
    h.telefono AS huesped_telefono,
    r.mascotas,
    r.detalle_mascotas,
    r.notas_reserva
   FROM reservas r
     JOIN cabanas c ON c.id_cabana = r.id_cabana
     JOIN huespedes h ON h.id_huesped = r.id_huesped
  WHERE (r.estado = ANY (ARRAY['confirmada'::estado_reserva_enum, 'activa'::estado_reserva_enum])) AND r.fecha_checkin >= CURRENT_DATE AND r.fecha_checkin <= (CURRENT_DATE + 7)
  ORDER BY 1, 6;
```

</details>

### B.4 — `vista_prereservas_activas`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
 SELECT pr.id_pre_reserva,
    c.nombre AS cabana,
    pr.id_cabana,
    pr.fecha_in,
    pr.fecha_out,
    pr.personas,
    pr.estado,
    pr.expira_en,
    EXTRACT(epoch FROM pr.expira_en - now()) / 60::numeric AS minutos_para_vencer,
    pr.monto_total,
    pr.monto_sena,
    pr.canal_origen,
    pr.canal_pago_esperado,
    TRIM(BOTH FROM (h.nombre || ' '::text) || COALESCE(h.apellido, ''::text)) AS huesped_nombre,
    h.telefono AS huesped_telefono
   FROM pre_reservas pr
     JOIN cabanas c ON c.id_cabana = pr.id_cabana
     JOIN huespedes h ON h.id_huesped = pr.id_huesped
  WHERE (pr.estado = ANY (ARRAY['pendiente_pago'::estado_prereserva_enum, 'pago_en_revision'::estado_prereserva_enum])) AND pr.expira_en > now()
  ORDER BY pr.expira_en;
```

</details>

### C.1 — columnas de `cabanas`

<details>
<summary>Output crudo (click para expandir)</summary>

```
| column_name     | data_type                  | is_nullable | column_default                          |
|-----------------|----------------------------|-------------|-----------------------------------------|
| id_cabana       | bigint                     | NO          | nextval('cabanas_id_cabana_seq'::regclass) |
| nombre          | text                       | NO          | null                                    |
| tipo            | text                       | NO          | null                                    |
| capacidad_base  | integer                    | NO          | null                                    |
| capacidad_max   | integer                    | NO          | null                                    |
| activa          | boolean                    | NO          | true                                    |
| orden_limpieza  | integer                    | YES         | null                                    |
| descripcion     | text                       | YES         | null                                    |
| fotos_urls      | text                       | YES         | null                                    |
| created_at      | timestamp with time zone   | NO          | now()                                   |
```

</details>

### C.2 — columnas de `bloqueos`

<details>
<summary>Output crudo (click para expandir)</summary>

```
| column_name   | data_type                  | is_nullable | column_default                              |
|---------------|----------------------------|-------------|---------------------------------------------|
| id_bloqueo    | bigint                     | NO          | nextval('bloqueos_id_bloqueo_seq'::regclass) |
| id_cabana     | bigint                     | YES         | null                                        |
| fecha_desde   | date                       | NO          | null                                        |
| fecha_hasta   | date                       | NO          | null                                        |
| motivo        | text                       | NO          | null                                        |
| descripcion   | text                       | YES         | null                                        |
| creado_por    | text                       | NO          | null                                        |
| activo        | boolean                    | NO          | true                                        |
| source_event  | text                       | NO          | null                                        |
| created_at    | timestamp with time zone   | NO          | now()                                       |
```

</details>

### C.3.a — columnas de `huespedes`

<details>
<summary>Output crudo (click para expandir)</summary>

```
| column_name           | data_type                  | is_nullable |
|-----------------------|----------------------------|-------------|
| id_huesped            | bigint                     | NO          |
| nombre                | text                       | NO          |
| apellido              | text                       | YES         |
| dni                   | text                       | YES         |
| telefono              | text                       | YES         |
| telefono_normalizado  | text                       | YES         |
| email                 | text                       | YES         |
| canal_preferido       | text                       | YES         |
| primera_reserva_fecha | date                       | YES         |
| total_reservas        | integer                    | NO          |
| notas_internas        | text                       | YES         |
| created_at            | timestamp with time zone   | NO          |
| updated_at            | timestamp with time zone   | NO          |
```

</details>

### C.3.b — `normalizar_telefono(text)`

<details>
<summary>Output crudo (click para expandir)</summary>

```sql
CREATE OR REPLACE FUNCTION public.normalizar_telefono(input text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_clean TEXT;
BEGIN
  IF input IS NULL OR TRIM(input) = '' THEN
    RETURN NULL;
  END IF;

  -- Quitar espacios, guiones, paréntesis, puntos
  v_clean := REGEXP_REPLACE(input, '[\s\-\(\)\.]', '', 'g');

  -- Si empieza con '00', reemplazar por '+'
  IF v_clean LIKE '00%' THEN
    v_clean := '+' || SUBSTRING(v_clean FROM 3);
  END IF;

  -- Colapsar múltiples '+' a uno solo (solo válido al inicio)
  -- Primero: quitar todos los '+' excepto el primero
  IF v_clean LIKE '+%' THEN
    v_clean := '+' || REGEXP_REPLACE(SUBSTRING(v_clean FROM 2), '[^0-9]', '', 'g');
  ELSE
    -- Sin '+', dejar solo dígitos
    v_clean := REGEXP_REPLACE(v_clean, '[^0-9]', '', 'g');
  END IF;

  -- Si quedó vacío después de limpiar, retornar NULL
  IF v_clean = '' OR v_clean = '+' THEN
    RETURN NULL;
  END IF;

  RETURN v_clean;
END;
$function$
```

</details>

### C.4 — columna `ninos` en `pre_reservas` y `reservas`

<details>
<summary>Output crudo (click para expandir)</summary>

```
| table_name    | column_name | data_type | is_nullable | column_default |
|---------------|-------------|-----------|-------------|----------------|
| pre_reservas  | ninos       | text      | YES         | null           |
| reservas      | ninos       | text      | YES         | null           |
```

**Hallazgo:** ambas columnas son TEXT, no BOOLEAN como se había anticipado en el análisis A.3. Ver divergencia #15 y observaciones internas C.4.

</details>

### Query auxiliar — introspección de valores persistidos de `ninos` (post-C.4)

<details>
<summary>Output crudo (click para expandir)</summary>

```
| tabla         | id  | ninos   |
|---------------|-----|---------|
| pre_reservas  | 25  | "false" |
| pre_reservas  | 26  | "false" |
| reservas      | 8   | "false" |
```

**Observación:** los 3 registros existentes en DEV tienen el valor textual `"false"` en la columna `ninos`. Confirma desalineación actual entre función (BOOLEAN) y tablas (TEXT). Corrige inferencia previa (`'t'`/`'f'`). El cast implícito BOOLEAN→TEXT en PostgreSQL al INSERT está produciendo la representación `"false"` (no la forma canónica corta).

</details>

### Query auxiliar — conteo textual de ocurrencias `NULLIF(TRIM(`

<details>
<summary>Output crudo (click para expandir)</summary>

**Query 1 — conteo de `NULLIF(TRIM(`:**

```
| fn                  | nullif_trim_ocurrencias |
|---------------------|-------------------------|
| cancelar_prereserva | 5                       |
| confirmar_reserva   | 7                       |
| crear_bloqueo       | 8                       |
| crear_prereserva    | 20                      |
| registrar_pago      | 18                      |
```

**Total B = 58**

**Query 2 — conteo de `NULLIF(` (sin requerir TRIM):**

```
| fn                  | nullif_total_ocurrencias |
|---------------------|--------------------------|
| cancelar_prereserva | 5                        |
| confirmar_reserva   | 7                        |
| crear_bloqueo       | 8                        |
| crear_prereserva    | 22                       |
| registrar_pago      | 18                       |
```

**Total C = 60**

**Observación:** las dos ocurrencias de diferencia C − B (= 2) están en `crear_prereserva` y corresponden a las validaciones inline de contacto del huésped sin TRIM (`NULLIF(v_huesped_payload->>'telefono', '')` y `NULLIF(v_huesped_payload->>'email', '')`). Tratamiento aprobado: observación interna, no pendiente formal — el payload anidado `huesped` es excepción del patrón principal porque su normalización vive en `upsert_huesped`.

</details>

---

## 6. Pendientes operativos del Frente A

### Decisiones diferidas (no bloqueantes para snapshots B/C)

- [x] Conteo: Camino 1 aprobado — changelog sin cifra. Redacción aprobada: "Patrón defensivo `NULLIF(TRIM(...), '')` aplicado en los extracts de payload de las 5 funciones write críticas: `registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva` y `crear_bloqueo`." No usar 52, 58, 60 ni 56 en el changelog.
- [ ] **Frente B:** revisar `DECISIONES_NO_REABRIR.md` D-HARD-01 para sustituir "56 asignaciones" por redacción sin cifra. No corregir en Frente A.
- [x] **Normalizaciones L-6D-02 del motor PostgreSQL** en vistas — DECISIÓN APROBADA 2026-05-27: para las vistas afectadas del Bloque 20, el canónico v1.7.2 adopta la forma persistida que devuelve `pg_get_viewdef()`. No se detalla cada caso en el changelog. Nota breve única: "En las vistas actualizadas por snapshot, el SQL se refleja en la forma persistida por PostgreSQL para facilitar futuras comparaciones con `pg_get_viewdef()`." Criterio firme para B.1-B.4.
- [x] **Desalineación `ninos` función/tablas** (hallazgo C.4): DECISIÓN APROBADA 2026-05-27 tras introspección de valores persistidos:
  - **Snapshot-first vigente:** canónico v1.7.2 refleja DEV tal cual (función con `v_ninos BOOLEAN`, tablas con `ninos TEXT`).
  - **Item nuevo en `Pendiente_pre_produccion.md`** durante Frente B con redacción liviana: "Evaluar alineación de tipo de `ninos` entre función y tablas antes de TEST/PROD."
  - **No es freno del bump documental.** Hallazgo gestionado.
  - **No tocar SQL en DEV.** No cambiar columnas ni funciones.
  - **No atribuir causa histórica** al hardening sin evidencia.

### Snapshots pendientes

- [x] B.1 — `vista_ocupacion` (H5) ✅
- [x] B.2 — `vista_calendario` (H6) ✅
- [x] B.3 — `vista_limpieza_semana` (H6) ✅
- [x] B.4 — `vista_prereservas_activas` (H6-bis) ✅
- [x] C.1 — columnas de `cabanas` (divergencia `capacidad_max` vs `capacidad_maxima`) ✅
- [x] C.2 — columnas de `bloqueos` (divergencia `activo` BOOLEAN vs `estado` enum) ✅
- [x] C.3.a — columnas de `huespedes` ✅
- [x] C.3.b — `normalizar_telefono(text)` (manejo del `+`) ✅
- [x] C.4 — columna `ninos` en `pre_reservas` y `reservas` ✅ (con hallazgo)
- [x] Query auxiliar — conteo textual de `NULLIF(TRIM(` ✅ (ejecutada con query secundaria adicional sobre `NULLIF(`)

### Post-snapshots

- [ ] Validación cruzada final de divergencias contra la lista de la sección 4.
- [ ] Aprobación final del bump.
- [ ] Backup de v1.7.1 (opción C aprobada: tag Git + archivo en `Docs/Implementacion/Archivados/`).
- [ ] Redacción del changelog v1.7.1 → v1.7.2 con separación a) hardening + b) correcciones documentales.
- [ ] Aplicación in-place quirúrgica al archivo `6B_SCHEMA_SQL.md` v1.7.2.

### Después del Frente A

- [ ] Frente B — bloque H7 en `HARDENING_PRE_PRODUCCION_EJECUCION.md` (si falta consolidar).
- [ ] Frente B — `6D_CIERRE.md`.
- [ ] Frente B — actualizaciones menores en archivos satélite.
- [ ] Frente B — agregar item liviano nuevo en `Pendiente_pre_produccion.md`: "Evaluar alineación de tipo de `ninos` entre función y tablas antes de TEST/PROD" (hallazgo gestionado de C.4).
- [ ] Frente B — revisar `DECISIONES_NO_REABRIR.md` D-HARD-01 para sustituir "56 asignaciones" por redacción sin cifra. Mismo tratamiento para referencias a "56" en `Pendiente_pre_produccion.md` y `ESTADO_ACTUAL_VITA_DELTA.md`.

---

## 7. Bitácora cronológica abreviada

| Fecha-Hora | Evento |
|---|---|
| 2026-05-27 | Apertura H8. Plan Frente A propuesto por Claude. |
| 2026-05-27 | Plan Frente A aprobado con ajustes (backup opción C, changelog con separación a/b, divergencias L-6D-09 incluidas en bump como correcciones documentales, snapshot-first). |
| 2026-05-27 | Inventario de queries read-only aprobado con ajustes (C.3 dividido en C.3.a y C.3.b, fallback de firma para `normalizar_telefono`, A.1-A.5 uno por uno). |
| 2026-05-27 | Baseline de conteos confirmado: 1,2,1,2,2,11 — idéntico a baseline post-H7. DEV intacto. |
| 2026-05-27 | A.1 `registrar_pago` capturado y aprobado. 17 asignaciones con patrón canónico. Divergencias del log explícito confirmadas. |
| 2026-05-27 | A.2 `confirmar_reserva` capturado y aprobado. 6 asignaciones. Divergencia `estado_invalido` confirmada. |
| 2026-05-27 | A.3 `crear_prereserva` capturado y aprobado. 18 asignaciones. Divergencias `v_ninos` BOOLEAN y `canal_pago_esperado` opcional confirmadas. C.4 propuesto y aprobado. |
| 2026-05-27 | A.4 `cancelar_prereserva` capturado y aprobado. 4 asignaciones. Sin divergencias documentales nuevas. |
| 2026-05-27 | A.5 `crear_bloqueo` capturado y aprobado. 7 asignaciones. D-HARD-04 confirmada estructuralmente. Discrepancia conteo 52 vs 56 abierta, no bloqueante. |
| 2026-05-27 | Sub-bloque A cerrado: 5 de 5 funciones aprobadas. Working note creada. |
| 2026-05-27 | B.1 `vista_ocupacion` capturado y aprobado. Fix H5 confirmado (`- '1 mon'::interval`). Normalizaciones L-6D-02 del motor identificadas; decisión sobre forma canónica (opciones 1/2/3) diferida. |
| 2026-05-27 | Criterio aprobado para normalizaciones L-6D-02 en vistas: adoptar forma persistida en canónico v1.7.2 + nota breve única en changelog. Sin detallar cada caso. |
| 2026-05-27 | B.2 `vista_calendario` capturado y aprobado. Fix H6 confirmado: `TRIM(BOTH FROM (h.nombre \|\| ' '::text) \|\| COALESCE(h.apellido, ''::text)) AS huesped_nombre`. 14 columnas, 2 estados filtrados, horizonte 60 días hardcoded (pendiente pre-producción separado). |
| 2026-05-27 | B.3 `vista_limpieza_semana` capturado y aprobado. Fix H6 confirmado en 2 ocurrencias del UNION ALL. Diferencia de estados filtrados entre checkout (3) y checkin (2) registrada como observación interna, no va al changelog. Horizonte 7 días hardcoded como comportamiento vigente fuera de alcance H8. |
| 2026-05-27 | B.4 `vista_prereservas_activas` capturado y aprobado. Fix H6-bis confirmado (1 ocurrencia). Sub-bloque B cerrado: 4 de 4 vistas aprobadas. Total ocurrencias TRIM agregadas: 4. |
| 2026-05-27 | C.1 columnas de `cabanas` capturado y aprobado. Confirma `capacidad_max` (no `capacidad_maxima`). 10 columnas reales en la tabla. |
| 2026-05-27 | C.2 columnas de `bloqueos` capturado y aprobado. Confirma `activo` BOOLEAN (no `estado` enum). `id_cabana` nullable confirma D-HARD-04. Verificación de enum/trigger postergada a edición final. |
| 2026-05-27 | C.3.a columnas de `huespedes` y C.3.b cuerpo de `normalizar_telefono(text)` capturados juntos. Firma `(text)` confirmada. Cuerpo confirma preservación del `+` (regex `[^0-9]` no lo elimina del prefijo). |
| 2026-05-27 | C.3.a + C.3.b cerrados como aprobados. Sin divergencia documental nueva — solo confirmación estructural/comportamental. No van al changelog. |
| 2026-05-27 | C.4 columna `ninos` capturado. **Hallazgo inesperado:** ambas columnas (`pre_reservas.ninos`, `reservas.ninos`) son TEXT, no BOOLEAN. Predicción del análisis A.3 fue equivocada. Cast implícito BOOLEAN→TEXT funciona, round-trip consistente, pero hay desalineación de tipo función/tablas. Decisión A/B/C diferida. |
| 2026-05-27 | Corrección de redacción aplicada: no afirmar "el hardening introdujo la desalineación" sin evidencia histórica. Redacción aprobada: "El snapshot C.4 confirma una desalineación actual entre `v_ninos BOOLEAN` en `crear_prereserva` y columnas `ninos TEXT` en `pre_reservas` / `reservas`." Introspección de valores persistidos pendiente antes de decidir destino documental. Snapshot-first vigente: canónico refleja DEV. No abrir pendiente formal todavía. |
| 2026-05-27 | Introspección de valores `ninos` ejecutada. 3 registros en DEV todos con valor `"false"` (literal textual). Corrige inferencia previa (`'t'`/`'f'`). C.4 cerrado como aprobado con hallazgo gestionado. Decisión: snapshot-first en canónico + item liviano en `Pendiente_pre_produccion.md` durante Frente B. No es freno del bump. |
| 2026-05-27 | Query auxiliar de conteo textual ejecutada (variantes `NULLIF(TRIM(` y `NULLIF(`). Resultados: A=52 (manual extract), B=58 (textual TRIM), C=60 (textual total). **Ninguna coincide con "56" histórico.** Camino 1 aprobado: changelog sin cifra. Las 3 métricas quedan registradas en working note con nota sobre que cuentas textuales pueden incluir comentarios. Eventual corrección de "56" en `DECISIONES_NO_REABRIR.md` queda para Frente B. |
| 2026-05-27 | Validación final del Frente A propuesta y aprobada con 7 ajustes obligatorios. Aplicados a working note. Próximo paso: backup v1.7.1 (tag Git + archivo histórico) y luego edición in-place del schema canónico siguiendo orden H2-H4-ter. |
| 2026-05-27 | Backup v1.7.1 creado con banner. MD5 cuerpo idéntico. 9 ediciones aplicadas in-place al schema canónico siguiendo orden H2-H4-ter: 5 funciones + 4 vistas + header + changelog. Verificaciones de no regresión OK. Búsquedas finales OK. Archivos entregados a Franco para revisión. Frente A NO cerrado todavía. |
| 2026-05-27 | Franco detecta inconsistencia post-revisión: el changelog v1.7.2 afirmaba que `canal_pago_esperado` era "opcional/no obligatorio", pero el `CREATE TABLE pre_reservas` mantiene `canal_pago_esperado TEXT NOT NULL`. **Inferencia equivocada de Claude** (análoga a las de A.3 y C.4): asumió "opcional" porque desapareció de la validación manual, sin verificar la columna. Tercera vez consecutiva en H8 que una inferencia sobre comportamiento sin verificar empíricamente termina siendo incorrecta. |
| 2026-05-27 | Introspección de columnas extendida (`canal_pago_esperado`, `mascotas`, `ninos` y otros). Confirma: `canal_pago_esperado` = `text NOT NULL`, `mascotas` = `boolean NOT NULL DEFAULT false`, `ninos` = `text nullable`. Mascotas consistente; `ninos` ya gestionado; `canal_pago_esperado` requiere corrección documental. |
| 2026-05-27 | Correcciones aplicadas al `6B_SCHEMA_SQL.md v1.7.2`: (1) changelog reemplaza "opcional" por explicación de que sigue requerido a nivel schema; (2) nuevo item en "Hallazgos no resueltos" para `canal_pago_esperado`; (3) Sección 10.5 payload narrativo aclara `canal_pago_esperado` requerido por schema y `ninos` como boolean parseable. SQL ejecutable NO se tocó. MD5 de los 5 cuerpos de funciones intactos. |
| 2026-05-27 | **Frente A de H8 — CERRADO ✅** Franco aprobó archivo corregido tras segunda revisión. Confirmaciones registradas: (1) `6B_SCHEMA_SQL.md` v1.7.2 es schema canónico vigente; (2) backup v1.7.1 con banner es archivo histórico, no fuente; (3) H7 tratado como validación sin cambios SQL; (4) Etapa 6D NO se afirma cerrada; (5) `canal_pago_esperado` documentado como requerido por schema; (6) `ninos` gestionado como pendiente liviano; (7) cifra "56" no aparece en changelog; (8) no hay schema paralelo. Próximo: arrancar Frente B. |

---

## Aprendizajes del Frente A para Frente B

1. **No inferir comportamiento sin verificar empíricamente.** Tres veces en H8 una inferencia sobre estructura/datos resultó equivocada:
   - A.3: asumí que columna `ninos` debía ser BOOLEAN (era TEXT).
   - C.4: asumí que el cast guarda `'t'`/`'f'` (guarda `"false"` literal).
   - Frente A: asumí que `canal_pago_esperado` era opcional (la columna sigue NOT NULL).
   
   **Patrón:** cuando una variable local del extract aparece sin validación manual, eso no implica que el campo sea opcional. Hay que verificar la columna de destino.

2. **El "snapshot-first" debe extenderse a las columnas destino** cuando el extract aplica `NULLIF(TRIM(...), '')` y el campo desaparece de la validación manual. La introspección de las 8 columnas que Franco pidió debería haber estado en el plan original de C.1-C.4 si yo hubiera sido más sistemático.

3. **Las divergencias documentales pueden estar latentes** entre función y constraint de columna, no solo entre función y declaración de variable. v1.7.2 quedó alineado con DEV en el SQL, pero la narrativa requirió un segundo pase de corrección post-revisión.

---

**Estado actual:** Frente A de H8 **CERRADO ✅** (2026-05-27). Schema canónico v1.7.2 vigente. Backup v1.7.1 archivado. Próximo: arrancar Frente B de H8.

---

## Plan operativo final aprobado del Frente A

### Redacciones aprobadas

- **Header del archivo v1.7.2:** "6B_SCHEMA_SQL.md v1.7.2 refleja documentalmente el estado real de DEV post-hardening H2-H6-bis. H7 validó concurrencia sin cambios SQL. Etapa 6D no cerrada todavía — H8 Frente B pendiente."
- **Changelog patrón unificado:** "Patrón defensivo `NULLIF(TRIM(...), '')` aplicado en los extracts de payload de las 5 funciones write críticas: `registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva` y `crear_bloqueo`."
- **Changelog `canal_pago_esperado` (corrección post-revisión):** "El extract aplica el patrón canónico `NULLIF(TRIM(...), '')`, pero el campo continúa requerido a nivel schema porque `pre_reservas.canal_pago_esperado` es `TEXT NOT NULL`. Si llega ausente, vacío o whitespace, la variable queda NULL y el INSERT puede fallar por constraint `NOT NULL`; evaluar en Frente B si corresponde restaurar validación manual controlada o hacer nullable la columna."
- **Changelog nota normalizaciones PostgreSQL:** "Las vistas actualizadas se reflejan en la forma persistida por PostgreSQL vía `pg_get_viewdef()` para facilitar futuras comparaciones." Va como nota técnica general del changelog, no como cambio de hardening sección a).
- **Cambios en Bloque 6 sobre bloqueos:** "Si aparece una referencia documental a `estado_bloqueo_enum` o `bloqueos.estado`, revisar contra DEV real y corregirla puntualmente si corresponde." No redactar como "eliminar enum" de entrada. No ejecutar introspecciones adicionales salvo ambigüedad concreta. **Resultado durante edición:** no apareció ninguna referencia; sin acción.
- **Hallazgo `ninos` en changelog:** mención mínima de alineación documental (no bloque de deuda técnica). Tratamiento principal va en Frente B como item liviano en `Pendiente_pre_produccion.md`.

### Items para Frente B (consolidado)

1. Revisar bloque H7 en `HARDENING_PRE_PRODUCCION_EJECUCION.md` (header "En curso" pero cierre interno "H1-H7 cerrados").
2. Crear `6D_CIERRE.md` formato similar a `6C_CIERRE.md`.
3. Agregar item liviano en `Pendiente_pre_produccion.md`: "Evaluar alineación de tipo de `ninos` entre función y tablas antes de TEST/PROD".
4. **Agregar item liviano en `Pendiente_pre_produccion.md`: "Contrato de `canal_pago_esperado`: evaluar si se restaura validación manual con `payload_invalido` o si se hace nullable a nivel schema antes de TEST/PROD".**
5. Sustituir cifra "56 asignaciones" por redacción sin cifra en `DECISIONES_NO_REABRIR.md` D-HARD-01, `Pendiente_pre_produccion.md` línea 460, `ESTADO_ACTUAL_VITA_DELTA.md` línea 184.
6. Actualizar `ESTADO_ACTUAL_VITA_DELTA.md` sección "Schema canónico actual" — marcar v1.7.2 como vigente.
7. Marcar "Bump documental del schema canónico a v1.7.2" como cerrado en `Pendiente_pre_produccion.md`.

### Redacciones aprobadas

- **Header del archivo v1.7.2:** "6B_SCHEMA_SQL.md v1.7.2 refleja documentalmente el estado real de DEV post-hardening H2-H6-bis. H7 validó concurrencia sin cambios SQL. Etapa 6D no cerrada todavía — H8 Frente B pendiente."
- **Changelog patrón unificado:** "Patrón defensivo `NULLIF(TRIM(...), '')` aplicado en los extracts de payload de las 5 funciones write críticas: `registrar_pago`, `confirmar_reserva`, `crear_prereserva`, `cancelar_prereserva` y `crear_bloqueo`."
- **Changelog nota normalizaciones PostgreSQL:** "Las vistas actualizadas se reflejan en la forma persistida por PostgreSQL vía `pg_get_viewdef()` para facilitar futuras comparaciones." Va como nota técnica general del changelog, no como cambio de hardening sección a).
- **Cambios en Bloque 6 sobre bloqueos:** "Si aparece una referencia documental a `estado_bloqueo_enum` o `bloqueos.estado`, revisar contra DEV real y corregirla puntualmente si corresponde." No redactar como "eliminar enum" de entrada. No ejecutar introspecciones adicionales salvo ambigüedad concreta.
- **Hallazgo `ninos` en changelog:** mención mínima de alineación documental (no bloque de deuda técnica). Tratamiento principal va en Frente B como item liviano en `Pendiente_pre_produccion.md`.

### Orden de edición aprobado

**Orden H2-H4-ter (no orden físico del archivo):**

1. `registrar_pago` (H2)
2. `confirmar_reserva` (H3)
3. `crear_prereserva` (H4)
4. `cancelar_prereserva` (H4-bis)
5. `crear_bloqueo` (H4-ter)
6. Vistas Bloque 20: `vista_ocupacion`, `vista_calendario`, `vista_limpieza_semana`, `vista_prereservas_activas` (mantener orden físico)
7. Bloque 3: corrección `capacidad_maxima` → `capacidad_max` (búsqueda global)
8. Bloque 6: corrección `bloqueos.estado/estado_bloqueo_enum` → `activo BOOLEAN` (si aplica)
9. Header y nuevo changelog (al final, una vez confirmado el contenido)

### Secuencia operativa pre-edición → edición → post-edición

**A — Backup v1.7.1 (antes de editar):**

1. Tag/commit Git.
2. Copia histórica en `Docs/Implementacion/Archivados/6B_SCHEMA_SQL_v1.7.1_PRE_HARDENING.md`.
3. Banner explícito: "ARCHIVO HISTÓRICO — NO ES FUENTE CANÓNICA VIGENTE".

**B — Edición in-place quirúrgica:** siguiendo el orden H2-H4-ter aprobado.

**C — Post-edición (no cerrar Frente A todavía):** devolver a Franco:

1. Resumen de archivos modificados.
2. Diff conceptual por sección.
3. Confirmación: no se tocaron funciones no afectadas (`normalizar_telefono`, `upsert_huesped`, `validar_disponibilidad`, `obtener_disponibilidad_rango`, `expirar_prereservas_vencidas`).
4. Confirmación: no se tocaron vistas no afectadas (`vista_disponibilidad`, `vista_calendario_semanal`).
5. Confirmación: no se tocaron seed, pg_cron, EXCLUDE constraints, ni schema paralelo.
6. Búsqueda final con grep en el archivo modificado: `capacidad_maxima`, `bloqueos.estado`, `estado_bloqueo`, `trg_log_bloqueos`, `56` (cifra histórica).

Solo después de revisión de Franco se cierra Frente A.

---

**Estado actual:** validación final del Frente A aprobada con 7 ajustes obligatorios. Plan operativo registrado. Próximo paso: ejecutar backup v1.7.1 antes de editar.
