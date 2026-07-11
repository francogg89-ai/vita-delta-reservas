# Cierre — Portal Operativo · Exposición L3 Cuenta Corriente · Bloque 0 (read-only)

Acta de cierre del **Bloque 0** del frente que expone, como **lecturas read-only** en el portal
operativo interno, la capa histórica (L3) de la cuenta corriente de socios: el histórico mensual
(A30) y los acumulados (A31). Estado: **completo y verde en TEST**.

> Este documento es el **acta** del Bloque 0. Los `D-CC-*`/`L-CC-*` que siguen se acuñan acá con
> su ID, pero —siguiendo la convención del carril (acta L1/L2)— la **propagación a los satélites**
> (`DECISIONES_NO_REABRIR.md`, `Lecciones_Aprendidas.md`, `ESTADO_ACTUAL_VITA_DELTA.md`,
> `Pendiente_pre_produccion.md`) y al **canónico** `6B_SCHEMA_SQL.md` se hace recién en la
> canonización coordinada, pegada a la promoción a OPS. Nada de eso se toca en este bloque.

---

## 1. Qué es este bloque

Exponer al portal, con el mismo patrón que las lecturas ya existentes (A24/A25/A13/A27/A28/A29),
dos funciones L3 **ya canonizadas** (v1.12.0) del motor contable del Carril B:

- **A30 — `cuenta_corriente.historico`** → `cuenta_corriente_historico(p_mes date)`: la foto mensual
  de un período (cabecera, cascada, socios, detalle fino, movimientos, retribución operativa).
- **A31 — `cuenta_corriente.historico_acumulados`** → `cuenta_corriente_historico_acumulados()`:
  la evolución y los totales acumulados sobre las fotos vigentes desde el piso contable.

**No se construyó contabilidad nueva ni motor nuevo: se expuso lo que ya existe.** No hubo cambios
de esquema, ni GRANT, ni canónico, ni bootstrap, ni frontend, ni OPS.

---

## 2. Qué quedó desplegado en TEST (ejecutado por Franco)

- **Gateway** `portal-api` (TEST) actualizado con el diff aditivo A31 (2 validators + 2 entradas de
  CATALOG socio-only, read-only). Desplegado y verde.
  - baseline A29: `bc38a056689c20c26b7f6d74c7b2f0ec2b5caec91d990d46b8014dd6f1b65fef`
  - A31 desplegado: `07f316b8ec9bc335f908ca08f927ff6192924827b600df73132aa2bbcb081a8c`
- **Wrappers n8n** importados y **activos** en TEST:
  - `portal-a30-cuenta-corriente-historico__TEST`
  - `portal-a31-cuenta-corriente-historico-acumulados__TEST`
- **Credenciales/secreto** cargados en los wrappers (Modo B; el secreto no se commitea).

Todo lo demás (OPS, snapshots, canónico, bootstrap, UI) queda **fuera** — ver sección 8.

---

## 3. Inventario de artefactos y hashes (SHA-256)

**Implementación (3, aprobados y congelados):**

| Artefacto | Hash |
|---|---|
| `portal-api_A31_TEST_index.ts` | `07f316b8ec9bc335f908ca08f927ff6192924827b600df73132aa2bbcb081a8c` |
| `portal-a30-cuenta-corriente-historico__TEST.json` | `09909f517bc6b4d568b628193723aa4179fcd072718c7bdc9bad22fcdd679463` |
| `portal-a31-cuenta-corriente-historico-acumulados__TEST.json` | `1e498ea89d6e09e898b20bd3d4da624dbe596cf28452406294cdd8d43c36f11b` |

**Validación (4, ronda final):**

| Artefacto | Hash |
|---|---|
| `CC_L3_A30_historico_smoke_directo.ps1` | `d84e595a986a7c2a3128dff089378cb55605550646f272e4d90f20baf1b355ed` |
| `CC_L3_A31_acumulados_smoke_directo.ps1` | `bc9fdf1dd214cf6bdce9cf7f3e77e4176185a8684bb55f6a602a813d46eb8587` |
| `CC_L3_GW_smoke.ps1` | `cde1f5f7013f85680de351374fd89cf9a9bc016d334ab0431d68dca5ff530bb2` |
| `CC_L3_oracle_readonly.sql` | `c3755385b8939726a20ca98d5dd33047c2049ef9284499442ce70415a4753bf2` |

---

## 4. Resultados de smokes y oracle (ejecutados por Franco en TEST)

### 4.1 Smokes

| Smoke | PASSED | FAILED | LASTEXITCODE |
|---|---|---|---|
| A31 directo (`cuenta_corriente.historico_acumulados`) | 24 | 0 | 0 |
| A30 directo (`cuenta_corriente.historico`) | 34 | 0 | 0 |
| Gateway end-to-end (JWT → portal-api → HMAC → wrapper → L3) | 50 | 0 | 0 |

- **A31** cubrió: socio autorizado; Vicky/Jenny/intruso rechazados (`rol_no_permitido`); firma
  inválida; ts vencido; ambiente incorrecto; action binding; payload `{}`/omitido/`null` → ok;
  objeto-con-claves/array/string/number/boolean → `payload_invalido`; 6 claves top-level; arrays y
  objetos estrictos; piso `2026-07-01`; evolución ordenada; `meta.fotos_vigentes == evolucion.length`;
  allowlist limpia.
  Observaciones reales: `sin_datos=False`, `piso=2026-07-01`, `fotos_vigentes=3`,
  `evolucion=2026-07-01, 2026-08-01, 2026-11-01`, `saldos_por_socio=3`.
- **A30** cubrió: seguridad/roles/firma/ts/ambiente/action; payload mensual estricto; foto
  pre-extensión y mes sin foto. Derivación real: `MesPreExtension=2026-07-01`,
  `MesSinFoto=2026-09-01`. Foto pre-extensión: 14 claves, `sin_foto=false`,
  `detalle_disponible=false`, `detalle_motivo=foto_pre_extension`, detalle fino vacío,
  cabecera/cascada/socios/retribución presentes, movimientos dentro de la ventana mensual. Mes sin
  foto: `ok:true`, 14 claves, `sin_foto=true`, `detalle_motivo=sin_foto_vigente`, 8 secciones
  vacías, cabecera null, retribución null, período round-trip.
- **Gateway** validó el recorrido completo `JWT → portal-api → HMAC → wrapper n8n → funciones L3 →
  gateway`. A02: socio ve 20 acciones (incluye A30/A31), Vicky 15 (no las ve), Jenny 2 (no las ve);
  Vicky/Jenny → `rol_no_permitido`; sin JWT → `no_autorizado`; contratos A30/A31 correctos; ambos
  caminos (foto pre-extensión y mes sin foto) probados end-to-end; allowlist limpia.

### 4.2 Oracle de no-mutación

```
veredicto: "OK: 0 mutacion (forma 7/7/2/2 valida + counts + max_ids + table_hashes + sequences identicos)"
before_shape_ok: true    after_shape_ok: true
counts_iguales: true     max_ids_iguales: true    table_hashes_iguales: true    sequences_iguales: true
before_key_counts / after_key_counts: {counts:7, max_ids:2, sequences:2, table_hashes:7}
```

Los fingerprints BEFORE y AFTER, sin `captured_at`, son idénticos en las cuatro secciones. Correr
las lecturas L3 (directas y por gateway) **no mutó nada** en las 7 tablas relevantes.

### 4.3 Rama natural `error_entorno` (evidencia de que son lecturas)

Con el gateway A31 desplegado y los wrappers aún inactivos, una llamada devolvió:

```
{ "ok": false, "error": { "code": "error_entorno", "message": "respuesta inesperada del backend", "detail": null } }
```

Un dispatch no confiable de estas lecturas produce `error_entorno` — **nunca** `estado_incierto`
(que se reserva para escrituras que podrían haberse aplicado).

---

## 5. Auditoría de las evidencias (verificaciones estáticas, en harness — no en TEST)

Cruces hechos contra los artefactos (no contra TEST; no se ejecutó nada en TEST/Supabase/n8n):

- **Hash del gateway desplegado** == hash del artefacto A31 (`07f316b8…`), y baseline == A29
  (`bc38a056…`). El diff es el aditivo aprobado.
- **Forma del fingerprint**: 7 counts / 2 max_ids / 2 sequences / 7 table_hashes. Aritmética
  coherente: `liquidacion_cascada`=32=8×4 (8 pasos × 4 liquidaciones); `liquidacion_socio`=12=3×4
  (3 socios); `fotos_vigentes`=3 ≤ `liquidaciones_periodo`=4 (1 no vigente); secuencias
  `last_value`=14 con `max_id` de movimientos=14 y de liquidaciones=11 (huecos por rollback, coherente).
- **`md5('[]')` = `d751713988987e9331980363e24189ce`**: coincide con el hash de las 3 tablas de
  detalle fino vacías (`liquidacion_gasto`, `liquidacion_incidencia`, `liquidacion_participacion`),
  confirmando 0 filas genuinas (fotos pre-extensión).
- **Conteo de asserts** (parser AST de PowerShell, invocaciones en el flujo): A31=24, A30=34,
  GW=50 — coinciden exactamente con los PASSED reportados.
- **Mensaje `error_entorno`** trazado al artefacto desplegado: `return noConfiable('respuesta
  inesperada del backend')`; y la decisión read→`error_entorno` / write→`estado_incierto` vive en el
  gateway (comentario "sin needsIdempotencyKey -> dispatch no confiable = error_entorno").
- El SQL del oracle es **SELECT puro** (pglast: 2 `SelectStmt`; barrido write-ops limpio).

**Conclusión de auditoría: sin inconsistencias ni cobertura faltante. Cierre confirmado.**

---

## 6. Decisiones acuñadas (candidatas; propagación diferida a canonización/OPS)

- **D-CC-40 — Visibilidad colectiva socio-only.** Todo socio autenticado ve la cuenta corriente
  contable **completa de todos los socios** (dato compartido entre socios). `roles:['socio']`; sin
  self-only, sin inyección de identidad de socio. Vicky/Jenny (y cualquier rol fuera de la
  allowlist) → `rol_no_permitido`; sin JWT → `no_autorizado`.
- **D-CC-41 — A30/A31 son lecturas read-only.** Exposición estrictamente de lectura; no mutan
  estado. Demostrado por el oracle (sección 4.2).
- **D-CC-42 — Payload mensual exacto `YYYY-MM-01`.** A30 exige un objeto con **única** clave `mes`,
  YMD real, **día `01`**, y `>=` piso contable `2026-07-01`. Cualquier otra cosa (mes mal formado,
  día ≠ 01, pre-piso, clave extra) → `payload_invalido`. Validado en el gateway (validador espejo)
  y en el wrapper (2.ª defensa).
- **D-CC-43 — Payload vacío estricto de A31.** `undefined`/`null` → `{}` → ok; `{}` → ok; objeto con
  claves / array / string / number / boolean → `payload_invalido`. Validado en gateway y wrapper.
- **D-CC-44 — `sin_foto` y `sin_datos` son ÉXITOS, no errores.** Un mes sin foto vigente devuelve
  `ok:true` con `sin_foto:true` y `detalle_motivo:'sin_foto_vigente'` (nunca `no_encontrado`);
  acumulados sin datos devuelve `ok:true` con `sin_datos`. La foto pre-extensión devuelve
  `sin_foto:false`, `detalle_disponible:false`, `detalle_motivo:'foto_pre_extension'`.
- **D-CC-45 — Naturaleza mixta frozen/live de L3.** El histórico compone la **foto congelada**
  (`liquidaciones_periodo` + `liquidacion_cascada`/`socio`/`participacion`/`gasto`/`incidencia`,
  append-only) con **`movimientos_socio` en vivo** filtrados a la ventana mensual `[mes, mes+1)`.
  Los acumulados agregan sobre las fotos vigentes + movimientos en vivo. Leer esta mezcla no muta
  nada (incluida la tabla live).
- **D-CC-46 — Detalle fino solo con extensión (`n_part > 0`).** La foto pre-extensión (`n_part == 0`)
  devuelve `detalle_disponible:false` y detalle fino vacío
  (`participacion`/`gastos`/`incidencias`/`matriz_por_socio`/`gastos_sin_incidencia` = `[]`). El
  detalle fino solo se puebla en fotos con extensión.
- **D-CC-47 — `error_entorno`, nunca `estado_incierto`, para dispatch incierto de estas lecturas.**
  Al ser read-only sin efectos colaterales (sin `idempotency_key`, sin `isWrite`), un dispatch no
  confiable devuelve `error_entorno`. `estado_incierto` se reserva para escrituras que podrían
  haberse aplicado.
- **D-CC-48 — Exposición aditiva con el patrón A29.** HMAC firmado server-side por el gateway
  (el harness nunca ve el secreto), revalidación de 5 dimensiones en el wrapper, `Respond` con
  `responseCode:200` para todo resultado manejado (ok o rechazo), allowlist de 13 códigos. El cambio
  al gateway es **100% aditivo** (2 validators + 2 entradas de CATALOG; sin modificar nada existente).
- **D-CC-49 — Ausencia deliberada de UI/OPS/canónico/bootstrap en este bloque.** El alcance se
  limitó a exponer las lecturas L3 en TEST vía gateway + wrappers. Sin frontend, sin promoción a OPS,
  sin cambios de esquema/GRANT/canónico/bootstrap.

---

## 7. Hallazgos / lecciones (candidatas; propagación diferida)

- **L-CC-20 — No-mutación se prueba multi-dimensión.** Un oracle read-only con `counts` + `max_ids`
  + **`table_hashes`** (`md5(jsonb_agg(to_jsonb(fila) ORDER BY PK))` por tabla) + `sequences`
  (`last_value`), más un **guard de forma 7/7/2/2**, detecta inserciones, borrados, **UPDATEs** (que
  counts/max_ids no verían) y cobertura incompleta. El veredicto OK exige forma válida en BEFORE y
  AFTER **y** las 4 secciones idénticas; `captured_at` queda fuera de la comparación.
- **L-CC-21 — `pg_sequences` NO expone `is_called`.** Solo `last_value`. Las secuencias reales se
  **descubren** con `pg_get_serial_sequence` (no se asumen); las tablas de PK compuesta no aportan
  secuencia.
- **L-CC-22 — `jsonb_object_length` NO existe en PostgreSQL.** Para contar claves de un objeto jsonb
  se usa `(SELECT count(*) FROM jsonb_object_keys(x))` guardado por `jsonb_typeof(x)='object'`
  (una sección ausente/no-objeto cuenta `-1` y nunca aprueba forma).
- **L-CC-23 — Parser-only no alcanza para SQL/PS.** `pglast` y el AST de PowerShell validan
  **sintaxis** pero no resuelven catálogo; los bugs `is_called` y `jsonb_object_length` solo se
  atrapan **ejecutando** el SQL contra un PostgreSQL real. La validación por ejecución es parte del
  cierre de artefactos SQL.
- **L-CC-24 — Aserciones de array estrictas.** En los smokes, `Is-Arr = ($v -is [System.Array])`
  (no admite `null`) y `AllEmpty` valida tipo **antes** de medir longitud: una sección
  `null`/objeto/string no puede aprobar como array ni como array vacío. Es seguro porque **todas**
  las secciones-lista del canónico están `COALESCE`-adas a `'[]'::jsonb` (nunca `null` en datos
  legítimos), así que esto solo cierra el falso-verde.
- **L-CC-25 — Fotos TEST persistidas son pre-extensión.** Al cierre hay 3 fotos vigentes
  (`2026-07-01`, `2026-08-01`, `2026-11-01`), todas con `n_part == 0` (detalle fino vacío). El mes
  sin foto se deriva dinámicamente como el primer hueco `>=` piso (`2026-09-01` hoy), no se
  hardcodea.
- **L-CC-26 — Todo resultado manejado del wrapper es HTTP 200.** El nodo `Respond` tiene
  `responseCode:200` y ambas ramas del `IF acceso` llegan al mismo `Respond`; por eso los smokes
  directos exigen HTTP 200 **además** del envelope/código esperado, distinguiendo resultados
  manejados de fallas de infraestructura.

---

## 8. Fuera de alcance (deliberado, no es deuda de este bloque)

Nada de esto se tocó ni se diseñó:

- **UI Histórico** (frontend del histórico/acumulados en el portal).
- **OPS**: promoción del gateway A31 y los wrappers a OPS.
- **Snapshot/foto real** y **cierre mensual** (generar nuevas fotos).
- **Supersesión** de fotos y **retiros adicionales**.
- **Mercado Pago**, **canónico** (`6B_SCHEMA_SQL.md`), **bootstrap**, **schema/GRANT**.
- Propagación de estos `D-CC-*`/`L-CC-*` a los satélites (diferida a canonización pegada a OPS).

---

## 9. Próximo bloque lógico (no diseñado, no iniciado)

El siguiente bloque lógico del frente es la **UI del Histórico en el Portal Operativo sobre TEST**,
consumiendo las acciones ya validadas:

- `cuenta_corriente.historico`
- `cuenta_corriente.historico_acumulados`

La UI debe diseñarse, implementarse y validarse completamente en TEST antes de promover esta
exposición a OPS. Una vez cerrada la UI y sus pruebas integrales, el bloque posterior será la
**promoción coordinada a OPS** del gateway A31, los wrappers A30/A31 y el frontend correspondiente,
junto con la canonización/propagación documental que corresponda.

**Orden acordado: UI en TEST → QA/cierre de UI → promoción integral a OPS.**

No se diseña ni se inicia ninguno de esos pasos dentro de esta acta.

---

## 10. Veredicto

**Bloque 0 — Exposición L3 Cuenta Corriente (read-only): CERRADO y verde en TEST.** Auditoría sin
inconsistencias. Las 7 piezas quedan congeladas con los hashes de la sección 3. La promoción a OPS
y la propagación a satélites/canónico quedan para el bloque de canonización coordinada.
