-- =====================================================================
-- HORARIOS_A07UX_TEARDOWN_TEST.sql
-- Mini-bloque UX A07. Limpieza del fixture. SOLO TEST.
-- Correr COMPLETO (nada seleccionado) SIEMPRE despues del smoke (pase o falle).
-- Idempotente: borra por motivo='smoke_a07_ovr_e2268a33'.
-- Salida esperada: estado='TEARDOWN_OK' + overrides_restantes=0.
-- =====================================================================
DO $gate$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM configuracion_general WHERE clave='ambiente' AND valor='test') THEN
    RAISE EXCEPTION 'TEARDOWN A07 abortado: configuracion_general.ambiente <> ''test''.';
  END IF;
END
$gate$;

DELETE FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33';

SELECT CASE WHEN c = 0 THEN 'TEARDOWN_OK' ELSE 'TEARDOWN_FAIL' END AS estado,
       c AS overrides_restantes
FROM (SELECT count(*) AS c FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33') x;
