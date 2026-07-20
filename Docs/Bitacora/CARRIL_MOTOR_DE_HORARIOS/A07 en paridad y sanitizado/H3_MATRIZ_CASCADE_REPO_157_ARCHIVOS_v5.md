# H3 — MATRIZ CASCADE DEL REPO · 157 ARCHIVOS  *(v5 — cierre de inventario)*

**Bloque:** `H3-cierre-inventario` · **Carril:** Motor de Horarios
**Deriva de:** `13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` (**v4 — post-D2**)
**Predecesor:** `H1` — cierre técnico y documental definitivo (`H1_CIERRE_POLITICA_DURABLE_A07.md`)

> **Documento diagnóstico versionado en la Bitácora.**
> **No forma parte del canónico SQL.**

---

## 0. Procedencia y denominador

```
HEAD_BASE_MATRIZ   = 07fea85802bc4fccbff1236813593762aefe58d9
FILAS_BASE         = 107
HEAD_CORTE_H3      = b058de456afd186f91d6ff7e5666978ef4b4df64
ALCANCE            = Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/
TOTAL_VERSIONADOS  = 157
FILAS_DELTA        = 50
```

**El denominador de esta v5 es 157.** Los dos HEAD son coordenadas de **procedencia**, no dos
denominadores alternativos:

| Rango | Origen | HEAD de medición |
|---|---|---|
| Filas **1–107** | heredadas verbatim de la v4, salvo la fila 70 | `07fea85` |
| Filas **108–157** | delta medido, un archivo por fila | `b058de4` |

Entre `07fea85` y `b058de4`: **50 archivos agregados, 0 eliminados**. La numeración 1–107 de la v4 se
conserva sin desplazamientos, de modo que el diff v4→v5 sea auditable fila por fila.

**Esta v5 y el cierre de H3 no son filas de sí mismos.** El universo medido es el del árbol en
`b058de4`; ambos documentos son la *salida* de H3 y no existían en ese HEAD.

**Autoridad ≠ ejecutabilidad, y ninguna de las dos se hereda por fecha de carpeta.** Ver §1.

---

## 1. Matriz autoritativa — criterio de decisión

Existen dos copias de la matriz H3, con las versiones **invertidas** respecto de la fecha de sus
carpetas. Se confirma como autoritativa la copia de **`13-07-2026`** (**v4 — post-D2**). El criterio
**no es la fecha de la carpeta**, que es una etiqueta tipeada a mano, sino tres señales medidas y
convergentes:

| # | Criterio | Evidencia |
|---|---|---|
| 1 | **Contenido** | La v4 es superconjunto estricto de la v3: conserva la sección *Cambios en v3* y le agrega *Cambios en v4*. La derivación es unidireccional. |
| 2 | **Coherencia con D2** | La v3 mantiene 4 filas `PENDIENTE_D2` / `CANDIDATO_REPO_HASTA_D2`. D2 ya corrió en verde con `sha256_lf_vivo = sha256_lf_repo` 7/7. La v4 no tiene ninguna. |
| 3 | **Historial de mantenimiento** | Medido sobre `git log`. Decisivo: ver la tabla siguiente. |

### 1.1 El historial de mantenimiento — la copia de 14-07 es un fósil

| commit | fecha | copia `13-07-2026` | copia `14-07-2026` |
|---|---|---|---|
| `03e20a6` | 2026-07-14 20:11 | `51cc2252…` **v3** | `51cc2252…` **v3** |
| `82f28df` | 2026-07-15 11:00 | `eeac64de…` **v4** | `51cc2252…` |
| `8dd1235` | 2026-07-15 21:43 | `68babb23…` **v4** | `51cc2252…` |
| `b058de4` | 2026-07-18 | `68babb23…` **v4** | `51cc2252…` |

**Las dos copias nacieron byte-idénticas en `03e20a6`.** Después sólo una se mantuvo. La copia de
`14-07-2026` no es "una versión vieja guardada en una carpeta nueva": es un **fósil** del baseline v3
que nunca se volvió a tocar.

`8dd1235` corrigió además un error real de `82f28df`: *"5 de estos 12 son `NO_EJECUTABLE_GATE_OBSOLETO`"*
→ **4**. Verificado por cruce sobre la tabla de datos: de las 12 filas `CONSOLIDAR`, **4** son
`NO_EJECUTABLE_GATE_OBSOLETO` y 8 son `EJECUTABLE`. La v4 a `b058de4` es internamente consistente.

### 1.2 Confirmación independiente — `D2_RUNBOOK.md`

La misma inversión se repite en el otro archivo divergente del par de carpetas: la copia de
`13-07-2026` (12 808 B) es la **POST-D2** y la de `14-07-2026` (12 864 B) es la **PRE-D2**. Dos
archivos distintos, misma dirección de inversión. No es una anomalía de un archivo suelto.

**Regla que queda fijada:** *autoridad por mantenimiento medido, no por etiqueta de carpeta.*

---

## 2. Nota de auditoría — el changelog de la v4 subdeclara

Registrada acá porque afecta la trazabilidad de la derivación v3 → v4 → v5. **No se modifica la v3 ni
la v4.**

El *diff semántico* real v3 → v4 cambió **6 filas**:

```
4, 5, 8, 9, 70, 86
```

El changelog de la v4 declara las filas **4, 8, 9, 86** (y la 16). Por lo tanto:

| Hecho medido | Consecuencia |
|---|---|
| Las filas **5** y **70** cambiaron y **no están declaradas** en el changelog de la v4 | Cambios sólo en `motivo`, coherentes con D2, pero no anunciados |
| La fila **16 no cambió** entre v3 y v4 | El changelog de la v4 la presenta como cambio; en realidad ya venía corregida desde la v3, cuyo propio changelog la declara |

Detalle de las dos filas no declaradas:

- **Fila 5** (`04-07-2026/HORARIOS_GUARD_S1_ROLLBACK_TEST.sql`): `motivo` pasó de *"Vigente si S1 sigue
  vivo (no verificado en D1)"* a *"Vigente: S1 fue confirmado vivo y exacto por D2"*.
- **Fila 70**: `motivo` dejó de citar `2c99db28…` y pasó a citar `3188bceb…`, sin declarar el cambio de
  hash de referencia.

Ninguna de las dos altera clasificación: `estado`, `autoridad_actual` ni `accion_v1_13` quedaron
iguales en ambas. El efecto es de trazabilidad, no de contenido clasificatorio.

---

## 3. Cambios en v5 (respecto de la v4)

| # | Cambio | Alcance |
|---|---|---|
| 1 | **Fila 70 cerrada.** `PENDIENTE_H1`/`BLOQUEADO_H1` → `HISTORICO`/`NO`/`ARCHIVAR_EVIDENCIA` | 1 fila |
| 2 | **50 filas nuevas** (108–157), una por archivo del delta, clasificadas individualmente | 50 filas |
| 3 | **Addendum de procedencia de `2c99db28`** por coordenada inmutable | §6 |
| 4 | **Nota de auditoría** del changelog subdeclarado de la v4 | §2 |
| 5 | **Clasificación de los 7 duplicados** `13-07` / `14-07` | §7 |
| 6 | Denominador redeclarado: 107 → **157**, con los dos HEAD explícitos | §0 |

**Nada más cambió en las filas 1–107.** Rutas, numeración y clasificaciones se conservan verbatim de
la v4 salvo la fila 70. **Ya no quedan filas abiertas:** cero `PENDIENTE_D2`, cero
`CANDIDATO_REPO_HASTA_D2`, cero `PENDIENTE_H1`, cero `BLOQUEADO_H1`.

---

## 4. Diccionario

| Columna | Valores |
|---|---|
| `estado` | `VIGENTE` · `SUPERADO` · `HISTORICO` · `DUPLICADO` · `COLISION_DIVERGENTE` · `CONTAMINACION` |
| `autoridad_actual` | `SI` = probada contra el vivo · `PARCIAL` · `NO`. **Retirados en v5 por agotamiento:** `CANDIDATO_REPO_HASTA_D2` (cerrado por D2) y `PENDIENTE_H1` (cerrado por H1). Se documentan para leer la v3 y la v4. |
| `dominio_autoridad` | `CUERPO_FN` · `TRIGGER` · `DDL` · `ACL` · `APP_FRONTEND` · `APP_N8N` · `NINGUNO` |
| `fragmento_autoritativo` | Qué parte del archivo manda. El gate y el script casi nunca lo son |
| `estado_script` | `EJECUTABLE` · `NO_EJECUTABLE_GATE_OBSOLETO` (aborta: gatea `58d75c1b`) · `NO_APLICA` |
| `accion_v1_13` | **`CONSOLIDAR` = entra al canónico SQL (6B)** · `CITAR` · `ARCHIVAR` · `ARCHIVAR_EVIDENCIA` · `PRESERVAR_APP` · `RECLASIFICAR`. **Retirados en v5 por agotamiento:** `PENDIENTE_D2` y `BLOQUEADO_H1`. |
| `fecha` | Fecha de la carpeta. `(raiz)` para archivos sin carpeta. Para `A07 en paridad y sanitizado/`, que no lleva fecha en el nombre, se usa la del commit que la introdujo: **`b058de4`, 2026-07-18**. |
| `sha256` | **Prefijo SHA-256 de 12 caracteres hexadecimales, NO la huella completa.** Sirve para identificar la fila, no para verificar integridad. Las huellas íntegras están en §7 (duplicados), §8 (runsheets) y §6 (artefactos A07). |

**Tipos agregados en v5** (para el delta): `TXT_HARNESS` · `PATCH_DIFF` · `JSON_EVIDENCIA` ·
`MD_MANIFIESTO` · `MD_GUIA` · `MD_PLAN_PRUEBAS` · `PY_VERIFICADOR` · `JS_NODO_N8N`. Los demás se
reutilizan de la v4 sin cambio de semántica.

---

## 5. Resumen — 157 filas

| estado | n |
|---|---|
| `VIGENTE` | 99 |
| `HISTORICO` | 28 |
| `SUPERADO` | 19 |
| `DUPLICADO` | 6 |
| `CONTAMINACION` | 3 |
| `COLISION_DIVERGENTE` | 2 |

| autoridad_actual | n |
|---|---|
| `NO` | 144 |
| `SI` | 12 |
| `PARCIAL` | 1 |

| accion_v1_13 | n |
|---|---|
| `CITAR` | 72 |
| `ARCHIVAR` | 37 |
| `ARCHIVAR_EVIDENCIA` | 30 |
| `CONSOLIDAR` | 12 |
| `PRESERVAR_APP` | 3 |
| `RECLASIFICAR` | 3 |

| estado_script | n |
|---|---|
| `EJECUTABLE` | 71 |
| `NO_APLICA` | 71 |
| `NO_EJECUTABLE_GATE_OBSOLETO` | 15 |

**12 archivos entran al canónico SQL** (`CONSOLIDAR`) — los mismos 12 de la v4, sin altas ni bajas.
**Cero filas abiertas.**

### 5.1 Por qué el delta no aporta candidatos al canónico

Medición sobre los 50 archivos nuevos. **Los `.sql` del delta son 23**, y conviene desglosarlos porque
el número se presta a confusión: **21 archivos de nombre único** bajo `13-07-2026/` (12 de D1 + 9 de
D2) **más 2 copias duplicadas** bajo `14-07-2026/` (`D2_Q4_TRIGGER_OV_GUARD.sql` y
`D2_Q7_VEREDICTO.sql`). 21 + 2 = **23 filas `.sql`** en la matriz: filas 110–121, 125–131, 133, 134,
142 y 143.

Los 23 no contienen **una sola sentencia DDL o DML no comentada**. Son consultas de diagnóstico read-only, autocontenidas, que abren
`BEGIN TRANSACTION READ ONLY` y traen su propio gate de ambiente sobre
`configuracion_general('ambiente')`. La única coincidencia con patrón DDL en todo el conjunto está en
un **comentario** de `D1_Q2_OVERLOADS.sql` (línea 32). Los 27 restantes son `.md` de cierre, `.txt` de
harness, `.patch`, `.json` de evidencia, 2 `.js` de nodo y 1 `.py` verificador.

**Ninguno de los 50 puede ser autoridad del canónico SQL.** Por eso los 12 `CONSOLIDAR` no se mueven.

---

## 6. Addendum de procedencia — `2c99db28…981c3`

El hash que rondas previas dieron por *"NO LOCALIZADO"*. **No estaba perdido, y tampoco está donde
H1 lo encontró.** Ambas cosas son ciertas, en momentos distintos.

### 6.1 Coordenada inmutable

```
contenido    sha256  2c99db28866a4e9e7e0ec586e5a18fd443a4b91b64b704fcaa833cbe31a981c3
blob Git     sha1    bd731c6817370148023118c8a5de290a4db05858
ruta histórica       Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
tamaño               41 775 B
vigencia desde       9ff6db7   (2026-07-11)  feat(portal): expose L3 account history reads in TEST
último commit
donde estuvo         a2a5893   (2026-07-16)  fix(portal): corregir H-1 y H-2 del historico contable
sustituido en        b058de4   (2026-07-18)  chore(horarios): cerrar H1 y preparar inventario H3
```

**Contenido sustituto — el vigente hoy en la sede canónica:**

```
contenido    sha256  3208b0687e4ef878eb74378173ded2bc5c634cac55ca08f336096de04eaa8fcd
blob Git     sha1    49bf96a4b12e8aea8ea2c2115670006db8a10126
ruta                 Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
tamaño               42 004 B
fijado en            b058de4   (2026-07-18)
```

**Se registra por blob, no por ruta.** El blob SHA-1 es content-addressed: sobrevive a movimientos,
renombres y ediciones futuras del archivo. Una ruta sola, no — y en este caso concreto la ruta ya dejó
de apuntar a ese contenido.

### 6.2 Historia completa de la sede canónica

| commit | fecha | sha256 del contenido |
|---|---|---|
| `47a23db` | 2026-06-20 | `0cbc8ae9f9f3…` |
| `5113d1a` | 2026-06-26 | `593a4597f5b8…` |
| `f477a6b` | 2026-06-30 | `fd79babef468…` |
| `be18fac` | 2026-07-02 | `abee1d0c58e1…` |
| **`9ff6db7`** | **2026-07-11** | **`2c99db28866a…`** |
| **`b058de4`** | **2026-07-18** | **`3208b0687e4e…`** |

`2c99db28` fue el contenido de la sede durante **siete días**. Barrido sobre `git ls-files` a
`b058de4`, archivo por archivo: **hoy no existe en el árbol de trabajo**; sólo es recuperable por blob.

### 6.3 Precisión temporal — qué caducó, qué fue falso negativo y qué no

**No se reescribe H1 ni ningún kickoff histórico.** Pero decir que "no hay nada que corregir" sería
impreciso, y meter las tres afirmaciones históricas en la misma bolsa también: **no son del mismo
tipo de error.**

| Documento | Qué afirma | Naturaleza | Estado hoy |
|---|---|---|---|
| `KICKOFF_B1_3_CONTINUACION_POST_D2.md` §11 | `2c99db28` **NO LOCALIZADO** | **Falso negativo de alcance** — no caducidad | **Corregido** por H1 §2.1 al ampliar el barrido a `Workflows/` |
| `H1_CIERRE_POLITICA_DURABLE_A07.md` §2.1 | `2c99db28` está en la sede canónica | Verdadera contra su HEAD **`a2a5893`**, declarado en sus líneas 8 y 111 | **Caduca en presente**: sustituida en `b058de4` |
| `KICKOFF_H3_CIERRE_INVENTARIO.md` §2.3 y §2.4 | 147 archivos; `2c99db28` en la sede | Verdaderas contra su HEAD **`a2a5893`** | **Caducas en presente**: hoy 157 y `3208b068` |

**La primera no fue una verdad relativa al HEAD.** `2c99db28` **ya estaba versionado en el árbol** en el
momento de esa medición: vivía en `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`,
fijado por `9ff6db7` el 2026-07-11. El barrido que produjo el `NO LOCALIZADO` estaba **acotado a
`Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`**, y por eso no lo vio. Con precisión:

- El resultado era **verdadero únicamente respecto de ese barrido limitado**.
- **No era verdadero como afirmación global sobre el repositorio.** El archivo estaba ahí.
- **H1 corrigió el falso negativo ampliando el alcance a `Workflows/`.**

Las otras dos sí son caducidad genuina: eran verdaderas contra su HEAD declarado y dejaron de serlo
cuando `b058de4` cambió el árbol.

**Precisión que esta v5 debe dejar explícita:** H1 §5 proyectaba la sustitución de la sede canónica
**para el bloque de consolidación**, posterior a H3. En los hechos, esa sustitución **se ejecutó de
forma anticipada en `b058de4`**, el mismo commit que cerró H1 y preparó H3. Es decir: la sede ya está
sustituida *antes* de que H3 cierre, no después. Esto no invalida H1 — al contrario, H1 la había
aprobado — pero adelanta un paso que el propio H1 ubicaba río abajo, y por eso el kickoff de H3 quedó
midiendo un árbol que su commit de origen ya había cambiado. **La consolidación v1.13.0 debe partir de
que la sede canónica del A07 ya es `3208b068…8fcd` y no volver a sustituirla.**

### 6.4 Los cuatro artefactos A07 vigentes en `b058de4` — no confundirlos

| Ruta | sha256 | Bytes | Qué es |
|---|---|---|---|
| `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | `3208b068…8fcd` | 42 004 | **Sede canónica.** Único con autoridad |
| `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/10-07-2026/…TEMPLATE.PATCHED.json` | `3188bceb…6def` | 41 775 | Salida del patcher — **fila 70**, evidencia |
| `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/…__OPS__CANDIDATO_SANITIZADO.json` | `d0342c9c…09c7` | 41 981 | Referencia construida, **no** export real |
| `Docs/Implementacion/Carril_C/PROMOCION_OPS/portal-a07-crear-reserva__OPS.json` | `93641838…a230b` | 40 527 | Export histórico **pre-fix**, sin gaps |

Medición hecha en esta v5: el `jsCode` de `router1_crear` (2 128 ch) y de `router3_confirmar`
(1 831 ch) es **byte-idéntico** entre los extractos `.js` del delta y la sede canónica. Paridad
probada; la autoridad la retiene la sede.

---

## 7. Los 7 duplicados `13-07-2026` / `14-07-2026` — cadena de custodia

Se clasifican en las filas 108–157. **Ninguno se borra ni se mueve:** hay documentos históricos que
citan esas rutas.

Tabla completa, con **SHA-256 íntegros** de cada archivo. Rutas relativas a
`Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`.

| # | Ruta exacta | Bytes | SHA-256 completo | Resultado | Tratamiento |
|---|---|---|---|---|---|
| 1 | `13-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` | 10 064 | `011d263a1853dc2cbb5166108d02f893e8b30f90deff25aa1f6d6ad4237fe126` | **IDÉNTICO** | `14-07` → `DUPLICADO` / `ARCHIVAR` |
| | `14-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` | 10 064 | `011d263a1853dc2cbb5166108d02f893e8b30f90deff25aa1f6d6ad4237fe126` | | |
| 2 | `13-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` | 10 605 | `47bbd414ac7cdb5fe1bce3bf4d3a3cdaf833c501690293b216f1eeb3db390e8d` | **IDÉNTICO** | `14-07` → `DUPLICADO` / `ARCHIVAR` |
| | `14-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` | 10 605 | `47bbd414ac7cdb5fe1bce3bf4d3a3cdaf833c501690293b216f1eeb3db390e8d` | | |
| 3 | `13-07-2026/D2_Q4_TRIGGER_OV_GUARD.sql` | 5 798 | `b4d44fe2cf8d92e68542492f5557721289745fee39c0c7fa6d2eed55f0ca9a61` | **IDÉNTICO** | `14-07` → `DUPLICADO` / `ARCHIVAR` |
| | `14-07-2026/D2_Q4_TRIGGER_OV_GUARD.sql` | 5 798 | `b4d44fe2cf8d92e68542492f5557721289745fee39c0c7fa6d2eed55f0ca9a61` | | |
| 4 | `13-07-2026/D2_Q7_VEREDICTO.sql` | 14 571 | `5f2086d392116bfe6678244f2dd586a34bb597c16b63849821909213127f954d` | **IDÉNTICO** | `14-07` → `DUPLICADO` / `ARCHIVAR` |
| | `14-07-2026/D2_Q7_VEREDICTO.sql` | 14 571 | `5f2086d392116bfe6678244f2dd586a34bb597c16b63849821909213127f954d` | | |
| 5 | `13-07-2026/D2_RUNBOOK.md` | 12 808 | `354d4fba24b2e155989ed75da96018a055cbaa8e15b2f8c7a3257a3c582d2b9b` | **DIVERGENTE** | `14-07` (PRE-D2) → `SUPERADO` / `ARCHIVAR` |
| | `14-07-2026/D2_RUNBOOK.md` | 12 864 | `404841bbc72ca524a10c7f5c665a30b8a7dd01c1c8dc7f3a5f396108e58c8bc9` | | |
| 6 | `13-07-2026/D2_VALIDACION_HARNESS_PG17.txt` | 32 196 | `6d61361787e9fe06903e70c77af6aaf10764c7699572befeb2f9fa2546c1cc78` | **IDÉNTICO** | `14-07` → `DUPLICADO` / `ARCHIVAR` |
| | `14-07-2026/D2_VALIDACION_HARNESS_PG17.txt` | 32 196 | `6d61361787e9fe06903e70c77af6aaf10764c7699572befeb2f9fa2546c1cc78` | | |
| 7 | `13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | 37 715 | `68babb238033a985199e6eab8fbbd766fe55b4640dfdf95fc630bb096901b093` | **DIVERGENTE** | `14-07` (v3) → `SUPERADO` / `ARCHIVAR_EVIDENCIA` |
| | `14-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | 35 910 | `51cc22524b29e4438f73e0e4cd32e67fc8c6576f4fbb2ffb2b4e2916657dca7c` | | |

### 7.1 Lectura de la tabla

- **5 IDÉNTICO** — mismo SHA-256 en ambas rutas. La copia de `13-07-2026` queda `VIGENTE`; la de
  `14-07-2026` queda `DUPLICADO` / `ARCHIVAR`, con `superado_por` apuntando a la primera.
- **2 DIVERGENTE** — SHA-256 distintos. En ambos casos la copia de `13-07-2026` es la **más nueva por
  contenido** pese a estar en la carpeta de fecha anterior:
  - `D2_RUNBOOK.md`: `13-07` es POST-D2, `14-07` es PRE-D2 → `SUPERADO` / `ARCHIVAR`.
  - `H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md`: `13-07` es la **v4**, `14-07` es la **v3** →
    `SUPERADO` / `ARCHIVAR_EVIDENCIA`.

La copia de `13-07-2026` de la matriz queda a su vez `SUPERADO` por esta v5, con
`accion_v1_13 = ARCHIVAR_EVIDENCIA`: es la matriz de la que esta v5 deriva y se conserva intacta.

### 7.2 El octavo archivo

`KICKOFF_B1_3_CONTINUACION_POST_D2.md` existe **sólo** en `14-07-2026`. No es duplicado: fila propia
(**147**), `HISTORICO` / `CITAR`.

---

## 8. Colisión divergente — `HORARIOS_B2_RUNSHEET (1)/(2)`

Filas **87** y **88**, heredadas sin cambio de la v4. **No son duplicados: divergen.** Se declaran
**ambos algoritmos** para evitar la confusión que arrastraban los kickoffs previos, que citaban MD5
donde otros documentos citaban SHA-256:

| Archivo | Bytes | MD5 | SHA-256 |
|---|---|---|---|
| `HORARIOS_B2_RUNSHEET (1).md` | 13 129 | `1a152ac9b7c733f21020af827999e228` | `8497b436780a8eb94d26eabef990584a9f904c717d35b72d97f042344d093e1d` |
| `HORARIOS_B2_RUNSHEET (2).md` | 15 725 | `e0f1b023d42394390cb9f6a9d04a4456` | `c87e4a587c48708fb6545259f3405a4b775e49538966505563158e82920bf388` |

Ambos → `ARCHIVAR`. **No se elige uno por tamaño.** Tras el canónico se genera un
`HORARIOS_B2_RUNSHEET.md` nuevo desde el estado congelado. Eso ocurre en la consolidación, no en H3.

---

## 9. Contaminación de otros carriles — documentada, NO movida

Filas **71**, **72** y **76**, heredadas sin cambio de la v4.

| Fila | Archivo | Bytes | Carril real |
|---|---|---|---|
| 71 | `11-07-2026/CC_L3_BLOQUE0_CIERRE.md` | 15 236 | Cuenta Corriente |
| 72 | `11-07-2026/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md` | 13 880 | Cuenta Corriente |
| 76 | `CIERRE_UI_RETIRO_SALDO_FRONTEND.md` | 16 757 | Frontend / CC |

`CONTAMINACION` / `RECLASIFICAR`. **No se mueven:** mover rompería rutas citadas en documentos
históricos. La reclasificación formal es del carril dueño, no de H3.

---

## 10. Autoridad probada contra el vivo — 12 archivos, uno con autoridad parcial

Sin cambios respecto de la v4. Son los que entran al canónico SQL (`CONSOLIDAR`): los 8 del pin de D1
+ los 4 de D2 (S0/S1/S2/B2-helper), estos últimos con autoridad probada por la comparación directa LF
del cierre de D2.

| Objeto vivo | Artefacto | dominio | estado_script |
|---|---|---|---|
| `resolver_horario` (wrapper) | `06-07/B1_2_CORE_MIGRACION_TEST.sql` | CUERPO_FN | **NO_EJECUTABLE** (gatea 58d75c1b) |
| `_resolver_horario`, `vigencias_conflictos_comprometidos`,<br>`crear_vigencia_horario`, `trg_guard_vigencias`,<br>2 triggers, **DDL de vigencias** | `08-07/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | CUERPO_FN + TRIGGER + DDL + ACL | EJECUTABLE |
| `validar_gap_bordes_congelados` | `08-07/B1_3_B_VALIDADOR_GAP_TEST.sql` | CUERPO_FN + ACL | EJECUTABLE |
| `crear_prereserva` | `08-07/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | CUERPO_FN | EJECUTABLE |
| `confirmar_reserva` | **`09-07/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql`** | CUERPO_FN | EJECUTABLE |
| `crear_reserva_con_horario_pactado` | `09-07/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` | CUERPO_FN + ACL | EJECUTABLE |
| `crear_override_horario_puntual` | `09-07/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | CUERPO_FN + ACL | EJECUTABLE |
| `obtener_disponibilidad_rango` | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | CUERPO_FN | EJECUTABLE |
| **3 validadores S0** (`validar_estado_horario_final`, `validar_no_eventos_comprometidos`, `validar_estado_override`) | **`04-07/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql`** | CUERPO_FN | **NO_EJECUTABLE** (gatea 58d75c1b) |
| **`trg_guard_overrides()` + trigger `trg_ov_guard`** | **`04-07/HORARIOS_GUARD_S1_TRIGGER_TEST.sql`** | CUERPO_FN + TRIGGER | **NO_EJECUTABLE** (gatea 58d75c1b) |
| **`crear_override_horario` (S2)** | **`04-07/HORARIOS_GUARD_S2_FUNCION_TEST.sql`** | CUERPO_FN | **NO_EJECUTABLE** (gatea 58d75c1b) |
| **`crear_bloqueo`, `fecha_hoy_ar`** | **`HORARIOS_B2_GUARD_HELPER_TEST.sql`** | CUERPO_FN | EJECUTABLE (sin gate de fingerprint) |

**El parcial es la fila 30** (`06-07/B1_2_CORE_MIGRACION_TEST.sql`): es autoridad del **wrapper**
`resolver_horario`, pero su `_resolver_horario` y su helper fueron superados por A. Queda con
autoridad `PARCIAL` — **ya contado dentro de los 12 `CONSOLIDAR`, no es un archivo número 13.**

**Autoridad ≠ ejecutabilidad.** 4 de estos 12 artefactos son `NO_EJECUTABLE_GATE_OBSOLETO`: su gate
espera el resolver viejo `58d75c1b` y abortan hoy. El canónico se arma del **cuerpo** de la función
(probado idéntico al vivo), no de re-ejecutar el script.

---

## 11. Matriz — 157 filas

**Filas 1–107:** heredadas de la v4 contra `07fea85`, verbatim salvo la fila 70.
**Filas 108–157:** delta medido contra `b058de4`.

| # | ruta | fecha | bloque | tipo | estado | autoridad_actual | dominio_autoridad | fragmento_autoritativo | estado_script | referencia_viva | superado_por | accion_v1_13 | motivo | sha256 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `04-07-2026/HORARIOS_GUARD_ALTA_OVERRIDES_CIERRE_TECNICO_PRELIMINAR.md` | 04-07-2026 | GUARD-cierre | MD_CIERRE | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar de S0-S3. S3 ya no existe; el resto sigue vivo pero sin pin. | `3ee96779128f` |
| 2 | `04-07-2026/HORARIOS_GUARD_S0_RUNSHEET.md` | 04-07-2026 | GUARD-S0 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de S0. Negative-scope explicito sobre S1/S2/S3. | `18f88c2cb5ed` |
| 3 | `04-07-2026/HORARIOS_GUARD_S0_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S0 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | `validar_estado_horario_final` | — | ARCHIVAR | Smoke de S0. Helpers temporales en BEGIN..ROLLBACK. | `dc06fc3a5e41` |
| 4 | `04-07-2026/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | 04-07-2026 | GUARD-S0 | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN | CREATE de los 3 validadores S0 (no el gate, no el script) | **NO_EJECUTABLE_GATE_OBSOLETO** | `validar_estado_horario_final, validar_no_eventos_comprometidos, validar_estado_override` | — | **CONSOLIDAR** | Autoridad de los 3 validadores S0 (validar_estado_horario_final, validar_no_eventos_comprometidos, validar_estado_override). D2: comparacion directa LF vivo==repo, 3/3. Script NO re-ejecutable (gate 58d75c1b). | `4708bb164965` |
| 5 | `04-07-2026/HORARIOS_GUARD_S1_ROLLBACK_TEST.sql` | 04-07-2026 | GUARD-S1 | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `trg_ov_guard, trg_guard_overrides` | — | CITAR | Rollback de S1. Vigente: S1 fue confirmado vivo y exacto por D2. La aplicabilidad destructiva del rollback no fue ejecutada en este bloque. | `cde0bc9bd5ed` |
| 6 | `04-07-2026/HORARIOS_GUARD_S1_RUNSHEET.md` | 04-07-2026 | GUARD-S1 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de S1. | `737f137b0e3b` |
| 7 | `04-07-2026/HORARIOS_GUARD_S1_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S1 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | `trg_ov_guard` | — | ARCHIVAR | Smoke de S1. | `dd3f8f5ed124` |
| 8 | `04-07-2026/HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | 04-07-2026 | GUARD-S1 | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + TRIGGER | CREATE trg_guard_overrides() + CREATE CONSTRAINT TRIGGER trg_ov_guard (lin. 152-155) | **NO_EJECUTABLE_GATE_OBSOLETO** | `trg_guard_overrides, trg_ov_guard` | — | **CONSOLIDAR** | Autoridad de trg_guard_overrides() y del trigger trg_ov_guard. D2: comparacion directa LF vivo==repo + fp_triggerdef vivo==repo. Script NO re-ejecutable (gate 58d75c1b). | `7bcef3c4c1fc` |
| 9 | `04-07-2026/HORARIOS_GUARD_S2_FUNCION_TEST.sql` | 04-07-2026 | GUARD-S2 | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN | CREATE de crear_override_horario(jsonb) | **NO_EJECUTABLE_GATE_OBSOLETO** | `crear_override_horario` | — | **CONSOLIDAR** | Autoridad de crear_override_horario(jsonb). D2: comparacion directa LF vivo==repo. Script NO re-ejecutable (gate 58d75c1b). | `632adaac7363` |
| 10 | `04-07-2026/HORARIOS_GUARD_S2_ROLLBACK_TEST.sql` | 04-07-2026 | GUARD-S2 | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `crear_override_horario` | — | CITAR | Rollback de S2. | `a200c7a6580b` |
| 11 | `04-07-2026/HORARIOS_GUARD_S2_RUNSHEET.md` | 04-07-2026 | GUARD-S2 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de S2. | `5d27dd404857` |
| 12 | `04-07-2026/HORARIOS_GUARD_S2_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S2 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | `crear_override_horario` | — | ARCHIVAR | Smoke de S2. | `bf6548df2811` |
| 13 | `04-07-2026/HORARIOS_GUARD_S3_FUNCION_TEST.sql` | 04-07-2026 | GUARD-S3 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | CREA crear_paquete_dia_especial (S3). S3 AUSENTE del vivo (Q7). Reemplazada por F. | `c6cf43e1abe8` |
| 14 | `04-07-2026/HORARIOS_GUARD_S3_ROLLBACK_TEST.sql` | 04-07-2026 | GUARD-S3 | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | Dropea S3. Ya no aplica: S3 no existe. | `ded094625308` |
| 15 | `04-07-2026/HORARIOS_GUARD_S3_RUNSHEET.md` | 04-07-2026 | GUARD-S3 | MD_RUNSHEET | **SUPERADO** | NO | NINGUNO | — | NO_APLICA | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | Runsheet de S3. | `d36512ce5a5d` |
| 16 | `04-07-2026/HORARIOS_GUARD_S3_SMOKES_TEST.sql` | 04-07-2026 | GUARD-S3 | SQL_SMOKE | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | ARCHIVAR | 21 invocaciones reales de S3 (barrido H7). Inejecutable: S3 no existe. | `2caa6a765090` |
| 17 | `04-07-2026/HORARIOS_R0_RESOLVER_FIX_TEST.sql` | 04-07-2026 | R0-resolver | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Fix R0 de resolver_horario. B1.2-CORE reescribio wrapper + interno. | `41bc861abb0d` |
| 18 | `04-07-2026/HORARIOS_R0_RESOLVER_PREFLIGHT_TEST.sql` | 04-07-2026 | R0-resolver | SQL_DIAG | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Preflight diagnostico de R0. | `8c54bbe47625` |
| 19 | `04-07-2026/HORARIOS_R0_RESOLVER_ROLLBACK_TEST.sql` | 04-07-2026 | R0-resolver | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Rollback de un fix superado. | `202061b03cad` |
| 20 | `04-07-2026/HORARIOS_R0_RESOLVER_RUNSHEET.md` | 04-07-2026 | R0-resolver | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de R0. | `459f378bd18b` |
| 21 | `04-07-2026/HORARIOS_R0_RESOLVER_SMOKES_TEST.sql` | 04-07-2026 | R0-resolver | SQL_SMOKE | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Smokes de R0. | `db39b76feb1c` |
| 22 | `05-07-2026/B1_1_CREAR_VIGENCIA_FUNCION_TEST.sql` | 05-07-2026 | B1.1 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Firma B1.1 de vigencias_conflictos_comprometidos (7 args) + crear_vigencia_horario. Ambas reemplazadas por A (jsonb). | `d80a9a0e1fb0` |
| 23 | `05-07-2026/B1_1_GUARD_TRIGGER_TEST.sql` | 05-07-2026 | B1.1 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Version B1.1 de trg_guard_vigencias + los 2 triggers. A los recrea. | `5c834f714482` |
| 24 | `05-07-2026/B1_1_ROLLBACK_TEST.sql` | 05-07-2026 | B1.1 | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Rollback de B1.1. | `44b2f486d223` |
| 25 | `05-07-2026/B1_1_SMOKES_TEST.sql` | 05-07-2026 | B1.1 | SQL_SMOKE | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Smokes contra la firma de 7 args. | `384780f68a66` |
| 26 | `05-07-2026/B1_1_VIGENCIAS_DDL_TEST.sql` | 05-07-2026 | B1.1 | SQL_DDL | **SUPERADO** | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | DDL original de vigencias_horario_base/detalle. A las DROPEA y RECREA (lineas 107-132) => A es la autoridad del DDL. | `3abc356e0d1b` |
| 27 | `05-07-2026/B1_1_VIGENCIAS_HORARIO_BASE_CIERRE_TECNICO_PRELIMINAR.md` | 05-07-2026 | B1.1 | MD_CIERRE | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar B1.1. | `030820727e9b` |
| 28 | `05-07-2026/B1_2_PRE_BASELINE_PERF_120D_TEST.sql` | 05-07-2026 | B1.2-PRE | SQL_DIAG | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | — | ARCHIVAR | Baseline de performance pre-B1.2. Diagnostico. | `80fa4c86b3c1` |
| 29 | `05-07-2026/B1_2_PRE_DIAGNOSTICO_G1_TEST.sql` | 05-07-2026 | B1.2-PRE | SQL_DIAG | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | — | ARCHIVAR | Diagnostico G1 pre-B1.2. | `09b98b8be664` |
| 30 | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_MIGRACION | VIGENTE | **PARCIAL** | CUERPO_FN | CREATE de resolver_horario (wrapper). Su _resolver_horario y el helper fueron superados por A | **NO_EJECUTABLE_GATE_OBSOLETO** | `resolver_horario` | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | **CONSOLIDAR** | AUTORIDAD de resolver_horario (wrapper INTACTO, fp 1bd96c89). Su _resolver_horario y vigencias_conflictos_comprometidos fueron superados por A. | `f88f7d2e87b3` |
| 31 | `06-07-2026/B1_2_CORE_ROLLBACK_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_ROLLBACK | HISTORICO | NO | NINGUNO | — | **NO_EJECUTABLE_GATE_OBSOLETO** | — | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | ARCHIVAR | Rollback de B1.2-CORE. | `42827c111002` |
| 32 | `06-07-2026/B1_2_CORE_SMOKE_PERF_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Smoke de performance B1.2. | `1ef1fcfa53d2` |
| 33 | `06-07-2026/B1_2_CORE_SMOKE_RUTAS_TEST.sql` | 06-07-2026 | B1.2-CORE | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Smoke de rutas B1.2. | `1aec6e2f66a9` |
| 34 | `06-07-2026/CIERRE_TECNICO_PRELIMINAR_B1_2_CORE.md` | 06-07-2026 | B1.2-CORE | MD_CIERRE | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar B1.2-CORE. | `e62de3f15ebd` |
| 35 | `06-07-2026/INVENTARIO_Y_BARRIDO_B1_2_CASCADE.md` | 06-07-2026 | B1.2-CASCADE | MD_INVENTARIO | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Inventario del barrido B1.2-CASCADE (nunca implementado). | `cb38ec33209d` |
| 36 | `06-07-2026/KICKOFF_B1_2_CASCADE.md` | 06-07-2026 | B1.2-CASCADE | MD_KICKOFF | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Kickoff de B1.2-CASCADE. Abandonado por el pivote semanal. | `e07c594a6b96` |
| 37 | `07-07-2026/DISENO_DETALLADO_B1_2_CASCADE.md` | 07-07-2026 | B1.2-CASCADE | MD_DISENO | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | `07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md` | CITAR | Diseno de B1.2-CASCADE. Descartado por el pivote a vigencias semanales. | `756dae091aa5` |
| 38 | `07-07-2026/EVALUACION_PIVOTE_VIGENCIAS_SEMANALES.md` | 07-07-2026 | pivote-semanal | MD_DISENO | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Decision del pivote a vigencias semanales. Fundamento de B1.3. | `e67acada0c2a` |
| 39 | `07-07-2026/KICKOFF_B1_3_VIGENCIAS_SEMANALES.md` | 07-07-2026 | B1.3-kickoff | MD_KICKOFF | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Kickoff de B1.3. | `7c2a9c2fcdb1` |
| 40 | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | 08-07-2026 | B1.3-A | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + TRIGGER + DDL + ACL | CREATE de 4 fns + 2 triggers + DDL de vigencias (lin. 107-132) + REVOKEs | EJECUTABLE | `_resolver_horario, vigencias_conflictos_comprometidos, crear_vigencia_horario, trg_guard_vigencias, trg_vig_guard, trg_vig_guard_detalle, DDL vigencias` | — | **CONSOLIDAR** | AUTORIDAD de 4 de los 11 + los 2 triggers + el DDL de vigencias. Dropea el overload de 7 args (consistente con Q2 (0 overloads): la ausencia esta probada, no el comando que la produjo). | `f5cf08b3a51c` |
| 41 | `08-07-2026/B1_3_A_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-A | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de A. Vigente. | `31c2244def3b` |
| 42 | `08-07-2026/B1_3_A_SMOKE_TEST.sql` | 08-07-2026 | B1.3-A | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de A. Vigente. | `5aa95dad7419` |
| 43 | `08-07-2026/B1_3_B_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-B | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de B. Vigente. | `a6eecc988934` |
| 44 | `08-07-2026/B1_3_B_SMOKE_TEST.sql` | 08-07-2026 | B1.3-B | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de B. Vigente. | `61c2fcef5a83` |
| 45 | `08-07-2026/B1_3_B_VALIDADOR_GAP_TEST.sql` | 08-07-2026 | B1.3-B | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + ACL | CREATE de validar_gap_bordes_congelados + REVOKE | EJECUTABLE | `validar_gap_bordes_congelados` | — | **CONSOLIDAR** | AUTORIDAD de validar_gap_bordes_congelados (fp 5c5ef50e). | `a324bb597841` |
| 46 | `08-07-2026/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | 08-07-2026 | B1.3-C | SQL_PATCH | VIGENTE | **SI** | CUERPO_FN | Patcher: reescribe crear_prereserva via pg_get_functiondef + regexp_replace | EJECUTABLE | `crear_prereserva` | — | **CONSOLIDAR** | AUTORIDAD de crear_prereserva (fp 62fefb63). Patcher via pg_get_functiondef + regexp_replace. | `2b1ddd188563` |
| 47 | `08-07-2026/B1_3_C_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-C | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de C. Vigente. | `b6d283705c9a` |
| 48 | `08-07-2026/B1_3_C_SMOKE_TEST.sql` | 08-07-2026 | B1.3-C | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de C. Vigente. | `b2ce1b38c51c` |
| 49 | `08-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | 08-07-2026 | B1.3-D | SQL_PATCH | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `09-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | ARCHIVAR | *** H4 RESUELTO *** Ancla por texto literal e inserta el bloque D ANTES del BEGIN. El vivo NO tiene esta forma (firma_variante_08_07=false). | `fab12ead8fce` |
| 50 | `08-07-2026/B1_3_D_ROLLBACK_TEST.sql` | 08-07-2026 | B1.3-D | SQL_ROLLBACK | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `09-07-2026/B1_3_D_ROLLBACK_TEST.sql` | ARCHIVAR | Rollback simetrico del patch 08-07. Inaplicable al vivo. | `fd3851f4ff27` |
| 51 | `08-07-2026/B1_3_D_SMOKE_TEST.sql` | 08-07-2026 | B1.3-D | SQL_SMOKE | **DUPLICADO** | NO | NINGUNO | — | EJECUTABLE | `confirmar_reserva` | `09-07-2026/B1_3_D_SMOKE_TEST.sql` | ARCHIVAR | Byte-identico al de 09-07 (sha b9a8ddd5...). Duplicado exacto, sin conflicto. | `b9a8ddd5f9d4` |
| 52 | `09-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | 09-07-2026 | B1.3-D | SQL_PATCH | VIGENTE | **SI** | CUERPO_FN | Patcher: reescribe confirmar_reserva. Ancla por regex (variante 09-07) | EJECUTABLE | `confirmar_reserva` | — | **CONSOLIDAR** | *** H4 RESUELTO *** AUTORIDAD de confirmar_reserva (fp e6ac8ddc). Ancla por regex; bloque D DENTRO del BEGIN. firma_variante_09_07=true en el vivo. | `8ab4e29cf7c7` |
| 53 | `09-07-2026/B1_3_D_ROLLBACK_TEST.sql` | 09-07-2026 | B1.3-D | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `confirmar_reserva` | — | CITAR | Rollback correspondiente a la variante desplegada. El unico aplicable. | `81716cf6b3af` |
| 54 | `09-07-2026/B1_3_D_SMOKE_TEST.sql` | 09-07-2026 | B1.3-D | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `confirmar_reserva` | — | CITAR | Smoke de D. Byte-identico al de 08-07. | `b9a8ddd5f9d4` |
| 55 | `09-07-2026/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` | 09-07-2026 | B1.3-E | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + ACL | CREATE de crear_reserva_con_horario_pactado + REVOKE | EJECUTABLE | `crear_reserva_con_horario_pactado` | — | **CONSOLIDAR** | AUTORIDAD de crear_reserva_con_horario_pactado (fp 93c1700f). DB-only. | `5b197ed638da` |
| 56 | `09-07-2026/B1_3_E_ROLLBACK_TEST.sql` | 09-07-2026 | B1.3-E | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Rollback de E. Vigente. | `0e28c6da953f` |
| 57 | `09-07-2026/B1_3_E_SMOKE_TEST.sql` | 09-07-2026 | B1.3-E | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de E. Vigente. | `8e5f6f2e82ee` |
| 58 | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | 09-07-2026 | B1.3-F | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN + ACL | CREATE de crear_override_horario_puntual + DROP de S3 + REVOKE | EJECUTABLE | `crear_override_horario_puntual` | — | **CONSOLIDAR** | AUTORIDAD de crear_override_horario_puntual (fp 33d7ac8a). contiene el DROP de S3 (linea 118) + postcheck de ausencia (455-456). DB-only. | `917b2ec6a0d0` |
| 59 | `09-07-2026/B1_3_F_ROLLBACK_TEST.sql` | 09-07-2026 | B1.3-F | SQL_ROLLBACK | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `crear_paquete_dia_especial` | — | CITAR | Rollback de F: RECREA S3 (linea 46). Es la unica referencia legitima que crea S3 en el repo. | `ade9cc4b8d1a` |
| 60 | `09-07-2026/B1_3_F_SMOKE_TEST.sql` | 09-07-2026 | B1.3-F | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Smoke de F (15/15 verde). | `f4394477f8d3` |
| 61 | `09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md` | 09-07-2026 | B1.3-cierre | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Documento, no SQL. Fuente de los baselines S8, se cita. | `068d90858ccb` |
| 62 | `09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md` | 09-07-2026 | B1.3-cierre | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Documento, no SQL. Se cita. | `7fa040714c9c` |
| 63 | `10-07-2026/CrearReserva.PATCHED.tsx` | 10-07-2026 | integracion-A07 | TSX_FRONTEND | VIGENTE | **SI** | APP_FRONTEND | Componente React desplegado. No es SQL | NO_APLICA | — | — | PRESERVAR_APP | Frontend desplegado. NO entra al canonico SQL (6B). Se preserva y se cita. | `f0ce620b6218` |
| 64 | `10-07-2026/REPORTE_VALIDACION_A07_gap_conflicto.md` | 10-07-2026 | integracion-A07 | MD_REPORTE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Reporte de validacion de la integracion A07. | `d7980db0ced2` |
| 65 | `10-07-2026/harness_router1_crear.mjs` | 10-07-2026 | integracion-A07 | MJS_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Harness local del router 1 (crear). | `803ab49d83f3` |
| 66 | `10-07-2026/harness_router3_confirmar.mjs` | 10-07-2026 | integracion-A07 | MJS_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Harness local del router 3 (confirmar). | `ea3b2ee46e2a` |
| 67 | `10-07-2026/harness_texto_error_reserva.mjs` | 10-07-2026 | integracion-A07 | MJS_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Harness de textos de error. | `22eb202b7c0c` |
| 68 | `10-07-2026/patch_a07_gap_conflicto.py` | 10-07-2026 | integracion-A07 | PY_PATCHER | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Patcher Python del A07. | `73eb5c1da527` |
| 69 | `10-07-2026/patch_crear_reserva_gap_conflicto.py` | 10-07-2026 | integracion-A07 | PY_PATCHER | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Patcher Python del frontend. | `3683f6ad579e` |
| 70 | `10-07-2026/portal-a07-crear-reserva__TEMPLATE.PATCHED.json` | 10-07-2026 | integracion-A07 | JSON_WORKFLOW | HISTORICO | NO | NINGUNO | — | NO_APLICA | `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | — | ARCHIVAR_EVIDENCIA | Desbloqueada por H1. Salida historica del patcher `patch_a07_gap_conflicto.py` (fila 68), congelada el 10-07-2026: sha256 `3188bceb…6def`, 41 775 B. NO es la sede canonica: la sede es `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`, hoy sha256 `3208b068…8fcd` (42 004 B), fijada en `b058de4`. TAMPOCO es el export historico pre-fix, que es `Docs/Implementacion/Carril_C/PROMOCION_OPS/portal-a07-crear-reserva__OPS.json`, sha256 `93641838…a230b` (40 527 B), sin manejo de gaps. Los tres son artefactos distintos. Solo la sede canonica vigente tiene autoridad; la salida historica del patcher y el export historico pre-fix son evidencia. Se archiva como evidencia y se cita. Ver H1 §2.1 y §2.4 y el addendum de procedencia de esta v5. | `3188bceb777b` |
| 71 | `11-07-2026/CC_L3_BLOQUE0_CIERRE.md` | 11-07-2026 | CUENTA-CORRIENTE | MD_CIERRE | **CONTAMINACION** | NO | NINGUNO | — | NO_APLICA | — | — | RECLASIFICAR | Pertenece al carril CUENTA CORRIENTE, no a Horarios. DECISION: documentar y NO mover. | `635eca352e50` |
| 72 | `11-07-2026/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md` | 11-07-2026 | CUENTA-CORRIENTE | MD_EVIDENCIA | **CONTAMINACION** | NO | NINGUNO | — | NO_APLICA | — | — | RECLASIFICAR | Pertenece al carril CUENTA CORRIENTE. DECISION: documentar y NO mover. | `9019f878740a` |
| 73 | `12-07-2026/QAGAP_A_SEED_TEST.sql` | 12-07-2026 | QA-gap | SQL_SEED | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `crear_prereserva, confirmar_reserva` | — | CITAR | Seed del QA formal de gaps. RUNID qagap_20260712_01. ASCII puro (unico .sql que cumple). | `590e1ff07bcf` |
| 74 | `12-07-2026/QAGAP_B_RUNBOOK_PORTAL.md` | 12-07-2026 | QA-gap | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runbook del QA de gaps via portal. | `653cfba37162` |
| 75 | `12-07-2026/QAGAP_C_CLEANUP_TEST.sql` | 12-07-2026 | QA-gap | SQL_TEARDOWN | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Cleanup del QA de gaps. | `24e964a25f37` |
| 76 | `CIERRE_UI_RETIRO_SALDO_FRONTEND.md` | (raiz) | FRONTEND-CC | MD_CIERRE | **CONTAMINACION** | NO | NINGUNO | — | NO_APLICA | — | — | RECLASIFICAR | Pertenece al carril FRONTEND / CUENTA CORRIENTE. DECISION: documentar y NO mover. | `461018c2b225` |
| 77 | `FUNCION_RESGUARDO.md` | (raiz) | resguardo | MD_DUMP_JSON | HISTORICO | NO | NINGUNO | — | NO_APLICA | `crear_prereserva` | — | ARCHIVAR_EVIDENCIA | Dump JSON, no SQL. Evidencia del EOL mixto: se archiva y se cita en el doc de fidelidad. Dump JSON de pg_get_functiondef(crear_prereserva): header con \n (LF), cuerpo con \r\n (CRLF). Resguardo pre-B1.3-C. Ver D1_DECISION_FIDELIDAD_FUNCTIONDEF.md. | `2f2811b9018d` |
| 78 | `HORARIOS_A07UX_CIERRE.md` | (raiz) | A07UX | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre del mini-bloque UX A07 (override_hora_invalido -> payload_invalido). | `924530eadba1` |
| 79 | `HORARIOS_A07UX_POSTCHECK_TEST.sql` | (raiz) | A07UX | SQL_VERIF | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Postcheck del A07UX. | `a88386e64cef` |
| 80 | `HORARIOS_A07UX_RUNSHEET.md` | (raiz) | A07UX | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet del A07UX. | `54d66d28ff69` |
| 81 | `HORARIOS_A07UX_SETUP_TEARDOWN_POSTCHECK_TEST.sql` | (raiz) | A07UX | SQL_VERIF | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Setup+teardown+postcheck combinado del A07UX. | `3ce1084eaa1a` |
| 82 | `HORARIOS_A07UX_SETUP_TEST.sql` | (raiz) | A07UX | SQL_SETUP | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Setup del A07UX. | `95f78fa788b0` |
| 83 | `HORARIOS_A07UX_TEARDOWN_TEST.sql` | (raiz) | A07UX | SQL_TEARDOWN | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Teardown del A07UX. | `aac2abf21536` |
| 84 | `HORARIOS_A07UX_smoke_e2e_TEST.ps1` | (raiz) | A07UX | PS1_SMOKE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Smoke E2E del A07UX (PowerShell). | `08e4d9eb552d` |
| 85 | `HORARIOS_B2_CIERRE.md` | (raiz) | HORARIOS-B2 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | `crear_bloqueo, fecha_hoy_ar` | — | CITAR | Cierre de HORARIOS_B2 (guard helper). Distinto de HORARIOS_FASEB_B2. | `1625275470db` |
| 86 | `HORARIOS_B2_GUARD_HELPER_TEST.sql` | (raiz) | HORARIOS-B2 | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN | CREATE de crear_bloqueo(jsonb) y fecha_hoy_ar() | EJECUTABLE | `crear_bloqueo, fecha_hoy_ar, crear_prereserva` | — | **CONSOLIDAR** | Autoridad de crear_bloqueo(jsonb) y fecha_hoy_ar(). D2: comparacion directa LF vivo==repo, 2/2. Sin gate de fingerprint (EJECUTABLE). | `31e7558fbfc9` |
| 87 | `HORARIOS_B2_RUNSHEET (1).md` | (raiz) | HORARIOS-B2 | MD_RUNSHEET | **COLISION_DIVERGENTE** | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR | md5 1a152ac9..., 13129 B. Divergente del (2). Sufijo de descarga. NO se elige por tamano. | `8497b436780a` |
| 88 | `HORARIOS_B2_RUNSHEET (2).md` | (raiz) | HORARIOS-B2 | MD_RUNSHEET | **COLISION_DIVERGENTE** | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR | md5 e0f1b023..., 15725 B. Divergente del (1). Sufijo de descarga. NO se elige por tamano. | `c87e4a587c48` |
| 89 | `HORARIOS_B3_CIERRE.md` | (raiz) | HORARIOS-B3 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre de HORARIOS_B3 (wrappers UX A07/A08). | `f3b2af9783c4` |
| 90 | `HORARIOS_B3_RUNSHEET.md` | (raiz) | HORARIOS-B3 | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de HORARIOS_B3. | `c4cd2b613107` |
| 91 | `HORARIOS_B3_smoke_e2e_TEST.ps1` | (raiz) | HORARIOS-B3 | PS1_SMOKE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Smoke E2E de HORARIOS_B3 (PowerShell). | `145004e552d1` |
| 92 | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | (raiz) | DISP-RANGO | SQL_MIGRACION | VIGENTE | **SI** | CUERPO_FN | CREATE de obtener_disponibilidad_rango | EJECUTABLE | `obtener_disponibilidad_rango` | — | **CONSOLIDAR** | AUTORIDAD de obtener_disponibilidad_rango (fp 37009a32, ODR INTACTO/pin). Q6: llamada por precios_disponibilidad_noches y vista_disponibilidad. | `84442d908ae7` |
| 93 | `HORARIOS_DISPONIBILIDAD_RANGO_B_VERIFICACION_TEST.sql` | (raiz) | DISP-RANGO | SQL_VERIF | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `obtener_disponibilidad_rango` | — | CITAR | Verificacion del ODR. | `5f29c47a301c` |
| 94 | `HORARIOS_DISPONIBILIDAD_RANGO_CIERRE_TECNICO_PRELIMINAR.md` | (raiz) | DISP-RANGO | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre preliminar de la integracion resolver_horario -> ODR. | `4e9e6db393b8` |
| 95 | `HORARIOS_DISPONIBILIDAD_RANGO_C_SMOKES_TEST.sql` | (raiz) | DISP-RANGO | SQL_SMOKE | VIGENTE | NO | NINGUNO | — | EJECUTABLE | `obtener_disponibilidad_rango` | — | CITAR | Smokes del ODR. | `42a8ccae1049` |
| 96 | `HORARIOS_DISPONIBILIDAD_RANGO_D_RUNSHEET.md` | (raiz) | DISP-RANGO | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet del ODR. | `83373d493575` |
| 97 | `HORARIOS_DISPONIBILIDAD_RANGO_PASO0_LIVE_TEST.sql` | (raiz) | DISP-RANGO | SQL_DIAG | HISTORICO | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR | Paso 0 live del ODR. Diagnostico previo. | `43c75efa3dfe` |
| 98 | `HORARIOS_DISPONIBILIDAD_RANGO_RELEVAMIENTO.md` | (raiz) | DISP-RANGO | MD_DISENO | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Relevamiento y diseno de la integracion ODR. | `5a01a9ad1e34` |
| 99 | `HORARIOS_FASEB_B2_CIERRE.md` | (raiz) | FASEB-B2 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | `resolver_horario` | — | CITAR | Cierre de FASEB_B2 (resolver_horario standalone). | `d9079c35847b` |
| 100 | `HORARIOS_FASEB_B2_RESOLVER_HORARIO_TEST.sql` | (raiz) | FASEB-B2 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | ARCHIVAR | Primera version de resolver_horario. Superada por B1.2-CORE (wrapper + interno). | `7850c4d035cf` |
| 101 | `HORARIOS_FASEB_B2_RUNSHEET.md` | (raiz) | FASEB-B2 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de FASEB_B2. | `c787bd8bbe92` |
| 102 | `HORARIOS_FASEB_B3_CIERRE.md` | (raiz) | FASEB-B3 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | `crear_prereserva` | — | CITAR | Cierre de FASEB_B3 (resolver_horario -> crear_prereserva). | `83e37795f3e6` |
| 103 | `HORARIOS_FASEB_B3_INTEGRACION_CREAR_PRERESERVA_TEST.sql` | (raiz) | FASEB-B3 | SQL_MIGRACION | **SUPERADO** | NO | NINGUNO | — | EJECUTABLE | — | `08-07-2026/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | ARCHIVAR | Integracion original de resolver_horario en crear_prereserva. Superada por el patch C. | `040ad93a48dd` |
| 104 | `HORARIOS_FASEB_B3_RUNSHEET.md` | (raiz) | FASEB-B3 | MD_RUNSHEET | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runsheet de FASEB_B3 (v3). | `b94aa43cda6d` |
| 105 | `HORARIOS_FASEB_B3_SMOKES_TEST.sql` | (raiz) | FASEB-B3 | SQL_SMOKE | HISTORICO | NO | NINGUNO | — | EJECUTABLE | `crear_prereserva` | — | ARCHIVAR | Smokes de FASEB_B3. 5 helpers temporales. | `7ffd5ca04663` |
| 106 | `HORARIOS_FASEB_B3_VERIFICACION_TEST.sql` | (raiz) | FASEB-B3 | SQL_VERIF | HISTORICO | NO | NINGUNO | — | EJECUTABLE | `crear_prereserva` | — | ARCHIVAR | Verificacion de FASEB_B3. | `66c99936dc42` |
| 107 | `HORARIOS_REQUISITO_GUARD_ALTA_OVERRIDES_PENDIENTE.md` | (raiz) | requisito-diferido | MD_REQUISITO | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Requisito diferido: guard de alta de overrides vs reservas. Origen de S0-S3. | `bfc4e0008eac` |
| 108 | `13-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` | 13-07-2026 | D1/D2-evidencia | MD_DISENO | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Decision de fidelidad sobre `pg_get_functiondef` y EOL mixto. Citada por la fila 77 (`FUNCION_RESGUARDO.md`). Sigue siendo la referencia del criterio de fidelidad del carril. | `011d263a1853` |
| 109 | `13-07-2026/D1_DIFF_vs_b7a13a.patch` | 13-07-2026 | D1/D2-evidencia | PATCH_DIFF | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR_EVIDENCIA | Diff del arbol contra `b7a13a`. Evidencia de D1. Contiene DDL solo como texto citado dentro del diff; no es un script ejecutable. | `451f2f176ebe` |
| 110 | `13-07-2026/D1_Q0_CONTEXTO.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `be68ee48384d` |
| 111 | `13-07-2026/D1_Q1_FINGERPRINTS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `848afc55b982` |
| 112 | `13-07-2026/D1_Q2_OVERLOADS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `17a5bec1d765` |
| 113 | `13-07-2026/D1_Q3B_PRIV_EFECTIVOS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `5484b73488a4` |
| 114 | `13-07-2026/D1_Q3_ACL.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `fe274b4a895b` |
| 115 | `13-07-2026/D1_Q4_TRIGGERS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `8abee720152f` |
| 116 | `13-07-2026/D1_Q5_DEPEND.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `8a94518c2462` |
| 117 | `13-07-2026/D1_Q6_CALLERS_CANDIDATOS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `713d1064fc52` |
| 118 | `13-07-2026/D1_Q7_S3_AUSENCIA.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `fdd9f57b4703` |
| 119 | `13-07-2026/D1_Q8B_H4_VARIANTE_D.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `fa82aa7e697f` |
| 120 | `13-07-2026/D1_Q8_CUERPOS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `d4dab9aecec7` |
| 121 | `13-07-2026/D1_Q9_VEREDICTO.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D1. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `203812d1e2a8` |
| 122 | `13-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` | 13-07-2026 | D1/D2-evidencia | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Resultados de D1 en TEST y freeze de 11 objetos con doble fingerprint fp_raw/fp_lf. Es la referencia del congelamiento que habilita el canonico. | `47bbd414ac7c` |
| 123 | `13-07-2026/D1_RUNBOOK.md` | 13-07-2026 | D1/D2-evidencia | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runbook de ejecucion de D1. Describe el orden de las Q y el criterio de veredicto. | `b1620ecd94f9` |
| 124 | `13-07-2026/D1_VALIDACION_HARNESS.txt` | 13-07-2026 | D1/D2-evidencia | TXT_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR_EVIDENCIA | Salida cruda del harness local de validacion de D1. Log de corrida, no artefacto ejecutable. | `1fca2a7d22f6` |
| 125 | `13-07-2026/D2_Q0_CONTEXTO.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `cf1ec93d039e` |
| 126 | `13-07-2026/D2_Q1_INVENTARIO.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `848dfc500307` |
| 127 | `13-07-2026/D2_Q2_PRESENCIA_Y_OVERLOADS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `6d1bc165db92` |
| 128 | `13-07-2026/D2_Q3B_PRIV_EFECTIVOS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `67314252c5d6` |
| 129 | `13-07-2026/D2_Q3_ACL.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `e9c360b95be8` |
| 130 | `13-07-2026/D2_Q4_TRIGGER_OV_GUARD.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `b4d44fe2cf8d` |
| 131 | `13-07-2026/D2_Q5_CUERPOS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `8c4bfd0c3082` |
| 132 | `13-07-2026/D2_Q5_CUERPOS_TEST.json` | 13-07-2026 | D1/D2-evidencia | JSON_EVIDENCIA | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR_EVIDENCIA | Cuerpos de funcion exportados de TEST en D2. EOL MIXTO medido: 78 secuencias CRLF sobre base LF. Es el insumo de la comparacion LF byte a byte 7/7 del cierre de D2. | `8b9a9c92f266` |
| 133 | `13-07-2026/D2_Q6_CALLERS_CANDIDATOS.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `e98d2ef035ad` |
| 134 | `13-07-2026/D2_Q7_VEREDICTO.sql` | 13-07-2026 | D1/D2-evidencia | SQL_DIAG | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | ARCHIVAR_EVIDENCIA | Consulta de diagnostico read-only del bloque D2. Autocontenida: abre `BEGIN TRANSACTION READ ONLY` y trae su propio gate de ambiente sobre `configuracion_general('ambiente')`. Cero DDL y cero DML (verificado). No gatea el fingerprint obsoleto `58d75c1b`. Evidencia del inventario congelado. | `5f2086d39211` |
| 135 | `13-07-2026/D2_RESULTADOS_TEST_Y_CIERRE_B1_3.md` | 13-07-2026 | D1/D2-evidencia | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre de D2 en TEST. Documenta la comparacion cuerpo vivo vs fragmento del repo con `sha256_lf_vivo = sha256_lf_repo` 7/7. Es la prueba que promovio las filas 4, 8, 9 y 86. | `fb1c91848121` |
| 136 | `13-07-2026/D2_RUNBOOK.md` | 13-07-2026 | D1/D2-evidencia | MD_RUNSHEET | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Runbook de D2, version POST-D2. Divergente de su homonimo en 14-07-2026, que es la version PRE-D2. Esta es la vigente. Menciona el fingerprint `58d75c1b` en prosa; no lo gatea. | `354d4fba24b2` |
| 137 | `13-07-2026/D2_VALIDACION_HARNESS_PG17.txt` | 13-07-2026 | D1/D2-evidencia | TXT_HARNESS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | ARCHIVAR_EVIDENCIA | Salida cruda del harness PostgreSQL 17.x de D2. Byte-identica a su copia en 14-07-2026. | `6d61361787e9` |
| 138 | `13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | 13-07-2026 | H3-inventario | MD_INVENTARIO | SUPERADO | NO | NINGUNO | — | NO_APLICA | — | `A07 en paridad y sanitizado/H3_MATRIZ_CASCADE_REPO_157_ARCHIVOS_v5.md` | ARCHIVAR_EVIDENCIA | MATRIZ v4 — post-D2. Fue la autoritativa hasta H3. Confirmada como tal por contenido, coherencia con D2 e historial de mantenimiento. Es la matriz de la que DERIVA esta v5. Se conserva intacta como evidencia historica. Su changelog subdeclara: ver la nota de auditoria de esta v5. | `68babb238033` |
| 139 | `13-07-2026/H7_S3_BARRIDO_REPO_CRUDO_Y_CLASIFICADO.md` | 13-07-2026 | D1/D2-evidencia | MD_INVENTARIO | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Barrido H7 del repo, crudo y clasificado. Origen del recuento de 21 invocaciones reales de S3 que corrigio la fila 16 en v3. | `d26dbeb62a75` |
| 140 | `14-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` | 14-07-2026 | D1/D2-evidencia | MD_DISENO | DUPLICADO | NO | NINGUNO | — | NO_APLICA | — | `13-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` | ARCHIVAR | Copia BYTE-IDENTICA de `13-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` (10 064 B, mismo sha256). Duplicado exacto, sin divergencia. Se archiva. NO se borra ni se mueve: hay documentos historicos que citan esta ruta. | `011d263a1853` |
| 141 | `14-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` | 14-07-2026 | D1/D2-evidencia | MD_CIERRE | DUPLICADO | NO | NINGUNO | — | NO_APLICA | — | `13-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` | ARCHIVAR | Copia BYTE-IDENTICA de `13-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` (10 605 B, mismo sha256). Duplicado exacto, sin divergencia. Se archiva. NO se borra ni se mueve: hay documentos historicos que citan esta ruta. | `47bbd414ac7c` |
| 142 | `14-07-2026/D2_Q4_TRIGGER_OV_GUARD.sql` | 14-07-2026 | D1/D2-evidencia | SQL_DIAG | DUPLICADO | NO | NINGUNO | — | EJECUTABLE | — | `13-07-2026/D2_Q4_TRIGGER_OV_GUARD.sql` | ARCHIVAR | Copia BYTE-IDENTICA de `13-07-2026/D2_Q4_TRIGGER_OV_GUARD.sql` (5 798 B, mismo sha256). Duplicado exacto, sin divergencia. Se archiva. NO se borra ni se mueve: hay documentos historicos que citan esta ruta. | `b4d44fe2cf8d` |
| 143 | `14-07-2026/D2_Q7_VEREDICTO.sql` | 14-07-2026 | D1/D2-evidencia | SQL_DIAG | DUPLICADO | NO | NINGUNO | — | EJECUTABLE | — | `13-07-2026/D2_Q7_VEREDICTO.sql` | ARCHIVAR | Copia BYTE-IDENTICA de `13-07-2026/D2_Q7_VEREDICTO.sql` (14 571 B, mismo sha256). Duplicado exacto, sin divergencia. Se archiva. NO se borra ni se mueve: hay documentos historicos que citan esta ruta. | `5f2086d39211` |
| 144 | `14-07-2026/D2_RUNBOOK.md` | 14-07-2026 | D1/D2-evidencia | MD_RUNSHEET | SUPERADO | NO | NINGUNO | — | NO_APLICA | — | `13-07-2026/D2_RUNBOOK.md` | ARCHIVAR | Version PRE-D2 del runbook (12 864 B). DIVERGE de la copia en 13-07-2026 (12 808 B), que es la POST-D2. Declara a D2 como bloqueante pendiente y a las filas 4, 8, 9 y 86 como `PENDIENTE_D2`: contradice el D2 ya corrido en verde. La carpeta mas nueva contiene la version mas vieja — misma inversion que la matriz. | `404841bbc72c` |
| 145 | `14-07-2026/D2_VALIDACION_HARNESS_PG17.txt` | 14-07-2026 | D1/D2-evidencia | TXT_HARNESS | DUPLICADO | NO | NINGUNO | — | NO_APLICA | — | `13-07-2026/D2_VALIDACION_HARNESS_PG17.txt` | ARCHIVAR | Copia BYTE-IDENTICA de `13-07-2026/D2_VALIDACION_HARNESS_PG17.txt` (32 196 B, mismo sha256). Duplicado exacto, sin divergencia. Se archiva. NO se borra ni se mueve: hay documentos historicos que citan esta ruta. | `6d61361787e9` |
| 146 | `14-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | 14-07-2026 | H3-inventario | MD_INVENTARIO | SUPERADO | NO | NINGUNO | — | NO_APLICA | — | `13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | ARCHIVAR_EVIDENCIA | MATRIZ v3 — corregida (35 910 B). NO es autoritativa. Fosil del baseline: nacio identica a la copia de 13-07-2026 en `03e20a6` y nunca se volvio a tocar, mientras la otra se promovio a v4 en `82f28df` y se corrigio en `8dd1235`. Conserva 4 `PENDIENTE_D2` que el D2 ya invalido. Se conserva intacta como evidencia historica. | `51cc22524b29` |
| 147 | `14-07-2026/KICKOFF_B1_3_CONTINUACION_POST_D2.md` | 14-07-2026 | D1/D2-evidencia | MD_KICKOFF | HISTORICO | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Kickoff de continuacion post-D2. Unico archivo presente solo en 14-07-2026. Su §11 declaraba `2c99db28` como NO LOCALIZADO: FALSO NEGATIVO, no una verdad relativa a su HEAD. El archivo ya estaba versionado en `Workflows/`, fuera del alcance del barrido, que estaba acotado a `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`. El resultado era valido solo respecto de ese barrido limitado y NO como afirmacion global sobre el repositorio. H1 §2.1 lo corrigio ampliando el alcance a `Workflows/`. NO se reescribe el kickoff. | `534f11593f1f` |
| 148 | `A07 en paridad y sanitizado/GUIA_COPIA_A07_TEST_A_OPS.md` | 18-07-2026 | H1-A07 | MD_GUIA | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Guia operativa de copia del A07 de TEST a OPS. Procedimiento manual de Franco; no ejecuta nada por si misma. | `1dc1e73cad65` |
| 149 | `A07 en paridad y sanitizado/H1_CIERRE_POLITICA_DURABLE_A07.md` | 18-07-2026 | H1-A07 | MD_CIERRE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Cierre tecnico y documental definitivo de H1. Fija la politica durable del A07 y declara la sede canonica. Medido contra HEAD `a2a5893`. Es la fuente que desbloquea la fila 70. | `152e4bbd301e` |
| 150 | `A07 en paridad y sanitizado/KICKOFF_H3_CIERRE_INVENTARIO.md` | 18-07-2026 | H3-cierre-inventario | MD_KICKOFF | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Kickoff de H3, medido contra HEAD `a2a5893`. Su §2.3 declara 147 archivos y su §2.4 declara que `2c99db28` esta en la sede canonica: ambas verdaderas en `a2a5893` y superadas por `b058de4`. NO se reescribe; se precisa en esta v5. | `5b9442a4b2e9` |
| 151 | `A07 en paridad y sanitizado/MANIFIESTO_AMBIENTES_A07.md` | 18-07-2026 | H1-A07 | MD_MANIFIESTO | VIGENTE | NO | NINGUNO | — | NO_APLICA | `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | — | CITAR | Manifiesto de 12 paths ambientales del A07 con placeholders determinsticos. Es el unico medio declarado por H1 para derivar OPS desde el template canonico. | `6dc2ffa11919` |
| 152 | `A07 en paridad y sanitizado/PLAN_PRUEBAS_A07.md` | 18-07-2026 | H1-A07 | MD_PLAN_PRUEBAS | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Plan de pruebas del A07. Referencia de validacion; no ejecuta nada contra TEST ni OPS. | `e687eda48b3c` |
| 153 | `A07 en paridad y sanitizado/REPORTE_COMPARACION_A07_TEST_OPS.md` | 18-07-2026 | H1-A07 | MD_REPORTE | VIGENTE | NO | NINGUNO | — | NO_APLICA | — | — | CITAR | Comparacion TEST vs OPS del A07. Cita `19d2439a…` como OPS PRE-fix: es insumo de comparacion, NO el OPS post-fix. H1 §1 advierte explicitamente contra confundir los tres hashes. | `60338c6a8107` |
| 154 | `A07 en paridad y sanitizado/portal-a07-crear-reserva__OPS__CANDIDATO_SANITIZADO.json` | 18-07-2026 | H1-A07 | JSON_WORKFLOW | VIGENTE | NO | NINGUNO | — | NO_APLICA | `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | — | ARCHIVAR_EVIDENCIA | Candidato OPS sanitizado, sha256 `d0342c9c…09c7` (41 981 B). H1 §1 lo declara "una referencia construida del estado esperado": NO es un export real de OPS y NO es la sede canonica. Difiere del template canonico por placeholders y ausencia de metadata de instancia. | `d0342c9cdd05` |
| 155 | `A07 en paridad y sanitizado/router1_crear.jsCode.js` | 18-07-2026 | H1-A07 | JS_NODO_N8N | VIGENTE | NO | APP_N8N | `jsCode` del nodo `router1_crear` | NO_APLICA | `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | — | PRESERVAR_APP | Extracto del `jsCode` aprobado del nodo `router1_crear`, 2 134 B. MEDIDO EN ESTA v5: byte-identico al `jsCode` del mismo nodo dentro de la sede canonica (2 128 caracteres, ambos). Paridad probada, pero la autoridad la retiene la sede, no el extracto. | `af603528a6b1` |
| 156 | `A07 en paridad y sanitizado/router3_confirmar.jsCode.js` | 18-07-2026 | H1-A07 | JS_NODO_N8N | VIGENTE | NO | APP_N8N | `jsCode` del nodo `router3_confirmar` | NO_APLICA | `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | — | PRESERVAR_APP | Extracto del `jsCode` aprobado del nodo `router3_confirmar`, 1 837 B. MEDIDO EN ESTA v5: byte-identico al `jsCode` del mismo nodo dentro de la sede canonica (1 831 caracteres, ambos). Paridad probada, pero la autoridad la retiene la sede, no el extracto. | `b5daccc42b98` |
| 157 | `A07 en paridad y sanitizado/verificador_a07.py` | 18-07-2026 | H1-A07 | PY_VERIFICADOR | VIGENTE | NO | NINGUNO | — | EJECUTABLE | — | — | CITAR | Verificador read-only del A07 sobre la terna candidato/template/vivo, con `--self-test`. H1 §2.4 lo declara el medio de validacion de la politica durable. No muta nada. | `d59826009573` |

---

## 12. Hallazgos

### 1. H4 — cerrado
Fila 49 **SUPERADA**; fila 52 **AUTORIDAD**, probado contra el vivo (`firma_variante_09_07 = true`).

La consecuencia está en los **rollbacks**: el de 08-07 (fila 50) ancla por texto literal, y ese anchor
**no existe en el vivo**. **El único aplicable es el de 09-07** (fila 53).

### 2. Colisión divergente — `HORARIOS_B2_RUNSHEET (1)/(2)`
Filas 87 y 88. Ver §8. Ambos → `ARCHIVAR`, con MD5 y SHA-256 completos declarados.

### 3. `B1_3_A` es la autoridad del DDL
Dropea y recrea `vigencias_horario_base` / `_detalle` (líneas 107-132). La fila 26
(`B1_1_VIGENCIAS_DDL`) queda **SUPERADA también en el DDL**.

### 4. Contaminación — 3 archivos
Filas 71, 72 (Cuenta Corriente) y 76 (Frontend/CC). **Documentar y NO mover.** Ver §9.

### 5. Sobre causalidad
La matriz afirma **qué está y qué no está** en el vivo. **No afirma qué comando histórico lo produjo.**
Que `B1_3_A` contenga el `DROP` del overload de 7 args y que hoy ese overload no exista son dos hechos
**consistentes**; el segundo no prueba criptográficamente al primero.

### 6. La fecha de carpeta no es metadata — es una etiqueta
Dos archivos divergentes del mismo par de carpetas quedaron invertidos en la misma dirección. La
decisión se toma por contenido, coherencia con la evidencia e historial de `git`. Ver §1.

### 7. Un hash "no localizado" puede estar fuera del alcance del barrido
`2c99db28` nunca estuvo perdido: vivía en `Workflows/`, fuera de
`Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`. Y para cuando H3 arrancó, ya había sido sustituido. Un
barrido acotado produce ausencias que no son inexistencias. Ver §6.

### 8. El commit que prepara un bloque puede invalidar los números de su propio kickoff
`b058de4` cerró H1, emitió el kickoff de H3 y **en el mismo commit** agregó 10 archivos y sustituyó la
sede canónica del A07. El kickoff quedó midiendo `a2a5893`: 147 archivos y `2c99db28` en la sede. Al
arrancar H3 el árbol ya decía 157 y `3208b068`. **Revalidar los conteos contra el HEAD real es
obligatorio, no ceremonial.**

---

## 13. Alcance negativo de esta v5

Esta matriz **no** modifica: el canónico `6B_SCHEMA_SQL.md` · el bootstrap
`bootstrap_entorno_nuevo_v1.12.0/` · los satélites de `Docs/Operacional/`, `CLAUDE.md`, `README.md` ·
la sede canónica del A07 · la v3 ni la v4 · ningún kickoff histórico · TEST · OPS · Supabase · n8n.

**No acuña `D-HR-*` ni `L-HR-*`.** Eso corresponde a la consolidación canónica v1.13.0, en bloque
separado.
