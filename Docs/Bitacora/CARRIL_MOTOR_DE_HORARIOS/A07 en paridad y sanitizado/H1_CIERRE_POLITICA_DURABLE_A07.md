# H1 — CIERRE: política durable del artefacto A07

**Carril:** Motor de Horarios · **Bloque:** `H1` (post-D2)
**Fecha:** 2026-07-18
**Estado técnico:** ✅ **ACEPTADO por Franco** — la alineación funcional de A07 TEST/OPS no se reabre.
**Estado documental:** ✅ **CERRADO** — evidencia durable incorporada en su totalidad (§1). **Cierre técnico y documental definitivo.**

> **Verificado contra clone fresco.** HEAD `a2a5893` (`fix(portal): corregir H-1 y H-2 del historico contable`), rama `main`, árbol limpio.
> **Gate de apertura:** `git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD` → **exit 0**.

---

## 1. Evidencia durable de la ejecución en Windows

### 1.1 Resultado declarado por Franco

| Chequeo | Resultado |
|---|---|
| Cantidad de nodos | **24** en OPS, TEST y template |
| Estructura (nombres originales y normalizados únicos, sin colisiones) | OK |
| `settings` (`executionOrder`, `binaryMode`) | OK |
| Credenciales PostgreSQL (6 nodos, flavor por ambiente) | OK |
| Conducta de gaps presente | OK |
| OPS vs TEST · TEMPLATE vs TEST · OPS vs TEMPLATE | **sin diferencias funcionales** |
| **Resultado** | **PARIDAD FUNCIONAL CONFIRMADA** |
| **EXIT_CODE_PARIDAD** | **0** |
| Self-tests | **16/16 correctos** |
| **EXIT_CODE_SELFTESTS** | **0** |

### 1.2 Datos exactos incorporados — **CERRADO**

Franco generó `EVIDENCIA_A07_PARIDAD_WINDOWS.txt` (2026-07-18, PowerShell 5.1, `py`). Estado de incorporación:

| Campo | Valor | Estado |
|---|---|---|
| **OPS post-fix verificado** — SHA-256 | `DEA1EA873934CA1670A3292D42D270926505665E088894125F69A7453A9CB6A0` | ✅ |
| **OPS post-fix verificado** — bytes | `42134` | ✅ |
| **TEST usado** — SHA-256 | `3B2E8787F204BB831DE98F75D0A8B01CA325C8B7D17D95AFC5E033A7DCCCD092` | ✅ |
| **TEST usado** — bytes | `42387` | ✅ |
| **Template** — SHA-256 | `3208B0687E4EF878EB74378173DED2BC5C634CAC55CA08F336096DE04EAA8FCD` | ✅ |
| **Template** — bytes | `42004` | ✅ |
| Salida completa de paridad | ver **Apéndice A** | ✅ incorporada |
| `EXIT_CODE_PARIDAD` | **0** | ✅ |
| Salida completa de self-tests | ver **Apéndice B** | ✅ incorporada |
| `EXIT_CODE_SELFTESTS` | **0** | ✅ |
| **Archivo de evidencia** — SHA-256 | `4B9699F17574B8E65B58DF2473CC0C893C92DC56905025CE3535A3E0C539BC2F` | ✅ |
| **Archivo de evidencia** — bytes | `5635` | ✅ |

**Archivos usados en la corrida** (rutas relativas a `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/`):

```
portal-a07-crear-reserva__OPS.json        <- OPS POST-FIX (active=True: export del vivo ya corregido)
portal-a07-crear-reserva__TEMPLATE.json
portal-a07-crear-reserva__TEST.json
```

> **Confirmación relevante:** el verificador reportó `active: OPS_MOD=True`, lo que acredita que el primer argumento fue un **export del OPS vivo ya con el fix aplicado**, no el candidato sanitizado construido como referencia. Es el OPS post-fix real.

> **Nota de encoding.** `Set-Content`/`Add-Content -Encoding utf8` en PowerShell 5.1 escribe **UTF-8 con BOM**. Los 5635 bytes y el SHA-256 corresponden al archivo **con** BOM. Si el archivo se regenera en otra plataforma o sin BOM, ambos valores cambian aunque el contenido visible sea idéntico.

### 1.3 Trazabilidad de snapshots — dos hallazgos

**Hallazgo A — El template coincide byte a byte. Cadena de custodia cerrada.**

| Origen | SHA-256 | Bytes |
|---|---|---|
| Template generado en la conversación | `3208b0687e4ef878eb74378173ded2bc5c634cac55ca08f336096de04eaa8fcd` | 42 004 |
| Template verificado en Windows | `3208B0687E4EF878EB74378173DED2BC5C634CAC55CA08F336096DE04EAA8FCD` | 42 004 |

**Son el mismo archivo.** El artefacto que Franco ejecutó es exactamente el generado y aprobado acá, sin intermediación ni transformación. Esto cierra la custodia del template.

**Hallazgo B — El TEST de la evidencia NO es el mismo snapshot que el de la conversación.**

| Origen | SHA-256 | Bytes |
|---|---|---|
| TEST usado en el análisis de la conversación | `2d36154207df8dae3eeccd0706619d8ae0fb3b7b4bdeefbc540f54be36a41625` | 42 387 |
| TEST usado en la evidencia durable (Windows) | `3B2E8787F204BB831DE98F75D0A8B01CA325C8B7D17D95AFC5E033A7DCCCD092` | 42 387 |

**Mismo tamaño, hashes distintos: no son byte-idénticos.** Ambos pesan exactamente **42 387 bytes**, pero sus SHA-256 difieren, de modo que su contenido no es idéntico. La coincidencia de tamaño no acredita identidad; el hash es el único criterio. Es el patrón típico de dos exports sucesivos del mismo workflow que difieren en identificadores de igual longitud (por ejemplo `versionId`).

Esto **no invalida nada**, pero acota lo que se puede afirmar:

- La **evidencia durable** respalda paridad funcional entre: OPS post-fix (`DEA1EA87…`) · TEMPLATE (`3208B068…`) · TEST-Windows (`3B2E8787…`).
- El **análisis estructural** de este documento (§2.3: 24 nodos, grafo 22/28, 7 de 9 `jsCode` byte-idénticos) se hizo contra **TEST-conversación** (`2d361542…`), no contra TEST-Windows.
- **Refuerzo, no debilitamiento:** el **mismo** template byte-idéntico dio paridad funcional contra **dos snapshots distintos** de TEST, en dos plataformas distintas (Linux y Windows) y por dos ejecutores distintos. La equivalencia funcional queda respaldada de forma más robusta que con una sola corrida.
- **Lo que no se afirma:** que TEST-conversación y TEST-Windows sean byte-idénticos entre sí. No lo son, y no fueron comparados directamente entre ellos.

**Progresión de tamaños de OPS** (coherente con el fix aplicado):

| Artefacto | SHA-256 | Bytes |
|---|---|---|
| OPS **pre-fix** (insumo de comparación) | `19d2439a…f10f7` | 40 845 |
| Candidato sanitizado (referencia construida) | `d0342c9c…09cf7` | 41 981 |
| **OPS post-fix real** (verificado en Windows) | `DEA1EA87…CB6A0` | **42 134** |

El delta pre-fix → post-fix es **+1 289 bytes**, consistente con la incorporación del manejo de gaps en los dos routers. El candidato sanitizado difiere del OPS real porque lleva placeholders y no incluye metadata de instancia (`id`, `versionId`, `webhookId`).

> ⚠️ **Advertencia de hash — no confundir tres artefactos distintos.**
> `19d2439abc50bfb4669ae6906d13261fe713075c509dde4e50e4f52b6d7f10f7` (40 845 B), citado en `REPORTE_COMPARACION_A07_TEST_OPS.md`, corresponde al **OPS ANTERIOR al fix** (insumo de comparación). **No es el hash del OPS post-fix.**
> `d0342c9cdd05a884c74c57bc4107fe2b001f27dfaa6887b6fc78a162742509c7` (41 981 B) corresponde al **candidato OPS sanitizado**, una referencia construida del estado esperado; **no** es un export real.
> El **OPS post-fix real y verificado** es `DEA1EA873934CA1670A3292D42D270926505665E088894125F69A7453A9CB6A0` (42 134 B). Es el único que acredita el estado corregido de OPS.

---

## 2. Resolución de las condiciones del kickoff, punto por punto

### 2.1 §12 — Procedencia · **RESUELTA**

> **Hallazgo que cierra el paso 1: el hash `2c99db28…` NO estaba perdido.** El kickoff anterior §11 lo daba por *"NO LOCALIZADO en el clone"*. Está en `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`. Quedó fuera del barrido previo porque el alcance de la matriz H3 es `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/` y ese archivo vive fuera de esa carpeta.

Inventario de los A07 versionados (medido en el clone, HEAD `a2a5893`):

| Ruta | SHA-256 | Nodos / aristas | Gap-first | Clasificación |
|---|---|---|---|---|
| `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` | `2c99db28…981c3` | 24 / 28 | **Sí** (2 nodos) | Sede actual del template en el repo — el hash "histórico" |
| `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/10-07-2026/…TEMPLATE.PATCHED.json` | `3188bceb…6def` | 24 / 28 | **Sí** (2 nodos) | Salida del patcher `patch_a07_gap_conflicto.py` — fila 70 de H3 |
| `Docs/Implementacion/Carril_C/PROMOCION_OPS/portal-a07-crear-reserva__OPS.json` | `93641838…a230b` | 24 / 28 | **No** (0 nodos) | Registro de la promoción de OPS **anterior al fix** |

Los tres son artefactos **sanitizados/versionables**; ninguno es el RAW.

### 2.2 §13 — Cadena de custodia · **RESUELTA**

**Política de custodia del RAW (vigente):**

> El export RAW queda bajo **custodia privada local de Franco**. No se sube al repo ni a conversaciones. Sólo se comparten **hashes, tamaños y copias sanitizadas**.

**Distinción necesaria entre dos verificaciones diferentes, sobre archivos diferentes:**

| Alcance | Sobre qué archivo | Qué se probó |
|---|---|---|
| **Custodia byte a byte** | Snapshot **anterior** del A07 | Verificación RAW→redactado ejecutada específicamente sobre ese snapshot: RAW y redactado diferían únicamente en la sustitución del literal HMAC por su placeholder. |
| **Paridad funcional** | Snapshots **actuales** usados para TEST / OPS / template | Equivalencia funcional entre los tres, con exit 0 y self-tests en verde. **No incluye** una verificación RAW→sanitizado ejecutada sobre estos archivos. |

> **No se atribuye al snapshot actual una verificación RAW→sanitizado que no fue ejecutada específicamente sobre él.** Lo probado sobre los snapshots actuales es paridad funcional, no custodia byte a byte del RAW.

**Manifiesto y placeholders:** `MANIFIESTO_AMBIENTES_A07.md` documenta los paths ambientales alterados (12 secciones: path, valor por ambiente, obligatoriedad, impacto, validación). Placeholders determinísticos: `__PEGAR_SECRETO_O_USAR_VARIABLE__`, `REEMPLAZAR_POR_CRED_{TEST,OPS}`, `REEMPLAZAR_ID_8CBIS_{TEST,OPS}`.

### 2.3 §14 — Invariantes de nodos, conexiones y `jsCode` · **VERIFICADA, con delta intencional declarado**

Comparación medida entre el template del repo (`2c99db28…`) y el template aprobado (`3208b068…`):

| Invariante | Resultado |
|---|---|
| Nodos | **24 / 24** · mismo conjunto de nombres (idéntico) |
| Conexiones | **22 nodos fuente · 28 aristas** en ambos · **grafo idéntico** |
| `jsCode` de los 9 nodos `code` | **7 de 9 byte-idénticos** |
| `jsCode` que difieren | **2**: `router1_crear` (2062 → 2128 ch) y `router3_confirmar` (1712 → 1831 ch) |

> **Distinción necesaria.** El invariante de §14 exige que **la sanitización** no altere la lógica. La diferencia en los 2 routers **no proviene de la sanitización**: es el **fix funcional aprobado** (alineación del manejo de gaps de calendario), un cambio de contenido intencional. Está acotado exactamente a esos dos nodos: nada más cambió.

**Aclaración de métrica.** El kickoff anterior cita *"22 conexiones"*: corresponde a **22 nodos fuente** en el objeto `connections`. Las **aristas totales son 28** (contando cada destino individual). Ambas métricas coinciden entre el repo y el aprobado. Se deja explícito para que el invariante sea verificable sin ambigüedad.

**Sobre el literal HMAC.** El literal de 64 caracteres del fallback del ternario en `validar_firma_ts_rol` es un **dummy sintético sin valor operativo**, colocado para preservar longitud en los exports de trabajo. No es el secreto real y no requiere rotación. Los artefactos versionables lo reemplazan por `__PEGAR_SECRETO_O_USAR_VARIABLE__`. El verificador lo normaliza acotado a ese ternario y **no clasifica ningún literal como secreto por su longitud**.

### 2.4 §15 — Política durable del A07 · **DEFINIDA**

| Punto | Definición |
|---|---|
| **Naturaleza del template aprobado** | **Template canónico sanitizado con TEST como flavor de referencia**, derivable a OPS exclusivamente mediante `MANIFIESTO_AMBIENTES_A07.md`. Usa nombre y webhook `__TEST`, placeholders TEST y prefijo `portal_test_a07_`. **No es flavor-neutral.** |
| **Sede canónica** | `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`. Los A07 bajo `Docs/Bitacora/` y `Docs/Implementacion/Carril_C/PROMOCION_OPS/` son **evidencia histórica**, no autoridad. |
| **Qué se commitea** | Solo el sanitizado: sin `id`/`versionId`, `meta = null`, sin `webhookId`, sin ids de credencial ni de subworkflow. |
| **Qué nunca se commitea** | El RAW. Custodia privada local de Franco (§2.2). |
| **Cómo se re-sanitiza** | Aplicando el mismo manifiesto (paths declarados) y probando los invariantes de §2.3. Cualquier cambio fuera del manifiesto es fallo de sanitización. |
| **Cómo se valida** | `verificador_a07.py` (read-only) sobre la terna candidato/template/vivo, con exit 0, más `--self-test`. |
| **Cómo se aplica un fix a un ambiente** | **Edición en el lugar**: reemplazar únicamente el texto del `jsCode` del nodo afectado. No copiar nodos completos, no tocar conexiones, conservar `Code: derivar`, credenciales, webhook y subworkflow del ambiente. |
| **Normalización de referencias** | Al pegar entre ambientes: `$('Code: derivar1')` → `$('Code: derivar')`, `$('router1_crear1')` → `$('router1_crear')`. El sufijo `1` es artefacto de duplicación en n8n, cosmético. |

---

## 3. Alcance de los self-tests del verificador

> **Los self-tests comprobaron que el verificador detecta correctamente las mutaciones negativas incluidas y preserva los casos positivos.**

Desglose exacto de los 16 casos ejecutados:

| Tipo | Cantidad | Casos |
|---|---|---|
| **Mutaciones negativas** (deben hacer fallar) | **14** | `onError` · `alwaysOutputData` · `disabled` · `retryOnFail` · `maxTries` · `waitBetweenTries` · `executeOnce` · `settings.executionOrder` · `settings.binaryMode` · nodo duplicado (cantidad) · colisión de nombres normalizados · credencial PG con flavor equivocado · cambio funcional de mensaje en `router1_crear` · cambio funcional de `code` en `router1_crear` |
| **Casos positivos** (no deben fallar) | **2** | terna limpia · **mutación del dummy HMAC** (cambia solo el literal del fallback: no produce diferencia ni lenguaje de secreto) |
| **Total** | **16** | 16/16 correctos, `EXIT_CODE_SELFTESTS = 0` |

> **Ajuste de conteo — confirmado por la evidencia real.** La instrucción mencionaba *"15 mutaciones negativas"*. La salida de Windows registra **14** casos con `esperado_falla=True` y **2** con `esperado_falla=False` (terna limpia + dummy HMAC), total 16. Si se cuentan las **mutaciones** aplicadas al archivo base son **15** (14 negativas + la del dummy HMAC, que es positiva); la terna limpia no es una mutación. El desglose de arriba coincide exactamente con `EVIDENCIA_A07_PARIDAD_WINDOWS.txt` (Apéndice B).

**No se afirma que el falso verde sea imposible.** Lo comprobado es la cobertura de las mutaciones enumeradas.

> ⚠️ **Discrepancia detectada entre esta formulación y el banner del propio verificador.**
> `verificador_a07.py` imprime, al encabezar los self-tests:
> `SELF-TESTS -- exit 0 debe ser IMPOSIBLE ante cada mutacion`
> Esa es exactamente la formulación absoluta que la política de redacción descarta, y queda impresa dentro de la evidencia durable. **No se modificó** (fuera del alcance de esta corrección). Queda registrado como ajuste cosmético pendiente: cambiar el banner por una formulación equivalente a la de esta sección. El cambio afecta solo una cadena de texto del banner, no la lógica del verificador ni sus resultados; requeriría regenerar la evidencia para mantener la correspondencia literal.

---

## 4. Artefactos y evidencias de H1

### 4.1 Clasificación de custodia

| Archivo | SHA-256 (bytes) | Rol | **Clasificación de custodia** |
|---|---|---|---|
| `portal-a07-crear-reserva__TEMPLATE.json` | `3208b068…8fcd` (42 004) | Template canónico, flavor de referencia **TEST** · byte-idéntico al verificado en Windows | **Sanitizado y versionable** |
| `portal-a07-crear-reserva__OPS__CANDIDATO_SANITIZADO.json` | `d0342c9c…09cf7` (41 981) | Estado esperado de OPS post-fix | **Sanitizado, referencia construida** |
| `portal-a07-crear-reserva__OPS.json` (post-fix) | `DEA1EA87…CB6A0` (42 134) | Export real de OPS ya corregido; acredita el estado post-fix | ⚠️ **Evidencia privada local — NO commitear** |
| `EVIDENCIA_A07_PARIDAD_WINDOWS.txt` | `4B9699F1…BC2F` (5 635, UTF-8 con BOM) | Evidencia durable de la ejecución (Apéndices A y B) | **Evidencia documental versionable, solo tras confirmar que no contiene datos sensibles** |
| **RAW de TEST / OPS** | — | Exports crudos de n8n | ⚠️ **Custodia privada local — NO subir ni commitear** |

> **Chequeo previo a versionar la evidencia.** `EVIDENCIA_A07_PARIDAD_WINDOWS.txt` incluye rutas absolutas de la máquina de Franco (`C:\Users\franc\OneDrive\…`) provenientes del campo `Path` de `Get-FileHash`. Confirmar que eso sea aceptable, o recortarlo, **antes** de commitear. No contiene secretos: el fallback HMAC es el dummy sintético y el verificador no lo imprime.

### 4.2 Documentación de soporte (sanitizada y versionable)

| Archivo | Rol |
|---|---|
| `MANIFIESTO_AMBIENTES_A07.md` | Manifiesto de paths ambientales |
| `REPORTE_COMPARACION_A07_TEST_OPS.md` | Comparación nodo por nodo |
| `GUIA_COPIA_A07_TEST_A_OPS.md` | Procedimiento de edición en el lugar |
| `verificador_a07.py` | Verificador read-only + self-tests |
| `PLAN_PRUEBAS_A07.md` | Plan de pruebas en dos capas |

**Los cinco valores que cambian por ambiente:** webhook path · secreto HMAC operativo vía `$vars` · credenciales PostgreSQL de los 6 nodos · id del subworkflow de avisos 8C-bis · prefijo de idempotencia.

---

## 5. Estado del A07 tras H1

> **La lógica de A07 está congelada.** Durante la consolidación, Franco sustituirá la sede canónica del repo por el template ya aprobado, **sin rediseñarlo ni modificar su lógica**.

Esto no reabre A07: es una **sustitución de archivo en el repo**, no un cambio funcional. No ocurre en H3 (ver alcance del kickoff de H3), sino en el bloque de consolidación canónica.

---

## 6. Decisiones y lecciones candidatas (propuestas, **sin acuñar**)

Series `D-HR-*` / `L-HR-*`: **libres** (cero ocurrencias en los satélites del clone). Se acuñan en el bloque de consolidación, con aprobación explícita de Franco.

**Decisiones candidatas**

| Tema | Enunciado en una línea |
|---|---|
| Sede única del A07 | El template sanitizado vive en `Workflows/n8n/Supabase/`; las copias bajo `Docs/` son evidencia histórica. |
| Custodia del RAW | El RAW queda bajo custodia privada local de Franco; solo se comparten hashes, tamaños y copias sanitizadas. |
| Flavor de referencia | El template canónico usa TEST como flavor de referencia y se deriva a OPS solo mediante el manifiesto. |
| Edición en el lugar | Los fixes entre ambientes se aplican reemplazando solo el `jsCode` del nodo, nunca copiando nodos completos. |
| Sufijo `1` cosmético | El sufijo que n8n agrega al duplicar es cosmético; se normaliza al pegar, no se replica en el repo. |
| Dummy HMAC | El literal del fallback es un dummy sintético sin valor operativo; no se trata como secreto ni por longitud. |
| Verificación obligatoria | Ningún A07 se declara alineado sin exit 0 del verificador y self-tests en verde, con evidencia durable archivada. |

**Lecciones candidatas**

| Tema | Enunciado en una línea |
|---|---|
| Alcance del barrido | Un hash "no localizado" puede estar fuera del alcance del barrido: `2c99db28` estaba en `Workflows/`, no en `Docs/Bitacora/`. |
| Falsos verdes por normalización | Una regex de normalización amplia sobre todo el `jsCode` puede ocultar cambios funcionales; acotar el enmascarado al path exacto. |
| Métrica de conexiones | "22 conexiones" y "28 aristas" miden cosas distintas; declarar cuál se usa o el invariante es ambiguo. |
| Código de error ≠ flag | `override_hora_invalido` y `hora_fuera_de_rango` son códigos de error del motor SQL mapeados a `payload_invalido`, no flags del cliente. |
| Hash por artefacto | Un hash de insumo (OPS pre-fix) no puede presentarse como hash del resultado (OPS post-fix). Etiquetar cada hash con su artefacto y su momento. |

---

## 7. Alcance negativo de H1

- No se ejecutó nada en TEST ni en OPS desde la conversación; toda ejecución la hizo Franco.
- No se importaron workflows en n8n · no se tocó Supabase · no se corrió SQL.
- No se modificó el canónico, el bootstrap ni los satélites.
- No se hicieron commits ni push.
- No se resolvió la fila 70 de H3 (queda para el bloque H3, ahora desbloqueada).
- No se consolidó el canónico v1.13.0 (bloque aparte, posterior a H3).
- No se sustituyó la sede canónica del A07 (ocurre en la consolidación, §5).

---

## 8. Qué desbloquea este cierre

1. **Fila 70 de H3** (`10-07-2026/portal-a07-crear-reserva__TEMPLATE.PATCHED.json`, autoridad `PENDIENTE_H1`, acción `BLOQUEADO_H1`, fingerprint `3188bceb777b`) pasa a su estado definitivo. Era la **única fila abierta** de la matriz v4.
2. Con H3 sin filas abiertas, se habilita el bloque de consolidación canónica v1.13.0.

**Continuación inmediata:** `KICKOFF_H3_CIERRE_INVENTARIO.md`.
**Posterior, en bloque separado:** `KICKOFF_CONSOLIDACION_CANONICA_v1_13_0.md` (se emite recién tras el cierre real de H3).

---

## Apéndice A — Salida completa de paridad (Windows, 2026-07-18)

Comando ejecutado desde `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/`:

```powershell
& py .\verificador_a07.py `
  ".\portal-a07-crear-reserva__OPS.json" `
  ".\portal-a07-crear-reserva__TEMPLATE.json" `
  ".\portal-a07-crear-reserva__TEST.json"
```

```
========================================================================
VERIFICADOR A07  --  paridad funcional (read-only)
========================================================================
  OPS_MOD  : .\portal-a07-crear-reserva__OPS.json  (24 nodos)
  TEMPLATE : .\portal-a07-crear-reserva__TEMPLATE.json  (24 nodos)
  TEST     : .\portal-a07-crear-reserva__TEST.json  (24 nodos)

[ESTRUCTURA] OK: 24 nodos, nombres originales y normalizados unicos en los tres.
[DESPLIEGUE] active: OPS_MOD=True, TEMPLATE=False, TEST=True   (informativo; versionables inactivos / vivos activos)
[SETTINGS] OK: {'executionOrder': 'v1', 'binaryMode': 'separate'} en los tres.
[CREDENCIALES] OPS_MOD OK: 6 nodos PostgreSQL con credencial flavor 'ops'.
[CREDENCIALES] TEMPLATE OK: 6 nodos PostgreSQL con credencial flavor 'test'.
[CREDENCIALES] TEST OK: 6 nodos PostgreSQL con credencial flavor 'test'.
[HMAC] El fallback del ternario en validar_firma_ts_rol es un DUMMY
       SINTETICO de longitud fija, SIN valor operativo (solo preserva
       longitud en los exports de trabajo). Se normaliza acotado a ese
       ternario; no se compara ni se imprime. Los artefactos versionables
       usan __PEGAR_SECRETO_O_USAR_VARIABLE__.
[CONDUCTA] OK: gap-errors presentes en router1_crear y router3_confirmar (los tres).

------------------------------------------------------------------------
COMPARACION  OPS_MOD  vs  TEST
------------------------------------------------------------------------
  OK  --  sin diferencias funcionales.

------------------------------------------------------------------------
COMPARACION  TEMPLATE  vs  TEST
------------------------------------------------------------------------
  OK  --  sin diferencias funcionales.

------------------------------------------------------------------------
COMPARACION  OPS_MOD  vs  TEMPLATE
------------------------------------------------------------------------
  OK  --  sin diferencias funcionales.

========================================================================
RESULTADO: PARIDAD FUNCIONAL CONFIRMADA  (exit 0)
========================================================================
```

`EXIT_CODE_PARIDAD = 0`

---

## Apéndice B — Salida completa de self-tests (Windows, 2026-07-18)

```powershell
& py .\verificador_a07.py --self-test `
  ".\portal-a07-crear-reserva__OPS.json" `
  ".\portal-a07-crear-reserva__TEMPLATE.json" `
  ".\portal-a07-crear-reserva__TEST.json"
```

```
========================================================================
SELF-TESTS  --  exit 0 debe ser IMPOSIBLE ante cada mutacion
========================================================================
Base: OPS=portal-a07-crear-reserva__OPS.json | TEMPLATE=portal-a07-crear-reserva__TEMPLATE.json | TEST=portal-a07-crear-reserva__TEST.json

[PASS] POSITIVO trio limpio                           esperado_falla=False  obtuvo_falla=False  exit=0
[PASS] onError modificado                             esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] alwaysOutputData modificado                    esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] disabled agregado                              esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] retryOnFail agregado                           esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] maxTries agregado                              esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] waitBetweenTries agregado                      esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] executeOnce agregado                           esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] settings.executionOrder modificado             esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] settings.binaryMode modificado                 esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] nodo duplicado (cantidad)                      esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] colision por norm_node_name (sufijo 1)         esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] credencial PG con flavor equivocado            esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] cambio funcional de mensaje en router1         esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] cambio funcional de code en router1            esperado_falla=True  obtuvo_falla=True  exit=1
[PASS] HMAC: cambiar solo el dummy (no debe fallar ni marcar secreto) esperado_falla=False  obtuvo_falla=False  exit=0

------------------------------------------------------------------------
SELF-TESTS: 16/16 correctos.
RESULTADO SELF-TESTS: TODOS OK  (exit 0)
========================================================================
```

`EXIT_CODE_SELFTESTS = 0`

> **Nota metodológica sobre esta corrida.** Los self-tests usaron como base el **OPS post-fix real**, no el candidato sanitizado. Las mutaciones se aplican en memoria sobre una copia (`deepcopy`); el archivo en disco no se modifica. Es una corrida read-only.
