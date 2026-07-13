# Protocolo de Orquestación de Frentes, Etapas y Bloques

**Versión:** 1.1  
**Fecha:** 2026-07-13  
**Estado:** autoridad operativa transversal del proyecto  
**Ámbito:** Claude, Franco, ChatGPT/Codex y cualquier agente que trabaje sobre el repositorio

**Objetivo:** organizar proyectos técnicos largos en unidades controlables, preservar la separación entre construcción y auditoría, evitar expansión silenciosa de alcance y garantizar traspasos verificables entre conversaciones, agentes y entornos.

## 1. Separación obligatoria de roles

Los roles no son intercambiables dentro del circuito normal.

### 1.1 Claude — diseñador y constructor

Claude es el agente principal de producción técnica. Le corresponde:

- inspeccionar repo y fuentes autorizadas;
- diagnosticar el estado real;
- diseñar frentes, etapas y bloques;
- proponer decisiones técnicas;
- crear y modificar archivos del repositorio;
- generar SQL, workflows, código, documentación, harnesses y artefactos;
- ejecutar validaciones locales o read-only disponibles;
- preparar paquetes de ejecución para Franco;
- preparar el paquete de auditoría para ChatGPT;
- corregir hallazgos de auditoría;
- producir el cierre formal y el kickoff siguiente cuando el bloque quede aprobado.

Claude puede hacer auto-revisión, pero esa revisión no reemplaza la auditoría independiente.

### 1.2 Franco — decisor y ejecutor de escrituras externas

Franco conserva la autoridad de negocio y la ejecución de cambios sobre sistemas externos. Le corresponde:

- aprobar decisiones de negocio y cambios de alcance;
- autorizar entornos y promociones;
- ejecutar escrituras en Supabase, n8n, Vercel, GitHub y otros servicios;
- devolver a Claude y ChatGPT la evidencia real de esas ejecuciones;
- aceptar o rechazar excepciones, riesgos residuales y cierres.

Ningún agente debe presumir autorización de escritura externa.

### 1.3 ChatGPT/Codex — auditor técnico independiente

ChatGPT/Codex no es el constructor principal. Le corresponde:

- auditar el prompt, respuesta y artefactos de Claude;
- verificar afirmaciones contra repo fresco, fuentes vivas y evidencia;
- revisar contratos, seguridad, compatibilidad, pruebas, alcance y regresiones;
- distinguir comprobado, inferido, decidido, pendiente y fuera de alcance;
- clasificar hallazgos por severidad;
- emitir un veredicto independiente;
- indicar correcciones y evidencias faltantes;
- auditar el cierre y el kickoff siguiente cuando Claude los produzca.

Dentro del circuito normal, ChatGPT/Codex no debe:

- diseñar la solución primaria en reemplazo de Claude;
- crear o modificar archivos de implementación del repositorio;
- aplicar migraciones, editar workflows o desplegar funciones;
- escribir en Supabase, n8n, Vercel, GitHub u otros entornos;
- corregir silenciosamente los artefactos auditados;
- actuar como autor y auditor final del mismo cambio.

Puede producir informes de auditoría, matrices de hallazgos, prompts de corrección, consultas read-only y harnesses aislados necesarios para validar una afirmación.

Solo una instrucción explícita de Franco que declare una excepción puntual puede alterar esta separación. La excepción debe quedar identificada y no se presume.

## 2. Jerarquía única

Usar siempre esta jerarquía:

1. **Proyecto:** producto o sistema completo. Ejemplo: `Vita Delta Reservas`.
2. **Frente o carril:** capacidad funcional grande con principio y fin. Ejemplo: `Motor de Precios v2`.
3. **Etapa:** agrupación opcional de bloques por naturaleza. Ejemplo: diagnóstico, backend, exposición, frontend, validación, consolidación.
4. **Bloque:** unidad atómica de trabajo con un objetivo verificable. Ejemplo: `B3 — funciones del motor`.
5. **Sub-bloque:** división excepcional de un bloque cuando existe un límite técnico real. Ejemplo: `B3-A — cálculo base`; `B3-B — reglas de venta`.
6. **Conversación de construcción:** conversación de Claude dedicada a un bloque o sub-bloque.
7. **Conversación de auditoría:** conversación separada de ChatGPT dedicada a auditar ese bloque.

No usar proyecto, etapa, bloque, conversación de construcción y conversación de auditoría como sinónimos.

## 3. Regla central

Todo frente debe tener:

- un roadmap vivo;
- bloques con alcance explícito;
- un kickoff autosuficiente por bloque;
- criterios de DONE verificables;
- reglas de freno;
- artefactos construidos por Claude;
- evidencia de las ejecuciones realizadas por Franco;
- un paquete de auditoría;
- un veredicto independiente de ChatGPT;
- un cierre formal posterior a la auditoría;
- un kickoff del bloque siguiente generado desde el estado real aprobado.

No se inicia implementación directamente desde una idea informal.

Un bloque no se considera formalmente cerrado solo porque Claude terminó de crear archivos. Debe completar el circuito construcción → ejecución autorizada → auditoría → corrección, cuando corresponda → cierre.

## 4. Estados obligatorios

No usar solamente pendiente, en curso o cerrado. Registrar cinco dimensiones:

- **Estado funcional:** PROPUESTO / PLANIFICADO / EN CONSTRUCCIÓN / EN AUDITORÍA / EN CORRECCIÓN / PAUSADO / BLOQUEADO / CERRADO.
- **Entorno máximo validado:** REPO / HARNESS / DEV / TEST / OPS.
- **Estado documental:** NO DOCUMENTADO / DOCUMENTADO / CANONIZADO.
- **Promoción:** NO APLICA / PENDIENTE / PROMOVIDO.
- **Auditoría:** NO INICIADA / EN CURSO / APROBADA / APROBADA CON OBSERVACIONES / REQUIERE CORRECCIONES / BLOQUEADA POR FALTA DE EVIDENCIA.

Formato recomendado:

> **Estado:** EN AUDITORÍA · validado en TEST · no promovido a OPS · documentado · auditoría en curso.

Formato de cierre:

> **Estado:** CERRADO · validado en TEST · no promovido a OPS · canonización pendiente · auditoría aprobada.

Un bloque no puede declararse cerrado sin indicar entorno, documentación, promoción y auditoría.

## 5. Artefactos mínimos

### 5.1 Roadmap del frente

Documento vivo que contiene:

- objetivo final del frente;
- problema que resuelve;
- dependencias;
- decisiones congeladas;
- mapa completo de bloques;
- estado multidimensional de cada bloque;
- riesgos transversales;
- ideas diferidas;
- criterio de cierre del frente completo.

El roadmap no reemplaza la bitácora ni debe acumular toda la historia.

### 5.2 Kickoff de construcción del bloque

Debe ser autosuficiente y contener:

1. proyecto, frente, etapa y bloque;
2. objetivo único;
3. estado real comprobado;
4. autoridades que deben consultarse;
5. decisiones que no se reabren;
6. alcance incluido;
7. alcance excluido;
8. dependencias y precondiciones;
9. contratos afectados;
10. entornos permitidos y prohibidos;
11. orden de trabajo;
12. entregables que Claude debe crear;
13. acciones externas que solo Franco puede ejecutar;
14. plan de validación;
15. criterios de DONE técnico;
16. criterios para pasar a auditoría;
17. reglas de freno;
18. política de commits y despliegues;
19. archivos o rutas que deben inspeccionarse;
20. bloque siguiente previsto, solo como referencia.

El kickoff debe basarse en repo fresco, objetos vivos o fuentes autoritativas. No puede basarse únicamente en recuerdos del chat anterior.

### 5.3 Bitácora de construcción y ejecución

Es obligatoria cuando el bloque tiene escrituras, múltiples pruebas, incidentes o decisiones emergentes. Debe registrar:

- acciones realizadas por Claude;
- archivos creados o modificados;
- comandos y artefactos usados;
- validaciones realizadas;
- acciones externas ejecutadas por Franco;
- evidencia y resultados;
- residuos o mutaciones;
- desvíos;
- decisiones nuevas;
- pendientes derivados.

Debe distinguir con claridad quién realizó cada acción.

### 5.4 Paquete de auditoría Claude → ChatGPT

Claude debe prepararlo al terminar la construcción. Debe contener:

1. kickoff vigente;
2. prompt recibido por Claude;
3. respuesta completa de Claude;
4. rama, HEAD y working tree;
5. commits y diff reales;
6. inventario exacto de archivos creados o modificados;
7. afirmaciones técnicas que se consideran comprobadas;
8. pruebas ejecutadas, resultados y evidencia cruda;
9. acciones externas ejecutadas por Franco;
10. estado por entorno;
11. contratos, fingerprints y conteos relevantes;
12. riesgos, residuos y pendientes;
13. aspectos no comprobados;
14. lista exacta de archivos y fuentes que ChatGPT debe auditar;
15. criterio de DONE contra el cual debe emitirse el veredicto.

Claude debe frenar después de producir este paquete. No debe generar el cierre formal como hecho consumado antes del veredicto.

### 5.5 Informe de auditoría ChatGPT → Claude

Debe contener:

- alcance auditado;
- evidencia consultada;
- afirmaciones comprobadas;
- afirmaciones no comprobadas o contradichas;
- hallazgos ordenados por severidad;
- impacto sobre contratos, alcance, entornos y DONE;
- correcciones requeridas;
- pruebas o evidencia faltante;
- archivos que deben volver a auditarse;
- veredicto.

Severidades:

- **CRÍTICO:** invalida el diseño, compromete integridad o puede afectar OPS.
- **ALTO:** incumple contrato, DONE o requisito esencial.
- **MEDIO:** defecto real no bloqueante para el núcleo, pero requiere corrección o registro.
- **BAJO:** precisión, mantenibilidad o documentación.
- **OBSERVACIÓN:** mejora o riesgo no demostrado.

Veredictos permitidos:

- **APROBADO**;
- **APROBADO CON OBSERVACIONES NO BLOQUEANTES**;
- **REQUIERE CORRECCIONES**;
- **BLOQUEADO POR FALTA DE EVIDENCIA**.

ChatGPT debe frenar después del veredicto. No debe implementar la corrección.

### 5.6 Cierre formal del bloque

Claude lo produce después de la auditoría aprobada o de una excepción explícita aceptada por Franco. Debe contener:

- objetivo original;
- alcance ejecutado y no ejecutado;
- estado final comprobado;
- artefactos creados o modificados;
- acciones ejecutadas por Franco;
- evidencias;
- pruebas y resultados;
- resultado de auditoría;
- hallazgos corregidos;
- observaciones no bloqueantes aceptadas;
- fingerprints o contratos fijados;
- decisiones acuñadas;
- lecciones aprendidas;
- riesgos residuales;
- pendientes derivados;
- estado de cada entorno;
- commits reales;
- veredicto de DONE;
- actualización requerida de documentos satélite;
- kickoff del próximo bloque.

ChatGPT puede auditar este cierre, pero no debe redactarlo como sustituto de Claude dentro del circuito normal.

### 5.7 Checkpoint de decisión

Se crea cuando el bloque no puede continuar de forma segura. Debe incluir:

- hallazgo;
- evidencia;
- impacto;
- opciones reales;
- recomendación de Claude;
- opinión de auditoría, si ya existe;
- qué queda congelado mientras se decide;
- punto exacto desde el cual reanudar.

## 6. Ciclo normal de un bloque

### Fase 0 — Diseño del frente

1. Claude inspecciona fuentes autoritativas.
2. Claude diseña roadmap y bloques.
3. Franco aprueba decisiones de negocio y alcance.
4. ChatGPT puede auditar el roadmap cuando Franco lo solicite.
5. Claude genera el kickoff del primer bloque y frena.

### Fase 1 — Apertura del bloque por Claude

1. Verificar repo fresco, rama, HEAD y working tree.
2. Reconciliar kickoff contra repo y sistemas vivos.
3. Confirmar alcance, exclusiones, entornos y DONE.
4. Informar divergencias.
5. Frenar si aparece una condición bloqueante.

### Fase 2 — Construcción por Claude

1. Diseñar antes de implementar.
2. Crear o modificar artefactos dentro del alcance.
3. Validar un sub-bloque por vez.
4. Registrar desvíos y decisiones.
5. Preparar acciones externas para Franco sin ejecutarlas.

### Fase 3 — Ejecución externa por Franco

1. Franco revisa y ejecuta las escrituras autorizadas.
2. Devuelve outputs, errores, capturas, exports o resultados.
3. Claude incorpora esa evidencia a la bitácora.
4. Ningún agente presume éxito sin evidencia.

### Fase 4 — Auto-verificación y paquete de auditoría

1. Claude verifica el resultado contra el kickoff.
2. Declara lo comprobado y lo no comprobado.
3. Arma el paquete de auditoría.
4. Frena.

### Fase 5 — Auditoría independiente por ChatGPT

1. ChatGPT abre una conversación separada.
2. Inspecciona repo fresco y evidencia real.
3. Contrasta afirmaciones de Claude.
4. Emite hallazgos y veredicto.
5. Frena sin corregir.

### Fase 6 — Corrección

Si el veredicto requiere correcciones:

1. Franco devuelve el informe a Claude.
2. Claude corrige los hallazgos dentro del mismo bloque o propone un bloque nuevo si cambió el alcance.
3. Franco ejecuta las escrituras necesarias.
4. Claude vuelve a validar y genera un paquete de reauditoría.
5. ChatGPT reaudita únicamente el delta y las áreas afectadas, sin perder de vista el DONE completo.

### Fase 7 — Cierre y traspaso

Con auditoría aprobada:

1. Claude actualiza solo los satélites afectados.
2. Claude produce el cierre formal.
3. Claude actualiza el roadmap.
4. Claude genera el kickoff autosuficiente del siguiente bloque.
5. ChatGPT puede auditar cierre y kickoff si Franco lo solicita.
6. Todos frenan. El bloque siguiente comienza en una conversación nueva.

## 7. Protocolo ante complicaciones o ideas nuevas

Toda novedad se clasifica antes de implementarse.

### Clase A — Incidencia local absorbible

Condiciones:

- pertenece al objetivo actual;
- no cambia contratos públicos;
- no agrega una capa nueva;
- no modifica decisiones cerradas;
- puede validarse dentro del plan existente.

Acción: Claude la resuelve dentro del bloque, la documenta y la incluye en el paquete de auditoría.

### Clase B — Hallazgo bloqueante

Condiciones:

- contradice una premisa del kickoff;
- falta una autoridad confiable;
- repo y vivo divergen materialmente;
- existe riesgo de escribir en el entorno incorrecto;
- no puede validarse sin una decisión.

Acción: Claude frena y produce checkpoint. ChatGPT puede validar el diagnóstico, pero no decide por Franco.

### Clase C — Mejora valiosa pero no necesaria

Condiciones:

- aporta valor;
- no es requisito para cerrar el bloque;
- abre trabajo adicional o una variante comercial o técnica.

Acción: registrar en roadmap o backlog. No implementarla dentro del bloque actual.

### Clase D — Cambio de alcance

Condiciones:

- cambia firma, contrato o fuente de verdad;
- agrega objetos de base, workflows, gateway, UI o entorno no previstos;
- afecta más de una capa que el kickoff no contemplaba;
- cambia el DONE;
- reabre una decisión congelada.

Acción: Claude frena y propone revisión de roadmap o bloque nuevo. Franco decide. ChatGPT puede auditar el impacto.

### Clase E — Incidente urgente de operación

Acción: separar un bloque de hotfix con alcance mínimo, rollback, pruebas, auditoría y cierre propio. No mezclarlo silenciosamente con el bloque en curso.

## 8. Reglas de freno obligatorias

Claude debe frenar cuando:

- el siguiente paso pertenece a otro bloque;
- hay que escribir en un sistema externo sin autorización;
- se requiere una decisión de negocio no resuelta;
- una fuente autoritativa contradice otra;
- se propone reabrir una decisión cerrada;
- aparece un cambio de contrato;
- se requiere una operación destructiva no prevista;
- la evidencia no permite afirmar el resultado;
- el contexto ya no permite un traspaso confiable;
- terminó el paquete de auditoría;
- el bloque alcanzó DONE técnico pero todavía falta auditoría.

ChatGPT debe frenar cuando:

- falta el kickoff o el paquete de auditoría mínimo;
- no puede acceder a evidencia suficiente;
- se le pide corregir silenciosamente el objeto auditado;
- la tarea cambia de auditoría a construcción sin una excepción explícita de Franco;
- emitió el veredicto.

Franco debe frenar una ejecución cuando:

- el entorno no coincide con el autorizado;
- el preflight falla;
- el comando difiere del artefacto aprobado;
- la operación destructiva no tiene rollback o gate;
- aparece un error no contemplado.

Frenar no significa abandonar. Significa entregar estado, evidencia y punto de continuación preciso.

## 9. Criterio para separar conversaciones

Abrir conversación nueva cuando:

- comienza un bloque diferente;
- cambia la capa principal de trabajo;
- cambia el entorno de ejecución, especialmente TEST a OPS;
- se cerró un contrato y comienza su implementación;
- se inicia promoción o canonización;
- aparece un hotfix independiente;
- el contexto acumulado dificulta distinguir hechos, hipótesis y decisiones.

Además:

- la conversación de construcción de Claude y la conversación de auditoría de ChatGPT deben ser separadas;
- el auditor debe recibir el paquete de auditoría, no depender del chat interno de construcción;
- no abrir conversación nueva por un ajuste local del mismo bloque;
- una reauditoría del mismo bloque puede continuar en la conversación de auditoría si el contexto sigue siendo confiable.

## 10. Reglas de traspaso

### 10.1 Claude → Franco: paquete de ejecución

Debe incluir:

- objetivo de la escritura;
- entorno exacto;
- preflight;
- artefacto o comando exacto;
- resultado esperado;
- evidencia que Franco debe devolver;
- rollback o estrategia de recuperación;
- condición de freno.

### 10.2 Claude → ChatGPT: paquete de auditoría

Debe permitir auditar sin leer la conversación de construcción completa. Debe distinguir:

- comprobado;
- inferido;
- decidido;
- pendiente;
- fuera de alcance.

Debe incluir rutas y nombres exactos y exigir inspección de repo fresco y estado vivo.

### 10.3 ChatGPT → Claude: informe de auditoría

Debe ser accionable y no contener correcciones aplicadas silenciosamente. Cada hallazgo debe incluir:

- evidencia;
- severidad;
- impacto;
- corrección esperada;
- criterio de revalidación.

### 10.4 Claude → siguiente bloque: cierre y kickoff

Solo se produce después del veredicto aprobatorio o excepción explícita de Franco. El kickoff siguiente debe basarse en el estado real aprobado y no copiar historia innecesaria.

## 11. Regla de autoridad

Orden general de autoridad, adaptable al frente:

1. estado vivo del entorno correspondiente;
2. repo fresco en la rama autorizada;
3. definiciones extraídas del sistema vivo;
4. canónico vigente;
5. commit y diff reales del bloque;
6. evidencia de ejecución devuelta por Franco;
7. cierre formal del bloque anterior;
8. decisiones no reabrir;
9. estado actual y roadmap;
10. bitácoras históricas;
11. mensajes de conversaciones anteriores.

Las afirmaciones de Claude no son autoridad por sí mismas. El informe de ChatGPT tampoco reemplaza la evidencia primaria.

Cuando dos fuentes divergen, no elegir silenciosamente. Explicar la divergencia y determinar qué fuente gobierna ese objeto.

## 12. Regla de documentación satélite

Cada cierre debe indicar expresamente cuáles documentos requieren actualización:

- estado actual;
- roadmap del frente;
- decisiones no reabrir;
- lecciones aprendidas;
- pendientes preproducción;
- README;
- canónico;
- bootstrap;
- inventarios o fingerprints;
- bitácora de construcción;
- informe o referencia de auditoría;
- cierre del bloque.

No actualizar todos por reflejo. Actualizar solo los afectados y evitar duplicar el mismo detalle.

Claude crea o modifica los satélites. ChatGPT audita que las actualizaciones sean correctas y completas.

## 13. Integración obligatoria con agentes

Este protocolo es la fuente canónica completa. No debe copiarse íntegramente en archivos de instrucciones de agentes.

La integración se realiza mediante dos puertas con roles distintos:

- **Claude Code:** `.claude/rules/00-orquestacion.md`, que define a Claude como diseñador y constructor.
- **ChatGPT/Codex:** `AGENTS.md`, que define a ChatGPT como auditor técnico independiente.

La puerta de Claude debe obligar a:

1. consultar el protocolo al abrir y cerrar trabajo;
2. diseñar y construir dentro del alcance;
3. no ejecutar escrituras externas sin autorización;
4. preparar paquete de auditoría;
5. corregir hallazgos;
6. no cerrar ni avanzar antes del veredicto.

La puerta de ChatGPT debe obligar a:

1. consultar el protocolo y kickoff;
2. auditar independientemente;
3. no confiar en afirmaciones no verificadas;
4. no modificar los artefactos auditados;
5. emitir hallazgos y veredicto;
6. frenar después de la auditoría.

Si este protocolo cambia, revisar ambas puertas para confirmar que reflejen esta separación.

## 14. Comandos breves por rol

### A. Claude — diseñar un frente nuevo

```text
MODO: DISEÑAR FRENTE

Proyecto: [nombre]
Frente/carril: [nombre]
Objetivo de negocio: [resultado buscado]
Restricciones conocidas: [lista]
Estado actual conocido: [resumen]

Inspeccioná las fuentes autoritativas y entregá:
1. diagnóstico del estado real;
2. límites del frente;
3. dependencias y riesgos;
4. decisiones a congelar o confirmar;
5. roadmap completo de bloques;
6. criterios de DONE y auditoría por bloque;
7. puntos de separación de conversaciones;
8. kickoff autosuficiente del primer bloque;
9. archivos o rutas a inspeccionar.

No implementes todavía. Frená después del kickoff.
```

### B. Claude — abrir y construir un bloque

```text
MODO: ABRIR BLOQUE

Trabajá exclusivamente sobre el kickoff adjunto del bloque [ID y nombre].

Antes de escribir:
1. verificá repo fresco, rama, HEAD y working tree;
2. verificá fuentes vivas autorizadas;
3. reconciliá kickoff y estado real;
4. informá divergencias;
5. fijá alcance, exclusiones, entornos y DONE.

Después diseñá y creá los artefactos del bloque, un sub-bloque por vez. Prepará para Franco cualquier escritura externa. No avances al bloque siguiente.
```

### C. Claude — controlar un desvío

```text
MODO: CONTROL DE DESVÍO

Durante el bloque [ID] apareció:
[describir hallazgo, problema o idea]

No lo implementes todavía. Clasificalo como A, B, C, D o E según el protocolo. Entregá evidencia, impacto, recomendación y acción concreta.
```

### D. Claude — preparar paquete de auditoría

```text
MODO: PREPARAR AUDITORÍA

Terminaste la construcción del bloque [ID].

No lo declares cerrado. Entregá el paquete autosuficiente de auditoría con kickoff, prompt, respuesta, repo/HEAD, diff, archivos, afirmaciones, pruebas, evidencia, estado por entorno, acciones de Franco, riesgos, pendientes y lista exacta para ChatGPT.

Frená al terminar.
```

### E. ChatGPT — auditar un bloque

```text
MODO: AUDITAR BLOQUE

Actuá como auditor técnico independiente del bloque [ID]. Claude diseñó y creó los artefactos; no los des por correctos.

Auditá el kickoff, prompt, respuesta, repo fresco, diff, archivos, pruebas y evidencia. No modifiques los artefactos ni implementes soluciones.

Entregá:
1. alcance y evidencia consultada;
2. afirmaciones comprobadas y no comprobadas;
3. hallazgos por severidad;
4. impacto sobre contratos, entornos y DONE;
5. correcciones que Claude debe realizar;
6. pruebas o evidencia faltante;
7. veredicto: APROBADO, APROBADO CON OBSERVACIONES, REQUIERE CORRECCIONES o BLOQUEADO POR FALTA DE EVIDENCIA.

Frená después del veredicto.
```

### F. Claude — corregir hallazgos

```text
MODO: CORREGIR AUDITORÍA

Aplicá únicamente las correcciones derivadas del informe de auditoría del bloque [ID]. Para cada hallazgo, indicá causa, cambio, validación y evidencia.

No abras alcance nuevo. Al terminar, regenerá el paquete de auditoría y frená.
```

### G. Claude — cerrar y traspasar

```text
MODO: CERRAR Y TRASPASAR

El bloque [ID] recibió veredicto aprobatorio.

Reconciliá el cierre contra repo y evidencia real. Entregá:
1. estado final multidimensional;
2. alcance ejecutado y no ejecutado;
3. artefactos y commits;
4. pruebas y evidencia;
5. resultado de auditoría y correcciones;
6. decisiones, lecciones, riesgos y pendientes;
7. satélites actualizados;
8. roadmap actualizado;
9. cierre formal;
10. kickoff autosuficiente del siguiente bloque;
11. archivos/rutas para las próximas conversaciones.

Frená. No empieces el bloque siguiente.
```

## 15. Aplicación al Motor de Precios v2

- **Proyecto:** Vita Delta Reservas.
- **Frente:** Motor de Precios v2.
- **Bloques:** B1, B1.1, B2A, B2B, B3, B3.1, B4, B5, B6, B7.
- **Conversaciones recomendadas:** una conversación Claude por bloque y una conversación ChatGPT de auditoría por bloque o grupo de correcciones estrechamente relacionadas.
- **Separaciones obligatorias:**
  - diagnóstico read-only → DDL;
  - backend → exposición pública;
  - gateway → portal;
  - TEST → OPS;
  - implementación → auditoría;
  - auditoría aprobada → canonización y cierre.

Ejemplo de estado durante auditoría:

> B3 — EN AUDITORÍA · funciones verdes en TEST según paquete de Claude · OPS intacto · canónico pendiente · auditoría en curso.

Ejemplo de cierre:

> B3 — CERRADO · funciones verificadas en TEST · OPS intacto · auditoría aprobada · canonización diferida a B7.

Ejemplo ante idea nueva:

> Agregar override manual de capacidad cambia contrato y agrega capacidad administrativa. Claude no lo absorbe en B3; lo registra como B3.1. ChatGPT audita que la separación sea suficiente.

## 16. Resultado operativo esperado

Para cada bloque:

1. Franco abre la conversación de Claude con el kickoff.
2. Claude inspecciona, diseña y crea archivos.
3. Franco ejecuta las escrituras externas autorizadas.
4. Claude valida y prepara el paquete de auditoría.
5. Franco abre una conversación separada con ChatGPT y sube el paquete.
6. ChatGPT audita y emite veredicto.
7. Si hay hallazgos, Franco devuelve el informe a Claude.
8. Claude corrige y el bloque vuelve a auditoría.
9. Con auditoría aprobada, Claude produce cierre y kickoff siguiente.
10. Nadie inicia automáticamente el bloque siguiente.

El detalle largo queda en el repositorio. Cada conversación recibe solo el contexto necesario para su rol y para el bloque actual.
