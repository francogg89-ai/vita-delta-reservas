-- ============================================================================
-- B3_VERIFY -- Verificacion read-only de B3
-- Corre despues de B3_FUNCIONES.sql. No muta nada.
-- Salida: (1) checks PASS/FAIL, (2) fingerprint de funciones.
-- ============================================================================
BEGIN;
CREATE TEMP TABLE _v (orden INT, check_id TEXT, esperado TEXT, obtenido TEXT, ok BOOLEAN) ON COMMIT DROP;

-- V1: las 13 funciones existen
INSERT INTO _v
SELECT 1, 'V1_funciones', '13', COUNT(*)::TEXT, COUNT(*) = 13
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios_%';

-- V2: hardening -- ninguna alcanzable desde el Data API
INSERT INTO _v
SELECT 2, 'V2_hardening_funciones', '0_expuestas',
       COUNT(*) FILTER (WHERE proacl IS NULL
         OR EXISTS (SELECT 1 FROM aclexplode(proacl) a
                    JOIN pg_roles r ON r.oid = a.grantee
                    WHERE r.rolname IN ('anon','authenticated','service_role')))::TEXT||'_expuestas',
       COUNT(*) FILTER (WHERE proacl IS NULL
         OR EXISTS (SELECT 1 FROM aclexplode(proacl) a
                    JOIN pg_roles r ON r.oid = a.grantee
                    WHERE r.rolname IN ('anon','authenticated','service_role'))) = 0
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios_%';

-- V3: precios_cotizar es STABLE (read-only); congelar es VOLATILE (unico writer)
INSERT INTO _v
SELECT 3, 'V3_volatilidad', 'cotizar=STABLE/congelar=VOLATILE',
       (SELECT CASE provolatile WHEN 's' THEN 'STABLE' WHEN 'v' THEN 'VOLATILE' ELSE 'OTRA' END
          FROM pg_proc WHERE proname='precios_cotizar')
       ||'/'||
       (SELECT CASE provolatile WHEN 's' THEN 'STABLE' WHEN 'v' THEN 'VOLATILE' ELSE 'OTRA' END
          FROM pg_proc WHERE proname='precios_cotizar_congelar'),
       (SELECT provolatile='s' FROM pg_proc WHERE proname='precios_cotizar')
   AND (SELECT provolatile='v' FROM pg_proc WHERE proname='precios_cotizar_congelar');

-- V4: SECURITY INVOKER en todas (ninguna DEFINER)
INSERT INTO _v
SELECT 4, 'V4_security_invoker', '0_definer',
       COUNT(*) FILTER (WHERE prosecdef)::TEXT||'_definer',
       COUNT(*) FILTER (WHERE prosecdef) = 0
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios_%';

-- V5: cotizar NO usa FOR UPDATE ni advisory locks (path sin locks)
INSERT INTO _v
SELECT 5, 'V5_sin_locks', 'sin_locks',
       CASE WHEN COUNT(*) = 0 THEN 'sin_locks' ELSE COUNT(*)::TEXT||'_con_locks' END,
       COUNT(*) = 0
FROM pg_proc
WHERE pronamespace='public'::regnamespace
  AND proname IN ('precios_cotizar','precios_disponibilidad_noches','precios_precio_noche',
                  'precios_eventos_interseccion','precios_cotizacion_obtener')
  AND (prosrc ~* 'FOR UPDATE' OR prosrc ~* 'advisory');

-- V6: fecha_out EXCLUSIVE -- no se pasa fecha_out - 1 a obtener_disponibilidad_rango
INSERT INTO _v
SELECT 6, 'V6_fecha_out_exclusive', 'correcto',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname='precios_disponibilidad_noches')
                 ~ 'obtener_disponibilidad_rango\(p_fecha_in, p_fecha_out'
            THEN 'correcto' ELSE 'INCORRECTO' END,
       (SELECT prosrc FROM pg_proc WHERE proname='precios_disponibilidad_noches')
         ~ 'obtener_disponibilidad_rango\(p_fecha_in, p_fecha_out';

-- V7: checkout_disponible cuenta como vendible
INSERT INTO _v
SELECT 7, 'V7_checkout_vendible', 'si',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname='precios_disponibilidad_noches')
                 ~ 'checkout_disponible' THEN 'si' ELSE 'NO' END,
       (SELECT prosrc FROM pg_proc WHERE proname='precios_disponibilidad_noches') ~ 'checkout_disponible';

-- V8: la estructura B2A sigue intacta (B3 no toco tablas)
INSERT INTO _v
SELECT 8, 'V8_estructura_B2A_intacta', 'da52a16c045689523a5f1f113f513a87', fp,
       fp = 'da52a16c045689523a5f1f113f513a87'
FROM (
  WITH cols AS (
    SELECT 'C|'||table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||COALESCE(column_default,'') AS line
    FROM information_schema.columns
    WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                         'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR (table_name='cabanas' AND column_name='perfil_tarifario')
       OR (table_name='reservas' AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
       OR (table_name='pre_reservas' AND column_name='cotizacion_id')),
  cons AS (
    SELECT 'K|'||conrelid::regclass::text||'|'||conname||'|'||pg_get_constraintdef(oid) AS line
    FROM pg_constraint
    WHERE conrelid::regclass::text IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                       'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR conname IN ('cabanas_perfil_tarifario_fkey','chk_reservas_precio_source',
                      'reservas_cotizacion_id_fkey','pre_reservas_cotizacion_id_fkey')),
  idx AS (
    SELECT 'I|'||tablename||'|'||indexname||'|'||indexdef AS line
    FROM pg_indexes
    WHERE tablename IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                        'overrides_precio','cotizaciones_precio','precios_auditoria')
       OR indexname='idx_paquetes_evento_id_evento'),
  todo AS (SELECT line FROM cols UNION ALL SELECT line FROM cons UNION ALL SELECT line FROM idx)
  SELECT md5(string_agg(line, E'\n' ORDER BY line)) AS fp FROM todo) x;

-- V9: la grilla B2B sigue intacta (32 celdas vigentes)
INSERT INTO _v
SELECT 9, 'V9_grilla_B2B_intacta', '32', COUNT(*)::TEXT, COUNT(*) = 32
FROM tarifas_motor WHERE vigente_hasta IS NULL;

SELECT check_id, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS estado
FROM _v ORDER BY orden;
COMMIT;

-- ---------------------------------------------------------------------------
-- FINGERPRINT de funciones B3 -- NORMALIZADO
-- Se elimina CR (chr(13)) antes de hashear: si el .sql llega al SQL Editor con
-- line endings CRLF (Windows), PostgreSQL guarda \r\n dentro de prosrc y el md5
-- crudo cambia AUNQUE el codigo sea byte-identico. El fingerprint normalizado es
-- estable e independiente del line ending -> comparable harness/TEST/OPS.
-- Se emite tambien el crudo, solo como diagnostico.
-- ---------------------------------------------------------------------------
SELECT md5(string_agg(proname||'|'||md5(replace(prosrc, chr(13), ''))||'|'||provolatile::TEXT||'|'||prosecdef::TEXT, E'\n' ORDER BY proname))
         AS b3_fingerprint_funciones_normalizado,
       md5(string_agg(proname||'|'||md5(prosrc)||'|'||provolatile::TEXT||'|'||prosecdef::TEXT, E'\n' ORDER BY proname))
         AS fp_crudo_diagnostico,
       COUNT(*) FILTER (WHERE prosrc LIKE '%'||chr(13)||'%') AS funciones_con_CR,
       COUNT(*) AS n_funciones
FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios_%';
