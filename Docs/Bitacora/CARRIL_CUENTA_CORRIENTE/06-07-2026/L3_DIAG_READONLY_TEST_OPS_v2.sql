-- ============================================================================
-- L3_DIAG_READONLY_TEST_OPS_v2.sql
-- Diagnostico READ-ONLY ASERTIVO para el Bloque 2 (L3 historico). NO escribe.
--
-- Naturaleza: una sola sentencia (WITH ... SELECT). Sin BEGIN, sin DO, sin
-- CREATE TEMP, sin LOCK, sin INSERT/UPDATE/DELETE, sin llamadas a funciones que
-- escriban. Consolida todo en UNA grilla final (correr con NADA seleccionado).
--
-- Uso: correr TAL CUAL en TEST y luego en OPS. Antes de cada corrida, ajustar el
-- literal 'ambiente_esperado' en el CTE params (test u ops). La columna
-- 'ambiente_match' corta visualmente si se corrio en el entorno equivocado.
--
-- Diferencia vs v1 (mas asertivo; no solo informativo):
--   * FUNCION_FIRMA resuelve por FIRMA EXACTA con to_regprocedure() (no por
--     proname): si la firma exacta no existe -> estado REVISAR.
--   * TABLA_COLUMNAS compara n_columnas contra esperado (5 / 19 / 7) -> OK/REVISAR.
--   * CONSTRAINT_RESUMEN: fila por tabla con constraints_esperadas vs detectadas.
--   * CONSTRAINT_PK_COMPUESTA: verifica columnas exactas de la PK compuesta.
--   * CONSTRAINT_FK_COMPUESTA: verifica FK (id_liquidacion,id_gasto) de
--     liquidacion_incidencia -> liquidacion_gasto(id_liquidacion,id_gasto).
--   * CONSTRAINT_CHECKS_NOMBRE: presencia por NOMBRE de los CHECKs del artefacto.
--   * TRIGGER_POR_TABLA: exige exactamente 2 triggers por tabla
--     (trg_<tabla>_no_upd_del, trg_<tabla>_no_truncate), ambos ejecutando
--     trg_9h_inmutable() -> OK/REVISAR (1, 3, nombres o funcion distinta = REVISAR).
--
-- Naturaleza de las comparaciones: TABLAS/CONSTRAINTS/TRIGGERS/ACL se verifican
-- por HUELLA ESTRUCTURAL DETERMINISTA DE CATALOGO y por asercion contra
-- expectativas (conteos, nombres, columnas via conkey/confkey del catalogo, no
-- por texto formateado). El byte-a-byte aplica solo a CUERPOS de funcion via
-- pg_get_functiondef (md5+len): comparable TEST<->OPS (misma version de
-- PostgreSQL). No comparar esos hashes contra un harness de otra version; la
-- comparacion del cuerpo contra el artefacto/canonico se hace aparte en harness.
--
-- Supuesto: las 3 tablas estan desplegadas (promocion estructural de Bloque 1).
-- Si faltara alguna, los bloques de catalogo la marcan AUSENTE/REVISAR; la
-- referencia directa a liquidacion_participacion (FOTOS_POR_PERIODO) presupone
-- su existencia.
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
-- ---- expectativas de objetos (nombre, columnas, constraints, PK) -----------
tbls(nombre, n_col_esp, n_con_esp, pk_cols) AS (
  VALUES
    ('liquidacion_participacion', 5,  5, 'id_liquidacion,id_cabana'),
    ('liquidacion_gasto',         19, 14, 'id_liquidacion,id_gasto'),
    ('liquidacion_incidencia',    7,  7, 'id_liquidacion,id_gasto,seq')
),
-- CHECKs esperados por nombre (definidos explicitamente en el artefacto B1)
chk_esp(tabla, conname) AS (
  VALUES
    ('liquidacion_participacion','chk_lpart_valor_pos'),
    ('liquidacion_gasto','chk_lgasto_clase'),
    ('liquidacion_gasto','chk_lgasto_monto_pos'),
    ('liquidacion_gasto','chk_lgasto_moneda'),
    ('liquidacion_gasto','chk_lgasto_pagador_tipo'),
    ('liquidacion_gasto','chk_lgasto_pagador_cons'),
    ('liquidacion_gasto','chk_lgasto_alcance_clase'),
    ('liquidacion_gasto','chk_lgasto_sin_incidencia_coherente'),
    ('liquidacion_gasto','chk_lgasto_clase_sug'),
    ('liquidacion_gasto','chk_lgasto_motivo_dom'),
    ('liquidacion_incidencia','chk_linc_seq_pos'),
    ('liquidacion_incidencia','chk_linc_destino'),
    ('liquidacion_incidencia','chk_linc_monto_centavos'),
    ('liquidacion_incidencia','chk_linc_destino_socio')
),
-- funciones esperadas por FIRMA EXACTA (to_regprocedure)
fn_esp(nombre, firma) AS (
  VALUES
    ('registrar_snapshot_periodo',            'public.registrar_snapshot_periodo(date,numeric,text,bigint,text)'),
    ('liquidacion_vigente',                   'public.liquidacion_vigente(date)'),
    ('saldo_corriente_socio',                 'public.saldo_corriente_socio(bigint)'),
    ('mayor_socio',                           'public.mayor_socio(bigint)'),
    ('reporte_retribucion_operativo_periodo', 'public.reporte_retribucion_operativo_periodo(date)')
),
sensibles(rol) AS (
  VALUES ('public'), ('anon'), ('authenticated'), ('service_role')
),
-- resolucion de oids
tbl_oid AS (
  SELECT te.nombre, te.n_col_esp, te.n_con_esp, te.pk_cols, c.oid AS reloid, c.relacl
  FROM tbls te
  LEFT JOIN pg_class c
    ON c.relname = te.nombre
   AND c.relnamespace = 'public'::regnamespace
   AND c.relkind = 'r'
),
fn_oid AS (
  SELECT fe.nombre, fe.firma, to_regprocedure(fe.firma)::oid AS procoid,
         p.prosecdef, p.provolatile, p.prolang, p.proacl
  FROM fn_esp fe
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(fe.firma)::oid
),
inmut AS (
  SELECT p.oid FROM pg_proc p
  WHERE p.proname = 'trg_9h_inmutable' AND p.pronamespace = 'public'::regnamespace
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

-- columnas: lista completa + huella + ASERCION n_columnas vs esperado
b_cols AS (
  SELECT 'TABLA_COLUMNAS'::text, 10, 0,
         t.nombre::text,
         (CASE WHEN t.reloid IS NULL THEN 'AUSENTE'
               ELSE 'n_columnas=' || (SELECT count(*) FROM pg_attribute a
                                      WHERE a.attrelid = t.reloid AND a.attnum > 0 AND NOT a.attisdropped)::text
                    || ' / esperado=' || t.n_col_esp::text
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
         (CASE WHEN t.reloid IS NULL THEN 'REVISAR'
               WHEN (SELECT count(*) FROM pg_attribute a
                     WHERE a.attrelid = t.reloid AND a.attnum > 0 AND NOT a.attisdropped) = t.n_col_esp
               THEN 'OK' ELSE 'REVISAR' END)::text
  FROM tbl_oid t
),

-- listado por constraint (referencia; INFO)
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

-- ASERCION: PK compuesta esperada (columnas exactas via conkey)
b_pk AS (
  SELECT 'CONSTRAINT_PK_COMPUESTA'::text, 25, 0,
         t.nombre::text,
         ('pk_esperada=' || t.pk_cols)::text,
         ('pk_actual=' || COALESCE((SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                                    FROM pg_constraint c
                                    CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                                    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
                                    WHERE c.conrelid = t.reloid AND c.contype = 'p'), '(sin PK)'))::text,
         ''::text,
         (CASE WHEN t.reloid IS NULL THEN 'REVISAR'
               WHEN (SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                     FROM pg_constraint c
                     CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                     JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
                     WHERE c.conrelid = t.reloid AND c.contype = 'p') = t.pk_cols
               THEN 'OK' ELSE 'REVISAR' END)::text
  FROM tbl_oid t
),

-- ASERCION: resumen de constraints por tabla (esperadas vs detectadas) + huella
b_con_sum AS (
  SELECT 'CONSTRAINT_RESUMEN'::text, 26, 0,
         t.nombre::text,
         ('constraints_esperadas=' || t.n_con_esp::text ||
          ' / detectadas=' || (SELECT count(*) FROM pg_constraint c WHERE c.conrelid = t.reloid)::text)::text,
         ''::text,
         COALESCE((SELECT md5(string_agg(c.contype::text || ':' || c.conname || ':' || pg_get_constraintdef(c.oid),
                                         ',' ORDER BY c.conname))
                   FROM pg_constraint c WHERE c.conrelid = t.reloid), '(0)')::text,
         (CASE WHEN t.reloid IS NULL THEN 'AUSENTE'
               WHEN (SELECT count(*) FROM pg_constraint c WHERE c.conrelid = t.reloid) = t.n_con_esp
               THEN 'OK' ELSE 'REVISAR' END)::text
  FROM tbl_oid t
),

-- ASERCION: FK compuesta incidencia -> gasto (columnas exactas via conkey/confkey)
b_fk_comp AS (
  SELECT 'CONSTRAINT_FK_COMPUESTA'::text, 27, 0,
         'liquidacion_incidencia -> liquidacion_gasto'::text,
         'esperado: FK (id_liquidacion,id_gasto) REFERENCES liquidacion_gasto(id_liquidacion,id_gasto)'::text,
         (CASE WHEN EXISTS (
                 SELECT 1 FROM pg_constraint c
                 WHERE c.conrelid = (SELECT reloid FROM tbl_oid WHERE nombre = 'liquidacion_incidencia')
                   AND c.contype = 'f'
                   AND c.confrelid = (SELECT reloid FROM tbl_oid WHERE nombre = 'liquidacion_gasto')
                   AND (SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                        FROM unnest(c.conkey) WITH ORDINALITY AS k(n, ord)
                        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.n) = 'id_liquidacion,id_gasto'
                   AND (SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                        FROM unnest(c.confkey) WITH ORDINALITY AS k(n, ord)
                        JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.n) = 'id_liquidacion,id_gasto')
               THEN 'presente (fk_linc_gasto)' ELSE 'NO ENCONTRADA' END)::text,
         ''::text,
         (CASE WHEN EXISTS (
                 SELECT 1 FROM pg_constraint c
                 WHERE c.conrelid = (SELECT reloid FROM tbl_oid WHERE nombre = 'liquidacion_incidencia')
                   AND c.contype = 'f'
                   AND c.confrelid = (SELECT reloid FROM tbl_oid WHERE nombre = 'liquidacion_gasto')
                   AND (SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                        FROM unnest(c.conkey) WITH ORDINALITY AS k(n, ord)
                        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.n) = 'id_liquidacion,id_gasto'
                   AND (SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                        FROM unnest(c.confkey) WITH ORDINALITY AS k(n, ord)
                        JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.n) = 'id_liquidacion,id_gasto')
               THEN 'OK' ELSE 'REVISAR' END)::text
),

-- ASERCION: CHECKs presentes por nombre (los del artefacto B1)
b_chk_nom AS (
  SELECT 'CONSTRAINT_CHECKS_NOMBRE'::text, 28, 0,
         ce.tabla::text,
         ('checks_esperados=' || count(*)::text || ' / presentes=' || count(pc.conname)::text)::text,
         ('faltantes=' || COALESCE(string_agg(CASE WHEN pc.conname IS NULL THEN ce.conname END, ','), '(ninguno)'))::text,
         ''::text,
         (CASE WHEN count(*) = count(pc.conname) THEN 'OK' ELSE 'REVISAR' END)::text
  FROM chk_esp ce
  LEFT JOIN tbl_oid t ON t.nombre = ce.tabla
  LEFT JOIN pg_constraint pc ON pc.conrelid = t.reloid AND pc.conname = ce.conname AND pc.contype = 'c'
  GROUP BY ce.tabla
),

-- listado por trigger (referencia; INFO)
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

-- ASERCION: exactamente 2 triggers por tabla, nombres exactos, ambos trg_9h_inmutable
b_trg_tbl AS (
  SELECT 'TRIGGER_POR_TABLA'::text, 32, 0,
         t.nombre::text,
         ('n_triggers=' || (SELECT count(*) FROM pg_trigger tg
                            WHERE tg.tgrelid = t.reloid AND NOT tg.tgisinternal)::text ||
          ' / ok_esperados=' || (SELECT count(*) FROM pg_trigger tg
                                 WHERE tg.tgrelid = t.reloid AND NOT tg.tgisinternal
                                   AND tg.tgname IN ('trg_' || t.nombre || '_no_upd_del',
                                                     'trg_' || t.nombre || '_no_truncate')
                                   AND tg.tgfoid = (SELECT oid FROM inmut))::text)::text,
         ('esperados: trg_' || t.nombre || '_no_upd_del + trg_' || t.nombre ||
          '_no_truncate (ambos EXECUTE trg_9h_inmutable)')::text,
         ''::text,
         (CASE WHEN t.reloid IS NULL THEN 'AUSENTE'
               WHEN (SELECT count(*) FROM pg_trigger tg
                     WHERE tg.tgrelid = t.reloid AND NOT tg.tgisinternal) = 2
                AND (SELECT count(*) FROM pg_trigger tg
                     WHERE tg.tgrelid = t.reloid AND NOT tg.tgisinternal
                       AND tg.tgname IN ('trg_' || t.nombre || '_no_upd_del',
                                         'trg_' || t.nombre || '_no_truncate')
                       AND tg.tgfoid = (SELECT oid FROM inmut)) = 2
               THEN 'OK' ELSE 'REVISAR' END)::text
  FROM tbl_oid t
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

-- ASERCION: firma EXACTA via to_regprocedure + cuerpo (hash/len) + metadata
b_fn AS (
  SELECT 'FUNCION_FIRMA'::text, 50, 0,
         f.nombre::text,
         (CASE WHEN f.procoid IS NULL THEN 'AUSENTE (firma exacta no encontrada: ' || f.firma || ')'
               ELSE 'firma OK: args=(' || pg_get_function_identity_arguments(f.procoid) || ') ret=' ||
                    pg_get_function_result(f.procoid) ||
                    ' lang=' || (SELECT lanname FROM pg_language l WHERE l.oid = f.prolang) ||
                    ' vol=' || f.provolatile::text || ' secdef=' || f.prosecdef::text END)::text,
         (CASE WHEN f.procoid IS NULL THEN ''
               ELSE 'len=' || length(pg_get_functiondef(f.procoid))::text END)::text,
         (CASE WHEN f.procoid IS NULL THEN '' ELSE md5(pg_get_functiondef(f.procoid)) END)::text,
         (CASE WHEN f.procoid IS NULL THEN 'REVISAR' ELSE 'OK' END)::text
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
         (CASE WHEN f.procoid IS NULL THEN 'REVISAR'
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
  UNION ALL SELECT * FROM b_pk
  UNION ALL SELECT * FROM b_con_sum
  UNION ALL SELECT * FROM b_fk_comp
  UNION ALL SELECT * FROM b_chk_nom
  UNION ALL SELECT * FROM b_trg
  UNION ALL SELECT * FROM b_trg_cnt
  UNION ALL SELECT * FROM b_trg_tbl
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
