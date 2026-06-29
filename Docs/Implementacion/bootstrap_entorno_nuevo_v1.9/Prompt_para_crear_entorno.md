Quiero convertir el bootstrap de entorno nuevo en artefactos ejecutables y repetibles.

Prepará una propuesta para `6B_SCHEMA_SQL.md v1.9.0` y una carpeta:

`Docs/Implementacion/bootstrap_entorno_nuevo_v1.9.0/`

Con estos archivos:

1. `00_PRECHECK_ENTORNO_NUEVO.sql`

   * read-only;
   * valida proyecto/base vacía/roles/extensiones/default grants;
   * no escribe nada.

2. `01_BOOTSTRAP_PARTE_B_BASE.sql`

   * extraído literalmente del canónico v1.9.0;
   * incluye Parte B Bloques 1→23 (con el hardening del Bloque 23, REVOKE EXECUTE de las 13 funciones base, ya canónico);
   * no incluye Parte C ni Parte D.

3. `01_VERIFY_PARTE_B_BASE.sql`

   * read-only;
   * devuelve una fila-veredicto `PARTE_B_OK` o `PARTE_B_INCOMPLETA`;
   * valida inventario base, seeds, cron y funciones base sin EXECUTE público.

4. `02_BOOTSTRAP_PARTE_C_CARRIL_B.sql`

   * extraído literalmente del canónico v1.9.0;
   * incluye Parte C C0→C14;
   * mantiene hardening Carril B C12;
   * setea `ambiente='dev'` para esta variante DEV.

5. `02_VERIFY_PARTE_C_CARRIL_B.sql`

   * read-only (renombrado desde `02_VERIFY_FINAL_ENTORNO.sql`: ya no es el gate final);
   * devuelve una fila-veredicto `PARTE_C_OK` o detalle de fallas;
   * incluye C14, inventario Carril B, hardening Carril B, hardening funciones base y barrido global de permisos.

6. `03_BOOTSTRAP_PARTE_D_PORTAL.sql`

   * extraído literalmente del canónico v1.9.0 (PARTE D, D1→D5);
   * crea las tablas `portal_usuarios` y `portal_idempotencia`, la función `portal_cargar_gasto_interno(jsonb)` y su hardening (D-C-34);
   * SOLO estructura: sin seed de `portal_usuarios`, sin usuarios de auth, sin secretos, sin URLs, sin Project ID, sin datos reales, sin marcador de ambiente;
   * cierra con D5 (auto-test estricto de estructura/hardening por NOTICE).

7. `03_VERIFY_FINAL_ENTORNO.sql`

   * read-only;
   * devuelve la fila-veredicto FINAL `ENTORNO_COMPLETO_OK` o detalle de fallas;
   * verificación **estricta** de estructura y hardening del portal (espejo de D5): FKs contra tabla/columna exactas, CHECK/UNIQUE por relación y conjunto de columnas, firma de la función, hardening por ACL real (incl. TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) y estado de RLS/policies; sin depender de datos, usuarios reales ni ambiente.

8. `README_EJECUCION_BOOTSTRAP.md`

   * orden exacto de ejecución (01→03);
   * advertencia de confirmar Project Ref en URL;
   * ejecutar solo sobre base nueva/vacía;
   * no usar sobre OPS existente;
   * qué resultado esperar en cada verificación.

Condiciones:

* No rediseñar schema.
* La Parte D es solo estructura (sin seed/usuarios/secretos/ambiente).
* No copiar datos reales ni fixtures.
* No usar DROP CASCADE.
* No mezclar DEV/TEST/OPS.
* No tocar OPS actual.
* Todo debe ser compatible con Supabase SQL Editor.
* Los SQL deben estar pensados para pegar por archivo completo o por secciones claras, y las verificaciones deben devolver una fila-veredicto.
