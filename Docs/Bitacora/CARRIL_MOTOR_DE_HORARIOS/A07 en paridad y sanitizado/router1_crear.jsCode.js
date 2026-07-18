// router1_crear — lee PG-1. Mapea error o arma pg2_args (con payload2 que INCLUYE id_pre_reserva).
const res = $json.resultado; const D = $('Code: derivar').first().json;
function mapErr(e) {
  const conflicto = ['no_disponible'];
  const payloadInv = ['cabana_no_existe','cabana_inactiva','excede_capacidad','fechas_invalidas',
    'precio_requerido','huesped_nombre_requerido','huesped_contacto_requerido','hora_fuera_de_rango','payload_invalido','fecha_in_pasada','override_hora_invalido'];

  if (e === 'checkin_pisa_checkout_anterior') return {
    ok:false,
    error: {
      code:'conflicto',
      message:'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.',
      detail:null
    }
  };

  if (e === 'checkout_pisa_checkin_posterior') return {
    ok:false,
    error: {
      code:'conflicto',
      message:'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.',
      detail:null
    }
  };

  if (conflicto.includes(e)) return { ok:false, error: { code:'conflicto', message:'sin disponibilidad en el rango', detail:null } };
  if (payloadInv.includes(e)) return { ok:false, error: { code:'payload_invalido', message:'datos de reserva rechazados: '+e, detail:null } };
  if (e === 'unique_violation_inesperado') return { ok:false, error: { code:'estado_incierto', message:'estado incierto al crear; verificar antes de reintentar', detail:{ paso:'prereserva', ids_creados:{}, source_event:D.sev, idempotency_key:D.idem } } };
  return { ok:false, error: { code:'error_interno', message:'no se pudo crear la prereserva', detail:null } };
}
if (!res || res.ok !== true) return [{ json: { continuar:false, envelope: mapErr(res ? res.error : null) } }];
const id_pre = res.id_pre_reserva;
// payload2 = base + id_pre_reserva (clave EXACTA del payload de registrar_pago, 6B L4580).
const payload2 = Object.assign({}, D.payload2_base, { id_pre_reserva: id_pre });
const pg2_args = JSON.stringify({ idem: D.idem, id_pre, sev: D.sev, payload2 });
return [{ json: { continuar:true, id_pre, pg2_args } }];