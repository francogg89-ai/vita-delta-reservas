-- ============================================================================
-- B2B_SMOKES -- Suite Sm1..Sm9 de validacion del seed B2B
-- Corre despues de B2B_SEED.sql. Read-only (no muta datos).
-- Salida: tabla PASS/FAIL como ultimo result set.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _esp (perfil TEXT, temporada_clave TEXT, concepto TEXT, precio NUMERIC(12,2)) ON COMMIT DROP;
INSERT INTO _esp VALUES
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

CREATE TEMP TABLE _smoke_res (orden INT, sid TEXT, resultado TEXT) ON COMMIT DROP;

-- Sm1: temporada_vigencia -- 8 filas, continua, exclusive-end correcto
INSERT INTO _smoke_res
SELECT 1, 'Sm1_temporadas',
  CASE WHEN (SELECT COUNT(*) FROM temporada_vigencia) = 8
        AND (SELECT COUNT(*) FROM (SELECT fecha_out_excl, LEAD(fecha_in) OVER (ORDER BY fecha_in) AS sig
                                   FROM temporada_vigencia) s
              WHERE sig IS NOT NULL AND sig <> fecha_out_excl) = 0
        AND (SELECT MIN(fecha_in) FROM temporada_vigencia) = DATE '2026-03-15'
        AND (SELECT MAX(fecha_out_excl) FROM temporada_vigencia) = DATE '2030-03-15'
       THEN 'PASS - 8 filas, continua 2026-03-15..2030-03-15'
       ELSE 'FAIL' END;

-- Sm2: cada (perfil,temporada) con exactamente 8 conceptos vigentes; total 32
INSERT INTO _smoke_res
SELECT 2, 'Sm2_8_conceptos_x_grilla',
  CASE WHEN (SELECT COUNT(*) FROM (SELECT perfil, temporada_clave FROM tarifas_motor
                                   WHERE vigente_hasta IS NULL
                                   GROUP BY perfil, temporada_clave HAVING COUNT(*) = 8) g) = 4
        AND (SELECT COUNT(*) FROM tarifas_motor WHERE vigente_hasta IS NULL) = 32
       THEN 'PASS - 4 grillas x 8 conceptos = 32'
       ELSE 'FAIL ('||(SELECT COUNT(*) FROM tarifas_motor WHERE vigente_hasta IS NULL)||' vigentes)' END;

-- Sm3: ausencia de celdas faltantes (cartesiano 2 perfiles x 2 temporadas x 8 conceptos)
INSERT INTO _smoke_res
SELECT 3, 'Sm3_sin_celdas_faltantes',
  CASE WHEN COUNT(*) = 0 THEN 'PASS - cartesiano 100% cubierto'
       ELSE 'FAIL - '||COUNT(*)||' celdas faltantes' END
FROM (SELECT p.perfil, s.temporada_clave, c.concepto
      FROM (VALUES ('grande'),('chica')) p(perfil)
      CROSS JOIN (VALUES ('alta'),('baja')) s(temporada_clave)
      CROSS JOIN (VALUES ('semana_noche_1'),('semana_noche_2'),('semana_noche_3'),('semana_noche_4'),
                         ('semana_noche_5plus'),('alta_demanda_noche_1'),('alta_demanda_noche_2'),
                         ('alta_demanda_noche_3plus')) c(concepto)
      WHERE NOT EXISTS (SELECT 1 FROM tarifas_motor t
                        WHERE t.perfil=p.perfil AND t.temporada_clave=s.temporada_clave
                          AND t.concepto=c.concepto AND t.vigente_hasta IS NULL)) f;

-- Sm4: cero tarifas en 0 o negativas
INSERT INTO _smoke_res
SELECT 4, 'Sm4_sin_ceros',
  CASE WHEN COUNT(*) = 0 THEN 'PASS - ninguna tarifa <= 0' ELSE 'FAIL - '||COUNT(*)||' en 0/negativas' END
FROM tarifas_motor WHERE vigente_hasta IS NULL AND precio <= 0;

-- Sm5: unicidad vigente
INSERT INTO _smoke_res
SELECT 5, 'Sm5_unicidad_vigente',
  CASE WHEN COUNT(*) = 0 THEN 'PASS - 1 sola version vigente por celda'
       ELSE 'FAIL - '||COUNT(*)||' celdas duplicadas' END
FROM (SELECT perfil, temporada_clave, concepto FROM tarifas_motor WHERE vigente_hasta IS NULL
      GROUP BY perfil, temporada_clave, concepto HAVING COUNT(*) > 1) d;

-- Sm6: PRECIOS EXACTOS -- las 32 celdas fila por fila
INSERT INTO _smoke_res
SELECT 6, 'Sm6_precios_exactos_32',
  CASE WHEN (SELECT COUNT(*) FROM _esp e
               JOIN tarifas_motor t ON t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
                                   AND t.concepto=e.concepto AND t.vigente_hasta IS NULL
              WHERE t.precio = e.precio) = 32
       THEN 'PASS - 32/32 precios exactos'
       ELSE 'FAIL - solo '||(SELECT COUNT(*) FROM _esp e
               JOIN tarifas_motor t ON t.perfil=e.perfil AND t.temporada_clave=e.temporada_clave
                                   AND t.concepto=e.concepto AND t.vigente_hasta IS NULL
              WHERE t.precio = e.precio)||'/32' END;

-- Sm7: DEMOSTRACION de grillas completas -- tarifa_incompleta NO dispararia
--      (la logica del error vive en B3; aca se demuestra que los datos alcanzan)
INSERT INTO _smoke_res
SELECT 7, 'Sm7_grillas_completas',
  CASE WHEN COUNT(*) = 4 THEN 'PASS - grande/chica x alta/baja completas (tarifa_incompleta no aplicaria)'
       ELSE 'FAIL - solo '||COUNT(*)||'/4 grillas completas' END
FROM (SELECT t.perfil, t.temporada_clave
      FROM tarifas_motor t WHERE t.vigente_hasta IS NULL
      GROUP BY t.perfil, t.temporada_clave
      HAVING COUNT(DISTINCT t.concepto) = 8) g;

-- Sm8: resolucion de temporada en bordes (preview de B3; valida los datos)
--      2026-07-11 -> baja/2026 | 2026-11-15 -> alta/2026 (inicio inclusive)
--      2027-03-14 -> alta/2026 (ultimo dia) | 2027-03-15 -> baja/2027 (fin exclusive)
INSERT INTO _smoke_res
SELECT 8, 'Sm8_resolucion_bordes',
  CASE WHEN
    (SELECT temporada_clave||'/'||anio FROM temporada_vigencia
      WHERE DATE '2026-07-11' >= fecha_in AND DATE '2026-07-11' < fecha_out_excl) = 'baja/2026'
    AND (SELECT temporada_clave||'/'||anio FROM temporada_vigencia
          WHERE DATE '2026-11-15' >= fecha_in AND DATE '2026-11-15' < fecha_out_excl) = 'alta/2026'
    AND (SELECT temporada_clave||'/'||anio FROM temporada_vigencia
          WHERE DATE '2027-03-14' >= fecha_in AND DATE '2027-03-14' < fecha_out_excl) = 'alta/2026'
    AND (SELECT temporada_clave||'/'||anio FROM temporada_vigencia
          WHERE DATE '2027-03-15' >= fecha_in AND DATE '2027-03-15' < fecha_out_excl) = 'baja/2027'
    -- unicidad: ninguna fecha resuelve a mas de una temporada
    AND (SELECT COUNT(*) FROM temporada_vigencia
          WHERE DATE '2026-11-15' >= fecha_in AND DATE '2026-11-15' < fecha_out_excl) = 1
  THEN 'PASS - bordes inclusive/exclusive correctos, resolucion unica'
  ELSE 'FAIL' END;

-- Sm9: hardening no degradado + fingerprint estructural B2A intacto
INSERT INTO _smoke_res
SELECT 9, 'Sm9_hardening_y_estructura',
  CASE WHEN
    (SELECT COUNT(*) FROM information_schema.role_table_grants
       WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                            'overrides_precio','cotizaciones_precio','precios_auditoria')
         AND grantee IN ('anon','authenticated','service_role','PUBLIC')) = 0
    AND (SELECT COUNT(*) FROM pg_class WHERE relrowsecurity AND relname IN
         ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
          'overrides_precio','cotizaciones_precio','precios_auditoria')) = 0
    AND (WITH cols AS (
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
         SELECT md5(string_agg(line, E'\n' ORDER BY line)) FROM todo) = 'da52a16c045689523a5f1f113f513a87'
  THEN 'PASS - hardening intacto + fingerprint B2A sin cambios'
  ELSE 'FAIL - hardening degradado o estructura modificada' END;

-- Resultado (ultimo result set)
SELECT sid, resultado FROM _smoke_res ORDER BY orden;

COMMIT;
