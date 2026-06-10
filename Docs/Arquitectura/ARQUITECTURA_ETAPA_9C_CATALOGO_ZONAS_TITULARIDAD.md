# ARQUITECTURA_ETAPA_9C_CATALOGO_ZONAS_TITULARIDAD.md — Catálogo enriquecido, zonas y titularidad (Carril B)

**Etapa:** 9C — Cimientos del catálogo de la contabilidad interna / **Carril B** (primera sub-etapa de diseño de schema).
**Estado:** ✅ **Diseño conceptual de 9C — APROBADO por Franco.** No es cierre formal de 9C ni de Carril B; no propaga satélites, no toca el canónico, no toca OPS.
**Tipo:** Diseño conceptual previo al schema. **Sin SQL, sin DDL, sin nombres definitivos de tabla, sin funciones, sin policies, sin grants, sin workflows, sin implementación.**
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (NO se modifica en este documento).
**Entorno:** ninguno (diseño conceptual). Cuando haya implementación: **TEST primero**; **OPS solo con aprobación explícita y dentro de la única promoción coordinada de todo el Carril B** (junto al helper `public.abortar_si_falla(jsonb)` de 9B, hoy solo en TEST).
**Depende de:** `ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md` (v0.8, base conceptual aprobada), `9A_DIAGNOSTICO_INGRESOS.md` (cerrado), `9B_CIERRE.md` (cerrado, validado en TEST).
**Autores:** Franco (titular) + Claude (arquitecto).
**Historial:** v1.0 — primer documento formal de 9C; consolida las cuatro decisiones marco P1–P4 y las decisiones propias de 9C.

> Este documento convierte el encuadre conceptual de 9C en **decisiones numeradas y revisables de una sola lectura**.
> Define los **insumos estáticos** de la matriz dinámica (catálogo de cabañas enriquecido, zonas, titularidad).
> **No** propone tablas ni SQL, **no** diseña activación por rango (9D), matriz (9E), gasto rediseñado (9F) ni cascada (9G).
> **No** actualiza el canónico ni los satélites, **no** toca OPS.

---

## 0. Propósito y alcance

9C define **lo estático** de lo que después consume la matriz dinámica de participación (§5.2 del conceptual): el catálogo de cabañas enriquecido, las zonas y su pertenencia, y el modo de leer el beneficiario de cada cabaña.

**Entra:** valor relativo, beneficiario económico, pertenencia a zona, catálogo de zonas, punto único de resolución de titularidad, regla de altas futuras (cabañas y zonas).

**No entra (sub-etapas posteriores):** activación operativa por rango (9D), matriz derivada (9E), entidad de gasto rediseñada con clases A/C/D/E (9F), cascada de liquidación read-only de 11 pasos (9G), capas complementarias y persistencia de liquidaciones/saldados (9H), fiscal/AFIP/ARCA/IVA (9I, fuera del MVP).

**Restricción transversal (heredada):** no mezclar contabilidad operativa interna con fiscal/legal. AFIP/ARCA/IVA fuera del MVP.

> **Nota de nombres:** todos los nombres de entidades de este documento son **conceptuales y no definitivos** (ej. *"cabaña enriquecida"*, *"catálogo de zonas"*, *"pertenencia cabaña↔zona"*, *"punto único de resolución de titularidad"*). El schema fija los nombres reales en la etapa de SQL, con sus propias compuertas.

---

## 1. Decisiones marco del Carril B (P1–P4)

Estas cuatro decisiones se tomaron en el *gate* previo a abrir 9C. Son **transversales** a todo el Carril B; se registran acá por ser este el primer documento formal de la fase de diseño de schema. Cada una indica **dónde aterriza** y dónde se elaborará en detalle (sin re-decidirse).

- **D-9C-01 (P1) — Titularidad estable en el MVP, con punto único de resolución de titularidad para no impedir versionarla por rango más adelante. Sin historial de titularidad ahora.** *Aterriza en 9C (§3 y §5).*
- **D-9C-02 (P2) — Centavo residual del reparto: al socio de mayor participación del período; en caso de empate, a Rodrigo (Murillo). Regla determinística; el monto es irrelevante, importa que sea reproducible.** *Aterriza en 9E/9G (redondeo del paso 9 de la cascada). Se implementa, no se re-decide, en esas sub-etapas.*
- **D-9C-03 (P3) — Horas de socio como gasto valorizado manualmente desde el día uno: etiqueta `horas de trabajo`, el socio que trabajó como pagador/desembolso, cantidad/detalle en el comentario, monto total cargado a mano; la clase (A/C/D/E) determina la incidencia. Sin motor automático de valor/hora en el MVP (una tarifa sugerida/configurable por workflow queda para más adelante, sin obligación).** *Aterriza en 9F. Consecuencia para 9F: el pagador de un gasto debe poder ser un **socio**, no solo "caja". Se elabora en 9F.*
- **D-9C-04 (P4) — Activación por rango `[)` en el modelo, política mensual en el MVP: para participar en la matriz de un mes, la cabaña debe **cubrir el mes completo**. Activaciones parciales / semanas / fines de semana quedan latentes o se resuelven con ajustes manuales. Pro-rata diario diferido.** *Aterriza en 9D/9E.*

---

## 2. Cabaña enriquecida

Se **enriquecen las 5 cabañas existentes** (no son altas): se les agregan atributos conceptuales sobre los que ya tienen.

- **valor relativo** — estable. El **tipo sugiere** un default (grande = 100, chica = 78), pero **no lo impone**: una cabaña puede acordarse con otro valor (§2.1 del conceptual).
- **beneficiario económico** → un socio. Estable. **Se lee únicamente vía el punto único de resolución de titularidad** (§3), nunca por *join* directo desde la matriz o la cascada.
- **pertenencia a zona** — vive en la relación de pertenencia (§4), **no** como columna de la cabaña.

**Decisiones:**

- **D-9C-05 — Valor relativo estable a nivel cabaña.** El `tipo` sugiere el default; no lo impone. Una cabaña nueva puede tener un valor distinto al de su tipo.
- **D-9C-06 — Beneficiario económico = atributo estable de la cabaña, leído SIEMPRE mediante el punto único de resolución de titularidad (nunca por *join* directo).** Sin tabla de rangos ni historial en el MVP. *(Es el aterrizaje de D-9C-01/P1 en 9C; ver ruta de migración en §5.)*
- **D-9C-10 — No sobrecargar `cabanas.activa` (flag global existente) como activación operativa.** La activación operativa por rango (9D) es un **eje independiente** (§3 del conceptual: bloqueo ≠ activación ≠ titularidad). El `tipo` puede **sugerir** la zona default al sembrar, pero la pertenencia se **setea explícitamente**; no se deriva de `tipo`.

> *Columnas vs. satélite (decisión de schema, no de 9C):* siendo `valor_relativo` y `beneficiario` atributos estables 1:1 con la cabaña, son naturales como atributos directos; la pertenencia a zona es muchos-a-muchos y va en relación aparte sí o sí. La forma exacta se fija en el diseño de schema de 9C.

---

## 3. Zonas / módulos

- **Catálogo plano de zonas nombradas.** **Sin jerarquía** (nada de zonas de zonas). **Módulo = zona** (un solo concepto).
- **La zona no tiene bolsillo ni beneficiario:** es un **intermediario de distribución** (§2.2 del conceptual). Un gasto de zona (Clase D) se reparte entre las cabañas **activas** de la zona en el período y baja a sus dueños.
- **El pool operativo NO es una zona sembrada:** es la "zona universal" = todas las activas del período (§2.3). Se **deriva** en 9D/9E, no se mantiene a mano.

**Decisiones:**

- **D-9C-07 — Zona = catálogo plano nombrado, sin jerarquía, sin bolsillo ni beneficiario; intermediario de distribución.**
- **D-9C-08 — Pertenencia cabaña↔zona = muchos-a-muchos.** Una cabaña pertenece a su zona principal (grandes o chicas) y eventualmente a otras zonas físicas (jardín, muelle, pasarela, parrillas, etc.). Lo exigen los gastos Clase D sobre subconjuntos solapados (ej. "jardín sector chicas", "pasarela de un sector").
- **D-9C-09 — Seed MVP de zonas: solo `grandes` y `chicas`.** Las zonas físicas (muelle, pasarela, jardín general, parrillas, etc.) se definen **on-demand**, cuando aparezca el primer gasto Clase D o reporte que realmente las necesite. No se inventan zonas que todavía no se sabe si se usarán.

---

## 4. Punto único de resolución de titularidad (seam)

**Concepto:** *"beneficiario vigente de la cabaña X (a una fecha F)"*. En el MVP es **trivial** — devuelve un beneficiario estable y la fecha se ignora. La **disciplina** es que la matriz y la cascada **lean siempre por este único punto**, no el atributo directo desde muchos lugares.

**Por qué importa:** si en el futuro hay titularidad por período, se cambia **solo** la implementación de esa resolución —se agrega el manejo por rango— **sin rehacer la matriz ni la cascada**. Hoy no construye historial; mañana lo habilita en un único lugar.

**Decisión:**

- **D-9C-11 — Punto único de resolución de titularidad confirmado: atributo `beneficiario` estable + resolución nombrada que hoy devuelve ese atributo.** Sin tabla de rangos / sin historial en el MVP.
  - **Ruta de migración futura** (si/cuando haya que versionar, p. ej. un traspaso socio→socio): crear la relación con rangos `[)` *(cabaña × socio × rango)*, backfill desde el atributo actual con **rango abierto**, **repuntar** la implementación de la resolución a la nueva relación, retirar el atributo. **Cero cambios en los consumidores** (matriz, cascada, reportes) — ése es el valor del seam.

> **Sobre "reescribir historia":** como las liquidaciones son read-only y **no se persisten todavía**, cambiar un atributo solo afecta **re-derivar** meses pasados, lo cual es aceptable para el MVP. La protección fuerte llega con los **snapshots persistidos (9H)**, que congelan los valores usados en cada liquidación. Por eso hoy alcanza con la disciplina de no cambiar atributos retroactivamente sin intención.

---

## 5. Altas futuras de cabañas y zonas (regla general)

El modelo debe soportar **altas futuras**, no por una cabaña/zona específica planificada, sino como capacidad general del diseño.

**Regla conceptual (cabañas):** *cualquier socio puede incorporar una cabaña nueva. Toda cabaña nueva debe tener **beneficiario económico**, **valor relativo propio** y **pertenencia a zona**; esa zona puede ser una **existente** (p. ej. `chicas`) o una **nueva**, según corresponda. Si la cabaña se activa operativamente para el período, entra al pool y su valor relativo modifica automáticamente la matriz dinámica (§5.2).*

Ejemplos **equivalentes y meramente ilustrativos** (ninguno es un alta definida ni una decisión de negocio):

- Remo podría agregar una cabaña *"Domo"* con valor relativo 120;
- Franco podría agregar otra con valor relativo 78 o 100;
- Rodrigo podría agregar una cabaña *"Argentina"* con valor relativo 50;
- o cualquier otro caso acordado.

> **Aclaración explícita:** *"Argentina"* es **solo un ejemplo ilustrativo** para mostrar que una cabaña nueva puede tener un valor relativo distinto (p. ej. 50). **No** es un alta próxima, **no** está planificada y **no** es necesariamente de Rodrigo. Lo importante no es el nombre, sino que el modelo soporte altas por **cualquier** socio, con beneficiario económico, valor relativo propio y pertenencia a zona.

**Decisiones:**

- **D-9C-12 — Soporte de altas futuras de cabañas por cualquier socio,** cada una con **beneficiario económico**, **valor relativo propio** y **pertenencia a zona** (existente o nueva, según corresponda); al activarse operativamente para el período, entra al pool y su valor relativo se suma al total activo, recalculando la matriz automáticamente. *"Argentina"* (y *"Domo"*, etc.) son solo ejemplos ilustrativos.
- **D-9C-13 — Soporte de creación de nuevas zonas cuando exista una necesidad real (no especulativa):** (i) dar **alcance a un gasto Clase D**, **o** (ii) la **pertenencia de una cabaña nueva** que no encaja en una zona existente. No se crean zonas por anticipado sin una de esas necesidades.

---

## 6. Datos iniciales (seed conceptual de 9C)

Enriquece las cabañas existentes. Los beneficiarios mapean a los tres socios ya sembrados (resuelven a `id_socio` en la etapa de schema). Fuente: §2.4 del conceptual.

| Cabaña | Tipo | Valor relativo | Beneficiario | Zona MVP |
|---|---|---|---|---|
| Arrebol | grande | 100 | Franco | grandes |
| Madre Selva | grande | 100 | Rodrigo | grandes |
| Bamboo | grande | 100 | Remo | grandes |
| Guatemala | chica | 78 | Franco | chicas |
| Tokio | chica | 78 | Remo | chicas |

**Zonas a sembrar ahora:** `grandes`, `chicas` (D-9C-09). **Zonas físicas:** ninguna todavía (on-demand).

---

## 7. Lo que 9C deja servido para 9D–9G (forward pointers)

- **9D (activación por rango):** cuelga rangos de activación `[)` del catálogo enriquecido; política mensual / "cubre el mes completo" (D-9C-04).
- **9E (matriz derivada):** lee los cuatro insumos de §5.2 — catálogo + valor relativo + activación (9D) + titularidad (vía punto único de resolución). Acá aterriza el centavo residual (D-9C-02). La matriz **se deriva, no se guarda**.
- **9F (gasto rediseñado):** lee la **pertenencia a zona** para Clase D y la **cabaña** para Clase E; la incidencia resuelve a socio por el **mismo punto único de resolución de titularidad**. *Nota heredada de D-9C-03:* el **pagador de un gasto debe poder ser un socio**, no solo "caja" (necesario para horas y para desembolsos personales).
- **9G (cascada read-only):** compone ingreso (lectura de `pagos`, sin cambio estructural) + gasto (9F) + matriz (9E); reportes de overrides y 5%-vs-monotributo; saldos internos **incidencia − desembolso** derivados, con a lo sumo estado básico "saldado / no saldado".
- **Altas de cabañas (D-9C-12):** una cabaña nueva aporta a la **matriz (9E)** vía su **valor relativo + activación**; su **pertenencia a zona** (obligatoria en el alta) alimenta el **alcance de Clase D (9F)**, no los pesos de la matriz. Por eso la zona es obligatoria: ninguna cabaña queda fuera del catálogo de zonas, y un gasto Clase D siempre tiene a quién repartirse.

---

## 8. Riesgos de sobrediseño (a evitar en 9C)

- **Zona jerárquica** (zonas de zonas) — basta plana.
- **Colapsar zona con `tipo`** — son ejes distintos; la pertenencia se setea, no se deriva del tipo.
- **Sobrecargar `cabanas.activa`** como activación operativa — viola la independencia de ejes (§3 del conceptual).
- **Construir ya la tabla de rangos de titularidad "para dejarla lista"** — es historial encubierto; va contra "sin historial ahora" (D-9C-11).
- **Ponerle beneficiario o caja a la zona** — es intermediario, no bolsillo.
- **Inventar zonas físicas que todavía no se usan** (D-9C-09).
- **Sembrar el pool como zona** — el pool se deriva (§3).

---

## 9. Qué NO implementar todavía

Nada de: SQL, DDL, nombres definitivos de tabla, funciones, policies, grants, bloques transaccionales, migraciones, workflows n8n, bump del canónico, OPS. Además, fuera de 9C: activación por rango (9D), matriz (9E), gasto rediseñado (9F), cascada (9G); tabla de rangos de titularidad / historial; motor de valor/hora; persistencia de matriz o de liquidaciones; saldado efectivo de deudas entre socios (solo estado/reporting básico, más adelante); conversión de monedas como lógica contable; pro-rata diario de la matriz; capa fiscal/ARCA. El **número** del % operativo (25→12,5) y su base siguen sujetos a la conversación de Franco con sus socios; la **cascada no se congela como inmutable** hasta esa confirmación.

---

## 10. Glosario mínimo

- **Punto único de resolución de titularidad (seam):** la **única** lectura nombrada que responde *"beneficiario vigente de la cabaña X"*. Hoy devuelve un beneficiario estable; mañana puede manejar rangos sin que matriz/cascada se enteren. No es una abstracción decorativa: es la **disciplina** de no leer el beneficiario desde muchos lugares.
- **Intermediario de distribución (zona):** agrupación nombrada que **reparte** un gasto entre sus cabañas activas y baja a sus dueños. No acumula plata ni tiene dueño.
- **Pool operativo:** "zona universal" = todas las cabañas activas del período. **Derivado**, no sembrado.
- **Valor relativo:** peso de una cabaña en la matriz. Por cabaña (no rígido por tipo). El tipo solo sugiere un default.

---

## 11. Decisiones de 9C — índice consolidado

| ID | Tipo | Decisión (resumen) | Aterriza |
|---|---|---|---|
| **D-9C-01** | Marco (P1) | Titularidad estable + punto único de resolución; sin historial | 9C |
| **D-9C-02** | Marco (P2) | Residual al de mayor participación; empate → Rodrigo | 9E/9G |
| **D-9C-03** | Marco (P3) | Horas = gasto valorizado manual; pagador = socio; sin motor | 9F |
| **D-9C-04** | Marco (P4) | Activación por rango, política mensual, "cubre el mes"; pro-rata diferido | 9D/9E |
| **D-9C-05** | 9C | Valor relativo estable; tipo sugiere, no impone | 9C |
| **D-9C-06** | 9C | Beneficiario = atributo estable, leído solo vía resolución única | 9C |
| **D-9C-07** | 9C | Zona = catálogo plano, sin jerarquía, sin bolsillo, intermediario | 9C |
| **D-9C-08** | 9C | Pertenencia cabaña↔zona muchos-a-muchos | 9C |
| **D-9C-09** | 9C | Seed zonas: solo grandes y chicas; físicas on-demand | 9C |
| **D-9C-10** | 9C | No sobrecargar `cabanas.activa` como activación; ejes independientes | 9C |
| **D-9C-11** | 9C | Punto único de resolución confirmado; sin rangos/historial; ruta de migración | 9C |
| **D-9C-12** | 9C | Altas de cabañas por cualquier socio: beneficiario + valor relativo + zona (existente o nueva); "Argentina" solo ilustrativo | 9C |
| **D-9C-13** | 9C | Crear nuevas zonas solo ante necesidad real: alcance Clase D **o** pertenencia de cabaña nueva | 9C |

---

## 12. Próximos pasos (fuera de este documento conceptual)

1. **Aprobación de Franco** de este 9C conceptual (✅ dada).
2. **Diseño de schema de 9C en bloques** — ya cae en la etapa de SQL/DDL, con sus propias compuertas (TEST primero, aprobación explícita por bloque). Define cómo se materializan: cabaña enriquecida, catálogo de zonas, pertenencia M2M, punto único de resolución de titularidad. **Todavía no.**
3. Recién después: **9D (activación por rango)** → **9E (matriz derivada read-only)** → **9F (gasto rediseñado)** → **9G (cascada read-only)**.
4. **Promoción coordinada a OPS** de todo el Carril B (con el helper `abortar_si_falla` de 9B y el conjunto completo) en **una sola** operación, con **bump único** del canónico, **solo con aprobación explícita**.

---

**Fin del documento 9C conceptual v1.0 — APROBADO.** Sin SQL, sin schema, sin nombres definitivos, sin workflows, sin canónico, sin OPS. Listo para la etapa de diseño de schema de 9C.
