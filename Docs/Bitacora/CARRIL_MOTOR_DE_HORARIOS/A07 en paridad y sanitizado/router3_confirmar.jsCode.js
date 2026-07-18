// router3_confirmar — lee PG-3. Exito {ok:true,data}; conflicto; ajuste 3:
// estado_invalido + estado_actual='convertida' -> recheck (PG-4); resto -> estado_incierto.
const res = $json.resultado; const D = $('Code: derivar').first().json;
const id_pre = $('router1_crear').first().json.id_pre;
if (res && res.ok === true) return [{ json: { recheck:false, envelope: { ok:true, data: {
  id_reserva: res.id_reserva, id_pre_reserva: res.id_pre_reserva, id_huesped: res.id_huesped, idempotent_match: false } } } }];

const e = res ? res.error : null;

if (e === 'checkin_pisa_checkout_anterior') return [{
  json: {
    recheck:false,
    envelope: {
      ok:false,
      error: {
        code:'conflicto',
        message:'gap_checkin: El check-in queda demasiado cerca del checkout anterior. Elegí un horario de entrada más tarde.',
        detail:null
      }
    }
  }
}];

if (e === 'checkout_pisa_checkin_posterior') return [{
  json: {
    recheck:false,
    envelope: {
      ok:false,
      error: {
        code:'conflicto',
        message:'gap_checkout: El check-out queda demasiado cerca del check-in posterior. Elegí un horario de salida más temprano.',
        detail:null
      }
    }
  }
}];

if (e === 'estado_invalido' && res && res.estado_actual === 'convertida') return [{ json: { recheck:true } }];
if (e === 'conflicto_al_confirmar' || e === 'no_disponible') return [{ json: { recheck:false, envelope: {
  ok:false, error: { code:'conflicto', message:'conflicto de disponibilidad al confirmar', detail:null } } } }];
return [{ json: { recheck:false, envelope: { ok:false, error: {
  code:'estado_incierto', message:'estado incierto al confirmar; verificar antes de reintentar',
  detail: { paso:'confirmacion', ids_creados: { id_pre_reserva: id_pre }, source_event: D.sev, idempotency_key: D.idem } } } } }];