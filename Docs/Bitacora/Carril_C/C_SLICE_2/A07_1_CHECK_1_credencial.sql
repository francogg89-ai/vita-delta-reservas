-- ============================================================================
-- A07.1 — CHECK 1: Verificación de credencial y privilegio EXECUTE
-- Carril C / Portal Operativo Interno — Slice 2 / A07 (escrituras reuse).
--
-- NATURALEZA: 100% READ-ONLY. No inserta, no actualiza, no borra, no toca grants.
-- DÓNDE EJECUTAR: en n8n, desde un nodo Postgres que use la credencial
--   `vita_supabase_test` (LA MISMA que va a usar el wrapper A07). NO ejecutar
--   desde el SQL Editor de Supabase: ahí conectás como `postgres` directo y el
--   resultado NO representa a la credencial de n8n (que es lo que queremos probar).
--
-- CRITERIO DE PASO (D-C-60):
--   - Las 4 columnas exec_* deben dar TRUE.
--   - Si current_user NO tiene EXECUTE sobre las 4 funciones del motor → FRENO.
--     NO se toca ningún grant en este slice (coherente con P-C-11). Se analiza.
-- NOTA: el ACL observado en el snapshot es {postgres=X/postgres} (solo postgres
--   ejecuta), así que en la práctica esto exige que la credencial conecte como
--   postgres/superuser. Lo confirmamos empíricamente, no lo asumimos.
-- ============================================================================

SELECT
  current_user                                                                          AS current_user,
  session_user                                                                          AS session_user,
  has_function_privilege(current_user, 'public.crear_prereserva(jsonb)',  'EXECUTE')    AS exec_crear_prereserva,
  has_function_privilege(current_user, 'public.registrar_pago(jsonb)',    'EXECUTE')    AS exec_registrar_pago,
  has_function_privilege(current_user, 'public.confirmar_reserva(jsonb)', 'EXECUTE')    AS exec_confirmar_reserva,
  has_function_privilege(current_user, 'public.crear_bloqueo(jsonb)',     'EXECUTE')    AS exec_crear_bloqueo,
  -- Veredicto agregado: TRUE solo si las 4 dan EXECUTE.
  (    has_function_privilege(current_user, 'public.crear_prereserva(jsonb)',  'EXECUTE')
   AND has_function_privilege(current_user, 'public.registrar_pago(jsonb)',    'EXECUTE')
   AND has_function_privilege(current_user, 'public.confirmar_reserva(jsonb)', 'EXECUTE')
   AND has_function_privilege(current_user, 'public.crear_bloqueo(jsonb)',     'EXECUTE')
  )                                                                                      AS veredicto_exec_ok,
  -- Confirmación redundante de ambiente (no daña, ancla el resultado a TEST).
  (SELECT valor FROM configuracion_general WHERE clave = 'ambiente')                     AS ambiente_marker;
