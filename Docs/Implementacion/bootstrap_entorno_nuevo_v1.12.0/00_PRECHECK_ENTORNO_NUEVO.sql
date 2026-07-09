-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.12.0 — 00: PRECHECKS READ-ONLY
-- Canónico de referencia: 6B_SCHEMA_SQL.md v1.12.0 (PARTE B Bloques 1→23 +
--   PARTE C Bloques C0→C14). El canónico es la fuente; esta carpeta lo referencia.
-- ----------------------------------------------------------------------------
-- USO: correr en el SQL Editor del PROYECTO NUEVO, cada bloque por separado,
--      CON NADA SELECCIONADO (L-8A-01). El editor muestra solo el último SELECT;
--      por eso el gate (P1) cierra en una fila-veredicto.
--
-- NATURALEZA: 100% read-only. Solo leen catálogos del sistema. No crean, no
--      modifican, no consumen secuencias. Seguros en cualquier proyecto: si por
--      error se corren sobre OPS/TEST, P1 devuelve BASE_NO_VACIA.
--
-- GATE: el discriminador de entorno NO es el ID de cabaña (un bootstrap limpio
--      nace 1-5 igual que TEST/OPS; L-RDEV-02). El gate de esta etapa es:
--        (a) Project Ref correcto  -> confirmar por URL del navegador (P0)
--        (b) SQL Editor del proyecto nuevo
--        (c) base vacía            -> P1 == BASE_VACIA_OK
--      No avanzar a 01_BOOTSTRAP_PARTE_B_BASE.sql si P1 no da BASE_VACIA_OK.
--      NUNCA correr sobre OPS (ref __REF_SANITIZADO__).
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- P0 — Contexto e identidad del proyecto (INFORMATIVO; read-only)
-- ----------------------------------------------------------------------------
-- El Project Ref NO es legible de forma confiable por SQL: current_database()
-- siempre = 'postgres' (L-7B-01) y en el SQL Editor current_user = 'postgres'
-- (L-7E-01). Confirmá el ref por la URL del navegador: debe ser el PROYECTO
-- NUEVO, nunca __REF_SANITIZADO__ (OPS).
-- ────────────────────────────────────────────────────────────────────────────
SELECT
  current_database()                AS db,
  current_user                      AS usuario_sql,
  split_part(version(), ' on ', 1)  AS pg_version,
  now()                             AS ahora;


-- ────────────────────────────────────────────────────────────────────────────
-- P1 — GATE OBLIGATORIO: BASE VACÍA (read-only; solo catálogos)
-- ----------------------------------------------------------------------------
-- Cuenta objetos de negocio (20 tablas base), Carril B (9 tablas, 6 secuencias),
-- funciones del proyecto (13 motor + 21 Carril B) y la tabla del marcador
-- 'ambiente'. TODO debe dar 0. El veredicto se basa en los objetos NOMBRADOS del
-- proyecto; total_tablas_public es informativo (idealmente 0; si >0, inspeccionar
-- qué son antes de avanzar).
-- ────────────────────────────────────────────────────────────────────────────
WITH base_tabs AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
    AND c.relname IN (
      'bloqueos','cabanas','configuracion_general','consultas','cuentas_cobro',
      'descuentos','eventos_especiales','feriados','gastos','huespedes','log_cambios',
      'overrides_operativos','pagos','paquetes_evento','plantillas_mensajes',
      'pre_reservas','reservas','socios','tarifas','temporadas')
),
carrilb_tabs AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
    AND c.relname IN (
      'zonas','cabana_zona','activaciones_operativas','gastos_internos',
      'liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
      'movimientos_socio','revaluaciones')
),
config_table AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = 'configuracion_general'
),
funcs AS (
  SELECT count(*) AS n
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      -- motor (13)
      'cancelar_prereserva','confirmar_reserva','crear_bloqueo','crear_prereserva',
      'expirar_prereservas_vencidas','log_cambio_estado','normalizar_telefono',
      'obtener_disponibilidad_rango','registrar_pago','set_telefono_normalizado',
      'set_updated_at','upsert_huesped','validar_disponibilidad',
      -- Carril B (21)
      'resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion',
      'cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo',
      'reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo','liquidacion_vigente',
      'saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
      'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual',
      'registrar_reversa','registrar_revaluacion','trg_9h_inmutable','abortar_si_falla')
),
seqs AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'S'
    AND c.relname IN (
      'zonas_id_zona_seq','activaciones_operativas_id_activacion_seq',
      'gastos_internos_id_gasto_seq','liquidaciones_periodo_id_liquidacion_seq',
      'movimientos_socio_id_movimiento_seq','revaluaciones_id_revaluacion_seq')
),
total_public AS (
  SELECT count(*) AS n
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
)
SELECT
  (SELECT n FROM base_tabs)     AS tablas_base_presentes,        -- esperado 0
  (SELECT n FROM carrilb_tabs)  AS tablas_carrilb_presentes,     -- esperado 0
  (SELECT n FROM config_table)  AS tabla_ambiente_presente,      -- esperado 0 (sin tabla => sin marcador)
  (SELECT n FROM funcs)         AS funciones_proyecto_presentes, -- esperado 0
  (SELECT n FROM seqs)          AS secuencias_carrilb_presentes, -- esperado 0
  (SELECT n FROM total_public)  AS total_tablas_public,          -- informativo (idealmente 0)
  CASE WHEN (SELECT n FROM base_tabs)    = 0
        AND (SELECT n FROM carrilb_tabs) = 0
        AND (SELECT n FROM config_table) = 0
        AND (SELECT n FROM funcs)        = 0
        AND (SELECT n FROM seqs)         = 0
       THEN 'BASE_VACIA_OK -> habilita 01_BOOTSTRAP_PARTE_B_BASE.sql'
       ELSE 'BASE_NO_VACIA -> DETENER: no es el proyecto nuevo o ya se ejecutó algo'
  END AS veredicto;


-- ────────────────────────────────────────────────────────────────────────────
-- P2 — Versión de PostgreSQL y extensiones requeridas (read-only)
-- ----------------------------------------------------------------------------
-- Esperado: pg_version 17.x. btree_gist y pg_cron DISPONIBLES (default_version
-- no nulo). "instalada" puede venir NULL ahora: btree_gist se instala en Bloque 1
-- y pg_cron lo usa el Bloque 22.
-- Si pg_cron_disponible es NULL -> pg_cron NO disponible en este proyecto -> el
-- Bloque 22 (cron.schedule) se omite/maneja, no se fuerza.
-- ────────────────────────────────────────────────────────────────────────────
SELECT
  split_part(version(), ' on ', 1) AS pg_version,
  (SELECT default_version  FROM pg_available_extensions WHERE name = 'btree_gist') AS btree_gist_disponible,
  (SELECT installed_version FROM pg_available_extensions WHERE name = 'btree_gist') AS btree_gist_instalada,
  (SELECT default_version  FROM pg_available_extensions WHERE name = 'pg_cron')    AS pg_cron_disponible,
  (SELECT installed_version FROM pg_available_extensions WHERE name = 'pg_cron')    AS pg_cron_instalada;


-- ────────────────────────────────────────────────────────────────────────────
-- P3 — Roles del Data API presentes (read-only)
-- ----------------------------------------------------------------------------
-- Esperado: anon, authenticated, service_role presentes (y postgres,
-- supabase_admin, authenticator). Importan para que el REVOKE de Bloque 23 / C12
-- y los asserts de hardening de C14/02_VERIFY tengan sujeto real.
-- ────────────────────────────────────────────────────────────────────────────
SELECT rolname, rolcanlogin, rolsuper
FROM pg_roles
WHERE rolname IN ('anon','authenticated','service_role','authenticator','postgres','supabase_admin')
ORDER BY rolname;


-- ────────────────────────────────────────────────────────────────────────────
-- P4 — Baseline de exposición / confirmación de switches (read-only)
-- ----------------------------------------------------------------------------
-- Proxy SQL del switch "Automatically expose new tables". Lista los DEFAULT
-- PRIVILEGES de schema public que afectarían a objetos NUEVOS.
--
-- LECTURA:
--  - OK (proyecto cerrado como OPS; D-RDEV-02): 0 filas, o solo defaults inocuos
--    del rol postgres SIN privilegios de lectura/escritura a anon/authenticated/
--    service_role/PUBLIC.
--  - ALERTA (proyecto abierto): filas que conceden SELECT/INSERT/UPDATE/DELETE a
--    anon/authenticated/service_role. Si aparece -> el switch no quedó OFF ->
--    corregir en consola ANTES de 01_BOOTSTRAP.
--
-- 0 filas = ideal. Si hay filas, leer la columna privilegios_default.
-- ────────────────────────────────────────────────────────────────────────────
SELECT
  n.nspname                          AS schema,
  pg_get_userbyid(d.defaclrole)      AS rol_que_define,
  d.defaclobjtype                    AS tipo_objeto,   -- r=tabla, S=secuencia, f=función, T=tipo
  array_to_string(d.defaclacl, ', ') AS privilegios_default
FROM pg_default_acl d
JOIN pg_namespace n ON n.oid = d.defaclnamespace
WHERE n.nspname = 'public'
ORDER BY rol_que_define, tipo_objeto;
