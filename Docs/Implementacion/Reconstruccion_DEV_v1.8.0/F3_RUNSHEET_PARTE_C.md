# F3 — Ejecución de Parte C (Carril B) · Runsheet

**Proyecto:** `VITA_DELTA_DEV` · **DEV_REF:** `wsrdzjmvnzxidjlovlja` · **PG 17.6**
**Fuente de SQL:** `6B_SCHEMA_SQL.md` **v1.8.0**, sección **PARTE C** (Bloques C0→C14)
**Estado de entrada:** F2 cerrado — checkpoint `PARTE_B_OK` (2/4/20/6/13/13/2 + seed 5/3/10/1/1/1 + 2 jobs).

> Igual que F2: este runsheet **orquesta, no re-emite SQL**. Cada bloque se **copia del canónico** (Parte C). El canónico es la única fuente.

---

## Reglas de ejecución (idénticas a F2)

1. SQL Editor del **proyecto DEV nuevo** — confirmar `DEV_REF = wsrdzjmvnzxidjlovlja` en la URL, **nunca** `lpiatqztudxiwdlcoasv` (OPS).
2. **Un bloque por vez, con NADA seleccionado** (L-8A-01).
3. Éxito por bloque = **corre sin error** (Parte C no trae verificación por bloque; el gate es C14 + el checkpoint de inventario de abajo).
4. Si un bloque falla → **parar y diagnosticar**, no continuar.
5. **C13 es un solo bloque con 6 sub-statements** (C13.1→C13.6) en orden: el `NOT NULL` (C13.4) depende del backfill (C13.3). Correr C13 **entero**, no por pedazos.

---

## Orden de bloques (C0 → C14)

| # | Bloque (canónico) | Qué deja |
|---|---|---|
| C0 | Prerrequisito de extensión | `btree_gist` (idempotente; ya está del Bloque 1) |
| C1 | Columnas nuevas en `cabanas` | `valor_relativo` NUMERIC(6,2) (CHECK >0) + `id_socio_beneficiario` BIGINT FK RESTRICT — **NULLABLE** (el NOT NULL es C13.4) |
| C2 | Catálogo de zonas y pertenencias | tablas `zonas` y `cabana_zona` **vacías** (se siembran en C13) |
| C3 | Activaciones operativas (pool) | tabla `activaciones_operativas` **vacía** · EXCLUDE gist no-solape `[)` por cabaña |
| C4 | Gastos internos | `gastos_internos` (17 col, 18 constraints; clases A/C/D/E) |
| C5 | Cuenta corriente 9H — tablas | 5 tablas append-only: `liquidaciones_periodo`, `liquidacion_cascada`, `liquidacion_socio`, `movimientos_socio`, `revaluaciones` |
| C6 | Inmutabilidad 9H | `trg_9h_inmutable()` + **10 triggers** (BEFORE UPDATE + BEFORE DELETE sobre las 5 tablas 9H) |
| C7 | Seam de titularidad (9C) | `resolver_beneficiario(id_cabana, fecha)` |
| C8 | Matriz y reparto (9E) | `matriz_participacion`, `repartir_por_matriz`, `detalle_participacion` (read-only) |
| C9 | Cascada read-only (9G) | `cascada_periodo`, `saldo_socios_periodo`, `incidencia_gasto`, `reporte_overrides_periodo`, `reporte_5_vs_fiscal_periodo`, `gastos_sin_incidencia_periodo` (6) |
| C10 | Cuenta corriente 9H — funciones | lectura: `liquidacion_vigente`, `saldo_corriente_socio`, `mayor_socio`, `reporte_retribucion_operativo_periodo` · escritura (solo-INSERT, advisory locks): `registrar_snapshot_periodo`, `registrar_retiro`, `registrar_movimiento_manual`, `registrar_reversa`, `registrar_revaluacion` |
| C11 | Helper de cobranza atómica (9B) | `abortar_si_falla(jsonb)` |
| C12 | Hardening — REVOKE | REVOKE total sobre **9 tablas + 6 secuencias + 21 funciones** a PUBLIC/anon/authenticated/service_role |
| C13 | Seeds estructurales reales | ver detalle abajo |
| C14 | Verificación de seeds y consistencia | asserts read-only → NOTICE (ver abajo) |

---

## C13 — qué siembra (detalle, todo POR NOMBRE)

- **C13.1** — `configuracion_general('ambiente') = 'dev'` (`ON CONFLICT DO NOTHING`). **Para este entorno es `dev`** — no cambiar a test/ops. `config` pasa de 10 → **11**.
- **C13.2** — `zonas`: `grandes`, `chicas` (2 filas).
- **C13.3** — backfill de beneficiarios + `valor_relativo` por nombre: **Arrebol→Franco/100, Madre Selva→Rodrigo/100, Bamboo→Remo/100, Guatemala→Franco/78, Tokio→Remo/78**. Depende de `socios=3` con **Remo** (ya sembrado en Bloque 21).
- **C13.4** — `NOT NULL` en `cabanas.valor_relativo` e `id_socio_beneficiario` (recién acá, post-backfill).
- **C13.5** — `cabana_zona`: grandes = Arrebol/Madre Selva/Bamboo; chicas = Guatemala/Tokio (5 filas).
- **C13.6** — pool de activaciones (D-9D-10): Bamboo/Madre Selva/Arrebol/Tokio desde **2026-07-01**; **Guatemala desde 2026-11-01** (5 filas, abiertas).

---

## Notas / gotchas (solo para saber)

- **C12 en un proyecto cerrado:** las funciones y secuencias del Carril B nacen **sin grants a roles API** (creadas por postgres; ver P4). El REVOKE de C12 es **red de seguridad** y, en las 9 tablas Carril B, saca también el residual `Dxtm` que heredarían del default de postgres → las tablas Carril B quedan en **0 exposición** (a diferencia de las tablas base, que conservan el residual aceptado).
- **C14 es read-only** (bloque `DO` con asserts). Si todo cuadra, termina con un `NOTICE`; si algo falla, aborta con `EXCEPTION` detallada indicando qué no cuadró.

**NOTICE esperado de C14:**

```
PARTE C OK: zonas=2, cabana_zona=5, beneficiarios sin NULL, activaciones=5,
seam 5/5, matriz 378/456, reparto Σ=100000.00, hardening tablas/secuencias/funciones sin exposición.
```

---

## Checkpoint de cierre de Parte C — INVENTARIO (READ-ONLY)

Correr **después de C14**, con nada seleccionado. Read-only. Cubre el checklist de inventario que C14 no asserta por conteo (9 tablas / 21 funciones / 10 triggers / 6 secuencias) y reconfirma `ambiente='dev'`.

```sql
-- CHECKPOINT CARRIL B — INVENTARIO (read-only). Correr después de C14.
WITH
ctabs  AS (SELECT count(*) n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
            WHERE s.nspname='public' AND c.relkind='r'
            AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos',
              'liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
              'movimientos_socio','revaluaciones')),
cfuncs AS (SELECT count(DISTINCT p.proname) n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
            WHERE s.nspname='public' AND p.proname IN (
              'resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion',
              'cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo',
              'reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo','liquidacion_vigente',
              'saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
              'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual',
              'registrar_reversa','registrar_revaluacion','trg_9h_inmutable','abortar_si_falla')),
ctrigs AS (SELECT count(*) n FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
            WHERE p.proname='trg_9h_inmutable' AND NOT t.tgisinternal),
cseqs  AS (SELECT count(*) n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
            WHERE s.nspname='public' AND c.relkind='S'
            AND c.relname IN ('zonas_id_zona_seq','activaciones_operativas_id_activacion_seq',
              'gastos_internos_id_gasto_seq','liquidaciones_periodo_id_liquidacion_seq',
              'movimientos_socio_id_movimiento_seq','revaluaciones_id_revaluacion_seq')),
amb    AS (SELECT valor FROM configuracion_general WHERE clave='ambiente')
SELECT
  (SELECT n FROM ctabs)  AS tablas_carrilb,          -- esperado 9
  (SELECT n FROM cfuncs) AS funciones_carrilb,       -- esperado 21
  (SELECT n FROM ctrigs) AS triggers_inmutabilidad,  -- esperado 10
  (SELECT n FROM cseqs)  AS secuencias_carrilb,      -- esperado 6
  COALESCE((SELECT valor FROM amb),'(ausente)') AS ambiente,  -- esperado 'dev'
  CASE WHEN (SELECT n FROM ctabs)=9 AND (SELECT n FROM cfuncs)=21
        AND (SELECT n FROM ctrigs)=10 AND (SELECT n FROM cseqs)=6
        AND (SELECT valor FROM amb)='dev'
       THEN 'CARRIL_B_OK -> habilita F5 (barrido global de permisos + cierre)'
       ELSE 'CARRIL_B_INCOMPLETO -> revisar el conteo/marcador que no cuadra'
  END AS veredicto;
```

---

## Qué sigue (F5), cuando esto cierre

Solo con **C14 = NOTICE** y checkpoint = **`CARRIL_B_OK`**, preparo F5:

1. **Barrido global de permisos** (read-only, base + Carril B): confirma **0 grants amplios** (`SELECT/INSERT/UPDATE/DELETE`) a PUBLIC/anon/authenticated/service_role en todo el schema, y **reporta explícitamente** el residual aceptado de las tablas base (`Dxtm` = TRUNCATE/REFERENCES/TRIGGER/MAINTAIN; **sin** r/a/w/d; no se revoca, por paridad OPS/TEST).
2. **Documento breve de cierre** de la reconstrucción DEV.
3. **Handoff:** recomendaciones para credencial n8n `vita_supabase_dev` y para el portal operativo interno (sin crear workflows en esta etapa).

---

## Qué NO hace F3

- No crea workflows n8n ni la credencial DEV (eso es handoff, F5/F6).
- No toca DEV viejo, TEST ni OPS.
- No corre funciones de escritura 9H (las secuencias del Carril B quedan en 1; C14 y el checkpoint son read-only).
