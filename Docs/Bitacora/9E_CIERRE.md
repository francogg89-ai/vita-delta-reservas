# 9E_CIERRE.md — Cierre parcial Etapa 9E / Carril B

**Etapa:** 9E — Matriz dinámica de participación (derivada, read-only). Tercera sub-etapa de **schema** del Carril B / contabilidad operativa interna.
**Estado:** ✅ **Cerrada y verificada en TEST.** Cierre **parcial** de Carril B (9F–9G siguen pendientes).
**Entorno de validación:** TEST (`vita-delta-test`) — IDs de cabaña 1–5.
**Entorno de operación:** — (9E **no** se promovió a OPS; promoción diferida a la operación coordinada única de todo el Carril B).
**Fecha de cierre:** 2026-06-10.
**Base conceptual:** `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8) §177-192 (matriz dinámica, riesgo compartido); decisiones marco **D-9C-02** (centavo residual) y **D-9C-04 / D-9D-06** (política mensual "cubre el mes completo").
**Depende de:** 9C (catálogo enriquecido + seam) y 9D (activación por rango), ambas cerradas en TEST.
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` — **NO modificado** (sin bump).
**Autores:** Franco (titular, ejecutor de todos los writes) + Claude (arquitecto).
**Decisiones registradas:** D-9E-01 a D-9E-08. **Lecciones:** L-9E-01.

---

## 1. Resumen ejecutivo

9E materializó la **matriz dinámica de participación**: la proporción en que se reparte el pool entre socios en un período, calculada **siempre como consulta** sobre los cuatro insumos (catálogo + valor relativo de 9C + titularidad vía `resolver_beneficiario` de 9C + activación por período de 9D). **No persiste nada** — la matriz se deriva, nunca se guarda (conceptual §177). Es la primera capa puramente funcional de Carril B: **sin tablas nuevas, sin EXCLUDE, sin seed**.

Se construyeron **tres funciones read-only** (`LANGUAGE sql`, `STABLE`, `SECURITY INVOKER`, con `REVOKE EXECUTE`): `matriz_participacion` (proporciones por socio), `repartir_por_matriz` (distribuye un monto dado, con el **centavo residual** de D-9C-02), y `detalle_participacion` (matriz a nivel cabaña para auditoría). Ninguna lee `pagos`: el ingreso entra en la cascada (9G), que consumirá estas funciones; 9E solo reparte proporciones y montos que le pasan.

Aquí aterrizó la **política mensual** ("cubre el mes completo", `daterange @> mes`) y el **centavo residual**, cuya semántica de desempate se fijó explícitamente (D-9E-08). Todo se validó contra el seed real de 9D, incluido el caso difícil del empate de noviembre.

---

## 2. Qué se construyó (funciones de 9E en TEST)

Todas `LANGUAGE sql STABLE SECURITY INVOKER`, sin variables `v_`, con `REVOKE EXECUTE` de `PUBLIC`/`anon`/`authenticated`/`service_role`.

- **`matriz_participacion(p_periodo DATE) RETURNS TABLE(id_socio, valor_socio, valor_pool, participacion)`** — proporciones del mes. Normaliza `p_periodo` al mes (`date_trunc`); una cabaña participa si una activación `@> mes` (D-9D-06); titularidad vía seam; agrupa por beneficiario; `participacion = valor_socio / valor_pool`; devuelve solo socios con participación > 0; pool vacío → 0 filas (sin división por cero).
- **`repartir_por_matriz(p_periodo DATE, p_monto NUMERIC) RETURNS TABLE(id_socio, participacion, monto_asignado)`** — reparte `p_monto` por la matriz. `monto_base = round(p_monto * participacion, 2)`; `residual = p_monto − Σ monto_base` se suma una sola vez al **ganador del residual** (D-9E-08). Garantiza `Σ monto_asignado = p_monto` exacto.
- **`detalle_participacion(p_periodo DATE) RETURNS TABLE(id_cabana, cabana, valor_relativo, id_socio, beneficiario, participa)`** — matriz a nivel cabaña, **todas** las cabañas con flag `participa`, para auditoría/reportes. No persiste.

---

## 3. Semántica del centavo residual (D-9E-08, confirmada — respeta D-9C-02)

D-9C-02: *"al socio de mayor participación del período; en caso de empate, a Rodrigo"*. La interpretación **confirmada por Franco** y aplicada:

1. Se toma el grupo con **máxima `participacion`** del período.
2. Si ese grupo tiene **un solo** socio → gana ese (no hay empate; Rodrigo no interviene).
3. Si hay **empate** en el máximo:
   - si **Rodrigo está dentro** del empate → gana Rodrigo;
   - si **Rodrigo no está** → gana el **menor `id_socio`** entre los empatados.

**Clave:** Rodrigo **no** recibe el residual si no forma parte del empate de mayor participación. Lo contrario ("ante cualquier duda, Rodrigo") violaría D-9C-02; esta regla la respeta.

**Codificación SQL (orden de desempate):** `ORDER BY participacion DESC, (nombre = 'Rodrigo') DESC, id_socio ASC LIMIT 1`. El `participacion DESC` aísla el máximo; `(nombre='Rodrigo') DESC` sube a Rodrigo si está en el empate; si no está, `id_socio ASC` toma el menor.

**Validado en vivo:** noviembre 2026 tiene empate en el máximo entre Franco (178/456) y Remo (178/456), con Rodrigo abajo (100/456). El residual fue a **Franco** (menor `id_socio` entre los empatados), **no a Rodrigo** — exactamente la regla.

---

## 4. Bloques ejecutados (bitácora)

| Bloque | Contenido | Resultado |
|---|---|---|
| **A** | Gate read-only: ambiente `test`, cuatro insumos presentes (valor_relativo 5/5, beneficiario 5/5, seam, `activaciones_operativas` 5 filas), Rodrigo presente, preview de pool, funciones 9E ausentes. | Verde. Preview: julio 4/378, noviembre 5/456. |
| **B** | `matriz_participacion` (DROP+CREATE en runs separados + REVOKE). | OK (julio/noviembre suman 1; pools 378/456; empate nov Franco=Remo=178; junio 0 filas). |
| **C** | `repartir_por_matriz` + `detalle_participacion` (DROP+CREATE + REVOKE). | OK (repartos exactos; residual a Franco en nov; detalle jul 4 / Guatemala no; nov 5; 0 grants). |
| **D** | Verificación consolidada read-only + aislamiento. | Verde (todos OK). |
| **E** | Este documento de cierre parcial. | — |

---

## 5. Resultados de validación (seed real de 9D)

**Matriz julio 2026** (4 activas; Guatemala fuera), pool = 378:

| Socio | valor_socio | participación |
|---|---|---|
| Remo (Bamboo 100 + Tokio 78) | 178 | 0.4709 |
| Franco (Arrebol 100) | 100 | 0.2646 |
| Rodrigo (Madre Selva 100) | 100 | 0.2646 |

**Matriz noviembre 2026** (5 activas), pool = 456:

| Socio | valor_socio | participación |
|---|---|---|
| Franco (Arrebol 100 + Guatemala 78) | 178 | 0.3904 |
| Remo (Bamboo 100 + Tokio 78) | 178 | 0.3904 |
| Rodrigo (Madre Selva 100) | 100 | 0.2193 |

**Reparto exacto (centavo residual):** `repartir_por_matriz` validado con `100000.00`, `100000.01`, `999999.99`, `12345.67` → `Σ monto_asignado = monto` exacto en todos. Residual: julio → Remo (mayor, sin empate); noviembre → Franco (empate con Remo, menor `id_socio`, no Rodrigo).

---

## 6. Decisiones registradas (D-9E-01 .. D-9E-08)

- **D-9E-01** — 9E es **solo funciones read-only**: sin tablas nuevas, sin persistir la matriz (confirma "se deriva, no se guarda", conceptual §177).
- **D-9E-02** — `matriz_participacion(p_periodo DATE)` parametrizada por mes; **normaliza internamente** al mes (cualquier día sirve). Output: `id_socio, valor_socio, valor_pool, participacion`.
- **D-9E-03** — Regla **"cubre el mes completo"** vía `daterange(fecha_desde,fecha_hasta,'[)') @> mes`; titularidad vía `resolver_beneficiario(id_cabana, inicio_mes)`. Hereda D-9D-06. Incluye `detalle_participacion` a nivel cabaña (read-only, auditoría).
- **D-9E-04** — `participacion` como **fracción 0..1** `NUMERIC` sin escala fija, **exponiendo `valor_socio` y `valor_pool`** (transparencia/reproducibilidad). No porcentaje 0..100.
- **D-9E-05** — `repartir_por_matriz` (con centavo residual) **vive en 9E**; reparte un monto dado, **no lee `pagos` ni hace cascada**. 9G lo consumirá.
- **D-9E-06** — **Pool vacío** (`valor_pool=0`): matriz vacía (0 filas), `repartir` vacío (monto no repartible); sin división por cero.
- **D-9E-07** — `REVOKE EXECUTE` de `PUBLIC`/`anon`/`authenticated`/`service_role` (paridad con el seam); `SECURITY INVOKER`. Confirmado: 0 grants expuestos en las 3 funciones.
- **D-9E-08** — **Semántica del centavo residual confirmada** (ver §3): mayor participación; si Rodrigo está en el empate del máximo gana Rodrigo; si no, menor `id_socio` entre los empatados. Rodrigo **no** recibe el residual fuera del empate. Codificado como `ORDER BY participacion DESC, (nombre='Rodrigo') DESC, id_socio ASC LIMIT 1`.

---

## 7. DDL aplicado (registro — fuente hasta el bump del canónico)

```sql
-- matriz_participacion (Bloque B)
DROP FUNCTION IF EXISTS matriz_participacion(DATE);
CREATE FUNCTION matriz_participacion(p_periodo DATE)
RETURNS TABLE (id_socio BIGINT, valor_socio NUMERIC, valor_pool NUMERIC, participacion NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  WITH mes AS (
    SELECT daterange(date_trunc('month', p_periodo)::date,
                     (date_trunc('month', p_periodo) + INTERVAL '1 month')::date, '[)') AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  ),
  participantes AS (
    SELECT resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio, c.valor_relativo
    FROM activaciones_operativas a
    JOIN cabanas c ON c.id_cabana = a.id_cabana
    CROSS JOIN mes m
    WHERE daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango
  ),
  por_socio AS (SELECT id_socio, SUM(valor_relativo) AS valor_socio FROM participantes GROUP BY id_socio),
  total AS (SELECT SUM(valor_socio) AS valor_pool FROM por_socio)
  SELECT s.id_socio, s.valor_socio, t.valor_pool, (s.valor_socio / t.valor_pool) AS participacion
  FROM por_socio s CROSS JOIN total t
  WHERE t.valor_pool > 0
  ORDER BY participacion DESC, s.id_socio;
$$;
REVOKE EXECUTE ON FUNCTION matriz_participacion(DATE) FROM PUBLIC, anon, authenticated, service_role;

-- repartir_por_matriz (Bloque C) — centavo residual D-9E-08
DROP FUNCTION IF EXISTS repartir_por_matriz(DATE, NUMERIC);
CREATE FUNCTION repartir_por_matriz(p_periodo DATE, p_monto NUMERIC)
RETURNS TABLE (id_socio BIGINT, participacion NUMERIC, monto_asignado NUMERIC)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  WITH base AS (
    SELECT m.id_socio, m.participacion, ROUND(p_monto * m.participacion, 2) AS monto_base
    FROM matriz_participacion(p_periodo) m
  ),
  resid AS (SELECT p_monto - COALESCE(SUM(monto_base),0) AS residual FROM base),
  ganador AS (
    SELECT b.id_socio FROM base b JOIN socios s ON s.id_socio = b.id_socio
    ORDER BY b.participacion DESC, (s.nombre = 'Rodrigo') DESC, b.id_socio ASC LIMIT 1
  )
  SELECT b.id_socio, b.participacion,
         b.monto_base + CASE WHEN b.id_socio = (SELECT id_socio FROM ganador)
                             THEN (SELECT residual FROM resid) ELSE 0 END AS monto_asignado
  FROM base b
  ORDER BY b.participacion DESC, b.id_socio;
$$;

-- detalle_participacion (Bloque C) — auditoria
DROP FUNCTION IF EXISTS detalle_participacion(DATE);
CREATE FUNCTION detalle_participacion(p_periodo DATE)
RETURNS TABLE (id_cabana BIGINT, cabana TEXT, valor_relativo NUMERIC,
               id_socio BIGINT, beneficiario TEXT, participa BOOLEAN)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  WITH mes AS (
    SELECT daterange(date_trunc('month', p_periodo)::date,
                     (date_trunc('month', p_periodo) + INTERVAL '1 month')::date, '[)') AS rango,
           date_trunc('month', p_periodo)::date AS inicio
  )
  SELECT c.id_cabana, c.nombre, c.valor_relativo,
         resolver_beneficiario(c.id_cabana, m.inicio) AS id_socio, s.nombre,
         EXISTS (SELECT 1 FROM activaciones_operativas a
                 WHERE a.id_cabana = c.id_cabana
                   AND daterange(a.fecha_desde, a.fecha_hasta, '[)') @> m.rango) AS participa
  FROM cabanas c CROSS JOIN mes m
  JOIN socios s ON s.id_socio = resolver_beneficiario(c.id_cabana, m.inicio)
  ORDER BY c.id_cabana;
$$;

REVOKE EXECUTE ON FUNCTION repartir_por_matriz(DATE, NUMERIC) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION detalle_participacion(DATE)        FROM PUBLIC, anon, authenticated, service_role;
```

> Nota: en TEST los REVOKE se ejecutaron en statements separados por rol (un `REVOKE ... FROM PUBLIC;` por línea). La forma agrupada de arriba es equivalente y se documenta así por brevedad.

---

## 8. Verificación (estado final probado en TEST)

- **Funciones:** las 3 presentes con firma y propiedades correctas (`STABLE`, `SECURITY INVOKER`).
- **Corrección:** matrices de julio y noviembre suman 1.000000; repartos exactos para 4 montos distintos; junio (sin pool) → 0 filas.
- **Residual:** julio → Remo (mayor, sin empate); noviembre → Franco (empate con Remo, menor `id_socio`, no Rodrigo).
- **Detalle:** julio 4 participan / Guatemala no; noviembre 5.
- **Aislamiento:** `EXCLUDE` global sigue = 3 (9E no agrega, es read-only); `cabanas.activa` sin cambios (md5 `facd2112861454dd5699484c22ba265d`); 9D intacta (5 activaciones); 9C intacta (zonas 2 / cabana_zona 5).
- **Grants:** 0 expuestos a roles Data API en las 3 funciones. Ambiente `test`.

---

## 9. Lo que NO se hizo en 9E (alcance respetado)

- **No se tocó OPS.** 9E vive solo en TEST.
- **No se bumpeó el canónico.** `6B_SCHEMA_SQL.md v1.7.3` sigue vigente.
- **No se leyó `pagos`** ni se calculó ingreso (eso es 9G).
- **No se construyó:** la **cascada de 11 pasos (9G)**; el **% operativo** (25→12,5) — **sigue abierto**, sujeto a la conversación de Franco con sus socios; 5%-vs-monotributo; gasto rediseñado (9F); persistencia de la matriz o de liquidaciones (9H); pro-rata diario (latente); saldos internos; fiscal/AFIP/ARCA/IVA; tablas nuevas. **9E no congela la cascada.**
- **No se persiste nada** — todas las funciones son derivación read-only.

---

## 10. Lecciones (para `Lecciones_Aprendidas.md`)

- **L-9E-01** — Reparto de un monto por proporciones con cierre exacto al centavo: redondear solo el reparto base por entidad y sumar el **residual una sola vez** al ganador (no redondear en pasos intermedios). El desempate del ganador se codifica en el `ORDER BY ... LIMIT 1` (criterio primario `participacion DESC`, luego preferencia nombrada, luego `id_socio`), lo que permite expresar reglas de negocio de desempate en SQL puro sin variables ni lógica imperativa. Garantiza `Σ asignado = monto`.

---

## 11. Pendiente para la promoción coordinada (NO ahora)

Todo Carril B se promueve a OPS en **una sola operación**, con aprobación explícita y **bump único** del canónico. Lo que 9E deja anotado:

- **Recrear en OPS** las 3 funciones (`matriz_participacion`, `repartir_por_matriz`, `detalle_participacion`) con la disciplina **DROP+CREATE** + `REVOKE`. Dependen de que 9C (seam, valor_relativo) y 9D (`activaciones_operativas` con la carga real, incluida la desactivación de Guatemala) ya estén en OPS.
- Las funciones son **read-only y no exponen Data API** (REVOKE aplicado); no agregan pendientes de hardening propios más allá de la paridad de grants.

---

## 12. Estado tras 9E y forward pointers

- **Carril B / schema:** 9C, 9D y **9E cerradas y verificadas en TEST**. Quedan listos los insumos estáticos (9C), la activación por período (9D) y la **matriz dinámica + el primitivo de reparto** (9E).
- **Inmediato siguiente:** **9F — gasto rediseñado.** La tabla `gastos` actual es estructuralmente insuficiente (FK de una sola cabaña, sin clase A/C/D/E, `pagado_por` TEXT y no socio, sin separación desembolso/incidencia). 9F rediseña el gasto con las clases, el alcance por zona (`cabana_zona` de 9C) y el **pagador que puede ser un socio** (D-9C-03). La incidencia resuelve a socio por el mismo seam.
- **Después:** **9G — cascada read-only de 11 pasos**, que compone ingreso (lectura de `pagos`) + gasto (9F) + matriz (9E, con `repartir_por_matriz`), aplica el % operativo (cuando Franco lo cierre con sus socios) y produce reportes; sin persistir liquidaciones (eso es 9H).

> **Nota de proceso:** este cierre se redacta **antes** de actualizar los seis satélites (`ESTADO_ACTUAL_VITA_DELTA.md`, `DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `Pendiente_pre_produccion.md`, `6B_SCHEMA_SQL.md`, `CLAUDE.md`). La propagación es el paso siguiente y se hace como conjunto, con Franco aportando los satélites actuales. Hasta entonces, este documento (junto con `9C_CIERRE.md` y `9D_CIERRE.md`) es la fuente del contenido a propagar. El canónico **no** se bumpea en 9E.

---

**Fin de `9E_CIERRE.md` — 9E cerrada y verificada en TEST. Sin OPS, sin bump del canónico, read-only. Carril B continúa en 9F (gasto rediseñado).**
