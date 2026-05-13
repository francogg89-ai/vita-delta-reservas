// ============================================================
// VITA DELTA — Auditoría Fase 6 v1
// Verificación final antes de n8n
//
// SOLO LECTURA: no modifica datos, validaciones ni protecciones.
// Función a ejecutar: auditarSheet()
// Detecta el entorno automáticamente (DEV o TEST).
// ============================================================

function auditarSheet() {
  const ss     = SpreadsheetApp.getActiveSpreadsheet();
  const ui     = SpreadsheetApp.getUi();
  const nombre = ss.getName();
  const hoy    = new Date();
  const currentId = ss.getId();

  let entorno;
  if      (nombre.includes("DEV"))  entorno = "DEV";
  else if (nombre.includes("TEST")) entorno = "TEST";
  else {
    ui.alert("❌ Entorno no reconocido",
      `El nombre del Spreadsheet es "${nombre}".\nDebe contener "DEV" o "TEST".`,
      ui.ButtonSet.OK);
    return;
  }

  const resultados = [];
  let   errores    = 0;
  let   warnings   = 0;

  // ── Helpers ────────────────────────────────────────────────

  function ok(msg)   { resultados.push(`  ✅ ${msg}`); }
  function err(msg)  { resultados.push(`  ❌ ${msg}`); errores++; }
  function warn(msg) { resultados.push(`  ⚠️  ${msg}`); warnings++; }
  function sep(msg)  { resultados.push(`\n── ${msg} ──`); }

  function getSheet(name) { return ss.getSheetByName(name); }

  function getHeaders(sh) {
    if (!sh || sh.getLastColumn() === 0) return [];
    return sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0]
      .map(h => String(h).trim());
  }

  function getColIdx(headers, col) { return headers.indexOf(col); } // 0-based, -1 si no existe

  function getDataRows(sh) {
    if (!sh || sh.getLastRow() < 2) return [];
    return sh.getRange(2, 1, sh.getLastRow() - 1, sh.getLastColumn()).getValues();
  }

  function isFrozen(sh) {
    return sh.getFrozenRows() >= 1;
  }

  function hasValidation(sh, colIdx) {
    // Revisa la celda de fila 2 en esa columna (1-based)
    if (sh.getLastRow() < 2) {
      // Hoja vacía: revisa igual en fila 2
      const rule = sh.getRange(2, colIdx + 1).getDataValidation();
      return rule !== null;
    }
    const rule = sh.getRange(2, colIdx + 1).getDataValidation();
    return rule !== null;
  }

  function hasProtection(sh) {
    const sheetProts = sh.getProtections(SpreadsheetApp.ProtectionType.SHEET);
    const rangeProts = sh.getProtections(SpreadsheetApp.ProtectionType.RANGE);
    return sheetProts.length > 0 || rangeProts.length > 0;
  }

  function colProtected(sh, colIdx) {
    const rangeProts = sh.getProtections(SpreadsheetApp.ProtectionType.RANGE);
    for (const p of rangeProts) {
      const r = p.getRange();
      if (r.getColumn() <= colIdx + 1 && r.getLastColumn() >= colIdx + 1) return true;
    }
    return false;
  }

  // Verifica que una temporada cubra la fecha hoy
  function temporadaCubreHoy(rows, headers) {
    const idxDesde = getColIdx(headers, "fecha_desde");
    const idxHasta = getColIdx(headers, "fecha_hasta");
    const idxActiva = getColIdx(headers, "activa");
    if (idxDesde < 0 || idxHasta < 0) return false;
    for (const row of rows) {
      const activa = idxActiva >= 0 ? row[idxActiva] : true;
      if (!activa && activa !== "" && String(activa).toUpperCase() !== "TRUE") continue;
      const desde = new Date(row[idxDesde]);
      const hasta = new Date(row[idxHasta]);
      if (hoy >= desde && hoy <= hasta) return true;
    }
    return false;
  }

  // ── NOMBRES ESPERADOS de las 24 hojas ─────────────────────

  const HOJAS_ESPERADAS = [
    "CABAÑAS", "HUÉSPEDES", "FERIADOS", "TARIFAS", "TEMPORADAS",
    "EVENTOS_ESPECIALES", "PAQUETES_EVENTO", "CONSULTAS", "PRE_RESERVAS",
    "RESERVAS", "PAGOS", "DISPONIBILIDAD_CACHE", "BLOQUEOS",
    "OVERRIDES_OPERATIVOS", "CONFIGURACION_GENERAL", "PLANTILLAS_MENSAJES",
    "CUENTAS_COBRO", "GASTOS", "DESCUENTOS", "SOCIOS", "LOG_CAMBIOS",
    "VISTA_CALENDARIO", "VISTA_PRERESERVAS_ACTIVAS", "VISTA_OCUPACION"
  ];

  // ── ENCABEZADOS ESPERADOS por hoja ────────────────────────

  const HEADERS_ESPERADOS = {
    "CABAÑAS":            ["id_cabana","nombre","tipo","capacidad_base","capacidad_max","activa","bloqueada","motivo_bloqueo","orden_limpieza","descripcion","fotos_urls","created_at"],
    "HUÉSPEDES":          ["id_huesped","nombre","apellido","dni","telefono","email","canal_preferido","primera_reserva_fecha","total_reservas","notas_internas","created_at","updated_at"],
    "FERIADOS":           ["fecha","nombre","tipo","activo"],
    "TARIFAS":            ["id_tarifa","tipo_cabana","concepto","precio","descripcion","activa","valida_desde","valida_hasta","created_at","updated_at"],
    "TEMPORADAS":         ["id_temporada","nombre","fecha_desde","fecha_hasta","multiplicador","activa","created_at"],
    "EVENTOS_ESPECIALES": ["id_evento","nombre","fecha_desde","fecha_hasta","modo_precio","reglas_especiales","activa","source_event","created_at"],
    "PAQUETES_EVENTO":    ["id_paquete","id_evento","tipo_cabana","nombre_paquete","fecha_in","fecha_out","precio_total","personas_max","incluye","notas","activo","created_at"],
    "CONSULTAS":          ["id_consulta","canal","id_contacto_externo","id_huesped","estado_conversacion","id_cabana_tentativa","fecha_in_tentativa","fecha_out_tentativa","personas_tentativa","ultimo_mensaje_at","contexto_json","tokens_json","motivo_derivacion","source_event","created_at","updated_at"],
    "PRE_RESERVAS":       ["id_prereserva","id_consulta","id_cabana","id_huesped","fecha_in","fecha_out","hora_checkin","hora_checkout","personas","monto_total","monto_sena","estado","expira_en","canal_pago_esperado","canal_origen","intentos_pago","referencia_mp","notas","source_event","created_at","updated_at"],
    "RESERVAS":           ["id_reserva","id_prereserva","id_cabana","id_huesped","fecha_checkin","fecha_checkout","hora_checkin","hora_checkout","personas","estado","canal_origen","id_tarifa_aplicada","monto_total","monto_sena","monto_saldo","mascotas","detalle_mascotas","ninos","encargado_semana","notas","created_by","source_event","created_at","updated_at"],
    "PAGOS":              ["id_pago","id_prereserva","id_reserva","tipo","medio_pago","proveedor","cuenta_destino","monto_esperado","monto_recibido","moneda","estado","es_automatico","comprobante_url","referencia_externa","tx_hash","validado_por","validado_en","motivo_rechazo","notas","source_event","created_at","updated_at"],
    "DISPONIBILIDAD_CACHE": ["id_cabana","fecha","estado","hora_checkin_minima","hora_checkin_maxima","hora_checkout_maxima","hora_checkout_minima","tipo_dia","temporada","es_ultimo_dia_bloque","minimo_noches","id_reserva_activa","id_prereserva_activa","tiene_checkout","id_reserva_checkout","tiene_checkin","id_reserva_checkin","recalculado_en"],
    "BLOQUEOS":           ["id_bloqueo","id_cabana","fecha_desde","fecha_hasta","motivo","descripcion","creado_por","activo","source_event","created_at"],
    "OVERRIDES_OPERATIVOS": ["id_override","fecha_desde","fecha_hasta","id_cabana","tipo_override","valor","motivo","creado_por","activo","source_event","created_at"],
    "CONFIGURACION_GENERAL": ["clave","valor","descripcion"],
    "PLANTILLAS_MENSAJES": ["id_plantilla","nombre","canal","evento_disparador","texto","keywords","score_minimo","destinatario","activa","created_at"],
    "CUENTAS_COBRO":      ["id_cuenta","nombre","medio","proveedor","datos_cobro","titular","instrucciones","activa","created_at"],
    "GASTOS":             ["id_gasto","fecha","categoria","descripcion","monto","id_cabana","pagado_por","reembolsable","comprobante_url","created_at"],
    "DESCUENTOS":         ["id_descuento","nombre","tipo","valor","aplica_a","aplica_sobre","fecha_desde","fecha_hasta","codigo","usos_maximos","usos_actuales","minimo_noches","monto_minimo","prioridad","combinable","requiere_aprobacion","activo","source_event","created_at","updated_at"],
    "SOCIOS":             ["id_socio","nombre","porcentaje_utilidades","whatsapp","activo"],
    "LOG_CAMBIOS":        ["id_log","fecha_hora","tabla_afectada","id_registro","campo_modificado","valor_anterior","valor_nuevo","modificado_por","source_event","nivel","detalle"],
    "VISTA_CALENDARIO":   ["id_cabana","nombre_cabana","fecha","estado_display","id_reserva","nombre_huesped","hora_checkin","hora_checkout","encargado_semana"],
    "VISTA_PRERESERVAS_ACTIVAS": ["id_prereserva","nombre_cabana","nombre_huesped","telefono","fecha_in","fecha_out","monto_sena","canal_pago_esperado","expira_en"],
    "VISTA_OCUPACION":    [],
  };

  // ══════════════════════════════════════════════════════════
  // BLOQUE 1 — ESTRUCTURA
  // ══════════════════════════════════════════════════════════
  sep("BLOQUE 1 — ESTRUCTURA");

  // 1.1 Cantidad de hojas
  const hojas = ss.getSheets().map(s => s.getName());
  if (hojas.length === 24) {
    ok(`Total de hojas: 24`);
  } else {
    err(`Total de hojas: ${hojas.length} (esperado: 24)`);
  }

  // 1.2 Hojas esperadas presentes
  let faltanHojas = [];
  for (const nombre of HOJAS_ESPERADAS) {
    if (!getSheet(nombre)) faltanHojas.push(nombre);
  }
  if (faltanHojas.length === 0) {
    ok("Todas las 24 hojas esperadas existen con nombres correctos");
  } else {
    err(`Hojas faltantes o con nombre incorrecto: [${faltanHojas.join(", ")}]`);
  }

  // 1.3 Encabezados y congelamiento por hoja
  for (const [shName, expectedHeaders] of Object.entries(HEADERS_ESPERADOS)) {
    const sh = getSheet(shName);
    if (!sh) continue; // ya reportado arriba

    // VISTA_OCUPACION: debe estar completamente vacía, sin encabezados ni filas congeladas
    if (expectedHeaders.length === 0) continue;

    // Congelamiento fila 1 (excluye VISTA_OCUPACION, ya saltada arriba)
    if (!isFrozen(sh)) {
      warn(`${shName}: fila 1 no está inmovilizada`);
    }

    const actual = getHeaders(sh);
    const faltantes = expectedHeaders.filter(h => !actual.includes(h));
    const extra     = actual.filter(h => h !== "" && !expectedHeaders.includes(h));

    if (faltantes.length === 0 && extra.length === 0) {
      ok(`${shName}: encabezados correctos (${expectedHeaders.length} columnas)`);
    } else {
      if (faltantes.length > 0) err(`${shName}: columnas faltantes → [${faltantes.join(", ")}]`);
      if (extra.length > 0)     warn(`${shName}: columnas extra no esperadas → [${extra.join(", ")}]`);
    }
  }

  // ══════════════════════════════════════════════════════════
  // BLOQUE 2 — DATOS MÍNIMOS
  // ══════════════════════════════════════════════════════════
  sep("BLOQUE 2 — DATOS MÍNIMOS");

  // 2.1 CABAÑAS — 5 filas, activa=TRUE, bloqueada=FALSE
  {
    const sh = getSheet("CABAÑAS");
    if (sh) {
      const headers = getHeaders(sh);
      const rows    = getDataRows(sh);
      const iActiva   = getColIdx(headers, "activa");
      const iBloqueada = getColIdx(headers, "bloqueada");
      const totalFilas = rows.filter(r => r[0] !== "").length;

      if (totalFilas === 5) ok("CABAÑAS: 5 filas cargadas");
      else err(`CABAÑAS: ${totalFilas} filas (esperado: 5)`);

      const noActivas = rows.filter(r => r[0] !== "" && String(r[iActiva]).toUpperCase() !== "TRUE").length;
      if (noActivas === 0) ok("CABAÑAS: todas con activa = TRUE");
      else err(`CABAÑAS: ${noActivas} cabañas con activa ≠ TRUE`);

      const bloqueadas = rows.filter(r => r[0] !== "" && String(r[iBloqueada]).toUpperCase() === "TRUE").length;
      if (bloqueadas === 0) ok("CABAÑAS: todas con bloqueada = FALSE");
      else warn(`CABAÑAS: ${bloqueadas} cabañas con bloqueada = TRUE (¿intencional?)`);
    }
  }

  // 2.2 TARIFAS — al menos 10 filas, precio > 0, activa = TRUE
  {
    const sh = getSheet("TARIFAS");
    if (sh) {
      const headers = getHeaders(sh);
      const rows    = getDataRows(sh).filter(r => r[0] !== "");
      const iPrecio  = getColIdx(headers, "precio");
      const iActiva  = getColIdx(headers, "activa");

      if (rows.length >= 10) ok(`TARIFAS: ${rows.length} filas cargadas`);
      else err(`TARIFAS: ${rows.length} filas (esperado: al menos 10)`);

      const preciosCero = rows.filter(r => Number(r[iPrecio]) === 0).length;
      if (preciosCero === 0) ok("TARIFAS: ningún precio es 0");
      else err(`TARIFAS: ${preciosCero} filas con precio = 0 (no permitido en TARIFAS)`);

      const noActivas = rows.filter(r => String(r[iActiva]).toUpperCase() !== "TRUE").length;
      if (noActivas === 0) ok("TARIFAS: todas con activa = TRUE");
      else warn(`TARIFAS: ${noActivas} tarifas con activa ≠ TRUE`);
    }
  }

  // 2.3 TEMPORADAS — cubre fecha de hoy
  {
    const sh = getSheet("TEMPORADAS");
    if (sh) {
      const headers = getHeaders(sh);
      const rows    = getDataRows(sh).filter(r => r[0] !== "");
      if (rows.length >= 2) ok(`TEMPORADAS: ${rows.length} filas cargadas`);
      else warn(`TEMPORADAS: solo ${rows.length} fila(s) — verificar cobertura`);

      if (temporadaCubreHoy(rows, headers)) ok("TEMPORADAS: la fecha de hoy está cubierta");
      else err("TEMPORADAS: la fecha de hoy NO está cubierta por ninguna temporada activa");
    }
  }

  // 2.4 EVENTOS_ESPECIALES — 1 fila activa
  {
    const sh = getSheet("EVENTOS_ESPECIALES");
    if (sh) {
      const rows = getDataRows(sh).filter(r => r[0] !== "");
      if (rows.length >= 1) ok(`EVENTOS_ESPECIALES: ${rows.length} fila(s) cargada(s)`);
      else err("EVENTOS_ESPECIALES: sin filas — falta cargar Año Nuevo 2026/2027");
    }
  }

  // 2.5 PAQUETES_EVENTO — al menos 4 filas, precio_total = 0, activo = TRUE
  {
    const sh = getSheet("PAQUETES_EVENTO");
    if (sh) {
      const headers  = getHeaders(sh);
      const rows     = getDataRows(sh).filter(r => r[0] !== "");
      const iPrecio  = getColIdx(headers, "precio_total");
      const iActivo  = getColIdx(headers, "activo");

      if (rows.length >= 4) ok(`PAQUETES_EVENTO: ${rows.length} filas cargadas`);
      else err(`PAQUETES_EVENTO: ${rows.length} filas (esperado: al menos 4)`);

      const noPlaceholder = rows.filter(r => Number(r[iPrecio]) !== 0).length;
      if (noPlaceholder === 0) ok("PAQUETES_EVENTO: todos con precio_total = 0 (placeholder aprobado)");
      else warn(`PAQUETES_EVENTO: ${noPlaceholder} paquetes con precio_total > 0 — verificar si son precios reales cargados`);

      const noActivos = rows.filter(r => String(r[iActivo]).toUpperCase() !== "TRUE").length;
      if (noActivos === 0) ok("PAQUETES_EVENTO: todos con activo = TRUE");
      else err(`PAQUETES_EVENTO: ${noActivos} paquetes con activo ≠ TRUE`);
    }
  }

  // 2.6 CONFIGURACION_GENERAL — mínimo 40 claves, sheets_url, whatsapp
  {
    const sh = getSheet("CONFIGURACION_GENERAL");
    if (sh) {
      const headers = getHeaders(sh);
      const rows    = getDataRows(sh).filter(r => r[0] !== "");
      const iClave  = getColIdx(headers, "clave");
      const iValor  = getColIdx(headers, "valor");

      if (rows.length >= 40) ok(`CONFIGURACION_GENERAL: ${rows.length} claves cargadas`);
      else warn(`CONFIGURACION_GENERAL: ${rows.length} claves (esperado: al menos 40)`);

      const getValor = (clave) => {
        const row = rows.find(r => String(r[iClave]).trim() === clave);
        return row ? String(row[iValor]).trim() : null;
      };

      // sheets_url
      const sheetsUrl = getValor("sheets_url");
      if (!sheetsUrl)                         err("CONFIGURACION_GENERAL: clave 'sheets_url' no encontrada");
      else if (sheetsUrl.startsWith("COMPLETAR")) warn("CONFIGURACION_GENERAL: sheets_url todavía dice COMPLETAR — actualizar con URL real");
      else if (!sheetsUrl.includes(currentId)) err("CONFIGURACION_GENERAL: sheets_url no apunta a este Spreadsheet (ID actual: " + currentId + ")");  
      else if (sheetsUrl.includes("docs.google.com/spreadsheets")) ok("CONFIGURACION_GENERAL: sheets_url apunta correctamente a este Spreadsheet ✓");
      else warn(`CONFIGURACION_GENERAL: sheets_url tiene valor inusual → ${sheetsUrl}`);

      // whatsapp
      ["whatsapp_franco","whatsapp_rodrigo","whatsapp_jennifer"].forEach(clave => {
        const val = getValor(clave);
        if (!val)                          err(`CONFIGURACION_GENERAL: clave '${clave}' no encontrada`);
        else if (val.includes("XXXXXXXXXX")) warn(`CONFIGURACION_GENERAL: ${clave} = ${val} — completar con número real`);
        else if (val.startsWith("+549"))   ok(`CONFIGURACION_GENERAL: ${clave} con formato internacional ✓`);
        else                               warn(`CONFIGURACION_GENERAL: ${clave} = ${val} — verificar formato (+549...)`);
      });

      // encargado_ciclo_inicio_fecha
      const cicloFecha = getValor("encargado_ciclo_inicio_fecha");
      if (!cicloFecha) err("CONFIGURACION_GENERAL: clave 'encargado_ciclo_inicio_fecha' no encontrada");
      else ok(`CONFIGURACION_GENERAL: encargado_ciclo_inicio_fecha = ${cicloFecha}`);

      // prereserva_expiracion_minutos — alertar si DEV tiene 60 o TEST tiene 2
      const expMin = getValor("prereserva_expiracion_minutos");
      if (expMin) {
        if (entorno === "DEV" && expMin === "60")  warn("CONFIGURACION_GENERAL: prereserva_expiracion_minutos = 60 en DEV — recomendado: 2 para pruebas rápidas");
        if (entorno === "TEST" && expMin === "2")   warn("CONFIGURACION_GENERAL: prereserva_expiracion_minutos = 2 en TEST — recomendado: 60 para pruebas realistas");
        if (entorno === "DEV" && expMin === "2")    ok("CONFIGURACION_GENERAL: prereserva_expiracion_minutos = 2 en DEV ✓");
        if (entorno === "TEST" && expMin === "60")  ok("CONFIGURACION_GENERAL: prereserva_expiracion_minutos = 60 en TEST ✓");
      }
    }
  }

  // 2.7 CUENTAS_COBRO — al menos 1 activa
  {
    const sh = getSheet("CUENTAS_COBRO");
    if (sh) {
      const headers = getHeaders(sh);
      const rows    = getDataRows(sh).filter(r => r[0] !== "");
      const iActiva = getColIdx(headers, "activa");
      const activas = rows.filter(r => String(r[iActiva]).toUpperCase() === "TRUE").length;
      if (activas >= 1) ok(`CUENTAS_COBRO: ${activas} cuenta(s) activa(s)`);
      else err("CUENTAS_COBRO: ninguna cuenta activa");

      // Verificar que no tenga COMPLETAR en datos_cobro
      const iDatos = getColIdx(headers, "datos_cobro");
      const sinCompletar = rows.filter(r => String(r[iDatos]).startsWith("COMPLETAR")).length;
      if (sinCompletar > 0) warn(`CUENTAS_COBRO: ${sinCompletar} fila(s) con datos_cobro = COMPLETAR — actualizar antes de conectar MercadoPago`);
    }
  }

  // 2.8 PLANTILLAS_MENSAJES — al menos 2 activas
  {
    const sh = getSheet("PLANTILLAS_MENSAJES");
    if (sh) {
      const headers  = getHeaders(sh);
      const rows     = getDataRows(sh).filter(r => r[0] !== "");
      const iActiva  = getColIdx(headers, "activa");
      const iNombre  = getColIdx(headers, "nombre");
      const activas  = rows.filter(r => String(r[iActiva]).toUpperCase() === "TRUE").length;
      if (activas >= 2) ok(`PLANTILLAS_MENSAJES: ${activas} plantilla(s) activa(s)`);
      else err(`PLANTILLAS_MENSAJES: ${activas} plantilla(s) activa(s) (esperado: al menos 2)`);

      const nombres = rows.map(r => String(r[iNombre]));
      if (nombres.includes("prereserva_creada"))  ok("PLANTILLAS_MENSAJES: 'prereserva_creada' existe");
      else err("PLANTILLAS_MENSAJES: falta plantilla 'prereserva_creada'");
      if (nombres.includes("nueva_reserva_equipo")) ok("PLANTILLAS_MENSAJES: 'nueva_reserva_equipo' existe");
      else err("PLANTILLAS_MENSAJES: falta plantilla 'nueva_reserva_equipo'");
    }
  }

  // 2.9 SOCIOS — 3 filas, porcentajes suman 100
  {
    const sh = getSheet("SOCIOS");
    if (sh) {
      const headers = getHeaders(sh);
      const rows    = getDataRows(sh).filter(r => r[0] !== "");
      const iPct    = getColIdx(headers, "porcentaje_utilidades");
      if (rows.length === 3) ok("SOCIOS: 3 filas cargadas");
      else err(`SOCIOS: ${rows.length} filas (esperado: 3)`);

      const suma = rows.reduce((acc, r) => acc + Number(r[iPct] || 0), 0);
      if (suma === 100) ok("SOCIOS: porcentajes suman 100");
      else err(`SOCIOS: porcentajes suman ${suma} (esperado: 100)`);
    }
  }

  // ══════════════════════════════════════════════════════════
  // BLOQUE 3 — HOJAS QUE DEBEN ESTAR VACÍAS
  // ══════════════════════════════════════════════════════════
  sep("BLOQUE 3 — HOJAS QUE DEBEN ESTAR VACÍAS");

  ["DISPONIBILIDAD_CACHE","LOG_CAMBIOS","CONSULTAS","PRE_RESERVAS","RESERVAS","PAGOS"].forEach(shName => {
    const sh = getSheet(shName);
    if (!sh) return;
    const lastRow = sh.getLastRow();
    if (lastRow <= 1) ok(`${shName}: vacía ✓`);
    else warn(`${shName}: tiene ${lastRow - 1} fila(s) de datos — ¿datos de prueba previos?`);
  });

  // VISTA_OCUPACION — completamente vacía (sin encabezados tampoco)
  {
    const sh = getSheet("VISTA_OCUPACION");
    if (sh) {
      const lastRow = sh.getLastRow();
      const lastCol = sh.getLastColumn();
      if (lastRow === 0 || (lastRow === 1 && lastCol === 0)) {
        ok("VISTA_OCUPACION: completamente vacía ✓");
      } else {
        const cell = sh.getRange(1, 1).getValue();
        if (lastRow === 1 && String(cell).trim() !== "") {
          warn(`VISTA_OCUPACION: tiene contenido en A1 → "${cell}" — debe estar completamente vacía`);
        } else if (lastRow > 1) {
          warn(`VISTA_OCUPACION: tiene ${lastRow} fila(s) — debe estar completamente vacía`);
        } else {
          ok("VISTA_OCUPACION: vacía ✓");
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════
  // BLOQUE 4 — VALIDACIONES
  // ══════════════════════════════════════════════════════════
  sep("BLOQUE 4 — VALIDACIONES (muestra de columnas críticas)");

  const validacionesAChequear = [
    ["CABAÑAS",             "tipo"],
    ["CABAÑAS",             "activa"],
    ["CABAÑAS",             "bloqueada"],
    ["TARIFAS",             "tipo_cabana"],
    ["TARIFAS",             "concepto"],
    ["TARIFAS",             "activa"],
    ["FERIADOS",            "tipo"],
    ["EVENTOS_ESPECIALES",  "modo_precio"],
    ["PAQUETES_EVENTO",     "tipo_cabana"],
    ["CONSULTAS",           "canal"],
    ["CONSULTAS",           "estado_conversacion"],
    ["PRE_RESERVAS",        "estado"],
    ["PRE_RESERVAS",        "canal_pago_esperado"],
    ["RESERVAS",            "estado"],
    ["RESERVAS",            "encargado_semana"],
    ["PAGOS",               "tipo"],
    ["PAGOS",               "medio_pago"],
    ["PAGOS",               "moneda"],
    ["PAGOS",               "estado"],
    ["DISPONIBILIDAD_CACHE","estado"],
    ["DISPONIBILIDAD_CACHE","tipo_dia"],
    ["DISPONIBILIDAD_CACHE","temporada"],
    ["DISPONIBILIDAD_CACHE","tiene_checkout"],
    ["DISPONIBILIDAD_CACHE","tiene_checkin"],
    ["BLOQUEOS",            "motivo"],
    ["OVERRIDES_OPERATIVOS","tipo_override"],
    ["PLANTILLAS_MENSAJES", "canal"],
    ["PLANTILLAS_MENSAJES", "destinatario"],
    ["CUENTAS_COBRO",       "medio"],
    ["DESCUENTOS",          "tipo"],
    ["DESCUENTOS",          "aplica_a"],
    ["DESCUENTOS",          "aplica_sobre"],
    ["LOG_CAMBIOS",         "nivel"],
    ["SOCIOS",              "activo"],
  ];

  for (const [shName, colName] of validacionesAChequear) {
    const sh = getSheet(shName);
    if (!sh) continue;
    const headers = getHeaders(sh);
    const colIdx  = getColIdx(headers, colName);
    if (colIdx < 0) {
      err(`Validación: columna "${colName}" no encontrada en ${shName}`);
      continue;
    }
    if (hasValidation(sh, colIdx)) ok(`Validación presente: ${shName}.${colName}`);
    else err(`Validación FALTANTE: ${shName}.${colName}`);
  }

  // ══════════════════════════════════════════════════════════
  // BLOQUE 5 — PROTECCIONES (solo TEST)
  // ══════════════════════════════════════════════════════════
  if (entorno === "TEST") {
    sep("BLOQUE 5 — PROTECCIONES (solo TEST)");

    // Hojas con protección de hoja completa
    ["DISPONIBILIDAD_CACHE", "LOG_CAMBIOS",
     "VISTA_CALENDARIO", "VISTA_PRERESERVAS_ACTIVAS", "VISTA_OCUPACION"].forEach(shName => {
      const sh = getSheet(shName);
      if (!sh) return;
      const prots = sh.getProtections(SpreadsheetApp.ProtectionType.SHEET);
      if (prots.length > 0) ok(`Protección de hoja: ${shName} ✓`);
      else err(`Protección de hoja FALTANTE: ${shName}`);
    });

    // CONFIGURACION_GENERAL.clave — protección de rango
    {
      const sh = getSheet("CONFIGURACION_GENERAL");
      if (sh) {
        const headers = getHeaders(sh);
        const colIdx  = getColIdx(headers, "clave");
        if (colIdx >= 0 && colProtected(sh, colIdx)) ok("Protección de rango: CONFIGURACION_GENERAL.clave ✓");
        else err("Protección de rango FALTANTE: CONFIGURACION_GENERAL.clave");
      }
    }

    // RESERVAS — columnas técnicas
    {
      const sh = getSheet("RESERVAS");
      if (sh) {
        const headers = getHeaders(sh);
        ["id_reserva","id_prereserva","created_at","updated_at","source_event"].forEach(col => {
          const idx = getColIdx(headers, col);
          if (idx >= 0 && colProtected(sh, idx)) ok(`Protección de rango: RESERVAS.${col} ✓`);
          else err(`Protección de rango FALTANTE: RESERVAS.${col}`);
        });
      }
    }

    // PAGOS — columnas técnicas
    {
      const sh = getSheet("PAGOS");
      if (sh) {
        const headers = getHeaders(sh);
        ["id_pago","created_at","updated_at","es_automatico","referencia_externa","tx_hash"].forEach(col => {
          const idx = getColIdx(headers, col);
          if (idx >= 0 && colProtected(sh, idx)) ok(`Protección de rango: PAGOS.${col} ✓`);
          else err(`Protección de rango FALTANTE: PAGOS.${col}`);
        });
      }
    }

    // DESCUENTOS.usos_actuales
    {
      const sh = getSheet("DESCUENTOS");
      if (sh) {
        const headers = getHeaders(sh);
        const idx = getColIdx(headers, "usos_actuales");
        if (idx >= 0 && colProtected(sh, idx)) ok("Protección de rango: DESCUENTOS.usos_actuales ✓");
        else err("Protección de rango FALTANTE: DESCUENTOS.usos_actuales");
      }
    }
  }

  if (entorno === "DEV") {
    sep("BLOQUE 5 — PROTECCIONES (DEV)");
    const sh = getSheet("CONFIGURACION_GENERAL");
    if (sh) {
      const headers = getHeaders(sh);
      const idx = getColIdx(headers, "clave");
      if (idx >= 0 && colProtected(sh, idx)) ok("Protección de rango: CONFIGURACION_GENERAL.clave ✓");
      else err("Protección de rango FALTANTE: CONFIGURACION_GENERAL.clave");
    }
  }

  // ══════════════════════════════════════════════════════════
  // RESUMEN FINAL
  // ══════════════════════════════════════════════════════════
  const totalChecks = resultados.filter(r => r.includes("✅") || r.includes("❌")).length;
  const resumenFinal = [
    `\n══════════════════════════════════════`,
    `  AUDITORÍA FASE 6 — ${entorno}`,
    `══════════════════════════════════════`,
    ...resultados,
    `\n══════════════════════════════════════`,
    `  RESULTADO FINAL`,
    `  ✅ OK:       ${totalChecks - errores}`,
    `  ⚠️  Warnings: ${warnings}`,
    `  ❌ Errores:  ${errores}`,
    `══════════════════════════════════════`,
    errores > 0
      ? `\n❌ HAY ${errores} ERROR(ES). Corregir antes de avanzar a n8n.`
      : warnings > 0
        ? `\n⚠️  Todo OK pero hay ${warnings} aviso(s) para revisar.`
        : `\n✅ SHEETS LISTO PARA n8n. Todos los checks pasaron.`,
  ].join("\n");

  Logger.log(resumenFinal);

  // Alert con resumen ejecutivo (el log completo queda en Extensiones → Apps Script → Registros)
  const alertMsg = [
    `Entorno: ${entorno}`,
    ``,
    `✅ OK:       ${totalChecks - errores}`,
    `⚠️  Warnings: ${warnings}`,
    `❌ Errores:  ${errores}`,
    ``,
    errores > 0
      ? `HAY ERRORES. No avanzar a n8n.\nRevisá el log completo en:\nExtensiones → Apps Script → Ver → Registros`
      : warnings > 0
        ? `Sin errores, pero hay avisos.\nRevisá el log para los detalles.`
        : `SHEETS LISTO PARA n8n.\nTodos los checks pasaron correctamente.`,
  ].join("\n");

  ui.alert(
    errores > 0 ? `❌ Auditoría ${entorno} — HAY ERRORES` :
    warnings > 0 ? `⚠️ Auditoría ${entorno} — Con avisos` :
    `✅ Auditoría ${entorno} — Todo OK`,
    alertMsg,
    ui.ButtonSet.OK
  );
}
