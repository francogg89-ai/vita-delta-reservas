# H3 — CIERRE DE INVENTARIO DEL CARRIL

**Carril:** Motor de Horarios · **Bloque:** `H3-cierre-inventario`
**Predecesor:** `H1` — cierre técnico y documental definitivo (`H1_CIERRE_POLITICA_DURABLE_A07.md`)
**Sucesor:** `KICKOFF_CONSOLIDACION_CANONICA_v1_13_0.md` — se emite recién después de que Franco commitee este cierre
**Estado:** **CERRADO, sin filas abiertas**

> **Un bloque por conversación.** Este cierre cubre exclusivamente H3. La consolidación canónica
> v1.13.0 es un bloque separado con su propio kickoff. No se mezcla.

---

## 1. Contexto medido

```
clone            fresco de origin/main
HEAD             b058de456afd186f91d6ff7e5666978ef4b4df64  (b058de4)
mensaje          chore(horarios): cerrar H1 y preparar inventario H3
rama             main
árbol al abrir   limpio (git status --porcelain vacío)
gate D2          git merge-base --is-ancestor 82f28df HEAD  ->  exit 0
cadena           82f28df -> d6fc392 -> 8dd1235 -> a2a5893 -> b058de4
```

El kickoff de H3 fue emitido contra `a2a5893`. **HEAD resultó posterior**, así que se revalidó todo
antes de generar nada, según su propia §0.

### 1.1 Revalidación — qué se confirmó y qué caducó

**Confirmado byte a byte:** los sha256 y tamaños de ambas matrices; los 7 duplicados con sus 5
idénticos y 2 divergentes; los dos `HORARIOS_B2_RUNSHEET` con MD5 y SHA-256; los 3 archivos de
contaminación con sus tamaños.

**Caducado — dos números del kickoff, ambos invalidados por el propio `b058de4`:**

| Kickoff §  | Decía | Medido a `b058de4` |
|---|---|---|
| §2.3 | 147 archivos versionados bajo el carril | **157** — el commit agregó 10 |
| §2.4 | `2c99db28` está en la sede canónica del A07 | La sede hoy es **`3208b068…8fcd`**; el commit la sustituyó |

Ninguna de las dos era un error del kickoff: eran verdaderas contra `a2a5893`, su HEAD declarado. Lo
que caducó es la lectura en presente. Se resuelve en la v5, §6.3.

---

## 2. Alcance ejecutado — los 9 puntos del kickoff §1

| # | Punto | Resultado |
|---|---|---|
| 1 | Confirmar la matriz autoritativa | **v4 (`13-07-2026`)**, por tres criterios convergentes. v5 §1 |
| 2 | Crear una v5 derivada de la v4 | `H3_MATRIZ_CASCADE_REPO_157_ARCHIVOS_v5.md`, 157 filas |
| 3 | v3 y v4 intactas, sin modificar | Verificado: sha256 sin cambio. §5 de este cierre |
| 4 | Cerrar la fila 70 | `HISTORICO` / `NO` / `ARCHIVAR_EVIDENCIA`. v5 fila 70 |
| 5 | Registrar la ruta real de `2c99db28` sin reescribir kickoffs | Addendum por coordenada inmutable. v5 §6 |
| 6 | Clasificar ambos `HORARIOS_B2_RUNSHEET` | Filas 87 y 88, ambos `ARCHIVAR`. v5 §8 |
| 7 | Documentar la contaminación de otros carriles | Filas 71, 72, 76, `RECLASIFICAR`, **no movidas**. v5 §9 |
| 8 | Dejar H3 sin filas abiertas | **Cero**: sin `PENDIENTE_D2`, `CANDIDATO_REPO_HASTA_D2`, `PENDIENTE_H1` ni `BLOQUEADO_H1` |
| 9 | Emitir el cierre H3 | Este documento |

---

## 3. Decisiones tomadas en H3

### 3.1 Matriz autoritativa — v4, por mantenimiento medido

Las dos copias de la matriz están con las versiones invertidas respecto de la fecha de sus carpetas.
Se confirma la de `13-07-2026` (**v4 — post-D2**). El criterio **no es la fecha de carpeta**:

1. **Contenido** — la v4 es superconjunto estricto de la v3.
2. **Coherencia con D2** — la v3 conserva 4 filas `PENDIENTE_D2`, que el D2 ya corrido en verde
   (`sha256_lf_vivo = sha256_lf_repo` 7/7) invalidó.
3. **Historial de mantenimiento** — decisivo:

| commit | fecha | copia `13-07` | copia `14-07` |
|---|---|---|---|
| `03e20a6` | 2026-07-14 20:11 | `51cc2252…` v3 | `51cc2252…` v3 |
| `82f28df` | 2026-07-15 11:00 | `eeac64de…` **v4** | `51cc2252…` |
| `8dd1235` | 2026-07-15 21:43 | `68babb23…` **v4** | `51cc2252…` |
| `b058de4` | 2026-07-18 | `68babb23…` **v4** | `51cc2252…` |

**Las dos nacieron byte-idénticas.** Sólo una se mantuvo. La copia de `14-07-2026` es un **fósil** del
baseline v3, no una versión distinta guardada por error en la carpeta equivocada.

Confirmación independiente: la misma inversión se repite en `D2_RUNBOOK.md` — la copia de `13-07` es
la POST-D2 y la de `14-07` es la PRE-D2. Dos archivos, misma dirección.

**Regla fijada:** *autoridad por mantenimiento medido, no por etiqueta de carpeta.*

### 3.2 Denominador — 157, con dos HEAD de procedencia

```
HEAD_BASE_MATRIZ  = 07fea85802bc4fccbff1236813593762aefe58d9   -> filas 1..107
FILAS_BASE        = 107
HEAD_CORTE_H3     = b058de456afd186f91d6ff7e5666978ef4b4df64   -> filas 108..157
FILAS_DELTA       = 50
TOTAL_VERSIONADOS = 157
ALCANCE           = Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/
```

Los dos HEAD son coordenadas de **procedencia**, no dos denominadores alternativos. **El denominador
es 157.** La numeración 1–107 de la v4 se conserva sin desplazamientos, así el diff v4→v5 queda
auditable fila por fila.

### 3.3 Fila 70 — cerrada

| campo | v4 | v5 |
|---|---|---|
| `estado` | `VIGENTE` | **`HISTORICO`** |
| `autoridad_actual` | `PENDIENTE_H1` | **`NO`** |
| `dominio_autoridad` | `APP_N8N` | **`NINGUNO`** |
| `fragmento_autoritativo` | Workflow n8n. No es SQL. BLOQUEADO por H1 | **`—`** |
| `estado_script` | `NO_APLICA` | `NO_APLICA` |
| `referencia_viva` | `A07 (n8n)` | **`Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`** |
| `accion_v1_13` | `BLOQUEADO_H1` | **`ARCHIVAR_EVIDENCIA`** |

El `motivo` distingue explícitamente los tres artefactos que se venían confundiendo: la salida
histórica del patcher (`3188bceb…`, esta fila), la sede canónica actual (`3208b068…`) y el export
histórico pre-fix (`93641838…`).

### 3.4 `2c99db28` — registrado por coordenada inmutable

```
contenido    sha256  2c99db28866a4e9e7e0ec586e5a18fd443a4b91b64b704fcaa833cbe31a981c3
blob Git     sha1    bd731c6817370148023118c8a5de290a4db05858
ruta histórica       Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
vigencia desde       9ff6db7  (2026-07-11)
último commit
donde estuvo         a2a5893  (2026-07-16)
sustituido en        b058de4  (2026-07-18)

sustituto    sha256  3208b0687e4ef878eb74378173ded2bc5c634cac55ca08f336096de04eaa8fcd
             blob    49bf96a4b12e8aea8ea2c2115670006db8a10126
```

Se registra por **blob**, no por ruta: el blob es content-addressed y sobrevive a movimientos,
renombres y ediciones. La ruta ya dejó de apuntar a ese contenido.

**Precisión obligatoria — dos errores de distinta naturaleza.** No se reescribió H1 ni ningún kickoff
histórico, pero decir que "no hay nada que corregir" sería impreciso, y meter las tres afirmaciones
históricas en la misma bolsa también lo sería.

**`2c99db28 NO LOCALIZADO` fue un FALSO NEGATIVO, no una verdad relativa al HEAD.** El archivo ya
estaba versionado en el árbol: vivía en `Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`
desde `9ff6db7` (2026-07-11). El barrido que produjo ese resultado estaba **acotado a
`Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/`**. Por lo tanto:

- el resultado era verdadero **únicamente respecto de ese barrido limitado**;
- **no era verdadero como afirmación global sobre el repositorio**;
- **H1 corrigió el falso negativo ampliando el alcance a `Workflows/`.**

Las otras dos afirmaciones sí son caducidad genuina: H1 §2.1 y el kickoff de H3 fueron **medidos
contra `a2a5893`** — declarado en las líneas 8 y 111 de H1 — y eran verdaderas contra ese HEAD.
Dejaron de serlo cuando `b058de4` cambió el árbol.

Sobre eso último: la sustitución de la sede canónica que **H1 §5 proyectaba para el bloque de
consolidación** terminó **ejecutándose de forma anticipada en `b058de4`**, el mismo commit que cerró
H1 y preparó H3. La sede ya está sustituida *antes* de que H3 cierre, no después.

**Consecuencia para el bloque siguiente: la consolidación v1.13.0 debe partir de que la sede canónica
del A07 ya es `3208b068…8fcd`, y no volver a sustituirla.**

### 3.5 Nota de auditoría — el changelog de la v4 subdeclara

El diff semántico real v3 → v4 cambió **6 filas: 4, 5, 8, 9, 70 y 86**. El changelog de la v4 declara
4, 8, 9, 86 y además la 16. Por lo tanto:

- Las filas **5** y **70** cambiaron y **no están declaradas** (sólo en `motivo`, coherentes con D2).
- La fila **16 no cambió** entre v3 y v4, aunque el changelog de la v4 la presenta como cambio: ya
  venía corregida desde la v3.

Ninguna de las dos altera clasificación. El efecto es de trazabilidad. **Registrado en la v5 §2, sin
tocar la v3 ni la v4.**

---

## 4. Artefactos emitidos

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `H3_MATRIZ_CASCADE_REPO_157_ARCHIVOS_v5.md` | 76 027 | `ffa04f9d13c31776c378e3cdd33936d47287ec125e73caa8e1c74c76b67cdcfb` |
| `VERIFICADOR_H3_v5.py` | 23 430 | `a5f62e306cb734456a4fe6ed6f7acc2d34ba7a7e6a11b63b306729ee4accc297` |
| `H3_CIERRE_INVENTARIO_CARRIL.md` (este) | *se reporta en la entrega* | *un documento no puede contener su propio hash* |

Los tres en `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/`.
**UTF-8 sin BOM · EOL LF puro · newline final.** Los tres son **altas**: cero archivos modificados,
cero borrados, cero movidos.

El verificador es **estrictamente read-only e independiente del sistema operativo**: no escribe
ningún archivo, no borra, no mueve, no commitea, no toca red, **no modifica la configuración de Git,
no hace reset y no normaliza el clone**.

Para todo archivo versionado mide el **objeto Git** vía `git cat-file blob HEAD:<ruta>`, nunca el
working tree, y verifica el return code de cada comando. Sólo las tres altas — que no tienen blob en
`HEAD` — se miden del working tree. **Resultado comprobado idéntico con `core.autocrlf=true` y con
`core.autocrlf` sin definir: `OK: 118 · FALLAS: 0 · exit 0` en ambos casos.**

---

## 5. Criterios de DONE — kickoff §4

| Criterio | Estado |
|---|---|
| clone fresco + gate `82f28df` exit 0 | ✅ |
| matriz autoritativa confirmada por contenido, criterio documentado | ✅ v5 §1 |
| v5 creada, derivada de la v4 | ✅ 157 filas |
| v3 y v4 intactas (sha256 sin cambios) | ✅ §6.3 |
| denominador decidido y declarado con HEAD de corte | ✅ 157, dos HEAD |
| fila 70 cerrada con estado definitivo | ✅ |
| ruta real de `2c99db28` registrada | ✅ v5 §6, por blob |
| kickoffs históricos NO reescritos | ✅ |
| 7 duplicados clasificados (5 idénticos + 2 divergentes) | ✅ v5 §7 |
| ambos `HORARIOS_B2_RUNSHEET` clasificados | ✅ filas 87 y 88 |
| 3 archivos de contaminación documentados, NO movidos | ✅ filas 71, 72, 76 |
| v5 sin filas abiertas | ✅ cero |
| cierre H3 emitido | ✅ este documento |
| canónico / bootstrap / satélites / sede A07 intactos | ✅ §6.4 |
| verificación independiente del sistema operativo | ✅ §6.0 — idéntica con `core.autocrlf` true y false |

---

## 6. Evidencia

### 6.0 Los hashes de archivos versionados son de BLOBS Git, no del working tree

**Todo SHA-256 y MD5 de un archivo versionado que aparece en este cierre y en la v5 corresponde a los
bytes del objeto Git — representación canónica LF — y no a la representación *smudged* del working
tree.**

La distinción no es teórica. Con `core.autocrlf=true`, el checkout de Git convierte LF → CRLF al
escribir el working tree. El archivo en disco queda legítimamente distinto del objeto versionado y
`git diff` sigue limpio, porque la conversión es parte del contrato de Git. Medido sobre la v4:

```
blob Git (canónico, LF)        37 715 B   68babb238033a985199e6eab8fbbd766fe55b4640dfdf95fc630bb096901b093
working tree smudged (CRLF)    37 981 B   11a7f884e4de8ca9a20d47f8979a82bcdd1c667b2aaf21ed8447961d427e27d1
```

Son **266 secuencias CRLF** sobre 266 LF: el mismo objeto, dos representaciones. Una auditoría real en
Windows sobre clone fresco midió exactamente `11a7f884…`, y la conversión LF → CRLF del blob canónico
reproduce ese valor byte a byte.

**Consecuencia para quien audite:** un `sha256sum` del working tree en Windows **no** coincidirá con
los valores de estos documentos, y eso no indica alteración. Para reproducirlos:

```
git cat-file blob HEAD:<ruta> | sha256sum        # canónico, en cualquier sistema operativo
git show     HEAD:<ruta>      | sha256sum        # equivalente
```

**Excepción deliberada:** las tres altas de H3 están en estado `??` y todavía no tienen blob en `HEAD`.
Sus hashes son los bytes reales del working tree, que es donde viven. Son LF puro, y el verificador lo
comprueba.

### 6.1 Conteos sobre las 157 filas de datos

Contados **sólo sobre filas de datos** de la tabla grande, parseadas por su cabecera de 15 columnas.
No por `grep` global: los diccionarios y las notas contienen los mismos tokens.

| `estado` | n | | `autoridad_actual` | n | | `accion_v1_13` | n | | `estado_script` | n |
|---|---|---|---|---|---|---|---|---|---|---|
| `VIGENTE` | 99 | | `NO` | 144 | | `CITAR` | 72 | | `NO_APLICA` | 71 |
| `HISTORICO` | 28 | | `SI` | 12 | | `ARCHIVAR` | 37 | | `EJECUTABLE` | 71 |
| `SUPERADO` | 19 | | `PARCIAL` | 1 | | `ARCHIVAR_EVIDENCIA` | 30 | | `NO_EJECUTABLE_GATE_OBSOLETO` | 15 |
| `DUPLICADO` | 6 | |  |  | | `CONSOLIDAR` | 12 | |  |  |
| `CONTAMINACION` | 3 | |  |  | | `PRESERVAR_APP` | 3 | |  |  |
| `COLISION_DIVERGENTE` | 2 | |  |  | | `RECLASIFICAR` | 3 | |  |  |

Las cuatro columnas suman **157**. Numeración contigua 1..157, sin huecos ni repeticiones.

### 6.2 Prueba de cero filas abiertas

| Token | Ocurrencias en `autoridad_actual` o `accion_v1_13` |
|---|---|
| `PENDIENTE_D2` | **0** |
| `CANDIDATO_REPO_HASTA_D2` | **0** |
| `PENDIENTE_H1` | **0** |
| `BLOQUEADO_H1` | **0** |

Los cuatro valores quedan **retirados por agotamiento** y documentados en el diccionario de la v5
únicamente para poder leer la v3 y la v4.

`CONSOLIDAR` sigue en **12**, los mismos de la v4, **sin altas ni bajas**, y los 12 están todos en las
filas 1..107.

### 6.2.1 Clasificación individual anclada — contra el intercambio de filas

Los conteos por sí solos no impiden que dos filas intercambien clasificación conservando los totales.
Para cerrar ese hueco, el verificador fija el SHA-256 de la proyección
`ruta|estado|autoridad_actual|dominio_autoridad|estado_script|accion_v1_13|superado_por`, ordenada por
ruta:

```
filas 108..157   50 líneas   e35ea95da60049d6e4a0a28904354fe0d470c45c28c1d60ff622cc1646353861
filas 1..157    157 líneas   966e5394f362689e7009ed1b9238270d643b12c091e5b930b474520c6574837c
```

Las 157 líneas de proyección son **distintas entre sí**: ninguna fila puede ser reemplazada por otra
sin alterar el hash.

### 6.3 v3 y v4 byte-idénticas

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `14-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` (**v3**) | 35 910 | `51cc22524b29e4438f73e0e4cd32e67fc8c6576f4fbb2ffb2b4e2916657dca7c` |
| `13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` (**v4**) | 37 715 | `68babb238033a985199e6eab8fbbd766fe55b4640dfdf95fc630bb096901b093` |

Idénticos a lo medido al abrir el bloque y a lo declarado en el kickoff §2.1.
`git diff --name-only HEAD` no las lista.

### 6.4 Intocables — verificados sin modificar

`Docs/Implementacion/6B_SCHEMA_SQL.md` · `bootstrap_entorno_nuevo_v1.12.0/` ·
`Docs/Operacional/` · `CLAUDE.md` · `README.md` ·
`Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json` · v3 · v4 · kickoffs históricos.

TEST, OPS, Supabase y n8n: **no tocados**. Sin commits, sin push.

### 6.5 Por qué el delta no aporta candidatos al canónico

**Desglose de los 23 `.sql`, para despejar la discrepancia con el "21" de una entrega anterior:** son
**21 archivos de nombre único** bajo `13-07-2026/` (12 de D1 + 9 de D2) **más 2 copias duplicadas**
bajo `14-07-2026/` (`D2_Q4_TRIGGER_OV_GUARD.sql` y `D2_Q7_VEREDICTO.sql`). 21 + 2 = **23 filas `.sql`**
en la matriz: 110–121, 125–131, 133, 134, 142 y 143. La medición anterior había recorrido sólo la
carpeta `13-07-2026/` y por eso reportó 21; la afirmación cubría 23. **Corregido: la prueba de esta
entrega recorre los 23.**

Resultado sobre los 23: **cero sentencias DDL o DML no comentadas**; los 23 abren
`BEGIN TRANSACTION READ ONLY`; los 23 traen su propio gate de ambiente sobre
`configuracion_general('ambiente')`. La única coincidencia con patrón DDL en todo el conjunto está en
un **comentario** de `D1_Q2_OVERLOADS.sql`, línea 32.

El comando y su stdout íntegro se entregan en `PRUEBA_READONLY_23_SQL.txt`, y el chequeo está además
incorporado al verificador (§14), que descuenta comentarios de línea y de bloque antes de buscar
sentencias mutantes.

Los 27 restantes: `.md` de cierre y diseño, `.txt` de harness, `.patch`, `.json` de evidencia, 2 `.js`
de nodo y 1 `.py` verificador. **Ninguno de los 50 puede ser autoridad del canónico SQL.**

### 6.6 Medición nueva — paridad de los `jsCode`

| Nodo | En la sede canónica | En el extracto `.js` | Idénticos |
|---|---|---|---|
| `router1_crear` | 2 128 ch | 2 128 ch | **sí, byte a byte** |
| `router3_confirmar` | 1 831 ch | 1 831 ch | **sí, byte a byte** |

Coincide con los tamaños post-fix que declara H1 §2.3. Paridad probada; la autoridad la retiene la
sede, no el extracto. Por eso los dos `.js` quedan `PRESERVAR_APP` con `autoridad_actual = NO`.

---

## 7. Hallazgos que se llevan al bloque siguiente

1. **La fecha de carpeta no es metadata, es una etiqueta.** Dos archivos divergentes del mismo par de
   carpetas quedaron invertidos en la misma dirección. Se decide por contenido, coherencia con la
   evidencia e historial de `git`.
2. **Un hash "no localizado" puede estar fuera del alcance del barrido.** `2c99db28` nunca estuvo
   perdido: vivía en `Workflows/`, fuera del alcance de la matriz. Un barrido acotado produce
   ausencias que no son inexistencias.
3. **El commit que prepara un bloque puede invalidar los números de su propio kickoff.** `b058de4`
   cerró H1, emitió el kickoff de H3 y en el mismo commit agregó 10 archivos y sustituyó la sede
   canónica del A07. Revalidar contra el HEAD real es obligatorio, no ceremonial.
4. **Declarar siempre el algoritmo de hash.** Los kickoffs previos citaban MD5 donde otros documentos
   citaban SHA-256. La v5 §8 declara ambos, completos, para los dos runsheets.
5. **La sede canónica del A07 ya está sustituida.** La consolidación no debe volver a sustituirla.

**No se acuñan `D-HR-*` ni `L-HR-*` en H3.** Corresponden a la consolidación canónica v1.13.0.

---

## 8. Alcance negativo de H3

No se tocó, ni se propuso tocar: el canónico `6B_SCHEMA_SQL.md` · el bootstrap
`bootstrap_entorno_nuevo_v1.12.0/` · los satélites (`DECISIONES_NO_REABRIR.md`,
`Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`, `Pendiente_pre_produccion.md`, `CLAUDE.md`,
`README.md`) · la sede canónica del A07 · la lógica del A07, que sigue congelada · la v3 · la v4 ·
ningún kickoff histórico · TEST · OPS · Supabase · n8n · git (sin commit, sin push).

Tampoco se movió ni se borró ningún archivo: los 7 duplicados, los 2 runsheets en colisión y los 3
archivos de contaminación **siguen exactamente donde estaban**, porque hay documentos históricos que
citan esas rutas.

---

## 9. Punto exacto de frenado

H3 **frena acá**. La v5 está emitida sin filas abiertas y este cierre está escrito, con canónico,
bootstrap, satélites y sede del A07 intactos.

**Siguiente paso, de Franco:**

```
1. auditar la v5 y este cierre
2. correr el verificador:
     python3 "Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/A07 en paridad y sanitizado/VERIFICADOR_H3_v5.py" --repo .
   -> debe dar exit 0
3. commitear las 3 altas
```

**Recién después** se emite `KICKOFF_CONSOLIDACION_CANONICA_v1_13_0.md`, en conversación separada.

Español rioplatense con voseo. Claude diseña, inspecciona, valida y genera artefactos. **Franco
ejecuta todas las escrituras y git.**
