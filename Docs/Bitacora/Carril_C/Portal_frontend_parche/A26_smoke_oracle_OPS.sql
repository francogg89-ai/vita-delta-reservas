-- ============================================================================
-- A26_smoke_oracle_OPS.sql  --  Carril C / Portal Operativo Interno - Bloque OPS-A
-- Oracle de GROUND TRUTH para el smoke directo de A26 (disponibilidad.cabana).
-- 100% OPS (lpiatqztudxiwdlcoasv). READ-ONLY. No crea ni modifica nada (sin DDL, sin canonico).
--
-- Para que sirve:
--   [A] elegir una cabana ACTIVA para $CabValida y confirmar que la inexistente
--       no aparezca activa;
--   [B] reproducir EXACTO el pre-check del wrapper (1 fila / 0 filas);
--   [C] barrer un rango amplio y elegir $OcupDesde/$OcupHasta y $FechaCheckout;
--   [D] obtener la verdad de la ventana exacta que usa el smoke (T5/T6): el
--       volcado de A26 por n8n debe coincidir fila por fila con esto;
--   [E] ver las filas subyacentes (reservas / bloqueos / pre_reservas) que
--       explican cada estado.
--
-- NOTA (L-8A-01): el editor SQL de Supabase ejecuta SOLO el texto seleccionado.
-- Corre cada bloque [A]..[E] seleccionandolo. Con nada seleccionado corre todo.
-- Editar los literales marcados con  <<<  (cab / fechas) en cada bloque.
-- ============================================================================


-- [A] -------------------------------------------------------------------------
-- Catalogo de cabanas. Elegi una con activa = true para $CabValida.
-- Confirma que $CabInvalida (p.ej. 999999) NO figure como activa.
SELECT id_cabana, nombre, activa
FROM cabanas
ORDER BY id_cabana;


-- [B] -------------------------------------------------------------------------
-- Equivalente EXACTO del pre-check del wrapper:
--   SELECT 1 FROM cabanas WHERE id_cabana = $id AND activa = TRUE;
-- 1 fila  => cabana valida+activa (el wrapper sigue a la funcion).
-- 0 filas => inexistente/inactiva (el wrapper devuelve no_encontrado).
SELECT 1 AS existe
FROM cabanas
WHERE id_cabana = 1          -- <<< id_cabana a chequear
  AND activa = TRUE;


-- [C] -------------------------------------------------------------------------
-- Barrido amplio: dias NO 'disponible' de una cabana en un rango grande.
-- De aca eligis:
--   * una ventana [OcupDesde, OcupHasta) que contenga algo de ocupacion;
--   * una fila con estado 'checkout_disponible' -> $FechaCheckout.
WITH params AS (
  SELECT 1::bigint            AS cab,   -- <<< id_cabana
         (CURRENT_DATE - 30)  AS d1,    -- <<< desde amplio (inclusive)
         (CURRENT_DATE + 200) AS d2     -- <<< hasta amplio (exclusive)
)
SELECT f.id_cabana, f.fecha, f.estado
FROM params p
CROSS JOIN LATERAL obtener_disponibilidad_rango(p.d1, p.d2, p.cab) AS f
WHERE f.estado <> 'disponible'
ORDER BY f.fecha;


-- [D] -------------------------------------------------------------------------
-- GROUND TRUTH de la ventana EXACTA del smoke (debe coincidir con cab/desde/hasta
-- que pongas en A26_smoke_directo_OPS.ps1 -> $CabOcup / $OcupDesde / $OcupHasta).
-- El volcado de T5 (A26 via n8n) tiene que dar fila por fila lo mismo que esto.
-- Recordar intervalo [) : la ultima fila es (hasta - 1 dia), no incluye 'hasta'.
WITH params AS (
  SELECT 1::bigint        AS cab,   -- <<< $CabOcup
         DATE '2026-07-10' AS d1,   -- <<< $OcupDesde (inclusive)
         DATE '2026-07-20' AS d2    -- <<< $OcupHasta (exclusive)
)
SELECT f.fecha, f.estado, f.id_cabana, f.hora_checkin_base, f.hora_checkout_base
FROM params p
CROSS JOIN LATERAL obtener_disponibilidad_rango(p.d1, p.d2, p.cab) AS f
ORDER BY f.fecha;


-- [E1] ------------------------------------------------------------------------
-- Reservas que explican 'ocupada' (estado confirmada/activa, intervalo
-- [fecha_checkin, fecha_checkout)) y 'checkout_disponible' (fecha_checkout = dia).
WITH params AS (
  SELECT 1::bigint AS cab, DATE '2026-07-10' AS d1, DATE '2026-07-20' AS d2  -- <<< igual que [D]
)
SELECT r.id_reserva, r.id_cabana, r.estado, r.fecha_checkin, r.fecha_checkout
FROM reservas r, params p
WHERE r.id_cabana = p.cab
  AND r.estado IN ('confirmada','activa','completada')
  AND r.fecha_checkout > p.d1
  AND r.fecha_checkin  < p.d2
ORDER BY r.fecha_checkin;


-- [E2] ------------------------------------------------------------------------
-- Bloqueos ACTIVOS que explican 'bloqueada'. Incluye el bloqueo TOTAL
-- (id_cabana IS NULL), que afecta a todas las cabanas. Intervalo [fecha_desde, fecha_hasta).
WITH params AS (
  SELECT 1::bigint AS cab, DATE '2026-07-10' AS d1, DATE '2026-07-20' AS d2  -- <<< igual que [D]
)
SELECT b.*
FROM bloqueos b, params p
WHERE b.activo = TRUE
  AND (b.id_cabana = p.cab OR b.id_cabana IS NULL)
  AND b.fecha_hasta > p.d1
  AND b.fecha_desde < p.d2
ORDER BY b.fecha_desde;


-- [E3] ------------------------------------------------------------------------
-- Pre-reservas VIGENTES que explican 'ocupada': pendiente_pago no vencida
-- (expira_en > NOW()) o pago_en_revision. Intervalo [fecha_in, fecha_out).
-- Las pendiente_pago VENCIDAS no aparecen aca y NO bloquean (matriz caso 4).
WITH params AS (
  SELECT 1::bigint AS cab, DATE '2026-07-10' AS d1, DATE '2026-07-20' AS d2  -- <<< igual que [D]
)
SELECT pr.id_cabana, pr.estado, pr.expira_en, pr.fecha_in, pr.fecha_out
FROM pre_reservas pr, params p
WHERE pr.id_cabana = p.cab
  AND ((pr.estado = 'pendiente_pago' AND pr.expira_en > NOW()) OR pr.estado = 'pago_en_revision')
  AND pr.fecha_out > p.d1
  AND pr.fecha_in  < p.d2
ORDER BY pr.fecha_in;
