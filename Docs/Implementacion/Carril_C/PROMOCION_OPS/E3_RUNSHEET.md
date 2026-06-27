# Bloque E3 — A07 + A10-MP (JSON generados) + auditoría de escritura

**Etapa:** Promoción Carril C a OPS — Bloque E, sub-grupo **E3 (escrituras sensibles)**.
**Método:** **import de JSON generado** (no duplicación manual). Los dos JSON ya vienen transformados y verificados estructuralmente.
**Artefactos:** `portal-a10mp-registrar-cobro__OPS.json`, `portal-a07-crear-reserva__OPS.json`, `E3_smoke_seguridad_escritura__OPS.ps1`, `E3_gate_no_escribe.sql`, `E3_A07_teardown.sql`.

---

## 0. Diagnóstico de tu A10-MP roto

El error **"action no coincide con el endpoint"** es el *action binding* (D-C-41): el wrapper compara `body.action` contra su `EXPECTED_ACTION` y rebota si no coinciden. Tu A10-MP armado a mano quedó con el `EXPECTED_ACTION` de **W10** (`cobranza.registrar_saldo`) — casi seguro porque lo duplicaste de W10 y cambiaste el path pero no esa constante. El gateway manda `cobranza.registrar_cobro`, el wrapper espera `registrar_saldo` → rebote.

**El JSON generado lo arregla:** verifiqué que `EXPECTED_ACTION = 'cobranza.registrar_cobro'` y que **no hay ni una mención de `registrar_saldo`** en todo el workflow.

> 🔴 **Antes de importar:** **borrá tu `portal-a10mp-registrar-cobro__OPS` manual** (el roto). Si lo dejás, su webhook path colisiona con el del JSON que vas a importar (misma instancia n8n, mismo path).

---

## 1. Import de los 2 JSON a n8n OPS

Por cada archivo (`portal-a10mp-registrar-cobro__OPS.json` y `portal-a07-crear-reserva__OPS.json`):

1. n8n → **Import from File** → seleccionás el JSON.
2. **Reasignar credencial:** n8n marca los nodos Postgres con credencial faltante (el JSON trae `vita_supabase_ops` con id placeholder). Seleccioná `vita_supabase_ops` en cada uno.
   - A10-MP: **3 nodos PG** (`leer_ambiente`, `PG_cobro_mp`, `PG_verif_post`).
   - A07: **6 nodos PG** (`leer_ambiente`, `PG-0 precheck_reserva`, `PG-1 crear_prereserva`, `PG-2 lock_precheck_pago`, `PG-3 confirmar_reserva`, `PG-4 recheck_reserva_post_confirmar`).
3. **HMAC:** en `validar_firma_ts_rol`, reemplazá `__PEGAR_SECRETO_O_USAR_VARIABLE__` por el **`VITA_HMAC_SECRET` de OPS** (el mismo del gateway).
4. **Guardar + Activar.**

Lo que **ya viene resuelto en el JSON** (no tocás): path `__OPS`, `EXPECTED_ACTION` correcto, y en A07 el `Call` apunta a `fHzMFj7pGMKuYEOb` (8C-bis OPS) con `entorno` autoresuelto desde `leer_ambiente.valor` (sin hardcode).

---

## 2. Smoke de SEGURIDAD (no escribe) — auditar antes de cualquier escritura

`E3_smoke_seguridad_escritura__OPS.ps1`. Editás el bloque CONFIG por wrapper (viene listo para A10-MP; para A07 hay comentarios para descomentar). Corre 4 probes, **ninguno escribe** (todos rebotan antes de los nodos PG):

- **P1** action incorrecto → `accion_desconocida` ← *esto es lo que te falló; confirma que un action equivocado NO escribe.*
- **P2** firma inválida → `firma_invalida`.
- **P3** rol `jenny` → `rol_no_permitido`.
- **P4** `ambiente=test` → `ambiente_incorrecto`.

### Confirmación dura de "no escribe"
1. Corré `E3_gate_no_escribe.sql` (read-only) → anotá los 3 conteos.
2. Corré el smoke de seguridad (los 4 probes).
3. Corré `E3_gate_no_escribe.sql` de nuevo → los conteos deben ser **idénticos**. Si no cambiaron, ningún probe escribió.

Hacé esto para **A10-MP y A07** antes de pasar a escritura real.

---

## 3. Escritura real CONTROLADA (opcional, cuando vos decidas)

Hasta acá auditaste sin escribir. Cuando quieras validar el camino feliz completo (alta real + aviso), de forma controlada:

### A07 — crear 1 reserva de prueba + verificar aviso + limpiar
1. Hacé **un** alta vía A07 (UI o probe firmado) con datos de una reserva de prueba. Anotá el `id_reserva` que devuelve (`envelope.data.id_reserva`).
2. Verificá que la reserva quedó creada y que **el aviso 8C-bis se disparó con `entorno=ops`** (llega el mail a Jennifer — avisale que es una prueba, o usá un destinatario de prueba si el sub-workflow lo permite).
3. **Cleanup:** abrí `E3_A07_teardown.sql`, reemplazá `<ID_RESERVA>` por el id del paso 1, corré todo. Borra pago(s) + reserva + pre_reserva en orden, con gate `ops`. El aviso no deja nada en DB (solo mail).

### A10-MP — registrar 1 cobro de prueba
A10-MP escribe en `pagos`. Si querés probar el camino real, hacelo sobre una reserva de prueba y borrá el/los pago(s) creado(s) con un DELETE acotado por `id_reserva` (gate `ops`, mismo patrón que el teardown de A07). Si preferís, te armo un `E3_A10MP_teardown.sql` específico — avisame.

---

## 4. Cierre de E3 / Bloque E

- [ ] A10-MP manual roto borrado; JSON `portal-a10mp-registrar-cobro__OPS` importado, credencial + HMAC OK, activo.
- [ ] A07 JSON `portal-a07-crear-reserva__OPS` importado, credencial + HMAC OK, activo, Call a `fHzMFj7pGMKuYEOb`.
- [ ] Smoke de seguridad P1-P4 verde en ambos.
- [ ] Gate de no-escritura: conteos idénticos antes/después en ambos.
- [ ] (Opcional) escritura real controlada + teardown OK.

Con E3 cerrado, los **13 wrappers `__OPS`** están arriba y el Bloque E queda completo. El siguiente es el **Bloque H** (smokes read-only end-to-end vía gateway por rol + un alta controlada con su aviso). El "Bloque F" del plan ya quedó **fusionado** acá: el A07 OPS trae la rama de aviso apuntando al 8C-bis OPS.

> **Aviso de método (E3):** estos dos son **import de JSON** (no duplicación). Lo único que editás tras importar es la credencial (reasignar a `vita_supabase_ops`) y el HMAC (`__PEGAR_` → secreto de OPS).
