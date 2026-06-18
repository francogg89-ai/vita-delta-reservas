-- ============================================================================
-- PROMO_BLOQUE_K1_FINGERPRINT_ESTRUCTURAL.sql
-- Promoción — BLOQUE K1: huella estructural SELECTIVA del Carril B + helper.
-- DOBLE CORRIDA: correr el MISMO script en TEST y en OPS; comparar las dos
-- salidas. Si la fila TOTAL_CARRIL coincide → paridad estructural exacta. Si no,
-- las filas por objeto localizan la diferencia. NADA embebido (simétrico).
--
-- 100% READ-ONLY. Compara ESTRUCTURA, no datos:
--   SÍ: tablas del carril, columnas (nombre+tipo+nullability), constraints
--       (nombre+definición), índices (nombre+definición), triggers
--       (nombre+definición), grants/ACL; funciones (firma + cuerpo + volatilidad
--       + security + search_path + ACL) incluido el helper; columnas de 9C en cabanas.
--   NO: reservas, pagos, bloqueos, gastos reales, liquidaciones, fixtures,
--       valores/uso de secuencias, marcador 'ambiente', datos de laboratorio.
--
-- Determinismo entre entornos: sin OIDs; ACL por su texto (usa nombres de rol,
-- iguales en TEST/OPS, dueño=postgres en ambos); cuerpos de función NORMALIZADOS
-- quitando '\r' (el helper en TEST quedó con \r\n; en OPS con \n).
--
-- Correr con NADA seleccionado (L-8A-01).
-- ============================================================================

WITH
carril_tabs(nom) AS (VALUES
  ('zonas'),('cabana_zona'),('activaciones_operativas'),('gastos_internos'),
  ('liquidaciones_periodo'),('liquidacion_cascada'),('liquidacion_socio'),
  ('movimientos_socio'),('revaluaciones')),
carril_fns(nom) AS (VALUES
  ('resolver_beneficiario'),('matriz_participacion'),('repartir_por_matriz'),('detalle_participacion'),
  ('cascada_periodo'),('saldo_socios_periodo'),('incidencia_gasto'),('reporte_overrides_periodo'),
  ('reporte_5_vs_fiscal_periodo'),('gastos_sin_incidencia_periodo'),('liquidacion_vigente'),('saldo_corriente_socio'),
  ('mayor_socio'),('reporte_retribucion_operativo_periodo'),('registrar_snapshot_periodo'),('registrar_retiro'),
  ('registrar_movimiento_manual'),('registrar_reversa'),('registrar_revaluacion'),('abortar_si_falla'),('trg_9h_inmutable')),

-- ── Manifiesto por TABLA del carril ─────────────────────────────────────────
tab_manifest AS (
  SELECT ct.nom,
    -- columnas: attnum|nombre|tipo|notnull
    COALESCE((SELECT string_agg(format('%s|%s|%s|%s', a.attnum, a.attname,
                       format_type(a.atttypid, a.atttypmod), a.attnotnull), E'\n' ORDER BY a.attnum)
              FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped),'') AS cols,
    -- constraints: nombre|definición (orden por nombre)
    COALESCE((SELECT string_agg(format('%s|%s', con.conname, pg_get_constraintdef(con.oid)), E'\n' ORDER BY con.conname)
              FROM pg_constraint con WHERE con.conrelid = c.oid),'') AS cons,
    -- índices: nombre|definición
    COALESCE((SELECT string_agg(format('%s|%s', i.indexname, i.indexdef), E'\n' ORDER BY i.indexname)
              FROM pg_indexes i WHERE i.schemaname='public' AND i.tablename = ct.nom),'') AS idx,
    -- triggers no internos: nombre|definición
    COALESCE((SELECT string_agg(format('%s|%s', tg.tgname, pg_get_triggerdef(tg.oid)), E'\n' ORDER BY tg.tgname)
              FROM pg_trigger tg WHERE tg.tgrelid = c.oid AND NOT tg.tgisinternal),'') AS trg,
    -- ACL de la tabla (texto; NULL explícito si sin grants)
    COALESCE(c.relacl::text, 'NULL') AS acl
  FROM carril_tabs ct
  JOIN pg_class c ON c.relname = ct.nom
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname='public' AND c.relkind='r'
),
tab_huellas AS (
  SELECT 'tabla:'||nom AS objeto,
         md5('COLS\n'||cols||'\nCONS\n'||cons||'\nIDX\n'||idx||'\nTRG\n'||trg||'\nACL\n'||acl) AS huella,
         nom AS ord
  FROM tab_manifest
),

-- ── Columnas de 9C agregadas a cabanas (solo esas dos; no toda la tabla) ─────
cabanas_carril AS (
  SELECT 'cabanas:carril_cols' AS objeto,
    md5(COALESCE((SELECT string_agg(format('%s|%s|%s', a.attname,
                       format_type(a.atttypid, a.atttypmod), a.attnotnull), E'\n' ORDER BY a.attname)
              FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
              JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname='public' AND c.relname='cabanas'
                AND a.attname IN ('valor_relativo','id_socio_beneficiario')
                AND NOT a.attisdropped),'(ausente)')) AS huella,
    'zzz_cabanas' AS ord
),

-- ── Manifiesto por FUNCIÓN del carril (incluye helper y trg_9h_inmutable) ────
fn_huellas AS (
  SELECT 'func:'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS objeto,
    md5(
      -- cuerpo completo NORMALIZADO (quita \r) + volatilidad/security/search_path van dentro de functiondef
      replace(pg_get_functiondef(p.oid), E'\r', '')
      || E'\n--ACL--\n' || COALESCE(p.proacl::text, 'NULL')
    ) AS huella,
    'fn_'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS ord
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (SELECT nom FROM carril_fns)
),

todo AS (
  SELECT objeto, huella, ord FROM tab_huellas
  UNION ALL SELECT objeto, huella, ord FROM cabanas_carril
  UNION ALL SELECT objeto, huella, ord FROM fn_huellas
)
SELECT objeto, huella FROM todo
UNION ALL
-- Huella total: md5 del concatenado determinístico de todas las huellas por objeto
SELECT 'TOTAL_CARRIL ('||count(*)||' objetos)' AS objeto,
       md5(string_agg(huella, '|' ORDER BY ord)) AS huella
FROM todo
ORDER BY 1;
