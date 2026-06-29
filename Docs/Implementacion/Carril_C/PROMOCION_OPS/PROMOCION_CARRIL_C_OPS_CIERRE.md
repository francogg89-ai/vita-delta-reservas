# PROMOCIÓN DEL CARRIL C A OPS — CIERRE

**Etapa:** Cierre de la promoción del Carril C (Portal Operativo Interno) a OPS + bump del canónico a **v1.9.0** + actualización de satélites.
**Fecha de cierre:** 2026-06-29.
**Estado:** ✅ Cerrada. El Carril C completo (Portal Operativo Interno: gateway `portal-api`, los 13 wrappers n8n y el frontend) quedó **promovido a OPS** en una operación coordinada bloque por bloque (Bloques **A→H**, junio 2026), con **paridad estructural TEST↔OPS del portal certificada por fingerprint** y el canónico `6B_SCHEMA_SQL.md` **bumpeado a v1.9.0** (Bloque **I**) incorporando las estructuras internas del portal como **PARTE D**. El bootstrap kit se regeneró pineado a la nueva versión.
**Ámbito:** 100% documental + de promoción/consolidación de schema. Claude actuó como arquitecto: generó los artefactos `PROMO_C_BLOQUE_*`, las verificaciones, el bump del canónico y este cierre; **Franco ejecutó todos los writes** en Supabase, n8n y Vercel, y los commits en git. Claude no tocó OPS, n8n ni Vercel directamente.

> **Qué NO reabre este cierre.** No reabre ni redefine las decisiones de diseño del Carril C (`D-C-XX`) ni del contrato frontend (`D-FE-XX`), que conservan su numeración y son la fuente de diseño. No reabre los cierres de slice (`C_SLICE*_CIERRE.md`), el del contrato (`CONTRATO_FRONTEND_PORTAL_CIERRE.md`), los de frontend (`FRONTEND_SUBSLICE*_CIERRE.md`), el de A10-MP (`A10MP_CIERRE.md`) ni el del aviso A07 (`AVISO_8CBIS_PORTAL_A07_CIERRE.md`). Las decisiones de esta etapa (`D-PROMO-C-XX`) son **decisiones de promoción/ejecución**, no rediseño del modelo; las lecciones (`L-PROMO-C-XX`) son de promoción, validación y documentación. El detalle bloque por bloque vive en `PROMO_C_BLOQUE_E_CIERRE.md` y `PROMO_C_BLOQUE_H_CIERRE.md`.

---

## 1. Resumen ejecutivo

Hasta v1.8.1 el Portal Operativo Interno (Carril C) vivía **solo en TEST**: la infra de identidad/idempotencia (`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno`) era una capa aditiva **TEST-only fuera del canónico** (precedente `portal_usuarios`, D-C-34), y el gateway `portal-api`, los 13 wrappers n8n y el frontend apuntaban al entorno de pruebas. Esta etapa lo **promovió a OPS** —por DDL bloque por bloque, **sin copiar datos de TEST**— y lo **consolidó en el canónico v1.9.0** como capa real (PARTE D), autocontenida y apta para bootstrappear un entorno de cero.

Resultado verificado:

- **Paridad estructural TEST↔OPS del portal certificada por fingerprint:** la huella `TOTAL_PORTAL` sobre los **3 objetos** del portal (`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno(jsonb)`) quedó **idéntica** en ambos entornos (`dee953e867aed06a9c65836bac14e8f7`), por doble corrida del mismo script simétrico read-only.
- **13 wrappers `__OPS`** andando en OPS, validados con escrituras reales (cobro multi-porción por A10-MP y alta por A07); el aviso 8C-bis disparó en el alta real con `entorno=ops`.
- **Smokes read-only end-to-end por rol 14/14 en verde** contra el gateway de OPS, **anti-OPS respetado** (cero escrituras, cero consumo de secuencias del negocio).
- **Frontend desplegado en OPS** (Vercel), con el banner de ambiente resuelto para OPS (sin banner) y el fix anti-autofill del incidente de datos.
- **Canónico v1.9.0 entregado** (PARTE D ejecutable + §25 conceptual + changelog + conteos: 31 tablas / 31 funciones / +1 secuencia), con **bootstrap kit regenerado** pineado a v1.9.0 (9 archivos) y verificación estricta del entorno.

El equipo opera ahora el Portal Operativo Interno sobre OPS con los datos reales del complejo. El frente de pagos autónomos (Mercado Pago) y la web pública siguen fuera de alcance por diseño.

---

## 2. Estado de entrada (verificado)

- **Carril C cerrado y validado en TEST** en slices verticales: diseño Backend/API (D-C-01…28), Slice 0 (espina de seguridad), Slice 1 (lecturas reuse), Slice 2 (escrituras reuse), Slice 3a (lecturas nuevas), Slice 3b (gasto interno), A10-MP (cobranza multi-porción `cobranza.registrar_cobro`), aviso 8C-bis en el alta por portal (A07), y el **Frontend TEST** (sub-slices 0→3, publicado en Vercel con piloto operativo OK).
- **Canónico v1.8.1** intacto; las estructuras internas del portal (`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno`) eran aditivas y **TEST-only**, fuera del canónico. **Nada del portal en OPS.**
- **OPS:** entorno de operación real interna, con el Carril B promovido (v1.8.0) y datos reales del complejo (cabañas 1-5, socios Franco/Rodrigo/Remo).
- **Política de promoción** (precedente Carril B, ratificada en el plan del Carril C): promoción **coordinada** por DDL bloque por bloque, sin copiar datos ni fixtures; satélites e IDs `D-PROMO-C-XX` / `L-PROMO-C-XX` recién en **este cierre final** (después del Bloque I), no bloque por bloque.

---

## 3. Inventario promovido a OPS

**3 estructuras internas del portal** (por DDL, sin seed de datos de TEST):
- `portal_usuarios` — identidad→rol (`jenny`/`vicky`/`socio`), interna (REVOKE a `anon`/`authenticated`, SELECT solo a `service_role`, invisible al Data API; FK a `auth.users` ON DELETE CASCADE; D-C-34). En OPS los usuarios se sembraron por Supabase Auth + seed recién en la promoción (Bloque C), no copiados de TEST.
- `portal_idempotencia` — `UNIQUE(nonce)` anti-replay (el `nonce` derivado de la firma HMAC) + `UNIQUE(action,idempotency_key)` + FK RESTRICT a `gastos_internos` + 7 CHECK.
- `portal_cargar_gasto_interno(jsonb)` — la función de carga de gasto con guard de dos capas en una transacción (anti-replay + idempotencia de negocio), `actor`/`source_event` derivados server-side, con su hardening (REVOKE a roles Data API).

**1 gateway** `portal-api` (Supabase Edge Function, BFF/frontera de confianza) desplegado en OPS, con CORS por env var (`CORS_ALLOW_ORIGIN`, nunca `'*'`).

**13 wrappers n8n `__OPS`** (path con sufijo `__OPS`, credencial de OPS en los nodos PG, HMAC de OPS): 8 lecturas (A03 `calendario.limpieza`, A04 `calendario.operativo`, A05 `reserva.detalle`, A06 `prereservas.activas`, A12 `cobranza.saldos`, A24 `historico.reservas`, A25 `ingresos.cobrados_periodo`, A13 `gastos.listado`) + 5 escrituras (A07 `reserva.crear_manual` con rama lateral del aviso 8C-bis, A08 `bloqueo.crear_manual`, W10 `cobranza.registrar_saldo` deprecated-in-place, A11 `cargar.gasto_interno`, A10-MP `cobranza.registrar_cobro`).

**1 frontend** (React + Vite + TypeScript estricto + Tailwind) desplegado en OPS (Vercel), con el banner de ambiente resuelto para OPS (no muestra banner) y la defensa anti-autofill en el alta.

> **W10 (`cobranza.registrar_saldo`) deprecated-in-place.** Sigue desplegado y operativo en OPS, pero el portal **no lo invoca** (B5 frontend usa solo A10-MP `cobranza.registrar_cobro`). Conserva a propósito su candado de ambiente (nunca se dispara). **No es deuda.**

---

## 4. Bloques ejecutados (bitácora A → I)

| Bloque | Qué hizo | Resultado |
|---|---|---|
| **A** | Snapshot baseline **read-only** de OPS antes de tocar nada. | ✅ |
| **B** | Infra del portal por DDL (las 3 estructuras), **sin seed**. | ✅ |
| **C** | Usuarios Auth en OPS + seed `portal_usuarios` (recién acá, no copiado de TEST). | ✅ |
| **D** | Gateway `portal-api` desplegado a OPS (CORS por env var). | ✅ |
| **E** | Los **13 wrappers `__OPS`** (8 lecturas + 5 escrituras). Hallazgo: candado anti-OPS `TEST-only` hardcodeado en `verificar_acceso` de A10-MP y W10; removido de A10-MP, conservado a propósito en W10. Validado con escrituras reales (cobro A10-MP, alta A07). | ✅ |
| **F** | Aviso 8C-bis en el A07 de OPS por rama lateral no bloqueante (`entorno` autoresuelto desde el marcador canónico). | ✅ alta real disparó el aviso, `entorno=ops` |
| **G** | Frontend OPS (build + deploy Vercel). Incidente de datos por autofill del navegador + dedup por email (resuelto con corrección de datos + defensa doble capa). Banner OPS resuelto (P-FE-09). | ✅ desplegado |
| **H** | **Fingerprint estructural TEST↔OPS** del portal + **smokes read-only end-to-end por rol**; H.3 (alta + aviso) por referencia. | ✅ huella idéntica; smokes 14/14 |
| **I** | Bump canónico `6B_SCHEMA_SQL.md` → **v1.9.0** (portal como PARTE D + §25) + regeneración del bootstrap kit pineado a v1.9.0 + verificación estricta del entorno. | ✅ kit 9 archivos; verify estricto |

---

## 5. Evidencia dura consolidada

| Ítem | Valor |
|---|---|
| Paridad estructural del portal (`TOTAL_PORTAL`, 3 objetos) | `dee953e867aed06a9c65836bac14e8f7` — **idéntica TEST↔OPS** |
| Huella `portal_usuarios` | `bb12480a2b316155c94302697ae1ea88` (TEST = OPS) |
| Huella `portal_idempotencia` | `3143abbae64521b2600a9c8e118f8091` (TEST = OPS) |
| Huella `func:portal_cargar_gasto_interno(jsonb)` | `82136c79acc451344e53f88f0b972bc7` (TEST = OPS) |
| Smokes read-only end-to-end por rol (OPS) | **14/14** verde · anti-OPS respetado (cero escrituras, cero consumo de secuencias) |
| Menú por rol (allowlist estricta) | jenny = 2 acciones exactas; vicky/socio = 14, faltantes 0 / extra 0 (W10 solo INFO legado) |
| Escrituras reales validadas (Bloque E) | cobro multi-porción A10-MP + alta A07 end-to-end OK en OPS |
| Aviso 8C-bis en A07 OPS | disparó en el alta real con `entorno=ops` (rama lateral no bloqueante, sub-workflow solo-lectura) |
| Canónico v1.9.0 (conteos) | 31 tablas · 31 funciones · +1 secuencia (`portal_idempotencia`); PARTE D + §25 + changelog |
| Bootstrap kit v1.9.0 | 9 archivos, pineados; verificación estricta del entorno (D5 + `03_VERIFY_FINAL_ENTORNO.sql`) |

> La huella `dee953…` (y las tres por objeto) es un **hash de estructura**: cubre columnas (nombre+tipo+nullability), constraints, índices, triggers no internos, ACL, estado RLS y policies, comentarios, y para la función el cuerpo completo + ACL + comentario. **No entra al hash** ninguna fila, secreto, uuid, valor de secuencia, marcador de ambiente, fecha/hora ni ref de proyecto.

---

## 6. Decisiones de promoción (D-PROMO-C-01 a D-PROMO-C-14) 🔒

Decisiones de **ejecución de la promoción** (no rediseño del modelo). Versión consolidada; el detalle bloque por bloque vive en este cierre (§4) y en los artefactos `PROMO_C_BLOQUE_*`.

- **D-PROMO-C-01** — Portal a OPS **por DDL bloque por bloque, sin copiar datos de TEST**: la infra (Bloque B) viaja **sin seed**; los usuarios Auth + el seed de `portal_usuarios` se crean **recién en OPS** (Bloque C). Estructura recreada, filas no copiadas.
- **D-PROMO-C-02** — Los **13 wrappers `__OPS`** usan **path con sufijo `__OPS`** (la instancia n8n aloja TEST y OPS; el sufijo evita colisión de paths), **credencial de OPS** en todos los nodos PG y **HMAC de OPS** en `validar_firma_ts_rol`. La paridad TEST↔OPS es **lógica** (keys/roles/validators/flags/HMAC/credencial), **no byte**.
- **D-PROMO-C-03** — **CORS del gateway por env var** `CORS_ALLOW_ORIGIN` **obligatoria**: el preflight falla si falta; **nunca `'*'`** en OPS (apunta al dominio del frontend de producción).
- **D-PROMO-C-04** — **Discriminación de ambiente por `ambiente_esperado`, no por valor literal.** El candado hardcodeado `!== 'test'` (mensaje "wrapper TEST-only") que vivía en `verificar_acceso` se **removió de A10-MP**; el chequeo válido `dbAmbiente !== v.ambiente_esperado` ya estaba y se conserva. **W10 conserva el candado a propósito** (deprecated, nunca invocado).
- **D-PROMO-C-05** — **Idempotency prefix por ambiente** (A07 OPS usa `portal_ops_a07_`). Cosmético: las bases TEST/OPS son separadas; sin efecto funcional.
- **D-PROMO-C-06** — **El frontend reconoce OPS por su project ref → sin banner** (resuelve P-FE-09): OPS no muestra banner; cualquier ref **desconocido** cae en el estado defensivo (rojo); TEST conserva el banner amarillo. Una sola fuente de verdad (la URL del build), sin env var de ambiente aparte.
- **D-PROMO-C-07** — **Aviso 8C-bis en el A07 de OPS por rama lateral no bloqueante** (Call al sub-workflow 8C-bis de OPS), con `entorno` **autoresuelto desde el marcador canónico** (`leer_ambiente.valor`), no hardcodeado → la promoción no requiere flip manual. El sub-workflow es **solo-lectura** (manda mail, no escribe DB).
- **D-PROMO-C-08** — **Paridad estructural del portal certificada por fingerprint simétrico**: la huella `TOTAL_PORTAL` (`dee953e867aed06a9c65836bac14e8f7`) quedó **idéntica TEST↔OPS** por doble corrida del mismo script read-only. El método es simétrico, **sin ambiente/ref/fecha en el hash**.
- **D-PROMO-C-09** — **Fingerprint por firma exacta + ACL ordenado + `\r` normalizado**: las funciones se resuelven por `regprocedure` (firma exacta, no por nombre), los `aclitem` se serializan **ordenados por texto**, y se normaliza `\r` del blob de cada objeto antes del `md5`. Robusto a overloads, a orden de array de grants y a diferencias de EOL.
- **D-PROMO-C-10** — **Guard de entorno OPS antes de autenticar** (exit 3) en todo smoke que apunte a OPS: verifica ref del proyecto + path del gateway **antes** de pedir credenciales o hacer login. Evita generar evidencia inválida contra TEST u otro entorno.
- **D-PROMO-C-11** — **Verificación de menú por allowlist estricta**: el menú por rol se valida por conjunto exacto (presencia de las acciones productivas **y** ausencia de extras), no solo presencia. **W10** se admite únicamente como catálogo técnico legado informativo, nunca como acción productiva.
- **D-PROMO-C-12** — **Smokes read-only end-to-end por rol 14/14 en verde** contra el gateway de OPS (gateway → allowlist → firma → wrapper → motor), **anti-OPS respetado** (cero escrituras, cero consumo de secuencias del negocio). H.3 (alta + aviso) se cierra **por referencia** a la evidencia ya registrada.
- **D-PROMO-C-13** — **Bump canónico v1.9.0** incorporando el portal como **PARTE D** (las 2 tablas + la función + su hardening D-C-34) + **§25** de diseño; **estructura pura** (sin seeds, secretos, URLs, Project ID, datos ni marcador de ambiente); **excluye la maquinaria de promoción** (gates/asserts/snapshots/fingerprints quedan en los `PROMO_C_BLOQUE_*` + cierres).
- **D-PROMO-C-14** — **Bootstrap kit regenerado y pineado a v1.9.0** con **verificación estricta del entorno**: el `bootstrap_entorno_nuevo_v1.9.0/` (9 archivos) reemplaza al anterior; el paso D5 + `03_VERIFY_FINAL_ENTORNO.sql` validan FKs por tabla/columna exactas (incl. `ON DELETE CASCADE`/`RESTRICT`), CHECK/UNIQUE por relación y conjunto exacto de columnas, firma de función, hardening por **ACL real** (`aclexplode`, cubre TRUNCATE/REFERENCES/TRIGGER/MAINTAIN), y RLS off + 0 policies. **El retiro del kit `bootstrap_entorno_nuevo_v1.8.1/` del árbol es una decisión operativa de limpieza de este cierre final** (evitar doble fuente ejecutable; queda en el historial de git), **no un requisito técnico del Bloque I**.

---

## 7. Reconciliación con decisiones conceptuales (no duplicar)

Estas decisiones del modelo **conservan su código**; la promoción las **aplica/materializa**, no las reemplaza:

- **Asimetría de hardening del portal** (la infra interna sale del Data API) → **D-C-34** (aplicada en OPS por DDL; viajó al canónico como PARTE D).
- **% operativo = 25%** → **D-NEG-01**; **inicio contable 2026-07-01** → **D-NEG-02** (reglas de negocio vigentes, sin cambios).
- **W10 deprecated-in-place** → **D-C-64** (el frontend dejó de llamarlo en B5; sigue desplegado).
- **Decisiones de diseño del Carril C** (`D-C-XX`) **y del contrato frontend** (`D-FE-XX`) → **no se renombran como D-PROMO-C**; viajaron por DDL/deploy sin cambio de diseño.
- **Lecciones menores de A10-MP** (guard `recargo>0`, fixtures escalonados por el EXCLUDE gist, "el SQL Editor de Supabase muestra solo el último `SELECT`") → **no se acuñan como L-C nuevas**; la del SQL Editor ya está cubierta por **L-8A-01**; las otras dos quedan referenciadas en `A10MP_CIERRE.md`.

---

## 8. Lecciones de la promoción (L-PROMO-C-01 a L-PROMO-C-08)

Lecciones de promoción, validación y documentación (no de arquitectura productiva).

- **L-PROMO-C-01** — Al promover wrappers n8n de TEST a OPS, **auditar la lógica interna de los nodos** (`jsCode` y SQL) por **guards de ambiente hardcodeados** (`!== 'test'`, mensajes "TEST-only"), no solo routing/credenciales/HMAC/Call. El candado vivía dentro de `verificar_acceso` y el builder de promoción no lo veía; un barrido posterior mostró que solo A10-MP y W10 lo tenían.
- **L-PROMO-C-02** — **Autofill del navegador + dedup por email = corrupción silenciosa de datos.** Un `<input type="email">` sin `autoComplete="off"` puede ser llenado por el navegador con el email del operador logueado; combinado con un upsert que deduplica por email en modo update, **sobrescribe el registro y colapsa filas**. Defensa de **doble capa** (`autoComplete="off"` + validación anti-autofill: email del huésped ≠ email del operador). Diagnóstico: **confirmar con query, no asumir** (una hipótesis de credencial cruzada se descartó así, evitando un fix equivocado).
- **L-PROMO-C-03** — **El EOL real del repo es LF, no CRLF.** No hay `.gitattributes` y los archivos tracked están en `i/lf`; la regla mnemónica "PowerShell → CRLF" no coincide con el remoto. **Verificar siempre con `git ls-files --eol`** antes de fijar EOL: la evidencia del repo gana a la regla genérica.
- **L-PROMO-C-04** — **Para certificar paridad entre entornos, fingerprint simétrico + doble corrida.** Correr el mismo script read-only en ambos lados y comparar la huella total es más simple y robusto que un diff estructural manual; **normalizar `\r` y ordenar los arrays sensibles (ACL)** elimina falsos rojos por EOL u orden.
- **L-PROMO-C-05** — **Guard de entorno barato antes de cualquier login en scripts que tocan OPS.** Cuesta tres comparaciones de string y blinda contra el peor caso (autenticar o generar evidencia contra el entorno equivocado).
- **L-PROMO-C-06** *(validación/documentación)* — **`aclexplode` enumera lo realmente concedido y cubre todos los privilegios de tabla** (incl. `MAINTAIN` de PG17) **sin guard de versión**; mejor que `has_table_privilege` por-privilegio para verificar hardening cross-versión en el `03_VERIFY` del bootstrap.
- **L-PROMO-C-07** *(validación/documentación)* — **Una FK inline en la PK queda auto-nombrada** (`tabla_col_fkey`); validarla por `conrelid`/`confrelid`/columnas/`confdeltype`, **no por `conname`** (la FK `portal_usuarios.user_id → auth.users(id)` ON DELETE CASCADE se verifica así).
- **L-PROMO-C-08** *(validación/documentación)* — **`pglast` valida un bloque `DO` solo a nivel de statement** (el plpgsql interno es opaco); para confianza real en la lógica de catálogo, **espejarla en un SELECT read-only** (`03_VERIFY_FINAL_ENTORNO.sql`) que pglast sí parsea entero. Corolario de empaquetado: **tras renombrar/promover archivos, verificar el árbol con `git ls-files`** (un rename puede dejar huérfanos del nombre viejo).

---

## 9. Estado final

- **Carril C vivo en OPS**: las 3 estructuras internas del portal + gateway `portal-api` + 13 wrappers `__OPS` + frontend, todo cerrado al Data API (la infra interna no se expone; las escrituras pasan por el gateway firmado).
- **Canónico `6B_SCHEMA_SQL.md v1.9.0`**: incorpora el portal como **PARTE D** (estructura pura) + **§25** conceptual; autocontenido y apto para bootstrappear un entorno de cero.
- **TEST = OPS** por huella estructural del portal (`TOTAL_PORTAL` idéntica). TEST conserva sus fixtures de laboratorio; OPS arranca limpio.
- **Bootstrap kit** regenerado a `bootstrap_entorno_nuevo_v1.9.0/` (9 archivos); el kit `v1.8.1/` se **retiró del árbol** (limpieza de este cierre; queda en el historial de git).
- El **frente de pagos autónomos** (Mercado Pago), la **web pública** y el carril **fiscal/legal** siguen **fuera de alcance** por diseño.

---

## 10. Pendientes y handoff

- **Corrida end-to-end del bootstrap kit v1.9.0 (01→03) sobre un Supabase nuevo** — el kit quedó validado contra un PostgreSQL limpio y verificado por estructura, pero **aún no ejecutado de punta a punta sobre un Supabase real**. Queda como pendiente (no bloqueante). Registrado en `Pendiente_pre_produccion.md`.
- **Cosmético — comentarios `D-C-61…64` en el artefacto del gateway A10-MP** — los comentarios del código desplegado citan provisionalmente `D-C-61…64` por arrastre del parche; la numeración oficial es **D-C-64…70** (D-C-61/62/63 son de A04). **No afecta runtime** (los comentarios no se ejecutan). Corregirlos es un pendiente cosmético, **solo si el artefacto se edita/propaga**. Registrado en `Pendiente_pre_produccion.md`.
- **W10 (`cobranza.registrar_saldo`)** — sigue como catálogo legado/deprecated a propósito; **no es deuda**.
- **Mercado Pago / web pública / fiscal** — frentes separados, fuera de este cierre.

---

## 11. Deltas para documentos satélite (aplicados con este cierre)

> El 6° satélite, `6B_SCHEMA_SQL.md`, **ya quedó hecho en el Bloque I (v1.9.0)** y no se toca acá. Los demás se actualizan preservando el **EOL LF** por archivo (verificado con `git ls-files --eol`: todo el repo es LF).

- **`DECISIONES_NO_REABRIR.md` (LF)** — (a) nueva sección **A10-MP** con **D-C-64…70** (saldando la deuda del ledger; texto verbatim de `A10MP_CIERRE.md`) **antes** de la sección del aviso A07; (b) actualización de la nota de numeración (las 64…70 quedan propagadas); (c) nueva sección **"## Promoción Carril C a OPS — cerrada 2026-06-29"** con la versión sintética de **D-PROMO-C-01…14** + reconciliación, al final del contenido del Carril C.
- **`Lecciones_Aprendidas.md` (LF)** — nueva sección **"## Lecciones de la promoción del Carril C a OPS (L-PROMO-C-XX)"** con **L-PROMO-C-01…08**, append al final.
- **`ESTADO_ACTUAL_VITA_DELTA.md` (LF)** — nueva "Etapa actual" = Carril C promovido a OPS + canónico/kit v1.9.0 (la anterior pasa a "Etapa previa"); "Schema canónico actual" → **v1.9.0**; entrada de "Documentación viva" del kit → **v1.9.0** (+ nota de retiro del v1.8.1) + este cierre.
- **`Pendiente_pre_produccion.md` (LF)** — marcar **CERRADA** la promoción coordinada del Carril C a OPS (espejo de la del Carril B); cerrar **P-FE-09** (banner OPS) y **P-C-7** (CORS); dos pendientes nuevos: corrida end-to-end del kit v1.9.0 y el cosmético de comentarios `D-C-61…64`.
- **`README.md` (LF)** — referencias al kit `v1.8.1` → **v1.9.0** (flujo 01→03, con nota de retiro del v1.8.1 del árbol); referencia a `6B_SCHEMA_SQL.md` → **v1.9.0**; nota del Carril C promovido a OPS.
- **`CLAUDE.md` (LF)** — nueva entrada en "Estado del proyecto" (Carril C en OPS + v1.9.0); "Schema canónico actual" → **v1.9.0**; actualizar la "Próxima etapa".

---

## 12. Inventario de artefactos / fuentes

- **Artefactos de promoción:** `PROMO_C_BLOQUE_A_SNAPSHOT_OPS.sql`, `PROMO_C_BLOQUE_B_INFRA_OPS.sql`, `PROMO_C_BLOQUE_C_PASO1_RUNSHEET_AUTH_OPS.md`, `PROMO_C_BLOQUE_C_SEED_USUARIOS_OPS.sql`, `PROMO_C_BLOQUE_D_RUNSHEET_GATEWAY_OPS.md`, los wrappers `__OPS` (E), `PROMO_C_BLOQUE_H_FINGERPRINT.sql`, `PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1`, `PROMO_C_BLOQUE_H_RUNSHEET_OPS.md`.
- **Cierres de bloque (referencia):** `PROMO_C_BLOQUE_E_CIERRE.md` (wrappers + hallazgos + incidente de datos), `PROMO_C_BLOQUE_H_CIERRE.md` (fingerprint + smokes).
- **Cierres de diseño/slice (referencia):** `CARRIL_C_BACKEND_API_DISENO_CIERRE.md`, `C_SLICE0…3B_CIERRE.md`, `CONTRATO_FRONTEND_PORTAL_CIERRE.md`, `FRONTEND_SUBSLICE0…3_CIERRE.md`, `A10MP_CIERRE.md` (D-C-64…70), `AVISO_8CBIS_PORTAL_A07_CIERRE.md` (D-C-71…73 / L-C-24/25).
- **Canónico:** `6B_SCHEMA_SQL.md v1.9.0` (PARTE D + §25 + changelog v1.8.1 → v1.9.0).
- **Bootstrap kit:** `Docs/Implementacion/bootstrap_entorno_nuevo_v1.9.0/` (9 archivos, pineados a v1.9.0).
- **Este cierre:** `Docs/Bitacora/PROMOCION_CARRIL_C_OPS_CIERRE.md`.

---

*Cierre — promoción del Carril C (Portal Operativo Interno) a OPS + canónico v1.9.0. Decisiones `D-PROMO-C-01..14` lockeadas; lecciones `L-PROMO-C-01..08`. Deuda `D-C-64..70` (A10-MP) saldada en el ledger. Las decisiones de diseño del Carril C (`D-C-XX`) y del contrato frontend (`D-FE-XX`) conservan su numeración y no se reabren.*
