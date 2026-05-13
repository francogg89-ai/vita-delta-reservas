// ============================================================
// VITA DELTA — Aplicador de Validaciones de Datos v3
// Fase 4 del PLAN_ETAPA_5_IMPLEMENTACION_REAL
// Versión corregida con listas exactas del PLAN aprobado
//
// Función a ejecutar: aplicarValidaciones()
// Idempotente: sobreescribe validaciones anteriores sin tocar datos
// ============================================================

function aplicarValidaciones() {
  const ss  = SpreadsheetApp.getActiveSpreadsheet();
  const ui  = SpreadsheetApp.getUi();
  const log = [];

  // ── Helpers ────────────────────────────────────────────────

  function getSheet(name) {
    const sh = ss.getSheetByName(name);
    if (!sh) throw new Error(`Hoja no encontrada: "${name}"`);
    return sh;
  }

  function getColIndex(sh, colName) {
    const lastCol = sh.getLastColumn();
    if (lastCol === 0) throw new Error(`La hoja "${sh.getName()}" no tiene columnas.`);
    const headers = sh.getRange(1, 1, 1, lastCol).getValues()[0];
    const idx     = headers.indexOf(colName);
    if (idx === -1) throw new Error(
      `Columna "${colName}" no encontrada en hoja "${sh.getName()}".\n` +
      `Columnas actuales: [${headers.join(", ")}]`
    );
    return idx + 1; // 1-based
  }

  // Aplica validación de lista desplegable desde fila 2 hasta fila 1000.
  // setAllowInvalid(true) = advertencia, no bloqueo duro.
  // Sobreescribe cualquier validación previa en el mismo rango.
  function applyList(sh, colIndex, values, helpText) {
    const range = sh.getRange(2, colIndex, 999, 1);
    const rule  = SpreadsheetApp.newDataValidation()
      .requireValueInList(values, true)
      .setAllowInvalid(true)
      .setHelpText(helpText)
      .build();
    range.setDataValidation(rule);
    const colHeader = sh.getRange(1, colIndex).getValue();
    log.push(`  ✓  ${sh.getName()}.${colHeader}  →  [${values.join(" | ")}]`);
  }

  function applyBool(sh, colIndex) {
    applyList(sh, colIndex,
      ["TRUE", "FALSE"],
      "Ingresá TRUE o FALSE exactamente.");
  }

  // ── Validaciones ───────────────────────────────────────────

  try {
    let sh;

    // ── CABAÑAS ──────────────────────────────────────────────
    sh = getSheet("CABAÑAS");
    applyList(sh, getColIndex(sh, "tipo"),
      ["grande", "chica"],
      "Tipo de cabaña: grande o chica.");
    applyBool(sh, getColIndex(sh, "activa"));
    applyBool(sh, getColIndex(sh, "bloqueada"));

    // ── FERIADOS ─────────────────────────────────────────────
    sh = getSheet("FERIADOS");
    applyList(sh, getColIndex(sh, "tipo"),
      ["nacional", "ano_nuevo", "local"],
      "Tipo de feriado.");
    applyBool(sh, getColIndex(sh, "activo"));

    // ── TARIFAS ──────────────────────────────────────────────
    sh = getSheet("TARIFAS");
    applyList(sh, getColIndex(sh, "tipo_cabana"),
      ["grande", "chica"],
      "Tipo de cabaña al que aplica esta tarifa.");
    applyList(sh, getColIndex(sh, "concepto"),
      [
        "semana_1",
        "semana_2",
        "semana_3",
        "semana_4",
        "semana_5",
        "semana_marginal_6plus",
        "finde_1_noche",
        "finde_completo",
        "feriado_aislado",
        "feriado_adicional",
        "semana_completa",
        "semana_adicional",
        "marginal_fijo_finde_semana",
        "extra_persona_noche"
      ],
      "Concepto de tarifa según ARQUITECTURA_ETAPA_3.");
    applyBool(sh, getColIndex(sh, "activa"));

    // ── TEMPORADAS ───────────────────────────────────────────
    sh = getSheet("TEMPORADAS");
    applyBool(sh, getColIndex(sh, "activa"));

    // ── EVENTOS_ESPECIALES ───────────────────────────────────
    sh = getSheet("EVENTOS_ESPECIALES");
    applyList(sh, getColIndex(sh, "modo_precio"),
      ["paquetes_fijos", "precio_por_noche", "consultar"],
      "Modo de precio del evento especial.");
    applyBool(sh, getColIndex(sh, "activa"));

    // ── PAQUETES_EVENTO ──────────────────────────────────────
    // precio_total = 0 está permitido aquí (placeholder aprobado)
    sh = getSheet("PAQUETES_EVENTO");
    applyList(sh, getColIndex(sh, "tipo_cabana"),
      ["grande", "chica", "todas"],
      "Tipo de cabaña del paquete.");
    applyBool(sh, getColIndex(sh, "activo"));

    // ── CONSULTAS ────────────────────────────────────────────
    // canal: agrega "manual" (corregido)
    // estado_conversacion: estados finales del PLAN (corregido)
    sh = getSheet("CONSULTAS");
    applyList(sh, getColIndex(sh, "canal"),
      ["whatsapp", "instagram", "web", "manual"],
      "Canal por el que llegó la consulta.");
    applyList(sh, getColIndex(sh, "estado_conversacion"),
      [
        "inicio",
        "eligiendo_fechas",
        "cotizando",
        "esperando_pago",
        "pago_en_proceso",
        "cerrada",
        "derivada_a_humano"
      ],
      "Estado actual de la conversación.");

    // ── PRE_RESERVAS ─────────────────────────────────────────
    // estado: estados finales del PLAN (corregido)
    // canal_pago_esperado: nuevo (agregado)
    sh = getSheet("PRE_RESERVAS");
    applyList(sh, getColIndex(sh, "estado"),
      [
        "pendiente_pago",
        "vencida",
        "convertida",
        "cancelada_por_cliente",
        "cancelada_por_bloqueo",
        "conflicto_pendiente"
      ],
      "Estado de la pre-reserva.");
    applyList(sh, getColIndex(sh, "canal_pago_esperado"),
      ["mp_link", "transferencia_bancaria", "transferencia_mp", "cripto", "efectivo"],
      "Medio de pago esperado para confirmar esta pre-reserva.");
    applyList(sh, getColIndex(sh, "canal_origen"),
      ["whatsapp", "instagram", "web", "manual"],
      "Canal por el que se originó la pre-reserva.");

    // ── RESERVAS ─────────────────────────────────────────────
    // estado: estados finales del PLAN (corregido)
    // encargado_semana: nuevo (agregado)
    sh = getSheet("RESERVAS");
    applyList(sh, getColIndex(sh, "estado"),
      [
        "confirmada",
        "activa",
        "completada",
        "cancelada",
        "cancelada_con_cargo",
        "conflicto_pendiente"
      ],
      "Estado de la reserva.");
    applyList(sh, getColIndex(sh, "canal_origen"),
      ["whatsapp", "instagram", "web", "manual", "booking", "airbnb"],
      "Canal de origen de la reserva.");
    applyList(sh, getColIndex(sh, "encargado_semana"),
      ["Franco", "Rodrigo"],
      "Encargado operativo de esa semana.");
    applyBool(sh, getColIndex(sh, "mascotas"));
    applyBool(sh, getColIndex(sh, "ninos"));

    // ── PAGOS ────────────────────────────────────────────────
    // tipo: reemplaza "ajuste" por "extra" (corregido)
    // medio_pago: lista final del PLAN (corregido)
    // moneda: nuevo (agregado)
    sh = getSheet("PAGOS");
    applyList(sh, getColIndex(sh, "tipo"),
      ["sena", "saldo", "extra", "reembolso"],
      "Tipo de movimiento de pago.");
    applyList(sh, getColIndex(sh, "medio_pago"),
      [
        "mp_link",
        "transferencia_mp",
        "transferencia_bancaria",
        "tarjeta",
        "efectivo",
        "cripto"
      ],
      "Medio de pago utilizado.");
    applyList(sh, getColIndex(sh, "moneda"),
      ["ARS", "USD", "USDT", "BTC"],
      "Moneda del pago.");
    applyList(sh, getColIndex(sh, "estado"),
      ["pendiente", "en_revision", "confirmado", "rechazado", "reembolsado"],
      "Estado del pago.");
    applyBool(sh, getColIndex(sh, "es_automatico"));

    // ── DISPONIBILIDAD_CACHE ─────────────────────────────────
    sh = getSheet("DISPONIBILIDAD_CACHE");
    applyList(sh, getColIndex(sh, "estado"),
      [
        "disponible",
        "ocupada",
        "bloqueada",
        "checkout_disponible",
        "limite_escalonamiento"
      ],
      "Estado del día en la cache de disponibilidad.");
    applyList(sh, getColIndex(sh, "tipo_dia"),
      ["semana", "finde", "feriado", "ano_nuevo"],
      "Clasificación operativa del día.");
    applyList(sh, getColIndex(sh, "temporada"),
      ["alta", "media", "baja"],
      "Temporada vigente para ese día.");
    applyBool(sh, getColIndex(sh, "es_ultimo_dia_bloque"));
    applyBool(sh, getColIndex(sh, "tiene_checkout"));
    applyBool(sh, getColIndex(sh, "tiene_checkin"));

    // ── BLOQUEOS ─────────────────────────────────────────────
    // motivo: lista final del PLAN (corregido)
    sh = getSheet("BLOQUEOS");
    applyList(sh, getColIndex(sh, "motivo"),
      ["mantenimiento", "uso_propio", "tormenta", "overbooking", "otro"],
      "Motivo del bloqueo de la cabaña.");
    applyBool(sh, getColIndex(sh, "activo"));

    // ── OVERRIDES_OPERATIVOS ─────────────────────────────────
    // Lista v1.1 — sin claves viejas de escalonamiento de checkout
    sh = getSheet("OVERRIDES_OPERATIVOS");
    applyList(sh, getColIndex(sh, "tipo_override"),
      [
        "escalonamiento_activo",
        "escalonamiento_umbral_checkins_dia",
        "hora_checkin",
        "hora_checkout",
        "checkin_flexible",
        "checkout_flexible",
        "minimo_noches",
        "disponibilidad_bloqueada"
      ],
      "Tipo de override operativo. Ver CONFIGURACION_GENERAL para referencia de claves.");
    applyBool(sh, getColIndex(sh, "activo"));

    // ── PLANTILLAS_MENSAJES ──────────────────────────────────
    // canal: sin "email" (corregido)
    // destinatario: huesped, equipo, limpieza, franco (sin jennifer)
    sh = getSheet("PLANTILLAS_MENSAJES");
    applyList(sh, getColIndex(sh, "canal"),
      ["whatsapp", "instagram", "todos"],
      "Canal de envío de la plantilla.");
    applyList(sh, getColIndex(sh, "destinatario"),
      ["huesped", "equipo", "limpieza", "franco"],
      "Destinatario de la plantilla.");
    applyBool(sh, getColIndex(sh, "activa"));

    // ── CUENTAS_COBRO ────────────────────────────────────────
    // medio: lista final del PLAN (corregido)
    sh = getSheet("CUENTAS_COBRO");
    applyList(sh, getColIndex(sh, "medio"),
      ["transferencia_bancaria", "transferencia_mp", "cripto", "efectivo"],
      "Medio de cobro habilitado.");
    applyBool(sh, getColIndex(sh, "activa"));

    // ── GASTOS ───────────────────────────────────────────────
    sh = getSheet("GASTOS");
    applyList(sh, getColIndex(sh, "categoria"),
      ["limpieza", "mantenimiento", "servicios", "insumos", "marketing", "administrativo", "otro"],
      "Categoría del gasto.");
    applyBool(sh, getColIndex(sh, "reembolsable"));

    // ── DESCUENTOS ───────────────────────────────────────────
    // tipo: agrega "noche_gratis" (corregido)
    // aplica_a: nuevo (agregado)
    sh = getSheet("DESCUENTOS");
    applyList(sh, getColIndex(sh, "tipo"),
      ["porcentaje", "monto_fijo", "noche_gratis"],
      "Tipo de descuento.");
    applyList(sh, getColIndex(sh, "aplica_a"),
      ["todas", "grande", "chica"],
      "Tipo de cabaña a la que aplica el descuento.");
    applyList(sh, getColIndex(sh, "aplica_sobre"),
      ["alojamiento", "extras", "total"],
      "Base sobre la que se calcula el descuento.");
    applyBool(sh, getColIndex(sh, "combinable"));
    applyBool(sh, getColIndex(sh, "requiere_aprobacion"));
    applyBool(sh, getColIndex(sh, "activo"));

    // ── SOCIOS ───────────────────────────────────────────────
    sh = getSheet("SOCIOS");
    applyBool(sh, getColIndex(sh, "activo"));

    // ── LOG_CAMBIOS ──────────────────────────────────────────
    // nivel: nuevo (agregado)
    sh = getSheet("LOG_CAMBIOS");
    applyList(sh, getColIndex(sh, "nivel"),
      ["info", "warning", "error"],
      "Nivel de severidad del evento registrado.");

    // ── Resumen ───────────────────────────────────────────────
    const resumen = log.join("\n");
    Logger.log("✅ Validaciones aplicadas correctamente.\n\n" + resumen);
    ui.alert(
      "✅ Validaciones aplicadas — v3",
      "Se aplicaron todas las validaciones correctamente.\n\n" +
      "Revisá el log completo en:\nExtensiones → Apps Script → Ver → Registros\n\n" +
      "Cuando confirmes que DEV está OK, ejecutá el mismo script en TEST.",
      ui.ButtonSet.OK
    );

  } catch (e) {
    Logger.log("❌ ERROR: " + e.message);
    ui.alert(
      "❌ Error al aplicar validaciones",
      e.message + "\n\nCorregí el problema y volvé a ejecutar.",
      ui.ButtonSet.OK
    );
  }
}
