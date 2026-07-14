-- ====================================================================================
-- D1_Q8B_H4_VARIANTE_D.sql
-- Bloque B1.3-consolidacion-canonica * D1 * H4: discriminar variante 08-07 vs 09-07 de B1_3_D
-- TEST unicamente. 100% LECTURA. Autocontenido: trae su propio gate y su propia
-- transaccion READ ONLY. No se puede ejecutar esta Q sin el gate: el archivo ES la Q.
-- Repo de referencia: HEAD 07fea85802bc4fccbff1236813593762aefe58d9
-- ====================================================================================

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL search_path = pg_catalog, public;

DO $gate$
DECLARE
  v_amb text := (
    SELECT valor
    FROM public.configuracion_general
    WHERE clave = 'ambiente'
  );
BEGIN
  IF v_amb IS DISTINCT FROM 'test' THEN
    RAISE EXCEPTION
      'GATE D1: ambiente=% (esperado test). Abortando.',
      COALESCE(v_amb, '<null>');
  END IF;
END
$gate$;

-- Q8-BIS -- H4: CUAL VARIANTE DE B1_3_D ESTA DESPLEGADA (1 fila).
--
--   Las dos variantes insertan el MISMO bloque [B1.3-D:BEGIN]..[B1.3-D:END] en
--   confirmar_reserva(jsonb), pero en POSICIONES DISTINTAS respecto del BEGIN interno:
--
--     08-07: replace(v_def, c_anchor, v_bloque || c_anchor)
--            c_anchor = E'  BEGIN\n    INSERT INTO reservas ('
--            => bloque ANTES del BEGIN:   ..[B1.3-D:END]\n  BEGIN\n    INSERT INTO reservas (
--
--     09-07: regexp_replace(v_def, E'(\n)([ \t]*)(INSERT INTO reservas)', E'\1'||v_bloque||E'\2\3')
--            => bloque DESPUES del BEGIN: ..BEGIN\n[B1.3-D:BEGIN]..[B1.3-D:END]\n    INSERT INTO reservas (
--
--   No es cosmetico: cambia si el bloque cae DENTRO o FUERA del sub-bloque BEGIN..END.
--   Este bloque emite la ventana de texto CRUDA: la decision se toma sobre evidencia.
WITH d AS (
  SELECT CASE WHEN to_regprocedure('public.confirmar_reserva(jsonb)') IS NULL THEN NULL
              ELSE pg_get_functiondef(to_regprocedure('public.confirmar_reserva(jsonb)'))
         END AS def
)
SELECT
  'Q8B_H4_VARIANTE_D'                                                     AS bloque,
  (SELECT valor FROM public.configuracion_general WHERE clave = 'ambiente') AS ambiente,
  current_setting('transaction_read_only')                                   AS transaction_read_only,
  md5(d.def)                                                              AS fingerprint_confirmar_reserva,
  'e6ac8ddce8a12a9c48ecc1aa128b311c'                                      AS baseline_s8,
  (md5(d.def) = 'e6ac8ddce8a12a9c48ecc1aa128b311c')                       AS coincide_con_s8,
  (d.def LIKE '%[B1.3-D:BEGIN]%')                                         AS tiene_bloque_d,
  (SELECT count(*) FROM regexp_matches(d.def, '\[B1\.3-D:BEGIN\]', 'g')) AS ocurrencias_begin_marker,
  (SELECT count(*) FROM regexp_matches(d.def, '\[B1\.3-D:END\]',   'g')) AS ocurrencias_end_marker,
  (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n\s*BEGIN\s*\n\s*INSERT INTO reservas') AS firma_variante_08_07,
  (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n[ \t]*INSERT INTO reservas')             AS firma_variante_09_07,
  substring(d.def
            from GREATEST(1, position('[B1.3-D:BEGIN]' in d.def) - 400)
            for  1300)                                                    AS ventana_cruda,
  CASE
    WHEN d.def IS NULL
      THEN '>>> confirmar_reserva(jsonb) AUSENTE <<<'
    WHEN d.def NOT LIKE '%[B1.3-D:BEGIN]%'
      THEN '>>> BLOQUE D AUSENTE DEL VIVO -- INVESTIGAR <<<'
    WHEN     (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n\s*BEGIN\s*\n\s*INSERT INTO reservas')
         AND NOT (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n[ \t]*INSERT INTO reservas')
      THEN 'DESPLEGADA = variante 08-07 (anchor literal)'
    WHEN     (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n[ \t]*INSERT INTO reservas')
         AND NOT (d.def ~ '--\s*\[B1\.3-D:END\]\s*\n\s*BEGIN\s*\n\s*INSERT INTO reservas')
      THEN 'DESPLEGADA = variante 09-07 (anchor regex)'
    ELSE '>>> AMBIGUO -- resolver leyendo ventana_cruda <<<'
  END                                                                     AS veredicto_h4
FROM d;

COMMIT;
