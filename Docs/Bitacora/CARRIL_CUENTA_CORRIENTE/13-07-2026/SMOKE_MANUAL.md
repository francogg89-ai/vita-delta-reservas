# SMOKE MANUAL — ¿una persona descubre que puede deslizar las tablas?

**Por qué existe.** Es la decisión 2 de Franco en SB-UI-6: *"no tocar `DataTable` todavía; agregar un
smoke manual explícito para comprobar si una persona descubre que puede deslizar las tablas en
mobile."* Esto **no se puede automatizar**: la pregunta no es si la tabla scrollea (scrollea: está
medido), sino si un ser humano **se da cuenta** de que puede.

## Lo que ya está medido (no hace falta re-medirlo)

En un teléfono emulado real (375px, touch, `isMobile`), sobre la tabla *Gastos congelados* con el
fixture **F20**:

| señal | estado |
|---|---|
| la tabla scrollea | **sí** — 764px ocultos (72% de la tabla) |
| barra de scroll visible en reposo | **no** — 2px, y en touch es *overlay*: solo aparece mientras se desliza |
| sombra o gradiente en el borde | **ninguna** |
| fade / mask en el borde derecho | **ninguno** |
| aviso textual en la pantalla | **ninguno** |
| última columna | queda **cortada al medio** ← única pista, y es débil |

**La descubribilidad depende enteramente de que la persona vea una columna cortada y adivine.**

## Procedimiento

**Duración:** ~4 minutos por persona. **Mínimo: 3 personas.** Al menos una que no sea Franco ni
Rodrigo (alguien que no haya visto la pantalla antes; Vicky es ideal).

### Preparación

1. `npm run qa` (ojo: comparte el puerto 5173 con `npm run dev` — bajá el otro primero).
2. Abrir en un **teléfono real**, no en el emulador del navegador. La barra de scroll del desktop
   es visible y arruina la prueba.
3. En la barra QA de abajo: **A30 = `F20 · peor caso visual (gastos densos)`**.
4. Abrir el **Detalle fino**.
5. Desplazarse hasta **Gastos congelados**.
6. **No explicar nada.** No decir la palabra "deslizar", "scroll" ni "tabla ancha".

### La prueba

Entregar el teléfono y decir exactamente esto, sin agregar nada:

> *"Necesito saber cuánto salió la reparación de la bomba y quién la pagó."*

Los dos datos están en columnas ocultas (**Monto** e **Incidencia**), a 764px a la derecha.

**Arrancar un cronómetro.** Registrar:

| qué observar | cómo se registra |
|---|---|
| ¿deslizó la tabla horizontalmente, sin ayuda? | SÍ / NO |
| tiempo hasta el primer intento de deslizar | segundos (o `—` si nunca lo intentó) |
| ¿qué hizo ANTES de deslizar? | (ej: rotó el teléfono, hizo zoom out, scrolleó vertical buscando, se quedó quieto) |
| ¿dijo en voz alta que "falta información"? | SÍ / NO |
| a los 60s sin éxito: preguntar *"¿ves todo lo que necesitás?"* | qué contesta |
| a los 90s: **abortar** y anotar `NO DESCUBRIÓ` | — |

### Criterio de resultado

- **PASA** si **3 de 3** deslizan sin ayuda en **menos de 20 segundos**.
- **FALLA** si alguien no descubre el deslizamiento, o tarda más de 20s, o resuelve la tarea
  rotando el teléfono / haciendo zoom (eso significa que la tabla no comunica que se desliza: la
  persona buscó una salida alternativa).

### Si FALLA

No tocar `DataTable` por reflejo. El resultado del smoke se suma al **HALLAZGO H-2** (filas
inutilizables en mobile, ya medido: 94% de la altura de la primera fila es espacio vacío) y va
**junto** a la propuesta separada, que es donde se decide qué hacer.

Deslizar bien una tabla de 9 columnas en 375px sigue siendo mala experiencia **aunque la persona
descubra que puede hacerlo**: descubrir el gesto no arregla que el 72% del contenido esté fuera de
vista. El smoke sirve para saber si el problema es **uno** (la tabla es incómoda) o **dos** (la
tabla es incómoda *y además* la gente ni siquiera sabe que puede deslizarla).

## Registro

```
Fecha:              ____________
Persona:            ____________   (rol: ____________)
Teléfono / browser: ____________

  ¿deslizó sin ayuda?        SÍ / NO
  tiempo al primer intento:  ______ s
  qué hizo antes:            _______________________________________
  ¿dijo que faltaba info?    SÍ / NO
  resolvió la tarea:         SÍ / NO   en ______ s

Observaciones:
_____________________________________________________________________
```
