# ARQUITECTURA_ETAPA_9_CARRIL_B_CONCEPTUAL.md — Contabilidad global Vita Delta

**Etapa:** 9 — Contabilidad operativa interna / **Carril B** (políticas de liquidación, reparto e imputación)
**Estado:** ✅ Documento conceptual **v0.8 — APROBADO como base conceptual** por Franco (con 3 ajustes menores incorporados: Clase D escalable, horas de socio según clase/destino, frase de desactivación precisada). Base para la futura etapa de diseño de schema. **NO es diseño de schema.**
**Tipo:** Mapa conceptual / lógica de negocio. **Sin SQL, sin schema, sin nombres de tabla definitivos, sin funciones, sin workflows, sin implementación.**
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3` (NO se modifica en este documento)
**Entorno:** ninguno — esto es diseño conceptual. Cuando haya implementación: TEST primero, OPS solo con aprobación explícita.
**Depende de:** `9A_DIAGNOSTICO_INGRESOS.md` (cerrado), `9B_CIERRE.md` (cerrado, validado en TEST), `ARQUITECTURA_ETAPA_9B_COBRANZA_POSTERIOR.md`.
**Autores:** Franco (titular) + Claude (arquitecto)
**Historial de versiones conceptuales:** v0.3 → v0.4 (tres ejes de estado) → v0.5 (cascada en capas) → v0.6 (fondo fiscal, luego descartado) → v0.7 (tabla de clasificación) → **v0.8 (consolidado y APROBADO: alcance derivado de clase + override trazable + publicidad + 3 ajustes finales)**.

> Este documento consolida la lógica conceptual de la contabilidad global. **No propone tablas,
> no genera SQL, no actualiza el canónico ni los satélites, no toca OPS.** Su único objetivo es
> dejar la lógica de negocio cerrada y revisable de una sola lectura, como base para una etapa
> posterior de diseño de schema (que tendrá sus propias restricciones y aprobaciones).

---

## 0. Propósito y alcance

Diseñar la **lógica conceptual** de cómo Vita Delta:

1. Imputa **ingresos** y **gastos** a cabañas y beneficiarios.
2. Liquida el **resultado** del período en capas ordenadas (cascada).
3. Reparte entre los socios según una **matriz dinámica** de cabañas activas.

**Fuera de alcance de este documento (conceptual):** schema, SQL, funciones, workflows, formularios, bump del canónico, promoción a OPS, contabilidad fiscal/legal real (ARCA/IVA/declaraciones), motor de valor/hora, conversión de monedas.

**Restricción transversal:** no mezclar **contabilidad operativa interna** (este documento) con **contabilidad fiscal/legal**. El único punto de contacto sancionado es la línea de gasto fiscal/administrativo (monotributo) dentro de la cascada — y aun así, como una línea de gasto más, sin lógica fiscal embebida.

---

## 1. Esqueleto conceptual: los tres ejes de un gasto + dos niveles de atadura

Toda la contabilidad se apoya en describir cada gasto con **tres ejes independientes**:

1. **Clase (A / C / D / E)** → define el **momento de la cascada** en que entra **y su alcance** (van pegados, ver §6).
2. **Regla de imputación** → con qué pesos se reparte dentro de su alcance.
3. **Desembolso vs. incidencia** → quién puso la plata (o el trabajo) ≠ quién lo soporta finalmente.

Y en **dos niveles de atadura**:

- La **cabaña** es la unidad de **imputación** (el casillero).
- El **socio** es la unidad de **incidencia final** (el bolsillo), alcanzado vía **titularidad**.

**Principio rector:** *todo gasto, sea cual sea su alcance, termina aterrizando en un socio.* No hay gasto que se quede "en una cabaña" sin un dueño detrás.

**Principio de flexibilidad (§7):** *el sistema sugiere, pero no decide.* La clase tiene una sugerencia por defecto según la etiqueta, pero la elige el operador; un cambio respecto de la sugerida es un **override** trazable.

---

## 2. Cabañas, zonas, pool, titularidad

### 2.1 Cabaña
Activo **permanente** del sistema. Existe siempre, aunque esté desactivada o bloqueada. Atributos conceptuales:
- **tipo** (grande / chica) → sugiere un **valor relativo** por defecto, pero no lo impone.
- **valor relativo** → **a nivel cabaña** (no rígido por tipo). Default sugerido: grande = 100, chica = 78; pero una cabaña nueva podría acordarse con otro valor (ej. 50).
- **beneficiario económico** (= dueño, para el MVP; ver §2.4).
- **estado** según los **tres ejes** independientes (§3).

Es la unidad atómica de imputación y de incidencia.

### 2.2 Zona
Agrupación **nombrada** de cabañas (zona grandes, zona chicas, muelle, jardín, pasarela, sector parrillas, futuras zonas). **"Módulo" = "zona"**: un solo concepto, no se separan.

La zona **no tiene bolsillo propio**: es un **intermediario de distribución**. Un gasto de zona se reparte entre las cabañas de la zona **activas en el período** y baja a sus dueños.

### 2.3 Pool operativo
La **"zona universal"**: todas las cabañas **activas** del período. Su membresía **se deriva** del estado de activación; no se mantiene a mano.

### 2.4 Titularidad / beneficiario económico
Para el **MVP**, *dueño* y *beneficiario económico* se tratan como **lo mismo**. El diseño **no debe impedir** que en el futuro difieran, ni que la titularidad **cambie por período** (traspaso entre socios) — ver Q-F (§9).

**Titularidad y valores actuales (confirmados):**

| Cabaña | Tipo | Valor relativo | Beneficiario económico | Zona |
|---|---|---|---|---|
| Arrebol | grande | 100 | Franco | grandes |
| Madre Selva | grande | 100 | Rodrigo | grandes |
| Bamboo | grande | 100 | Remo | grandes |
| Guatemala | chica | 78 | Franco | chicas |
| Tokio | chica | 78 | Remo | chicas |

---

## 3. Los tres ejes de estado de cabaña (independientes, sin derivación automática)

| Eje | Pregunta que responde | Naturaleza | ¿Existe hoy? |
|---|---|---|---|
| **Bloqueo de calendario** | ¿La cabaña se puede alquilar en estas fechas? | Por rango, operativo | Sí — tabla `bloqueos` (8D) |
| **Activación operativa** | ¿La cabaña participa del **pool económico** del período? | Por rango, nuevo | No |
| **Titularidad patrimonial** | ¿Quién absorbe costos patrimoniales y recibe beneficio? | Estable (revisable) | No |

**Regla:** los tres pueden coincidir, pero **ninguno deriva del otro**. El bloqueo puede ser **señal o ayuda** para decidir la activación, pero la activación **se setea aparte**. (Se revierte explícitamente la hipótesis previa de derivar activación desde el bloqueo `uso_propio`.)

**Ejemplos que muestran la independencia:**
- Bloqueada por mantenimiento, pero con gastos patrimoniales de su dueño → bloqueo ≠ titularidad.
- Bloqueada por uso propio un fin de semana → no participa de beneficios variables de ese rango → activación OFF (coincide con el bloqueo, pero por decisión).
- Desactivada operativamente sin bloqueo (alquilable pero fuera del pool) → activación ≠ bloqueo.

**Regla simplificada de desactivación:** si una cabaña está desactivada en un período, **sale del circuito económico operativo** (no participa de beneficios, ni de gastos operativos variables, ni de gastos de zona operativos salvo decisión manual). **Pero sus gastos patrimoniales propios (clase E) siguen correspondiendo a su beneficiario**, aunque esté desactivada o bloqueada.

**Soporte por rango, operación simple:** el modelo soporta activar/desactivar por **rango** (mes / semana / fin de semana). El **MVP arranca con rangos simples y reportes mensuales**, carga **por SQL controlado** (sin formulario). La precisión fina queda **latente** (admitida por el modelo, no construida).

---

## 4. La cascada de liquidación (11 pasos) — el corazón del modelo

```
 1  Ingresos operativos de alojamiento (señas + saldos confirmados)        [pool]
       │   (tipo IN ('sena','saldo'); el recargo 5% NO entra acá)
 2  − Gastos Clase A (operativos)                                          [pool · ANTES del %]
       │
       ▼
 3  = RESULTADO OPERATIVO BASE
       │
 4  − Porcentaje operativo (hoy 25%, futuro ~12,5%) ─────► sector operativo [LÍNEA DIVISORIA]
       │
       ▼
 5  = SALDO POST-OPERATIVO PARA BENEFICIARIOS
       │
 6  + Recargos 5% cobrados (tipo='extra')                                  [entrada · DESPUÉS del %]
       │
 7  − Gastos Clase C (no operativos de pool)                               [pool · DESPUÉS del %]
       │   mantenimiento general, zona general, infraestructura común,
       │   monotributo, gastos fiscales/administrativos, comisión bancaria/MP
       ▼
 8  = BASE DE GANANCIA DE SOCIOS
       │
 9  Repartir por MATRIZ DINÁMICA de cabañas activas                        [pool → socios]
       │
       ▼
     SALDO BRUTO POR SOCIO  (uno por socio)
       │
10  − Gastos Clase D / E (por socio)                                       [socio · DESPUÉS de matriz]
       │   D: zonas sectoriales · E: cabañas individuales · horas imputadas · ajustes
       ▼
11  = SALDO FINAL POR SOCIO
```

### 4.1 La línea divisoria (paso 4) es el concepto que ordena todo
- Lo que entra **arriba** de la línea (clase A) lo absorben el **sector operativo y los beneficiarios juntos**: reduce la base sobre la que se calcula el %.
- Lo que entra **abajo** (clases C, D, E, y el 5%) lo absorben **solo los beneficiarios**: el sector operativo ya cobró sobre el resultado base y no vuelve a tocar nada.
- **Por eso no se mezclan clase A y clase C:** cruzan esa línea en sentidos opuestos.

### 4.2 Equivalencia matemática dentro de un mismo nivel (Q-C, cerrada)
Descontar un gasto de pool **como número único antes de repartir** o **repartirlo por la misma matriz** da **resultado equivalente** (la matriz distribuye sobre la resta). Verificado:

> Base $1.000, gasto $100, matriz 26,46 / 26,46 / 47,08.
> A: (1000 − 100) × 0,4708 = **423,72** (Remo).
> B: (1000 × 0,4708) − (100 × 0,4708) = **423,72** (Remo). Idénticos.

**Lo que cambia el resultado NO es la forma de descuento, sino el momento de cascada** (arriba vs. abajo de la línea divisoria). Consecuencia de diseño: el sistema puede elegir la forma **más simple** en cada nivel (descontar el total del pool antes de repartir) sin afectar la corrección. Lo único que hay que clavar con precisión es **a qué nivel/momento pertenece cada gasto**.

### 4.3 El recargo 5% (tratamiento simple, sin fondo fiscal)
- **No entra al paso 1** → el sector operativo **no cobra %** sobre el 5%.
- **Entra en el paso 6** como **entrada post-operativa** que suma al saldo de beneficiarios.
- El **monotributo / gasto fiscal** es un **gasto Clase C** (paso 7), independiente.
- **NO hay neteo ni "fondo fiscal" automático.** El sistema **no** calcula un saldo fiscal positivo/negativo.
- Un **reporte mensual** puede mostrar comparativamente: total de 5% cobrado vs. total de monotributo/fiscal pagado, como **información**, no como lógica contable atada.

> **Frase conceptual:** *El recargo 5% es una entrada post-operativa, no base del porcentaje
> operativo. El monotributo es un gasto Clase C. Ambos pueden compararse en reportes, pero no
> quedan formalmente atados por un neteo o fondo fiscal automático.*

### 4.4 Coherencia con 9B
Esto es consistente con lo ya validado en TEST (9B/3b): el `extra` (5%) siempre fue una **línea separada** (`recargo_5_saldo_transferencia`) que **no reduce saldo**. v0.8 agrega que tampoco **suma a la base operativa** (no entra al paso 1).

---

## 5. La matriz dinámica de participación (paso 9)

### 5.1 Cómo se calcula
Para cada período, por cada socio se **suma el valor relativo de sus cabañas activas**, dividido por el **total de valor activo** del período. Eso da los pesos del reparto del paso 9, aplicados sobre la **base de ganancia de socios** (no sobre el ingreso bruto, no sobre el resultado operativo base).

### 5.2 La matriz se DERIVA, no se guarda
Insumos (cuatro): **catálogo de cabañas + titularidad + valor relativo + activación por período**. La matriz es siempre una **consulta** sobre esos insumos a una fecha/rango dado. Guardarla como números fijos la desincronizaría. **Escalabilidad gratis:** agregar una cabaña nueva es agregar una fila con sus atributos; la matriz se recalcula sola, sin rediseñar nada.

### 5.3 Participación por DISPOSICIÓN, no por ocupación (confirmado)
La participación se calcula sobre las cabañas que cada socio **tiene activadas para el pool** en el período, **independientemente de cuáles se alquilaron, cuántas noches o por cuánto.**

- **Lo que entra al pool** (la plata) = ingreso real del período.
- **Cómo se reparte** (los pesos) = matriz de **disposición** (cabañas activadas), no de ocupación.

> **Ejemplo extremo:** activas Arrebol, Madre Selva, Bamboo, Tokio (100/100/178, total 378 →
> 26,46 / 26,46 / 47,08). Si en todo el mes **solo se alquiló Bamboo** (de Remo), el resultado
> distribuible se reparte igual **26,46 / 26,46 / 47,08**, NO 100% a Remo. Porque Franco y
> Rodrigo **pusieron sus cabañas a disposición del pool**.

**Lógica de fondo:** el pool es un **acuerdo de riesgo compartido**. Todos ponen sus cabañas disponibles y comparten lo que entra (y lo que no), en proporción a lo que pusieron sobre la mesa. La ocupación puntual es suerte del mes; lo que se reparte es el resultado común.

**Por eso la activación importa tanto:** una cabaña **activada que no se alquiló sigue contando**; una **desactivada no cuenta**, se haya podido alquilar o no. La pregunta no es "¿se alquiló?", es **"¿estaba puesta a disposición del pool?"**.

### 5.4 Escenarios verificados

**Actual — activas Arrebol, Madre Selva, Bamboo, Tokio** (Guatemala fuera):
Franco 100 · Rodrigo 100 · Remo 178 · **total 378** → **26,46 / 26,46 / 47,08 %**

**Verano — se activa Guatemala:**
Franco 100+100=178 · Rodrigo 100 · Remo 178 · **total 456** → **39,04 / 21,93 / 39,04 %**

**Futuro — Argentina (chica, valor relativo 50, de Rodrigo), seis activas:**
Franco 178 · Rodrigo 100+50=150 · Remo 178 · **total 506** → **35,18 / 29,64 / 35,18 %**
*(Argentina con valor 50 confirma que el valor relativo es por cabaña, no rígido por tipo.)*

### 5.5 Pendiente: regla del centavo residual
Con participaciones desparejas (o 33,33 × 3), el reparto del paso 9 deja **centavos residuales**. Hay que fijar una **convención determinística única** (ej. redondeo + residual al socio de mayor participación, o a una cuenta de ajuste). Pendiente de decisión, con lugar preciso: el redondeo del paso 9.

---

## 6. Clase ⇒ momento de cascada **y alcance** (van pegados)

**Aclaración clave (confirmada):** el **alcance NO es un campo que se elige aparte** — lo determina la **clase**:

| Clase | Momento de cascada | **Alcance (derivado, fijo)** | Incidencia final |
|---|---|---|---|
| **A** | Paso 2 — antes del % | **General** (todo el pool de activas) | Operativo + beneficiarios |
| **C** | Paso 7 — después del %, antes de matriz | **General** (todos los beneficiarios) | Solo beneficiarios |
| **D** | Paso 10 — después de matriz | **Zona / sector** (una o más cabañas pertenecientes a una zona definida) | Dueños de las cabañas activas de la zona |
| **E** | Paso 10 — después de matriz | **Una cabaña** | Dueño de esa cabaña |

**Consecuencia central:** si los socios deciden cargar el arreglo de una cabaña como **A** o **C**, el alcance pasa a ser **general** — y **eso fue la decisión**. No es que "se cargó en A pero sigue afectando solo a esa cabaña": al ponerlo en A/C, los socios **decidieron que lo absorba el pool**.

**No existen combinaciones contradictorias** del tipo "clase D + alcance cabaña", porque el alcance no se elige: se deriva de la clase. El operador solo elige **la clase** (con sugerencia) y, cuando corresponde, **el detalle**: si es D, **cuál zona**; si es E, **cuál cabaña**.

**Trazabilidad descriptiva (no contable):** poner el arreglo de una cabaña en A/C **borra su rastro de incidencia** sobre esa cabaña (ya incide en el pool). Está bien que sea así. Pero la **etiqueta** y el **comentario** deben dejar el rastro descriptivo (ej. *"arreglo de Guatemala, acordado como general"*), para que el reporte muestre qué pasó aunque la plata se reparta entre todos.

---

## 7. Estructura de un gasto + flexibilidad ("el sistema sugiere, pero no decide")

### 7.1 Campos conceptuales de un gasto
1. **Clase (A/C/D/E)** — **elegida**, con **sugerencia por defecto** según la etiqueta. Define momento de cascada **y alcance**. **Es el único campo que mueve plata entre niveles.**
2. **Zona afectada** — solo si la clase es **D**.
3. **Cabaña afectada** — solo si la clase es **E**.
4. **Etiqueta / categoría** — descriptiva (qué es el gasto). Predefinidas comunes + **"otros"** abierto. Alimenta la sugerencia de clase.
5. **Pagador real (desembolso)** — quién puso la plata o el trabajo (puede ≠ incidencia).
6. **Medio de pago.**
7. **Comentario / justificación** — **obligatorio si hay override.**
8. **Marca de override** — se enciende **automáticamente** si la clase elegida ≠ clase sugerida.
9. **Comprobante** — opcional / futuro.

### 7.2 Mapa de sugerencias etiqueta → clase (sugerencia, nunca obligación)

| Etiqueta | Clase sugerida | Override típico hacia… |
|---|---|---|
| limpieza, insumos, papel, jabón, detergente | A | — |
| luz / gas operativo imputable a activas | A | C (arreglo general) / D (de zona) |
| jardín | C (general) | D (de un sector) |
| caminos | C (general) | **A** (si se acuerda operativo) / D |
| muelle / pasarela | C (general) | D (si sirve a un sector) |
| monotributo, administración, comisión bancaria/MP | C | — |
| termotanque, pintura, arreglo de baño | E | — |
| ropa blanca | A (reposición) | E (si queda en una cabaña) |
| **publicidad / marketing** | **C (general)** | **A** (comercial del período) / D (zona) / E (cabaña) |
| horas de socio | según **clase elegida y destino del trabajo** | — |
| otros | (sin sugerencia → pide clase + comentario) | — |

**Horas de socio — la clase deriva del destino del trabajo (el alcance no se elige aparte):**
- horas en una **cabaña puntual** → **Clase E**;
- horas en una **zona** → **Clase D**;
- horas **operativas generales** → **Clase A**;
- horas en **mantenimiento general** → **Clase C**.

En todos los casos, el socio que trabaja es el **desembolso** (no monetario) y la **incidencia** sigue la regla de la clase → puede generar **deuda entre socios** (ej. horas de Rodrigo en Tokio → incidencia de Remo → deuda Remo→Rodrigo). Valuación hora diferida.

### 7.3 Override (gobernanza para el MVP)
- Cargar un gasto con la **clase sugerida** = **operación normal**.
- **Cambiar** la clase sugerida = **override**.
- El override **pide comentario / justificación**.
- El gasto con override queda **marcado**.
- Debería poder **revisarse en un reporte mensual antes de cerrar la liquidación**.
- **MVP: sin permisos duros.** No se bloquea técnicamente a Vicky u otro operador. Pero se reconoce que **un override de clase no es una corrección menor: cambia quién absorbe el gasto y en qué momento entra** — es, en los hechos, invocar un acuerdo entre socios. La salvaguarda del MVP es **trazabilidad clara** (marca + comentario + reporte), no bloqueo.

### 7.4 Coherencia estructural vs. override de criterio (matiz para el diseño del formulario)
- **Override de criterio** (A↔C↔D por acuerdo): legítimo, solo pide comentario.
- **Incoherencia estructural** (ej. elegir D sin zona, o E sin cabaña): es probable **error de carga** → merece **advertencia más fuerte** que un override. No es lo mismo "los socios decidieron tratar esto distinto" que "esta combinación no se puede repartir". *(Detalle para cuando se diseñe el formulario, no ahora.)*

---

## 8. Tabla de clasificación práctica de gastos reales (v0.7, consolidada)

Momento de cascada según §4. Recordar: **alcance derivado de la clase** (§6).

| Gasto | Clase | Momento | Pagador (desembolso) | Incidencia final | Comentario / frontera |
|---|---|---|---|---|---|
| Limpieza (Jenny) | A | Paso 2 | Caja / socio | Operativo + beneficiarios | Límpido |
| Papel higiénico | A | Paso 2 | Caja / socio | Operativo + beneficiarios | Límpido |
| Rollos de cocina | A | Paso 2 | Caja / socio | Operativo + beneficiarios | Límpido |
| Detergente | A | Paso 2 | Caja / socio | Operativo + beneficiarios | Límpido |
| Garrafas (gas operativo) | A | Paso 2 | Caja / socio | Operativo + beneficiarios | Límpido |
| Electricidad zona grandes | A (sug.) | Paso 2 | Caja / socio | Operativo + beneficiarios | **Operador carga monto imputable a activas.** Override posible |
| Electricidad zona chicas | A (sug.) | Paso 2 | Caja / socio | Operativo + beneficiarios | $100 dos activas / $50 una / $0 ninguna. Override a D posible |
| Monotributo | C | Paso 7 | Socio / caja | Solo beneficiarios | El operativo no lo absorbe. Comparable con 5% en reporte, sin atadura |
| Administración | C | Paso 7 | Caja / socio | Solo beneficiarios | Junto al monotributo |
| Comisión bancaria / MP | C | Paso 7 | Caja (se descuenta sola) | Solo beneficiarios | **≠ recargo 5%** (esto SALE; el 5% ENTRA) |
| Mantenimiento jardín general | C (sug.) | Paso 7 | Caja / socio | Solo beneficiarios | Frontera con la fila siguiente; lo decide el acuerdo |
| Mantenimiento jardín sector chicas | D (sug.) | Paso 10 | Caja / socio | Franco (Guatemala) + Remo (Tokio) | Mismo "jardín", clase según acuerdo |
| Publicidad / marketing general | C (sug.) | Paso 7 | Caja / socio | Solo beneficiarios | Beneficia al complejo, no es costo de una estadía tomada |
| Publicidad campaña del período | A (override) | Paso 2 | Caja / socio | Operativo + beneficiarios | "Acordado como gasto operativo comercial para generar reservas del período" + comentario |
| Termotanque Guatemala | E | Paso 10 | Caja / socio | Franco | Patrimonial: incide aunque Guatemala esté desactivada |
| Pintura Arrebol | E | Paso 10 | Caja / socio | Franco | Patrimonial |
| Horas Rodrigo en Tokio | E | Paso 10 | **Rodrigo (trabajo, no monetario)** | Remo (dueño de Tokio) | Genera **deuda Remo→Rodrigo**. Valuación hora diferida |
| Compra general | A *o* C | Paso 2 *o* 7 | Caja / socio | Según clase elegida | Filtro maestro al cargar |
| Compra específica | E (usual) | Paso 10 | Caja / socio | Dueño de esa cabaña | Algo que queda en una cabaña |
| Arreglo de muelle | C *o* D | Paso 7 *o* 10 | Caja / socio | Según acuerdo | ¿Acceso común (C) o de un sector (D)? |
| Arreglo de pasarela | C *o* D | Paso 7 *o* 10 | Caja / socio | Según acuerdo | "Pasarela de un sector" → D |
| Ropa blanca | A *o* E | Paso 2 *o* 10 | Caja / socio | Según clase elegida | Reposición rotativa → A; queda en una cabaña → E |
| Caminos zona grandes | C/D/**A** | según acuerdo | Caja / socio | Según clase elegida | Ej. override a A: "acordado operativo necesario para las cabañas activas" |
| **Recargo 5% (cobrado al huésped)** | — (entrada) | **Paso 6** | — (lo paga el huésped) | Beneficiarios | **No es gasto ni clase.** Entrada post-operativa; no entra al paso 1 |

### 8.1 El filtro maestro de clasificación
> *¿Este gasto es necesario/recurrente para prestar el servicio de alojamiento **de ese período**
> (→ Clase A, arriba de la línea), o es conservación/mejora del activo (→ abajo: C/D/E según
> alcance)?*

La palabra clave es **del período**: si es para que las cabañas alquiladas **este** mes funcionen → A; si es para que el activo **dure** → C/D/E. **Pero la clase final la elige el operador (con sugerencia); el filtro es guía, no regla rígida.**

### 8.2 Tres precisiones que la tabla deja servidas
- **Comisión bancaria/MP ≠ recargo 5%.** Opuestos: el 5% **entra** (paso 6); la comisión **sale** (paso 7, clase C). Que el número sea parecido es coincidencia.
- **Lo patrimonial (E) incide aunque la cabaña esté desactivada.** La cabaña desactivada **no participa de la matriz ni de los gastos operativos variables del período**; por lo tanto, **tampoco participa indirectamente de las clases A/C que se reparten sobre la base de beneficiarios activos**. Sus **gastos patrimoniales propios (Clase E)** siguen correspondiendo a su beneficiario económico.
- **Desembolso ≠ incidencia** se ve nítido en "horas Rodrigo en Tokio": Rodrigo pone el trabajo, Remo soporta la incidencia → **deuda entre socios**. Por eso las horas **no son un módulo aparte**, sino un gasto con desembolso especial.

---

## 9. Preguntas críticas — estado

**Cerradas en v0.8:**
- **Q-A — Guatemala es chica (78), beneficiario Franco.** Confirmado. Valor relativo **por cabaña** (no rígido por tipo; Argentina=50 lo confirma).
- **Q-B — El % operativo (25→12,5):** la **cascada de 11 pasos es la decisión** — se aplica en el paso 4, después de clase A, antes de clase C, sobre el resultado operativo base. *(Sigue sujeto a la charla de Franco con sus socios para confirmar números/base, pero conceptualmente cerrado en el modelo.)*
- **Q-C — Momento, no forma de descuento** (§4.2). Reformulada y cerrada.
- **Q-D — General vs. sector:** **disuelta** — no hay criterio universal; es **clase elegida por gasto con sugerencia**. El jardín es C o D según el acuerdo, y el comentario lo registra.
- **Q-E — Monotributo es Clase C** (paso 7), no operativo. Cerrada.
- **Q-G — Dueño = beneficiario económico** para el MVP, sin impedir que difieran a futuro. Cerrada para el MVP.
- **Q-luz — La luz no tiene clase obligatoria:** sugerida A, override posible con comentario.
- **Q-override — Gobernanza del override:** trazabilidad sin permisos duros en el MVP (§7.3).

**Abiertas / latentes (para etapas posteriores):**
- **Q-F — Titularidad estable o traspasable por período.** Rumbo definido ("que el diseño no lo impida"), sin cerrar.
- **Centavo residual** del reparto (paso 9): convención determinística pendiente (§5.5).
- **Valuación hora** de trabajo de socios: diferida (¿uno por persona o por tarea?).
- **Period atómico fino** de la matriz: el MVP usa rango grueso mensual; la precisión diaria queda latente.

---

## 10. Riesgos de sobrediseño (a evitar)

- **Resolver la factura completa automáticamente** — evitado: el operador carga el **monto imputable** a activas.
- **Matriz diaria obligatoria** — el MVP empieza grueso; precisión diaria latente, no requisito.
- **Fondo fiscal con neteo automático** — **descartado** (v0.6). El 5% y el monotributo son líneas independientes; la comparación es reporte, no lógica.
- **Cuatro toggles de activación** — colapsados a **un eje operativo** + titularidad estable + bloqueos existentes.
- **"Módulo" separado de "zona"** — unificados.
- **Persistir la matriz** como números fijos — se **deriva** de los insumos.
- **Trabajo de socios como subsistema** — es un gasto con desembolso no monetario.
- **Motor de valor/hora elaborado** — diferido sin costo.
- **Elegir alcance aparte de la clase** — **no**: el alcance se deriva de la clase (§6).
- **Permisos duros de override en el MVP** — no; trazabilidad en su lugar.
- **Persistir liquidaciones cerradas** antes de validar el cálculo read-only.
- **Reusar la tabla `gastos` dormida asumiendo que sirve** — estructuralmente **no alcanza** (un solo FK a cabaña, una sola fecha, sin clase/alcance/desembolso/regla). *(Observación conceptual; el rediseño es trabajo de la etapa de schema.)*

---

## 11. Qué NO implementar todavía (alcance respetado)

Nada de: SQL, nombres de tablas definitivos, migraciones, funciones, workflows, formularios, bump del canónico, OPS. Además: no construir la capa fiscal/ARCA real; no construir el motor de valor/hora; no persistir liquidaciones; no hacer formulario de activación (SQL controlado al inicio); no cerrar formalmente "el 5% es repartible" (lo trata la cascada: entra como entrada post-operativa); no reemplazar formalmente `socios.porcentaje_utilidades` (ver §12); no reusar `gastos` tal cual; no fijar el período atómico fino; **no fijar el orden de la cascada como inmutable** hasta que Franco lo confirme con sus socios (el % operativo y su base siguen sujetos a esa conversación).

---

## 12. Nota sobre `socios.porcentaje_utilidades` (legado, no muerto)

El reparto fijo **33,33 / 33,34 / 33,33** sembrado en la tabla `socios` queda como **registro histórico / legado**. Para el **reparto operativo dinámico**, la **matriz dinámica de cabañas activas lo reemplaza** (§5).

> *`socios.porcentaje_utilidades` queda **cuestionado o superado** para el reparto operativo
> dinámico, salvo que se redefina su rol. **No debe usarse como fuente principal de la matriz
> operativa sin nueva decisión.***

---

## 13. Próximos pasos sugeridos (fuera de este documento conceptual)

1. **Aprobación de Franco** de este v0.8 como base conceptual.
2. Cerrar los **pendientes latentes** cuando corresponda (Q-F titularidad por período, centavo residual, valuación hora, período atómico).
3. Recién entonces: **diseño de schema por bloques** (con sus propias restricciones, TEST primero, aprobación explícita), incluyendo si/ cómo se rediseña `gastos`, cómo se modelan zonas, valor relativo, titularidad y activación por período, y cómo se representan las clases A/C/D/E y la matriz derivada.
4. **Promoción coordinada a OPS** (con el helper `abortar_si_falla` de 9B y todo el conjunto de contabilidad) en **una sola** operación ordenada, con **bump único** del canónico, **solo con aprobación explícita**.

---

**Fin del documento conceptual v0.8 — APROBADO como base conceptual.** Sin SQL, sin schema, sin workflows, sin implementación, sin canónico, sin OPS. Listo para la futura etapa de diseño de schema.
