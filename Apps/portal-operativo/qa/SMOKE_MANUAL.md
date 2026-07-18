# SMOKE MANUAL — ¿una persona resuelve la tarea en la card mobile, sin pelearse con la pantalla?

**Por qué existe.** En SB-UI-6.1, la representación mobile de *Gastos congelados* dejó de ser una
tabla de 9 columnas (que en 375px ocultaba el 72% del contenido y no comunicaba que se deslizaba) y
pasó a ser **una card vertical por gasto** (la tabla se conserva en tablet/desktop). El harness ya
mide que la card es compacta, exclusiva por breakpoint, con una card por gasto y sin desborde
horizontal. Lo que **no se puede automatizar** es si un ser humano, con la card, **completa una
tarea real** sin recurrir a scroll horizontal, zoom o rotación, y sin confundir *Pagador* con
*Incidencia*. Eso es esta prueba.

> **Estado: PENDIENTE de ejecución humana.** No está corrida. No la declares verde: hay que hacerla
> con personas y teléfono real.

## Lo que ya está medido (no hace falta re-medirlo)

En un teléfono emulado real (375px, touch, `isMobile`), sobre *Gastos congelados* con el fixture
**F20** (peor caso: gastos con todos los opcionales, etiquetas y comentarios largos):

| señal | estado (aserción dura en `qa:responsive`) |
|---|---|
| representación mobile | **card** (una por gasto), tabla **no** visible — exclusividad `tablaVis !== cardsVis` |
| una card por gasto | **sí** — cantidad e IDs de card == filas fuente, sin faltantes ni duplicados |
| desperdicio vertical de la peor card | por debajo del umbral (vacío por **unión** de intervalos, no `bot−top`) |
| scroll horizontal de página | **no** — `documentElement.scrollWidth === clientWidth` en 375/768/1280 |
| ninguna card excede el viewport a lo ancho | **sí** |

Lo que la máquina **no** dice: si la persona *encuentra el dato* y *lo lee bien*.

## Procedimiento

**Duración:** ~4 minutos por persona. **Mínimo: 3 personas.** Al menos una que no sea Franco ni
Rodrigo (alguien que no haya visto la pantalla antes; Vicky es ideal).

### Preparación

1. `npm run qa` (ojo: comparte el puerto 5173 con `npm run dev` — bajá el otro primero).
2. Abrir en un **teléfono real**, no en el emulador del navegador.
3. En la barra QA de abajo: **A30 = `F20 · peor caso visual (gastos densos)`**.
4. Abrir el **Detalle fino** y desplazarse (vertical) hasta **Gastos congelados**.
5. **No explicar nada.** No decir "card", "deslizar", "Pagador" ni "Incidencia".

### La prueba

Entregar el teléfono y decir exactamente esto, sin agregar nada:

> *"Necesito saber cuánto salió la reparación de la bomba y quién la pagó."*

En F20 ese gasto es **#71 — «Reparación integral de la bomba de agua del muelle norte»**. La persona
tiene que hallar tres cosas en su card: el **gasto** (la etiqueta de la bomba), el **monto**, y el
**Pagador** (quién la pagó).

**Ojo con la trampa semántica:** en la card hay una fila **Pagador** (quién puso la plata) y una fila
**Incidencia** (a quién se le **imputó** el gasto en el reparto — en F20 el #71 incidió en Rodrigo).
No son lo mismo. La pregunta apunta a **Pagador**. Leer Incidencia como si fuera el pagador es un
error y cuenta como tal.

**Arrancar un cronómetro.** Registrar:

| qué observar | cómo se registra |
|---|---|
| ¿encontró la card del gasto de la bomba? | SÍ / NO — tiempo: ______ s |
| ¿leyó el **monto**? | SÍ / NO |
| ¿identificó al **Pagador** (no la Incidencia)? | SÍ / NO — ¿qué valor dijo? ____________ |
| ¿necesitó **scroll horizontal**? | SÍ / NO |
| ¿necesitó **zoom**? | SÍ / NO |
| ¿necesitó **rotar** el teléfono? | SÍ / NO |
| a los 90s sin éxito: **abortar** y anotar `NO RESOLVIÓ` | — |

### Criterio de resultado

- **PASA** si **3 de 3** completan la tarea (gasto + monto + Pagador correcto) **sin** scroll
  horizontal, **sin** zoom y **sin** rotar el teléfono, y **distinguen Pagador de Incidencia**.
- **FALLA** si alguien no encuentra el dato, o lo resuelve recurriendo a scroll horizontal / zoom /
  rotación (eso indica que la card no le está mostrando lo que necesita en el ancho disponible), o
  **confunde Pagador con Incidencia** (eso indica que el rotulado no separa bien los dos conceptos).

### Si FALLA

No tocar `DataTable` ni rehacer la card por reflejo. El resultado se registra y va **junto** a la
decisión de un sub-bloque separado. Distinguir dos modos de falla:

- **no encuentra / necesita zoom-rotación** → problema de densidad o jerarquía visual de la card.
- **confunde Pagador con Incidencia** → problema de rotulado / redacción de esas dos filas.

Son arreglos distintos; anotar cuál se observó.

## Registro

```
Fecha:              ____________
Persona:            ____________   (rol: ____________)
Teléfono / browser: ____________

  ¿encontró la card de la bomba?   SÍ / NO    en ______ s
  ¿leyó el monto?                  SÍ / NO
  ¿Pagador correcto?               SÍ / NO    dijo: ____________
  ¿usó scroll horizontal?          SÍ / NO
  ¿usó zoom?                       SÍ / NO
  ¿rotó el teléfono?               SÍ / NO
  distinguió Pagador de Incidencia SÍ / NO
  resolvió la tarea:               SÍ / NO    en ______ s

Observaciones:
_____________________________________________________________________
```
