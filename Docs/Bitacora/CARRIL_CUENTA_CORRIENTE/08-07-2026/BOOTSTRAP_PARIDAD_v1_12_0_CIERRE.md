# Bloque C — Paridad del bootstrap kit con el canónico v1.12.0 (cierre de P-CC-4)

**Fecha:** 2026-07-08 · **Frente:** Cuenta Corriente / canonicalización (Bloque C) · **Commits:** `2c49e0e` (regenerar kit), `81964a4` (hotfix footer)

## Contexto

Tercer y último bloque del paquete de canonicalización CC. Bloque A dejó el canónico en v1.12.0; Bloque B acuñó los satélites; **Bloque C salda la deuda de paridad del bootstrap kit (P-CC-4)**: el kit vivía en `bootstrap_entorno_nuevo_v1.9.0/`, rezagado (v1.10.0 lecturas CC + v1.10.1 pct + v1.11.0 retiro + v1.12.0 snapshot detalle fino/L3).

## Qué creó A (`gen_bootstrap_v1_12_0.py`)

Carpeta `Docs/Implementacion/bootstrap_entorno_nuevo_v1.12.0/` (9 archivos), regenerada **reproduciblemente** desde el canónico v1.12.0 por **regla R2**: los 3 bootstrap (PARTE B/C/D) por extracción literal (primer fence `sql` por bloque, excluyendo Verificación/Rollback/Test/Monitoreo); `00_PRECHECK` y `01_VERIFY_PARTE_B` carry verbatim + re-sello de versión; `02_VERIFY`/`03_VERIFY_FINAL`/`Prompt`/`README` autoría v1.12.0 (02_VERIFY 12/27/16 + seed; 03_VERIFY_FINAL FK por columna, `portal_idempotencia_cc`, `portal_registrar_retiro`, `id_socio`). Set objetivo: **35/38/16**, Carril B 12/27, portal 3/2, seed `pct_operativo`.

## Qué retiró A

`Docs/Implementacion/bootstrap_entorno_nuevo_v1.9.0/` del working tree (queda en el historial de git). No dos kits vivos.

## Qué corrigió B (`patch_footer_canonico_v1_12_0.py`)

Micro-hotfix del footer `# FIN DEL DOCUMENTO` del canónico (Estado→v1.12.0 + snapshot/L3; "Próximos pasos" reencuadrados; puntero de trazabilidad). 3 ediciones `count==1` + reverse-identity, un único hunk, LF preservado; sin tocar SQL/PARTE/BLOQUE/changelog.

## Validaciones del generador

Harness PostgreSQL 16.14 + `pglast` con stubs Supabase (roles Data API, `auth.users`, pg_cron stub como extensión → el kit corre verbatim): `--check` OK, apply + `--retire-old` OK, reconstrucción 01→03 verde (C14/D5), verifies **`PARTE_B_OK`/`PARTE_C_OK`/`ENTORNO_COMPLETO_OK`**, conteos 35/16 (funciones 42 raw = 13 base + 27 C + 2 D; curado 38 = 9+27+2, 0 espurias), nominales OK, REVOKE/hardening OK (0 grants Data API en tablas nuevas; EXECUTE L3 = 0), EOL LF, **byte-proof PARTE B PASS**, scan sin Project Refs reales ni patrones sensibles (detección **por forma**, sin literales de refs en el generador).

## Scope negativo

C **no** tocó: canónico `6B_SCHEMA_SQL.md`, el bootstrap kit, gateway, n8n, frontend, `portal-api`, Supabase, TEST, OPS, git. **No** avanzó: primera foto real OPS, cierre asistido, exposición CC/L3, retiros/L1/L2/reembolsos. **No** movió `P-L3-01`/`P-L3-02`. La regeneración A / hotfix B fueron bloques previos (`2c49e0e`/`81964a4`); C es solo el cierre documental en satélites.

## Decisiones

- **Carpeta nueva + retiro de la vieja** (no parchar in-place): evita doble fuente ejecutable; el kit viejo queda en el historial de git.
- **Re-extraer del canónico** (no parchar el kit v1.9.0): garantiza paridad estructural real, no incremental.
- **Sin Project IDs reales en ningún artefacto nuevo**, ni como blocklist: sanitización y detección por forma genérica (`[a-z]{20}`).

## Lección

**R2 (primer-fence-`sql`-por-bloque) + prueba byte de PARTE B.** La extracción determinística del canónico se validó exigiendo que el cuerpo de PARTE B (inmutable v1.9.0→v1.12.0) fuera **byte-idéntico** al del kit v1.9.0; cualquier deriva aborta la generación. Es la garantía de que R2 no introduce cambios silenciosos y de que la paridad es real, no aproximada.

## Estado final

Kit vigente `bootstrap_entorno_nuevo_v1.12.0/` paritario con el canónico v1.12.0; `v1.9.0/` retirado (en git); satélites consistentes; **P-CC-4 ✅ CERRADO**. Paquete de canonicalización CC (A/B/C) completo.

## Pendientes posteriores (fuera de P-CC-4)

- **Corrida end-to-end del bootstrap v1.12.0 (01→03) sobre un Supabase nuevo** (validado contra PG limpio, aún no sobre un Supabase real).
- **Primera foto real en OPS + cierre asistido** (`P-L3-01`/`P-L3-02`).
- **Exposición de la capa CC/L3 en el portal operativo.**
- (No relacionados: UI del retiro, reembolsos, Mercado Pago, web pública, bot.)
