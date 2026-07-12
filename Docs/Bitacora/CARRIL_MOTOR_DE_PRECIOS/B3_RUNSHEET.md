# B3 — Runsheet de ejecución (TEST) · **v2 — corregido**

**Frente:** Motor de Precios v2 · Bloque **B3 — Funciones del motor**
**Estado:** corregido tras la 1ª corrida en TEST (34/37). **`B3_FUNCIONES.sql` NO cambió** — no había bug del motor.
**Validación:** harness PostgreSQL 16.14 — **VERIFY 9/9**, **SMOKES 40/40**, verde tanto en **base limpia** como sobre **dataset ocupado simulado**.

---

## 0. Qué pasó en la 1ª corrida y qué se corrigió

| Síntoma en TEST | Causa raíz (probada) | Corrección |
|---|---|---|
| Fingerprint `2ff4203a…` ≠ harness `098f2fe7…` | El `.sql` llegó con **CRLF**; PostgreSQL guarda `\r\n` dentro de `prosrc` → el md5 crudo cambia **aunque el código sea byte-idéntico**. Reproduje el hash exacto de TEST aplicando el mismo archivo en CRLF. | **`B3_VERIFY.sql`**: fingerprint **normalizado** (elimina `chr(13)` antes de hashear) → estable entre entornos. Emite también el crudo + `funciones_con_CR` como diagnóstico. |
| `Sm24_estadia_larga` FAIL | Con ocupación real, `motivo_no_reservable = no_disponible` **gana por COALESCE** (correcto: la disponibilidad es la restricción más fuerte). La regla **sí** se disparaba: `estadia_larga_derivar` estaba en `restricciones[]`. | **Smoke**: asertar contra **`restricciones[]`** (acumulativo), no contra `motivo` (primero-gana). |
| `Sm34_congelamiento` FAIL | Rango hardcodeado ocupado → `congelada=false` (**correcto por diseño**: no se congela lo no vendible). | **Smoke**: **Buscador A** — busca en runtime una ventana realmente vendible. |
| `Sm35_cotizacion_vencida` FAIL | Cascada de Sm34 (`cot_id` NULL). | Se resuelve con Sm34. |
| *(hallazgo nuevo)* | `bloqueos` **y** `reservas` tienen **exclusion constraints**. Un fixture que solape con datos reales de TEST **aborta la transacción entera**. | **Smoke**: **Buscador B** — busca una ventana limpia de reservas/bloqueos/pre-reservas antes de insertar fixtures. |

**Veredicto: ningún bug del motor.** Los 34 tests que pasaron incluían todos los casos críticos (ordinales, eventos, disponibilidad, overrides, dinero, 5%, cero mutación, cero residuos).

## 1. Orden de ejecución

| Paso | Archivo | ¿Cambió? |
|---|---|---|
| 1 | `B3_FUNCIONES.sql` | **No** (idéntico al que ya ejecutaste; mismo hash). Re-ejecutable: es `DROP`+`CREATE`. |
| 2 | `B3_VERIFY.sql` | **Sí** — fingerprint normalizado. |
| 3 | `B3_SMOKES.sql` | **Sí** — dataset-agnóstico (buscadores + `restricciones[]`). |
| — | `B3_ROLLBACK.sql` | No. |

> Como ya tenés B3 aplicado en TEST, **podés correr solo VERIFY y SMOKES**. Reaplicar `B3_FUNCIONES.sql` es inocuo (idempotente).

## 2. Expected output

**`B3_VERIFY.sql`** → **9/9 PASS** + fingerprints:

```
b3_fingerprint_funciones_normalizado = 098f2fe7916e11ffa78cff37622b9064   <- el que importa
fp_crudo_diagnostico                 = (2ff4203a... si el archivo llego en CRLF; 098f2fe7... si LF)
funciones_con_CR                     = 13 si CRLF, 0 si LF   (informativo, no es un fallo)
n_funciones                          = 13
```

**El criterio de aceptación es el NORMALIZADO: `098f2fe7916e11ffa78cff37622b9064`.** El crudo depende del line ending del archivo y no indica divergencia de código. `funciones_con_CR = 13` solo te dice que el `.sql` viajó en CRLF; no afecta el comportamiento (PostgreSQL parsea igual, y los 40 smokes lo confirman).

**`B3_SMOKES.sql`** → **40 filas, todas `PASS`** (Sm0 + Sm1–Sm39).

`Sm0_precondiciones` informa qué ventanas eligieron los buscadores, p. ej.:
```
Sm0_precondiciones | PASS - ventana vendible=2026-08-10 | ventana limpia=cab3@2029-04-02
```
Si Sm0 sale FAIL, dice exactamente qué falta (ampliar el rango del buscador, o hay un evento real en las ventanas canónicas).

Los que fallaban ahora pasan, y quedaron **cubiertos explícitamente**:
```
Sm24_estadia_larga ........... PASS - 10 noches derivan; el motor cotiza igual (ok=true)
Sm34_congelamiento ........... PASS - congela con TTL sobre ventana libre; NO crea pre-reserva ni reserva
Sm35_cotizacion_vencida ...... PASS - vencida rechazada; vigente se lee OK
Sm38_precedencia_motivo ...... PASS - motivo=no_disponible (gana); restricciones acumulan ambas   <- NUEVO
Sm39_no_congela_no_vendible .. PASS - congelar rechaza lo no vendible; cero filas nuevas          <- NUEVO
Sm37_cero_residuos ........... PASS - cero residuos; grilla (32) y config restauradas
```

## 3. Robustez de la suite (cómo se validó)

La suite se corrió en el harness en **dos escenarios**:
1. **Base limpia** → 40/40.
2. **Dataset ocupado simulado** (bloqueos en las fechas que fallaban en TEST **y** en las primeras ventanas candidatas de ambos buscadores) → **40/40**. Los buscadores se reubicaron solos (`2026-08-03` → `2026-08-10`; `cab1` → `cab3`).

**Regla de diseño nueva (para todos los smokes futuros del frente):** las **reglas de venta** se asertan contra `restricciones[]` (acumulativo). `motivo_no_reservable` es *"el primero gana"* y solo se asierta cuando el fixture lo controla (p. ej. Sm8, donde `no_disponible` es la de máxima prioridad).

## 4. Integridad

```
B3_FUNCIONES.sql  f869fd9e33bbe374d9429bcf42d677221c3d6efcb73ef08ac6fd368a7a34b893   (SIN CAMBIOS)
B3_VERIFY.sql     40723a72e5f41a911728ff7ba57252410d3d5bd1912138f004f00db9160bbe3f   (nuevo)
B3_SMOKES.sql     186f79a25a5acbba5dedb40b4bbf72aba5bcb2af17f38fb9b26b8250406d2213   (nuevo)
B3_ROLLBACK.sql   3c027fb286c99f39a27b4a49b6730ef75f7ae939df5f296f0671df14708e2293   (SIN CAMBIOS)
```

**Fingerprints:**
```
funciones B3 (NORMALIZADO)    : 098f2fe7916e11ffa78cff37622b9064   <- criterio de aceptacion
estructura B2A (debe seguir)  : da52a16c045689523a5f1f113f513a87   <- V8 lo verifica
```

## 5. Criterio de cierre

```
VERIFY  9/9   PASS
SMOKES  40/40 PASS
fingerprint NORMALIZADO = 098f2fe7916e11ffa78cff37622b9064
```

## 6. Lecciones candidatas del frente (no acuñadas)

- **Fingerprint de funciones**: hashear siempre sobre `prosrc` **normalizado** (`replace(prosrc, chr(13), '')`). El crudo es sensible al line ending del archivo y produce falsos positivos de divergencia.
- **Smokes contra dataset real**: nunca asumir que una fecha/cabaña está libre. Buscar la ventana en runtime.
- **Exclusion constraints** (`bloqueos`, `reservas`): un fixture solapado **aborta la transacción entera** (no da FAIL, da ERROR). Verificar solapamiento antes de insertar.
- **`motivo_no_reservable` es "primero gana"; `restricciones[]` es acumulativo.** Testear reglas contra el segundo.

---
**Alcance sin cambios:** B3 = solo funciones. No `crear_prereserva`, no gateway/portal, no OPS, no estructura. B3.1 (override de capacidad) queda para después del cierre.
