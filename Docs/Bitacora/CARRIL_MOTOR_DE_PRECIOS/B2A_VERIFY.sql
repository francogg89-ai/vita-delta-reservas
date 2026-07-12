-- ============================================================================
-- B2A_VERIFY -- Verificacion read-only de la migracion B2A
-- Corre despues de B2A_MIGRACION.sql. No muta nada.
-- Salida: tabla de checks (PASS/FAIL) + fingerprint estructural.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _verify (orden INT, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN) ON COMMIT DROP;

-- V1: 7 tablas nuevas existen
INSERT INTO _verify
SELECT 1, 'V1_tablas_nuevas', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                    'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria');

-- V2: columnas aditivas en cabanas/reservas/pre_reservas (7 en total)
INSERT INTO _verify
SELECT 2, 'V2_columnas_aditivas', '7', COUNT(*)::TEXT, COUNT(*) = 7
FROM information_schema.columns
WHERE (table_name='cabanas'      AND column_name='perfil_tarifario')
   OR (table_name='reservas'     AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
   OR (table_name='pre_reservas' AND column_name='cotizacion_id');

-- V3: capacidad_override es BOOLEAN NOT NULL DEFAULT FALSE
INSERT INTO _verify
SELECT 3, 'V3_capacidad_override', 'boolean/NO/false',
       data_type||'/'||is_nullable||'/'||COALESCE(column_default,'(null)'),
       data_type='boolean' AND is_nullable='NO' AND column_default LIKE 'false%'
FROM information_schema.columns WHERE table_name='reservas' AND column_name='capacidad_override';

-- V4: backfill correcto (5 cabanas, perfil = tipo, sin NULL)
INSERT INTO _verify
SELECT 4, 'V4_backfill_cabanas', '5/0',
       COUNT(*)::TEXT||'/'||COUNT(*) FILTER (WHERE perfil_tarifario IS NULL OR perfil_tarifario <> tipo)::TEXT,
       COUNT(*) = 5 AND COUNT(*) FILTER (WHERE perfil_tarifario IS NULL OR perfil_tarifario <> tipo) = 0
FROM cabanas;

-- V5: perfiles seed (grande=4, chica=3)
INSERT INTO _verify
SELECT 5, 'V5_perfiles_seed', 'grande=4,chica=3',
       string_agg(perfil||'='||personas_incluidas, ',' ORDER BY perfil),
       (SELECT personas_incluidas FROM perfiles_tarifarios WHERE perfil='grande')=4
   AND (SELECT personas_incluidas FROM perfiles_tarifarios WHERE perfil='chica')=3
FROM perfiles_tarifarios WHERE perfil IN ('grande','chica');

-- V6: 8 config keys de pricing
INSERT INTO _verify
SELECT 6, 'V6_config_keys', '8', COUNT(*)::TEXT, COUNT(*) = 8
FROM configuracion_general WHERE clave LIKE 'precio_%';

-- V7: editable flags (6 editables true, 2 false)
INSERT INTO _verify
SELECT 7, 'V7_config_editable', '6true/2false',
       COUNT(*) FILTER (WHERE editable)::TEXT||'true/'||COUNT(*) FILTER (WHERE NOT editable)::TEXT||'false',
       COUNT(*) FILTER (WHERE editable)=6 AND COUNT(*) FILTER (WHERE NOT editable)=2
FROM configuracion_general WHERE clave LIKE 'precio_%';

-- V8: indice nuevo en paquetes_evento.id_evento existe (fix riesgo B1.1 #4)
INSERT INTO _verify
SELECT 8, 'V8_idx_paquetes_evento', '1', COUNT(*)::TEXT, COUNT(*) = 1
FROM pg_indexes WHERE tablename='paquetes_evento' AND indexname='idx_paquetes_evento_id_evento';

-- V9: indice unico parcial de vigencia
INSERT INTO _verify
SELECT 9, 'V9_uq_tarifas_vigente', '1', COUNT(*)::TEXT, COUNT(*) = 1
FROM pg_indexes WHERE tablename='tarifas_motor' AND indexname='uq_tarifas_motor_vigente';

-- V10: hardening tablas -- ninguna de las 7 con grants a roles Data API
INSERT INTO _verify
SELECT 10, 'V10_hardening_tablas', '0_expuestas',
       COUNT(*) FILTER (WHERE g.grantee IN ('anon','authenticated','service_role','PUBLIC'))::TEXT||'_expuestas',
       COUNT(*) FILTER (WHERE g.grantee IN ('anon','authenticated','service_role','PUBLIC')) = 0
FROM information_schema.role_table_grants g
WHERE g.table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                       'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria');

-- V11: hardening secuencias -- 4 secuencias sin grants Data API
INSERT INTO _verify
SELECT 11, 'V11_hardening_secuencias', '0_expuestas',
       COUNT(*)::TEXT||'_expuestas',
       COUNT(*) = 0
FROM information_schema.role_usage_grants g
WHERE g.object_name IN ('tarifas_motor_id_seq','temporada_vigencia_id_seq',
                        'overrides_precio_id_seq','precios_auditoria_id_seq')
  AND g.grantee IN ('anon','authenticated','service_role','PUBLIC');

-- V12: RLS OFF en las 7 tablas nuevas
INSERT INTO _verify
SELECT 12, 'V12_rls_off', '0_con_rls',
       COUNT(*) FILTER (WHERE relrowsecurity)::TEXT||'_con_rls',
       COUNT(*) FILTER (WHERE relrowsecurity) = 0
FROM pg_class WHERE relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                                'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria');

-- V13: trigger propio de inmutabilidad existe y revocado del Data API
INSERT INTO _verify
SELECT 13, 'V13_trg_precios_inmutable', 'existe/revocado',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='trg_precios_inmutable') THEN 'existe' ELSE 'FALTA' END
         ||'/'||CASE WHEN (SELECT proacl FROM pg_proc WHERE proname='trg_precios_inmutable') IS NULL THEN 'PUBLIC!' ELSE 'revocado' END,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname='trg_precios_inmutable')
       AND (SELECT proacl FROM pg_proc WHERE proname='trg_precios_inmutable') IS NOT NULL;

-- Resultado principal
SELECT check_id, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado
FROM _verify ORDER BY orden;

COMMIT;

-- ---------------------------------------------------------------------------
-- FINGERPRINT ESTRUCTURAL (comparar TEST vs futura OPS).
-- md5 sobre dump ordenado de columnas + constraints + indices de los objetos B2A.
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
       COUNT(*) AS n_lineas
FROM todo;
