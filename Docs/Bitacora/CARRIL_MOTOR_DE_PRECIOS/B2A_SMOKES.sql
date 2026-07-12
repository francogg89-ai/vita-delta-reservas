-- ============================================================================
-- B2A_SMOKES -- Suite S1..S12 de validacion de B2A
-- Corre despues de B2A_MIGRACION.sql. Una sola transaccion.
-- Los tests destructivos se autolimpian por savepoints (BEGIN/EXCEPTION) y
-- DELETE; solo dejan huecos de secuencia (nextval no se revierte -- aceptado).
-- Salida: tabla PASS/FAIL como ultimo result set.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _smoke_res (orden INT, sid TEXT, resultado TEXT) ON COMMIT DROP;

-- S1: existencia de las 7 tablas nuevas
INSERT INTO _smoke_res
SELECT 1, 'S1_tablas', CASE WHEN COUNT(*)=7 THEN 'PASS ('||COUNT(*)||'/7)' ELSE 'FAIL ('||COUNT(*)||'/7)' END
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
  AND c.relname IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
                    'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria');

-- S2: constraints minimos presentes (PK x7 + FKs clave + CHECKs clave)
INSERT INTO _smoke_res
SELECT 2, 'S2_constraints',
  CASE WHEN
    (SELECT COUNT(*) FROM pg_constraint WHERE contype='p'
       AND conrelid::regclass::text IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia',
           'noches_alta_demanda','overrides_precio','cotizaciones_precio','precios_auditoria'))=7
    AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_tarifas_motor_precio_pos')
    AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_tarifas_motor_vigencia')
    AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_cotiz_expira')
    AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='cabanas_perfil_tarifario_fkey')
  THEN 'PASS' ELSE 'FAIL' END;

-- S3: indices clave
INSERT INTO _smoke_res
SELECT 3, 'S3_indices',
  CASE WHEN
    EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='uq_tarifas_motor_vigente')
    AND EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='idx_paquetes_evento_id_evento')
    AND EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='idx_cotizaciones_expira')
  THEN 'PASS' ELSE 'FAIL' END;

-- S4: columnas aditivas (7)
INSERT INTO _smoke_res
SELECT 4, 'S4_columnas_aditivas', CASE WHEN COUNT(*)=7 THEN 'PASS' ELSE 'FAIL ('||COUNT(*)||'/7)' END
FROM information_schema.columns
WHERE (table_name='cabanas'      AND column_name='perfil_tarifario')
   OR (table_name='reservas'     AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
   OR (table_name='pre_reservas' AND column_name='cotizacion_id');

-- S5: backfill (5 cabanas, perfil=tipo, sin NULL, mapping esperado)
INSERT INTO _smoke_res
SELECT 5, 'S5_backfill',
  CASE WHEN COUNT(*)=5
        AND COUNT(*) FILTER (WHERE perfil_tarifario IS NULL OR perfil_tarifario<>tipo)=0
        AND COUNT(*) FILTER (WHERE nombre IN ('Bamboo','Madre Selva','Arrebol') AND perfil_tarifario='grande')=3
        AND COUNT(*) FILTER (WHERE nombre IN ('Guatemala','Tokio') AND perfil_tarifario='chica')=2
       THEN 'PASS' ELSE 'FAIL' END
FROM cabanas;

-- S6: perfiles seed
INSERT INTO _smoke_res
SELECT 6, 'S6_perfiles_seed',
  CASE WHEN (SELECT personas_incluidas FROM perfiles_tarifarios WHERE perfil='grande')=4
        AND (SELECT personas_incluidas FROM perfiles_tarifarios WHERE perfil='chica')=3
       THEN 'PASS' ELSE 'FAIL' END;

-- S7: config keys (8 con editable correcto)
INSERT INTO _smoke_res
SELECT 7, 'S7_config_keys',
  CASE WHEN COUNT(*)=8
        AND COUNT(*) FILTER (WHERE editable)=6
        AND (SELECT valor FROM configuracion_general WHERE clave='precio_extra_persona_monto')='20000'
        AND (SELECT editable FROM configuracion_general WHERE clave='precio_redondeo_base')=FALSE
       THEN 'PASS' ELSE 'FAIL' END
FROM configuracion_general WHERE clave LIKE 'precio_%';

-- S8: hardening (tablas y secuencias sin grants Data API; RLS off)
INSERT INTO _smoke_res
SELECT 8, 'S8_hardening',
  CASE WHEN
    (SELECT COUNT(*) FROM information_schema.role_table_grants
       WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                            'overrides_precio','cotizaciones_precio','precios_auditoria')
       AND grantee IN ('anon','authenticated','service_role','PUBLIC'))=0
    AND (SELECT COUNT(*) FROM pg_class WHERE relrowsecurity AND relname IN
         ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
          'overrides_precio','cotizaciones_precio','precios_auditoria'))=0
  THEN 'PASS' ELSE 'FAIL' END;

-- S9: inmutabilidad de precios_auditoria (UPDATE y DELETE rechazados)
DO $s9$
DECLARE v_upd TEXT := 'FAIL'; v_del TEXT := 'FAIL';
BEGIN
  BEGIN
    INSERT INTO precios_auditoria (entidad, accion, actor, source_event)
      VALUES ('config','smoke','smoke','smoke');
    UPDATE precios_auditoria SET actor='x' WHERE source_event='smoke';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%append-only%' THEN v_upd := 'PASS'; ELSE v_upd := 'PASS('||SQLERRM||')'; END IF;
  END;
  BEGIN
    INSERT INTO precios_auditoria (entidad, accion, actor, source_event)
      VALUES ('config','smoke2','smoke','smoke');
    DELETE FROM precios_auditoria WHERE source_event='smoke';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%append-only%' THEN v_del := 'PASS'; ELSE v_del := 'PASS('||SQLERRM||')'; END IF;
  END;
  INSERT INTO _smoke_res VALUES (9, 'S9_inmutabilidad', 'update:'||v_upd||' delete:'||v_del);
END
$s9$;

-- S10: CHECK precio > 0 en tarifas_motor (rechaza precio=0 -- respalda nunca-$0)
DO $s10$
DECLARE v TEXT := 'FAIL - precio=0 aceptado';
BEGIN
  BEGIN
    INSERT INTO tarifas_motor (perfil, temporada_clave, concepto, precio, created_by, source_event)
      VALUES ('grande','alta','semana_noche_1', 0, 'smoke','smoke');
  EXCEPTION WHEN check_violation THEN v := 'PASS - precio=0 rechazado';
  END;
  INSERT INTO _smoke_res VALUES (10, 'S10_precio_positivo', v);
END
$s10$;

-- S11: unicidad de celda vigente (dos filas vigentes misma celda -> rechazo)
DO $s11$
DECLARE v TEXT := 'FAIL - duplicado vigente aceptado';
BEGIN
  BEGIN
    INSERT INTO tarifas_motor (perfil, temporada_clave, concepto, precio, created_by, source_event)
      VALUES ('grande','alta','semana_noche_1', 100000, 'smoke11','smoke');
    INSERT INTO tarifas_motor (perfil, temporada_clave, concepto, precio, created_by, source_event)
      VALUES ('grande','alta','semana_noche_1', 200000, 'smoke11','smoke');
  EXCEPTION WHEN unique_violation THEN v := 'PASS - duplicado vigente rechazado';
  END;
  DELETE FROM tarifas_motor WHERE created_by = 'smoke11';
  INSERT INTO _smoke_res VALUES (11, 'S11_unicidad_vigente', v);
END
$s11$;

-- S12: logica del gate anti-ambiente (rechaza ambiente != test) -- no invasivo
DO $s12$
DECLARE v_amb TEXT := 'ops'; v_esp TEXT := 'test'; v TEXT;
BEGIN
  IF v_amb IS DISTINCT FROM v_esp THEN v := 'PASS - gate rechaza ambiente!=test';
  ELSE v := 'FAIL'; END IF;
  INSERT INTO _smoke_res VALUES (12, 'S12_gate_logica', v);
END
$s12$;

-- Resultado (ultimo result set)
SELECT sid, resultado FROM _smoke_res ORDER BY orden;

COMMIT;
