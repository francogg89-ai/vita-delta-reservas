-- ============================================================================
-- C_SLICE3A_SNAPSHOT_READONLY.sql
-- Carril C / Portal Operativo Interno - Slice 3a (lecturas nuevas A24 / A25).
-- SNAPSHOT READ-ONLY. Solo SELECT / introspeccion de catalogo. CERO writes, CERO DDL.
--
-- OBJETIVO: confirmar contra el ENTORNO REAL (no contra el canonico) las columnas,
-- dominios y datos minimos que necesitan A24 (historico.reservas) y A25
-- (ingresos.cobrados_periodo) ANTES de disenar las queries definitivas.
--
-- REGLAS DURAS:
--   * Ejecutar SOLO en la conexion TEST (ref bdskhhbmcksskkzqkcdp).
--   * OPS es un proyecto Supabase SEPARADO (ref lpiatqztudxiwdlcoasv) con credenciales
--     propias: no se toca aca de ninguna forma.
--   * El SQL Editor de Supabase ejecuta SOLO el texto seleccionado: corre bloque por
--     bloque (S0 PRIMERO). Si S0 no devuelve 'test', DETENER: estas en el entorno
--     equivocado.
--   * Los bloques de DATOS (S5-S11) llevan guard anti-OPS embebido por JOIN al
--     marcador de ambiente: si se corrieran fuera de 'test', el JOIN no matchea
--     y degradan a 0 filas (defensa en profundidad sobre el gate procedural).
--
-- Nada de esto modifica el schema canonico (6B_SCHEMA_SQL.md v1.8.1) ni el Carril B.
-- ============================================================================


-- ===========================================================================
-- S0 -- GATE DE AMBIENTE (CORRER PRIMERO). DEBE devolver exactamente 'test'.
--       Si devuelve 'ops' o vacio: DETENER. No sigas con el resto del archivo.
-- ===========================================================================
SELECT valor AS ambiente_actual
FROM configuracion_general
WHERE clave = 'ambiente';


-- ===========================================================================
-- S1 -- INTROSPECCION: columnas reales de reservas (vs canonico).
--       Confirma fecha_checkin/fecha_checkout/estado/monto_total/monto_sena/
--       canal_origen/created_at para la query y el contrato de A24.
-- ===========================================================================
SELECT ordinal_position, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'reservas'
ORDER BY ordinal_position;


-- ===========================================================================
-- S2 -- INTROSPECCION: columnas reales de pagos.
--       Confirma tipo/medio_pago/estado/monto_recibido/validado_en/created_at/
--       id_reserva/id_prereserva para A24 (saldo_real) y A25 (caja percibida).
-- ===========================================================================
SELECT ordinal_position, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'pagos'
ORDER BY ordinal_position;


-- ===========================================================================
-- S3 -- INTROSPECCION: columnas de huespedes y cabanas (join + privacidad).
--       Para A24 se expone nombre/telefono/email; NUNCA dni ni notas_internas.
-- ===========================================================================
SELECT table_name, ordinal_position, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('huespedes', 'cabanas')
ORDER BY table_name, ordinal_position;


-- ===========================================================================
-- S4 -- DOMINIOS reales: enums de estado (reserva/pago) + CHECK de pagos.
--       Fija los valores validos del filtro 'estado' (A24) y del scope de tipo (A25).
-- ===========================================================================
-- 4a. Valores de los enums de estado.
SELECT t.typname, e.enumlabel, e.enumsortorder
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
WHERE t.typname IN ('estado_reserva_enum', 'estado_pago_enum')
ORDER BY t.typname, e.enumsortorder;

-- 4b. CHECKs de pagos (tipo y medio_pago) tal como estan desplegados.
SELECT con.conname, pg_get_constraintdef(con.oid) AS definicion
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
WHERE c.relname = 'pagos' AND con.contype = 'c'
  AND con.conname IN ('chk_pagos_tipo', 'chk_pagos_medio')
ORDER BY con.conname;


-- ===========================================================================
-- S5 -- A24 / UNIVERSO: conteo de reservas, rango de fecha_checkin y cuantas
--       caen pre-julio. Valida que el FLOOR 2026-07-01 (D-C-11/20) tiene efecto
--       observable o no en los datos actuales de TEST.
-- ===========================================================================
SELECT
  COUNT(*)                                                          AS total_reservas,
  MIN(r.fecha_checkin)                                              AS min_checkin,
  MAX(r.fecha_checkin)                                              AS max_checkin,
  COUNT(*) FILTER (WHERE r.fecha_checkin <  DATE '2026-07-01')      AS pre_julio,
  COUNT(*) FILTER (WHERE r.fecha_checkin >= DATE '2026-07-01')      AS desde_julio
FROM reservas r
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test';


-- ===========================================================================
-- S6 -- A24 / UNIVERSO: distribucion por estado y por cabana presente.
--       Confirma que estados/cabanas existen para probar los filtros.
-- ===========================================================================
-- 6a. Por estado.
SELECT r.estado, COUNT(*) AS n
FROM reservas r
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test'
GROUP BY r.estado
ORDER BY n DESC;

-- 6b. Por cabana (con nombre, para validar el join de A24).
SELECT c.id_cabana, c.nombre, COUNT(r.*) AS n_reservas
FROM cabanas c
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test'
LEFT JOIN reservas r ON r.id_cabana = c.id_cabana
GROUP BY c.id_cabana, c.nombre
ORDER BY c.id_cabana;


-- ===========================================================================
-- S7 -- A25 / UNIVERSO: pagos por tipo x estado (foto cruda del dinero).
--       Confirma que SOLO existen los tipos/estados que asume el diseno.
-- ===========================================================================
SELECT p.tipo, p.estado, COUNT(*) AS n, SUM(p.monto_recibido) AS suma_recibido
FROM pagos p
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test'
GROUP BY p.tipo, p.estado
ORDER BY p.tipo, p.estado;


-- ===========================================================================
-- S8 -- A25 / CAJA PERCIBIDA (D-9G-03): reproduce el criterio del Carril B
--       (mes calendario de created_at, sena+saldo CONFIRMADOS). Muestra TODOS los
--       meses (incluido pre-julio) con flag de scope: A25 SOLO devuelve los meses
--       con dentro_floor_a25 = true (floor D-NEG-02). Comparar contra 9G_CIERRE.
-- ===========================================================================
SELECT
  date_trunc('month', p.created_at)                                              AS mes,
  (date_trunc('month', p.created_at) >= DATE '2026-07-01')                       AS dentro_floor_a25,
  SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('sena','saldo'))                AS ingreso_operativo,
  COUNT(*)              FILTER (WHERE p.tipo IN ('sena','saldo'))                AS n_pagos_operativos,
  SUM(p.monto_recibido) FILTER (WHERE p.tipo = 'extra')                          AS extras_recargos,
  SUM(p.monto_recibido) FILTER (WHERE p.tipo IN ('ajuste','reembolso'))          AS ajustes_reembolsos
FROM pagos p
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test'
WHERE p.estado = 'confirmado'
GROUP BY 1
ORDER BY 1;


-- ===========================================================================
-- S9 -- A25 / DESGLOSE por medio_pago, CON FLOOR APLICADO (created_at >= 2026-07-01).
--       Esto es lo que A25 devuelve realmente: pre-julio se recorta, no se rechaza.
--       Valida el contrato 'por_medio' y que la suma cuadre con el headline floored.
-- ===========================================================================
SELECT
  date_trunc('month', p.created_at)  AS mes,
  p.medio_pago,
  SUM(p.monto_recibido)              AS monto,
  COUNT(*)                           AS n
FROM pagos p
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test'
WHERE p.estado = 'confirmado'
  AND p.tipo IN ('sena','saldo')
  AND p.created_at >= DATE '2026-07-01'   -- FLOOR D-NEG-02 (recorta, no rechaza)
GROUP BY 1, p.medio_pago
ORDER BY 1, p.medio_pago;


-- ===========================================================================
-- S10 -- NORMALIZACION pago->reserva (base de A24.saldo_real y A25 por reserva).
--        Cuenta cuantos pagos resuelven por id_reserva directo vs solo prereserva
--        vs huerfanos. Justifica la CTE COALESCE (D-C-49 / L-9A-01).
-- ===========================================================================
SELECT
  COUNT(*)                                                                          AS total_pagos,
  COUNT(*) FILTER (WHERE p.id_reserva IS NOT NULL)                                  AS con_id_reserva,
  COUNT(*) FILTER (WHERE p.id_reserva IS NULL AND p.id_prereserva IS NOT NULL)      AS solo_prereserva,
  COUNT(*) FILTER (WHERE p.id_reserva IS NULL AND p.id_prereserva IS NULL)          AS huerfanos
FROM pagos p
JOIN configuracion_general cg ON cg.clave = 'ambiente' AND cg.valor = 'test';


-- ===========================================================================
-- S11 -- A24 / saldo_real byte-alineado a A12 (D-C-49): reproduce la regla exacta
--        (universo + CTE de mapeo reserva_por_prereserva con MIN(id_reserva), sin
--        subquery escalar) para una muestra. A24 debe devolver ESTE saldo_real.
-- ===========================================================================
WITH gate AS (
  SELECT 1 FROM configuracion_general WHERE clave = 'ambiente' AND valor = 'test'
),
-- CTE de mapeo desde RESERVAS (NO desde pagos): reservas.id_pre_reserva -> id_reserva.
-- Sale de reservas para no perder senas asociadas SOLO por pre-reserva (D-C-49); si
-- saliera de pagos con id_reserva IS NOT NULL, esas senas no se atribuirian y saldo_real
-- quedaria inflado. OJO naming: reservas.id_pre_reserva (CON guiones) vs pagos.id_prereserva
-- (SIN guiones); ambas referencian pre_reservas.id_pre_reserva.
reserva_por_prereserva AS (
  SELECT id_pre_reserva, MIN(id_reserva) AS id_reserva
  FROM reservas
  WHERE id_pre_reserva IS NOT NULL
  GROUP BY id_pre_reserva
),
pagos_norm AS (
  SELECT
    COALESCE(p.id_reserva, rpp.id_reserva) AS id_reserva,
    p.monto_recibido, p.tipo, p.estado
  FROM pagos p
  LEFT JOIN reserva_por_prereserva rpp ON rpp.id_pre_reserva = p.id_prereserva
)
SELECT
  r.id_reserva,
  r.estado,
  r.fecha_checkin,
  r.monto_total,
  COALESCE(SUM(pn.monto_recibido) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')), 0)            AS cobrado_sena_saldo,
  r.monto_total - COALESCE(SUM(pn.monto_recibido) FILTER (
    WHERE pn.estado = 'confirmado' AND pn.tipo IN ('sena','saldo')), 0)           AS saldo_real
FROM reservas r
CROSS JOIN gate
LEFT JOIN pagos_norm pn ON pn.id_reserva = r.id_reserva
GROUP BY r.id_reserva, r.estado, r.fecha_checkin, r.monto_total
ORDER BY r.id_reserva
LIMIT 25;


-- ===========================================================================
-- S12 -- COLISION DE NOMBRES: confirma que NO existe ya una funcion publica cuyo
--        nombre choque con lo nuevo, y lista funciones de Carril B "de ingreso"
--        (que A25 NO reusa: solo referencia el criterio D-9G-03, sin societario).
-- ===========================================================================
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (
    p.proname ILIKE '%ingreso%'
    OR p.proname ILIKE '%liquidac%'
    OR p.proname ILIKE '%percib%'
    OR p.proname ILIKE '%historic%'
  )
ORDER BY p.proname;

-- FIN DEL SNAPSHOT. Nada de lo anterior escribe ni altera el schema.
