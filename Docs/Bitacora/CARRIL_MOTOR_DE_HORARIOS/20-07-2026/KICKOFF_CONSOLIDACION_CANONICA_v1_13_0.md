# KICKOFF — CONSOLIDACIÓN CANÓNICA v1.13.0

**Carril:** Motor de Horarios · **Bloque:** `consolidacion-canonica-v1.13.0`
**Predecesor:** `H3` — cierre de inventario del carril, **auditado, commiteado y pusheado**
**HEAD canónico inicial:** `164794a54ea28693520db27fdb7bb6b137c6bb07`
**Documento autocontenido:** una conversación nueva debe poder arrancar solo con esto + el repo.

> **Un bloque por conversación.** Este kickoff cubre exclusivamente la consolidación del Motor de
> Horarios en `6B_SCHEMA_SQL.md`. No mezclar con B3.1, Carril D, frente de marketing ni Mercado Pago.

---

## 0. Apertura — clone fresco y gate

**Antes de tocar nada, cloná fresco. El repo es la autoridad, no la memoria, ni el working tree de H3,
ni versiones intermedias de ningún artefacto.**

```
git clone https://github.com/francogg89-ai/vita-delta-reservas.git
cd vita-delta-reservas
git rev-parse HEAD                 # 164794a54ea28693520db27fdb7bb6b137c6bb07
git rev-parse --abbrev-ref HEAD    # main
git status --porcelain             # vacío
```

**Gates de cadena — los tres deben dar exit 0:**

```
git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD   # D2
git merge-base --is-ancestor b058de456afd186f91d6ff7e5666978ef4b4df64 HEAD   # H1 + kickoff H3
git merge-base --is-ancestor 164794a54ea28693520db27fdb7bb6b137c6bb07 HEAD   # cierre H3
```

**Si HEAD ya no es `164794a`, revalidá todo antes de diseñar.** Ver §9.3.

### 0.1 Cómo se mide el hash de un archivo versionado

Con `core.autocrlf=true` (Windows) el checkout convierte LF → CRLF: medir el archivo en disco da un
hash distinto sin que nada esté alterado. **Todo hash de archivo versionado se mide sobre el blob de
Git.**

**No se usa una tubería de shell para esto.** `git cat-file blob … | sha256sum` no es portable: en
PowerShell la tubería es un flujo de texto que reescribe los bytes, y `sha256sum` no existe por defecto
en Windows. El helper del bloque es Python, y es el mismo que usa el verificador:

```python
import hashlib, subprocess

def sha_blob(ruta, rev="HEAD"):
    """SHA-256 de los bytes canónicos del objeto Git. Idéntico en Windows, PowerShell y Linux."""
    r = subprocess.run(["git", "cat-file", "blob", "%s:%s" % (rev, ruta)],
                       capture_output=True)          # sin text=True: stdout son BYTES
    if r.returncode != 0:                            # return code verificado siempre
        raise SystemExit("git cat-file rc=%d: %s"
                         % (r.returncode, r.stderr.decode("utf-8", "replace")))
    return hashlib.sha256(r.stdout).hexdigest()      # sin decodificar ni recodificar
```

Las cuatro condiciones son obligatorias: **bytes crudos, sin `text=True`, return code verificado, y
cero conversión de encoding entre `git` y el hash.** El verificador final del bloque deberá exponer esta función y
todos los hashes de este documento se reproducen con ella.

---

## 1. Alcance — exactamente esto y nada más

Consolidar el **Motor de Horarios** dentro del canónico `Docs/Implementacion/6B_SCHEMA_SQL.md`,
llevándolo de **v1.12.0 a v1.13.0**, generar el bootstrap kit nuevo, y propagar a los satélites en el
cierre formal.

1. Diseñar y entregar el **extractor read-only del vivo de TEST**, que Franco ejecuta. §5.
2. Auditar su salida y comprobar ausencia de drift. §5.4.
3. Redactar el canónico del carril **desde el vivo normalizado a LF**. §3.2.
4. Pinear los fingerprints dobles y los `triggerdef`. §3.3.
5. Escribir el changelog `v1.12.0 → v1.13.0`, el encabezado de estado y el índice.
6. Corregir las **5 menciones stale** al bootstrap v1.9.0 dentro del canónico. §2.7.
7. Generar `Docs/Implementacion/bootstrap_entorno_nuevo_v1.13.0/`. §3.4.
8. Probar identidad canónico ↔ bootstrap y bootstrap ejecutado desde cero. §6.
9. Acuñar `D-HR-*` y `L-HR-*` y propagar a satélites — **sólo en el cierre formal**.
10. Emitir el cierre del bloque con verificador read-only propio.
11. Emitir al final el **kickoff del bloque posterior de promoción TEST→OPS**. §3.1.

**OPS no se toca en este bloque.** Fuera de alcance: todo lo de §11.

---

## 2. Estado medido en `164794a`

Medido sobre clone fresco de `origin/main` el 2026-07-20, con `sha_blob()` de §0.1.

### 2.1 El canónico no contiene **nada** del Motor de Horarios

`Docs/Implementacion/6B_SCHEMA_SQL.md` — **439 514 B**, sha256 `b730eafe0f53b7b9…`, declara
`Canónico vigente: 6B_SCHEMA_SQL.md v1.12.0`.

Barrido de objetos del carril sobre el canónico completo: `resolver_horario`, `_resolver_horario`,
`vigencias_horario_base`, `crear_vigencia_horario`, `trg_guard_overrides`, `crear_override_horario`,
`validar_gap_bordes_congelados` → **0 ocurrencias en las siete**.

Lo mismo en el bootstrap: los **7 `.sql`** del kit v1.12.0 dan 0 ocurrencias de objetos de horarios.

La consolidación es **adición pura**. La PARTE A llega hasta la sección 25 (Carril C); el SQL ejecutable
está partido en PARTE B (base), PARTE C (Carril B) y PARTE D (Carril C).

### 2.2 Los 12 artefactos de la cadena de autoridad

De `H3_MATRIZ_CASCADE_REPO_157_ARCHIVOS_v5.md`, filas con `accion_v1_13 = CONSOLIDAR`. Los 12 están
presentes en `164794a`. Rutas relativas a `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`.

| Fila | Artefacto | Bytes | sha256 (prefijo 12) | autoridad | `estado_script` |
|---|---|---|---|---|---|
| 4 | `04-07-2026/HORARIOS_GUARD_S0_VALIDADORES_TEST.sql` | 9 076 | `4708bb164965` | SI | **NO_EJECUTABLE** |
| 8 | `04-07-2026/HORARIOS_GUARD_S1_TRIGGER_TEST.sql` | 9 120 | `7bcef3c4c1fc` | SI | **NO_EJECUTABLE** |
| 9 | `04-07-2026/HORARIOS_GUARD_S2_FUNCION_TEST.sql` | 10 239 | `632adaac7363` | SI | **NO_EJECUTABLE** |
| 30 | `06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` | 19 286 | `f88f7d2e87b3` | **PARCIAL** | **NO_EJECUTABLE** |
| 40 | `08-07-2026/B1_3_A_MIGRACION_SEMANAL_TEST.sql` | 35 615 | `f5cf08b3a51c` | SI | EJECUTABLE |
| 45 | `08-07-2026/B1_3_B_VALIDADOR_GAP_TEST.sql` | 10 483 | `a324bb597841` | SI | EJECUTABLE |
| 46 | `08-07-2026/B1_3_C_PATCH_CREAR_PRERESERVA_TEST.sql` | 8 293 | `2b1ddd188563` | SI | EJECUTABLE |
| 52 | `09-07-2026/B1_3_D_PATCH_CONFIRMAR_RESERVA_TEST.sql` | 8 860 | `8ab4e29cf7c7` | SI | EJECUTABLE |
| 55 | `09-07-2026/B1_3_E_CREAR_RESERVA_PACTADA_TEST.sql` | 14 924 | `5b197ed638da` | SI | EJECUTABLE |
| 58 | `09-07-2026/B1_3_F_CREAR_OVERRIDE_PUNTUAL_TEST.sql` | 28 124 | `917b2ec6a0d0` | SI | EJECUTABLE |
| 86 | `HORARIOS_B2_GUARD_HELPER_TEST.sql` | 25 539 | `31e7558fbfc9` | SI | EJECUTABLE |
| 92 | `HORARIOS_DISPONIBILIDAD_RANGO_A_INTEGRACION_TEST.sql` | 7 070 | `84442d908ae7` | SI | EJECUTABLE |

Los valores de la columna sha256 son **prefijos de 12 caracteres**, no huellas completas: identifican,
no verifican integridad.

**Mapa artefacto → objetos** (de la v5 §10):

| Artefacto | Objetos que aporta |
|---|---|
| S0 (fila 4) | `validar_estado_horario_final`, `validar_no_eventos_comprometidos`, `validar_estado_override` |
| S1 (fila 8) | `trg_guard_overrides()` + trigger `trg_ov_guard` |
| S2 (fila 9) | `crear_override_horario` |
| B1_2 (fila 30) | **sólo** el wrapper `resolver_horario` |
| B1_3_A (fila 40) | `_resolver_horario`, `vigencias_conflictos_comprometidos`, `crear_vigencia_horario`, `trg_guard_vigencias`, 2 triggers, **DDL de `vigencias_horario_base` / `_detalle`**, ACL |
| B1_3_B (fila 45) | `validar_gap_bordes_congelados` + ACL |
| B1_3_C (fila 46) | `crear_prereserva` |
| B1_3_D (fila 52) | `confirmar_reserva` |
| B1_3_E (fila 55) | `crear_reserva_con_horario_pactado` + ACL |
| B1_3_F (fila 58) | `crear_override_horario_puntual` + ACL |
| B2 helper (fila 86) | `crear_bloqueo`, `fecha_hoy_ar` |
| Disponibilidad (fila 92) | `obtener_disponibilidad_rango` |

### 2.3 Los 12 son de TEST

Los 12 terminan en `_TEST.sql`. D2 corrió sólo contra TEST: `ambiente = test`, PostgreSQL 17.6.
**No existe artefacto de promoción TEST→OPS del SQL del carril.** Es lo esperado y ya está resuelto por
la premisa de §3.1: no es una pregunta abierta.

### 2.4 4 de los 12 abortan hoy — y no importa para el canónico

Filas **4, 8, 9 y 30** son `NO_EJECUTABLE_GATE_OBSOLETO`: su gate espera el resolver viejo `58d75c1b`
y aborta contra el estado actual.

**Autoridad ≠ ejecutabilidad.** Los cuatro **son autoridad** de sus objetos: D2 probó
`sha256_lf_vivo = sha256_lf_repo` 7/7 comparando el cuerpo vivo contra el fragmento del repo. Y como el
canónico se redacta **desde el vivo** (§3.2), que el script no corra hoy es irrelevante: el script no
es la fuente, es la cadena de custodia que prueba que el vivo es el correcto.

### 2.5 La fila 30 es `PARCIAL` — no la trates como completa

`06-07-2026/B1_2_CORE_MIGRACION_TEST.sql` es autoridad **únicamente del wrapper** `resolver_horario`.
Su `_resolver_horario` y su helper **fueron superados por B1_3_A** (fila 40).

Relacionado: **B1_3_A es también la autoridad del DDL** — dropea y recrea `vigencias_horario_base` /
`_detalle` en sus líneas 107-132. La fila 26 (`B1_1_VIGENCIAS_DDL`) está `SUPERADA` también en el DDL.

### 2.6 Los satélites no mencionan el carril

| Satélite | Bytes | `Motor de Horarios` | `resolver_horario` |
|---|---|---|---|
| `Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md` | 108 650 | **0** | **0** |
| `Docs/Operacional/Pendiente_pre_produccion.md` | 85 718 | **0** | **0** |
| `Docs/Operacional/DECISIONES_NO_REABRIR.md` | 165 756 | — | — |
| `Docs/Operacional/Lecciones_Aprendidas.md` | 114 946 | — | — |
| `CLAUDE.md` | 76 075 | — | — |
| `README.md` | 52 200 | — | — |

`D-HR-*` y `L-HR-*` son namespaces **vírgenes**: 0 identificadores de cada uno. La numeración arranca
en `D-HR-01` y `L-HR-01`. Prefijos ya usados, para no pisarlos: `D-C`, `D-9H`, `D-CC`, `D-FE`, `D-9F`,
`D-9B`, `D-8B`, `D-9G`, `D-HARD`, `D-9C`, `D-PROMO`, `D-7B`, `D-9D`, `D-9E`, `D-8D`, `D-NEG`, `D-8`,
`D-RDEV`, `D-7E`, `D-8C`.

### 2.7 🟡 El canónico tiene 5 menciones stale al bootstrap v1.9.0

Conteo dentro de `6B_SCHEMA_SQL.md`: **5** ocurrencias de `bootstrap_entorno_nuevo_v1.9.0/` contra
**1** de `v1.12.0`. Líneas 36, 49, 59, 106 y 8258. La línea 59 lo declara como deuda consciente
`P-CC-4` y la 8258 pide regenerar el kit.

El kit **v1.12.0 ya existe** en el árbol; lo que quedó rezagado es el **texto** del canónico.
**Corregirlo forma parte de v1.13.0**, y debe quedar coherente con el kit nuevo.

### 2.8 🟢 La sede canónica del A07 ya está sustituida — no volver a sustituirla

H1 §5 proyectaba la sustitución de `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`
**para este bloque**. Se ejecutó anticipadamente en `b058de4`.

```
sede canónica hoy   sha256  3208b0687e4ef878eb74378173ded2bc5c634cac55ca08f336096de04eaa8fcd
                    blob    49bf96a4b12e8aea8ea2c2115670006db8a10126
contenido anterior  sha256  2c99db28866a4e9e7e0ec586e5a18fd443a4b91b64b704fcaa833cbe31a981c3
                    blob    bd731c6817370148023118c8a5de290a4db05858   (ya no está en el árbol)
```

Sustituirla de nuevo sería una regresión. La lógica del A07 sigue congelada.

### 2.9 🟡 El verificador de H3 está agotado — no lo reutilices

`VERIFICADOR_H3_v5.py` era un gate **pre-commit**. Corrido hoy sobre `164794a` da `OK: 115 · FALLAS: 3`
y exit 1, con tres fallas esperadas y correctas: HEAD avanzó, y las altas ya no están en `??`. No
indican alteración de nada. Este bloque necesita **su propio verificador** — que sí puede reutilizar
`sha_blob()` de §0.1.

---

## 3. Premisas cerradas — **no se reabren**

Estas decisiones ya están tomadas y escritas. **La conversación nueva no debe pedirle a Franco que
elija entre opciones sobre ninguna de ellas.**

### 3.1 Secuencia del bloque — CERRADA

> **v1.13.0 consolida el estado autoritativo probado y congelado en TEST. OPS permanece intacto y
> explícitamente pendiente de promoción hasta el bloque posterior.**

Concretamente:

1. Consolidar el estado autoritativo probado en TEST.
2. Bumpear el canónico a **v1.13.0**.
3. Generar un bootstrap nuevo **v1.13.0**.
4. **Mantener OPS intacto.**
5. Dejar la promoción TEST→OPS para un **bloque posterior e independiente**.
6. Emitir al final el **kickoff de esa promoción**.

**Dónde está escrito:** `09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md` (*"al cerrar, bump
`6B_SCHEMA_SQL.md` v1.12.0 → v1.13.0 + nuevo bootstrap; una sola vez, coordinado"* y
*"`Docs/Implementacion/bootstrap_entorno_nuevo_v1.13.0/` — nuevo bootstrap"*) y
`09-07-2026/CIERRE_B1_3_Y_KICKOFF_INTEGRACION_TEST.md`.

Que las versiones anteriores del canónico se hayan consolidado **después** de su promoción a OPS es un
precedente real, documentado en el encabezado del canónico. **No reabre esta decisión.**

### 3.2 El canónico se redacta **desde el vivo**, no desde los artefactos — CERRADA

La fuente del canónico es `pg_get_functiondef()` del objeto vivo de TEST, **normalizado a LF**. Los 12
artefactos de §2.2 son la **cadena de custodia** que prueba que el vivo es el correcto — no son el
texto que se copia.

**Dónde está escrito:** `13-07-2026/D1_Q8_CUERPOS.sql` y `13-07-2026/D2_Q5_CUERPOS.sql`, ambos en su
encabezado: *"consolidar el canonico v1.13.0 desde el VIVO y no desde los artefactos"*.

**Consecuencia operativa, y es la que ordena el bloque:** la fuente autoritativa **no está en el repo**. Hay
que ir a buscarlo a TEST, y en Supabase ejecuta Franco. De ahí la fase obligatoria de §5.

### 3.3 Doble fingerprint — CERRADA

Autoridad: `13-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md`, **Opción C**, cerrada por Franco. Las
opciones A (preservar CRLF en el canónico) y B (normalizar el vivo y re-pinear) quedaron descartadas y
no se reabren.

```sql
fp_raw = md5(pg_get_functiondef(...))                        -- verifica el VIVO tal como está
fp_lf  = md5(replace(pg_get_functiondef(...), chr(13), ''))  -- verifica contra el CANÓNICO LF-only
```

- **Canónico y bootstrap: LF-only.**
- **Los fingerprints se calculan dentro de la sesión de PostgreSQL**, nunca exportando a archivo: una
  redirección tipo `psql -o` agrega un `\n` final y corrompe el hash.
- **Ninguna escritura en TEST ni en OPS** para verificar: el doble hash se calcula por lectura.

**Qué queda pineado en v1.13.0** (D1 §7):

1. Los **11 objetos** con `fp_raw` + `fp_lf`, congelados en D1 §4.
2. Los **triggers** con `md5(pg_get_triggerdef(oid, true))`: `trg_vig_guard`
   (`e8cf4990e3fc36d92ee97198e16085bd`) y `trg_vig_guard_detalle`
   (`99a7a7b61631db62b63cf4bebf9d0e54`) ya congelados en D1, más **`trg_ov_guard`** que aporta D2.
   `pg_get_triggerdef` es de una sola línea y no lleva EOL embebidos: no necesita doble hash.
3. Los objetos de **D2** — 7 funciones + `trg_ov_guard` — con el mismo esquema de doble hash. D2 ya
   emite `md5_raw`, `md5_lf` y `cantidad_cr` por objeto.
4. La declaración de versión: **fingerprints válidos para PostgreSQL 17.x**.

**Detección de normalización accidental** — el doble fingerprint la vuelve *detectable*, no la impide.
`fp_raw == fp_lf` **no alcanza** como criterio. Una normalización exclusivamente física se identifica
con los cuatro predicados juntos contra los baselines congelados:

```
cr_baseline    > 0                    -- el objeto TENÍA CR
fp_raw_actual != fp_raw_baseline      -- el texto crudo cambió
fp_lf_actual  == fp_lf_baseline       -- pero el normalizado NO
cr_actual      = 0                    -- y ahora no tiene CR
```

Si `fp_lf` también cambió, **hubo cambio textual**, no normalización: ahí hay que ir al diff.

**Límites declarados en D1 §6, que el bloque debe respetar:** la validación corrió en PG **17.10** y
TEST es **17.6** (misma major, mecanismo idéntico, no verificado en 17.6 exactamente);
`md5(pg_get_functiondef())` **no es portable entre major versions** porque el header lo reconstruye el
servidor. **⇒ El bootstrap kit v1.13.0 debe declarar `PostgreSQL 17.x` como la versión contra la que
sus fingerprints son válidos.**

### 3.4 Bootstrap — CERRADA

**Se genera `Docs/Implementacion/bootstrap_entorno_nuevo_v1.13.0/`.**
**No se modifica ni se extiende `bootstrap_entorno_nuevo_v1.12.0/`**, que queda como **kit histórico
ejecutable de esa versión**.

Conjunto exacto del kit vigente v1.12.0, medido con `git ls-tree` — **9 archivos: 7 `.sql` + 2 `.md`**:

| Archivo | Tipo | Bytes | blob (prefijo 12) |
|---|---|---|---|
| `00_PRECHECK_ENTORNO_NUEVO.sql` | precheck | 11 135 | `57db721ac993` |
| `01_BOOTSTRAP_PARTE_B_BASE.sql` | bootstrap | 107 521 | `6c9a4faa7c3d` |
| `01_VERIFY_PARTE_B_BASE.sql` | verify | 5 853 | `ce4d2f09c223` |
| `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql` | bootstrap | 100 708 | `fe02811b77db` |
| `02_VERIFY_PARTE_C_CARRIL_B.sql` | verify | 11 576 | `02d296a1b606` |
| `03_BOOTSTRAP_PARTE_D_PORTAL.sql` | bootstrap | 48 972 | `b4f0032971fe` |
| `03_VERIFY_FINAL_ENTORNO.sql` | verify | 12 675 | `4aef6ce66cd0` |
| `Prompt_para_crear_entorno.md` | doc | 2 835 | `c14c42280970` |
| `README_EJECUCION_BOOTSTRAP.md` | doc | 3 083 | `d9ba15ae035c` |

Es la **única declaración del conjunto** en este kickoff. Cualquier conteo distinto que aparezca en
otro documento está stale y se corrige contra esta tabla.

### 3.5 Contaminación de otros carriles — CERRADA por H3, fuera de alcance

Filas **71**, **72** y **76** de la v5 (`11-07-2026/CC_L3_BLOQUE0_CIERRE.md`,
`11-07-2026/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md`, `CIERRE_UI_RETIRO_SALDO_FRONTEND.md`) quedaron
resueltas por H3: **`CONTAMINACION` / `RECLASIFICAR`, documentar, no mover.**

**No se tocan desde el carril Horarios.** Cualquier reclasificación formal pertenece al carril dueño
(Cuenta Corriente / Frontend). Quedan **expresamente fuera del alcance** de este bloque.

---

## 4. Puntos de diseño a resolver **en el diseño**

No son decisiones bloqueantes previas: se resuelven dentro del diseño, que igual requiere aprobación
explícita de Franco antes de generar artefactos.

1. **Ubicación en el canónico.** Propuesta a confirmar: **sección 26** en la PARTE A para el diseño del
   Motor de Horarios, y **PARTE E** para su SQL ejecutable, siguiendo el patrón de PARTE C (Carril B) y
   PARTE D (Carril C).
2. **Huella estructural.** El Carril B tiene `TOTAL_CARRIL = f5187092083451ceb5b182334bdb4a17` y el
   Carril C `TOTAL_PORTAL = dee953e867aed06a9c65836bac14e8f7`. Definir si el Motor de Horarios recibe
   una huella equivalente y cómo se calcula, dado que se mide contra TEST.

---

## 5. Fase obligatoria — adquisición del vivo de TEST

**El canónico se redacta desde el vivo (§3.2), y en Supabase ejecuta Franco.** Por eso el bloque **no
puede** saltar del diseño aprobado a generar el canónico: hay una fase intermedia con su propio hard
stop.

### 5.1 Qué evidencia congelada del repo sirve, y qué hay que volver a extraer

**Sirve como respaldo, ya congelado en el repo — no se re-extrae:**

| Evidencia | Para qué sirve |
|---|---|
| D1 §4 — 11 `fp_raw` + `fp_lf` | **Baseline de drift.** Contra esto se comparan los fingerprints de hoy |
| D1 §4 — `fp_triggerdef` de `trg_vig_guard` y `trg_vig_guard_detalle` | Baseline de los triggers |
| D2 — `md5_raw`, `md5_lf`, `cantidad_cr` de 7 funciones + `trg_ov_guard` | Baseline de los objetos de D2 |
| Los 12 artefactos de §2.2 | Cadena de custodia: prueban que el vivo es el aprobado |
| `H3_MATRIZ_…_v5.md` | Inventario y clasificación del carril |

**Debe volver a extraerse del vivo — no alcanza con el repo:**

| Qué | Por qué |
|---|---|
| El **texto fuente** de cada cuerpo: `pg_get_functiondef()` crudo y normalizado a LF | Es lo que se copia al canónico. §3.2 |
| Firmas exactas, ACL, forma de tablas y triggers vigentes | Deben reflejar el vivo de hoy, no el de hace una semana |
| `fp_raw`, `fp_lf`, `cantidad_cr` actuales | Sólo comparándolos con el baseline se demuestra ausencia de drift |

**`13-07-2026/D2_Q5_CUERPOS_TEST.json` es un caso especial.** Es el export de cuerpos de D2 y es
evidencia valiosa, pero **no es la fuente**: está fechado el 13-07, y `git ls-files --eol` lo reporta
como **`i/crlf`** — CRLF en el índice mismo. Sirve como **contraste cruzado** de la extracción
nueva, no como texto a copiar.

### 5.2 Qué debe cubrir el extractor

Un único artefacto SQL read-only, autocontenido, que Franco ejecuta en TEST. Cobertura obligatoria:

- Los **11 objetos de D1** y los **7 objetos de D2** — 18 funciones.
- Los **3 `triggerdef`**: `trg_vig_guard`, `trg_vig_guard_detalle`, `trg_ov_guard`.
- Por objeto: **firma exacta** (`regprocedure` / `oid`), **`fp_raw`**, **`fp_lf`**, **`cantidad_cr`**,
  **bytes**, y el **cuerpo completo** crudo y normalizado.
- Gate de ambiente: `configuracion_general('ambiente') = 'test'`, y abortar si no.
- Aserción explícita de **`transaction_read_only = on`** dentro de la propia transacción.

### 5.3 Cómo debe salir — machine-readable, sin perder bytes

**No se copian cuerpos a mano, y no se usa `psql -o` ni tuberías de texto.** Una redirección a archivo
agrega un `\n` final y corrompe el hash; una tubería de texto reescribe EOL y encoding.

La salida debe ser **una estructura machine-readable emitida como valor** — un `jsonb` leído desde el
cliente — donde los cuerpos viajen codificados. Es aceptable **base64 del cuerpo crudo y del
normalizado**, calculado dentro de PostgreSQL, **siempre que el diseño pruebe reversibilidad e
integridad**:

- `sha256` de los bytes crudos, calculado **dentro de la base**, viaja junto al base64;
- decodificar el base64 del lado del auditor y volver a hashear **debe reproducir ese sha256**;
- la longitud en bytes declarada debe coincidir con la del decodificado;
- `md5` del decodificado debe reproducir `fp_raw`, y el del normalizado, `fp_lf`.

Si alguna de esas cuatro no cierra, la extracción se descarta y se rehace. **No se "arregla" a mano.**

### 5.4 Compuertas antes de generar el canónico

**El canónico no se empieza a escribir hasta que las cinco estén en verde:**

1. **Firmas esperadas completas** — 18/18 funciones y 3/3 `triggerdef`, sin faltantes.
2. **Fingerprints actuales == baselines** de D1 y D2, o drift explicado y aprobado por Franco según la
   tabla de cuatro predicados de §3.3.
3. **Cero overloads inesperados** — conteo por `proname`, contrastado con las firmas esperadas.
4. **`triggerdef` coincidentes** con los baselines.
5. **Salida completa auditada**, con la prueba de reversibilidad de §5.3 en verde.

### 5.5 Hard stop

Entregado el extractor, **el bloque frena**. Franco lo ejecuta en TEST y devuelve la salida. Recién con
las cinco compuertas de §5.4 en verde se generan canónico, bootstrap y verificador final.

---

## 6. Especificación de validación — qué debe incluir el diseño

`pglast` + harness PostgreSQL 17.x **no alcanza**. El diseño que se presente antes de generar
artefactos tiene que incluir, como mínimo:

### 6.1 Manifest e inventario

- **Manifest exacto** de objetos, firmas y **orden de dependencias** para creación.
- **Inventario esperado**: tablas, funciones, triggers y **ACL**, con conteos y nombres.

### 6.2 Extracción y anclaje de los bloques SQL

- **Método para extraer los bloques SQL exactos de la PARTE E** del canónico — determinista y
  reproducible, no "buscar a ojo entre los backticks".
- **Hashes o proyección determinista** de esos bloques, de modo que un bloque no pueda cambiar sin que
  cambie el ancla.
- **`pglast` sobre cada fragmento ejecutable**, no sobre el archivo entero.

### 6.3 Identidad canónico ↔ bootstrap

- **Método para demostrar que canónico y bootstrap contienen el mismo SQL autoritativo.**
- **Prueba de identidad por bloques**, no por conteos: bloque a bloque, con hash. Dos archivos pueden
  tener el mismo número de funciones y distinto contenido.

### 6.4 Ejecución real

- **Bootstrap completo ejecutado desde cero en PostgreSQL 17.x.**
- Verificación posterior, sobre el entorno recién creado, de: **firmas**, **`fp_lf`**,
  **`fp_triggerdef`**, **forma de las tablas**, **triggers**, **ACL**, **cero objetos faltantes** y
  **cero objetos extra**.
- Recordatorio de D1 §5: un entorno recién bootstrappeado **nace LF-only**, así que su `fp_raw` debe
  ser igual a su `fp_lf`. Si difieren, algo metió CR.

### 6.5 Ediciones y manifest final

- **Prueba inversa o patcher con `count == 1` para cada edición del canónico.** El canónico tiene
  439 514 B: cada ancla se verifica única antes de aplicar y se prueba la identidad inversa después.
- **Manifest final** con rutas, bytes y **SHA-256 de blob** de todo lo tocado, medido con `sha_blob()`
  de §0.1.

---

## 7. Orden de trabajo

1. **Clone y revalidación del repo** — los tres gates de §0 y la §2 completa contra el HEAD real.
2. **Diseño completo**, incluyendo el procedimiento de extracción read-only (§5) y la especificación de
   validación (§6), más los dos puntos de §4.
3. **Aprobación explícita de Franco.**
4. **Generar únicamente el extractor read-only.** Nada más.
5. **Franco lo ejecuta contra TEST.**
6. **Auditar la salida** y comprobar ausencia de drift — las cinco compuertas de §5.4.
7. **HARD STOP.**
8. **Recién entonces**: generar canónico v1.13.0, bootstrap v1.13.0 y verificador final; correr la
   validación de §6; cierre formal con acuñación `D-HR-*` / `L-HR-*` y propagación a satélites en una
   única pasada; y emitir el kickoff de promoción TEST→OPS.

---

## 8. Criterios de DONE

**Repo y contexto**

- [ ] Clone fresco, HEAD `164794a`, los tres gates en exit 0
- [ ] §2 revalidada contra el HEAD real, con `sha_blob()`
- [ ] §4 resuelta y diseño aprobado explícitamente **antes** de generar artefactos

**Adquisición del vivo (§5)**

- [ ] Extractor read-only entregado, con gate `ambiente = 'test'` y aserción `transaction_read_only = on`
- [ ] Cobertura 18 funciones + 3 `triggerdef`, con firma, `fp_raw`, `fp_lf`, `cantidad_cr`, bytes y
      cuerpos crudo y normalizado
- [ ] Salida machine-readable con reversibilidad probada: base64 → sha256 y bytes coincidentes,
      `md5` reproduciendo `fp_raw` y `fp_lf`
- [ ] Las **5 compuertas de §5.4** en verde, incluida la ausencia de overloads inesperados
- [ ] Hard stop respetado antes de generar el canónico

**Canónico y bootstrap**

- [ ] Canónico en **v1.13.0**, redactado **desde el vivo normalizado a LF**, con los 12 artefactos como
      cadena de custodia
- [ ] Changelog `v1.12.0 → v1.13.0`, encabezado de estado e índice actualizados
- [ ] Fila 30 tratada como `PARCIAL`: sólo el wrapper `resolver_horario`
- [ ] 11 `fp_raw` + `fp_lf`, 3 `fp_triggerdef` y los objetos de D2 pineados
- [ ] Declaración explícita de **PostgreSQL 17.x** en el bootstrap kit
- [ ] Las **5 menciones stale** al bootstrap v1.9.0 corregidas
- [ ] `bootstrap_entorno_nuevo_v1.13.0/` generado; `v1.12.0/` **sin modificar**
- [ ] **OPS intacto**, y su pendiente de promoción declarado explícitamente en el canónico
- [ ] Sede canónica del A07 **sin volver a sustituir**

**Validación (§6)**

- [ ] Manifest de objetos, firmas y orden de dependencias
- [ ] Inventario esperado de tablas, funciones, triggers y ACL
- [ ] Método determinista de extracción de los bloques de la PARTE E, con hashes o proyección
- [ ] `pglast` en exit 0 **sobre cada fragmento ejecutable**
- [ ] Identidad canónico ↔ bootstrap probada **por bloques**, no por conteos
- [ ] Bootstrap ejecutado **desde cero** en PostgreSQL 17.x
- [ ] Verificación post-bootstrap: firmas, `fp_lf`, `fp_triggerdef`, forma de tablas, triggers, ACL,
      cero faltantes y cero extra
- [ ] Patcher con `count == 1` y prueba inversa para **cada** edición del canónico
- [ ] EOL observado con `git ls-files --eol` antes y después de cada edición, y preservado

**Cierre**

- [ ] Verificador propio, read-only, independiente del sistema operativo
- [ ] `D-HR-*` y `L-HR-*` acuñados **sólo en el cierre**
- [ ] Satélites propagados en una única pasada coordinada
- [ ] Cierre formal + kickoff de promoción TEST→OPS emitidos
- [ ] Manifest final con rutas, bytes y SHA-256 de blob

---

## 9. Riesgos y falsos verdes conocidos

### 9.1 "El script corre sin error" no prueba nada acá
El canónico se redacta desde el vivo. Cuatro de los doce artefactos ni siquiera arrancan, y eso es
irrelevante: la prueba es la comparación de cuerpos de D1/D2, ya congelada.

### 9.2 Medir el working tree en vez del blob
Con `core.autocrlf=true` los hashes cambian sin que cambie nada. Le pasó a la auditoría de H3: la v4
dio `11a7f884…` en Windows contra `68babb23…` canónico, por 266 CRLF. Se mide con `sha_blob()` de §0.1,
nunca con una tubería de shell.

### 9.3 El commit que prepara un bloque puede invalidar su propio kickoff
`b058de4` cerró H1, emitió el kickoff de H3 y en el mismo commit agregó 10 archivos y sustituyó la sede
del A07. El kickoff quedó declarando 147 archivos cuando el árbol ya decía 157. **Revalidar §2 contra
el HEAD real es obligatorio, no ceremonial.**

### 9.4 Conteos que suman bien y aun así están mal
Dos clasificaciones pueden intercambiarse conservando los totales; dos archivos pueden tener el mismo
número de funciones y distinto contenido. El verificador de H3 lo resolvió anclando un sha256 de la
proyección fila por fila. **Anclá la proyección, no sólo los totales** — vale igual para la identidad
canónico ↔ bootstrap de §6.3.

### 9.5 Un barrido acotado produce ausencias que no son inexistencias
`2c99db28` estuvo declarado "NO LOCALIZADO" estando versionado en `Workflows/`, fuera del alcance del
barrido. **La primera versión de este mismo kickoff repitió el error:** dio por abiertas las decisiones
de §3.1 y §3.4 porque sólo barrió los artefactos de H3 y el canónico, sin mirar los documentos del
09-07 ni la decisión de fidelidad del 13-07, donde ya estaban escritas. **Declarar siempre el alcance
de una búsqueda antes de concluir una ausencia.**

### 9.6 Reabrir lo cerrado por no encontrar dónde quedó escrito
Corolario del anterior, y la razón de que §3 exista con su procedencia documentada. Una decisión
cerrada que no se encuentra sigue estando cerrada.

### 9.7 Normalizar un archivo existente como efecto lateral
Ver §10. `D2_Q5_CUERPOS_TEST.json` está en `i/crlf`: aplicarle la regla "LF puro" lo rompería. **El EOL
se observa por archivo, no se asume.**

### 9.8 La fecha de carpeta es una etiqueta, no metadata
Dos archivos del carril quedaron con las versiones invertidas respecto de sus carpetas. Se decide por
contenido, coherencia con la evidencia e historial de `git`.

---

## 10. EOL — se observa por archivo, no se asume

**Antes de editar cualquier archivo existente:**

```
git ls-files --eol -- <ruta>
```

Devuelve `i/<eol-en-el-índice>  w/<eol-en-el-working-tree>  attr/<atributos>  <ruta>`. **Después de
editar, repetir el comando y preservar exactamente el estado observado.**

Medido hoy en `164794a`, como ejemplo de por qué esto no es opcional:

```
i/lf     w/lf     attr/     Docs/Implementacion/6B_SCHEMA_SQL.md
i/lf     w/lf     attr/     Docs/Implementacion/bootstrap_entorno_nuevo_v1.12.0/README_EJECUCION_BOOTSTRAP.md
i/crlf   w/crlf   attr/     Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D2_Q5_CUERPOS_TEST.json
```

**No hay una regla histórica única para el repo, y no se debe inventar una.** Los **archivos nuevos**
que genere este bloque son **UTF-8 sin BOM, LF puro y newline final**. Los **existentes** conservan lo
que `git ls-files --eol` reporte para ellos. **Nunca se normaliza un archivo existente como efecto
lateral de una edición.**

---

## 11. Hard stops permanentes

- **Claude diseña, inspecciona, valida y genera artefactos. Franco ejecuta** todo en Supabase, n8n,
  Vercel y git.
- **Sin commit, sin push.** Nunca.
- **No se generan artefactos antes de un diseño aprobado explícitamente.**
- **No se genera el canónico antes de las cinco compuertas de §5.4.**
- **Ediciones quirúrgicas:** `str_replace` con aserción `count == 1` y prueba de identidad inversa.
  Nunca reescritura completa de un archivo existente.
- **EOL observado y preservado** por archivo, según §10.
- **Ninguna escritura en TEST ni en OPS.** El extractor es read-only y lo ejecuta Franco.
- **Los satélites se tocan sólo en el cierre formal**, en una pasada coordinada.
- **Sin Project IDs, secretos ni credenciales reales.** Convención `__PEGAR_`.
- Una decisión debe poder explicarse en una oración a un socio. Si no, está sobrediseñada.

---

## 12. Alcance negativo — lo que este bloque NO toca

**OPS** · `bootstrap_entorno_nuevo_v1.12.0/`, que queda como kit histórico ejecutable · las filas 71,
72 y 76 de contaminación (§3.5) · `H3` y sus tres artefactos ya commiteados · la v3 y la v4 de la
matriz · ningún kickoff histórico · la sede canónica del A07 · la lógica del A07, congelada · **B3.1**
(override de capacidad), pausado y delegado · **Carril D** (agente WhatsApp) · **frente de marketing** ·
**Mercado Pago / MP-02** · el **Pricing Engine B4 / v6.6.3** · cualquier carril ajeno al Motor de
Horarios.

---

## 13. Archivos a subir a la conversación nueva

Sólo este kickoff. **Pero ojo: no todo se lee del clone.** El texto fuente del canónico sale del vivo
de TEST y llega por la vía de §5. Del repo se leen los baselines, la cadena de custodia y el canónico
a editar:

- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` — autoridad
  del doble fingerprint y baseline de los 11 + 2
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md`
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D2_RESULTADOS_TEST_Y_CIERRE_B1_3.md` — baseline de
  los 7 + `trg_ov_guard`
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/13-07-2026/D2_Q5_CUERPOS_TEST.json` — contraste cruzado,
  **no fuente** (§5.1)
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/H3_MATRIZ_CASCADE_REPO_157_ARCHIVOS_v5.md`
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/H3_CIERRE_INVENTARIO_CARRIL.md`
- `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/09-07-2026/KICKOFF_B1_3_CIERRE_DIAGNOSTICO.md` — procedencia
  de la secuencia de §3.1
- `Docs/Implementacion/6B_SCHEMA_SQL.md`
- `Docs/Implementacion/bootstrap_entorno_nuevo_v1.12.0/` — kit de referencia, **no se modifica**
- los 12 artefactos de §2.2

---

## 14. Mensaje inicial para la conversación nueva

> Arrancamos el bloque de **consolidación canónica v1.13.0** del Motor de Horarios. Te subo el kickoff.
>
> Cloná fresco de `origin/main`. HEAD esperado: `164794a54ea28693520db27fdb7bb6b137c6bb07`. Corré los
> tres gates de la §0 y revalidá la §2 completa contra el HEAD real antes de proponerme nada — si algún
> número no coincide, frená y reportámelo. Los hashes se miden con el helper de la §0.1, no con
> tuberías de shell.
>
> Las premisas de la §3 están **cerradas**: no me las reabras ni me pidas que elija entre opciones sobre
> ellas. Consolidamos el estado autoritativo probado en TEST, OPS queda intacto y la promoción es un
> bloque posterior.
>
> Presentame el diseño completo: los dos puntos de la §4, el procedimiento de extracción de la §5 y la
> especificación de validación de la §6. **No generes ningún artefacto antes de que yo lo apruebe.**
> Cuando lo apruebe, generás **únicamente el extractor read-only**, lo corro yo en TEST, y frenás hasta
> que auditemos la salida.
>
> Todo en español rioplatense con voseo. Vos diseñás y validás; yo ejecuto todo en git, Supabase y n8n.

---

## 15. Punto exacto de frenado

El bloque frena, para aprobación de Franco, en **cuatro puntos duros**:

1. Después de revalidar §2 y presentar el diseño (§4 + §5 + §6) — **antes** de generar un solo
   artefacto.
2. Después de entregar el **extractor read-only** — Franco lo ejecuta en TEST y el bloque espera.
3. Después de entregar canónico, bootstrap y verificador — **antes** de cualquier commit.
4. Después del cierre formal — **antes** de emitir el kickoff de promoción TEST→OPS.

Español rioplatense con voseo, sin excepción.
