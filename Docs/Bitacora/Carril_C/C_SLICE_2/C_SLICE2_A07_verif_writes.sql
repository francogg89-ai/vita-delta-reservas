-- ============================================================================
-- C_SLICE2_A07 — VERIFICACION DE ESCRITURAS por idem. Read-only. TEST.
-- Correr despues del Bloque 3 (funcional) y de nuevo despues del Bloque 4
-- (concurrencia). Cada reserva creada debe tener EXACTAMENTE 1 reserva y 1
-- seña; los casos rechazados, 0/0/0.
--
-- Esperado tras Bloque 3 (funcional):
--   FELIZ   1 / 1 / 1   |  PARCIAL 1 / 1 / 1   |  CONCUR 0 / 0 / 0
--   NODISP  0 / 0 / 0   |  CAPAC   0 / 0 / 0
-- Esperado tras Bloque 4 (concurrencia): CONCUR pasa a 1 / 1 / 1.
-- (reservas / pagos_sena DEBEN ser 1 en los creados; >1 = duplicado = FALLA.)
-- ============================================================================
WITH fx(nombre, idem) AS (VALUES
  ('FELIZ',   'portal_test_a07_1_2027-03-01_2027-03-03_0eaa37d506b27a1265c5b53b1ec1b705ef33f3c04153f5372e03931781d1f813_dee3c866744b'),
  ('PARCIAL', 'portal_test_a07_2_2027-04-05_2027-04-07_2c7b4d4c511af40434f803e5884d1fc7abd8d1678d96af630c9879385e19686e_c842a0a7e4d3'),
  ('CONCUR',  'portal_test_a07_3_2027-05-10_2027-05-12_add07a6959e978e12129a25c89e7637bf402203163079c816494d1d70cf1f1d5_7fb1a3dfea45'),
  ('NODISP',  'portal_test_a07_1_2027-03-01_2027-03-03_57c521d7f5ecfe39304f2715f96cd492ff7adc6c499305802ffd78dbffec3418_dee3c866744b'),
  ('CAPAC',   'portal_test_a07_5_2027-06-01_2027-06-03_fb30ebd25816f82ddf2f2bd10a4827eda624992c499cd536235738e1b8386bce_e6c0617979fd')
)
SELECT fx.nombre,
       (SELECT count(*) FROM reservas     r  WHERE r.source_event   = fx.idem)                    AS reservas,
       (SELECT count(*) FROM pagos        p  WHERE p.source_event   = fx.idem AND p.tipo='sena')  AS pagos_sena,
       (SELECT count(*) FROM pre_reservas pr WHERE pr.idempotency_key = fx.idem)                  AS prereservas
FROM fx
ORDER BY fx.nombre;
