# D2 — RESULTADOS EN TEST Y CIERRE DE B1.3

**Bloque:** `B1.3-consolidacion-canonica` · **Fase:** cierre del inventario DB del carril
**Clone fresco:** HEAD `03e20a62aa2f7d12a7354968584769bfd60548fa` (rama `main`, árbol limpio)
**Set ejecutado:** `D2_Q0 … D2_Q7` (9 archivos) en Supabase TEST. Ejecutado por Franco en Supabase TEST y auditado de manera independiente.
**Naturaleza:** 100 % lectura. Claude no escribió en ninguna base.

> **Documento diagnóstico versionado en la Bitácora.**
> **No forma parte del canónico SQL.**

---

## 0. Contexto (Q0)

| Campo | Valor |
|---|---|
| `ambiente` | `test` |
| `transaction_read_only` | `on` |
| Motor | PostgreSQL 17.6 (TEST) |
| `server_addr` | `<REDACTADO — IPv6 del pooler de Supabase TEST>` |

**Sanitización — registrada.** La IPv6 real no se transcribe. Salida raw local, en poder de Franco.

---

## 1. Veredicto integral de D2 (Q7)

| Métrica | Valor |
|---|---|
| `objetos_nombre_presentes` | 7 |
| `firmas_esperadas_presentes` | **7** |
| `firmas_esperadas_ausentes` | 0 |
| `firmas_distintas_de_esperada` | 0 |
| `overloads_extra` | 0 |
| `firmas_vivas_totales` | 7 |
| `execute_a_public` | **0** |
| `priv_efectivos_data_api` | **0** |
| `roles_data_api_ausentes` | 0 |
| `trg_ov_guard_filas` | 1 |
| `trg_ov_guard_ok` | **true** |
| `otros_triggers_en_overrides` | 0 |
| `objetos_con_cr` | 7 |
| `cr_totales` | 540 |
| `observaciones` | `<ninguna -- todo consistente>` |

Los 7 objetos existen con su **firma exacta**, sin overloads, **sin exposición** (0 `EXECUTE` a PUBLIC, 0 privilegios efectivos), y el trigger `trg_ov_guard` cumple las 13 propiedades del predicado.

---

## 2. Los siete fingerprints — CONGELADOS (doble hash MD5, opción C)

El esquema operativo elegido es el doble fingerprint MD5: `fp_raw` verifica el vivo (con CRLF), `fp_lf` verifica contra el canónico LF-only.

| Objeto | `fp_raw` (vivo) | `fp_lf` (canónico LF-only) |
|---|---|---|
| `public.crear_bloqueo(jsonb)` | `0391133ff2eea689bb18e65088536555` | `c097dcc70e5c3b19b3ce26b74e3e17f3` |
| `public.crear_override_horario(jsonb)` | `239c2e4c41f7905382bc1d49758abc6f` | `3036c6789e4c4e2a0d3b628249162604` |
| `public.fecha_hoy_ar()` | `fbfa96e0fa3f0ab855f1782c6c28000f` | `dce59fab0ab52076d81e7f87a03828b2` |
| `public.trg_guard_overrides()` | `c7d217ea134dddba215e88c2e26d844a` | `279ca092b303e99d5cc9cdb47d12ac0e` |
| `public.validar_estado_horario_final(bigint,date)` | `348d26e9abb7caebfaeb05305fc77e23` | `493c14c62dff590505151fa73ba1951c` |
| `public.validar_estado_override(bigint,date)` | `d27ea6e16f22c2ae17a0c3fe40b2a5c0` | `ec17b66abe6c08f6eb8f5f409141468f` |
| `public.validar_no_eventos_comprometidos(bigint,date)` | `4b0dbe1be47ea92509a2857816fd13e6` | `a3f60d6065a20ec3d5dcfae85b644c5b` |

**Trigger `trg_ov_guard`:** `fp_triggerdef = f6a5394751129110617e9c7ce22e5cab`

Los 7 cuerpos vivos están versionados en `13-07-2026/D2_Q5_CUERPOS_TEST.json` — el export original de Franco:

```
sha256 archivo = 8b9a9c92f26668e5cf3e378b9095a19a91ad83930be815858e6ef366f742b490
```

Ese archivo tiene `ambiente=test` y `transaction_read_only=on` en las siete filas. **CR total: 540** — patrón CRLF consistente con el resto del carril.

---

## 3. Comparación cuerpo-vivo vs fragmento-del-repo

**Franco lo pidió explícitamente: una firma coincidente NO vuelve autoritativo al artefacto.** Hay que comparar los cuerpos.

### 3.1 Método — comparación directa, no sólo por hash

Para cada objeto se hace una **comparación directa de texto**, más un control por dos funciones de hash independientes:

1. **`functiondef` vivo normalizado a LF** — extraído del export original `13-07-2026/D2_Q5_CUERPOS_TEST.json` (sha256 `8b9a9c92…`), con `chr(13)` removido.
2. **`functiondef` reconstruido desde el fragmento del repo** — el objeto se recrea en un harness PostgreSQL 17.10 desde el fragmento exacto del artefacto, se extrae su `pg_get_functiondef` y se normaliza a LF.
3. **`comparacion_directa_lf`** — igualdad de texto byte a byte entre (1) y (2).
4. **`sha256_lf_vivo`** y **`sha256_lf_repo`** — SHA-256 de (1) y (2) respectivamente.
5. Se conservan los `fp_raw` / `fp_lf` MD5 como esquema operativo.

El criterio de autoridad es: **`comparacion_directa_lf = true`** y **`sha256_lf_vivo = sha256_lf_repo`**. Que además coincidan `fp_lf` (MD5) y `sha256_lf` es una verificación cruzada por dos algoritmos distintos; la evidencia primaria es la comparación directa de texto, no un hash aislado.

> **Nota metodológica.** El hash debe calcularse **dentro de la sesión de base** (`SELECT md5(replace(pg_get_functiondef(oid), chr(13), ''))`). Exportar el `functiondef` a un archivo con `psql -tA -o` agrega un salto de línea final que no está en el `functiondef` original y **cambia todos los hashes**. Este cierre calcula los hashes en la base para evitar ese artefacto.

### 3.2 Matriz por objeto

| Objeto | Artefacto | Líneas | `sha256_lf_vivo` | `sha256_lf_repo` | `comparacion_directa_lf` | Autoridad |
|---|---|---|---|---|---|---|
| `fecha_hoy_ar` | `B2_GUARD_HELPER` | 16-23 | `1a07c72819d590e4…` | `1a07c72819d590e4…` | **true** | **SI** |
| `validar_estado_horario_final` | `S0_VALIDADORES` | 56-101 | `391ef9dc913e75b7…` | `391ef9dc913e75b7…` | **true** | **SI** |
| `validar_no_eventos_comprometidos` | `S0_VALIDADORES` | 110-158 | `9d9a84ba7f66218e…` | `9d9a84ba7f66218e…` | **true** | **SI** |
| `validar_estado_override` | `S0_VALIDADORES` | 165-182 | `fe0498944bfba840…` | `fe0498944bfba840…` | **true** | **SI** |
| `trg_guard_overrides` | `S1_TRIGGER` | 57-142 | `a61d55ffa42acfa6…` | `a61d55ffa42acfa6…` | **true** | **SI** |
| `crear_override_horario` | `S2_FUNCION` | 50-196 | `2d1804ce4a9658be…` | `2d1804ce4a9658be…` | **true** | **SI** |
| `crear_bloqueo` | `B2_GUARD_HELPER` | 398-622 | `72d9ea6ee73ce2d3…` | `72d9ea6ee73ce2d3…` | **true** | **SI** |

**Resultado: 7/7 `comparacion_directa_lf = true` y `sha256_lf_vivo = sha256_lf_repo`.** Cada `functiondef_completo` de `D2_Q5_CUERPOS_TEST.json` se normalizó a LF y se comparó **byte a byte** contra el `functiondef` reconstruido del fragmento del repo. Las longitudes coinciden en los 7, la comparación directa da `true`, y el SHA-256 calculado independientemente en cada lado (en Python del lado vivo, dentro de la base del lado repo) coincide.

**Verificación de fidelidad del insumo vivo.** El `functiondef_completo` del Q5 se validó contra los `md5_raw` (CRLF) y `md5_lf` (LF) que el propio JSON declara: 7/7 en ambos, más `bytes` y `cantidad_cr` exactos. El `md5_raw` coincidiendo confirma que el texto vivo se preservó byte-exacto, CRLF incluido.

### 3.3 `sha256_lf` completos (vivo y repo — idénticos)

```
public.fecha_hoy_ar()
  sha256_lf_vivo = 1a07c72819d590e4b869db91ecbc1fc22361a82df596ebb7d847a82265b26eb9
  sha256_lf_repo = 1a07c72819d590e4b869db91ecbc1fc22361a82df596ebb7d847a82265b26eb9
  comparacion_directa_lf = true   (len 180 == 180)
public.validar_estado_horario_final(bigint,date)
  sha256_lf_vivo = 391ef9dc913e75b72f50c3c66ea91d6c4796fbfafb7c740e59497537c7d558a3
  sha256_lf_repo = 391ef9dc913e75b72f50c3c66ea91d6c4796fbfafb7c740e59497537c7d558a3
  comparacion_directa_lf = true   (len 1278 == 1278)
public.validar_no_eventos_comprometidos(bigint,date)
  sha256_lf_vivo = 9d9a84ba7f66218e73e38518d46f00e1854272b63d59c171ff4af8e5f670fd19
  sha256_lf_repo = 9d9a84ba7f66218e73e38518d46f00e1854272b63d59c171ff4af8e5f670fd19
  comparacion_directa_lf = true   (len 1238 == 1238)
public.validar_estado_override(bigint,date)
  sha256_lf_vivo = fe0498944bfba84027b13c93793d7123668a02db6f6ce163b3de7a6a3ce32a6a
  sha256_lf_repo = fe0498944bfba84027b13c93793d7123668a02db6f6ce163b3de7a6a3ce32a6a
  comparacion_directa_lf = true   (len 373 == 373)
public.trg_guard_overrides()
  sha256_lf_vivo = a61d55ffa42acfa6df1018eb4a0c25ffd6de476c1085591d547954fa965feb35
  sha256_lf_repo = a61d55ffa42acfa6df1018eb4a0c25ffd6de476c1085591d547954fa965feb35
  comparacion_directa_lf = true   (len 4041 == 4041)
public.crear_override_horario(jsonb)
  sha256_lf_vivo = 2d1804ce4a9658becb123baff48b370aa9cd6b9a7c63accf47ee04c38416cb56
  sha256_lf_repo = 2d1804ce4a9658becb123baff48b370aa9cd6b9a7c63accf47ee04c38416cb56
  comparacion_directa_lf = true   (len 6069 == 6069)
public.crear_bloqueo(jsonb)
  sha256_lf_vivo = 72d9ea6ee73ce2d3abe5133371186aeb89b045043d0da1f6e0e505e0e06d369d
  sha256_lf_repo = 72d9ea6ee73ce2d3abe5133371186aeb89b045043d0da1f6e0e505e0e06d369d
  comparacion_directa_lf = true   (len 8869 == 8869)
```

### 3.4 Los 14 puntos de comparación

| # | Punto | Resultado |
|---|---|---|
| 1 | Cuerpo completo | ✅ **comparación directa LF 7/7 byte-idéntica** + `sha256_lf_vivo = sha256_lf_repo` |
| 2 | Firma | ✅ 7/7 exactas (verificado por OID contra `to_regprocedure`) |
| 3 | Retorno | incluido en `functiondef` ⇒ cubierto por la comparación directa |
| 4 | Lenguaje | ídem (`plpgsql` / `sql`) |
| 5 | Volatilidad | ídem |
| 6 | SECURITY INVOKER/DEFINER | ídem |
| 7 | `proconfig` | ídem |
| 8 | Owner esperado | ⚠️ no comparable en harness (owner local ≠ owner Supabase); Q1 del vivo lo reporta |
| 9 | ACL | ✅ Q3/Q3B: 0 `EXECUTE` a PUBLIC, 0 privilegios efectivos |
| 10 | Comentarios | `COMMENT ON` presente en los fragmentos; `functiondef` no los incluye, se comparan aparte |
| 11 | `triggerdef` | ✅ `fp_triggerdef` vivo `f6a53947…`; trigger reconstruido del repo idéntico |
| 12 | Tabla y función del trigger | ✅ `overrides_operativos` + `trg_guard_overrides()` (por OID) |
| 13 | Eventos y `tgtype` | ✅ AFTER I/U/D, no TRUNCATE, FOR EACH ROW (Q4 + Q7) |
| 14 | deferrable / initially deferred / enabled | ✅ CONSTRAINT, DEFERRABLE, INITIALLY DEFERRED, enabled |

**Único punto no verificable en harness:** el owner (#8), porque el rol dueño en Supabase no existe en el harness local. Q1 del vivo lo reporta; no afecta la autoridad del cuerpo.

---

## 4. Mapa de callers (Q6) — clasificado

| Objeto | Caller | Tipo |
|---|---|---|
| `fecha_hoy_ar` | `crear_bloqueo` | CALLER |
| `fecha_hoy_ar` | `crear_prereserva` | CALLER |
| `fecha_hoy_ar` | `crear_reserva_con_horario_pactado` | CALLER |
| `validar_no_eventos_comprometidos` | `validar_estado_override` | CALLER |
| `validar_estado_horario_final` | `validar_estado_override` | CALLER |
| `validar_estado_override` | `crear_override_horario` | CALLER |
| `validar_estado_override` | `crear_override_horario_puntual` | CALLER |
| `validar_estado_override` | `trg_guard_overrides` | CALLER |
| `trg_guard_overrides` | `crear_bloqueo` | COMENTARIO — **comentario, no caller** |

**`crear_bloqueo` en el cuerpo de `trg_guard_overrides()` es un comentario, no una invocación.** Verificado: línea 70 de `S1_TRIGGER`, `-- Capa 0: … como crear_bloqueo.` El resto son callers reales.

Estos objetos forman la **capa de guards de overrides** (S0/S1/S2): los validadores se llaman entre sí y desde `crear_override_horario` / `crear_override_horario_puntual` / el trigger; `fecha_hoy_ar` es un helper de fecha usado por tres funciones de reserva.

---

## 5. Actualización de H3

| Filas | Antes | Después | Prueba |
|---|---|---|---|
| 4, 8, 9, 86 | `CANDIDATO_REPO_HASTA_D2` / `PENDIENTE_D2` | **`SI` / `CONSOLIDAR`** | comparación directa LF (§3) |
| 16 | `~24 invocaciones` | **`21 invocaciones reales`** | barrido H7 |

`autoridad_actual = SI`: de 8 a **12**. `CONSOLIDAR`: de 8 a **12**. Fila 70 sigue `PENDIENTE_H1`.

**Autoridad total, no parcial.** Las filas 4, 8 y 86 crean varios objetos cada una (3 validadores; función + trigger; 2 funciones). **Todos** dieron match, así que la autoridad es total. Si alguno hubiera diferido, esa fila habría quedado en autoridad parcial explícita — no fue el caso.

---

## 6. Qué queda probado / qué no

### Probado
- Los 7 objetos fuera del pin existen en TEST con su firma exacta, sin overloads, sin exposición ACL.
- El trigger `trg_ov_guard` cumple las 13 propiedades y su `fp_triggerdef` coincide con el reconstruido del repo.
- `crear_bloqueo` en `trg_guard_overrides` es comentario.
- **Comparación directa cuerpo vivo vs repo: 7/7 byte-idénticos** (`comparacion_directa_lf = true`), con `sha256_lf_vivo = sha256_lf_repo` en los 7. Evidencia primaria: igualdad de texto + SHA-256 independiente en cada lado.
- La opción C se comporta como se diseñó: `fp_raw` difiere por EOL, `fp_lf` coincide, en los 7.

### No probado (y honestamente marcado)
- **Qué comando histórico creó cada objeto.** La comparación prueba que el repo describe fielmente el vivo, no que ese script fue el que corrió. Consistencia, no cadena causal.
- **El owner del vivo**, en el harness (sí en Q1 del vivo).
- **Que no exista otro objeto vivo del carril fuera de estos 7 + los 11.** D1 cubrió 11, D2 cubrió 7; juntos cubren lo que el barrido del repo identificó. Un objeto creado fuera del carril y no referenciado no sería detectado por este método.

### Límites de causalidad
El método compara **estado del repo vs estado del vivo**. No lee el log de la base. Toda afirmación de tipo *"este script produjo este objeto"* es una inferencia de consistencia, no un hecho medido — la misma reserva que en D1.

---

## 7. Veredicto final de D2

**El inventario DB del carril queda cerrado.** Los 7 objetos fuera del pin están medidos, congelados con doble fingerprint, y su autoridad en el repo está probada por comparación directa de cuerpos (7/7 byte-idénticos, `sha256_lf_vivo = sha256_lf_repo`). Sumados a los 11 de D1 y los 2 triggers de vigencias, **toda la superficie viva identificada del carril está inventariada y congelada**.

**La consolidación integral v1.13.0 continúa bloqueada por H1** — la política durable del artefacto A07 y su cadena de custodia. H1 es un bloqueante **independiente**: cerrar D2 no lo levanta.

| | |
|---|---|
| Inventario DB del carril | ✅ **CERRADO** — comparación directa 7/7 byte-idéntica |
| Consolidación v1.13.0 | ⛔ **bloqueada por H1** |
