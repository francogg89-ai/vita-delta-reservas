// ============================================================
// VITA DELTA — Aplicador de Protecciones por Entorno v1
// Fase 5 del PLAN_ETAPA_5_IMPLEMENTACION_REAL
//
// Función a ejecutar: aplicarProtecciones()
// Detecta automáticamente si el Sheet es DEV o TEST
// por el nombre del Spreadsheet.
// Idempotente: elimina protecciones anteriores del mismo
// tipo antes de aplicar las nuevas.
// ============================================================

function aplicarProtecciones() {
  const ss   = SpreadsheetApp.getActiveSpreadsheet();
  const ui   = SpreadsheetApp.getUi();
  const nombre = ss.getName();
  const log  = [];

  // ── Detectar entorno ───────────────────────────────────────
  let entorno;
  if (nombre.includes("DEV"))  entorno = "DEV";
  else if (nombre.includes("TEST")) entorno = "TEST";
  else {
    ui.alert(
      "❌ Entorno no reconocido",
      `El nombre del Spreadsheet es "${nombre}".\n` +
      `Debe contener "DEV" o "TEST" para que el script sepa qué protecciones aplicar.\n` +
      `No se aplicó ninguna protección.`,
      ui.ButtonSet.OK
    );
    return;
  }

  Logger.log(`▶ Entorno detectado: ${entorno}`);

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

  // Elimina protecciones existentes en un rango exacto para evitar duplicados.
  // Compara por descripción para identificarlas.
  function removeExistingProtections(sh, description) {
    const existing = sh.getProtections(SpreadsheetApp.ProtectionType.RANGE);
    existing.forEach(p => {
      if (p.getDescription() === description) p.remove();
    });
    const sheetProtections = sh.getProtections(SpreadsheetApp.ProtectionType.SHEET);
    sheetProtections.forEach(p => {
      if (p.getDescription() === description) p.remove();
    });
  }

  // Protección de RANGO con advertencia (allowInvalid = puede editar con aviso)
  function protectRangeWarning(sh, range, description) {
    removeExistingProtections(sh, description);
    const protection = range.protect();
    protection.setDescription(description);
    protection.setWarningOnly(true); // advertencia, no bloqueo
    log.push(`  ✓ [ADVERTENCIA]  ${sh.getName()}  →  ${description}`);
  }

  // Protección de HOJA COMPLETA con advertencia
  function protectSheetWarning(sh, description) {
    removeExistingProtections(sh, description);
    const protection = sh.protect();
    protection.setDescription(description);
    protection.setWarningOnly(true);
    log.push(`  ✓ [ADVERTENCIA HOJA]  ${sh.getName()}  →  ${description}`);
  }

  // Construye un rango de columna completa (fila 2 en adelante)
  // a partir del nombre de la columna.
  function colRange(sh, colName) {
    const colIdx  = getColIndex(sh, colName);
    const lastRow = Math.max(sh.getLastRow(), 2);
    return sh.getRange(2, colIdx, lastRow - 1, 1);
  }

  // Construye un rango multi-columna dado un array de nombres de columna.
  // Las columnas deben ser contiguas; si no lo son, se protegen individualmente.
  function multiColRanges(sh, colNames) {
    return colNames.map(name => colRange(sh, name));
  }

  // ── PROTECCIONES DEV ───────────────────────────────────────

  function aplicarDEV() {
    Logger.log("── DEV: aplicando protecciones mínimas ──");

    // Solo protección: CONFIGURACION_GENERAL.clave — advertencia
    // Evita cambiar accidentalmente el nombre de una clave.
    // La columna "valor" queda libre para experimentar.
    const shConfig = getSheet("CONFIGURACION_GENERAL");
    protectRangeWarning(
      shConfig,
      colRange(shConfig, "clave"),
      "DEV — clave de config: no renombrar sin actualizar el PLAN"
    );

    log.push("");
    log.push("DEV: resto de hojas sin protección (necesario para debugging de workflows).");
  }

  // ── PROTECCIONES TEST ──────────────────────────────────────

  function aplicarTEST() {
    Logger.log("── TEST: aplicando protecciones moderadas ──");

    let sh;

    // 1. DISPONIBILIDAD_CACHE — hoja completa con advertencia
    //    La escribe n8n; edición manual debe ser consciente.
    sh = getSheet("DISPONIBILIDAD_CACHE");
    protectSheetWarning(sh,
      "TEST — escribe n8n: no editar manualmente salvo corrección de prueba");

    // 2. LOG_CAMBIOS — hoja completa con advertencia
    //    No se edita manualmente; limpiar entre pruebas con conciencia.
    sh = getSheet("LOG_CAMBIOS");
    protectSheetWarning(sh,
      "TEST — log del sistema: no editar manualmente");

    // 3. CONFIGURACION_GENERAL.clave — rango con advertencia
    //    Las claves son fijas según el PLAN; los valores son editables.
    sh = getSheet("CONFIGURACION_GENERAL");
    protectRangeWarning(sh,
      colRange(sh, "clave"),
      "TEST — clave de config: no renombrar sin actualizar el PLAN");

    // 4. RESERVAS — columnas de sistema con advertencia
    //    Las escribe n8n; no se modifican manualmente.
    //    Excepción aprobada por arquitectura: estado puede cambiarse
    //    manualmente (confirmada → activa, activa → completada).
    sh = getSheet("RESERVAS");
    const reservasCols = ["id_reserva", "id_prereserva", "created_at", "updated_at", "source_event"];
    reservasCols.forEach(col => {
      protectRangeWarning(sh, colRange(sh, col),
        `TEST — RESERVAS.${col}: escribe n8n`);
    });

    // 5. PAGOS — columnas de sistema con advertencia
    sh = getSheet("PAGOS");
    const pagosCols = ["id_pago", "created_at", "updated_at", "es_automatico", "referencia_externa", "tx_hash"];
    pagosCols.forEach(col => {
      protectRangeWarning(sh, colRange(sh, col),
        `TEST — PAGOS.${col}: escribe n8n`);
    });

    // 6. DESCUENTOS.usos_actuales — rango con advertencia
    //    Solo escribe n8n cuando el motor de descuentos esté activo.
    sh = getSheet("DESCUENTOS");
    protectRangeWarning(sh,
      colRange(sh, "usos_actuales"),
      "TEST — DESCUENTOS.usos_actuales: escribe n8n, no modificar manualmente");

    // 7. Vistas operativas — hoja completa con advertencia
    //    Son generadas/derivadas por n8n; no se editan manualmente.
    ["VISTA_CALENDARIO", "VISTA_PRERESERVAS_ACTIVAS", "VISTA_OCUPACION"].forEach(nombre => {
      sh = getSheet(nombre);
      protectSheetWarning(sh,
        `TEST — vista derivada: generada por n8n, no editar manualmente`);
    });
  }

  // ── Ejecutar según entorno ─────────────────────────────────

  try {
    if (entorno === "DEV")  aplicarDEV();
    if (entorno === "TEST") aplicarTEST();

    // ── Resumen ─────────────────────────────────────────────
    const resumen = [
      `✅ Protecciones aplicadas — ${entorno}`,
      "",
      "Detalle:",
      ...log,
      "",
      "Recordatorios:",
      "• Todas las protecciones son tipo ADVERTENCIA (no bloqueo duro).",
      "• Vos (propietario) siempre podés editar aunque aparezca el aviso.",
      "• Cuando n8n se conecte con su cuenta de servicio, agregarla como",
      "  excepción en las protecciones de TEST desde:",
      "  Datos → Proteger hoja y rangos → [protección] → Editar → Excepciones.",
      "• Las protecciones de PROD se configuran en la jornada de producción.",
    ].join("\n");

    Logger.log(resumen);
    ui.alert(
      `✅ Protecciones aplicadas — ${entorno}`,
      resumen,
      ui.ButtonSet.OK
    );

  } catch (e) {
    Logger.log("❌ ERROR: " + e.message);
    ui.alert(
      "❌ Error al aplicar protecciones",
      e.message + "\n\nCorregí el problema y volvé a ejecutar.",
      ui.ButtonSet.OK
    );
  }
}
