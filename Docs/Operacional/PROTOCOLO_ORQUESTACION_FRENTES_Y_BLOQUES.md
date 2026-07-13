# Protocolo de Orquestación de Frentes, Etapas y Bloques

**Versión:** 1.0  
**Fecha:** 2026-07-13  
**Estado:** autoridad operativa transversal del proyecto  
**Ámbito:** Claude, ChatGPT/Codex y cualquier agente que trabaje sobre el repositorio

**Objetivo:** organizar proyectos técnicos largos en unidades de trabajo controlables, reducir pérdida de contexto, evitar expansión silenciosa de alcance y garantizar traspasos precisos entre conversaciones y agentes.

## 1. Jerarquía única

Usar siempre esta jerarquía:

1. **Proyecto:** producto o sistema completo. Ejemplo: `Vita Delta Reservas`.
2. **Frente o carril:** capacidad funcional grande con principio y fin. Ejemplo: `Motor de Precios v2`.
3. **Etapa:** agrupación opcional de bloques por naturaleza. Ejemplo: diagnóstico, backend, exposición, frontend, validación, consolidación.
4. **Bloque:** unidad atómica de trabajo con un objetivo verificable. Ejemplo: `B3 — funciones del motor`.
5. **Sub-bloque:** división excepcional de un bloque cuando existe un límite técnico real. Ejemplo: `B3-A — cálculo base`; `B3-B — reglas de venta`.
6. **Conversación:** contenedor de trabajo. Regla por defecto: una conversación trabaja un solo bloque o sub-bloque.

No usar “proyecto”, “etapa”, “bloque” y “conversación” como sinónimos.

## 2. Regla central

Todo frente debe tener:

- un roadmap vivo;
- bloques con alcance explícito;
- un kickoff autosuficiente por bloque;
- criterios de DONE verificables;
- reglas de freno;
- un cierre formal;
- un kickoff del bloque siguiente generado desde el estado real comprobado.

No se inicia implementación de un frente directamente desde una idea informal.

## 3. Estados obligatorios

No usar solamente “pendiente”, “en curso” o “cerrado”. Registrar cuatro dimensiones:

- **Estado funcional:** PROPUESTO / PLANIFICADO / EN CURSO / PAUSADO / BLOQUEADO / CERRADO.
- **Entorno máximo validado:** REPO / HARNESS / DEV / TEST / OPS.
- **Estado documental:** NO DOCUMENTADO / DOCUMENTADO / CANONIZADO.
- **Promoción:** NO APLICA / PENDIENTE / PROMOVIDO.

Formato recomendado:

> **Estado:** CERRADO · validado en TEST · no promovido a OPS · canonización pendiente.

Un bloque no puede declararse “cerrado” sin indicar entorno y estado documental.

## 4. Artefactos mínimos

### 4.1 Roadmap del frente

Documento vivo que contiene:

- objetivo final del frente;
- problema que resuelve;
- dependencias;
- decisiones congeladas;
- mapa completo de bloques;
- estado de cada bloque;
- riesgos transversales;
- ideas diferidas;
- criterio de cierre del frente completo.

El roadmap no contiene toda la ejecución histórica. Es un mapa de navegación.

### 4.2 Kickoff de bloque

Debe ser autosuficiente y contener:

1. identificación del proyecto, frente y bloque;
2. objetivo único del bloque;
3. estado real comprobado;
4. autoridades que deben consultarse;
5. decisiones que no se reabren;
6. alcance incluido;
7. alcance excluido;
8. dependencias y precondiciones;
9. contratos afectados;
10. entornos permitidos y prohibidos;
11. orden de trabajo;
12. entregables;
13. plan de validación;
14. criterios de DONE;
15. reglas de freno;
16. política de commits y despliegues;
17. archivos o rutas que la conversación nueva debe inspeccionar;
18. bloque siguiente previsto, solo como referencia.

El kickoff debe basarse en repo fresco, objetos vivos o fuentes autoritativas. No puede basarse únicamente en recuerdos del chat anterior.

### 4.3 Bitácora de ejecución

Es obligatoria cuando el bloque tiene escrituras, múltiples pruebas, incidentes o decisiones emergentes. Debe registrar:

- acciones realizadas;
- evidencia obtenida;
- comandos o artefactos usados;
- resultados de pruebas;
- residuos o mutaciones;
- desvíos;
- decisiones nuevas;
- pendientes derivados.

### 4.4 Cierre del bloque

Debe contener:

- objetivo original;
- alcance ejecutado y no ejecutado;
- estado final comprobado;
- artefactos creados o modificados;
- evidencias;
- pruebas y resultados;
- fingerprints o contratos fijados cuando corresponda;
- decisiones acuñadas;
- lecciones aprendidas;
- riesgos residuales;
- pendientes derivados;
- estado de cada entorno;
- commits reales;
- veredicto de DONE;
- actualización requerida de documentos satélite;
- kickoff del próximo bloque.

### 4.5 Checkpoint de decisión

Se crea solo cuando el bloque no puede continuar de forma segura. Debe incluir:

- hallazgo;
- evidencia;
- impacto;
- opciones reales;
- recomendación;
- qué queda congelado mientras se decide;
- punto exacto desde el cual reanudar.

## 5. Ciclo normal de un bloque

1. Verificar estado real.
2. Reconciliar kickoff contra repo y sistemas vivos.
3. Confirmar alcance y exclusiones.
4. Diseñar antes de implementar.
5. Ejecutar un sub-bloque por vez.
6. Validar antes de avanzar.
7. Registrar desvíos y decisiones.
8. Auditar el resultado completo.
9. Cerrar formalmente.
10. Generar kickoff del siguiente bloque.
11. Frenar.

Claude no debe continuar automáticamente al bloque siguiente aunque parezca obvio.

## 6. Protocolo ante complicaciones o ideas nuevas

Toda novedad se clasifica antes de implementarse.

### Clase A — Incidencia local absorbible

Condiciones:

- pertenece al objetivo actual;
- no cambia contratos públicos;
- no agrega una capa nueva;
- no modifica decisiones cerradas;
- puede validarse dentro del plan existente.

Acción: resolver dentro del bloque, documentar en la bitácora y verificar que no altere el DONE.

### Clase B — Hallazgo bloqueante

Condiciones:

- contradice una premisa del kickoff;
- falta una autoridad confiable;
- el repo y el vivo divergen materialmente;
- existe riesgo de escribir en el entorno incorrecto;
- no puede validarse sin una decisión.

Acción: frenar, producir checkpoint de decisión y no improvisar una salida.

### Clase C — Mejora valiosa pero no necesaria

Condiciones:

- aporta valor;
- no es requisito para cerrar el bloque;
- abre trabajo adicional o una variante comercial/técnica.

Acción: registrar en el roadmap como bloque futuro o backlog. No implementarla dentro del bloque actual.

### Clase D — Cambio de alcance

Condiciones:

- cambia una firma, contrato o fuente de verdad;
- agrega objetos de base, workflows, gateway, UI o entorno no previstos;
- afecta más de una capa que el kickoff no contemplaba;
- cambia el criterio de DONE;
- reabre una decisión congelada.

Acción: frenar. Proponer revisión del roadmap o un bloque nuevo. Esperar aprobación explícita antes de continuar.

### Clase E — Incidente urgente de operación

Acción: separar el incidente del frente normal. Crear un bloque de hotfix con alcance mínimo, rollback, pruebas y cierre propio. No mezclarlo silenciosamente con el bloque en curso.

## 7. Reglas de freno obligatorias

Claude debe frenar cuando ocurra cualquiera de estos casos:

- el siguiente paso pertenece a otro bloque;
- hay que escribir en OPS y el kickoff no lo autoriza;
- se requiere una decisión de negocio no resuelta;
- una fuente autoritativa contradice otra;
- se propone reabrir una decisión cerrada;
- aparece un cambio de contrato;
- el plan requiere una operación destructiva no prevista;
- la evidencia no permite afirmar el resultado;
- el contexto de la conversación ya no permite un traspaso confiable;
- el bloque alcanzó su criterio de DONE.

Frenar no significa abandonar. Significa entregar estado, evidencia y un punto de continuación preciso.

## 8. Criterio para separar conversaciones

Abrir conversación nueva cuando:

- comienza un bloque diferente;
- cambia la capa principal de trabajo, por ejemplo SQL a gateway o gateway a frontend;
- cambia el entorno de ejecución, especialmente TEST a OPS;
- se cerró un contrato y comienza su implementación;
- se inicia promoción o canonización;
- aparece un hotfix independiente;
- el contexto acumulado hace difícil distinguir hechos, hipótesis y decisiones.

No abrir conversación nueva por un ajuste local dentro del mismo bloque.

## 9. Regla de traspaso

El cierre de una conversación debe producir un kickoff que permita a otra instancia continuar sin leer el chat anterior.

El kickoff nuevo debe distinguir:

- **comprobado**;
- **inferido**;
- **decidido**;
- **pendiente**;
- **fuera de alcance**.

Debe incluir rutas y nombres exactos, pero exigir igualmente inspección de repo fresco y estado vivo. No debe copiar historia extensa que no afecte el siguiente bloque.

## 10. Regla de autoridad

Orden general de autoridad, adaptable al frente:

1. estado vivo del entorno correspondiente;
2. repo fresco en la rama autorizada;
3. definiciones extraídas del sistema vivo;
4. canónico vigente;
5. cierre formal del bloque anterior;
6. decisiones no reabrir;
7. estado actual y roadmap;
8. bitácoras históricas;
9. mensajes de conversaciones anteriores.

Cuando dos fuentes divergen, no elegir silenciosamente. Explicar la divergencia y determinar cuál es autoridad para ese objeto.

## 11. Regla de documentación satélite

Cada cierre debe indicar expresamente cuáles de estos documentos requieren actualización:

- estado actual;
- roadmap del frente;
- decisiones no reabrir;
- lecciones aprendidas;
- pendientes preproducción;
- README;
- canónico;
- bootstrap;
- inventarios o fingerprints;
- cierre del bloque.

No actualizar todos por reflejo. Actualizar solamente los afectados y evitar duplicar el mismo detalle en varios archivos.

## 12. Integración obligatoria con agentes

Este protocolo es la fuente canónica completa. No debe copiarse íntegramente en archivos de instrucciones de agentes, porque eso genera duplicación, deriva y consumo innecesario de contexto.

La integración se realiza mediante dos puertas breves:

- **Claude Code:** `.claude/rules/00-orquestacion.md`, cargada de forma incondicional al iniciar cada sesión.
- **ChatGPT/Codex y otros agentes compatibles:** `AGENTS.md`, ubicado en la raíz del repositorio.

Ambas puertas deben obligar a:

1. consultar este protocolo al diseñar o abrir un frente, etapa, bloque o sub-bloque;
2. releer sus reglas de estados, freno, cierre, autoridad y traspaso antes de declarar DONE;
3. no avanzar automáticamente al bloque siguiente;
4. usar el kickoff del bloque como contexto específico, sin reemplazar la verificación del repo y los sistemas vivos.

Si este protocolo cambia, deben revisarse las dos puertas de integración para confirmar que siguen apuntando a esta ruta y no contradicen su contenido.

## 13. Comandos breves para iniciar cada modo

### A. Diseñar un frente nuevo

```text
MODO: DISEÑAR FRENTE

Proyecto: [nombre]
Frente/carril: [nombre]
Objetivo de negocio: [resultado buscado]
Restricciones conocidas: [lista]
Estado actual conocido: [resumen]

No implementes todavía. Inspeccioná las fuentes autoritativas disponibles y entregá:
1. diagnóstico del estado real;
2. límites del frente;
3. dependencias y riesgos;
4. decisiones que deben congelarse o confirmarse;
5. roadmap completo de bloques, cada uno con objetivo, alcance, entregables, validación y DONE;
6. puntos exactos donde corresponde abrir una conversación nueva;
7. reglas para absorber, diferir o separar complicaciones e ideas nuevas;
8. kickoff autosuficiente del primer bloque;
9. archivos que deben subirse o rutas que deben inspeccionarse.

Frená después del kickoff. No empieces el primer bloque.
```

### B. Abrir un bloque

```text
MODO: ABRIR BLOQUE

Trabajá exclusivamente sobre el kickoff adjunto del bloque [ID y nombre].

Antes de proponer cambios:
1. verificá repo fresco, rama, HEAD y working tree;
2. verificá fuentes vivas autorizadas;
3. reconciliá el kickoff con el estado real;
4. informá divergencias;
5. fijá alcance incluido, excluido, entorno permitido y DONE.

Después ejecutá un sub-bloque por vez. No avances al bloque siguiente. Toda novedad debe clasificarse según el protocolo de desvíos. Frená cuando el bloque llegue a DONE o aparezca una condición obligatoria de freno.
```

### C. Evaluar una complicación o idea nueva

```text
MODO: CONTROL DE DESVÍO

Durante el bloque [ID] apareció esta novedad:
[describir hallazgo, problema o idea]

No la implementes todavía. Clasificala como:
A) incidencia local absorbible;
B) hallazgo bloqueante;
C) mejora diferible;
D) cambio de alcance;
E) incidente urgente independiente.

Entregá evidencia, impacto sobre alcance/contratos/DONE, recomendación y acción concreta: continuar, registrar para después, revisar roadmap, crear bloque nuevo o emitir checkpoint de decisión.
```

### D. Cerrar y traspasar

```text
MODO: CERRAR Y TRASPASAR

Auditá el bloque [ID y nombre] contra su kickoff y evidencia real.

Entregá:
1. veredicto de DONE;
2. estado final por entorno;
3. alcance ejecutado y no ejecutado;
4. artefactos y commits reales;
5. pruebas, resultados y evidencia;
6. decisiones y lecciones nuevas;
7. riesgos residuales y pendientes;
8. satélites que deben actualizarse;
9. roadmap actualizado;
10. cierre formal del bloque;
11. kickoff autosuficiente del siguiente bloque;
12. lista exacta de archivos/rutas para la conversación nueva.

El kickoff debe basarse en el estado real comprobado, no solo en el chat. Frená al terminar. No empieces el bloque siguiente.
```

## 14. Aplicación al Motor de Precios v2

- **Proyecto:** Vita Delta Reservas.
- **Frente:** Motor de Precios v2.
- **Bloques:** B1, B1.1, B2A, B2B, B3, B3.1, B4, B5, B6, B7.
- **Conversación recomendada:** una por bloque.
- **Separaciones especialmente obligatorias:**
  - diagnóstico read-only → DDL;
  - backend → exposición pública;
  - gateway → portal;
  - TEST → OPS;
  - implementación → canonización/cierre.

Ejemplo de estado correcto:

> B3 — CERRADO · funciones verdes en TEST · no expuestas públicamente · OPS intacto · canónico pendiente para B7.

Ejemplo ante idea nueva durante B3:

> “Agregar override manual de capacidad” cambia contrato y agrega una capacidad administrativa. No se absorbe en B3: se registra como B3.1, con kickoff y DONE propios.

## 15. Resultado operativo esperado

Con este protocolo, Franco solo necesita:

1. usar el comando **DISEÑAR FRENTE** al iniciar algo grande;
2. abrir cada conversación con el kickoff generado al cierre anterior;
3. usar **CONTROL DE DESVÍO** cuando aparezca una complicación o idea nueva;
4. pedir **CERRAR Y TRASPASAR** al terminar cada bloque.

El detalle largo queda en el repositorio. Las conversaciones reciben únicamente el contexto necesario para el bloque actual.
