-- C_SLICE2 / A10 - Check de privilegios. CORRER DESDE LA CREDENCIAL Postgres de n8n TEST
-- (vita_supabase_test), NO desde el SQL Editor con otro rol. Si alguna da false => FRENAR
-- antes de importar (el nodo PG_cobranza no podria ejecutar registrar_pago/abortar_si_falla).
SELECT
  has_function_privilege('public.registrar_pago(jsonb)'::regprocedure, 'EXECUTE')   AS puede_registrar_pago,
  has_function_privilege('public.abortar_si_falla(jsonb)'::regprocedure, 'EXECUTE') AS puede_abortar_si_falla;
