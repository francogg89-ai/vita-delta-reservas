-- ============================================================================
-- VITA DELTA · 9H · BLOQUE C.3 — SMOKES EFÍMEROS (D-9H-38)
-- Un solo run: BEGIN -> seed mínimo -> smokes -> SELECT veredicto -> ROLLBACK.
-- No persisten filas ni datos de negocio: sin seed permanente, sin DELETE, sin
-- teardown, sin DROP. Las secuencias BIGSERIAL (liquidaciones_periodo,
-- movimientos_socio, revaluaciones) pueden avanzar por diseño — nextval() no hace
-- rollback; el avance no tiene significado contable y no se resetea.
-- Cada smoke negativo captura SQLSTATE + CONSTRAINT + MESSAGE_TEXT y los compara
-- con lo esperado. Para errores de constraint (235xx) distingue el constraint;
-- para errores funcionales (P0001, sin constraint) distingue por fragmento de
-- mensaje, así un P0001 no pasa por la defensa equivocada. OK solo si coinciden.
-- Positivos D-9H-35/37/27 contra el 9G real (8 pasos, 0/3 socios).
-- Tras correr esto, ejecutar 9H_BLOQUE_C3_POSTCHECK.sql (read-only) para
-- confirmar que las 5 tablas quedan sin filas persistidas.
-- ============================================================================
BEGIN;

-- ── GATE DE AMBIENTE (dentro de la tx: si no es test, aborta y revierte) ──
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION '9H C.3 abortado: ambiente != test';
  END IF;
END $gate$;

CREATE TEMP TABLE _c3 (orden text, chequeo text, sqlstate_esp text, sqlstate_obt text,
                       constraint_esp text, constraint_obt text, mensaje_esp text, mensaje_obt text,
                       estado text) ON COMMIT DROP;

-- helper efímero: ejecuta SQL que DEBE fallar; captura SQLSTATE + CONSTRAINT + MESSAGE
-- y confirma que falló por la defensa correcta (constraint exacto o fragmento de mensaje).
CREATE OR REPLACE FUNCTION _c3_smoke(p_orden text,p_chequeo text,p_sql text,
                                     p_state_esp text,p_con_esp text,p_msg_esp text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE st text; con text; msg text; ok boolean; BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO _c3 VALUES (p_orden,p_chequeo,p_state_esp,'(no disparó)',p_con_esp,'-',p_msg_esp,'(no disparó)','FALLO: no disparó');
  EXCEPTION WHEN others THEN
    GET STACKED DIAGNOSTICS st = RETURNED_SQLSTATE, con = CONSTRAINT_NAME, msg = MESSAGE_TEXT;
    ok := (st = p_state_esp)
          AND (p_con_esp = '-' OR COALESCE(NULLIF(con,''),'-') = p_con_esp)
          AND (p_msg_esp = '-' OR position(p_msg_esp in COALESCE(msg,'')) > 0);
    INSERT INTO _c3 VALUES (p_orden,p_chequeo,p_state_esp,st,p_con_esp,COALESCE(NULLIF(con,''),'-'),
                            p_msg_esp,left(COALESCE(msg,''),80),
                            CASE WHEN ok THEN 'OK' ELSE 'FALLO_LATERAL' END);
  END;
END $fn$;

-- ── SEED mínimo (usa las funciones reales; en TEST llaman al 9G real) ──
DO $seed$
DECLARE v_jul bigint; v_ago bigint; v_jun bigint; v_rejul bigint; v_adel bigint; v_rev bigint; v_ret bigint;
BEGIN
  v_jul   := registrar_snapshot_periodo('2026-07-01',0.25,'seed_c3');
  v_ago   := registrar_snapshot_periodo('2026-08-01',0.25,'seed_c3');
  v_jun   := registrar_snapshot_periodo('2026-06-01',0.25,'seed_c3');           -- 0 socios (D-9H-27)
  v_rejul := registrar_snapshot_periodo('2026-07-01',0.25,'seed_c3',v_jul,'re-snap seed');
  v_adel  := registrar_movimiento_manual(2,'2026-09-01','adelanto',-50000,'seed_c3','adelanto seed');
  v_rev   := registrar_reversa(v_adel,'2026-09-02','seed_c3','reversa seed');
  v_ret   := registrar_movimiento_manual(2,'2026-07-31','retribucion_operativo',10000,'seed_c3','retrib seed','2026-07-01');
  CREATE TEMP TABLE _ctx (k text, v bigint) ON COMMIT DROP;
  INSERT INTO _ctx VALUES ('jul',v_jul),('ago',v_ago),('jun',v_jun),('rejul',v_rejul),('adel',v_adel),('rev',v_rev),('ret',v_ret);
END $seed$;

-- ── POSITIVOS en TEST real ──
DO $pos$
DECLARE v_jul bigint; v_jun bigint; nc int; ns int; njc int; njs int;
BEGIN
  SELECT v INTO v_jul FROM _ctx WHERE k='rejul';
  SELECT v INTO v_jun FROM _ctx WHERE k='jun';
  SELECT COUNT(*) INTO nc  FROM liquidacion_cascada WHERE id_liquidacion=v_jul;
  SELECT COUNT(*) INTO ns  FROM liquidacion_socio   WHERE id_liquidacion=v_jul;
  SELECT COUNT(*) INTO njc FROM liquidacion_cascada WHERE id_liquidacion=v_jun;
  SELECT COUNT(*) INTO njs FROM liquidacion_socio   WHERE id_liquidacion=v_jun;
  INSERT INTO _c3 VALUES ('0.010','POSITIVO julio: cascada congela 8 pasos (D-9H-35)','-','-','-','-','-','-', CASE WHEN nc=8 THEN 'OK' ELSE 'FALLO(c='||nc||')' END);
  INSERT INTO _c3 VALUES ('0.020','POSITIVO julio: liquidacion_socio congela 3 (D-9H-37)','-','-','-','-','-','-', CASE WHEN ns=3 THEN 'OK' ELSE 'FALLO(s='||ns||')' END);
  INSERT INTO _c3 VALUES ('0.030','POSITIVO junio: 8 cascada y 0 socios (D-9H-27)','-','-','-','-','-','-', CASE WHEN njc=8 AND njs=0 THEN 'OK' ELSE 'FALLO(c='||njc||',s='||njs||')' END);
END $pos$;

-- ── SMOKES NEGATIVOS (cada uno DEBE fallar por su defensa: constraint o fragmento) ──
DO $run$
BEGIN
  -- 1. Inmutabilidad (trigger D-9H-15 -> P0001, fragmento 'append-only')
  PERFORM _c3_smoke('1.010','UPDATE liquidaciones bloqueado',     $q$ UPDATE liquidaciones_periodo SET pct_operativo=0.5 WHERE id_liquidacion=(SELECT v FROM _ctx WHERE k='ago') $q$,'P0001','-','append-only');
  PERFORM _c3_smoke('1.020','DELETE movimientos bloqueado',       $q$ DELETE FROM movimientos_socio WHERE id_movimiento=(SELECT v FROM _ctx WHERE k='adel') $q$,'P0001','-','append-only');
  PERFORM _c3_smoke('1.030','TRUNCATE bloqueado',                 $q$ TRUNCATE liquidacion_socio $q$,'P0001','-','append-only');
  -- 2. Cadena (constraints; mensaje '-')
  PERFORM _c3_smoke('2.010','doble-raíz rechazada',               $q$ INSERT INTO liquidaciones_periodo (periodo,pct_operativo,id_liquidacion_supersede,creado_por) VALUES ('2026-07-01',0.25,NULL,'smk') $q$,'23505','uq_liq_una_raiz_por_periodo','-');
  PERFORM _c3_smoke('2.020','fork rechazado',                     $q$ INSERT INTO liquidaciones_periodo (periodo,pct_operativo,id_liquidacion_supersede,creado_por) VALUES ('2026-07-01',0.25,(SELECT v FROM _ctx WHERE k='jul'),'smk') $q$,'23505','uq_liq_sin_fork','-');
  PERFORM _c3_smoke('2.030','auto-supersede rechazado',           $q$ INSERT INTO liquidaciones_periodo (id_liquidacion,periodo,pct_operativo,id_liquidacion_supersede,creado_por) VALUES (999999,'2026-07-01',0.25,999999,'smk') $q$,'23514','chk_liq_no_auto_supersede','-');
  PERFORM _c3_smoke('2.040','cross-período rechazado',            $q$ INSERT INTO liquidaciones_periodo (periodo,pct_operativo,id_liquidacion_supersede,creado_por,comentario) VALUES ('2026-08-01',0.25,(SELECT v FROM _ctx WHERE k='rejul'),'smk','cross') $q$,'23503','fk_liq_supersede_mismo_periodo','-');
  -- 3. Re-snapshot / pct (función -> P0001, fragmento)
  PERFORM _c3_smoke('3.010','re-snap sin supersede rechazado',    $q$ SELECT registrar_snapshot_periodo('2026-07-01',0.25,'smk') $q$,'P0001','-','ya tiene foto vigente');
  PERFORM _c3_smoke('3.020','re-snap a no-cola rechazado',        $q$ SELECT registrar_snapshot_periodo('2026-07-01',0.25,'smk',(SELECT v FROM _ctx WHERE k='jul'),'viejo') $q$,'P0001','-','ya tiene foto vigente');
  PERFORM _c3_smoke('3.030','pct inválido rechazado',             $q$ SELECT registrar_snapshot_periodo('2026-10-01',1.5,'smk') $q$,'P0001','-','pct_operativo invalido');
  -- 4. Reversa (constraints)
  PERFORM _c3_smoke('4.010','doble-reversa rechazada',            $q$ SELECT registrar_reversa((SELECT v FROM _ctx WHERE k='adel'),'2026-09-03','smk','doble') $q$,'23505','uq_mov_reversa_unica','-');
  PERFORM _c3_smoke('4.020','reversa cross-socio rechazada',      $q$ INSERT INTO movimientos_socio (id_socio,fecha,tipo,monto,comentario,creado_por,id_movimiento_revertido) VALUES (1,'2026-09-03','reversa',50000,'cross','smk',(SELECT v FROM _ctx WHERE k='ret')) $q$,'23503','fk_mov_reversa_mismo_socio','-');
  -- 5. Conversión (función -> P0001, fragmento)
  PERFORM _c3_smoke('5.010','conversión cross-socio rechazada',   $q$ SELECT registrar_revaluacion(1,'2026-09-03',1000,10000,'parcial','smk',(SELECT v FROM _ctx WHERE k='adel'),'cross') $q$,'P0001','-','no pertenece al socio');
  PERFORM _c3_smoke('5.020','conversión a tipo incompatible (D-9H-34)', $q$ SELECT registrar_revaluacion(2,'2026-09-03',1000,5000,'parcial','smk',(SELECT v FROM _ctx WHERE k='ret'),'a retrib') $q$,'P0001','-','solo se liga a retiro/adelanto');
  -- 6. Retiro: guard saldo + escala (función -> P0001, fragmento)
  PERFORM _c3_smoke('6.010','guard saldo retiro (D-9H-25)',       $q$ SELECT registrar_retiro(2,'2026-09-03',999999999,'efectivo','smk',NULL) $q$,'P0001','-','saldo insuficiente');
  PERFORM _c3_smoke('6.020','escala sub-centavo (D-9H-36)',       $q$ SELECT registrar_retiro(2,'2026-09-03',100.005,'efectivo','smk',NULL) $q$,'P0001','-','excede 2 decimales');
  -- 7. Coherencia saldo_final (CHECK; INSERT crudo en junio que no tiene socios)
  PERFORM _c3_smoke('7.010','coherencia saldo_final rechazada',   $q$ INSERT INTO liquidacion_socio (id_liquidacion,id_socio,saldo_bruto,gastos_d,gastos_e,saldo_final,desembolsado_periodo) VALUES ((SELECT v FROM _ctx WHERE k='jun'),1,100,0,0,999,0) $q$,'23514','chk_socio_saldo_final_coherente','-');
END $run$;

-- ── VEREDICTO (último result set antes del ROLLBACK) ──
SELECT orden, chequeo, sqlstate_esp, sqlstate_obt, constraint_esp, constraint_obt, mensaje_esp, mensaje_obt, estado
FROM _c3 ORDER BY orden;

DO $ver$ DECLARE t int; n int; BEGIN
  SELECT COUNT(*), COUNT(*) FILTER (WHERE estado<>'OK') INTO t,n FROM _c3;
  RAISE NOTICE 'C.3 VEREDICTO: % chequeos, % no-OK. Filas revertidas por ROLLBACK; secuencias pueden avanzar (sin significado contable).', t, n;
END $ver$;

ROLLBACK;
