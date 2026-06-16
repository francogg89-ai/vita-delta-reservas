Quiero convertir el bootstrap de entorno nuevo en artefactos ejecutables y repetibles.

Prepará una propuesta para `6B_SCHEMA_SQL.md v1.8.1` y una carpeta:

`Docs/Implementacion/Bootstrap_Entorno_Nuevo_v1.8.1/`

Con estos archivos:

1. `00_PRECHECK_ENTORNO_NUEVO.sql`

   * read-only;
   * valida proyecto/base vacía/roles/extensiones/default grants;
   * no escribe nada.

2. `01_BOOTSTRAP_PARTE_B_BASE.sql`

   * extraído literalmente del canónico v1.8.1;
   * incluye Parte B Bloques 1→22;
   * agrega nuevo Bloque 23: hardening de las 13 funciones base del motor;
   * no incluye Parte C.

3. `01_VERIFY_PARTE_B_BASE.sql`

   * read-only;
   * devuelve una fila-veredicto `PARTE_B_OK` o `PARTE_B_INCOMPLETA`;
   * valida inventario base, seeds, cron y funciones base sin EXECUTE público.

4. `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql`

   * extraído literalmente del canónico v1.8.1;
   * incluye Parte C C0→C14;
   * mantiene hardening Carril B C12;
   * setea `ambiente='dev'` para esta variante DEV.

5. `02_VERIFY_FINAL_ENTORNO.sql`

   * read-only;
   * devuelve una fila-veredicto `ENTORNO_COMPLETO_OK` o detalle de fallas;
   * incluye C14, inventario Carril B, hardening Carril B, hardening funciones base y barrido global de permisos.

6. `README_EJECUCION_BOOTSTRAP.md`

   * orden exacto de ejecución;
   * advertencia de confirmar Project Ref en URL;
   * ejecutar solo sobre base nueva/vacía;
   * no usar sobre OPS existente;
   * qué resultado esperar en cada verificación.

Condiciones:

* No rediseñar schema.
* No copiar datos reales ni fixtures.
* No usar DROP CASCADE.
* No mezclar DEV/TEST/OPS.
* No tocar OPS actual.
* Todo debe ser compatible con Supabase SQL Editor.
* Los SQL deben estar pensados para pegar por archivo completo o por secciones claras, y las verificaciones deben devolver una fila-veredicto.
