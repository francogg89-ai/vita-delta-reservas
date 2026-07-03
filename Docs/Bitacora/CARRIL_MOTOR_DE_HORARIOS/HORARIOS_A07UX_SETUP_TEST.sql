-- =====================================================================
-- HORARIOS_A07UX_SETUP_TEST.sql
-- Mini-bloque UX A07. Fixture del smoke E2E. SOLO TEST.
-- Correr COMPLETO (nada seleccionado) ANTES del smoke.
-- Deja UN override corrupto (hora_checkin='25:99' -> cast_invalido) en una
-- cabana activa para 2027-06-15. Idempotente (limpia antes de insertar).
-- Identificador: motivo = 'smoke_a07_ovr_e2268a33'.
-- Salida esperada: estado='SETUP_OK' + id_override + id_cabana (COPIAR a $IdCabana del smoke).
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

SELECT 'SETUP_OK' AS estado,
       id_override, id_cabana, tipo_override, valor, fecha_desde, fecha_hasta, motivo
FROM overrides_operativos WHERE motivo = 'smoke_a07_ovr_e2268a33';
