-- ============================================================================
-- B2B_VERIFY -- Verificacion read-only del seed B2B
-- Corre despues de B2B_SEED.sql. No muta nada.
-- Salida: (1) tabla de checks PASS/FAIL, (2) detalle de discrepancias de precio
--         (vacio = OK), (3) fingerprints.
-- ============================================================================

BEGIN;

-- Grilla esperada (32 celdas confirmadas) -- fuente de verdad de la asercion
CREATE TEMP TABLE _esperado (perfil TEXT, temporada_clave TEXT, concepto TEXT, precio NUMERIC(12,2)) ON COMMIT DROP;
INSERT INTO _esperado VALUES
  ('grande','alta','semana_noche_1',165000),('grande','alta','semana_noche_2',130000),
  ('grande','alta','semana_noche_3',105000),('grande','alta','semana_noche_4',105000),
  ('grande','alta','semana_noche_5plus',105000),('grande','alta','alta_demanda_noche_1',255000),
  ('grande','alta','alta_demanda_noche_2',130000),('grande','alta','alta_demanda_noche_3plus',190000),
  ('grande','baja','semana_noche_1',130000),('grande','baja','semana_noche_2',100000),
  ('grande','baja','semana_noche_3',80000),('grande','baja','semana_noche_4',80000),
  ('grande','baja','semana_noche_5plus',80000),('grande','baja','alta_demanda_noche_1',180000),
  ('grande','baja','alta_demanda_noche_2',120000),('grande','baja','alta_demanda_noche_3plus',150000),
  ('chica','alta','semana_noche_1',140000),('chica','alta','semana_noche_2',110000),
  ('chica','alta','semana_noche_3',90000),('chica','alta','semana_noche_4',90000),
  ('chica','alta','semana_noche_5plus',90000),('chica','alta','alta_demanda_noche_1',220000),
  ('chica','alta','alta_demanda_noche_2',115000),('chica','alta','alta_demanda_noche_3plus',165000),
  ('chica','baja','semana_noche_1',110000),('chica','baja','semana_noche_2',90000),
  ('chica','baja','semana_noche_3',70000),('chica','baja','semana_noche_4',70000),
  ('chica','baja','semana_noche_5plus',70000),('chica','baja','alta_demanda_noche_1',150000),
  ('chica','baja','alta_demanda_noche_2',100000),('chica','baja','alta_demanda_noche_3plus',125000);

-- Temporadas esperadas (8 filas)
CREATE TEMP TABLE _esperado_temp (temporada_clave TEXT, anio INT, fecha_in DATE, fecha_out_excl DATE) ON COMMIT DROP;
INSERT INTO _esperado_temp VALUES
  ('baja',2026,'2026-03-15','2026-11-15'),('alta',2026,'2026-11-15','2027-03-15'),
  ('baja',2027,'2027-03-15','2027-11-15'),('alta',2027,'2027-11-15','2028-03-15'),
  ('baja',2028,'2028-03-15','2028-11-15'),('alta',2028,'2028-11-15','2029-03-15'),
  ('baja',2029,'2029-03-15','2029-11-15'),('alta',2029,'2029-11-15','2030-03-15');

CREATE TEMP TABLE _verify (orden INT, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN) ON COMMIT DROP;

-- T1a: temporada_vigencia -- 8 filas exactas (match total contra esperado)
INSERT INTO _verify
SELECT 1, 'T1a_temporadas_exactas', '8_match',
       (SELECT COUNT(*) FROM temporada_vigencia)::TEXT||'_filas/'||
       (SELECT COUNT(*) FROM _esperado_temp e
          JOIN temporada_vigencia t ON t.temporada_clave=e.temporada_clave AND t.anio=e.anio
         WHERE t.fecha_in=e.fecha_in AND t.fecha_out_excl=e.fecha_out_excl)::TEXT||'_match',
       (SELECT COUNT(*) FROM temporada_vigencia) = 8
   AND (SELECT COUNT(*) FROM _esperado_temp e
          JOIN temporada_vigencia t ON t.temporada_clave=e.temporada_clave AND t.anio=e.anio
         WHERE t.fecha_in=e.fecha_in AND t.fecha_out_excl=e.fecha_out_excl) = 8;

-- T1b: cobertura CONTINUA (sin gaps ni solapes): cada fecha_out_excl = fecha_in siguiente
INSERT INTO _verify
SELECT 2, 'T1b_cobertura_continua', '0_discontinuidades',
       COUNT(*) FILTER (WHERE siguiente_in IS NOT NULL AND siguiente_in <> fecha_out_excl)::TEXT||'_discontinuidades',
       COUNT(*) FILTER (WHERE siguiente_in IS NOT NULL AND siguiente_in <> fecha_out_excl) = 0
FROM (SELECT fecha_out_excl, LEAD(fecha_in) OVER (ORDER BY fecha_in) AS siguiente_in
      FROM temporada_vigencia) s;

-- T2: 32 filas vigentes en tarifas_motor
INSERT INTO _verify
SELECT 3, 'T2_tarifas_vigentes', '32', COUNT(*)::TEXT, COUNT(*) = 32
FROM tarifas_motor WHERE vigente_hasta IS NULL;

-- T3: completitud -- cada (perfil,temporada) con los 8 conceptos; cero celdas faltantes
INSERT INTO _verify
SELECT 4, 'T3_completitud_grillas', '0_faltantes',
       (SELECT COUNT(*) FROM _esperado e
         WHERE NOT EXISTS (SELECT 1 FROM tarifas_motor t
                           WHERE t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
                             AND t.concepto=e.concepto AND t.vigente_hasta IS NULL))::TEXT||'_faltantes',
       (SELECT COUNT(*) FROM _esperado e
         WHERE NOT EXISTS (SELECT 1 FROM tarifas_motor t
                           WHERE t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
                             AND t.concepto=e.concepto AND t.vigente_hasta IS NULL)) = 0;

-- T4: sin tarifas en 0 o negativas
INSERT INTO _verify
SELECT 5, 'T4_sin_ceros', '0', COUNT(*)::TEXT, COUNT(*) = 0
FROM tarifas_motor WHERE vigente_hasta IS NULL AND precio <= 0;

-- T5: unicidad vigente -- ninguna celda con mas de una fila vigente
INSERT INTO _verify
SELECT 6, 'T5_unicidad_vigente', '0_duplicadas', COUNT(*)::TEXT||'_duplicadas', COUNT(*) = 0
FROM (SELECT perfil, temporada_clave, concepto FROM tarifas_motor
      WHERE vigente_hasta IS NULL
      GROUP BY perfil, temporada_clave, concepto HAVING COUNT(*) > 1) d;

-- T6: PRECIOS EXACTOS -- las 32 celdas, fila por fila (sin spot-check)
INSERT INTO _verify
SELECT 7, 'T6_precios_exactos_32', '32_match',
       (SELECT COUNT(*) FROM _esperado e
          JOIN tarifas_motor t ON t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
                              AND t.concepto=e.concepto AND t.vigente_hasta IS NULL
         WHERE t.precio = e.precio)::TEXT||'_match',
       (SELECT COUNT(*) FROM _esperado e
          JOIN tarifas_motor t ON t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
                              AND t.concepto=e.concepto AND t.vigente_hasta IS NULL
         WHERE t.precio = e.precio) = 32;

-- T7: hardening no degradado (7 tablas + 4 secuencias sin Data API; RLS off)
INSERT INTO _verify
SELECT 8, 'T7_hardening_intacto', 'ok',
       CASE WHEN
         (SELECT COUNT(*) FROM information_schema.role_table_grants
            WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                 'overrides_precio','cotizaciones_precio','precios_auditoria')
              AND grantee IN ('anon','authenticated','service_role','PUBLIC')) = 0
         AND (SELECT COUNT(*) FROM information_schema.role_usage_grants
                WHERE object_name IN ('tarifas_motor_id_seq','temporada_vigencia_id_seq',
                                      'overrides_precio_id_seq','precios_auditoria_id_seq')
                  AND grantee IN ('anon','authenticated','service_role','PUBLIC')) = 0
         AND (SELECT COUNT(*) FROM pg_class WHERE relrowsecurity AND relname IN
              ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
               'overrides_precio','cotizaciones_precio','precios_auditoria')) = 0
       THEN 'ok' ELSE 'DEGRADADO' END,
       (SELECT COUNT(*) FROM information_schema.role_table_grants
          WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                               'overrides_precio','cotizaciones_precio','precios_auditoria')
            AND grantee IN ('anon','authenticated','service_role','PUBLIC')) = 0
       AND (SELECT COUNT(*) FROM information_schema.role_usage_grants
              WHERE object_name IN ('tarifas_motor_id_seq','temporada_vigencia_id_seq',
                                    'overrides_precio_id_seq','precios_auditoria_id_seq')
                AND grantee IN ('anon','authenticated','service_role','PUBLIC')) = 0
       AND (SELECT COUNT(*) FROM pg_class WHERE relrowsecurity AND relname IN
            ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
             'overrides_precio','cotizaciones_precio','precios_auditoria')) = 0;

-- Resultado principal
SELECT check_id, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado
FROM _verify ORDER BY orden;

-- Detalle de discrepancias de precio (vacio = todas las 32 exactas)
SELECT e.perfil, e.temporada_clave, e.concepto,
       e.precio AS precio_esperado,
       t.precio AS precio_cargado,
       CASE WHEN t.precio IS NULL THEN 'FALTANTE' ELSE 'DIFIERE' END AS problema
FROM _esperado e
LEFT JOIN tarifas_motor t
  ON t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
 AND t.concepto=e.concepto AND t.vigente_hasta IS NULL
WHERE t.precio IS NULL OR t.precio <> e.precio
ORDER BY e.perfil, e.temporada_clave, e.concepto;

COMMIT;

-- ---------------------------------------------------------------------------
-- T8: FINGERPRINT ESTRUCTURAL B2A -- debe seguir INTACTO tras B2B
--     esperado: da52a16c045689523a5f1f113f513a87  (124 lineas)
-- ---------------------------------------------------------------------------
WITH cols AS (
  SELECT 'C|'||table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||COALESCE(column_default,'') AS line
  FROM information_schema.columns
  WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                       'overrides_precio','cotizaciones_precio','precios_auditoria')
     OR (table_name='cabanas' AND column_name='perfil_tarifario')
     OR (table_name='reservas' AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
     OR (table_name='pre_reservas' AND column_name='cotizacion_id')
),
cons AS (
  SELECT 'K|'||conrelid::regclass::text||'|'||conname||'|'||pg_get_constraintdef(oid) AS line
  FROM pg_constraint
  WHERE conrelid::regclass::text IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                     'overrides_precio','cotizaciones_precio','precios_auditoria')
     OR conname IN ('cabanas_perfil_tarifario_fkey','chk_reservas_precio_source',
                    'reservas_cotizacion_id_fkey','pre_reservas_cotizacion_id_fkey')
),
idx AS (
  SELECT 'I|'||tablename||'|'||indexname||'|'||indexdef AS line
  FROM pg_indexes
  WHERE tablename IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                      'overrides_precio','cotizaciones_precio','precios_auditoria')
     OR indexname='idx_paquetes_evento_id_evento'
),
todo AS (SELECT line FROM cols UNION ALL SELECT line FROM cons UNION ALL SELECT line FROM idx)
SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS b2a_fingerprint_estructural,
       COUNT(*) AS n_lineas,
       CASE WHEN md5(string_agg(line, E'\n' ORDER BY line)) = 'da52a16c045689523a5f1f113f513a87'
            THEN 'PASS - estructura intacta' ELSE 'FAIL - estructura modificada' END AS estado
FROM todo;

-- ---------------------------------------------------------------------------
-- FINGERPRINT DE DATOS B2B (referencia TEST vs futura OPS del seed)
-- ---------------------------------------------------------------------------
WITH tar AS (
  SELECT 'T|'||perfil||'|'||temporada_clave||'|'||concepto||'|'||precio::TEXT AS line
  FROM tarifas_motor WHERE vigente_hasta IS NULL
),
tmp AS (
  SELECT 'S|'||temporada_clave||'|'||anio::TEXT||'|'||fecha_in::TEXT||'|'||fecha_out_excl::TEXT AS line
  FROM temporada_vigencia
),
todo AS (SELECT line FROM tar UNION ALL SELECT line FROM tmp)
SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS b2b_fingerprint_datos,
       COUNT(*) AS n_lineas
FROM todo;
