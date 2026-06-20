-- ============================================================================
-- C_SLICE2_A08_GW - VERIFICACION del smoke via gateway. Read-only. TEST.
-- Correr despues del smoke gateway. Confirma, por source_event, que:
--   1) cada bloqueo creado via gateway tiene exactamente 1 fila (sin duplicar), y
--   2) el ACTOR inyectado server-side por el gateway (desde portal_usuarios.nombre,
--      NUNCA del frontend) llego correctamente a bloqueos.creado_por:
--      GW_VICKY -> vicky ; GW_FRANCO -> franco.
--
-- Esperado:
--   GW_VICKY   bloqueos=1  creado_por=vicky
--   GW_FRANCO  bloqueos=1  creado_por=franco
-- ============================================================================
WITH fx(nombre, sev, actor_esp) AS (VALUES
  ('GW_VICKY',  'portal_test_a08_cab2_2027-10-01_2027-10-03_cf49bb4ec368', 'vicky'),
  ('GW_FRANCO', 'portal_test_a08_cab3_2027-10-01_2027-10-03_f3658020d1e4', 'franco')
)
SELECT fx.nombre,
       fx.actor_esp,
       (SELECT count(*) FROM bloqueos b WHERE b.source_event = fx.sev)               AS bloqueos,
       (SELECT b.creado_por FROM bloqueos b WHERE b.source_event = fx.sev
          ORDER BY b.id_bloqueo LIMIT 1)                                             AS creado_por
FROM fx
ORDER BY fx.nombre;
