// ===== portal-a04-operativo__TEST — nodo Code (render) =====
// Deriva de vita_w8c_html_operativo (8C) v2.1: operativo, 120 dias, CON montos,
// pestanias por mes. Read-only. Adaptaciones para el portal (Carril C / Slice 1 / B4):
//   (1) ymd() endurece comparaciones de fecha (L-8C-02): robusto a timestamps ISO.
//   (2) los 2 return devuelven el ENVELOPE del portal (D-C-18/38), no {html,statusCode}.
//   (3) branch de error: SIN HTML de error (codigo muerto eliminado); devuelve error_interno limpio.
// Auditoria de privacidad (D-C-03): SOLO montos a nivel reserva (monto_total/saldo_real, display clampeado a >=0)
// via money(); NO reparto por socio, NO cascada, NO mayor/cuenta corriente, NO societario.
// esc() aplicado a TODO texto dinamico (huesped, telefono, motivo, personas, cabana, notas_reserva).
// 'descripcion' de bloqueo se lee pero NO se renderiza. Color: rojo > gris > verde > blanco.

const TZ = 'America/Argentina/Buenos_Aires';
const HORIZONTE_DIAS = 120;

function esc(v) {
  if (v === null || v === undefined) return '';
  return String(v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function hhmm(t) { if (!t) return ''; const s = String(t); return s.length >= 5 ? s.slice(0, 5) : s; }
function money(n) {
  if (n === null || n === undefined || n === '') return '';
  const num = Number(n); if (Number.isNaN(num)) return '';
  return '$' + num.toLocaleString('es-AR', { maximumFractionDigits: 0 });
}
function notaCorta(v) {
  if (v === null || v === undefined) return '';
  const s = String(v).replace(/\s+/g, ' ').trim();
  if (!s) return '';
  return s.length > 28 ? s.slice(0, 27) + '…' : s;
}
// Saldo a mostrar en el calendario (A04): saldo_real puede dar NEGATIVO por sobrepago (pagos
// confirmados > monto_total, p. ej. datos de prueba); operativamente se muestra $0. El saldo_real
// crudo (incl. negativo) queda para reportes/detalle si despues se quiere.
function saldoVisible(n) {
  if (n === null || n === undefined) return n;
  return n < 0 ? 0 : n;
}
// Nota operativa en su propia linea, debajo del telefono; escapada y atenuada.
function notaLinea(v) {
  const t = notaCorta(v);
  return t ? '<br><span style="opacity:.7">📝 ' + esc(t) + '</span>' : '';
}
function primerNombre(full) { if (!full) return ''; return String(full).trim().split(/\s+/)[0]; }
// Normaliza date|timestamp ('2026-06-01T00:00:00.000Z') a 'YYYY-MM-DD' (L-8C-02).
function ymd(v) { if (v === null || v === undefined) return ''; return String(v).slice(0, 10); }

function safeAll(nodeName, keyField) {
  try {
    const items = $(nodeName).all();
    const failed = items.some(it => it && it.json && (it.json.error || it.error));
    if (failed) return { ok: false, rows: [] };
    const rows = items.map(it => it.json).filter(j => j && j[keyField] !== undefined && j[keyField] !== null);
    return { ok: true, rows };
  } catch (e) { return { ok: false, rows: [] }; }
}

const gridR = safeAll('PG: leer grilla', 'id_cabana');
const resR  = safeAll('PG: leer detalle', 'id_reserva');
const blkR  = safeAll('PG: leer bloqueos', 'id_bloqueo');
const outR  = safeAll('PG: leer salidas', 'id_reserva');
const huboError = !gridR.ok || !resR.ok || !blkR.ok || !outR.ok;

if (huboError) {
  // Branch de error: envelope uniforme, sin filtrar SQL/n8n crudo al cliente (D-C-18).
  return [{ json: { ok: false, error: { code: 'error_interno', message: 'no se pudo cargar el calendario', detail: null } } }];
}

const ORDEN_CABANAS = [
  { id: 1, nombre: 'Bamboo' }, { id: 2, nombre: 'Madre Selva' }, { id: 3, nombre: 'Arrebol' },
  { id: 4, nombre: 'Guatemala' }, { id: 5, nombre: 'Tokio' },
];

const dias = Array.from(new Set(gridR.rows.map(r => ymd(r.fecha)))).sort();
const primerDiaVisible = dias.length ? dias[0] : null;

const reservasPorCabana = {};
for (const r of resR.rows) (reservasPorCabana[r.id_cabana] = reservasPorCabana[r.id_cabana] || []).push(r);

const salidasPorCabana = {};
const vistosSalida = new Set();
function pushSalida(idc, idr, fecha, hora, nombre) {
  const k = String(idr);
  if (vistosSalida.has(k)) return;
  vistosSalida.add(k);
  (salidasPorCabana[idc] = salidasPorCabana[idc] || []).push({ id_reserva: idr, fecha_checkout: fecha, hora_checkout: hora, huesped_nombre: nombre });
}
for (const r of resR.rows) pushSalida(r.id_cabana, r.id_reserva, ymd(r.fecha_checkout), r.hora_checkout, r.huesped_nombre);
for (const s of outR.rows) pushSalida(s.id_cabana, s.id_reserva, ymd(s.fecha_checkout), s.hora_checkout, s.huesped_nombre);

const bloqueosEspecificos = {};
const bloqueosTotales = [];
for (const b of blkR.rows) {
  if (b.id_cabana === null || b.id_cabana === undefined) bloqueosTotales.push(b);
  else (bloqueosEspecificos[b.id_cabana] = bloqueosEspecificos[b.id_cabana] || []).push(b);
}

function reservasDeCabana(idc) { return reservasPorCabana[idc] || []; }
function salidasDeCabana(idc) { return salidasPorCabana[idc] || []; }
function entradaEseDia(idc, dia) { return reservasDeCabana(idc).find(r => ymd(r.fecha_checkin) === dia) || null; }
function salidaEseDia(idc, dia) { return salidasDeCabana(idc).find(s => ymd(s.fecha_checkout) === dia) || null; }
function ocupadaEseDia(idc, dia) {
  return reservasDeCabana(idc).find(r =>
    (ymd(r.fecha_checkin) <= dia && dia < ymd(r.fecha_checkout)) || ymd(r.fecha_checkout) === dia) || null;
}
function bloqueosQueCubren(idc, dia) {
  const esp = (bloqueosEspecificos[idc] || []).filter(b => ymd(b.fecha_desde) <= dia && dia < ymd(b.fecha_hasta));
  const tot = bloqueosTotales.filter(b => ymd(b.fecha_desde) <= dia && dia < ymd(b.fecha_hasta));
  return esp.concat(tot);
}
function bordeBloqueoEseDia(idc, dia) {
  const todos = (bloqueosEspecificos[idc] || []).concat(bloqueosTotales);
  return todos.find(b => ymd(b.fecha_desde) === dia || ymd(b.fecha_hasta) === dia) || null;
}

function calcularCelda(idc, dia) {
  const entra = entradaEseDia(idc, dia);
  const sale = salidaEseDia(idc, dia);
  const ocupa = ocupadaEseDia(idc, dia);
  const bloqueosCubren = bloqueosQueCubren(idc, dia);
  const bloqueado = bloqueosCubren.length > 0;
  const borde = bordeBloqueoEseDia(idc, dia);
  const hayMovimiento = !!(entra || sale);
  const recambioHuesped = !!(entra && sale && entra.id_reserva !== sale.id_reserva);
  const rojoBloqueoMov = !!(borde && hayMovimiento);
  if (recambioHuesped || rojoBloqueoMov) return { color: 'rojo', sale, entra, borde, bloqueosCubren };
  if (bloqueado) return { color: 'gris', bloqueosCubren };
  if (ocupa) {
    const inicioVisible = (ymd(ocupa.fecha_checkin) === dia) || (primerDiaVisible === dia && ymd(ocupa.fecha_checkin) < dia);
    // Dia de salida sin recambio (no hubo rojo porque nadie entra): mostrar "Sale X · hora".
    const esSalida = !!sale && !inicioVisible;
    return { color: 'verde', reserva: ocupa, esInicioVisible: inicioVisible, esSalida, sale };
  }
  return { color: 'blanco' };
}

const COLORES = {
  rojo: { bg: '#f8d2d2', label: 'Recambio / doble evento' },
  gris: { bg: '#d9d9d9', label: 'Bloqueo' },
  verde: { bg: '#cdeccd', label: 'Ocupado' },
  blanco: { bg: '#ffffff', label: 'Libre' },
};

const meses = {};
for (const dia of dias) (meses[dia.slice(0, 7)] = meses[dia.slice(0, 7)] || []).push(dia);
const NOMBRE_MES = { '01': 'Enero', '02': 'Febrero', '03': 'Marzo', '04': 'Abril', '05': 'Mayo', '06': 'Junio', '07': 'Julio', '08': 'Agosto', '09': 'Septiembre', '10': 'Octubre', '11': 'Noviembre', '12': 'Diciembre' };

function contenidoCelda(idc, dia) {
  const c = calcularCelda(idc, dia);
  const bg = COLORES[c.color].bg;
  let f1 = '', f2 = '', f3 = '';
  if (c.color === 'verde' && c.esInicioVisible) {
    const r = c.reserva;
    f1 = esc(r.huesped_nombre) + ' · ' + esc(r.personas) + 'p · ' + hhmm(r.hora_checkin);
    f2 = esc(r.huesped_telefono) + notaLinea(r.notas_reserva);
    f3 = money(r.monto_total) + ' / saldo ' + money(saldoVisible(r.saldo_real));
  } else if (c.color === 'verde' && c.esSalida) {
    // Dia de check-out sin recambio: solo "Sale <nombre> · <hora>"; filas 2-3 vacias.
    f1 = 'Sale ' + esc(primerNombre(c.sale.huesped_nombre)) + ' · ' + hhmm(c.sale.hora_checkout);
  } else if (c.color === 'rojo') {
    let arriba = '';
    if (c.sale) arriba = 'Sale ' + esc(primerNombre(c.sale.huesped_nombre)) + ' · ' + hhmm(c.sale.hora_checkout);
    else if (c.borde && ymd(c.borde.fecha_hasta) === dia) arriba = 'Fin bloqueo';
    let abajo = '';
    if (c.entra) {
      abajo = 'Entra ' + esc(c.entra.huesped_nombre) + ' · ' + esc(c.entra.personas) + 'p · ' + hhmm(c.entra.hora_checkin);
      f2 = esc(c.entra.huesped_telefono) + notaLinea(c.entra.notas_reserva);
      f3 = money(c.entra.monto_total) + ' / saldo ' + money(saldoVisible(c.entra.saldo_real));
    } else if (c.borde && ymd(c.borde.fecha_desde) === dia) {
      abajo = 'Inicio bloqueo · ' + esc(c.borde.motivo);
    }
    f1 = arriba && abajo ? (arriba + '<br>' + abajo) : (arriba || abajo);
  } else if (c.color === 'gris') {
    const b = c.bloqueosCubren[0];
    const extra = c.bloqueosCubren.length > 1 ? ' (+)' : '';
    f1 = esc(b ? b.motivo : 'bloqueo') + extra;
  }
  return { bg, f1, f2, f3 };
}

// Mes que contiene "hoy" (pestaña activa por defecto). primerDiaVisible es hoy salvo borde.
const hoyYM = (primerDiaVisible || dias[0] || '').slice(0, 7);
const clavesMes = Object.keys(meses).sort();
const mesActivo = clavesMes.indexOf(hoyYM) >= 0 ? hoyYM : (clavesMes[0] || '');

let secciones = '';
let pestanias = '';
for (const mk of clavesMes) {
  const diasMes = meses[mk];
  const parts = mk.split('-'); const anio = parts[0]; const mes = parts[1];
  const activa = (mk === mesActivo);
  const idMes = 'mes-' + mk;

  pestanias += '<button class="tab' + (activa ? ' tab-activa' : '') + '" data-mes="' + idMes + '" type="button">'
    + NOMBRE_MES[mes] + ' ' + anio + '</button>';

  let thDias = '<th class="cab">Cabaña</th>';
  for (const d of diasMes) thDias += '<th class="dia">' + d.slice(8, 10) + '</th>';
  let cuerpo = '';
  for (const cab of ORDEN_CABANAS) {
    const celdas = diasMes.map(d => contenidoCelda(cab.id, d));
    let tr1 = '<td class="cab" rowspan="3">' + esc(cab.nombre) + '</td>';
    let tr2 = '', tr3 = '';
    celdas.forEach(cel => {
      tr1 += '<td class="cell f1" style="background:' + cel.bg + '">' + cel.f1 + '</td>';
      tr2 += '<td class="cell f2" style="background:' + cel.bg + '">' + cel.f2 + '</td>';
      tr3 += '<td class="cell f3" style="background:' + cel.bg + '">' + cel.f3 + '</td>';
    });
    cuerpo += '<tr class="r-huesped">' + tr1 + '</tr><tr class="r-tel">' + tr2 + '</tr><tr class="r-pago">' + tr3 + '</tr>';
  }
  secciones += '<section class="mes" id="' + idMes + '"' + (activa ? '' : ' style="display:none"') + '><h2>' + NOMBRE_MES[mes] + ' ' + anio + '</h2>'
    + '<div class="scroll"><table><thead><tr>' + thDias + '</tr></thead><tbody>' + cuerpo + '</tbody></table></div></section>';
}

const ahora = new Intl.DateTimeFormat('es-AR', { timeZone: TZ, dateStyle: 'short', timeStyle: 'short' }).format(new Date());
const leyenda = Object.values(COLORES).map(c => '<span class="lg"><span class="sw" style="background:' + c.bg + '"></span>' + c.label + '</span>').join('');

const html = '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">'
  + '<meta name="viewport" content="width=device-width, initial-scale=1">'
  + '<title>Calendario operativo — Vita Delta</title>'
  + '<style>'
  + 'body{font-family:system-ui,Arial,sans-serif;margin:0;padding:1rem;background:#fafafa;color:#222}'
  + 'h1{font-size:1.3rem;margin:.2rem 0}'
  + '.info{color:#666;font-size:.8rem;margin-bottom:.8rem}'
  + '.leyenda{margin:.5rem 0 1rem;font-size:.8rem}'
  + '.lg{margin-right:1rem;white-space:nowrap}.sw{display:inline-block;width:14px;height:14px;border:1px solid #aaa;vertical-align:middle;margin-right:4px}'
  + '.mes{margin-bottom:1.5rem}.mes h2{font-size:1rem;margin:.5rem 0}'
  + '.tabs{display:flex;flex-wrap:wrap;gap:.4rem;margin:.6rem 0 1rem}'
  + '.tab{font-family:inherit;font-size:.85rem;padding:.4rem .8rem;border:1px solid #ccc;border-radius:8px;background:#fff;color:#333;cursor:pointer}'
  + '.tab:hover{background:#f0f0f0}'
  + '.tab-activa{background:#225;color:#fff;border-color:#225;font-weight:bold}'
  + '.scroll{overflow-x:auto;border:1px solid #ddd;border-radius:8px}'
  + 'table{border-collapse:collapse;font-size:.7rem;min-width:100%}'
  + 'th,td{border:1px solid #e0e0e0;padding:2px 4px;text-align:center;vertical-align:middle}'
  + 'th.dia{min-width:78px}'
  + 'td.cab,th.cab{position:sticky;left:0;background:#f0f0f0;font-weight:bold;text-align:left;min-width:90px;z-index:1}'
  + '.cell{min-width:78px;font-size:.65rem;line-height:1.15;height:18px}'
  + '.r-huesped .f1{font-weight:bold}'
  + '.r-pago .f3{color:#225}'
  + '</style></head>'
  + '<body>'
  + '<h1>Calendario operativo — Complejo Vita Delta</h1>'
  + '<div class="info">Datos al ' + esc(ahora) + ' · horizonte ' + HORIZONTE_DIAS + ' días · TEST</div>'
  + '<div class="leyenda">' + leyenda + '</div>'
  + '<div class="tabs">' + pestanias + '</div>'
  + secciones
  + '<script>'
  + '(function(){'
  + 'var tabs=document.querySelectorAll(".tab");'
  + 'function mostrar(idMes){'
  + 'var secs=document.querySelectorAll("section.mes");'
  + 'for(var i=0;i<secs.length;i++){secs[i].style.display=(secs[i].id===idMes)?"":"none";}'
  + 'for(var j=0;j<tabs.length;j++){'
  + 'if(tabs[j].getAttribute("data-mes")===idMes){tabs[j].classList.add("tab-activa");}'
  + 'else{tabs[j].classList.remove("tab-activa");}}'
  + '}'
  + 'for(var k=0;k<tabs.length;k++){'
  + 'tabs[k].addEventListener("click",function(){mostrar(this.getAttribute("data-mes"));});'
  + '}'
  + '})();'
  + '</script>'
  + '</body></html>';

return [{ json: { ok: true, data: { formato: 'html', html } } }];