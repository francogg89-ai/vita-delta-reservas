# Prompt para crear entorno nuevo — bootstrap v1.12.0

Este kit reconstruye un entorno Supabase **nuevo/vacío** paritario con el canónico
`Docs/Implementacion/6B_SCHEMA_SQL.md v1.12.0`. Se **genera de forma reproducible**
desde el canónico con `gen_bootstrap_v1_12_0.py` (Artefacto A de Bloque C):

1. Localiza `# PARTE B/C/D` por regex.
2. Por cada `## BLOQUE …` toma **el primer fence ```sql** como DDL (regla R2) y
   **excluye** los fences de "Verificación post-ejecución", "Rollback", "Test
   funcional" y "Monitoreo".
3. Emite banners `-- ═══ / -- BLOQUE N — título(sin backticks) / -- ═══` y termina
   en un único salto de línea.
4. **PARTE B es inmutable** v1.9.0→v1.12.0: el generador exige que su cuerpo (sin
   header) sea **byte-idéntico** al del kit v1.9.0; si difiere, **aborta sin escribir**.
5. `00_PRECHECK` y `01_VERIFY_PARTE_B` se **cargan verbatim** (solo re-sello de
   versión en el header); `02_VERIFY`, `03_VERIFY_FINAL`, este `Prompt` y el
   `README` son **autoría** actualizada a v1.12.0, embebidos como plantillas
   auditables en el generador.

## Qué incorpora v1.12.0 respecto de v1.9.0

- **v1.10.0** — lecturas de cuenta corriente `cuenta_corriente_viva` /
  `cuenta_corriente_detalle` (+ REVOKE), PARTE C.
- **v1.10.1** — helper `pct_operativo_vigente()` (+ REVOKE) y **seed** `pct_operativo`
  (`configuracion_general`, `valor='0.25'`, `tipo_valor='numeric'`, `editable=false`).
- **v1.11.0** — retiro desde saldo vivo: `portal_usuarios.id_socio` (FK/UNIQUE/CHECK),
  tabla `portal_idempotencia_cc`, `registrar_retiro_desde_saldo_vivo` (PARTE C),
  `portal_registrar_retiro(jsonb)` (PARTE D), REVOKE, D5 extendido.
- **v1.12.0** — snapshot con detalle fino + L3: tablas `liquidacion_participacion` /
  `liquidacion_gasto` / `liquidacion_incidencia`, 6 triggers de inmutabilidad,
  `registrar_snapshot_periodo` extendida, `cuenta_corriente_historico(date)` /
  `cuenta_corriente_historico_acumulados()`, REVOKE, hardening C12/C14.

## Set objetivo (paridad v1.12.0)

**35 tablas / 38 funciones / 16 triggers de inmutabilidad** en total. Carril B:
**12 tablas / 27 funciones**. Portal: **3 tablas / 2 funciones**. Seed `pct_operativo`.
Todo endurecido (REVOKE de PUBLIC/anon/authenticated/service_role).

> Las huellas históricas `TOTAL_CARRIL` y `TOTAL_PORTAL` son **referencia histórica**:
> v1.11.0/v1.12.0 las extienden con deltas estructurales intencionales; un bootstrap
> v1.12.0 **no** las reproduce, las extiende. La paridad se mide contra el set v1.12.0.

## Lo que el kit NO incluye (vive fuera)

Seed real de `portal_usuarios`, usuarios de Auth, backfill socio↔usuario, HMAC,
Project IDs/URLs reales, secretos, datos de huéspedes/PII, datos reales de OPS.
El bootstrap deja **solo estructura**; los datos operativos viven fuera del canónico.
