-- =====================================================================
-- HORARIOS_DISPONIBILIDAD_RANGO_PASO0_LIVE_TEST.sql   (rev 2)
-- Paso 0 (relevamiento) - Verificacion LIVE de obtener_disponibilidad_rango
--   en TEST, previa al diseno del delta de integracion de resolver_horario().
--
-- ALCANCE: SOLO LECTURA. No escribe, no consume secuencias, no aplica nada,
--   no DDL. Es seguro en cualquier entorno; pensado para correrse en TEST.
--   NO integra, NO reemplaza, NO toca la funcion ni crear_prereserva. Solo lee.
--
-- OBJETIVO:
--   1) Capturar el fingerprint baseline LIVE de obtener_disponibilidad_rango
--      (md5(pg_get_functiondef(...)), mismo metodo que B3 / crear_prereserva).
--      Ese valor sera el baseline que clavara el gate anti-OPS del delta.
--   2) Capturar el fingerprint del resolver_horario LIVE (dependencia dura;
--      el gate del delta exigira que la dependencia sea la esperada) + sus
--      atributos live (provolatile, prosecdef, owner, ACL) para completar el
--      baseline. NO cambia la logica del gate todavia; es diagnostico.
--   3) Confirmar ambiente, schema, existencias, ACL/owner de la ODR (define el
--      metodo de reemplazo).
--   4) Volcar el CUERPO LIVE completo para compararlo con canonico/bootstrap
--      (la fuente real manda si difiere).
--
-- COMO CORRERLO (Supabase SQL Editor):
--   [A] Corré con NADA seleccionado -> ejecuta SOLO [A] (el bloque [B] queda
--       COMENTADO por defecto). Devuelve UNA fila con todo el diagnostico.
--       Pegame esa fila entera (sobre todo los dos fingerprints).
--   [B] Para traer la definicion live: DESCOMENTÁ el bloque [B] (o seleccioná
--       solo esas lineas) y corrélo aparte -> una sola columna 'definicion_live'.
--       Expandí la celda y pegámela integra (asi comparo def viva vs canonico).
--   ( [C] es opcional: cuerpo del resolver. Descomentá y corré solo si te lo pido. )
-- =====================================================================


-- ═════════════════════════════════════════════════════════════════════
-- [A] DIAGNOSTICO EN UNA FILA (contexto + prerequisitos + fingerprints +
--     atributos ODR + atributos resolver). Correr con NADA seleccionado.
--     Devuelve exactamente 1 fila (LEFT JOIN a una fila dummy: si alguna
--     funcion no existiera, sus columnas de pg_proc saldrian NULL en vez de
--     colapsar la fila).
-- ═════════════════════════════════════════════════════════════════════
SELECT
  -- Contexto de entorno
  (SELECT valor FROM configuracion_general WHERE clave = 'ambiente')          AS ambiente,          -- esperado: test
  current_schema()                                                            AS schema_actual,     -- esperado: public

  -- Prerequisitos duros (ambos deben ser true)
  (to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)') IS NOT NULL) AS odr_existe,
  (to_regprocedure('public.resolver_horario(bigint,date)')                  IS NOT NULL) AS resolver_existe,

  -- Fingerprints baseline LIVE (mismo metodo que B3: md5(pg_get_functiondef(...)))
  md5(pg_get_functiondef(
    to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)'))) AS fingerprint_baseline_odr,
  md5(pg_get_functiondef(
    to_regprocedure('public.resolver_horario(bigint,date)')))                  AS fingerprint_resolver,

  -- Atributos LIVE de obtener_disponibilidad_rango (definen el metodo de reemplazo)
  --   esperado: security_definer=false, owner=postgres, acl '{postgres=X/postgres}'
  --   owner-only => CREATE OR REPLACE preserva ACL; DROP la perderia y ademas
  --   voltearia vista_disponibilidad (dependiente de esta funcion).
  p.provolatile                                                               AS odr_provolatile,       -- 'v'=volatile (ODR no es STABLE)
  p.prosecdef                                                                 AS odr_security_definer,  -- esperado: false
  pg_get_userbyid(p.proowner)                                                 AS odr_owner,             -- esperado: postgres
  COALESCE(array_to_string(p.proacl, ', '),
           '(default: PUBLIC EXECUTE)')                                       AS odr_acl,

  -- Atributos LIVE del resolver_horario (dependencia dura; baseline completo)
  --   esperado: provolatile='s' (STABLE), security_definer=false (INVOKER),
  --   owner=postgres, acl '{postgres=X/postgres}' (hardening Bloque 23).
  r.provolatile                                                               AS resolver_provolatile,      -- esperado: 's' (stable)
  r.prosecdef                                                                 AS resolver_security_definer, -- esperado: false
  pg_get_userbyid(r.proowner)                                                 AS resolver_owner,            -- esperado: postgres
  COALESCE(array_to_string(r.proacl, ', '),
           '(default: PUBLIC EXECUTE)')                                       AS resolver_acl,

  -- Firmas exactas resueltas (control: tipos esperados)
  to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')::text AS odr_firma_resuelta,
  to_regprocedure('public.resolver_horario(bigint,date)')::text                  AS resolver_firma_resuelta
FROM (SELECT 1) dummy
LEFT JOIN pg_proc p
  ON p.oid = to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')
LEFT JOIN pg_proc r
  ON r.oid = to_regprocedure('public.resolver_horario(bigint,date)');


-- ═════════════════════════════════════════════════════════════════════
-- [B] CUERPO LIVE COMPLETO de obtener_disponibilidad_rango.
--     COMENTADO por defecto. Para usarlo: descomentá las 2 lineas del SELECT
--     (o seleccionalas) y corrélas APARTE. Una sola columna 'definicion_live'.
--     Pegámela integra: comparo la def viva vs canonico (6B_SCHEMA_SQL.md
--     v1.10.0, Bloque 12) vs bootstrap. Si difiere, la fuente real manda.
-- ═════════════════════════════════════════════════════════════════════
-- SELECT pg_get_functiondef(
--   to_regprocedure('public.obtener_disponibilidad_rango(date,date,bigint)')) AS definicion_live;


-- ═════════════════════════════════════════════════════════════════════
-- [C] (OPCIONAL) CUERPO LIVE del resolver_horario. COMENTADO. Solo si te lo
--     pido: confirma que la dependencia viva coincide con
--     HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql. Con el fingerprint de [A]
--     alcanza para el gate; esto es verificacion extra.
-- ═════════════════════════════════════════════════════════════════════
-- SELECT pg_get_functiondef(
--   to_regprocedure('public.resolver_horario(bigint,date)')) AS resolver_live;
