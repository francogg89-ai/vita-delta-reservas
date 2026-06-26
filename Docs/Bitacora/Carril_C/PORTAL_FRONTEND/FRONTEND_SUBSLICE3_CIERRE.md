# Cierre — Frontend Sub-slice 3 (Portal Operativo Interno · Carril C): publicación TEST + piloto operativo

**Carril:** C — Portal Operativo Interno (frontend).
**Entorno:** TEST (`vita-delta-test`, ref `bdskhhbmcksskkzqkcdp`). **No se tocó backend, gateway `portal-api`, wrapper n8n, OPS, el canónico (`6B_SCHEMA_SQL.md` v1.8.1), W10 ni el contrato.**
**Fecha de cierre:** 2026-06-26.
**Base:** `FRONTEND_SUBSLICE2_CIERRE.md` (4 escrituras) · `FRONTEND_SUBSLICE1_CIERRE.md` (8 lecturas) · `FRONTEND_SUBSLICE0_CIERRE.md` (shell) · `CONTRATO_FRONTEND_PORTAL_v1.md`.
**Naturaleza:** **no** es una matriz técnica de casos (la QA por bloque y la QA por rol de A10-MP ya estaban hechas y no se repiten): es un **piloto operativo controlado** en TEST con los usuarios reales en sus roles.
**Stack / artefacto:** React 18 + Vite 5 + TypeScript strict + Tailwind 3; `vite build` → `dist/`, publicado como **build estático**.
**URL TEST:** `https://vita-delta-reservas.vercel.app`.

---

## 1. Alcance cerrado

Publicar el portal completo (8 lecturas + 4 escrituras, ya construido y validado por bloque en los sub-slices 0/1/2) en un **link TEST real** cableado a Supabase / `portal-api` de TEST, y correr un **piloto de uso real** con los usuarios reales por rol:

- **Jenny** revisando el calendario de limpieza;
- **Vicky** cargando reservas, bloqueos, gastos y cobros;
- **Rodrigo y socios** revisando saldos, ingresos, gastos e histórico.

Foco: recoger del uso real bugs, problemas de UX, textos confusos o faltantes. Solo se permitían **fixes menores de frontend** (textos, claridad, rutas). Backend, gateway, n8n, OPS, canónico y contrato **fuera de alcance**. **No se fue a producción.**

## 2. Deploy + banner (resumen de entrega)

| Pieza | Qué | Detalle |
|---|---|---|
| Host | Vercel (build estático) | Root Directory `Apps/portal-operativo`; build `npm run build`; output `dist`; **fallback SPA** por `vercel.json` (todas las rutas → `/index.html`, por `react-router-dom`); **sin `base`** (sirve en raíz). |
| Env vars | Solo TEST, browser-safe | `VITE_SUPABASE_URL` = `https://bdskhhbmcksskkzqkcdp.supabase.co`, `VITE_SUPABASE_ANON_KEY` (anon de TEST). En el panel del host, **nunca** en el repo, **nunca** `service_role`. Gateway = `${VITE_SUPABASE_URL}/functions/v1/portal-api`. |
| Auth | Sin cambios | Login **email/password** con usuarios ya creados (Auto Confirm) → **no** se tocan Site URL / Redirects de Supabase Auth. |
| Banner | Marca de ambiente | `src/lib/ambiente.ts` deriva el ambiente de `VITE_SUPABASE_URL` (ref TEST → `'test'`; otra cosa → `'desconocido'`, defensivo). `src/app/BannerAmbiente.tsx`: barra fija arriba de todo (visible **pre-login**) + título de pestaña diferenciado. `src/App.tsx` la monta y compensa con `pt-8` (sin romper el `min-h-full` de las pantallas). |
| Usuarios | Confirmados 5/5 | Diagnóstico read-only: jenny/vicky + franco/rodrigo/remo, todos en Auth y en `portal_usuarios`, rol correcto, `activo=true`. |

Verificación de build (clon limpio): `typecheck` + `build` **EXIT 0**, **120 módulos** (118 + `ambiente.ts` + `BannerAmbiente.tsx`), JS ~453 kB. Vite **inyecta** `VITE_*` en build-time → el banner sale del mismo dato que apunta el build a TEST.

## 3. Decisiones lockeadas durante el sub-slice 3 (🔒 no reabrir)

**D-FE-29 — Banner de ambiente por discriminación de `VITE_SUPABASE_URL` (sin `VITE_AMBIENTE`).** El portal marca el ambiente leyendo `VITE_SUPABASE_URL`: contiene el ref del proyecto TEST (`bdskhhbmcksskkzqkcdp`) → `'test'` (banner amarillo "AMBIENTE DE PRUEBA · TEST"); cualquier otra cosa → `'desconocido'`, **estado defensivo** (banner rojo "AMBIENTE NO RECONOCIDO - NO OPERAR"). **No** hay `VITE_AMBIENTE`: la única fuente de verdad del ambiente es la URL del build (mismo criterio que el resto del proyecto, que discrimina por URL/identidad y nunca por payload). El banner es **fijo arriba de todo** (visible pre-login) y diferencia el **título de pestaña**. El reconocimiento de OPS (su ref → sin banner / rótulo de producción) se agrega en la promoción a OPS (**P-FE-09**); hasta entonces todo lo no-TEST cae en `'desconocido'` a propósito (un build mal configurado grita en vez de parecer producción).

**D-FE-30 — Deploy del frontend TEST = build estático en Vercel + fallback SPA.** El Portal Operativo TEST se publica como build estático (`vite build` → `dist/`) en **Vercel**: Root Directory `Apps/portal-operativo`, build `npm run build`, output `dist`, fallback SPA por `vercel.json` (rutas → `/index.html`), sin `base`. Solo dos env vars de TEST y browser-safe (`VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY`, en el panel del host, nunca `service_role`). Login email/password → sin tocar Site URL / Redirects. Cloudflare Pages queda como alternativa equivalente documentada (usa `public/_redirects` `/* /index.html 200` en vez de `vercel.json`). URL TEST: `https://vita-delta-reservas.vercel.app`.

## 4. Lecciones (🔒)

**L-FE-08 — Vite inyecta `VITE_*` en build-time; el banner hace el ambiente autoverificable.** `import.meta.env.VITE_*` se resuelve/inyecta en **build-time** (no en runtime): un build hecho con `VITE_SUPABASE_URL` apuntando a TEST deja el ref inlineado en el bundle. Eso permite discriminar ambiente por la URL del proyecto (sin una env var de ambiente aparte, que duplicaría la fuente de verdad) y lo hace **autoverificable**: como el banner se deriva de la misma URL que apunta el frontend a TEST, **banner amarillo ⟺ la env var apunta a TEST**; si la env falta o está mal, el estado defensivo (rojo) lo grita. Corolario: un build sin configurar **no** debe parecerse al portal real — por eso lo no-reconocido es defensivo, no silencioso.

**L-FE-09 — Piloto previo al inicio contable: los reportes con floor de fecha se ven vacíos; hay que avisarlo.** La contabilidad operativa arranca el **2026-07-01** (D-NEG-02) y los reportes económicos del portal tienen ese floor (A25 ingresos, A13 gastos; el `periodo_desde` se recorta al piso). En un piloto/UAT corrido **antes** de esa fecha esos reportes se ven **vacíos o en cero** con los defaults (el piso queda por delante de "hoy"), y un cobro/gasto cargado "hoy" no aparece ahí. Es comportamiento **correcto**, no un bug, pero confunde a un usuario real: la verificación de una escritura de cobranza se hace por el **saldo que baja** en "Saldos a cobrar" (sin floor), no por "Ingresos cobrados", y las instrucciones del piloto lo dicen explícito. General: al testear con usuarios reales sobre reglas con cortes temporales, anticipar y avisar los "vacíos esperados".

## 5. Entregables del piloto

- **Frontend TEST publicado** en un link real, cableado a Supabase / `portal-api` de TEST, con el **banner "TEST" visible** (precondición obligatoria, cumplida antes de compartir el link).
- **Instrucciones cortas por rol** (Jenny / Vicky / socios): qué link abrir, con qué cuenta, qué probar acotado al rol y cómo reportar. Cada una dice explícito que es **AMBIENTE TEST**, que **no se carguen datos reales de huéspedes** y que se **reporte en el tracker**.
- **Tracker de feedback** (planilla, con desplegables): `fecha · usuario · rol · pantalla/ruta · acción intentada · resultado esperado · resultado observado · problema · severidad (blocker/menor/mejora/pendiente OPS) · estado (abierto/corregido/pendiente OPS/descartado) · notas`.

## 6. Gates de publicación (los 7, en verde)

| # | Gate | Verdicto |
|---|---|---|
| 1 | `typecheck` + `build` EXIT 0 | OK |
| 2 | Deploy TEST publicado | OK (`https://vita-delta-reservas.vercel.app`) |
| 3 | Banner "AMBIENTE DE PRUEBA · TEST" visible en el deploy | OK (amarillo) |
| 4 | Env vars del host → TEST (`…bdskhhbmcksskkzqkcdp.supabase.co`) | OK (probado por el banner) |
| 5 | Incógnito sin login = solo login + banner, nada operativo | OK |
| 6 | Login Jenny / Vicky / socio | OK |
| 7 | Sin `service_role` ni secretos (frontend, repo, logs, instrucciones) | OK (escaneo de repo: 0 `service_role`, 0 claves `eyJ…`, 0 valores HMAC, sin `.env` real trackeado) |

## 7. Resultado del piloto

**OK.** Los usuarios reales operaron en sus roles y **entendieron el flujo sin asistencia**; **cero blockers** y **sin fixes menores de frontend pendientes** (confirmado por Franco, 2026-06-26). El piso contable del 1/7 (L-FE-09) quedó anticipado en las instrucciones, así que no generó falsos reportes.

## 8. Pendientes / no implementado (honesto, sin inventar)

- **P-FE-09 (nuevo, para OPS):** extender el reconocimiento del banner al ref de OPS al promover (hoy lo no-TEST cae en el estado defensivo a propósito).
- **P-FE-08 (sigue):** "Ver detalle" A12→A05 por `?id_reserva` no implementado; **no** surgió como blocker en el piloto. UX diferida.
- **Para la promoción a OPS (no se resuelven acá):** **P-FE-01** (catálogo real de cabañas en vez de `CABANAS_TEST`), **P-C-7** (CORS del gateway al origin real), GRANTs/RLS y **seed real de `portal_usuarios`** en OPS, y el deploy OPS (reusa el setup Vercel de D-FE-30 con env vars de OPS).

## 9. Propagación a satélites + estado

Propagado en pasada coordinada (formato adaptado a cada satélite; contenido técnico preservado): `DECISIONES_NO_REABRIR.md` (D-FE-29/30), `Lecciones_Aprendidas.md` (L-FE-08/09), `Pendiente_pre_produccion.md` (P-FE-09), `ESTADO_ACTUAL_VITA_DELTA.md` (sub-slice 3 como etapa actual), `CLAUDE.md` (entrada sub-slice 3). EOL de cada archivo preservado (LF).

**Estado:** **sub-slice 3 (publicación TEST + piloto) cerrado — piloto TEST OK.** Con esto cierra la **Etapa 2 (Frontend TEST)** del Carril C. **Próximo: preparar la promoción coordinada del Carril C a OPS** (se para antes para sumar un par de detalles pedidos para OPS). A10 en el frontend = `cobranza.registrar_cobro` (B5), no se reabrió.
