# KICKOFF — H3: CIERRE DE INVENTARIO DEL CARRIL

**Carril:** Motor de Horarios · **Bloque:** `H3-cierre-inventario`
**Predecesor:** `H1` — **cierre técnico y documental definitivo** (`H1_CIERRE_POLITICA_DURABLE_A07.md`)
**Sucesor:** `KICKOFF_CONSOLIDACION_CANONICA_v1_13_0.md` — **se emite recién tras el cierre real de H3**
**Documento autocontenido:** una conversación nueva debe poder arrancar solo con esto + el repo.

> **Un bloque por conversación.** Este kickoff cubre **exclusivamente H3**. La consolidación canónica v1.13.0 es un bloque separado con su propio kickoff. No mezclar.

---

## 0. Apertura — clone fresco y gate

**Antes de tocar nada, cloná fresco. El repo es la autoridad, no la memoria ni copias locales.**

```
git clone https://github.com/francogg89-ai/vita-delta-reservas.git
cd vita-delta-reservas
git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD   # debe dar exit 0
git log --oneline -1
git status --porcelain    # debe salir vacío
```

**Estado verificado al emitir este kickoff (2026-07-18):**

- **HEAD:** `a2a5893` — `fix(portal): corregir H-1 y H-2 del historico contable`, rama `main`, árbol limpio.
- **Gate D2:** exit **0**.
- Commits posteriores a D2: `d6fc392`, `8dd1235`, `a2a5893`.

Si el HEAD cambió, **re-verificá toda la §2 antes de operar**. Los números de este kickoff son medidos, no heredados.

---

## 1. Alcance de H3 — exactamente esto y nada más

```
1. confirmar la matriz autoritativa
2. crear una nueva matriz v5 de cierre, DERIVADA de v4
3. mantener v3 y v4 como evidencia histórica, SIN modificarlas
4. cerrar la fila 70 (A07)
5. registrar la ruta real de 2c99db28 mediante la nueva matriz / addendum,
   SIN reescribir kickoffs históricos
6. clasificar ambos HORARIOS_B2_RUNSHEET
7. documentar la contaminación de otros carriles
8. dejar H3 SIN filas abiertas
9. emitir el cierre H3
```

**HARD STOP ahí.**

**Fuera de alcance de H3 — no tocar durante este bloque:**

- ❌ canónico (`6B_SCHEMA_SQL.md`)
- ❌ bootstrap (`bootstrap_entorno_nuevo_v1.12.0/`)
- ❌ satélites (`Docs/Operacional/`, `CLAUDE.md`, `README.md`)
- ❌ sede canónica del A07 (`Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json`)
- ❌ acuñación de `D-HR-*` / `L-HR-*` (va en la consolidación)
- ❌ TEST, OPS, Supabase, n8n, A07 vivo
- ❌ commits, push

---

## 2. Hallazgos medidos que H3 debe resolver

Todos medidos contra HEAD `a2a5893`.

### 2.1 🔴 La matriz H3 está duplicada y con las versiones invertidas

| Ruta | Versión declarada | SHA-256 | Bytes | `CONSOLIDAR` | `PENDIENTE_D2` | `PENDIENTE_H1` |
|---|---|---|---|---|---|---|
| `…/13-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | **v4 — post-D2** | `68babb23…b093` | 37 715 | **12** | 0 | 1 |
| `…/14-07-2026/H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md` | **v3 — corregida** | `51cc2252…ca7c` | 35 910 | 8 | 4 | 1 |

**La carpeta más reciente (14-07) contiene la versión más vieja (v3).** La **v4** es la coherente con la evidencia de D2 y con el kickoff anterior §5 (autoridad `SI` 12, `CONSOLIDAR` 12, sin `PENDIENTE_D2`).

**Acción:** confirmar v4 como autoritativa, derivar **v5** de ella, y dejar v3 y v4 intactas como evidencia histórica.

### 2.2 🟠 La duplicación no es solo de la matriz

Entre `13-07-2026/` y `14-07-2026/` hay **7 archivos repetidos**. De ellos, **2 divergen**:

| Archivo | 13-07 | 14-07 | Estado |
|---|---|---|---|
| `D1_DECISION_FIDELIDAD_FUNCTIONDEF.md` | 10 064 B | 10 064 B | idénticos |
| `D1_RESULTADOS_TEST_Y_FREEZE_B1_3.md` | 10 605 B | 10 605 B | idénticos |
| `D2_Q4_TRIGGER_OV_GUARD.sql` | 5 798 B | 5 798 B | idénticos |
| `D2_Q7_VEREDICTO.sql` | 14 571 B | 14 571 B | idénticos |
| `D2_VALIDACION_HARNESS_PG17.txt` | 32 196 B | 32 196 B | idénticos |
| **`D2_RUNBOOK.md`** | 12 808 B | 12 864 B | **DIVERGEN** |
| **`H3_MATRIZ_CASCADE_REPO_107_ARCHIVOS.md`** | 37 715 B | 35 910 B | **DIVERGEN** |

Solo en `14-07`: `KICKOFF_B1_3_CONTINUACION_POST_D2.md`.

**Acción:** clasificar los 7 duplicados en v5 (los 5 idénticos y los 2 divergentes reciben tratamiento distinto). **No borrar ni mover nada.**

### 2.3 🔴 El denominador de la matriz cambió: 107 → 147

| Referencia | Archivos versionados bajo `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/` |
|---|---|
| `07fea85` (HEAD contra el que se hizo la matriz) | **107** |
| `82f28df` (cierre D2) | 146 |
| `a2a5893` (HEAD actual) | **147** |

**40 archivos agregados, 0 eliminados** desde `07fea85`. Los agregados son los artefactos de D1/D2 (13-07 y 14-07) más el kickoff post-D2.

**Decisión requerida en H3:** si la **v5** congela el denominador histórico de **107** (declarando el HEAD de corte `07fea85`) o lo **extiende a los 147 vigentes**. El título del archivo dice "107 ARCHIVOS": si se extiende, el nombre debe reflejarlo.

### 2.4 🟢 El hash "no localizado" `2c99db28…` SÍ está en el repo

```
Workflows/n8n/Supabase/portal-a07-crear-reserva__TEMPLATE.json
```

Quedó fuera del barrido previo porque el alcance de H3 es `Docs/Bitacora/CARRIL_MOTOR_DE_HORARIOS/` y ese archivo vive fuera.

**Acción:** registrar la ruta real **en la v5 o en un addendum**. **No reescribir los kickoffs históricos** — la afirmación "NO LOCALIZADO" queda como evidencia de su momento y se corrige por documento nuevo, no por edición retroactiva.

### 2.5 🟡 Fila 70 — desbloqueada por H1

| Campo | Valor actual en v4 |
|---|---|
| Ruta | `10-07-2026/portal-a07-crear-reserva__TEMPLATE.PATCHED.json` |
| `autoridad_actual` | `PENDIENTE_H1` |
| `accion_v1_13` | `BLOQUEADO_H1` |
| Fingerprint | `3188bceb777b` |

Era la **única fila abierta** de la v4. H1 la desbloqueó (política durable definida, procedencia resuelta).

**Acción:** fijar su estado definitivo en v5, coherente con la política de H1 (el archivo es **evidencia histórica**, no la sede canónica).

### 2.6 🟡 Colisión divergente: `HORARIOS_B2_RUNSHEET`

| Archivo | Bytes | MD5 | SHA-256 |
|---|---|---|---|
| `HORARIOS_B2_RUNSHEET (1).md` | 13 129 | `1a152ac9b7c733f2…` | `8497b436780a8eb9…` |
| `HORARIOS_B2_RUNSHEET (2).md` | 15 725 | `e0f1b023d4239439…` | `c87e4a587c48708f…` |

**Nota de trazabilidad:** el kickoff anterior citaba `1a152ac9…` / `e0f1b023…` — son **MD5**, no SHA-256. Coinciden exactamente con lo medido. Se documentan ambos algoritmos para evitar confusión futura.

**Acción:** clasificar ambos (el criterio previo del carril era `ARCHIVAR` los dos y regenerar el runsheet desde el estado congelado, ya en la consolidación). **No elegir por tamaño.**

### 2.7 🟡 Contaminación de otros carriles — documentar, **NO mover**

| Archivo | Bytes | Carril real |
|---|---|---|
| `…/11-07-2026/CC_L3_BLOQUE0_CIERRE.md` | 15 236 | Cuenta Corriente |
| `…/11-07-2026/CC_L3_BLOQUE0_EVIDENCIAS_EJECUCION_TEST.md` | 13 880 | Cuenta Corriente |
| `…/CIERRE_UI_RETIRO_SALDO_FRONTEND.md` | 16 757 | Frontend |

**Acción:** documentarlos en v5 como contaminación conocida. **No moverlos** (mover rompería rutas citadas en documentos históricos).

---

## 3. Orden de trabajo sugerido

```
paso 1  clone fresco + gate + reportar HEAD real y árbol limpio
paso 2  confirmar matriz autoritativa (v4) por CONTENIDO y coherencia con D2,
        NO por fecha de carpeta. Documentar el criterio.
paso 3  decidir el denominador de v5 (107 congelado vs 147 vigentes) -> aprobación de Franco
paso 4  derivar v5 de v4: fila 70 cerrada + ruta real de 2c99db28 + duplicados
        clasificados + runsheets clasificados + contaminación documentada
paso 5  verificar que v5 no tenga filas abiertas (conteo sobre filas de datos, no grep global)
paso 6  emitir el cierre H3
HARD STOP -> Franco commitea. Recién después se emite el kickoff de consolidación.
```

**Regla de conteo:** contar **solo filas de datos** de la tabla. Un `grep` sobre todo el documento cuenta también los diccionarios y las notas de cambios, que contienen los mismos tokens.

---

## 4. Criterios de DONE de H3

```
clone fresco + gate 82f28df -> exit 0
matriz autoritativa confirmada por contenido, con criterio documentado
v5 creada, DERIVADA de v4
v3 y v4 intactas (verificar sha256 sin cambios)
denominador de v5 decidido y declarado explícitamente (con HEAD de corte)
fila 70 cerrada con estado definitivo
ruta real de 2c99db28 registrada en v5/addendum
kickoffs históricos NO reescritos
7 duplicados 13-07/14-07 clasificados (5 idénticos + 2 divergentes)
ambos HORARIOS_B2_RUNSHEET clasificados
3 archivos de contaminación documentados, NO movidos
v5 SIN filas abiertas
cierre H3 emitido
canónico / bootstrap / satélites / sede A07: INTACTOS
```

---

## 5. Riesgos y falsos verdes conocidos

- **Elegir la matriz por fecha de carpeta** → elegirías la v3. Elegir por **contenido**.
- **Contar filas con `grep` global** → los diccionarios y notas contienen los mismos tokens. Contar solo filas de datos.
- **Asumir el denominador 107** → hoy hay 147 archivos versionados. Declarar el HEAD de corte.
- **Confundir algoritmos de hash** → el kickoff anterior citaba MD5 donde otros documentos citan SHA-256. Declarar siempre cuál se usa.
- **Reescribir evidencia histórica** para "corregir" un dato viejo → prohibido. Se corrige por documento nuevo.
- **Mover archivos de contaminación** → rompe rutas citadas en documentos históricos. Solo documentar.
- **Tocar la sede del A07 en H3** → fuera de alcance. La sustitución la hace Franco en la consolidación, sin rediseñar la lógica.

---

## 6. Hard stops (permanentes)

Claude **no**: ejecuta TEST · toca OPS · modifica canónico, bootstrap o satélites · importa workflows en n8n · **modifica el A07** (su lógica está congelada) · toca la sede canónica del A07 durante H3 · hace commits · hace push.
**Franco ejecuta todas las escrituras y git.** Secuencia invariante: **diagnóstico → aprobación explícita → artefactos → Franco ejecuta → verificación → cierre formal.** Español rioplatense con voseo, siempre.

---

## 7. Archivos a subir a la conversación nueva

**Obligatorios**

```
H1_CIERRE_POLITICA_DURABLE_A07.md    (cierre técnico y documental definitivo)
este kickoff
```

Todo lo demás sale del **clone fresco**: ambas matrices (v3 y v4), los artefactos de D1/D2, y los archivos citados en §2.

**No subir el RAW del A07.** Custodia privada local de Franco; solo hashes, tamaños y copias sanitizadas.

---

## 8. Mensaje inicial para la conversación nueva

> Copiá y pegá esto para abrir el bloque:

```
Claude: arrancamos el bloque H3 (cierre de inventario del Carril Motor de Horarios).
Contexto completo en KICKOFF_H3_CIERRE_INVENTARIO.md y H1_CIERRE_POLITICA_DURABLE_A07.md.

Estado: H1 con cierre técnico y documental definitivo. Era el único bloqueante integral. D1 y D2 ya cerraron el
inventario DB del carril (11+7 objetos y 3 triggers congelados con doble
fingerprint fp_raw/fp_lf, opción C, PG 17.x).

ALCANCE DE ESTE BLOQUE: solo H3. La consolidación canónica v1.13.0 es un bloque
aparte con su propio kickoff, que se emite recién cuando H3 cierre. No mezclar.

Primero, sin generar nada: cloná fresco y verificá el gate.
  git merge-base --is-ancestor 82f28dfdab4acbb5ae6a4391a80e657d871765d5 HEAD
Debe dar exit 0. Reportame HEAD real y si el árbol está limpio.

Después, en este orden y sin escribir todavía:
1) Confirmá la matriz autoritativa. Hay dos copias divergentes con las versiones
   invertidas: 13-07 tiene la v4 (post-D2) y 14-07 tiene la v3. Decidí por
   CONTENIDO y coherencia con D2, no por fecha de carpeta, y documentá el criterio.
2) Proponeme el denominador de la v5: el histórico de 107 archivos congelado
   contra HEAD 07fea85, o los 147 vigentes. Necesito aprobar esto antes de seguir.
3) Proponeme el estado definitivo de la fila 70 (A07), ya desbloqueada por H1.
4) Proponeme cómo registrar la ruta real de 2c99db28 sin reescribir kickoffs
   históricos.

v3 y v4 no se modifican: son evidencia histórica. No toques canónico, bootstrap,
satélites ni la sede del A07 durante H3. Hard stop antes de cualquier escritura.
```

---

## 9. Punto exacto de frenado

H3 **frena** cuando la **v5** está emitida sin filas abiertas y el **cierre H3** escrito, con canónico, bootstrap, satélites y sede del A07 **intactos**. Franco commitea. **Recién entonces** se emite `KICKOFF_CONSOLIDACION_CANONICA_v1_13_0.md`, en conversación separada.
