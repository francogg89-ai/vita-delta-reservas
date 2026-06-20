# BITÁCORA MP-02 — Sesión 2026-06-20

> Preparación operativa en Mercado Pago Developers. **Solo panel.** No conecta nada real.
> Antecedente: `FRENTE_MP_02_PREP_RUNSHEET.md` (runsheet aprobado).
> 🔒 Ningún valor real de credencial se escribe acá. Solo placeholders y evidencia no sensible.

---

## Datos de sesión
- Fecha/hora inicio:
- Cuenta usada: cuenta real Vita Delta (confirmar: sí/no)
- Bloques trabajados hoy:

---

## Evidencia no sensible
- Application ID:
- Nombre de la app:
- Producto integrado: (Checkout Pro / otro)

---

## Secretos (placeholders — SIN valores reales)

| Placeholder | Estado (pend./ok) | Guardado en (gestor) |
|---|---|---|
| `__PEGAR_MP_PUBLIC_KEY_TEST__` | | |
| `__PEGAR_MP_ACCESS_TOKEN_TEST__` | | |
| `__PEGAR_MP_WEBHOOK_SECRET_TEST__` | **PENDIENTE** (depende de URL HTTPS real) | — |
| `__PEGAR_MP_PUBLIC_KEY_PROD__` | N/A en MP-02 (no activar) | — |
| `__PEGAR_MP_ACCESS_TOKEN_PROD__` | N/A en MP-02 (no activar) | — |
| `__PEGAR_MP_WEBHOOK_SECRET_PROD__` | N/A en MP-02 (no activar) | — |

---

## Checklist por bloque

**Bloque A — Aplicación + credenciales de prueba**
- [ ] Aplicación de Vita Delta creada/verificada
- [ ] Ubicadas Public Key + Access Token **de prueba**
- [ ] Credenciales de prueba guardadas en el gestor (placeholders)
- [ ] Producción **NO** activada

**Bloque B — Webhooks + Webhook Secret**
- [ ] Ubicada la sección Webhooks → Configurar notificaciones
- [ ] Identificado dónde se cargan las URLs (modo productivo / URL de prueba)
- [ ] Revisados los eventos; ubicado el evento **Pagos**
- [ ] Ubicado el simulador de notificaciones
- [ ] Entendido que el Webhook Secret se genera **al guardar** configuración
- [ ] Configuración de webhook **NO guardada** (o guardada solo si había URL HTTPS real)
- [ ] Webhook Secret marcado como **Pendiente** (o registrado, si se guardó con URL real)

**Bloque C — Medios de pago (solo reconocimiento)**
- [ ] Entendido que la exclusión de medios vive en la *preference* (no switch de panel)
- [ ] Relevada la lista real de tipos/medios de pago de AR
- [ ] Identificado el tipo `ticket` (offline) como el que se excluirá
- [ ] Listados los medios no-ticket candidatos (sujetos a verificación — D-MP-11)

**Bloque D — Usuarios y tarjetas de prueba**
- [ ] Cuenta de prueba **Vendedor** creada
- [ ] Cuenta de prueba **Comprador** creada
- [ ] Anotados identificadores de las cuentas de prueba
- [ ] Relevadas las **tarjetas de prueba** de AR

---

## Resumen de estado
- **OK:**
- **Pendiente:**
- **Diferido:**

---

## Dudas / decisiones que surgieron
-

---

## Próximo paso
-
