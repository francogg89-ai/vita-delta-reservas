# D1 — DECISIÓN DE FIDELIDAD DE `pg_get_functiondef()`  *(CERRADA)*

**Bloque:** `B1.3-consolidacion-canonica`
**Disparador:** Q8 demostró **EOL mixtos** en los cuerpos vivos: CRLF histórico + bloques B1.3 insertados con LF.
**Estado:** ✅ **CERRADA. Opción C adoptada por Franco.**

> **Documento diagnóstico. Fuera del repo.** No modifica el canónico, ni los satélites, ni TEST.

---

## 1. Decisión

**OPCIÓN C — doble fingerprint. El canónico y el bootstrap son LF-only. TEST queda intacto.**

```
fp_raw = md5(pg_get_functiondef(...))                        -- verifica el VIVO tal como está
fp_lf  = md5(replace(pg_get_functiondef(...), chr(13), ''))  -- verifica contra el CANÓNICO LF-only
```

| | |
|---|---|
| Escritura en TEST | **ninguna** |
| Escritura en OPS al promover | **ninguna** |
| Disciplina LF-only del repo | **respetada** |
| Re-pin de los once | **no** — se agrega un segundo hash |
| Normalización accidental | **detectable** mediante el doble fingerprint. **No queda impedida** |

Las opciones **A** (preservar CRLF en el canónico) y **B** (normalizar el vivo y re-pinear) quedan **descartadas y cerradas**. No se reabren.

---

## 2. El problema, en una línea

El fingerprint es `md5(pg_get_functiondef(oid))` sobre el **texto exacto**, y ese texto **contiene los CR**. Guardar el canónico LF-only y reconstruir desde ahí produce **once fingerprints distintos**, sin que cambie ni un token de SQL.

La opción C no elimina el fenómeno: **lo vuelve medible**. Cada objeto lleva dos hashes, y cada uno responde una pregunta distinta.

---

## 3. Evidencia

### 3.1 El repo ya contenía la prueba

`Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/FUNCION_RESGUARDO.md` es un dump JSON de `pg_get_functiondef(crear_prereserva)`. Los escapes lo muestran literalmente:

```
"CREATE OR REPLACE FUNCTION public.crear_prereserva(payload jsonb)\n
 RETURNS jsonb\n
 LANGUAGE plpgsql\n
AS $function$\r\n
DECLARE\r\n
  v_huesped_payload      JSONB;\r\n
  ...
```

**El header lo genera PostgreSQL y usa LF (`\n`). El `prosrc` está almacenado con CRLF (`\r\n`)** y se emite tal cual. La frontera es exactamente el `AS $function$`.

El fenómeno es **anterior a B1.3**: B1.3 sólo agregó bloques con LF a cuerpos que ya venían con CRLF.

### 3.2 Validación en harness **PostgreSQL 17.10** — los cinco requisitos

El harness se construyó desde `github.com/postgres/postgres`, rama `REL_17_STABLE`, commit `885dc83`
(`apt.postgresql.org` no está en la allowlist de red; se compiló desde fuente).

```
$ /opt/pg17/bin/postgres --version
postgres (PostgreSQL) 17.10
```

Fixture: función con EOL mixto (CRLF histórico + bloque insertado con LF), `SECURITY DEFINER`, `STABLE`, con `proconfig` y ACL revocada — replica el perfil de los objetos B1.3.

**Estado inicial:**

```
fp_raw   = cc070fbc252f734971f657bb1e98c92f
fp_lf    = 89c3df4ea36a4243bfa454b585390df1
cr_count = 8
```

**Se recrea desde su `functiondef` normalizado a LF** — exactamente lo que hará el bootstrap v1.13.0:

```sql
DO $$
DECLARE d text;
BEGIN
  d := replace(pg_get_functiondef('public.demo_mixto(bigint,date)'::regprocedure), chr(13), '');
  EXECUTE 'DROP FUNCTION public.demo_mixto(bigint,date)';
  EXECUTE d;
END $$;
```

**Resultado:**

```
fp_raw_nuevo   = 89c3df4ea36a4243bfa454b585390df1   <-- IDÉNTICO al fp_lf original
fp_lf_nuevo    = 89c3df4ea36a4243bfa454b585390df1
cr_count_nuevo = 0
```

**Cero cambios semánticos** — comparación completa de `pg_proc` contra el snapshot previo:

```
firma_identica               = t     (proname, proargtypes, prorettype, prolang)
flags_identicos              = t     (provolatile, proisstrict, prosecdef,
                                      proleakproof, proparallel, procost, prorows)
proconfig_identico           = t
acl_identico                 = t
prosrc_normalizado_identico  = t
```

| Requisito de Franco | Resultado |
|---|---|
| Recrear desde `functiondef` LF-only | ✅ |
| Volver a extraer `pg_get_functiondef` | ✅ |
| Confirmar `fp_lf` exacto | ✅ `fp_raw_nuevo == fp_lf` original |
| Confirmar equivalencia normalizada | ✅ `fp_lf_nuevo == fp_lf` original |
| Cero cambios semánticos | ✅ los 5 chequeos en `t` |

Log completo: **`D2_VALIDACION_HARNESS_PG17.txt`**.

### 3.3 Por qué la identidad es estructural, no coincidencia

`pg_get_functiondef()` = *header* (siempre LF, lo genera PG) + `$function$` + *prosrc* (con sus EOL literales) + `$function$`.

Si el único portador de CR es el `prosrc`, entonces:

```
md5(functiondef_reconstruido_desde_LF)  ==  md5(replace(functiondef_actual, chr(13), ''))
```

**Queda probado en PG 17.x.** Consecuencia operativa: **los once `fp_lf` son verificables contra el vivo sin escribir una sola línea en TEST**, y son exactamente los hashes que tendría el vivo si se reconstruyera desde el canónico LF-only.

---

## 4. Los once `fp_lf` — CONGELADOS

Calculados por Franco desde el CSV de Q8. Sus `fp_raw` reproducen exactamente los pins de S8.

| Objeto | `fp_raw` | `fp_lf` |
|---|---|---|
| `resolver_horario(bigint,date)` | `1bd96c89e587b15582fd7b2e29ae7e18` | `4acc0e1ca329837f589d87ab45805c30` |
| `_resolver_horario(bigint,date,boolean)` | `7e5bfa21b39d90b674c1a83d76b71b1d` | `b3d56eebd3fdca7305b3010d8630e9f4` |
| `vigencias_conflictos_comprometidos(date,date,boolean,jsonb)` | `c684340c893d8668dc2d74c7564106a8` | `d99fe0016195d1ff4134ab5ce8ef5519` |
| `crear_vigencia_horario(jsonb)` | `1a7d0d2d3507019563cedd376997780d` | `8137c2115bcd2e3ec1c6af618bf051f2` |
| `trg_guard_vigencias()` | `b4e48e49123a4c189609d0adc21730f5` | `275cf44652f567c687eb073565f2ff70` |
| `validar_gap_bordes_congelados(…)` | `5c5ef50eff10db716d17305dcbd54669` | `6c53d905269fcd1bd6087deb43b4bacf` |
| `crear_prereserva(jsonb)` | `62fefb63ef64e443ea2697645cd4e0a8` | `a16f10e6ae9db3c7552b2d813bb6740e` |
| `confirmar_reserva(jsonb)` | `e6ac8ddce8a12a9c48ecc1aa128b311c` | `98871669c650abcc73f1c2b4ee44936f` |
| `crear_reserva_con_horario_pactado(jsonb)` | `93c1700f5940b0e53095e08635e159d0` | `7016058f8e7d98c943c4e007671636cf` |
| `crear_override_horario_puntual(jsonb)` | `33d7ac8ad5f80b72a0266fb4eb4f7f4d` | `d0402e3abb4bcb1943777cf0649b607c` |
| `obtener_disponibilidad_rango(date,date,bigint)` | `37009a32154f93b80520500c0f15b46b` | `1560f8991dc854e0b0155146d1de2718` |

### Fingerprints de `triggerdef`

| Trigger | `md5(pg_get_triggerdef(oid, true))` |
|---|---|
| `trg_vig_guard` | `e8cf4990e3fc36d92ee97198e16085bd` |
| `trg_vig_guard_detalle` | `99a7a7b61631db62b63cf4bebf9d0e54` |

`pg_get_triggerdef` es de una sola línea y **no lleva EOL embebidos**: no necesita doble hash.

---

## 5. Cómo se usa el doble fingerprint

| Verificación | Hash | Contra qué |
|---|---|---|
| ¿TEST/OPS sigue como lo congelamos? | **`fp_raw`** | el vivo, tal cual |
| ¿El canónico v1.13.0 describe fielmente el vivo? | **`fp_lf`** | canónico LF-only |
| ¿Un bootstrap nuevo reprodujo el estado? | **`fp_lf`** | entorno recién creado (nace LF-only ⇒ su `fp_raw` == `fp_lf`) |
| ¿Alguien normalizó el vivo sin avisar? | ambos, **contra los baselines** | ver §5.1 |

### 5.1 Detección de normalización — el criterio correcto

**El doble fingerprint detecta la normalización accidental. No la impide.** La distinción importa: nada bloquea físicamente que alguien recree una función desde texto normalizado. Lo que el esquema garantiza es que **quede en evidencia**.

`fp_raw == fp_lf` **no alcanza como criterio**: sólo dice que el objeto no tiene CR hoy — no distingue *"lo normalizaron sin tocar el texto"* de *"lo normalizaron y además le cambiaron el contenido"*.

**Una normalización exclusivamente física** se identifica con los cuatro predicados juntos, evaluados contra los baselines congelados:

```
cr_baseline      >  0          -- el objeto TENIA CR
fp_raw_actual    != fp_raw_baseline   -- el texto crudo cambio
fp_lf_actual     == fp_lf_baseline    -- pero el texto normalizado NO
cr_actual        =  0          -- y ahora no tiene CR
```

Los cuatro a la vez ⇒ **el diff es exclusivamente físico**: sólo desaparecieron los `\r`. Ni un token de SQL cambió.

**Si `fp_lf` también cambió, hubo un cambio textual**, no una normalización. En ese caso el `fp_lf` es la señal de alarma: alguien tocó el contenido, y hay que ir a mirar el diff.

| `cr_baseline` | `fp_raw` | `fp_lf` | `cr_actual` | Diagnóstico |
|---|---|---|---|---|
| `> 0` | cambió | **igual** | `0` | **Normalización exclusivamente física.** Sin cambio semántico |
| `> 0` | cambió | **cambió** | `0` | **Normalización + cambio textual.** Investigar el diff |
| cualquiera | cambió | **cambió** | `> 0` | Cambio textual, sin normalizar |
| cualquiera | igual | igual | igual | Intacto |

Por eso el D2 emite **`md5_raw`, `md5_lf` y `cantidad_cr`** por objeto: los tres son necesarios. Con dos no alcanza.

---

## 6. Límites — declarados

- La validación corrió en **PG 17.10**; TEST es **PG 17.6**. Misma major; el mecanismo (prosrc preservado byte a byte, header con LF) es idéntico. No se verificó en 17.6 exactamente.
- La identidad de §3.3 supone que **el único portador de CR es el `prosrc`**. Contrastable contra el CSV de Q8: la columna de conteo de CR ya está ahí.
- **`md5(pg_get_functiondef())` no es garantizadamente portable entre major versions de PostgreSQL**, porque el header lo reconstruye el servidor. Inocuo mientras se comparen fingerprints *dentro* de la misma versión — pero **un bootstrap sobre otra major no reproduciría estos hashes**.

  **⇒ El bootstrap kit v1.13.0 debe declarar `PostgreSQL 17.x` como la versión contra la que sus fingerprints son válidos.**

---

## 7. Qué queda pineado en v1.13.0

1. Los **once** objetos con **`fp_raw` + `fp_lf`**.
2. Los **dos** triggers con su `fp_triggerdef`.
3. Los objetos del **D2** (7 funciones + `trg_ov_guard`) — **con el mismo esquema de doble hash**, en cuanto Franco ejecute el set. El D2 ya emite `md5_raw`, `md5_lf` y `cantidad_cr` por objeto.
4. La declaración de versión: **fingerprints válidos para PG 17.x**.
