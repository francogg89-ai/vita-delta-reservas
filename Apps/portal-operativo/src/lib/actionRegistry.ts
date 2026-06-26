import type { SesionContexto } from './types';

// Registry de presentacion del menu (D-FE-09).
// El registry SOLO aporta presentacion (label / grupo / orden / ruta) por `action`.
// La VISIBILIDAD la decide el backend via `acciones` de sesion.contexto (A02): es la
// unica autoridad. Cero hardcodeo de visibilidad por rol aca.
//
// sesion.contexto (A02) NO esta en el registry: es la llamada de bootstrap, no un item de menu.

export type Grupo = 'calendarios' | 'reservas' | 'bloqueos' | 'cobranzas' | 'economico';

export interface ActionMeta {
  action: string;
  label: string;
  grupo: Grupo;
  orden: number;
  ruta: string;
}

/** Grupos y su orden de aparicion en el menu (agrupacion funcional del contrato §10). */
export const GRUPOS: { id: Grupo; label: string }[] = [
  { id: 'calendarios', label: 'Calendarios' },
  { id: 'reservas', label: 'Reservas' },
  { id: 'bloqueos', label: 'Bloqueos' },
  { id: 'cobranzas', label: 'Cobranzas' },
  { id: 'economico', label: 'Economico' },
];

/**
 * Presentacion por accion. `ruta` queda definida (D-FE-09) para cuando entre el router
 * con las pantallas reales (sub-slice 1+); en sub-slice 0 la navegacion es por estado.
 */
export const ACTION_REGISTRY: Record<string, ActionMeta> = {
  'calendario.limpieza': {
    action: 'calendario.limpieza',
    label: 'Calendario de limpieza',
    grupo: 'calendarios',
    orden: 10,
    ruta: '/calendarios/limpieza',
  },
  'calendario.operativo': {
    action: 'calendario.operativo',
    label: 'Calendario operativo',
    grupo: 'calendarios',
    orden: 20,
    ruta: '/calendarios/operativo',
  },
  'reserva.detalle': {
    action: 'reserva.detalle',
    label: 'Detalle de reserva',
    grupo: 'reservas',
    orden: 10,
    ruta: '/reservas/detalle',
  },
  'prereservas.activas': {
    action: 'prereservas.activas',
    label: 'Pre-reservas activas',
    grupo: 'reservas',
    orden: 20,
    ruta: '/reservas/prereservas',
  },
  'historico.reservas': {
    action: 'historico.reservas',
    label: 'Historico de reservas',
    grupo: 'reservas',
    orden: 30,
    ruta: '/reservas/historico',
  },
  'reserva.crear_manual': {
    action: 'reserva.crear_manual',
    label: 'Crear reserva',
    grupo: 'reservas',
    orden: 40,
    ruta: '/reservas/crear',
  },
  'bloqueo.crear_manual': {
    action: 'bloqueo.crear_manual',
    label: 'Crear bloqueo',
    grupo: 'bloqueos',
    orden: 10,
    ruta: '/bloqueos/crear',
  },
  'cobranza.saldos': {
    action: 'cobranza.saldos',
    label: 'Saldos a cobrar',
    grupo: 'cobranzas',
    orden: 10,
    ruta: '/cobranzas/saldos',
  },
  'cobranza.registrar_cobro': {
    action: 'cobranza.registrar_cobro',
    label: 'Registrar cobro',
    grupo: 'cobranzas',
    orden: 20,
    ruta: '/cobranzas/registrar',
  },
  'ingresos.cobrados_periodo': {
    action: 'ingresos.cobrados_periodo',
    label: 'Ingresos cobrados',
    grupo: 'economico',
    orden: 10,
    ruta: '/economico/ingresos',
  },
  'gastos.listado': {
    action: 'gastos.listado',
    label: 'Gastos',
    grupo: 'economico',
    orden: 20,
    ruta: '/economico/gastos',
  },
  'cargar.gasto_interno': {
    action: 'cargar.gasto_interno',
    label: 'Cargar gasto',
    grupo: 'economico',
    orden: 30,
    ruta: '/economico/cargar-gasto',
  },
};

export interface GrupoMenu {
  id: Grupo;
  label: string;
  items: ActionMeta[];
}

/**
 * Composicion del menu (D-FE-09): interseccion de `acciones` (autoridad del backend)
 * con ACTION_REGISTRY (presentacion del frontend).
 *  - Accion en `acciones` sin entrada en el registry -> se ignora (tolerancia forward,
 *    coherente con el pin de version D-FE-01).
 *  - Entrada del registry que no este en `acciones` -> no se muestra.
 *  - Grupos sin items visibles no se renderizan.
 */
export function construirMenu(acciones: SesionContexto['acciones']): GrupoMenu[] {
  const permitidas = new Set(acciones);
  return GRUPOS.map((g) => ({
    id: g.id,
    label: g.label,
    items: Object.values(ACTION_REGISTRY)
      .filter((m) => m.grupo === g.id && permitidas.has(m.action))
      .sort((a, b) => a.orden - b.orden),
  })).filter((g) => g.items.length > 0);
}
