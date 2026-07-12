-- ============================================================================
-- B3_SMOKES -- Suite del motor de precios (v2 -- dataset-agnostica)
-- Corre despues de B3_FUNCIONES.sql. Una transaccion, COMMIT final.
--
-- ROBUSTEZ ANTE DATASET NO NEUTRO (leccion de la 1a corrida en TEST):
--  1) Las REGLAS se asertan contra `restricciones[]` (ACUMULATIVO), no contra
--     `motivo_no_reservable` (que es "el primero gana": la disponibilidad real
--     tiene prioridad y enmascara al resto). Sm38 testea esa precedencia.
--  2) Las ventanas de fechas NO se hardcodean: se BUSCAN en runtime.
--     - Buscador A: ventana vendible (para congelar).
--     - Buscador B: ventana limpia de reservas Y bloqueos (para fixtures).
--     `reservas` y `bloqueos` tienen EXCLUSION CONSTRAINTS: insertar un fixture
--     que solape con datos reales de TEST aborta la transaccion entera.
--
-- Fixtures marcados con source_event='smoke_b3'; teardown explicito.
-- Sm37 verifica CERO RESIDUOS. Las secuencias avanzan (nextval no se revierte).
-- Salida: tabla PASS/FAIL como ultimo result set.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _r (orden INT, sid TEXT, resultado TEXT) ON COMMIT DROP;
CREATE TEMP TABLE _fix (k TEXT, v TEXT) ON COMMIT DROP;
CREATE TEMP TABLE _oraculo (t TEXT, n BIGINT) ON COMMIT DROP;

INSERT INTO _oraculo
SELECT 'reservas', COUNT(*) FROM reservas
UNION ALL SELECT 'pre_reservas', COUNT(*) FROM pre_reservas
UNION ALL SELECT 'bloqueos', COUNT(*) FROM bloqueos
UNION ALL SELECT 'tarifas_motor', COUNT(*) FROM tarifas_motor
UNION ALL SELECT 'cotizaciones_precio', COUNT(*) FROM cotizaciones_precio;

-- ---------------------------------------------------------------------------
-- BUSCADOR A -- ventana VENDIBLE de 3 noches (lun->jue) para el congelamiento.
--   Sin finde (R3 no aplica), < 10 noches (R4 no aplica), 2 personas (sin extras).
-- ---------------------------------------------------------------------------
DO $findA$
DECLARE v_cab BIGINT; v_d DATE; v_q JSONB; v_found BOOLEAN := FALSE;
BEGIN
  FOR v_d IN SELECT d::DATE FROM generate_series(DATE '2026-08-03', DATE '2026-09-28', INTERVAL '7 days') d
  LOOP
    FOR v_cab IN SELECT c.id_cabana FROM cabanas c WHERE c.activa ORDER BY c.id_cabana
    LOOP
      v_q := precios_cotizar(jsonb_build_object(
        'id_cabana', v_cab, 'fecha_in', v_d, 'fecha_out', v_d + 3,
        'personas', 2, 'canal', 'web', 'modo', 'online'));
      IF COALESCE((v_q->>'ok')::BOOLEAN, FALSE)
         AND COALESCE((v_q->>'disponible')::BOOLEAN, FALSE)
         AND COALESCE((v_q->>'reservable_online')::BOOLEAN, FALSE) THEN
        INSERT INTO _fix VALUES ('free_cab', v_cab::TEXT), ('free_in', v_d::TEXT), ('free_out', (v_d + 3)::TEXT);
        v_found := TRUE; EXIT;
      END IF;
    END LOOP;
    EXIT WHEN v_found;
  END LOOP;
  IF NOT v_found THEN
    INSERT INTO _fix VALUES ('free_cab', NULL), ('free_in', NULL), ('free_out', NULL);
  END IF;
END
$findA$;

-- ---------------------------------------------------------------------------
-- BUSCADOR B -- ventana LIMPIA de 16 noches (lunes base, temporada baja 2029):
--   sin reservas confirmadas/activas NI bloqueos activos que solapen.
--   Necesaria porque reservas y bloqueos tienen EXCLUSION CONSTRAINTS.
--   Layout de fixtures dentro de la ventana:
--     reserva : [base+1, base+3)   -> ocupa noches base+1, base+2
--     bloqueo : [base+8, base+10)  -> ocupa noches base+8, base+9
--     (no se solapan entre si)
-- ---------------------------------------------------------------------------
DO $findB$
DECLARE v_cab BIGINT; v_d DATE; v_found BOOLEAN := FALSE;
BEGIN
  FOR v_d IN SELECT d::DATE FROM generate_series(DATE '2029-04-02', DATE '2029-08-27', INTERVAL '7 days') d
  LOOP
    FOR v_cab IN SELECT c.id_cabana FROM cabanas c WHERE c.activa ORDER BY c.id_cabana
    LOOP
      IF NOT EXISTS (
            SELECT 1 FROM bloqueos b
            WHERE b.activo = TRUE
              AND (b.id_cabana = v_cab OR b.id_cabana IS NULL)
              AND daterange(b.fecha_desde, b.fecha_hasta, '[)') && daterange(v_d, v_d + 16, '[)'))
         AND NOT EXISTS (
            SELECT 1 FROM reservas r
            WHERE r.id_cabana = v_cab
              AND r.estado IN ('confirmada','activa')
              AND daterange(r.fecha_checkin, r.fecha_checkout, '[)') && daterange(v_d, v_d + 16, '[)'))
         AND NOT EXISTS (
            SELECT 1 FROM pre_reservas pr
            WHERE pr.id_cabana = v_cab
              AND ((pr.estado = 'pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado = 'pago_en_revision')
              AND daterange(pr.fecha_in, pr.fecha_out, '[)') && daterange(v_d, v_d + 16, '[)'))
      THEN
        INSERT INTO _fix VALUES ('bloq_cab', v_cab::TEXT), ('bloq_base', v_d::TEXT);
        v_found := TRUE; EXIT;
      END IF;
    END LOOP;
    EXIT WHEN v_found;
  END LOOP;
  IF NOT v_found THEN
    INSERT INTO _fix VALUES ('bloq_cab', NULL), ('bloq_base', NULL);
  END IF;
END
$findB$;

-- Sm0 -- PRECONDICIONES: buscadores OK + ventanas canonicas 2026 sin eventos reales
INSERT INTO _r
SELECT 0, 'Sm0_precondiciones',
  CASE
    WHEN (SELECT v FROM _fix WHERE k='free_cab') IS NULL
      THEN 'FAIL - Buscador A: sin ventana vendible (ago-sep 2026). Ampliar rango.'
    WHEN (SELECT v FROM _fix WHERE k='bloq_cab') IS NULL
      THEN 'FAIL - Buscador B: sin ventana limpia (2029). Ampliar rango.'
    WHEN EXISTS (SELECT 1 FROM eventos_especiales e
                 WHERE e.activa AND COALESCE(e.source_event,'') <> 'smoke_b3'
                   AND e.fecha_desde < DATE '2026-11-23' AND (e.fecha_hasta + 1) > DATE '2026-07-13')
      THEN 'FAIL - hay evento REAL activo en las ventanas canonicas (2026-07-13..11-22): mover fechas de Sm1-Sm3/Sm18-Sm23'
    ELSE 'PASS - ventana vendible=' || (SELECT v FROM _fix WHERE k='free_in')
         || ' | ventana limpia=cab' || (SELECT v FROM _fix WHERE k='bloq_cab')
         || '@' || (SELECT v FROM _fix WHERE k='bloq_base')
  END;

-- ===========================================================================
-- Sm1 -- ORDINALES: canonico lunes->lunes (2026-07-13..2026-07-20, BAJA)
-- ===========================================================================
INSERT INTO _r
SELECT 1, 'Sm1_ordinal_canonico',
  CASE WHEN string_agg(n->>'concepto', '|' ORDER BY (n->>'fecha')::DATE) =
    'semana_noche_1|semana_noche_2|semana_noche_3|semana_noche_4|alta_demanda_noche_1|alta_demanda_noche_2|semana_noche_5plus'
  THEN 'PASS - lun/mar/mie/jue semana 1-4; vie/sab AD 1-2; dom semana_5plus'
  ELSE 'FAIL - ' || string_agg(n->>'concepto', '|' ORDER BY (n->>'fecha')::DATE) END
FROM jsonb_array_elements(
  precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":2,"modo":"online"}'::JSONB)
  -> 'desglose_noches') n;

-- Fixture: evento con paquete jue->dom (noches 16,17,18) para perfil grande
INSERT INTO eventos_especiales (nombre, fecha_desde, fecha_hasta, activa, source_event)
VALUES ('SMOKE_B3 Evento', '2026-07-16', '2026-07-18', TRUE, 'smoke_b3');
INSERT INTO _fix VALUES ('id_evento', (SELECT id_evento::TEXT FROM eventos_especiales WHERE source_event='smoke_b3'));
INSERT INTO paquetes_evento (id_evento, tipo_cabana, nombre_paquete, fecha_in, fecha_out, precio_total, personas_max, activo)
VALUES ((SELECT v::BIGINT FROM _fix WHERE k='id_evento'), 'grande', 'SMOKE_B3 Paquete', '2026-07-16', '2026-07-19', 500000, 5, TRUE);

-- Sm2 -- EVENTO NO REINICIA ORDINAL (D-PR-10) -- ejemplo de Franco
INSERT INTO _r
SELECT 2, 'Sm2_evento_no_reinicia_ordinal',
  CASE WHEN string_agg(n->>'concepto', '|' ORDER BY (n->>'fecha')::DATE) =
    'semana_noche_1|semana_noche_2|semana_noche_3|semana_noche_4|semana_noche_5plus|semana_noche_5plus'
  THEN 'PASS - tras el paquete el ordinal sigue en semana_noche_4 (no reinicia)'
  ELSE 'FAIL - ' || string_agg(n->>'concepto', '|' ORDER BY (n->>'fecha')::DATE) END
FROM jsonb_array_elements(
  precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-22","personas":2,"modo":"online"}'::JSONB)
  -> 'desglose_noches') n;

-- Sm3 -- CRUCE DE TEMPORADA (D-PR-09)
INSERT INTO _r
SELECT 3, 'Sm3_cruce_temporada',
  CASE WHEN string_agg((n->>'concepto')||':'||(n->>'temporada'), '|' ORDER BY (n->>'fecha')::DATE) =
    'semana_noche_1:baja|alta_demanda_noche_1:baja|alta_demanda_noche_2:baja|semana_noche_2:alta|semana_noche_3:alta|semana_noche_4:alta'
  THEN 'PASS - ordinal continuo cruzando 15/11; cada noche con su temporada'
  ELSE 'FAIL - ' || string_agg((n->>'concepto')||':'||(n->>'temporada'), '|' ORDER BY (n->>'fecha')::DATE) END
FROM jsonb_array_elements(
  precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-12","fecha_out":"2026-11-18","personas":2,"modo":"online"}'::JSONB)
  -> 'desglose_noches') n;

-- Sm4 -- BORDE EXCLUSIVE de temporada
INSERT INTO _r
SELECT 4, 'Sm4_borde_temporada_exclusive',
  CASE WHEN precios_resolver_temporada('2026-11-15') = 'alta'
        AND precios_resolver_temporada('2027-03-14') = 'alta'
        AND precios_resolver_temporada('2027-03-15') = 'baja'
       THEN 'PASS - inicio inclusive / fin exclusive' ELSE 'FAIL' END;

-- Sm5 -- temporada_no_resuelta
INSERT INTO _r
SELECT 5, 'Sm5_temporada_no_resuelta',
  CASE WHEN (precios_cotizar('{"id_cabana":1,"fecha_in":"2031-01-05","fecha_out":"2031-01-07","personas":2}'::JSONB)->>'error')
            = 'temporada_no_resuelta'
       THEN 'PASS - error controlado (ok=false)' ELSE 'FAIL' END;

-- Sm6 -- fecha_out EXCLUSIVE: 13->20 son 7 noches
INSERT INTO _r
SELECT 6, 'Sm6_fecha_out_exclusive',
  CASE WHEN (precios_disponibilidad_noches(1,'2026-07-13','2026-07-20')->>'noches_total')::INT = 7
        AND (precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":2}'::JSONB)->>'noches_count')::INT = 7
       THEN 'PASS - 7 noches (no 6 ni 8)' ELSE 'FAIL' END;

-- ---------------------------------------------------------------------------
-- Ventana limpia resuelta (Buscador B) -- base = lunes, temporada baja 2029
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _w ON COMMIT DROP AS
SELECT (SELECT v FROM _fix WHERE k='bloq_cab')::BIGINT AS cab,
       (SELECT v FROM _fix WHERE k='bloq_base')::DATE  AS base;

-- Fixture: huesped + reserva [base+1, base+3) -> checkout el dia base+3
INSERT INTO huespedes (nombre, email)
SELECT 'SMOKE_B3 Huesped', 'smoke_b3@example.invalid' FROM _w WHERE cab IS NOT NULL;

INSERT INTO reservas (id_cabana, id_huesped, fecha_checkin, fecha_checkout, hora_checkin, hora_checkout,
                      personas, canal_origen, monto_total, monto_sena, monto_saldo, source_event)
SELECT w.cab, (SELECT MAX(id_huesped) FROM huespedes WHERE nombre='SMOKE_B3 Huesped'),
       w.base + 1, w.base + 3, '14:00', '10:00', 2, 'manual', 100000, 50000, 50000, 'smoke_b3'
FROM _w w WHERE w.cab IS NOT NULL;

-- Sm7 -- checkout_disponible ES VENDIBLE (noche base+3 = dia de checkout)
INSERT INTO _r
SELECT 7, 'Sm7_checkout_disponible_vendible',
  CASE WHEN (SELECT d.estado FROM obtener_disponibilidad_rango(
               (SELECT base + 3 FROM _w), (SELECT base + 4 FROM _w), (SELECT cab FROM _w)) d) = 'checkout_disponible'
        AND (precios_disponibilidad_noches((SELECT cab FROM _w), (SELECT base + 3 FROM _w), (SELECT base + 4 FROM _w))
             ->>'disponible')::BOOLEAN = TRUE
       THEN 'PASS - la noche del dia de checkout se vende' ELSE 'FAIL' END;

-- Sm8 -- OCUPADA no vendible (noche base+1, dentro de la reserva)
INSERT INTO _r
SELECT 8, 'Sm8_ocupada_no_vendible',
  CASE WHEN (q.j->>'disponible')::BOOLEAN = FALSE
        AND (q.j->>'motivo_no_reservable') = 'no_disponible'
       THEN 'PASS - reserva confirmada bloquea' ELSE 'FAIL' END
FROM (SELECT precios_cotizar(jsonb_build_object(
        'id_cabana', (SELECT cab FROM _w), 'fecha_in', (SELECT base + 1 FROM _w),
        'fecha_out', (SELECT base + 2 FROM _w), 'personas', 2, 'modo', 'online')) AS j) q;

-- Fixture: bloqueo [base+8, base+10)
INSERT INTO bloqueos (id_cabana, fecha_desde, fecha_hasta, motivo, creado_por, activo, source_event)
SELECT w.cab, w.base + 8, w.base + 10, 'mantenimiento', 'smoke', TRUE, 'smoke_b3'
FROM _w w WHERE w.cab IS NOT NULL;

-- Sm9 -- R1: el bloqueo NO se pisa, ni en modo manual
INSERT INTO _r
SELECT 9, 'Sm9_bloqueo_no_pisable',
  CASE WHEN (precios_cotizar(jsonb_build_object('id_cabana',(SELECT cab FROM _w),'fecha_in',(SELECT base+8 FROM _w),
               'fecha_out',(SELECT base+9 FROM _w),'personas',2,'modo','online'))->>'disponible')::BOOLEAN = FALSE
        AND (precios_cotizar(jsonb_build_object('id_cabana',(SELECT cab FROM _w),'fecha_in',(SELECT base+8 FROM _w),
               'fecha_out',(SELECT base+9 FROM _w),'personas',2,'modo','manual'))->>'disponible')::BOOLEAN = FALSE
       THEN 'PASS - la disponibilidad real nunca se pisa (R1)' ELSE 'FAIL' END;

-- Sm10 -- EVENTO PARCIAL invalido (restriccion, no motivo)
INSERT INTO _r
SELECT 10, 'Sm10_evento_parcial',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r
                    WHERE r->>'codigo' = 'evento_parcial_no_vendible')
        AND (q.j->>'reservable_online')::BOOLEAN = FALSE
       THEN 'PASS - subrango de paquete rechazado' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-17","fecha_out":"2026-07-19","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm11 -- EVENTO EXACTO: precio = paquete
INSERT INTO _r
SELECT 11, 'Sm11_evento_exacto',
  CASE WHEN (q.j->>'precio_total') = '500000' AND (q.j->>'precio_source') = 'evento_especial'
       THEN 'PASS - paquete completo = 500.000 (evento_especial)' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-16","fecha_out":"2026-07-19","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm12 -- EVENTO + noches extra = mixto
INSERT INTO _r
SELECT 12, 'Sm12_evento_mas_noches',
  CASE WHEN (q.j->>'precio_source') = 'mixto' AND (q.j->>'precio_total') = '1050000'
       THEN 'PASS - 310.000 estandar + 500.000 paquete + 240.000 = 1.050.000' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-22","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm13 -- EVENTO SIN PAQUETE PARA EL PERFIL (D-PR-20)
INSERT INTO _r
SELECT 13, 'Sm13_evento_sin_paquete_perfil',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(
              precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-16","fecha_out":"2026-07-19","personas":2,"modo":"online"}'::JSONB)->'restricciones') r
              WHERE r->>'codigo' = 'evento_sin_paquete_perfil')
        AND (precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-16","fecha_out":"2026-07-19","personas":2,"modo":"online"}'::JSONB)->>'reservable_online')::BOOLEAN = FALSE
        AND (precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-16","fecha_out":"2026-07-19","personas":2,"modo":"manual"}'::JSONB)->>'ok')::BOOLEAN = TRUE
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(
              precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-16","fecha_out":"2026-07-19","personas":2,"modo":"manual"}'::JSONB)->'warnings') w
              WHERE w->>'codigo' = 'evento_sin_paquete_perfil')
       THEN 'PASS - online deriva; manual cotiza estandar con warning' ELSE 'FAIL' END;

-- Sm14 -- EXTRAS OFF
UPDATE configuracion_general SET valor='false' WHERE clave='precio_extra_persona_activo';
INSERT INTO _r
SELECT 14, 'Sm14_extras_off',
  CASE WHEN (precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":5,"modo":"online"}'::JSONB)->>'extra_persona_total') = '0'
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(
              precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":5,"modo":"online"}'::JSONB)->'warnings') w
              WHERE w->>'codigo' = 'recargo_extra_persona')
       THEN 'PASS - switch OFF: sin recargo ni warning' ELSE 'FAIL' END;
UPDATE configuracion_general SET valor='true' WHERE clave='precio_extra_persona_activo';

-- Sm15 -- EXTRAS ON: 1 extra x 20.000 x 7 noches = 140.000
INSERT INTO _r
SELECT 15, 'Sm15_extras_on',
  CASE WHEN (precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":5,"modo":"online"}'::JSONB)->>'extra_persona_total') = '140000'
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(
              precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":5,"modo":"online"}'::JSONB)->'warnings') w
              WHERE w->>'codigo' = 'recargo_extra_persona')
       THEN 'PASS - 1 extra x 20.000 x 7 noches = 140.000 + warning' ELSE 'FAIL' END;

-- Sm16 -- EXTRA SOBRE NOCHES DE EVENTO (D-PR-18): 9 noches (3 de evento) = 180.000
INSERT INTO _r
SELECT 16, 'Sm16_extra_en_evento',
  CASE WHEN (precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-22","personas":5,"modo":"online"}'::JSONB)->>'extra_persona_total') = '180000'
       THEN 'PASS - extra cubre las 9 noches (incl. las 3 del paquete)' ELSE 'FAIL' END;

-- Sm17 -- CHICA incluye 3
INSERT INTO _r
SELECT 17, 'Sm17_extras_chica',
  CASE WHEN (precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-13","fecha_out":"2026-07-15","personas":4,"modo":"online"}'::JSONB)->>'extra_persona_total') = '40000'
        AND (precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-13","fecha_out":"2026-07-15","personas":3,"modo":"online"}'::JSONB)->>'extra_persona_total') = '0'
       THEN 'PASS - chica: 3 incluidas; 4a persona = 1 extra' ELSE 'FAIL' END;

-- Sm18 -- R3 VIERNES SOLO en ALTA (restriccion, no motivo)
INSERT INTO _r
SELECT 18, 'Sm18_R3_viernes_solo',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='bloque_finde_obligatorio')
        AND (q.j->>'reservable_online')::BOOLEAN = FALSE
       THEN 'PASS - viernes solo rechazado en alta' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-20","fecha_out":"2026-11-21","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm19 -- R3 SABADO SOLO en ALTA
INSERT INTO _r
SELECT 19, 'Sm19_R3_sabado_solo',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='bloque_finde_obligatorio')
        AND (q.j->>'reservable_online')::BOOLEAN = FALSE
       THEN 'PASS - sabado solo rechazado en alta' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-21","fecha_out":"2026-11-22","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm20 -- R3 VIE+SAB juntos: la regla NO se dispara (ausencia de restriccion)
INSERT INTO _r
SELECT 20, 'Sm20_R3_vie_sab_juntos',
  CASE WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='bloque_finde_obligatorio')
       THEN 'PASS - vie+sab juntos: R3 no se dispara' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-20","fecha_out":"2026-11-22","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm21 -- R3 SWITCH OFF
UPDATE configuracion_general SET valor='false' WHERE clave='precio_bloque_finde_alta_activo';
INSERT INTO _r
SELECT 21, 'Sm21_R3_switch_off',
  CASE WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='bloque_finde_obligatorio')
       THEN 'PASS - switch OFF: R3 no se dispara (viernes solo vendible)' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-20","fecha_out":"2026-11-21","personas":2,"modo":"online"}'::JSONB) AS j) q;
UPDATE configuracion_general SET valor='true' WHERE clave='precio_bloque_finde_alta_activo';

-- Sm22 -- R3 NO aplica en BAJA
INSERT INTO _r
SELECT 22, 'Sm22_baja_viernes_suelto',
  CASE WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='bloque_finde_obligatorio')
       THEN 'PASS - en baja R3 no aplica (viernes suelto)' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-13","fecha_out":"2026-11-14","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Fixture: jueves 2026-11-19 (ALTA) marcado como noche de alta demanda
INSERT INTO noches_alta_demanda (fecha, origen, activo, nombre, created_by, source_event)
VALUES ('2026-11-19', 'manual', TRUE, 'SMOKE_B3', 'smoke', 'smoke_b3');

-- Sm23 -- ALTA DEMANDA pegada al finde se vende SUELTA
INSERT INTO _r
SELECT 23, 'Sm23_alta_demanda_suelta',
  CASE WHEN precios_clasificar_noche('2026-11-19') = 'alta_demanda'
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='bloque_finde_obligatorio')
        AND (q.j->'desglose_noches'->0->>'concepto') = 'alta_demanda_noche_1'
       THEN 'PASS - jueves marcado: alta_demanda; R3 no lo bloquea' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-19","fecha_out":"2026-11-20","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm24 -- ESTADIA LARGA >= 10 noches (restriccion, no motivo) <- FIX del FAIL en TEST
INSERT INTO _r
SELECT 24, 'Sm24_estadia_larga',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='estadia_larga_derivar')
        AND (q.j->>'reservable_online')::BOOLEAN = FALSE
        AND (q.j->>'noches_count') = '10'
        AND (q.j->>'ok')::BOOLEAN = TRUE
       THEN 'PASS - 10 noches derivan; el motor cotiza igual (ok=true)' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-06-01","fecha_out":"2026-06-11","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm25 -- CAPACIDAD online (restriccion)
INSERT INTO _r
SELECT 25, 'Sm25_capacidad_online',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='excede_capacidad')
        AND (q.j->>'reservable_online')::BOOLEAN = FALSE
       THEN 'PASS - online rechaza y deriva a humano' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-15","personas":6,"modo":"online"}'::JSONB) AS j) q;

-- Sm26 -- CAPACIDAD manual: warning (enforcement real en B3.1)
INSERT INTO _r
SELECT 26, 'Sm26_capacidad_manual_warning',
  CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'warnings') w WHERE w->>'codigo'='capacidad_max_override')
       THEN 'PASS - manual: warning, no bloqueo' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-15","personas":6,"modo":"manual"}'::JSONB) AS j) q;

-- Fixture: override PORCENTUAL +20% (todos los perfiles, todas las noches)
INSERT INTO overrides_precio (tipo, perfil, tipo_noche, fecha_in, fecha_out_excl, valor, activo, motivo, created_by, source_event)
VALUES ('porcentual', NULL, 'todas', '2026-10-05', '2026-10-08', 20, TRUE, 'SMOKE_B3', 'smoke', 'smoke_b3');

-- Sm27 -- OVERRIDE PORCENTUAL: 2026-10-05 (lun, baja, semana_noche_1=130.000) +20% = 156.000
INSERT INTO _r
SELECT 27, 'Sm27_override_porcentual',
  CASE WHEN (q.j->'desglose_noches'->0->>'precio') = '156000'
       THEN 'PASS - 130.000 +20% = 156.000'
       ELSE 'FAIL - ' || COALESCE(q.j->'desglose_noches'->0->>'precio','(null)') END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-10-05","fecha_out":"2026-10-06","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Fixture: override ABSOLUTO solapado (grande, semana) sobre la MISMA fecha
INSERT INTO overrides_precio (tipo, perfil, tipo_noche, fecha_in, fecha_out_excl, valor, activo, motivo, created_by, source_event)
VALUES ('absoluto', 'grande', 'semana', '2026-10-05', '2026-10-08', 99000, TRUE, 'SMOKE_B3', 'smoke', 'smoke_b3');

-- Sm28 -- PRECEDENCIA D-PR-17: absoluto gana al porcentual (SIN apilamiento)
INSERT INTO _r
SELECT 28, 'Sm28_override_precedencia',
  CASE WHEN (q.j->'desglose_noches'->0->>'precio') = '99000'
       THEN 'PASS - absoluto (99.000) gana; sin apilamiento (no 187.200)'
       ELSE 'FAIL - ' || COALESCE(q.j->'desglose_noches'->0->>'precio','(null)') END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-10-05","fecha_out":"2026-10-06","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm29 -- ESPECIFICIDAD por perfil: la chica NO toma el absoluto de 'grande'
INSERT INTO _r
SELECT 29, 'Sm29_override_por_perfil',
  CASE WHEN (q.j->'desglose_noches'->0->>'precio') = '132000'
       THEN 'PASS - chica aplica el porcentual (110.000 +20% = 132.000), no el absoluto de grande'
       ELSE 'FAIL - ' || COALESCE(q.j->'desglose_noches'->0->>'precio','(null)') END
FROM (SELECT precios_cotizar('{"id_cabana":4,"fecha_in":"2026-10-05","fecha_out":"2026-10-06","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm30 -- tarifa_incompleta: cierro una celda -> el motor NO cotiza $0
UPDATE tarifas_motor SET vigente_hasta = NOW()
WHERE perfil='grande' AND temporada_clave='alta' AND concepto='semana_noche_1' AND vigente_hasta IS NULL;
INSERT INTO _r
SELECT 30, 'Sm30_tarifa_incompleta',
  CASE WHEN (q.j->>'ok')::BOOLEAN = FALSE AND (q.j->>'error') = 'tarifa_incompleta'
       THEN 'PASS - celda faltante -> ok=false (nunca cotiza $0)' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-11-16","fecha_out":"2026-11-17","personas":2,"modo":"online"}'::JSONB) AS j) q;
UPDATE tarifas_motor SET vigente_hasta = NULL
WHERE perfil='grande' AND temporada_clave='alta' AND concepto='semana_noche_1' AND created_by='seed_b2b';

-- Sm31 -- DINERO: noches + eventos + extras == precio_total
INSERT INTO _r
SELECT 31, 'Sm31_desglose_suma_total',
  CASE WHEN (SELECT COALESCE(SUM((n->>'precio')::NUMERIC),0) FROM jsonb_array_elements(q.j->'desglose_noches') n)
          + (SELECT COALESCE(SUM((p->>'precio')::NUMERIC),0) FROM jsonb_array_elements(q.j->'desglose_eventos') p)
          + (q.j->>'extra_persona_total')::NUMERIC = (q.j->>'precio_total')::NUMERIC
       THEN 'PASS - noches + eventos + extras = precio_total (exacto)' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-22","personas":5,"modo":"online"}'::JSONB) AS j) q;

-- Sm32 -- DINERO (D-PR-19): sena + saldo == total, los tres multiplos de $1.000
INSERT INTO _r
SELECT 32, 'Sm32_sena_saldo',
  CASE WHEN (q.j->>'monto_sena')::NUMERIC + (q.j->>'monto_saldo')::NUMERIC = (q.j->>'precio_total')::NUMERIC
        AND (q.j->>'monto_sena')::NUMERIC % 1000 = 0
        AND (q.j->>'monto_saldo')::NUMERIC % 1000 = 0
        AND (q.j->>'precio_total')::NUMERIC % 1000 = 0
       THEN 'PASS - sena+saldo=total; los tres multiplos de 1.000' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":4,"fecha_in":"2026-07-13","fecha_out":"2026-07-16","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm33 -- El 5% queda FUERA de precio_total (solo warning, al peso, alineado A10-MP)
INSERT INTO _r
SELECT 33, 'Sm33_cargo_5pct_fuera',
  CASE WHEN (q.j->>'cargo_saldo_transferencia_mp')::NUMERIC = ROUND((q.j->>'monto_saldo')::NUMERIC * 5 / 100.0)
        AND (q.j->>'cargo_saldo_transferencia_mp')::NUMERIC > 0
        AND (SELECT COALESCE(SUM((n->>'precio')::NUMERIC),0) FROM jsonb_array_elements(q.j->'desglose_noches') n)
          + (SELECT COALESCE(SUM((p->>'precio')::NUMERIC),0) FROM jsonb_array_elements(q.j->'desglose_eventos') p)
          + (q.j->>'extra_persona_total')::NUMERIC = (q.j->>'precio_total')::NUMERIC
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'warnings') w WHERE w->>'codigo'='cargo_saldo_transferencia_mp')
       THEN 'PASS - 5% informativo (al peso), no contamina el alojamiento' ELSE 'FAIL' END
FROM (SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":2,"modo":"online"}'::JSONB) AS j) q;

-- Sm34 -- CONGELAMIENTO sobre la VENTANA VENDIBLE hallada (Buscador A)
INSERT INTO _fix SELECT 'cot_pre_res',  (SELECT COUNT(*)::TEXT FROM reservas);
INSERT INTO _fix SELECT 'cot_pre_prer', (SELECT COUNT(*)::TEXT FROM pre_reservas);
INSERT INTO _fix
SELECT 'cot_id',
  CASE WHEN (SELECT v FROM _fix WHERE k='free_cab') IS NULL THEN NULL
       ELSE (precios_cotizar_congelar(jsonb_build_object(
              'id_cabana', (SELECT v FROM _fix WHERE k='free_cab')::BIGINT,
              'fecha_in',  (SELECT v FROM _fix WHERE k='free_in'),
              'fecha_out', (SELECT v FROM _fix WHERE k='free_out'),
              'personas', 2, 'canal', 'web', 'modo', 'online'))->>'cotizacion_id')
  END;

INSERT INTO _r
SELECT 34, 'Sm34_congelamiento',
  CASE
    WHEN (SELECT v FROM _fix WHERE k='free_cab') IS NULL
      THEN 'FAIL - Buscador A no hallo ventana vendible (ver Sm0)'
    WHEN (SELECT v FROM _fix WHERE k='cot_id') IS NOT NULL
     AND EXISTS (SELECT 1 FROM cotizaciones_precio c WHERE c.cotizacion_id = (SELECT v FROM _fix WHERE k='cot_id')::UUID)
     AND (SELECT c.expires_at > NOW() FROM cotizaciones_precio c WHERE c.cotizacion_id = (SELECT v FROM _fix WHERE k='cot_id')::UUID)
     AND (SELECT COUNT(*)::TEXT FROM reservas)     = (SELECT v FROM _fix WHERE k='cot_pre_res')
     AND (SELECT COUNT(*)::TEXT FROM pre_reservas) = (SELECT v FROM _fix WHERE k='cot_pre_prer')
      THEN 'PASS - congela con TTL sobre ventana libre; NO crea pre-reserva ni reserva'
    ELSE 'FAIL' END;

-- Sm35 -- cotizacion_vencida
INSERT INTO cotizaciones_precio (cotizacion_id, id_cabana, perfil, fecha_in, fecha_out, personas, canal,
  precio_total, monto_sena, monto_saldo, precio_source, snapshot, created_at, expires_at)
VALUES ('00000000-0000-0000-0000-0000000b3bad', 5, 'chica', '2026-07-13','2026-07-15', 2, 'web',
  200000, 100000, 100000, 'motor_estandar', '{"smoke":"b3"}'::JSONB,
  NOW() - INTERVAL '2 hours', NOW() - INTERVAL '1 hour');

INSERT INTO _r
SELECT 35, 'Sm35_cotizacion_vencida',
  CASE WHEN (precios_cotizacion_obtener('00000000-0000-0000-0000-0000000b3bad')->>'error') = 'cotizacion_vencida'
        AND (precios_cotizacion_obtener((SELECT v FROM _fix WHERE k='cot_id')::UUID)->>'vigente')::BOOLEAN = TRUE
       THEN 'PASS - vencida rechazada; vigente se lee OK' ELSE 'FAIL' END;

-- Sm36 -- ORACULO DE CERO MUTACION: precios_cotizar no escribe nada
INSERT INTO _fix SELECT 'cot_snapshot', (SELECT COUNT(*)::TEXT FROM cotizaciones_precio);
SELECT precios_cotizar('{"id_cabana":1,"fecha_in":"2026-07-13","fecha_out":"2026-07-20","personas":5,"modo":"online"}'::JSONB);
SELECT precios_cotizar('{"id_cabana":4,"fecha_in":"2026-11-20","fecha_out":"2026-11-22","personas":3,"modo":"manual"}'::JSONB);
SELECT precios_cotizar('{"id_cabana":2,"fecha_in":"2026-08-08","fecha_out":"2026-08-11","personas":2,"modo":"online"}'::JSONB);

INSERT INTO _r
SELECT 36, 'Sm36_oraculo_cero_mutacion',
  CASE WHEN (SELECT COUNT(*) FROM reservas)      = (SELECT n FROM _oraculo WHERE t='reservas') + 1       -- +1 fixture Sm7
        AND (SELECT COUNT(*) FROM pre_reservas)  = (SELECT n FROM _oraculo WHERE t='pre_reservas')       -- sin cambios
        AND (SELECT COUNT(*) FROM bloqueos)      = (SELECT n FROM _oraculo WHERE t='bloqueos') + 1       -- +1 fixture Sm9
        AND (SELECT COUNT(*) FROM tarifas_motor) = (SELECT n FROM _oraculo WHERE t='tarifas_motor')      -- grilla intacta
        AND (SELECT COUNT(*)::TEXT FROM cotizaciones_precio) = (SELECT v FROM _fix WHERE k='cot_snapshot')
       THEN 'PASS - 3 cotizaciones: cero escrituras operativas, cero cotizaciones nuevas'
       ELSE 'FAIL - precios_cotizar muto estado' END;

-- Sm38 -- PRECEDENCIA DEL MOTIVO: la disponibilidad gana, pero restricciones[] ACUMULA.
--   Usa el bloqueo del Buscador B; 14 noches (>=10) que lo contienen.
--   (Convierte en test el hallazgo del diagnostico en TEST.)
INSERT INTO _r
SELECT 38, 'Sm38_precedencia_motivo',
  CASE WHEN (q.j->>'motivo_no_reservable') = 'no_disponible'
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='no_disponible')
        AND EXISTS (SELECT 1 FROM jsonb_array_elements(q.j->'restricciones') r WHERE r->>'codigo'='estadia_larga_derivar')
       THEN 'PASS - motivo=no_disponible (gana); restricciones acumulan ambas'
       ELSE 'FAIL' END
FROM (SELECT precios_cotizar(jsonb_build_object(
        'id_cabana', (SELECT cab FROM _w), 'fecha_in', (SELECT base FROM _w),
        'fecha_out', (SELECT base + 14 FROM _w), 'personas', 2, 'modo', 'online')) AS j) q;

-- Sm39 -- NO se congela lo no vendible (cero filas nuevas)
INSERT INTO _fix SELECT 'cot_n_antes', (SELECT COUNT(*)::TEXT FROM cotizaciones_precio);
INSERT INTO _r
SELECT 39, 'Sm39_no_congela_no_vendible',
  CASE WHEN (precios_cotizar_congelar(jsonb_build_object(
               'id_cabana', (SELECT cab FROM _w), 'fecha_in', (SELECT base + 8 FROM _w),
               'fecha_out', (SELECT base + 9 FROM _w), 'personas', 2, 'canal', 'web', 'modo', 'online'))
             ->>'congelada')::BOOLEAN = FALSE
        AND (SELECT COUNT(*)::TEXT FROM cotizaciones_precio) = (SELECT v FROM _fix WHERE k='cot_n_antes')
       THEN 'PASS - congelar rechaza lo no vendible; cero filas nuevas' ELSE 'FAIL' END;

-- ===========================================================================
-- TEARDOWN explicito (orden por FK)
-- ===========================================================================
DELETE FROM cotizaciones_precio
 WHERE cotizacion_id = '00000000-0000-0000-0000-0000000b3bad'
    OR cotizacion_id = (SELECT v FROM _fix WHERE k='cot_id')::UUID;
DELETE FROM overrides_precio     WHERE source_event = 'smoke_b3';
DELETE FROM noches_alta_demanda  WHERE source_event = 'smoke_b3';
DELETE FROM bloqueos             WHERE source_event = 'smoke_b3';
DELETE FROM reservas             WHERE source_event = 'smoke_b3';
DELETE FROM huespedes            WHERE nombre = 'SMOKE_B3 Huesped';
DELETE FROM paquetes_evento      WHERE id_evento IN (SELECT id_evento FROM eventos_especiales WHERE source_event='smoke_b3');
DELETE FROM eventos_especiales   WHERE source_event = 'smoke_b3';

-- Sm37 -- CERO RESIDUOS + estado restaurado
INSERT INTO _r
SELECT 37, 'Sm37_cero_residuos',
  CASE WHEN (SELECT COUNT(*) FROM eventos_especiales  WHERE source_event='smoke_b3') = 0
        AND (SELECT COUNT(*) FROM overrides_precio    WHERE source_event='smoke_b3') = 0
        AND (SELECT COUNT(*) FROM noches_alta_demanda WHERE source_event='smoke_b3') = 0
        AND (SELECT COUNT(*) FROM bloqueos            WHERE source_event='smoke_b3') = 0
        AND (SELECT COUNT(*) FROM reservas            WHERE source_event='smoke_b3') = 0
        AND (SELECT COUNT(*) FROM huespedes           WHERE nombre='SMOKE_B3 Huesped') = 0
        AND (SELECT COUNT(*) FROM cotizaciones_precio) = (SELECT n FROM _oraculo WHERE t='cotizaciones_precio')
        AND (SELECT COUNT(*) FROM reservas)            = (SELECT n FROM _oraculo WHERE t='reservas')
        AND (SELECT COUNT(*) FROM bloqueos)            = (SELECT n FROM _oraculo WHERE t='bloqueos')
        AND (SELECT COUNT(*) FROM tarifas_motor WHERE vigente_hasta IS NULL) = 32
        AND (SELECT valor FROM configuracion_general WHERE clave='precio_extra_persona_activo') = 'true'
        AND (SELECT valor FROM configuracion_general WHERE clave='precio_bloque_finde_alta_activo') = 'true'
       THEN 'PASS - cero residuos; grilla (32) y config restauradas' ELSE 'FAIL' END;

-- Resultado (ultimo result set)
SELECT sid, resultado FROM _r ORDER BY orden;

COMMIT;
