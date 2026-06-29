-- ============================================================================
-- BOOTSTRAP ENTORNO NUEVO v1.8.1 — 02_VERIFY: VEREDICTO FINAL DEL ENTORNO (RO)
-- Cubre: C14 (ESPEJADO como SELECT, L-RDEV-04), inventario Carril B, hardening
--   Carril B (C12), hardening de funciones base (Bloque 23) y barrido global de
--   permisos (relaciones / secuencias / funciones). 100% read-only.
-- ----------------------------------------------------------------------------
-- USO: SQL Editor del PROYECTO NUEVO, NADA seleccionado. Correr DESPUÉS de C14
--   (fin de 02_BOOTSTRAP_PARTE_C_CARRIL_B.sql). QUERY 1 = fila-veredicto;
--   QUERY 2 = reporte explícito del residual Dxtm (informativo).
-- VEREDICTO: ENTORNO_COMPLETO_OK | ENTORNO_INCOMPLETO.
-- CONDICIONES OBLIGATORIAS:
--   - Trampa `proacl IS NULL ⇒ PUBLIC ejecuta` contemplada en el barrido de funciones.
--   - El veredicto FALLA si hay cualquier EXECUTE amplio a PUBLIC/anon/authenticated/
--     service_role en las 13 funciones base O en las 21 funciones del Carril B.
--   - El residual Dxtm (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN en tablas/vistas base)
--     se REPORTA (QUERY 2), NO se cuenta como exposición amplia (paridad OPS/TEST).
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 1 — VEREDICTO FINAL (una fila)
-- ────────────────────────────────────────────────────────────────────────────
WITH
-- ── Inventario Carril B ──
ctabs  AS (SELECT count(*) n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
            WHERE s.nspname='public' AND c.relkind='r'
            AND c.relname IN ('zonas','cabana_zona','activaciones_operativas','gastos_internos',
              'liquidaciones_periodo','liquidacion_cascada','liquidacion_socio',
              'movimientos_socio','revaluaciones')),
cfuncs AS (SELECT count(DISTINCT p.proname) n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
            WHERE s.nspname='public' AND p.proname IN (
      'resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion',
      'cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo',
      'reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo','liquidacion_vigente',
      'saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
      'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual',
      'registrar_reversa','registrar_revaluacion','trg_9h_inmutable','abortar_si_falla')),
ctrigs AS (SELECT count(*) n FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
            WHERE p.proname='trg_9h_inmutable' AND NOT t.tgisinternal),
cseqs  AS (SELECT count(*) n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
            WHERE s.nspname='public' AND c.relkind='S'
            AND c.relname IN ('zonas_id_zona_seq','activaciones_operativas_id_activacion_seq',
              'gastos_internos_id_gasto_seq','liquidaciones_periodo_id_liquidacion_seq',
              'movimientos_socio_id_movimiento_seq','revaluaciones_id_revaluacion_seq')),
amb    AS (SELECT valor FROM configuracion_general WHERE clave='ambiente'),
-- ── C14 espejado como SELECT (read-only; las funciones del Carril B son read-only) ──
seam   AS (SELECT count(*) m FROM cabanas c
            WHERE resolver_beneficiario(c.id_cabana, DATE '2026-07-01') = c.id_socio_beneficiario),
seamt  AS (SELECT count(*) t FROM cabanas),
jul    AS (SELECT max(valor_pool) v FROM matriz_participacion(DATE '2026-07-01')),
nov    AS (SELECT max(valor_pool) v FROM matriz_participacion(DATE '2026-11-01')),
rep    AS (SELECT sum(monto_asignado) v FROM repartir_por_matriz(DATE '2026-07-01', 100000)),
-- ── Barrido global de permisos: relaciones y secuencias amplias (esperado 0/0) ──
broad_rel AS (
  SELECT count(*) n
  FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE s.nspname='public' AND c.relkind IN ('r','v')
    AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')
    AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
),
seq_exp AS (
  SELECT count(*) n
  FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE s.nspname='public' AND c.relkind='S'
    AND a.privilege_type IN ('USAGE','SELECT','UPDATE')
    AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
),
-- ── Hardening de funciones BASE (13): trampa proacl IS NULL; extensiones excluidas ──
base_exec AS (
  SELECT count(*) n
  FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='public'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.objid=p.oid AND d.classid='pg_proc'::regclass AND d.deptype='e')
    AND p.proname IN (
      'cancelar_prereserva','confirmar_reserva','crear_bloqueo','crear_prereserva',
      'expirar_prereservas_vencidas','log_cambio_estado','normalizar_telefono',
      'obtener_disponibilidad_rango','registrar_pago','set_telefono_normalizado',
      'set_updated_at','upsert_huesped','validar_disponibilidad')
    AND (
      p.proacl IS NULL
      OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                 WHERE a.privilege_type='EXECUTE'
                   AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role')))
    )
),
-- ── Hardening de funciones CARRIL B (21): misma trampa; extensiones excluidas ──
carrilb_exec AS (
  SELECT count(*) n
  FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='public'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.objid=p.oid AND d.classid='pg_proc'::regclass AND d.deptype='e')
    AND p.proname IN (
      'resolver_beneficiario','matriz_participacion','repartir_por_matriz','detalle_participacion',
      'cascada_periodo','saldo_socios_periodo','incidencia_gasto','reporte_overrides_periodo',
      'reporte_5_vs_fiscal_periodo','gastos_sin_incidencia_periodo','liquidacion_vigente',
      'saldo_corriente_socio','mayor_socio','reporte_retribucion_operativo_periodo',
      'registrar_snapshot_periodo','registrar_retiro','registrar_movimiento_manual',
      'registrar_reversa','registrar_revaluacion','trg_9h_inmutable','abortar_si_falla')
    AND (
      p.proacl IS NULL
      OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                 WHERE a.privilege_type='EXECUTE'
                   AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role')))
    )
)
SELECT
  (SELECT n FROM ctabs)         AS tablas_carrilb,             -- esperado 9
  (SELECT n FROM cfuncs)        AS funciones_carrilb,          -- esperado 21
  (SELECT n FROM ctrigs)        AS triggers_inmutabilidad,     -- esperado 10
  (SELECT n FROM cseqs)         AS secuencias_carrilb,         -- esperado 6
  COALESCE((SELECT valor FROM amb),'(ausente)') AS ambiente,   -- esperado 'dev'
  (SELECT m FROM seam) || '/' || (SELECT t FROM seamt) AS seam,-- esperado 5/5
  (SELECT v FROM jul)           AS matriz_julio,               -- esperado 378.00
  (SELECT v FROM nov)           AS matriz_noviembre,           -- esperado 456.00
  (SELECT v FROM rep)           AS reparto_sigma,              -- esperado 100000.00
  (SELECT n FROM broad_rel)     AS relaciones_amplias,         -- esperado 0
  (SELECT n FROM seq_exp)       AS secuencias_expuestas,       -- esperado 0
  (SELECT n FROM base_exec)     AS funciones_base_expuestas,   -- esperado 0 (13 motor)
  (SELECT n FROM carrilb_exec)  AS funciones_carrilb_expuestas,-- esperado 0 (21 Carril B)
  CASE WHEN (SELECT n FROM ctabs)=9 AND (SELECT n FROM cfuncs)=21
        AND (SELECT n FROM ctrigs)=10 AND (SELECT n FROM cseqs)=6
        AND (SELECT valor FROM amb)='dev'
        AND (SELECT m FROM seam)=5 AND (SELECT t FROM seamt)=5
        AND (SELECT v FROM jul) IS NOT DISTINCT FROM 378.00
        AND (SELECT v FROM nov) IS NOT DISTINCT FROM 456.00
        AND (SELECT v FROM rep) IS NOT DISTINCT FROM 100000.00
        AND (SELECT n FROM broad_rel)=0
        AND (SELECT n FROM seq_exp)=0
        AND (SELECT n FROM base_exec)=0
        AND (SELECT n FROM carrilb_exec)=0
       THEN 'ENTORNO_COMPLETO_OK'
       ELSE 'ENTORNO_INCOMPLETO -> revisar la columna cuyo valor no cuadra'
  END AS veredicto;


-- ────────────────────────────────────────────────────────────────────────────
-- QUERY 2 — REPORTE EXPLÍCITO DEL RESIDUAL (read-only; informativo)
-- ----------------------------------------------------------------------------
-- Agrupa toda concesión a PUBLIC/anon/authenticated/service_role sobre relaciones
-- y secuencias. ESPERADO: UNA sola fila 'residual_aceptado (Dxtm)' (las 20 tablas
-- base + 6 vistas con Dxtm = TRUNCATE/REFERENCES/TRIGGER/MAINTAIN; SIN r/a/w/d).
-- Las 9 tablas Carril B NO aparecen (REVOKE de C12). Si aparece una fila
-- 'AMPLIO (EXPOSICION)' -> exposición real -> NO cerrar (contradice QUERY 1).
-- El residual Dxtm NO se revoca: paridad OPS/TEST (D-RDEV-04).
-- ────────────────────────────────────────────────────────────────────────────
WITH grants AS (
  SELECT c.relkind, c.relname, a.grantee,
         string_agg(DISTINCT a.privilege_type, ',' ORDER BY a.privilege_type) AS privs,
         bool_or(a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','USAGE')) AS es_amplio
  FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(c.relacl) a
  WHERE s.nspname='public' AND c.relkind IN ('r','v','S')
    AND (a.grantee=0 OR pg_get_userbyid(a.grantee) IN ('anon','authenticated','service_role'))
  GROUP BY c.relkind, c.relname, a.grantee
)
SELECT
  CASE WHEN es_amplio THEN 'AMPLIO (EXPOSICION)' ELSE 'residual_aceptado (Dxtm)' END AS clase,
  count(*)                AS pares_objeto_rol,
  count(DISTINCT relname) AS objetos_distintos,
  string_agg(DISTINCT privs, ' | ' ORDER BY privs) AS sets_de_privilegios
FROM grants
GROUP BY es_amplio
ORDER BY es_amplio DESC;
