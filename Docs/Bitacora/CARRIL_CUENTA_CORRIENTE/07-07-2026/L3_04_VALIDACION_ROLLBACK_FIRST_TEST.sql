-- ============================================================================
-- L3_04_VALIDACION_ROLLBACK_FIRST_TEST.sql   (TRANSACCIONAL; termina en ROLLBACK)
-- Congela fotos EFIMERAS con la funcion extendida real, lee L3-detalle y
-- L3-acumulados, asevera invariantes y hace ROLLBACK. NADA persiste (salvo el
-- hueco de secuencia por nextval, que PostgreSQL no revierte: benigno, D-doc).
-- TEST-only (gate). Las aserciones son bloques DO que abortan (RAISE) si fallan;
-- si todo pasa, la ultima grilla muestra la evidencia y luego ROLLBACK.
--
-- v2: TODO ocurre dentro de la transaccion. El holder _l3_lab se crea DESPUES
-- del gate, con ON COMMIT DROP (y ademas el ROLLBACK lo deshace). No hay
-- CREATE TEMP ni INSERT antes del BEGIN, ni DROP TABLE final.
--
-- Mes de laboratorio: se define UNA sola vez en _l3_lab (abajo). Debe ser un mes
-- SIN foto vigente en TEST y para el cual registrar pueda resolver participacion
-- (dentro de la vigencia configurada). Default: 2026-12-01 (libre; TEST tiene
-- vigentes en 2026-07/08/11). Editar ahi si hace falta.
-- ============================================================================
BEGIN;

-- gate ambiente (primero de todo)
DO $gate$ BEGIN
  IF (SELECT valor FROM configuracion_general WHERE clave='ambiente') IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION 'GATE TEST-only: ambiente actual = %', COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(sin clave)');
  END IF;
END $gate$;

-- holder del mes de laboratorio (dentro de la txn; se deshace al ROLLBACK)
CREATE TEMP TABLE _l3_lab(mes date) ON COMMIT DROP;
INSERT INTO _l3_lab VALUES (DATE '2026-12-01');   -- <<< EDITAR AQUI el mes de lab

-- setup guard: el mes de lab NO debe tener foto vigente previa
DO $$ BEGIN
  IF liquidacion_vigente((SELECT mes FROM _l3_lab)) IS NOT NULL THEN
    RAISE EXCEPTION 'SETUP: el mes de lab % ya tiene foto vigente; edita _l3_lab a un mes libre', (SELECT mes FROM _l3_lab);
  END IF;
END $$;

-- (1) primer freeze: foto V1 (raiz) via la funcion extendida real
DO $$ BEGIN
  PERFORM registrar_snapshot_periodo((SELECT mes FROM _l3_lab), 0.25, 'harness_l3', NULL, 'efimera V1 L3');
END $$;

-- (2) L3-detalle sobre V1: detalle COMPLETO
DO $$
DECLARE r jsonb; v_id bigint; v_ncab int;
BEGIN
  v_id := liquidacion_vigente((SELECT mes FROM _l3_lab));
  IF v_id IS NULL THEN RAISE EXCEPTION 'FALLO: no se congelo foto V1'; END IF;
  r := cuenta_corriente_historico((SELECT mes FROM _l3_lab));
  SELECT count(*) INTO v_ncab FROM cabanas;

  IF (r->>'sin_foto')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'FALLO: sin_foto<>false en V1'; END IF;
  IF (r->>'detalle_disponible')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FALLO: detalle_disponible<>true (%)', r->>'detalle_disponible'; END IF;
  IF (r->>'detalle_motivo') IS NOT NULL THEN RAISE EXCEPTION 'FALLO: detalle_motivo no nulo (%)', r->>'detalle_motivo'; END IF;
  IF jsonb_array_length(r->'participacion') <> v_ncab THEN RAISE EXCEPTION 'FALLO: participacion=% <> cabanas=%', jsonb_array_length(r->'participacion'), v_ncab; END IF;
  IF jsonb_array_length(r->'cascada') <> 8 THEN RAISE EXCEPTION 'FALLO: cascada=% (esperado 8)', jsonb_array_length(r->'cascada'); END IF;
  IF jsonb_array_length(r->'socios') = 0 THEN RAISE EXCEPTION 'FALLO: socios vacio en V1'; END IF;
  IF jsonb_array_length(r->'matriz_por_socio') = 0 THEN RAISE EXCEPTION 'FALLO: matriz_por_socio vacia (deriva de participacion)'; END IF;
  IF jsonb_typeof(r->'retribucion_operativo') <> 'object' THEN RAISE EXCEPTION 'FALLO: retribucion_operativo no es objeto'; END IF;
  IF (r#>>'{cabecera,id_liquidacion}')::bigint <> v_id THEN RAISE EXCEPTION 'FALLO: cabecera<>vigente'; END IF;
  IF (r#>>'{cabecera,linaje,es_raiz}')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'FALLO: V1 deberia ser raiz'; END IF;
  IF (r#>>'{cabecera,linaje,id_liquidacion_supersede}') IS NOT NULL THEN RAISE EXCEPTION 'FALLO: V1 raiz con supersede no nulo'; END IF;
  RAISE NOTICE 'OK (2) V1 detalle completo: participacion=%, cascada=8, socios/matriz presentes, es_raiz=true', v_ncab;
END $$;

-- (3) segundo freeze: foto V2 que SUPERSEDE a V1 -> supersesion + no duplicacion
DO $$
DECLARE v1 bigint; v2 bigint; r jsonb;
BEGIN
  v1 := liquidacion_vigente((SELECT mes FROM _l3_lab));
  PERFORM registrar_snapshot_periodo((SELECT mes FROM _l3_lab), 0.25, 'harness_l3', v1, 'efimera V2 supersede');
  v2 := liquidacion_vigente((SELECT mes FROM _l3_lab));
  IF v2 IS NULL OR v2 = v1 THEN RAISE EXCEPTION 'FALLO: supersesion no cambio la vigente (v1=%, v2=%)', v1, v2; END IF;

  r := cuenta_corriente_historico((SELECT mes FROM _l3_lab));
  IF (r#>>'{cabecera,id_liquidacion}')::bigint <> v2 THEN RAISE EXCEPTION 'FALLO: L3 no lee la nueva vigente V2 (leyo %)', r#>>'{cabecera,id_liquidacion}'; END IF;
  IF (r#>>'{cabecera,linaje,id_liquidacion_supersede}')::bigint <> v1 THEN RAISE EXCEPTION 'FALLO: linaje.supersede<>V1'; END IF;
  IF (r#>>'{cabecera,linaje,es_raiz}')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'FALLO: V2 no deberia ser raiz'; END IF;
  RAISE NOTICE 'OK (3) supersesion: v1=% superseded, v2=% vigente y leida por L3', v1, v2;
END $$;

-- (4) L3-acumulados: no duplicacion de superseded, retiros_mes coherente, piso 0/0
DO $$
DECLARE a jsonb; v2 bigint; n_lab int; bad int;
BEGIN
  v2 := liquidacion_vigente((SELECT mes FROM _l3_lab));
  a := cuenta_corriente_historico_acumulados();

  SELECT count(*) INTO n_lab FROM jsonb_array_elements(a->'evolucion') e
    WHERE (e->>'periodo') = (SELECT mes::text FROM _l3_lab);
  IF n_lab <> 1 THEN RAISE EXCEPTION 'FALLO: mes de lab aparece % veces en evolucion (esperado 1; superseded duplicada?)', n_lab; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(a->'evolucion') e WHERE (e->>'id_liquidacion')::bigint = v2)
     THEN RAISE EXCEPTION 'FALLO: la vigente V2 no esta en evolucion'; END IF;

  IF EXISTS (SELECT 1 FROM jsonb_array_elements(a->'evolucion') e WHERE NOT (e ? 'retiros_mes'))
     THEN RAISE EXCEPTION 'FALLO: falta retiros_mes en alguna entrada de evolucion'; END IF;
  SELECT count(*) INTO bad FROM jsonb_array_elements(a->'evolucion') e
    WHERE (e->>'retiros_mes')::numeric IS DISTINCT FROM COALESCE((
      SELECT SUM(m.monto) FROM movimientos_socio m
      WHERE m.tipo='retiro' AND m.fecha >= (e->>'periodo')::date
        AND m.fecha < ((e->>'periodo')::date + INTERVAL '1 month')),0);
  IF bad > 0 THEN RAISE EXCEPTION 'FALLO: % entradas con retiros_mes incoherente vs mayor', bad; END IF;

  IF (a#>>'{meta,fotos_pre_piso}')::int <> 0 THEN RAISE EXCEPTION 'FALLO: fotos_pre_piso=% (esperado 0)', a#>>'{meta,fotos_pre_piso}'; END IF;
  IF (a#>>'{meta,movimientos_pre_piso}')::int <> 0 THEN RAISE EXCEPTION 'FALLO: movimientos_pre_piso=% (esperado 0)', a#>>'{meta,movimientos_pre_piso}'; END IF;

  RAISE NOTICE 'OK (4) acumulados: mes de lab x1 en evolucion (V2=%), retiros_mes coherente, piso 0/0', v2;
END $$;

-- (5) evidencia visible (ultima grilla antes del ROLLBACK)
SELECT
  'TODAS LAS ASERCIONES OK (ver mensajes NOTICE)'                    AS resultado,
  (SELECT mes FROM _l3_lab)                                          AS mes_lab,
  cuenta_corriente_historico((SELECT mes FROM _l3_lab))              AS l3_detalle_efimero,
  cuenta_corriente_historico_acumulados()                           AS l3_acumulados_efimero;

ROLLBACK;
