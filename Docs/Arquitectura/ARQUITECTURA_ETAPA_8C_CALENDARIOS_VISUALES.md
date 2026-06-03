# ARQUITECTURA ETAPA 8C — CALENDARIOS VISUALES POR EVENTO

**Estado:** ✅ **DISEÑO APROBADO** por Franco (v1.2). Listo para implementación por bloques empezando por HTML operativo en TEST. Cierre formal futuro en `8C_CIERRE.md`.
**Tipo:** Documento de diseño. **No contiene SQL ni configuración de workflows (JSON de n8n).**
**Fecha de redacción:** 2026-05-31.
**Versión:** v1.3 (sobre v1.2 aprobada: dos precisiones de implementación del render operativo en sección 5.2.2 — detección de salida incluye estado `completada`; bloqueo se evalúa con `EXISTS` sin asumir unicidad por celda, porque los totales `id_cabana IS NULL` no están cubiertos por el EXCLUDE. Verificación read-only de TEST realizada; W6 `__TEST` confirmado como vía de siembra de bloqueos. Sin cambios en decisiones grandes).
**Schema canónico de referencia:** `6B_SCHEMA_SQL.md v1.7.3`.
**Entorno objetivo de operación:** OPS (`vita-delta-ops`, operación real interna; 8A y 8B cerradas).
**Entorno de validación funcional:** TEST (`vita-delta-test`).

---

## 0. Encuadre y cómo leer este documento

Este documento sigue la misma convención de marcadores de la Etapa 8:

- **🔒 CERRADO** — decisión ya tomada (en este documento o heredada). No se reabre salvo contradicción crítica.
- **🟡 A VALIDAR** — decisión de diseño propuesta que necesita confirmación antes de implementar.
- **✅ VERIFICADO CONTRA OPS** — confirmado contra el contrato vivo de OPS en la verificación read-only del 2026-05-31 (sección 2). Ya no es supuesto.

> **Nota de estado (v1.2):** el documento está **APROBADO**. Los ítems 🔒 son ahora decisiones firmes de 8C. Las marcas ✅ de la sección 2 son hallazgos verificados contra OPS. Los ítems 🟡 restantes (notablemente la sección 9bis, alerta por reserva próxima) son **trabajo posterior previsto**, no parte de los tres bloques iniciales.

La sección 2 **no** es un plan pendiente: es el **registro de los hallazgos reales** leídos de OPS (vistas, columnas, cruce operativo con la reserva real id 1, estados de la grilla y contrato de limpieza). El resto del documento construye sobre esos hallazgos.

Este documento **no genera SQL ni JSON de workflow**. Es diseño. La implementación arranca recién tras la aprobación de este documento y por bloques, validando primero en TEST.

---

## 1. Contexto y objetivo de 8C

### 1.1 Qué resuelve 8C

8C construye **dos calendarios visuales internos, derivados y de solo lectura**, alimentados desde Supabase OPS como **fuente de verdad**:

1. **Calendario operativo/comercial** — para Franco, Rodrigo, Vicky y Remo. Muestra ocupación, reservas confirmadas/activas y bloqueos, con el detalle comercial necesario para operar y tomar reservas (huésped, personas, horarios de check-in/check-out, montos, teléfono). **Reemplaza el calendario manual mensual** (un Excel con una hoja por mes) que el equipo está agotando.
2. **Calendario de limpieza** — para Jennifer. Muestra entradas, salidas y cambios de los próximos 7 días, orientado a organizar limpieza y recambios, **sin datos comerciales** (sin montos ni señas).

8C **no** es un nuevo motor ni una nueva puerta de escritura: es una **capa de presentación** sobre vistas que ya existen en el schema. No calcula disponibilidad por su cuenta (principio heredado): **lee** de las vistas.

### 1.2 Qué queda explícitamente FUERA de 8C

- **Bloqueos operativos de uso real (creación/gestión):** son **8D**. 8C solo **muestra** bloqueos que ya existan en la base; no los crea ni los edita.
- **MercadoPago real / webhook MP, bot conversacional, frontend público de reservas, integraciones Airbnb/Booking automáticas:** etapas futuras.
- **Modificación de schema canónico o de funciones SQL:** no se tocan. La verificación de la sección 2 confirmó que las vistas existentes alcanzan; no hay hallazgo crítico que obligue a cambiar schema.
- **RLS / residual A5 en DEV:** no se tocan.
- **Tarifas reales, feriados productivos:** fuera de alcance.

### 1.3 Principios heredados que gobiernan 8C

- **Supabase es la fuente de verdad.** Todo lo que se pinta se deriva de las vistas; ninguna representación materializada (HTML cacheado o Sheet) es autoritativa.
- **No sobreingeniería.** MVP útil, simple, verticalmente implementable. Mejoras posibles quedan anotadas como futuro, no se construyen ahora.
- **No cron/polling como primera opción.** La actualización es por evento + repintado a demanda (sección 7).
- **Apps Script congelado.** El Sheet de resguardo se escribe vía API de Google Sheets desde n8n, no con Apps Script.
- **Convenciones:** snake_case, ISO 8601, celdas vacías antes que placeholders falsos.

---

## 2. Hallazgos de la verificación read-only contra OPS ✅

Verificación ejecutada el 2026-05-31 en el SQL Editor de OPS (`vita-delta-ops`, ref `lpiatqztudxiwdlcoasv`), solo lectura, con gate de ambiente confirmado (las 5 cabañas reales con IDs 1–5: Bamboo=1, Madre Selva=2, Arrebol=3, Guatemala=4, Tokio=5).

### 2.1 Las 6 vistas existen y sus columnas son las esperadas ✅

`pg_views` devolvió las 6 vistas del canónico: `vista_calendario`, `vista_calendario_semanal`, `vista_disponibilidad`, `vista_limpieza_semana`, `vista_ocupacion`, `vista_prereservas_activas`.

Columnas reales confirmadas de las tres que 8C consume:

- **`vista_disponibilidad`**: `id_cabana`, `fecha`, `estado` (TEXT), `tipo_dia`, `temporada`, `hora_checkin_base`, `hora_checkout_base`, `id_reserva_activa`, `id_prereserva_activa`. Es la **grilla día×cabaña**.
- **`vista_calendario`**: `id_cabana`, `cabana`, `id_reserva`, `fecha_checkin`, `fecha_checkout`, `hora_checkin`, `hora_checkout`, `personas`, `estado_reserva`, `huesped_nombre`, `huesped_telefono`, `monto_total`, `monto_saldo`, `encargado_semana`. Es el **detalle por reserva**.
- **`vista_limpieza_semana`**: `fecha_movimiento`, `tipo_movimiento` (checkin/checkout), `cabana`, `id_cabana`, `id_reserva`, `hora`, `personas`, `huesped`, `huesped_telefono`, `mascotas`, `detalle_mascotas`, `notas_reserva`. **No trae ningún campo de monto** → el contrato de limpieza es seguro de origen.

### 2.2 El cruce operativo funciona, validado con la reserva real ✅

La reserva real id 1 aparece en la grilla como `id_cabana=5` (Tokio), `fecha=2026-06-06`, `estado='ocupada'`, `id_reserva_activa=1`. El detalle de `vista_calendario` para esa misma reserva trae: huésped "Paula Lugo", 2 personas, check-in 13:00, check-out 16:00, teléfono 1166695723, monto_total 150000, monto_saldo 75000.

El cruce confirmado es:

```
vista_disponibilidad.id_reserva_activa  =  vista_calendario.id_reserva
```

Donde la grilla marca un día con reserva activa, el detalle lo rellena por ese match. Sólido y suficiente para el operativo.

### 2.3 Estados reales de la grilla — apareció `checkout_disponible` ✅

`vista_disponibilidad.estado` devolvió, en datos reales:

- `disponible` — libre.
- `ocupada` — hay reserva activa ese día (trae `id_reserva_activa`).
- `checkout_disponible` — **día de salida** en modelo `[)`: ese día sale un huésped y la cabaña puede recibir un check-in nuevo. Apareció el 2026-06-07 (salida de Paula).
- `bloqueada` — soportado por la vista (no se observó porque hoy no hay bloqueos en OPS).

**Hallazgo clave de diseño:** `checkout_disponible` **no es** el "rojo" del calendario (ver sección 5). Es solo la señal del motor de que ese día termina una ocupación y puede empezar otra. El color del operativo se calcula con lógica propia de pintado (sección 5.2), no copiando el `estado` 1:1.

### 2.4 Horizonte 120 y autodesplazamiento — origen del "se acaba" ✅

La grilla se extendió de forma continua desde 2026-05-31 hasta 2026-09-27 (≈120 días), por cabaña, desplazándose con `CURRENT_DATE`. El horizonte vive en `configuracion_general.horizonte_disponibilidad_dias = 120` (con fallback 120 por `COALESCE` en la vista).

**Conclusión:** el calendario manual "se acaba" porque tiene **una hoja física por mes creada a mano** (la última era "Marzo 2027"), no por límite del motor. Cualquier formato de 8C que lea el rango `[hoy, hoy+120]` hereda el autodesplazamiento y **no** reintroduce el problema de "crear el mes a mano".

> **Verificación menor pendiente (no bloqueante):** la query Q3 (lectura explícita de `horizonte_disponibilidad_dias` + `MIN/MAX(fecha)` de `vista_disponibilidad`) no se devolvió en la corrida. El rango quedó **validado empíricamente** vía Q4 (31-may → 27-sep). Se confirmará por prolijidad en la fase de implementación; no condiciona el diseño.

### 2.5 Contrato de limpieza validado con datos reales ✅

`vista_limpieza_semana` devolvió exactamente los dos movimientos de la reserva real: checkin 2026-06-06 13:00 y checkout 2026-06-07 16:00, ambos con `personas=2`, teléfono, `mascotas=false`. Ningún campo de monto. `detalle_mascotas` y `notas_reserva` vinieron vacíos (la reserva no los tiene; cuando existan, se mostrarán).

---

## 3. Dos públicos, dos contratos de visualización

### 3.1 Contrato operativo/comercial 🔒

Público: Franco, Rodrigo, Vicky, Remo. Puede ver información comercial completa.

Campos visibles por reserva (en celda ocupada):

- Huésped (nombre).
- Cantidad de personas.
- Horario de check-in y de check-out.
- Monto total y monto saldo (pagado / pendiente).
- Teléfono.

Capas mostradas: **reservas confirmadas/activas + bloqueos**. **No** se muestran pre-reservas vigentes (decisión de Franco).

Horizonte: **120 días** (`[hoy, hoy+120]`), autodesplazante.

### 3.2 Contrato de limpieza (Jennifer) 🔒

Público: Jennifer. Orientado a limpiar y organizar recambios. Ella también puede encargarse de check-in/check-out, por eso ve el teléfono.

Campos visibles:

- Cabaña.
- Fecha de movimiento.
- Tipo de movimiento (entrada / salida).
- Hora.
- **Cantidad de personas** (el dato más importante para ella).
- Teléfono.
- Mascotas (sí/no) y detalle de mascotas.
- Notas/comentarios de la reserva.

Exclusiones explícitas (no ve): montos, señas, cualquier dato comercial. DNI no aplica hoy (no implementado) y queda como **exclusión explícita para el futuro**: si algún día se agrega DNI al modelo, no debe aparecer en el calendario de limpieza.

Horizonte: **7 días** (la `vista_limpieza_semana` tal cual).

### 3.3 Tabla de campos: fuente → operativo → limpieza

| Campo | Fuente | Operativo | Limpieza |
|---|---|---|---|
| Cabaña | ambas vistas | sí | sí |
| Fecha / día | vista_disponibilidad / vista_limpieza_semana | sí (grilla) | sí (movimiento) |
| Estado del día | vista_disponibilidad | sí (color) | — |
| Huésped (nombre) | vista_calendario / vista_limpieza_semana | sí | sí |
| Personas | vista_calendario / vista_limpieza_semana | sí | **sí (clave)** |
| Hora check-in | vista_calendario / vista_limpieza_semana | sí | sí (movimiento) |
| Hora check-out | vista_calendario / vista_limpieza_semana | sí | sí (movimiento) |
| Teléfono | vista_calendario / vista_limpieza_semana | sí | sí |
| Monto total | vista_calendario | sí | **NO** |
| Monto saldo (pagado/pendiente) | vista_calendario | sí | **NO** |
| Mascotas / detalle | vista_limpieza_semana | (opcional) | sí |
| Notas/comentarios | vista_limpieza_semana | (opcional) | sí |
| Pre-reservas vigentes | vista_prereservas_activas | **NO** | **NO** |

---

## 4. Formato y arquitectura de entrega

### 4.1 Decisión: HTML servido (principal) + Sheet de resguardo (secundario) 🔒

- **HTML servido = formato principal.** Es la cara que ve el equipo a diario. Permite igualar o superar la calidad visual del calendario manual sin las limitaciones de pintado de la API de Sheets. Requisito de Franco: la calidad de visualización debe ser **como mínimo** la del Excel actual.
- **Google Sheet repintado = resguardo.** Red de seguridad ante caída de n8n: el Sheet queda en Drive y el equipo lo tiene "siempre descargado". No necesita ser bonito; necesita tener los datos.

Motivo de la jerarquía: el HTML resuelve de raíz la desincronización (render al vuelo desde la vista) y la calidad visual; el Sheet aporta resiliencia offline. Se priorizó calidad visual (HTML) por requerimiento explícito.

### 4.2 HTML vía webhook de n8n Cloud + Basic Auth 🔒

- n8n Cloud (`federicosecchi.app.n8n.cloud`) expone URLs públicas, accesibles desde datos móviles (el equipo accede desde el celular, la lancha, etc. — confirmado por Franco). No requiere infraestructura extra.
- **Dos endpoints separados**, uno por público:
  - operativo → contrato de la sección 3.1.
  - limpieza → contrato de la sección 3.2.
- Cada endpoint protegido con **Basic Auth** (mismo mecanismo que el Form Trigger de 8B).
- El HTML se **renderiza al vuelo** leyendo las vistas en cada carga: no hay estado materializado del lado HTML → **cero desincronización**.

### 4.3 Sheet de resguardo vía API de Google Sheets 🔒

- Se escribe con la **API de Google Sheets** mediante nodo n8n (credencial de Google Sheets ya configurada por Franco). **No** se usa Apps Script (regla heredada).
- Una sola estructura (o pocas hojas) que se **repinta sobre el rango** `[hoy, hoy+120]`, sin hojas-por-mes manuales → no reintroduce el "se acaba".
- **Marca de "última regeneración" visible (obligatoria):** el Sheet debe mostrar, en un lugar prominente (ej. celda fija arriba del calendario), la **fecha y hora ISO 8601 de la última regeneración** (timezone America/Argentina/Buenos_Aires). Como el Sheet es una **copia materializada** que puede quedar desactualizada respecto de OPS, esta marca evita que alguien tome decisiones mirando un resguardo viejo. Si el resguardo es de hace varios días, quien lo mira lo sabe de un vistazo y va al HTML (que siempre está fresco) o regenera. El HTML, al renderizar al vuelo, no necesita esta marca, pero **puede** mostrar también "datos al " + hora de la consulta como cortesía.
- Prioridad menor que el HTML. Puede quedar como repintado **a demanda** (botón "regenerar resguardo") en vez de automático tras cada reserva, si el HTML ya da tranquilidad. Se decide al implementar el bloque 3.

### 4.4 Orden de construcción 🔒

1. **HTML operativo** (el corazón; lo que el equipo usa a diario).
2. **HTML limpieza** (segundo público, contrato reducido).
3. **Sheet de resguardo** (respaldo offline).
4. **(Opcional, posterior) Alerta por reserva próxima — 8C-bis** (sección 9bis). NO es parte de los tres bloques principales; se construye recién después del bloque 3.

Cada bloque se valida en TEST antes de tocar OPS.

---

## 5. Diseño visual del calendario operativo

### 5.1 Lógica visual heredada del boceto 🔒

Se reproduce la **lógica** del Excel actual (no pixel-perfect, sí la estructura que el equipo ya conoce):

- **Grilla por mes.** Días como **columnas** (1, 2, 3 … fin de mes). Una grilla/sección por mes dentro del horizonte de 120 días.
- **Cabañas como bloques verticales**, en orden fijo: **Bamboo, Madre Selva, Arrebol, Guatemala, Tokio**.
- **Cada cabaña ocupa un bloque de 3 filas**, con etiqueta a la izquierda:
  1. Huésped · personas · horario.
  2. Teléfono.
  3. Pagado / pendiente.
- El **color** pinta el día (la columna del día para esa cabaña); el **texto** vive en las 3 filas de la cabaña, en los días ocupados.
- Leyenda de colores visible (verde / rojo / gris / blanco).

### 5.2 Codificación de estados y lógica de pintado 🔒

**Paleta y prioridad (de mayor a menor):**

1. **🔴 Rojo — día de dos eventos de transición** en esa cabaña. Cubre dos casos:
   - check-out de una reserva **y** check-in de **otra** reserva distinta el mismo día (recambio, **incluido el recambio "pegado"** donde `fecha_checkout` de la saliente = `fecha_checkin` de la entrante); o
   - **borde de bloqueo** (inicio o fin) que cae el mismo día que un **movimiento de reserva** (entrada o salida) en esa cabaña.
2. **⬜ Gris — bloqueo.** Todos los días del bloqueo se pintan gris, salvo los días-borde que caigan en el caso rojo (regla 1).
3. **🟢 Verde claro — ocupación por reserva.** Incluye el primer y el último día de la estadía. Un día de salida **sin** entrada de otro huésped es **verde**, no rojo.
4. **⬜ Blanco — libre**, sin ocupación ni movimiento.

**Regla única (vale para todos los casos, sin excepciones):**

> Un día de una cabaña es **rojo** si y solo si en esa cabaña, ese día, coinciden **dos eventos de transición**: un check-out de una reserva **y** un check-in de **otra** reserva distinta; **o** un borde de bloqueo (inicio/fin) junto con un movimiento de reserva.
> Si hay ocupación de un solo huésped (sin recambio), es **verde** — incluido el primer día (solo entra) y el último día (solo sale).
> Si hay bloqueo sin doble evento, es **gris**.
> Si no hay nada, es **blanco**.

El recambio "pegado" (la saliente termina el mismo día que empieza la entrante) **sí es rojo**: ese día ocurren dos eventos. No existe el caso "verde corrido pasando por un día de recambio".

**Cómo se calcula (capa de presentación, sin tocar schema):** el color **no** se lee de un único campo `estado`. Se calcula por cabaña y día combinando:

- **Ocupación (candidato a verde):** un día está ocupado si alguna reserva confirmada/activa cumple `fecha_checkin <= día < fecha_checkout` **o** `fecha_checkout = día` (el día de salida se cuenta como ocupado a efectos visuales; ver 5.2.1 sobre la invariante técnica).
- **Hay salida ese día:** existe reserva con `fecha_checkout = día`.
- **Hay entrada ese día:** existe reserva con `fecha_checkin = día`.
- **Recambio (rojo, caso A):** hay salida **y** entrada el mismo día, de reservas distintas.
- **Bloqueo (candidato a gris):** un bloqueo cumple `fecha_desde <= día < fecha_hasta` (modelo `[)`).
- **Rojo, caso B (bloqueo + movimiento):** el día es borde de bloqueo (`fecha_desde = día` o `fecha_hasta = día`) **y** además hay un movimiento de reserva (entrada o salida) ese día en la misma cabaña.

Aplicando la prioridad (rojo > gris > verde > blanco) sobre esos predicados se obtiene el color final. Las fechas de check-in/check-out por reserva están en `vista_calendario`; para el operativo (120 días) el cálculo se hace sobre las reservas del rango. **No requiere cambiar el schema.**

**Ejemplos validados con Franco — todos bajo la regla única:**

- *Solo entra 7 / sale 9, nada más:* blanco hasta el 6, **verde 7-8-9**, blanco del 10 en adelante. (El 9 es salida sin entrada → verde.)
- *Reservas A 4→7, B 7→9, C 10→12:* verde 4-5-6, **rojo el 7** (sale A + entra B, recambio pegado), verde 8, **verde el 9** (sale B, nadie entra ese día porque C entra el 10), verde 10-11-12. **(Corrección sobre v1.0: el día 7 es rojo, no verde corrido.)**
- *Recambios A 4→7, B 7→9, C 9→12:* verde 4-5-6, **rojo el 7** (sale A + entra B), verde 8, **rojo el 9** (sale B + entra C), verde 10-11-12.
- *Cadena día a día 4→5, 5→6, 6→7, 7→8:* verde 4, **rojo 5-6-7**, verde 8.

#### 5.2.1 Invariante técnica: `fecha_out` sigue siendo exclusive 🔒

El pintado verde del día de salida (cuando no hay recambio) es **una convención puramente visual/operativa**: sirve para que el equipo vea que ese día hay un check-out y, por lo tanto, limpieza/recambio a coordinar. **No modifica el modelo de datos.**

A nivel técnico, **`fecha_in` es inclusive y `fecha_out` es exclusive** (modelo daterange `[)`), exactamente como está cerrado en `DECISIONES_NO_REABRIR.md`. Esto significa:

- La noche de `fecha_out` **no** se cobra ni ocupa: esa misma noche la cabaña puede recibir un nuevo check-in (por eso el recambio pegado A→B el mismo día es válido y no genera solapamiento; lo garantiza el `EXCLUDE constraint`).
- 8C **no** toca la disponibilidad ni la lógica del motor. Solo decide un color para una celda. Que la celda del día de salida se pinte verde es presentación, no semántica de ocupación.
- Por eso `checkout_disponible` (estado real del motor, sección 2.3) y "verde del día de salida" conviven sin contradicción: el motor dice "esta cabaña está disponible para reservar ese día"; el calendario dice "ese día hay un checkout que atender". Son dos lecturas del mismo hecho, ninguna altera al modelo `[)`.

#### 5.2.2 Precisiones de implementación del render (v1.3) 🔒

Derivadas de la verificación read-only contra TEST (2026-05-31), leyendo la definición real de `vista_calendario_semanal`. No cambian decisiones de diseño; precisan cómo el nodo de render calcula los predicados, replicando la lógica de la vista existente en lugar de inventar una propia.

1. **Detección de "salida ese día" incluye estado `completada`.** Para detectar que una reserva sale un día (`fecha_checkout = día`), se consideran los estados `confirmada`, `activa` **y `completada`**, exactamente como hace el subselect `reserva_saliente` de `vista_calendario_semanal`. Si se omitiera `completada`, una reserva ya finalizada no marcaría su día de checkout y se perdería el rojo de un recambio donde la saliente ya pasó a completada. (Para "ocupada" y "entrada ese día" se mantienen `confirmada`/`activa`, igual que la vista.)

2. **Bloqueo se evalúa con `EXISTS`, sin asumir unicidad por celda.** El predicado de bloqueo es `EXISTS (bloqueo activo que cubra el día, con id_cabana = cabaña OR id_cabana IS NULL)`. No se asume "un bloqueo por celda": el `EXCLUDE` de la tabla `bloqueos` (`exc_bloqueos_no_overlap`) solo cubre bloqueos **específicos** (`WHERE activo = true AND id_cabana IS NOT NULL`), por lo que **un bloqueo total (`id_cabana IS NULL`) puede solaparse con uno específico o con otro total**. Basta que exista al menos un bloqueo activo que cubra el día para pintarlo gris (o rojo si además hay borde + movimiento). El render filtra siempre `activo = true`.

3. **El motivo de la celda gris sale de `bloqueos.motivo`** (CHECK: mantenimiento/uso_propio/tormenta/overbooking/otro) y opcionalmente `bloqueos.descripcion`. Nunca datos comerciales.

### 5.3 Datos en la celda — celda verde (monoetápica) vs celda roja (bietápica) 🔒

- **Celda verde (un solo huésped):** las 3 filas muestran al huésped que ocupa ese día (nombre · personas · horario / teléfono / pagado-pendiente).
- **Celda roja (dos eventos):** el orden de lectura **de arriba hacia abajo refleja la secuencia del día — primero lo que termina, después lo que empieza**:
  1. **Primero, lo que se va / termina:** check-out del huésped saliente con su **horario de salida**, **o** fin del bloqueo.
  2. **Después, lo que entra:** huésped que ingresa, cantidad de personas, horario de check-in; luego pago/pendiente del que entra; luego teléfono del que entra.
  - Es decir: en el día rojo, **los datos comerciales (pago, teléfono) son los del huésped que ENTRA**, no del que se va. Al saliente solo se le muestra que se va y a qué hora (dato para coordinar limpieza/recambio).

### 5.4 Fidelidad "lógica visual, no pixel-perfect" 🔒

El MVP replica la lógica del Excel (bloques por cabaña, días en columnas, color por estado, 3 filas de datos). No se promete reproducción exacta píxel a píxel. La barra continua tipo Gantt para estadías de varios días (Opción B) queda como **posible mejora futura, fuera del MVP**.

### 5.5 Estadías de varios días — Opción A 🔒

Para una estadía de varios días, el texto del huésped (nombre/personas/horario, teléfono, pagos) se escribe **una sola vez** (al inicio de la estadía); los días siguientes quedan **verdes sin repetir el texto**. Replica exactamente el comportamiento del Excel y evita curva de adopción. (Opción B = barra continua centrada: futuro, no MVP.)

---

### 5.6 Cómo se pintan los bloqueos (operativo) 🔒

Los bloqueos se muestran en el calendario operativo (no en el de limpieza). 8C **solo los muestra**; crearlos/editarlos es 8D. El modelo de bloqueos usa el mismo rango `[)` que las reservas: `fecha_desde` inclusive, `fecha_hasta` exclusive.

**a) Bloqueo específico por cabaña** (`id_cabana` = una cabaña concreta): se pinta gris en esa cabaña, en todos los días `fecha_desde <= día < fecha_hasta`. Las otras cabañas no se afectan.

**b) Bloqueo total** (`id_cabana = NULL`): aplica a **las cinco cabañas a la vez**. En el render, un bloqueo con `id_cabana IS NULL` se interpreta como "vale para toda cabaña": al calcular el color de cada cabaña, el predicado de bloqueo es verdadero si existe un bloqueo activo con (`id_cabana = <esa cabaña>` **o** `id_cabana IS NULL`) que cubra el día. Es decir, el bloqueo total se "expande" a las cinco columnas de cabaña; no hay una fila aparte de "complejo". Esto es consistente con cómo `vista_calendario_semanal` ya evalúa bloqueos (`b.id_cabana = c.id_cabana OR b.id_cabana IS NULL`).

**c) Inicio de bloqueo** (`fecha_desde`): el primer día del bloqueo es gris, salvo que ese día además haya un movimiento de reserva en esa cabaña (ver e).

**d) Fin de bloqueo:** como `fecha_hasta` es **exclusive**, el último día efectivamente bloqueado es `fecha_hasta - 1 día`. El día `fecha_hasta` **no** está bloqueado (la cabaña vuelve a estar disponible ese día). Esto evita pintar de más: un bloqueo `10→12` ocupa gris los días 10 y 11, y el 12 ya no es gris por ese bloqueo.

**e) Borde de bloqueo + movimiento de reserva → rojo:** si el día de inicio del bloqueo (`fecha_desde`) o el día de reapertura (`fecha_hasta`) coincide con un movimiento de reserva (un check-in o un check-out) en la misma cabaña, ese día es **rojo** (regla única, caso B), con prioridad sobre el gris. Ejemplos:
   - Bloqueo `7→10` en una cabaña donde una reserva tiene check-out el día 7 → el 7 es **rojo** (sale huésped + empieza bloqueo); 8 y 9 gris; el 10 según lo que haya (si nada, blanco).
   - Bloqueo `5→7` y una reserva con check-in el día 7 → 5 y 6 gris; el 7 es **rojo** (termina bloqueo + entra huésped).

**Prioridad recordada:** rojo (doble evento) > gris (bloqueo) > verde (ocupación) > blanco. Un día que sea simultáneamente borde de bloqueo y movimiento de reserva siempre gana rojo.

**Datos en una celda gris:** un bloqueo no tiene huésped ni montos. La celda gris puede mostrar, si está disponible, el motivo/descripción del bloqueo (campo de la tabla `bloqueos`), pero **no** datos comerciales. En una celda roja por borde-de-bloqueo + movimiento, se aplica la estructura bietápica de 5.3: arriba el evento que termina (fin de bloqueo, o checkout), abajo el que empieza (inicio de bloqueo, o checkin con sus datos).

## 6. Diseño visual del calendario de limpieza

### 6.1 Vista de 7 días orientada a movimientos 🔒

- Fuente: `vista_limpieza_semana` (próximos 7 días).
- Orientada a **movimientos** (entradas y salidas), no a grilla de ocupación: cada fila es un movimiento (checkin/checkout) con su fecha, hora, cabaña y datos.
- Ordenada por fecha y hora, para que Jennifer lea el día y el orden de recambios de un vistazo.

### 6.2 Campos y exclusiones de privacidad 🔒

Muestra: cabaña, fecha, tipo de movimiento (entrada/salida), hora, **personas**, teléfono, mascotas + detalle, notas.
No muestra: montos, señas, datos comerciales. DNI excluido a futuro (sección 3.2).

Como `vista_limpieza_semana` **no trae montos de origen** (verificado, sección 2.5), el contrato de limpieza se respeta seleccionando las columnas seguras en la consulta de n8n. **No se requiere vista derivada nueva ni cambio de schema.**

#### 6.2.1 Teléfono y notas en limpieza — decisión operativa explícita 🔒

Que Jennifer vea **teléfono** y **notas/comentarios** es una **decisión operativa deliberada**, no una omisión de privacidad: ella puede necesitar coordinar directamente temas de check-in/check-out o de limpieza con el huésped, y las notas pueden contener instrucciones útiles para la estadía o el recambio. Queda registrado como decisión, no como descuido.

**Regla operativa de carga de notas (para quien crea la reserva):**

> Las notas visibles para limpieza deben contener **solo información operativa útil para estadía, limpieza o coordinación**. **No** deben cargarse allí montos, señas, descuentos, acuerdos comerciales, conflictos, datos financieros, datos sensibles, ni información que Jennifer no necesite.

Es una regla **de carga** (disciplina del operador al escribir `notas_reserva`), no un control técnico: el campo `notas_reserva` es libre y 8C lo muestra tal cual. No cambia schema ni crea vista nueva. La responsabilidad de no contaminar las notas con datos comerciales recae en quien carga la reserva (8B). Si en el futuro se quisiera un control técnico (separar notas operativas de notas comerciales en columnas distintas), sería un cambio de schema fuera del alcance de 8C.

---

## 7. Modo de actualización

### 7.1 Repintado / regeneración a demanda — operación canónica 🔒

La operación canónica es **regenerar el calendario leyendo la fuente de verdad** sobre el rango (`[hoy, hoy+120]` operativo; 7 días limpieza). En HTML esto es trivial: cada carga del endpoint ya lee las vistas (no hay nada que "repintar"). Para el Sheet de resguardo, es un repintado completo del rango.

Debe existir como **herramienta de reparación/regeneración** invocable a demanda (el "botón regenerar"), independiente de cualquier evento. Esto cubre el requisito de Franco: **8C no puede depender solo de eventos futuros**; debe reflejar reservas/bloqueos que **ya existen** en Supabase.

### 7.2 Enganche en el punto de extensión post-`confirmar_reserva` 🔒

8B dejó marcado el punto de extensión post-`confirmar_reserva` ok. En 8C, ese punto actúa como **disparador**: tras confirmar una reserva, se invoca la regeneración. Pero el **dato siempre sale de la fuente de verdad** (la vista), no del evento: el evento dice "regenerá", no "pintá esto". Así, una confirmación, una expiración, una cancelación o un bloqueo manual quedan todos reflejados en la próxima regeneración, sin depender de que cada cambio dispare su propio evento.

Para el HTML, dado que renderiza al vuelo, el disparo es prácticamente innecesario (siempre está fresco). Para el Sheet de resguardo, el disparo post-confirmación mantiene el respaldo razonablemente al día; si se opta por regeneración solo a demanda (sección 4.3), se documenta esa decisión al implementar.

### 7.3 Por qué NO cron/polling 🔒

No se usa cron/polling como primera opción (principio heredado). El HTML al vuelo no lo necesita (lee en cada request). El Sheet se cubre con disparo por evento + regeneración a demanda. Un cron solo se consideraría si apareciera una razón fuerte (p. ej. mantener el Sheet de resguardo sincronizado sin intervención), y se decidiría explícitamente; no es el camino por defecto.

### 7.4 Reflejar reservas/bloqueos ya existentes 🔒

Como la regeneración lee siempre el rango completo desde las vistas, el calendario refleja **todo** lo que existe en Supabase en ese momento (reservas confirmadas/activas y bloqueos), no solo lo creado después de encender 8C. Esto resuelve explícitamente el punto de Franco de "no depender solo de eventos futuros".

---

## 8. Acceso y privacidad

### 8.1 Basic Auth y separación de públicos 🔒

- **Dos endpoints HTML separados**, con **URLs distintas** (una operativa, una de limpieza). No es una sola página con un parámetro: son dos rutas independientes.
- **Dos Basic Auth separados** (credenciales distintas por endpoint): la credencial operativa y la de limpieza son diferentes, de modo que dar acceso a Jennifer nunca habilita el endpoint comercial y viceversa.
- **Contraseñas fuertes** para cada Basic Auth (largas, aleatorias, no reutilizadas de otros sistemas). Se gestionan como credenciales de n8n, no se hardcodean en el HTML.
- **No compartir URLs con credenciales embebidas.** Está prohibido repartir links del tipo `https://usuario:password@host/...`: ese formato filtra la contraseña en historial, chats y caché. Las credenciales se comunican por un canal aparte del link, o se usa un mecanismo de sesión; nunca dentro de la URL.
- El endpoint operativo expone datos comerciales (montos, teléfono); el de limpieza no expone montos.
- La separación es **física** (dos URLs, dos contratos de consulta, dos credenciales), no un filtro condicional sobre una misma página. Reduce el riesgo de filtración accidental de datos comerciales a limpieza.

> **Nota:** el alcance de seguridad de 8C es Basic Auth + separación física + higiene de credenciales, suficiente para un MVP interno sin consumidores externos. Endurecimientos mayores (tokens rotables, expiración de sesión, RLS) quedan fuera de 8C y se evalúan si y cuando el sistema gane superficie pública.

### 8.2 Reparto de URLs 🔒

- **URL operativa** → equipo comercial (Franco, Rodrigo, Vicky, Remo), con su credencial. Algunos ya usan Google/Sheets; para ellos también sirve el Sheet de resguardo.
- **URL de limpieza** → Jennifer, con su credencial propia. Pensada como **link simple** que abre en el celular sin requerir cuenta de Google ni app (ella no usa Sheets). El HTML cumple bien este rol.
- Las dos URLs se reparten por separado, cada una a su público, sin credenciales embebidas en el link (8.1).

---

## 9. Plan de validación

Patrón heredado: **validar primero en TEST, OPS solo con smoke mínimo controlado**, sin pruebas destructivas.

### 9.1 En TEST (`vita-delta-test`)

1. **Verificación read-only en TEST — ✅ realizada (2026-05-31).** Confirmadas las 6 vistas (paridad con OPS), columnas reales de `bloqueos`, modelo de bloqueo total (`id_cabana IS NULL`, nullable, fuera del EXCLUDE), firma `crear_bloqueo(payload jsonb) → jsonb`, patrón de pintado de `vista_calendario_semanal`, y criterio de intersección de rango. TEST tiene 0 bloqueos → los casos de bloqueo se siembran.
2. **Vía de siembra de bloqueos: W6 `__TEST` ✅ confirmado.** Existe el workflow `vita_w06_crear_bloqueo_supabase__TEST` (vía alineada con el patrón validado del proyecto); se usa para crear los bloqueos de validación. Si por algún motivo no estuviera operativo, fallback a `crear_bloqueo(payload jsonb)` por bloque controlado en TEST (vía función del motor, nunca INSERT directo, con `source_event` claro tipo `test_8c_bloqueo_especifico` / `test_8c_bloqueo_total`, documentando qué se creó y cómo se limpia).
3. Construir el **HTML operativo** apuntando a la credencial de TEST (`vita_supabase_test`). Validar:
   - Grilla 120 días, 5 cabañas, autodesplazante.
   - Pintado correcto de los 4 estados con casos sembrados en TEST: ocupación simple (verde multi-día), recambio pegado (rojo), día de salida sin entrada (verde), bloqueo específico (gris una cabaña), bloqueo total (gris las 5), borde de bloqueo + movimiento (rojo).
   - Celda roja bietápica con orden sale→entra y datos comerciales del que entra.
   - Datos correctos en celda verde (huésped/personas/horarios/montos/teléfono).
   - Reserva que **intersecta** el rango (criterio `fecha_checkin <= hoy+120 AND fecha_checkout > hoy`).
4. **Caso "reserva iniciada antes de hoy":** no se fuerza la capa 8B si bloquea fechas pasadas (D-8B-11). Para validar intersección visible alcanza con una reserva que **empieza hoy** y sale dentro del rango. El caso estricto "empezó antes del rango y sale dentro" queda como **test técnico posterior** o se resuelve de forma controlada en TEST; no complica el MVP.
5. Manejo de error: validar que, si falla un Postgres o el render, el endpoint devuelve una **página HTML de error controlada** (mensaje genérico) sin stack trace, queries, credenciales ni nombres internos.

> Los pasos de HTML limpieza, Sheet de resguardo y regeneración/disparo se validan en sus bloques respectivos (2, 3 y modo de actualización), no en el Bloque 1.

### 9.2 En OPS (`vita-delta-ops`) — smoke mínimo controlado

Solo tras TEST verde: smoke de **solo lectura** sobre OPS — abrir los endpoints apuntando a la credencial OPS y verificar que la reserva real id 1 (Tokio, Paula Lugo, 06→07 jun) se ve correcta en operativo y en limpieza. Sin sembrar datos ficticios en OPS. El Sheet de resguardo de OPS se genera una vez como verificación.

---

## 9bis. Bloque 4 opcional / 8C-bis — Alerta por reserva próxima 🟡

**Estado: pendiente posterior.** NO forma parte de los tres bloques principales de 8C. Se documenta aquí como diseño previsto, pero **no se implementa antes** de tener HTML operativo + HTML limpieza + Sheet de resguardo funcionando y validados.

### Objetivo

Que una reserva cargada **con poca anticipación** no dependa de que alguien mire el calendario para enterarse. Si se confirma una reserva cuyo check-in es inminente (dentro de la próxima semana), el equipo operativo y Jennifer reciben un aviso activo.

### Regla propuesta

- **Disparador:** después de `confirmar_reserva` **OK** en el flujo de 8B (el mismo punto de extensión post-confirmación), evaluar la fecha de check-in de la reserva recién confirmada.
- **Condición:** si `fecha_checkin` está entre **hoy y hoy + 7 días inclusive**, enviar una **notificación interna** al equipo operativo y a Jennifer.
- **Origen del disparo:** la alerta sale **desde el evento de confirmación**, NO desde la regeneración manual ni desde abrir el HTML. Esto es deliberado: evita spam (abrir el calendario o regenerar el resguardo no debe re-disparar alertas de reservas ya avisadas).
- **Una alerta por confirmación:** se dispara una vez, en el momento de confirmar. No hay re-evaluación periódica (sin cron, coherente con el resto de 8C).
- **No tocar schema** en esta etapa. La condición se evalúa con datos que ya devuelve el flujo (la `fecha_checkin` de la reserva confirmada).

### Qué queda por decidir al implementar (no ahora)

- **Canal de la notificación:** dependerá de qué se decida para mensajería interna (correlacionado con la decisión pendiente de WhatsApp/Telegram del proyecto, hoy sin resolver). Mientras tanto podría ser un canal simple (ej. email interno o el canal que el equipo ya use). Se define al construir el bloque 4.
- **Contenido del mensaje a Jennifer vs equipo operativo:** Jennifer recibe la versión sin datos comerciales (mismo criterio que el calendario de limpieza); el equipo operativo puede recibir más contexto. Se especifica al implementar.
- **Umbral configurable:** los 7 días podrían quedar fijos o leerse de `configuracion_general`; se decide al implementar (sin cambiar schema, usando una clave de config existente o el valor fijo).

### Por qué queda para después

Los tres bloques principales resuelven el problema central (ver el estado de ocupación y coordinar limpieza). La alerta es una **mejora de robustez operativa** sobre eso, no un prerequisito. Construirla antes sería invertir el orden de prioridad. Se aborda recién cuando los tres calendarios estén estables.

## 10. Qué NO se hace en 8C (límites)

- No se crean ni editan bloqueos (es 8D). 8C solo los muestra.
- No se muestran pre-reservas vigentes (decisión de Franco).
- No se toca schema canónico ni funciones SQL.
- No se usa Apps Script.
- No se usa cron/polling como primera opción.
- No se construye barra continua tipo Gantt (Opción B) — futuro.
- No se avanza a frontend público, bot, MercadoPago real ni integraciones externas.
- No se usan DEV con datos reales ni se mezcla TEST con operación real.

---

## 11. Decisiones registradas (D-8C-01 …)

| ID | Decisión |
|---|---|
| D-8C-01 | 8C = capa de presentación de solo lectura sobre vistas existentes; Supabase es la fuente de verdad; no se toca schema |
| D-8C-02 | Dos calendarios separados con dos contratos de visualización: operativo (comercial) y limpieza (Jennifer) |
| D-8C-03 | Operativo: `vista_disponibilidad` (grilla/estado) × `vista_calendario` (detalle), cruzadas por `id_reserva_activa = id_reserva` |
| D-8C-04 | Operativo: 120 días autodesplazantes; muestra reservas confirmadas/activas + bloqueos; **no** pre-reservas |
| D-8C-05 | Operativo muestra montos (total + saldo), pagado/pendiente, huésped, personas, horarios check-in/out, teléfono |
| D-8C-06 | Limpieza: `vista_limpieza_semana`, 7 días; muestra cabaña/fecha/movimiento/hora/personas/teléfono/mascotas/notas; **no** montos. DNI excluido a futuro |
| D-8C-06b | Teléfono y notas en limpieza = **decisión operativa explícita** (Jennifer coordina check-in/out y limpieza). Regla de carga: las notas visibles para limpieza solo llevan info operativa; **nunca** montos, señas, descuentos, acuerdos comerciales, conflictos, datos financieros/sensibles. Es disciplina de carga (8B), no control técnico; no cambia schema |
| D-8C-07 | Formato principal = HTML servido por n8n Cloud + Basic Auth, render al vuelo (sin estado materializado); dos endpoints separados |
| D-8C-08 | Formato de resguardo = Google Sheet repintado vía API de Google Sheets (sin Apps Script), prioridad menor |
| D-8C-09 | Orden de construcción: 1) HTML operativo, 2) HTML limpieza, 3) Sheet resguardo |
| D-8C-10 | Paleta y prioridad de pintado: rojo > gris (bloqueo) > verde (ocupación) > blanco (libre) |
| D-8C-11 | **Regla única de rojo:** rojo = día con dos eventos de transición — checkout de una reserva + checkin de **otra** (incluido recambio pegado, mismo día) **o** borde de bloqueo + movimiento de reserva. No existe "verde corrido" pasando por un día de recambio (corrección v1.1) |
| D-8C-12 | Verde = ocupación de un solo huésped, incluido primer día (solo entra) y último día (solo sale, sin recambio). El verde del día de salida es **convención visual**, NO altera el modelo |
| D-8C-12b | **Invariante técnica:** `fecha_in` inclusive / `fecha_out` exclusive (modelo `[)`) se mantiene intacto. 8C solo decide colores; no toca disponibilidad, motor ni semántica de ocupación. `checkout_disponible` (motor) y verde-del-día-de-salida (visual) conviven sin contradicción |
| D-8C-13 | Gris = todos los días del bloqueo (`fecha_desde <= día < fecha_hasta`), salvo días-borde que caigan en rojo |
| D-8C-13b | **Bloqueos:** específico por cabaña pinta solo esa cabaña; bloqueo total (`id_cabana IS NULL`) se expande a las 5 cabañas vía predicado (`id_cabana = cabaña OR id_cabana IS NULL`); fin de bloqueo es exclusive (`fecha_hasta` no se pinta); borde de bloqueo + movimiento → rojo |
| D-8C-14 | El color se calcula en la capa de presentación combinando ocupación + recambio + bloqueo; no se lee 1:1 del campo `estado` |
| D-8C-14b | **Render (v1.3):** detección de salida incluye estados `confirmada`/`activa`/`completada` (como `reserva_saliente` de `vista_calendario_semanal`); bloqueo se evalúa con `EXISTS` filtrando `activo = true`, sin asumir unicidad por celda (los totales `id_cabana IS NULL` no están en el EXCLUDE); motivo de celda gris = `bloqueos.motivo` (+ `descripcion` opcional), nunca comercial |
| D-8C-15 | Layout heredado del Excel: grilla por mes, días en columnas, cabañas en bloques de 3 filas (huésped·personas·horario / teléfono / pagado-pendiente); orden Bamboo, Madre Selva, Arrebol, Guatemala, Tokio |
| D-8C-16 | Estadías multi-día = Opción A (texto una vez al inicio, días siguientes verdes sin repetir). Opción B (barra Gantt) = futuro |
| D-8C-17 | Celda roja bietápica: orden de lectura sale→entra; los datos comerciales (pago, teléfono) son los del huésped que ENTRA |
| D-8C-18 | Actualización = regeneración a demanda (canónica, lee fuente de verdad) + disparo post-`confirmar_reserva`; **no** cron/polling como primera opción |
| D-8C-19 | El calendario refleja reservas/bloqueos ya existentes (la regeneración lee el rango completo), no solo eventos futuros |
| D-8C-19b | **Sheet de resguardo muestra "última regeneración"** (fecha/hora ISO 8601, TZ Buenos Aires) de forma visible, para no decidir sobre una copia vieja |
| D-8C-20 | Acceso: **dos URLs separadas** con **dos Basic Auth distintos**, **contraseñas fuertes**, **sin credenciales embebidas en la URL**; separación física de públicos; link simple para Jennifer (sin cuenta Google) |
| D-8C-21 | **Alerta por reserva próxima = Bloque 4 opcional / 8C-bis, posterior** a los 3 bloques principales. Disparo desde `confirmar_reserva` OK (no desde regeneración ni desde abrir HTML, para evitar spam) si `fecha_checkin` ∈ [hoy, hoy+7] inclusive → notificación interna a equipo operativo y Jennifer. No toca schema. Canal y detalles se definen al implementar |

---

## 12. Estado y próximo paso

**Estado: DISEÑO APROBADO (v1.2).** Sobre la v1.1 aprobada por Franco se incorporaron dos agregados menores:

1. **Regla de carga de notas en limpieza** (6.2.1): teléfono y notas para Jennifer son decisión operativa explícita; las notas visibles solo llevan información operativa, nunca datos comerciales/financieros/sensibles. Disciplina de carga, sin cambio de schema.
2. **Alerta por reserva próxima** (9bis): documentada como **Bloque 4 opcional / 8C-bis posterior** a los tres bloques principales. Dispara desde `confirmar_reserva` OK si el check-in cae en `[hoy, hoy+7]`, notificando al equipo y a Jennifer; nunca desde regeneración ni desde abrir el HTML (anti-spam). No toca schema.

Historial de correcciones de la v1.1 (ya incorporadas): regla única de color, `fecha_out` exclusive como invariante, sección de bloqueos, "última regeneración" visible en el Sheet, seguridad endurecida.

**Próximo paso: implementación por bloques**, en el orden D-8C-09:

1. **HTML operativo en TEST** ← empezamos por acá.
2. HTML limpieza en TEST.
3. Sheet de resguardo en TEST.
4. (Posterior, opcional) 8C-bis alerta por reserva próxima.

Cada bloque se valida en TEST antes de cualquier smoke en OPS. El cierre formal de la etapa quedará en `8C_CIERRE.md`, con el formato de `8B_CIERRE.md`.

*Fin del documento de diseño de 8C (v1.3 — aprobado, con verificación TEST realizada y precisiones de render registradas).*
