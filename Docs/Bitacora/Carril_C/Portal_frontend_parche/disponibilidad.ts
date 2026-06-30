// Logica de disponibilidad (pura, sin React). Decide elegibilidad y valida rangos contra el
// estado por NOCHE que devuelve A26. El backend es la autoridad final (principio #6): esto es
// solo prevencion en el frontend. Modelo half-open [desde, hasta): una estadia/bloqueo ocupa las
// noches desde..hasta-1; el dia `hasta` (checkout/liberacion) NO es noche del rango.

import type { EstadoDisponibilidad } from './contratos';
import { sumarDias } from './fecha';

export type ModoCalendario = 'reserva' | 'bloqueo';

/** Cache de disponibilidad: 'YYYY-MM-DD' -> estado de ESA noche. Ausente (undefined) = no cargada. */
export type CacheDisponibilidad = Map<string, EstadoDisponibilidad>;

/**
 * Una noche es elegible para integrar un rango si esta LIBRE.
 * disponible / checkout_disponible -> elegible (checkout_disponible vale como inicio, criterio #6).
 * ocupada / bloqueada -> no elegible. undefined (no cargada) -> no elegible (se exige cargar antes).
 */
export function esNocheElegible(estado: EstadoDisponibilidad | undefined): boolean {
  return estado === 'disponible' || estado === 'checkout_disponible';
}

/** Noches que ocupa el rango half-open [desde, hasta): desde, desde+1, ..., hasta-1. */
export function nochesDelRango(desde: string, hasta: string): string[] {
  const out: string[] = [];
  let cur = desde;
  while (cur < hasta) {
    out.push(cur);
    cur = sumarDias(cur, 1);
  }
  return out;
}

/**
 * Espejo EXACTO del backend para el dia de inicio del rango:
 *  - la noche de inicio debe estar libre (esNocheElegible);
 *  - reserva (A07): fecha_in NO puede ser anterior a hoy (espejo `fecha_in_pasada`);
 *  - bloqueo (A08): fecha_desde pasada SI permitida (el guard backend es sobre fecha_hasta, no
 *    sobre fecha_desde) -> NO se bloquea aca; si lo bloquearamos el front seria mas estricto
 *    que el backend (rompe D-FE-23).
 */
export function inicioValido(
  ymd: string,
  modo: ModoCalendario,
  hoy: string,
  cache: CacheDisponibilidad,
): boolean {
  if (!esNocheElegible(cache.get(ymd))) return false;
  if (modo === 'reserva' && ymd < hoy) return false;
  return true;
}

export type MotivoRango = 'rango_invertido' | 'fecha_hasta_pasada' | 'noche_no_elegible' | 'falta_cargar';
export type ResultadoRango = { ok: true } | { ok: false; motivo: MotivoRango; detalle?: string };

/**
 * Valida el rango completo [desde, hasta). Autoridad final = backend; esto previene en el front.
 *  - hasta > desde (sino `rango_invertido`);
 *  - bloqueo: hasta > hoy, es decir hasta >= manana (sino `fecha_hasta_pasada`) -> espejo
 *    `rango_pasado` (crear_bloqueo rechaza fecha_hasta <= hoy);
 *  - TODAS las noches [desde, hasta) deben estar CARGADAS (si falta una -> `falta_cargar`) y
 *    ELEGIBLES (si alguna ocupada/bloqueada -> `noche_no_elegible`). Esto cubre el cruce de mes:
 *    una noche ocupada en un mes aun no consultado NO puede aprobarse (cae en `falta_cargar`).
 */
export function validarRango(
  desde: string,
  hasta: string,
  modo: ModoCalendario,
  manana: string,
  cache: CacheDisponibilidad,
): ResultadoRango {
  if (!(desde < hasta)) return { ok: false, motivo: 'rango_invertido' };
  if (modo === 'bloqueo' && hasta < manana) return { ok: false, motivo: 'fecha_hasta_pasada' };
  for (const noche of nochesDelRango(desde, hasta)) {
    const e = cache.get(noche);
    if (e === undefined) return { ok: false, motivo: 'falta_cargar', detalle: noche };
    if (!esNocheElegible(e)) return { ok: false, motivo: 'noche_no_elegible', detalle: noche };
  }
  return { ok: true };
}

/**
 * Maximo `hasta` (dia de checkout/liberacion, EXCLUSIVO) seleccionable arrancando en `desde`,
 * caminando sobre noches cargadas y elegibles. Frena en la primera noche NO elegible o NO cargada;
 * ese dia es el checkout maximo (habilita el back-to-back: salir el dia en que entra el siguiente).
 * null si `desde` no tiene siquiera su propia noche libre/cargada. Como frena en la frontera de lo
 * cargado, la seleccion nunca puede cruzar a un mes sin consultar (refuerza `falta_cargar`).
 */
export function maxFinSeleccionable(desde: string, cache: CacheDisponibilidad): string | null {
  if (!esNocheElegible(cache.get(desde))) return null;
  let noche = desde;
  while (esNocheElegible(cache.get(noche))) {
    noche = sumarDias(noche, 1);
  }
  return noche;
}
