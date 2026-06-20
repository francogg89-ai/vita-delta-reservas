-- ============================================================================
-- C_SLICE2_A07_GW - VERIFICACION del smoke via gateway. Read-only. TEST.
-- Correr despues del smoke gateway. Confirma, por idem, que:
--   1) cada reserva creada via gateway tiene 1 reserva y 1 sena (sin duplicar), y
--   2) el ACTOR inyectado server-side por el gateway (desde portal_usuarios.nombre,
--      NUNCA del frontend) llego correctamente a validado_por (sena) y created_by
--      (reserva): GW_VICKY -> vicky ; GW_SOCIO -> franco.
--
-- Esperado:
--   GW_VICKY  reservas=1  pagos_sena=1  sena_validado_por=vicky  reserva_created_by=vicky
--   GW_SOCIO  reservas=1  pagos_sena=1  sena_validado_por=franco reserva_created_by=franco
-- ============================================================================
WITH fx(nombre, idem, actor_esp) AS (VALUES
  ('GW_VICKY', 'portal_test_a07_4_2027-07-01_2027-07-03_50a7a1695c7fdd8a645a30e7dbd49324948f02fec5079cef1fcb084cdca5689e_86fed4ec6965', 'vicky'),
  ('GW_SOCIO', 'portal_test_a07_5_2027-07-01_2027-07-03_abd5952d1c838c7505ac84b7dae717d26f510ed264762ea067dfa68554e662bb_966b4252e36e', 'franco')
)
SELECT fx.nombre,
       fx.actor_esp,
       (SELECT count(*) FROM reservas r WHERE r.source_event = fx.idem)                     AS reservas,
       (SELECT count(*) FROM pagos p WHERE p.source_event = fx.idem AND p.tipo='sena')       AS pagos_sena,
       (SELECT p.validado_por FROM pagos p WHERE p.source_event = fx.idem AND p.tipo='sena'
          ORDER BY p.id_pago LIMIT 1)                                                        AS sena_validado_por,
       (SELECT r.created_by FROM reservas r WHERE r.source_event = fx.idem
          ORDER BY r.id_reserva LIMIT 1)                                                     AS reserva_created_by
FROM fx
ORDER BY fx.nombre;
