# FRENTE_MP_02_PREP_RUNSHEET.md — Preparación operativa en Mercado Pago Developers

**Frente:** Pagos Autónomos / Mercado Pago (separado del Carril C)
**Etapa:** MP-02 — Preparación operativa en Mercado Pago Developers
**Antecedente:** MP-01 = `FRENTE_MP_PAGOS_AUTONOMOS_DISENO.md` (diseño, D-MP-01 a D-MP-11)
**Estado:** ✅ Runsheet operativo — listo para que Franco ejecute en el panel. **Solo panel.** No conecta nada real.
**Tipo:** Runsheet + registro de secretos (placeholders) + checklist de aceptación
**Ejecuta:** Franco. Claude no ejecuta nada.
**Regla del frente:** **No** tocar Supabase, n8n, OPS, TEST, portal operativo, `portal-api` ni el schema canónico. **No** generar código. **No** conectar nada real.

> ⚠️ **Sobre rutas del panel:** las rutas y nombres de menú de Mercado Pago **pueden variar según la UI** del momento. Donde aparece "(puede variar según UI)", confirmá el label real en pantalla; el **concepto** es lo que importa, no el texto exacto.

> 🔒 **Sobre secretos:** en todo este runsheet, **ningún valor real** de credencial se escribe acá, ni se pega en chats, ni se sube al repo, ni se deja en capturas sin tapar. Solo se registran **placeholders** y evidencia no sensible.

---

## 0. Objetivo y límites de MP-02

**Objetivo:** dejar lista la base operativa en Mercado Pago Developers (aplicación, credenciales de **prueba**, reconocimiento de webhooks, relevamiento de medios, usuarios y tarjetas de prueba) para desbloquear MP-03/MP-04, **sin** activar producción y **sin** conectar nada.

**Lo que MP-02 NO incluye (importante para no perder tiempo):**

- **No** hay test end-to-end real del webhook, porque **todavía no existe un endpoint público del backend**. Eso es MP-03/MP-04.
- El **Webhook Secret puede quedar pendiente**: solo se genera al **guardar** configuración de webhook, y eso requiere una **URL HTTPS real**. Si no hay URL real de prueba controlada por Franco, **no se guarda** y el secret queda para más adelante.
- La **exclusión real de medios** (offline/`ticket`) **no** se hace acá: vive en la *preference*, con backend. En MP-02 solo se **releva** dónde y cuáles.

---

## 1. Runsheet paso a paso por bloques

### Bloque A — Aplicación + credenciales de prueba

**A.1** Ingresar al panel de desarrolladores: `mercadopago.com.ar/developers/panel` → botón **"Tus integraciones"** (puede variar según UI), iniciando sesión con la **cuenta real de Vita Delta** (no con un usuario de prueba).

**A.2** **Crear o verificar** la aplicación de Vita Delta: **"Crear aplicación"** (puede variar según UI). Al crearla:
- Nombre: algo identificable (ej. *Vita Delta Reservas*).
- Tipo de pago a integrar: **Pagos en línea**.
- ¿Plataforma de e-commerce? **No**.
- Producto a integrar: **Checkout Pro** (o "Pagos online"; puede variar según UI).

**A.3** Entrar a **"Detalles de la aplicación"** → menú lateral izquierdo → **"Credenciales de prueba"** (bajo "Pruebas"; puede variar según UI). Ahí están la **Public Key** y el **Access Token** de **prueba** (se crean automáticamente con la app).

**A.4** Registrar esas credenciales de prueba en el **gestor de secretos** de Franco, con los **nombres placeholder** de la tabla de la Sección 2. **No** pegarlas en este documento ni en ningún chat.

**A.5** Producción: **NO activar**. Dejar la sección "Credenciales de producción" sin tocar (activarla pide datos del negocio; no corresponde en MP-02).

---

### Bloque B — Webhooks + Webhook Secret (alcance corregido)

> **Regla de oro del Bloque B:** en MP-02 se hace **"reconocimiento seguro"**, no se guarda configuración con una URL inventada. **Solo se permite guardar configuración de webhook si existe una URL HTTPS real, controlada y de prueba.** Si no existe, el **Webhook Secret queda pendiente** para MP-03/MP-04 (cuando haya receptor/endpoint de prueba).

**Reconocimiento seguro (permitido ahora):**

**B.1** En la app: menú lateral → **"Webhooks"** → **"Configurar notificaciones"** (puede variar según UI).

**B.2** **Identificar dónde se cargan las URLs.** Vas a ver (típicamente) una pestaña **"Modo productivo"** que pide una **URL HTTPS** + credenciales productivas, y la posibilidad de una **URL de prueba** que, con credenciales de prueba, sirve para verificar antes de producción (puede variar según UI). **Solo mirar**, no cargar nada inventado.

**B.3** **Revisar qué eventos existen**, en particular el evento **"Pagos"** (es el que vamos a usar). Solo reconocimiento.

**B.4** **Ubicar el simulador** de notificaciones de webhooks (en la misma pantalla de configuración; función lanzada por MP). Reconocer dónde está.

**B.5** **Entender el mecanismo del secret:** la clave secreta (**Webhook Secret**) se **genera automáticamente al guardar la configuración** (URLs + eventos), y aparece en la propia pantalla de webhooks. No caduca; su rotación no es obligatoria pero sí recomendable.

**Diferido (no hacer ahora, salvo que exista URL HTTPS real de prueba):**

**B.6** **Guardar configuración de webhook:** **diferido**. Solo se hace si Franco ya tiene una **URL HTTPS real, controlada y de prueba** que pueda recibir el POST. En MP-02 no hay endpoint → **no guardar**.

**B.7** **Webhook Secret:** si no se guardó configuración (caso normal de MP-02), **queda pendiente** → pasa a MP-03/MP-04. Marcarlo así en la tabla de secretos (estado "Pendiente").

**B.8** **Simulador:** solo es **realmente usable** si hay una URL configurada que pueda **recibir** la prueba. Sin endpoint, el simulador no aporta validación real; queda como reconocimiento visual nada más.

---

### Bloque C — Medios de pago (solo reconocimiento)

> Acá **no se excluye nada**. La exclusión de `ticket`/offline vive en la *preference*, recién con backend (D-MP-02). MP-02 es relevamiento, insumo directo para **D-MP-11**.

**C.1** Entender **dónde** se configuran los medios en Checkout Pro: en una integración propia, la exclusión se hace **en la *preference*** (campo `payment_methods`, con `excluded_payment_types` / `excluded_payment_methods`), no con un switch global del panel. Dejar esto claro como criterio.

**C.2** **Relevar la lista real de tipos y medios de pago de Argentina** disponibles para Checkout Pro (vía la documentación oficial de medios de pago de MP y/o la referencia de `payment_methods`). Anotar:
- qué tipo corresponde al **efectivo offline** (`ticket`) → es el que se excluirá;
- qué otros tipos hay (tarjetas, débito, transferencia/CVU, `atm`, dinero en cuenta, etc.).

**C.3** Dejar registrado el insumo para **D-MP-11**: qué medios **no-ticket** son candidatos a habilitarse en el flujo automático **quedan sujetos a verificación** antes de habilitarse. En MP-02 **solo se listan**, no se deciden.

---

### Bloque D — Usuarios y tarjetas de prueba

**D.1** En la app: sección **"Cuentas de prueba"** → **"Crear cuenta de prueba"** → seleccionar país **Argentina** (puede variar según UI).

**D.2** Crear **dos** cuentas de prueba:
- **Vendedor** (cuenta para configurar la app/credenciales de prueba).
- **Comprador** (cuenta para simular el pago).

**D.3** Anotar identificador/usuario/e-mail de cada cuenta de prueba (son cuentas generadas por MP, **no** son personas reales → no es PII sensible). Si al loguear con una cuenta de prueba pide código de 6 dígitos, está en "Cuentas de prueba".

**D.4** **Relevar las tarjetas de prueba** (sandbox) desde la documentación oficial de MP para Argentina. Anotar las que sirvan para simular aprobado/rechazado/pendiente. No son secretos.

> Nota: logueado **con una cuenta de prueba** no se ven ciertas secciones (Credenciales de prueba, Calidad de integración). Por eso la app se configura con la **cuenta real**, no con la de prueba.

---

## 2. Tabla de registro de secretos (placeholders, sin valores)

> Franco completa la columna **"Estado"** y **"Guardado en"**. **Nunca** se escribe el valor real acá.

| Placeholder | Qué es | Ambiente | Dónde se obtiene (panel) | Pública/Secreta | Guardado en (gestor) | Estado |
|---|---|---|---|---|---|---|
| `__PEGAR_MP_PUBLIC_KEY_TEST__` | Public Key de prueba | TEST | Detalles de la app → Credenciales de prueba | Pública | _(a completar)_ | _(pend./ok)_ |
| `__PEGAR_MP_ACCESS_TOKEN_TEST__` | Access Token de prueba | TEST | Detalles de la app → Credenciales de prueba | **SECRETA** | _(a completar)_ | _(pend./ok)_ |
| `__PEGAR_MP_WEBHOOK_SECRET_TEST__` | Webhook Secret | TEST | Webhooks → Configurar notificaciones (al **guardar**) | **SECRETA** | _(a completar)_ | **Pendiente** (depende de guardar config con URL HTTPS real) |
| `__PEGAR_MP_PUBLIC_KEY_PROD__` | Public Key de producción | PROD | Credenciales de producción | Pública | — | **N/A en MP-02** (no activar) |
| `__PEGAR_MP_ACCESS_TOKEN_PROD__` | Access Token de producción | PROD | Credenciales de producción | **SECRETA** | — | **N/A en MP-02** (no activar) |
| `__PEGAR_MP_WEBHOOK_SECRET_PROD__` | Webhook Secret de producción | PROD | Webhooks (modo productivo) | **SECRETA** | — | **N/A en MP-02** (no activar) |

Convención alineada al proyecto (L-C-08 / L-C-10): placeholders con prefijo `__PEGAR_`; assert futuro por prefijo; el **Webhook Secret es un secreto distinto del Access Token**; separación TEST/PROD por configuración, nunca por payload.

---

## 3. Checklist de aceptación por bloque

**Bloque A**
- [ ] Aplicación de Vita Delta creada/verificada.
- [ ] Ubicadas Public Key + Access Token **de prueba**.
- [ ] Credenciales de prueba guardadas en el gestor (placeholders A.4).
- [ ] Producción **no** activada.

**Bloque B**
- [ ] Ubicada la sección Webhooks → Configurar notificaciones.
- [ ] Identificado dónde se cargan las URLs (modo productivo / URL de prueba).
- [ ] Revisados los eventos; ubicado el evento **Pagos**.
- [ ] Ubicado el simulador de notificaciones.
- [ ] Entendido que el Webhook Secret se genera **al guardar** configuración.
- [ ] Configuración de webhook **NO guardada** (o guardada **solo** si había URL HTTPS real de prueba).
- [ ] Webhook Secret marcado como **Pendiente** (o registrado, si se guardó con URL real).

**Bloque C**
- [ ] Entendido que la exclusión de medios vive en la *preference* (no switch de panel).
- [ ] Relevada la lista real de tipos/medios de pago de AR.
- [ ] Identificado el tipo `ticket` (offline) como el que se excluirá.
- [ ] Listados los medios no-ticket candidatos (sujetos a verificación — D-MP-11).

**Bloque D**
- [ ] Cuenta de prueba **Vendedor** creada.
- [ ] Cuenta de prueba **Comprador** creada.
- [ ] Anotados identificadores de las cuentas de prueba.
- [ ] Relevadas las **tarjetas de prueba** de AR.

---

## 4. Acciones seguras ahora vs diferidas

| Acción | ¿Ahora? |
|---|---|
| Crear/verificar aplicación | ✅ Segura ahora |
| Ubicar y guardar credenciales **de prueba** | ✅ Segura ahora |
| Reconocer sección de webhooks, URLs, eventos, simulador | ✅ Segura ahora (reconocimiento) |
| Entender cómo/ cuándo se genera el Webhook Secret | ✅ Segura ahora |
| Relevar lista de medios de pago de AR | ✅ Segura ahora |
| Crear usuarios de prueba + relevar tarjetas | ✅ Segura ahora |
| **Guardar configuración de webhook** | ⏸️ **Diferida** salvo URL HTTPS real de prueba controlada |
| **Generar/registrar Webhook Secret** | ⏸️ **Diferida** (depende de guardar config) → MP-03/MP-04 |
| **Usar el simulador como prueba real** | ⏸️ **Diferida** (necesita URL receptora) |
| Activar credenciales de producción | ⛔ **No** en MP-02 |
| Excluir medios reales | ⛔ **No** (vive en la *preference*, con backend) |
| Conectar Supabase/n8n/OPS/portal | ⛔ **No** |
| Escribir código | ⛔ **No** |

---

## 5. Evidencia que Franco puede anotar (sin copiar secretos)

Para dejar trazabilidad de MP-02 **sin** exponer nada sensible:

- **Application ID** y **nombre** de la aplicación (no son secretos).
- "Credencial de prueba registrada: **sí/no**" + fecha (sin el valor).
- **Prefijo/tipo** del Access Token solo si ayuda a confirmar ambiente (ej. distinguir prueba vs producción), **nunca el token completo**.
- Qué secciones del panel se ubicaron (webhooks, simulador, cuentas de prueba): ✓/✗.
- Estado del webhook: "config **no guardada** (sin endpoint)" o "config de prueba guardada con URL real".
- **Usuarios de prueba** creados (identificador/usuario/e-mail de las cuentas de prueba — son de MP, no PII real).
- **Tarjetas de prueba** relevadas (de la doc oficial; no son secretos).
- Lista de **medios de pago de AR** relevada (insumo D-MP-11).

**Sobre capturas de pantalla:** evitar capturar valores de credenciales. Si se captura una pantalla con el Access Token o el Webhook Secret visible, **tapar/recortar** el valor antes de guardar o compartir.

---

## 6. Riesgos y defensas (específicos de MP-02)

| Riesgo | Defensa |
|---|---|
| Guardar una **URL de webhook inventada/placeholder** | Solo "reconocimiento seguro"; no guardar config sin **URL HTTPS real** de prueba controlada (Bloque B). |
| Confundir credenciales de **prueba** con **producción** | Trabajar solo en **Credenciales de prueba**; no activar producción. |
| Exponer **Access Token** o **Webhook Secret** (chat/repo/captura) | Placeholders + gestor de secretos + recorte de capturas. El Webhook Secret es secreto **distinto** del Access Token. |
| Creer que "el webhook no anda" en pruebas | El simulador solo valida si hay **URL receptora**; la recepción real es MP-03/MP-04. |
| Configurar la app con un **usuario de prueba** | Con cuenta de prueba no se ven ciertas secciones; usar la **cuenta real** de Vita Delta. |
| Asumir medios habilitados sin verificar | Bloque C es **relevamiento**; los no-ticket quedan **sujetos a verificación** (D-MP-11). |
| Tocar algo fuera de alcance | MP-02 es **solo panel de MP**; nada de Supabase/n8n/OPS/portal/código. |

---

## 7. Qué NO hacer todavía

- **No** activar credenciales productivas.
- **No** guardar configuración de webhook con una URL inventada o placeholder.
- **No** generar ni registrar el Webhook Secret si no se guardó config con URL HTTPS real (queda pendiente para MP-03/MP-04).
- **No** usar el simulador como "prueba real" sin endpoint receptor.
- **No** excluir medios de pago todavía (eso vive en la *preference*, con backend).
- **No** adoptar `binary_mode` (D-MP-10).
- **No** habilitar medios no-ticket sin verificación (D-MP-11): en MP-02 solo se relevan.
- **No** tocar Supabase, n8n, OPS, TEST, portal operativo, `portal-api` ni el schema canónico.
- **No** generar código.
- **No** pegar ni exponer tokens reales ni el Webhook Secret en chats, repo o capturas.

---

## 8. Salida de MP-02 → qué desbloquea

Al cerrar MP-02 quedan disponibles para las próximas etapas:

- Aplicación de Vita Delta operativa.
- **Credenciales de prueba** (Public Key + Access Token) guardadas como secretos.
- Reconocimiento completo de webhooks (URLs, evento Pagos, simulador, mecanismo del secret).
- Lista de medios de pago de AR relevada (insumo D-MP-11).
- Usuarios y tarjetas de prueba listos.
- **Pendiente explícito:** Webhook Secret (requiere endpoint/URL HTTPS real) → se resuelve en **MP-03/MP-04**, cuando exista receptor de prueba.

> **Próxima etapa (no ejecutar ahora):** MP-03/MP-04 — receptor/endpoint de prueba con URL HTTPS real, configuración de webhook, generación del Webhook Secret y, recién ahí, prueba de recepción con el simulador. Todo con OK explícito de Franco y sin tocar OPS/canónico hasta promoción.
