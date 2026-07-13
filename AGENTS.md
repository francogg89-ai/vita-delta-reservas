# AGENTS.md — Vita Delta Reservas

## Autoridades iniciales

Antes de trabajar sobre este repositorio, consultar en este orden:

1. `Docs/Operacional/PROTOCOLO_ORQUESTACION_FRENTES_Y_BLOQUES.md`
2. `Docs/Operacional/ESTADO_ACTUAL_VITA_DELTA.md`
3. `Docs/Operacional/DECISIONES_NO_REABRIR.md`
4. `CLAUDE.md` como inventario técnico y operacional general
5. el kickoff y las autoridades específicas del bloque actual

No cargar contexto histórico largo salvo que afecte materialmente el bloque.

## Regla de unidad de trabajo

Todo trabajo debe clasificarse como proyecto, frente o carril, etapa opcional, bloque y, solo cuando exista un límite técnico real, sub-bloque.

La unidad normal de ejecución es un bloque o sub-bloque. No mezclar bloques diferentes en una misma intervención.

## Gate de apertura

Antes de diseñar, modificar archivos o proponer implementación:

1. leer las secciones aplicables del protocolo de orquestación;
2. verificar repo fresco, rama, HEAD y working tree;
3. reconciliar el kickoff con el estado real;
4. distinguir comprobado, inferido, decidido, pendiente y fuera de alcance;
5. declarar alcance incluido, alcance excluido, entornos permitidos y criterio de DONE;
6. informar contradicciones antes de continuar.

## Control de desvíos

Toda complicación, hallazgo o idea nueva debe clasificarse como:

- incidencia local absorbible;
- hallazgo bloqueante;
- mejora diferible;
- cambio de alcance;
- incidente urgente independiente.

No incorporar silenciosamente trabajo nuevo. Un cambio de contrato, capa, entorno, fuente de verdad, decisión cerrada o criterio de DONE exige frenar y proponer un bloque nuevo o un checkpoint de decisión.

## Gate de cierre

Antes de declarar terminado un frente, etapa, bloque o sub-bloque:

1. releer en el protocolo las reglas de estados, autoridad, freno, cierre, documentación satélite y traspaso;
2. auditar el resultado contra el kickoff y la evidencia real;
3. indicar estado funcional, entorno máximo validado, estado documental y promoción;
4. registrar alcance ejecutado y no ejecutado, pruebas, decisiones, lecciones, riesgos y pendientes;
5. actualizar solamente los documentos satélite afectados;
6. producir el cierre formal y el kickoff autosuficiente del siguiente bloque;
7. frenar.

Alcanzar el DONE de un bloque no autoriza a comenzar automáticamente el siguiente.
