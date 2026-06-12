-- ============================================================================
-- VITA DELTA · 9H · BLOQUE C — VERIFICACIÓN v2 (endurecida, read-only)
-- Corre tras 9H_BLOQUE_C_FUNCIONES_v3.sql. Devuelve veredicto legible.
-- Endurecimientos vs v1:
--   · firmas EXACTAS vía to_regprocedure (no por proname suelto)
--   · detección de overloads / funciones extra con esos 9 nombres
--   · PUBLIC EXECUTE vía aclexplode(COALESCE(proacl, acldefault('f', proowner)))
--     (captura el caso proacl IS NULL, donde el default da EXECUTE a PUBLIC)
--   · chequeo read-only de ambiente = test
--   · se mantienen volatilidad, SECURITY INVOKER y REVOKE de los 3 roles Data API
-- ============================================================================
WITH firmas(firma, clase, volat) AS (VALUES
  ('public.liquidacion_vigente(date)','L','s'),
  ('public.saldo_corriente_socio(bigint)','L','s'),
  ('public.mayor_socio(bigint)','L','s'),
  ('public.reporte_retribucion_operativo_periodo(date)','L','s'),
  ('public.registrar_snapshot_periodo(date,numeric,text,bigint,text)','W','v'),
  ('public.registrar_retiro(bigint,date,numeric,text,text,text)','W','v'),
  ('public.registrar_movimiento_manual(bigint,date,text,numeric,text,text,date,text)','W','v'),
  ('public.registrar_reversa(bigint,date,text,text)','W','v'),
  ('public.registrar_revaluacion(bigint,date,numeric,numeric,text,text,bigint,text)','W','v')
),
res AS (SELECT f.firma, f.clase, f.volat, to_regprocedure(f.firma) AS oid FROM firmas f),
nombres AS (SELECT ARRAY['liquidacion_vigente','saldo_corriente_socio','mayor_socio',
  'reporte_retribucion_operativo_periodo','registrar_snapshot_periodo','registrar_retiro',
  'registrar_movimiento_manual','registrar_reversa','registrar_revaluacion'] a),
chk AS (
  SELECT '1.010' orden,'FIRMAS' seccion,'9 firmas exactas resueltas (to_regprocedure)' chequeo,'9' esperado,
         (SELECT COUNT(*)::text FROM res WHERE oid IS NOT NULL) obtenido
  UNION ALL SELECT '1.020','FIRMAS','sin overloads/extra: COUNT por nombre = 9','9',
         (SELECT COUNT(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace, nombres
          WHERE n.nspname='public' AND p.proname = ANY(nombres.a))
  UNION ALL SELECT '2.010','VOLAT','4 lectura STABLE + SECURITY INVOKER','4',
         (SELECT COUNT(*)::text FROM res JOIN pg_proc p ON p.oid=res.oid
          WHERE res.clase='L' AND p.provolatile='s' AND p.prosecdef=false)
  UNION ALL SELECT '2.020','VOLAT','5 escritura VOLATILE + SECURITY INVOKER','5',
         (SELECT COUNT(*)::text FROM res JOIN pg_proc p ON p.oid=res.oid
          WHERE res.clase='W' AND p.provolatile='v' AND p.prosecdef=false)
  UNION ALL SELECT '2.030','VOLAT','volatilidad esperada coincide en las 9','9',
         (SELECT COUNT(*)::text FROM res JOIN pg_proc p ON p.oid=res.oid WHERE p.provolatile=res.volat)
  UNION ALL SELECT '3.010','SEG','3 roles Data API SIN EXECUTE en las 9','false',
         (SELECT bool_or(has_function_privilege(r, res.oid, 'EXECUTE'))::text
          FROM res, unnest(ARRAY['anon','authenticated','service_role']) r WHERE res.oid IS NOT NULL)
  UNION ALL SELECT '3.020','SEG','PUBLIC sin EXECUTE (aclexplode + acldefault)','0',
         (SELECT COUNT(*)::text FROM res JOIN pg_proc p ON p.oid=res.oid,
                 aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
          WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  UNION ALL SELECT '4.010','AMBIENTE','configuracion_general ambiente = test','test',
         COALESCE((SELECT valor FROM configuracion_general WHERE clave='ambiente'),'(ausente)')
)
SELECT orden, seccion, chequeo, esperado, obtenido,
       CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END estado FROM chk
UNION ALL
SELECT '99.99','VEREDICTO','Bloque C v3 funciones','FALLO=0',
       (SELECT COUNT(*) FILTER (WHERE obtenido<>esperado)::text FROM chk),
       CASE WHEN (SELECT COUNT(*) FILTER (WHERE obtenido<>esperado) FROM chk)=0
            THEN 'VERDE - 9 firmas exactas, sin overloads, seguras y cerradas a los 4 roles'
            ELSE 'ROJO - revisar filas con estado FALLO' END
ORDER BY orden;
