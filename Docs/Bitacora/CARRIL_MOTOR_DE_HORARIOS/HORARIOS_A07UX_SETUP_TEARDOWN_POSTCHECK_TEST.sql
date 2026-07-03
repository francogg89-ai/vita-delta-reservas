-- =====================================================================
-- HORARIOS_A07UX_SETUP_TEARDOWN_POSTCHECK_TEST.sql
-- Mini-bloque UX A07: mapear override_hora_invalido -> payload_invalido.
-- Fixtures del smoke E2E. SOLO TEST. Correr por secciones (nada seleccionado).
-- Identificador unico del smoke: motivo = 'smoke_a07_ovr_e2268a33'
--   fecha lejana fija: 2027-06-15 (fecha_in) / 2027-06-17 (fecha_out)
--   override corrupto: tipo_override='hora_checkin', valor='25:99' (cast_invalido)
-- El SETUP imprime el id_cabana usado: copialo a $IdCabana del smoke .ps1.
-- =====================================================================

-- =====================================================================
-- [SETUP] (correr ANTES del smoke). Idempotente: limpia antes de insertar.
-- =====================================================================
DO $gate$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM configuracion_general WHERE clave='ambiente' AND valor='test') THEN
    RAISE EXCEPTION 'SETUP A07 abortado: configuracion_general.ambiente <> ''test''.';
  END IF;
END
$gate$;

DELETE FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33';

INSERT INTO overrides_operativos(tipo_override, valor, id_cabana, fecha_desde, fecha_hasta, motivo, creado_por)
SELECT 'hora_checkin', '25:99',
       (SELECT id_cabana FROM cabanas WHERE activa ORDER BY id_cabana LIMIT 1),
       DATE '2027-06-15', DATE '2027-06-15', 'smoke_a07_ovr_e2268a33', 'smoke';

-- Copiar id_cabana a $IdCabana del smoke:
SELECT id_override, id_cabana, tipo_override, valor, fecha_desde, fecha_hasta, motivo
FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33';

-- =====================================================================
-- [TEARDOWN] (correr SIEMPRE despues del smoke, pase o falle). Idempotente.
-- =====================================================================
DO $gate$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM configuracion_general WHERE clave='ambiente' AND valor='test') THEN
    RAISE EXCEPTION 'TEARDOWN A07 abortado: configuracion_general.ambiente <> ''test''.';
  END IF;
END
$gate$;

DELETE FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33';

SELECT count(*) AS overrides_restantes
FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33';   -- debe ser 0

-- =====================================================================
-- [POSTCHECK] (read-only, tras el teardown). Las 3 columnas deben ser 0.
--   - overrides_smoke: el override del fixture ya no existe.
--   - prereservas_smoke: el HARD corta antes del INSERT -> ninguna pre-reserva.
--     (source_event derivado por A07: 'portal_test_a07_<idcab>_<fin>_<fout>_<hash>')
--   - huespedes_smoke: el HARD corta antes de upsert_huesped -> ningun huesped.
-- =====================================================================
SELECT
  (SELECT count(*) FROM overrides_operativos
     WHERE motivo = 'smoke_a07_ovr_e2268a33')                                             AS overrides_smoke,
  (SELECT count(*) FROM pre_reservas
     WHERE source_event LIKE 'portal\_test\_a07\_%\_2027-06-15\_2027-06-17\_%' ESCAPE '\') AS prereservas_smoke,
  (SELECT count(*) FROM huespedes
     WHERE nombre = 'SMOKE_A07_OVR')                                        AS huespedes_smoke;
