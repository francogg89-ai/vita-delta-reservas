-- ============================================================================
-- L3_DIAG_READONLY_TEST_OPS.sql
-- Diagnostico READ-ONLY para el Bloque 2 (L3 historico). NO escribe nada.
--
-- Naturaleza: una sola sentencia (WITH ... SELECT). Sin BEGIN, sin DO, sin
-- CREATE TEMP, sin LOCK, sin INSERT/UPDATE/DELETE, sin llamadas a funciones que
-- escriban. Consolida todo en UNA grilla final (correr con NADA seleccionado;
-- el SQL Editor muestra el ultimo -- y unico -- result set, L-CC-03/L-8A-01).
--
-- Uso: correr TAL CUAL en TEST y luego en OPS. Antes de cada corrida, ajustar
-- el literal 'ambiente_esperado' en el CTE params (test u ops). La columna
-- 'ambiente_match' compara ese literal contra configuracion_general('ambiente')
-- para cortar visualmente si se corrio en el entorno equivocado.
--
-- Alcance de las verificaciones (confirmatorio, no mutante):
--   AMBIENTE                : esperado vs detectado.
--   TABLA_COLUMNAS          : columnas reales + huella estructural determinista
--                             de catalogo (md5 sobre la firma ordenada).
--   TABLA_CONSTRAINT(_HUELLA): PK/FK/CHECK/UNIQUE (pg_get_constraintdef) +
--                             huella determinista del set de constraints.
--   TABLA_TRIGGER(_TOTAL)   : los 6 triggers de inmutabilidad (pg_get_triggerdef)
--                             + conteo (esperado 6).
--   TABLA_ACL / _DETALLE    : ACL real por aclexplode (grantees sensibles a la
--                             Data API; esperado 0) + materializacion.
--   FUNCION_FIRMA           : firma + retorno + lang + volatilidad + secdef, y
--                             hash byte-a-byte del cuerpo via pg_get_functiondef
--                             (comparable TEST<->OPS; ver nota de normalizacion).
--   FUNCION_ACL             : proacl materializado + EXECUTE a sensibles (0).
--   FOTOS_RESUMEN           : total fotos, vigentes, greenfield si/no.
--   FOTOS_POR_PERIODO       : por periodo, foto vigente + clasificacion
--                             CON_DETALLE / PRE_EXTENSION / ANOMALIA.
--   PISO                    : fotos_pre_piso y movimientos_pre_piso (esperado 0).
--
-- Nota de normalizacion (huella vs byte-a-byte): para TABLAS/CONSTRAINTS/
-- TRIGGERS/ACL la comparacion es por HUELLA ESTRUCTURAL DETERMINISTA DE CATALOGO
-- (hash sobre metadata ordenada), no "byte a byte". El byte-a-byte aplica solo a
-- CUERPOS de funcion extraidos con pg_get_functiondef: TEST y OPS estan en la
-- misma version de PostgreSQL, por lo que el md5 del cuerpo es directamente
-- comparable entre ambos. La comparacion del cuerpo contra el artefacto/canonico
-- se hace aparte en el harness (regenerando la funcion y hasheando su
-- pg_get_functiondef alli), porque el formateo del artefacto crudo difiere del
-- de pg_get_functiondef.
--
-- Supuesto: las 3 tablas nuevas estan desplegadas en el entorno (promocion
-- estructural de Bloque 1). Si alguna faltara, los bloques de catalogo la marcan
-- AUSENTE; la referencia directa a liquidacion_participacion (FOTOS_POR_PERIODO)
-- presupone su existencia.
-- ============================================================================

WITH
params AS (
  SELECT
    'test'::text      AS ambiente_esperado,   -- <<< EDITAR POR CORRIDA: 'test' en TEST / 'ops' en OPS
    DATE '2026-07-01' AS piso                  -- D-NEG-02 (piso contable)
),
amb AS (
  SELECT (SELECT valor FROM configuracion_general WHERE clave = 'ambiente') AS ambiente_detectado
),
env AS (
  SELECT p.ambiente_esperado, p.piso, a.ambiente_detectado,
         (p.ambiente_esperado = a.ambiente_detectado) AS ambiente_match
  FROM params p CROSS JOIN amb a
),
-- ---- listas de objetos esperados -------------------------------------------
tbls(nombre) AS (
  VALUES ('liquidacion_participacion'), ('liquidacion_gasto'), ('liquidacion_incidencia')
),
funcs(nombre) AS (
  VALUES ('registrar_snapshot_periodo'), ('liquidacion_vigente'),
         ('saldo_corriente_socio'), ('mayor_socio'), ('reporte_retribucion_operativo_periodo')
),
sensibles(rol) AS (
  VALUES ('public'), ('anon'), ('authenticated'), ('service_role')
),
-- resolucion de oids (LEFT JOIN => AUSENTE visible si falta)
tbl_oid AS (
  SELECT te.nombre, c.oid AS reloid, c.relacl
  FROM tbls te
  LEFT JOIN pg_class c
    ON c.relname = te.nombre
   AND c.relnamespace = 'public'::regnamespace
   AND c.relkind = 'r'
),
fn_oid AS (
  SELECT fe.nombre, p.oid AS procoid, p.prosecdef, p.provolatile, p.prolang, p.proacl
  FROM funcs fe
  LEFT JOIN pg_proc p
    ON p.proname = fe.nombre
   AND p.pronamespace = 'public'::regnamespace
),
ncab AS (SELECT count(*)::int AS n FROM cabanas),
vig AS (
  SELECT lp.periodo, lp.id_liquidacion
  FROM liquidaciones_periodo lp
  WHERE NOT EXISTS (
    SELECT 1 FROM liquidaciones_periodo s
    WHERE s.id_liquidacion_supersede = lp.id_liquidacion
  )
),

-- ==================== BLOQUES DE CHEQUEO (shape uniforme) ====================
-- shape: (seccion text, orden int, sub int, item text, detalle text, valor text, huella text, estado text)

b_amb AS (
  SELECT 'AMBIENTE'::text, 0, 0,
         'guard'::text,
         'ambiente_esperado vs configuracion_general(ambiente)'::text,
         (COALESCE(e.ambiente_esperado,'(null)') || ' / ' || COALESCE(e.ambiente_detectado,'(sin clave)'))::text,
         ''::text,
         (CASE WHEN e.ambiente_match THEN 'MATCH' ELSE 'MISMATCH' END)::text
  FROM env e
),

b_cols AS (
  SELECT 'TABLA_COLUMNAS'::text, 10, 0,
         t.nombre::text,
         (CASE WHEN t.reloid IS NULL THEN 'AUSENTE'
               ELSE 'n_columnas=' || (SELECT count(*) FROM pg_attribute a
                                      WHERE a.attrelid = t.reloid AND a.attnum > 0 AND NOT a.attisdropped)::text
          END)::text,
         (CASE WHEN t.reloid IS NULL THEN ''
               ELSE (SELECT string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || ' ' ||
                                       CASE WHEN a.attnotnull THEN 'NN' ELSE 'null' END, ' | ' ORDER BY a.attnum)
                     FROM pg_attribute a
                     WHERE a.attrelid = t.reloid AND a.attnum > 0 AND NOT a.attisdropped)
          END)::text,
         (CASE WHEN t.reloid IS NULL THEN ''
               ELSE (SELECT md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' ||
                                           CASE WHEN a.attnotnull THEN '1' ELSE '0' END, ',' ORDER BY a.attnum))
                     FROM pg_attribute a
                     WHERE a.attrelid = t.reloid AND a.attnum > 0 AND NOT a.attisdropped)
          END)::text,
         (CASE WHEN t.reloid IS NULL THEN 'AUSENTE' ELSE 'INFO' END)::text
  FROM tbl_oid t
),

b_con AS (
  SELECT 'TABLA_CONSTRAINT'::text, 20, 0,
         (t.nombre || ' :: ' || con.conname)::text,
         (CASE con.contype WHEN 'p' THEN 'PK' WHEN 'f' THEN 'FK' WHEN 'c' THEN 'CHECK'
                           WHEN 'u' THEN 'UNIQUE' ELSE con.contype::text END)::text,
         pg_get_constraintdef(con.oid)::text,
         ''::text,
         'INFO'::text
  FROM tbl_oid t
  JOIN pg_constraint con ON con.conrelid = t.reloid
),

b_con_fp AS (
  SELECT 'TABLA_CONSTRAINT_HUELLA'::text, 21, 0,
         t.nombre::text,
         ('n_constraints=' || count(con.oid)::text)::text,
         ''::text,
         COALESCE(md5(string_agg(con.contype::text || ':' || con.conname || ':' || pg_get_constraintdef(con.oid),
                                 ',' ORDER BY con.conname)), '(0)')::text,
         (CASE WHEN count(con.oid) = 0 AND bool_and(t.reloid IS NULL) THEN 'AUSENTE' ELSE 'INFO' END)::text
  FROM tbl_oid t
  LEFT JOIN pg_constraint con ON con.conrelid = t.reloid
  GROUP BY t.nombre
),

b_trg AS (
  SELECT 'TABLA_TRIGGER'::text, 30, 0,
         (t.nombre || ' :: ' || tg.tgname)::text,
         'trigger'::text,
         pg_get_triggerdef(tg.oid)::text,
         ''::text,
         'INFO'::text
  FROM tbl_oid t
  JOIN pg_trigger tg ON tg.tgrelid = t.reloid AND NOT tg.tgisinternal
),

b_trg_cnt AS (
  SELECT 'TABLA_TRIGGER_TOTAL'::text, 31, 0,
         'inmutabilidad (3 tablas)'::text,
         'esperados=6'::text,
         ('detectados=' || (SELECT count(*) FROM tbl_oid t
                            JOIN pg_trigger tg ON tg.tgrelid = t.reloid AND NOT tg.tgisinternal)::text)::text,
         ''::text,
         (CASE WHEN (SELECT count(*) FROM tbl_oid t
                     JOIN pg_trigger tg ON tg.tgrelid = t.reloid AND NOT tg.tgisinternal) = 6
               THEN 'OK' ELSE 'REVISAR' END)::text
),

b_tacl AS (
  SELECT 'TABLA_ACL'::text, 40, 0,
         t.nombre::text,
         ('acl_materializado=' ||
           CASE WHEN t.reloid IS NULL THEN 'AUSENTE'
                WHEN t.relacl IS NOT NULL THEN 'true'
                ELSE 'false (NULL=default; en tabla, PUBLIC sin acceso)' END)::text,
         ('grantees_sensibles=' ||
           CASE WHEN t.reloid IS NULL THEN '-'
                ELSE (SELECT count(*)::text FROM aclexplode(t.relacl) ax
                      WHERE (CASE WHEN ax.grantee = 0 THEN 'public'
                                  ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)) END)::text,
         ''::text,
         (CASE WHEN t.reloid IS NULL THEN 'AUSENTE'
               WHEN (SELECT count(*) FROM aclexplode(t.relacl) ax
                     WHERE (CASE WHEN ax.grantee = 0 THEN 'public'
                                 ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)) = 0
               THEN 'OK' ELSE 'REVISAR' END)::text
  FROM tbl_oid t
),

b_tacl_det AS (
  SELECT 'TABLA_ACL_DETALLE'::text, 41, 0,
         (t.nombre || ' :: ' || (CASE WHEN ax.grantee = 0 THEN 'public'
                                      ELSE ax.grantee::regrole::text END))::text,
         'privilegio expuesto a Data API'::text,
         ax.privilege_type::text,
         ''::text,
         'REVISAR'::text
  FROM tbl_oid t
  CROSS JOIN LATERAL aclexplode(t.relacl) ax
  WHERE (CASE WHEN ax.grantee = 0 THEN 'public'
              ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)
),

b_fn AS (
  SELECT 'FUNCION_FIRMA'::text, 50, 0,
         f.nombre::text,
         (CASE WHEN f.procoid IS NULL THEN 'AUSENTE'
               ELSE 'args=(' || pg_get_function_identity_arguments(f.procoid) || ') ret=' ||
                    pg_get_function_result(f.procoid) ||
                    ' lang=' || (SELECT lanname FROM pg_language l WHERE l.oid = f.prolang) ||
                    ' vol=' || f.provolatile::text || ' secdef=' || f.prosecdef::text END)::text,
         (CASE WHEN f.procoid IS NULL THEN ''
               ELSE 'len=' || length(pg_get_functiondef(f.procoid))::text END)::text,
         (CASE WHEN f.procoid IS NULL THEN '' ELSE md5(pg_get_functiondef(f.procoid)) END)::text,
         (CASE WHEN f.procoid IS NULL THEN 'AUSENTE' ELSE 'INFO' END)::text
  FROM fn_oid f
),

b_facl AS (
  SELECT 'FUNCION_ACL'::text, 55, 0,
         f.nombre::text,
         (CASE WHEN f.procoid IS NULL THEN 'AUSENTE'
               ELSE 'proacl_materializado=' || (f.proacl IS NOT NULL)::text END)::text,
         (CASE WHEN f.procoid IS NULL THEN '-'
               ELSE 'execute_sensibles=' || (SELECT count(*)::text FROM aclexplode(f.proacl) ax
                     WHERE ax.privilege_type = 'EXECUTE'
                       AND (CASE WHEN ax.grantee = 0 THEN 'public'
                                 ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)) END)::text,
         ''::text,
         (CASE WHEN f.procoid IS NULL THEN 'AUSENTE'
               WHEN f.proacl IS NOT NULL
                    AND (SELECT count(*) FROM aclexplode(f.proacl) ax
                         WHERE ax.privilege_type = 'EXECUTE'
                           AND (CASE WHEN ax.grantee = 0 THEN 'public'
                                     ELSE ax.grantee::regrole::text END) IN (SELECT rol FROM sensibles)) = 0
               THEN 'OK' ELSE 'REVISAR' END)::text
  FROM fn_oid f
),

b_fotos AS (
  SELECT 'FOTOS_RESUMEN'::text, 60, 0,
         'liquidaciones_periodo'::text,
         ('total_fotos=' || (SELECT count(*) FROM liquidaciones_periodo)::text)::text,
         ('vigentes=' || (SELECT count(*) FROM vig)::text ||
          ' | greenfield=' || CASE WHEN (SELECT count(*) FROM liquidaciones_periodo) = 0 THEN 'SI' ELSE 'NO' END)::text,
         ''::text,
         'INFO'::text
),

b_fotos_per AS (
  SELECT 'FOTOS_POR_PERIODO'::text, 65, 0,
         (to_char(v.periodo, 'YYYY-MM-DD') || ' :: liq#' || v.id_liquidacion::text)::text,
         ('n_participacion=' || (SELECT count(*) FROM liquidacion_participacion lp
                                 WHERE lp.id_liquidacion = v.id_liquidacion)::text ||
          ' / n_cabanas=' || (SELECT n FROM ncab)::text)::text,
         (CASE
            WHEN (SELECT count(*) FROM liquidacion_participacion lp WHERE lp.id_liquidacion = v.id_liquidacion) = 0
              THEN 'PRE_EXTENSION (0 participacion)'
            WHEN (SELECT count(*) FROM liquidacion_participacion lp WHERE lp.id_liquidacion = v.id_liquidacion) = (SELECT n FROM ncab)
              THEN 'CON_DETALLE (participacion = cabanas)'
            ELSE 'ANOMALIA (participacion parcial)'
          END)::text,
         ''::text,
         (CASE
            WHEN (SELECT count(*) FROM liquidacion_participacion lp WHERE lp.id_liquidacion = v.id_liquidacion) = 0
              THEN 'PRE_EXTENSION'
            WHEN (SELECT count(*) FROM liquidacion_participacion lp WHERE lp.id_liquidacion = v.id_liquidacion) = (SELECT n FROM ncab)
              THEN 'OK'
            ELSE 'REVISAR'
          END)::text
  FROM vig v
),

b_piso AS (
  SELECT 'PISO'::text, 70, 1,
         'fotos_pre_piso (periodo < piso)'::text,
         ('piso=' || to_char((SELECT piso FROM params), 'YYYY-MM-DD'))::text,
         ('count=' || (SELECT count(*) FROM vig v WHERE v.periodo < (SELECT piso FROM params))::text)::text,
         ''::text,
         (CASE WHEN (SELECT count(*) FROM vig v WHERE v.periodo < (SELECT piso FROM params)) = 0
               THEN 'OK' ELSE 'REVISAR' END)::text
  UNION ALL
  SELECT 'PISO'::text, 70, 2,
         'movimientos_pre_piso (fecha < piso)'::text,
         ('piso=' || to_char((SELECT piso FROM params), 'YYYY-MM-DD'))::text,
         ('count=' || (SELECT count(*) FROM movimientos_socio m WHERE m.fecha < (SELECT piso FROM params))::text)::text,
         ''::text,
         (CASE WHEN (SELECT count(*) FROM movimientos_socio m WHERE m.fecha < (SELECT piso FROM params)) = 0
               THEN 'OK' ELSE 'REVISAR' END)::text
),

todo(seccion, orden, sub, item, detalle, valor, huella, estado) AS (
  SELECT * FROM b_amb
  UNION ALL SELECT * FROM b_cols
  UNION ALL SELECT * FROM b_con
  UNION ALL SELECT * FROM b_con_fp
  UNION ALL SELECT * FROM b_trg
  UNION ALL SELECT * FROM b_trg_cnt
  UNION ALL SELECT * FROM b_tacl
  UNION ALL SELECT * FROM b_tacl_det
  UNION ALL SELECT * FROM b_fn
  UNION ALL SELECT * FROM b_facl
  UNION ALL SELECT * FROM b_fotos
  UNION ALL SELECT * FROM b_fotos_per
  UNION ALL SELECT * FROM b_piso
)
SELECT
  e.ambiente_esperado,
  e.ambiente_detectado,
  e.ambiente_match,
  t.seccion,
  t.item,
  t.detalle,
  t.valor,
  t.huella,
  t.estado
FROM todo t
CROSS JOIN env e
ORDER BY t.orden, t.sub, t.item;
