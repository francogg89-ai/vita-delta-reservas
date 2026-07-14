# D1 — RESULTADOS EN TEST Y FREEZE DE B1.3  *(v2 — corregido)*

**Bloque:** `B1.3-consolidacion-canonica`
**Repo:** HEAD `07fea85802bc4fccbff1236813593762aefe58d9` (rama `main`, árbol limpio)
**Set ejecutado:** `D1_Q0 … D1_Q9` — `sha256(set) = 317a68c1dfd369058105a3f9270e34c5b16fffbeadd0798afa1746bd8e2c4e0a`
**Naturaleza:** 100 % lectura. Ejecutado por Franco en Supabase TEST.

> **Documento diagnóstico. Fuera del repo.**

## Cambios respecto de v1

| # | Corrección |
|---|---|
| 1 | **Los dos fingerprints de `triggerdef` quedan congelados.** Placeholders eliminados |
| 7 | Incorporados los **once `fp_lf`** — opción C adoptada |
| 8 | **Causalidad moderada.** v1 decía *"queda probado que `B1_3_A` sí ejecutó su `DROP`"*. Falso: lo probado es la **ausencia actual** del overload, no el comando que la produjo |

---

## 0. Contexto (Q0)

| Campo | Valor |
|---|---|
| `ambiente` | `test` |
| `transaction_read_only` | `on` |
| Motor | **PostgreSQL 17.6** |
| `server_addr` | `<REDACTADO — IPv6 del pooler de Supabase TEST>` |

**Sanitización — registrada.** La IPv6 real **no se transcribe** a ninguna versión destinada al repo. La salida raw queda **local, en poder de Franco**. Claude nunca recibió ese valor: no existe copia en esta cadena.

---

## 1. Veredicto integral (Q9)

| Criterio | Resultado |
|---|---|
| Objetos presentes | **11 / 11** |
| Fingerprints coincidentes con S8 | **11 / 11** |
| Objetos ausentes | **0** |
| Overloads residuales | **0** |
| `EXECUTE` a `PUBLIC` | **0** |
| Privilegios efectivos `anon` / `authenticated` / `service_role` | **0** |
| Triggers | **exactamente 2, ambos correctos** |
| S3 en DB | **ausente** |
| H4 | **variante 09-07** |
| **`apto_para_freeze`** | **`true`** |
| `motivos_de_bloqueo` | `<ninguno>` |

---

## 2. Los once objetos — CONGELADOS (doble fingerprint, opción C)

`fp_raw` verifica el **vivo tal como está hoy**. `fp_lf` verifica contra el **canónico LF-only**.
Ver `D1_DECISION_FIDELIDAD_FUNCTIONDEF.md`.

| # | Objeto | `fp_raw` = `md5(pg_get_functiondef(…))` | `fp_lf` = `md5(replace(…, chr(13), ''))` |
|---|---|---|---|
| 1 | `public.resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | `4acc0e1ca329837f589d87ab45805c30` |
| 2 | `public._resolver_horario(bigint,date,boolean)` | `7e5bfa21b39d90b674c1a83d76b71b1d` | `b3d56eebd3fdca7305b3010d8630e9f4` |
| 3 | `public.vigencias_conflictos_comprometidos(date,date,boolean,jsonb)` | `c684340c893d8668dc2d74c7564106a8` | `d99fe0016195d1ff4134ab5ce8ef5519` |
| 4 | `public.crear_vigencia_horario(jsonb)` | `1a7d0d2d3507019563cedd376997780d` | `8137c2115bcd2e3ec1c6af618bf051f2` |
| 5 | `public.trg_guard_vigencias()` | `b4e48e49123a4c189609d0adc21730f5` | `275cf44652f567c687eb073565f2ff70` |
| 6 | `public.validar_gap_bordes_congelados(bigint,date,time,date,time,bigint,bigint)` | `5c5ef50eff10db716d17305dcbd54669` | `6c53d905269fcd1bd6087deb43b4bacf` |
| 7 | `public.crear_prereserva(jsonb)` | `62fefb63ef64e443ea2697645cd4e0a8` | `a16f10e6ae9db3c7552b2d813bb6740e` |
| 8 | `public.confirmar_reserva(jsonb)` | `e6ac8ddce8a12a9c48ecc1aa128b311c` | `98871669c650abcc73f1c2b4ee44936f` |
| 9 | `public.crear_reserva_con_horario_pactado(jsonb)` | `93c1700f5940b0e53095e08635e159d0` | `7016058f8e7d98c943c4e007671636cf` |
| 10 | `public.crear_override_horario_puntual(jsonb)` | `33d7ac8ad5f80b72a0266fb4eb4f7f4d` | `d0402e3abb4bcb1943777cf0649b607c` |
| 11 | `public.obtener_disponibilidad_rango(date,date,bigint)` | `37009a32154f93b80520500c0f15b46b` | `1560f8991dc854e0b0155146d1de2718` |

Los `fp_raw` coincidieron 11/11 con los baselines S8. Los `fp_lf` fueron derivados del CSV de Q8 por Franco y **el mecanismo quedó validado en harness PG 17.10** (ver documento de fidelidad).

---

## 3. Fingerprints de `triggerdef` — CONGELADOS

Las definiciones de trigger **no tenían baseline en S8**: se midieron por primera vez en Q4.

| Trigger | Tabla | `md5(pg_get_triggerdef(oid, true))` |
|---|---|---|
| `trg_vig_guard` | `public.vigencias_horario_base` | **`e8cf4990e3fc36d92ee97198e16085bd`** |
| `trg_vig_guard_detalle` | `public.vigencias_horario_detalle` | **`99a7a7b61631db62b63cf4bebf9d0e54`** |

Configuración verificada en ambos (`veredicto` de Q4 = `OK -- exacto y bien configurado`):
trigger-fn `public.trg_guard_vigencias()` (comparada **por OID**, no por texto) · `CONSTRAINT TRIGGER` · `DEFERRABLE` · `INITIALLY DEFERRED` · `enabled` (`tgenabled = 'O'`).

**El freeze de triggers pasa de cualitativo a criptográfico.**

---

## 4. ACL — CONGELADA

| Chequeo | Fuente | Resultado |
|---|---|---|
| `EXECUTE` a `PUBLIC` sobre los 11 | Q3 (`aclexplode` con `COALESCE(proacl, acldefault(…))`) | **0** |
| Privilegios **efectivos** de `anon` / `authenticated` / `service_role` | Q3-BIS (`has_function_privilege`, 33 filas) | **0** |

El `COALESCE` es lo que hace válido el resultado: sin él, un objeto sin hardening (`proacl IS NULL`) se vería como *"sin grants"* cuando en realidad tiene `EXECUTE` a `PUBLIC` por defecto.

---

## 5. Overload residual — AUSENTE  *(afirmación moderada — corrección 8)*

**Q2 reportó 0 overloads residuales.** La firma histórica de siete argumentos de `vigencias_conflictos_comprometidos` (B1.1) **no existe hoy en TEST**. Vive únicamente `(date,date,boolean,jsonb)`, `fp_raw = c684340c…`.

> **Lo que esto prueba:** la **ausencia actual** del overload. No hay ambigüedad de resolución de firma, y no hay callers legacy que buscar: no hay a qué apuntar.
>
> **Lo que NO prueba:** *qué comando histórico* lo eliminó. `08-07/B1_3_A_MIGRACION_SEMANAL_TEST.sql` **contiene** un `DROP FUNCTION …(date,date,boolean,time,time,time,time)`, y el estado vivo es **consistente** con que ese `DROP` haya corrido — pero Q2 lee `pg_proc`, no el log de la base. La atribución es una inferencia razonable, no un hecho medido.

---

## 6. S3 en DB — AUSENTE (Q7)

`crear_paquete_dia_especial(jsonb)` ausente por cuatro vías: `to_regprocedure` nulo · 0 filas en `pg_proc` · 0 dependencias en `pg_depend` · 0 callers DB por texto.

**Gate externo (repo + `Workflows/`): cerrado.** Ver `H7_S3_BARRIDO_REPO_CRUDO_Y_CLASIFICADO.md`.

Misma reserva de causalidad que §5: **la ausencia está probada.** Que la haya producido el `DROP` de `B1_3_F` es **consistente** con el repo y con el cierre de F — el grep no demuestra criptográficamente cuál comando corrió.

---

## 7. H4 — RESUELTO

```
fingerprint_confirmar_reserva  = e6ac8ddce8a12a9c48ecc1aa128b311c
firma_variante_08_07           = false
firma_variante_09_07           = true
```

**La variante desplegada es la del 09-07** (anchor por regex), con el bloque `[B1.3-D:BEGIN]…[B1.3-D:END]` **dentro** del `BEGIN…END` que contiene el `INSERT INTO reservas`.

| Artefacto | Estado |
|---|---|
| `09-07/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | **AUTORIDAD** de `confirmar_reserva` |
| `09-07/B1_3_D_ROLLBACK_TEST.sql` | **El único rollback aplicable al vivo** |
| `08-07/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | **SUPERADO** — no describe el vivo |
| `08-07/B1_3_D_ROLLBACK_TEST.sql` | **SUPERADO** — su anchor literal no existe en el vivo |
| `08-07/B1_3_D_SMOKE_TEST.sql` | Duplicado byte-idéntico del de 09-07 |

> **Riesgo eliminado:** aplicar el rollback del 08-07 contra el vivo habría fallado — o dejado la función en un estado no previsto — porque su `replace()` busca un anchor que la variante desplegada no contiene.

---

## 8. Mapa de callers (Q6)

| Caller | → | Objeto pineado | Carril |
|---|---|---|---|
| `validar_estado_horario_final(bigint,date)` | → | `resolver_horario(bigint,date)` | **Horarios** (S0) |
| `precios_disponibilidad_noches(bigint,date,date)` | → | `obtener_disponibilidad_rango(date,date,bigint)` | **MOTOR DE PRECIOS** ⚠ |
| `vista_disponibilidad` (vista) | → | `obtener_disponibilidad_rango(date,date,bigint)` | Horarios / lectura |

### 8.1 Dependencia cruzada con el Motor de Precios

`precios_disponibilidad_noches` **no pertenece a este carril**. **Se documenta; no se incorpora ese frente a B1.3.**

Implicancia concreta: el ODR tiene un consumidor vivo **fuera del carril**. Cualquier cambio de su firma o de su semántica rompe el Motor de Precios. **El pin no es cosmético: es un contrato entre carriles.**

### 8.2 El freeze de once no cubre toda la superficie viva — **el D2 lo cierra**

`validar_estado_horario_final` es caller ⇒ **existe**, y **no está pineada**. Fuera del pin quedan también:

| Objeto | Artefacto candidato | ¿Vivo? |
|---|---|---|
| `validar_estado_horario_final(bigint,date)` | `04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | **SÍ — probado por Q6** |
| `validar_no_eventos_comprometidos(bigint,date)` | ídem | sin medir |
| `validar_estado_override(bigint,date)` | ídem | sin medir |
| `trg_guard_overrides()` + trigger `trg_ov_guard` | `04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | sin medir — **Q4 nunca lo consultó** |
| `crear_override_horario(jsonb)` | `04-07/HORARIOS_GUARD_S2_FUNCION_TEST.sql` | sin medir |
| `crear_bloqueo(jsonb)`, `fecha_hoy_ar()` | `HORARIOS_B2_GUARD_HELPER_TEST.sql` | sin medir |

**Por qué el D1 no los vio:** Q1/Q2 sólo consultaban los once nombres pineados; Q4 sólo buscaba los triggers de vigencias.

**Lectura correcta de `apto_para_freeze = true`:** los once objetos que B1.3 tocó, más los dos pins, están congelados y verdes. **No** significa que el carril esté inventariado.

**El set `D2` mide esos 7 objetos + `trg_ov_guard`.** Hasta que corra, esos artefactos son `CANDIDATO_REPO_HASTA_D2` en la matriz H3 y **no entran al canónico**.

---

## 9. Estado del freeze

| Ítem | Estado |
|---|---|
| `apto_para_freeze_DB` | ✅ `true` |
| Once `fp_raw` | ✅ congelados |
| Once `fp_lf` | ✅ congelados (opción C) |
| Dos `fp_triggerdef` | ✅ **congelados** |
| ACL | ✅ congelada |
| Overload residual | ✅ ausente (causalidad no atribuida) |
| S3 en DB / repo / workflows | ✅ ausente (causalidad no atribuida) |
| H4 | ✅ 09-07 |
| Mapa de callers | ✅ con dependencia cruzada marcada |
| Fidelidad de `functiondef` | ✅ **CERRADA — opción C**, validada en PG 17.10 |
| Superficie viva fuera del pin | ⛔ **D2 pendiente de ejecución por Franco** |
| Cadena de custodia del A07 | ⛔ **H1 abierto** — bloqueante independiente |

**D2 es el único bloqueante pendiente para cerrar el inventario DB del carril.**

**H1 continúa abierto como bloqueante independiente** para el cierre integral del paquete B1.3 y del artefacto durable A07. Son dos bloqueantes distintos: cerrar el D2 **no** habilita a generar el canónico.
