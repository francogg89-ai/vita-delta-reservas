import type { ComponentType } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { ACTION_REGISTRY } from '../lib/actionRegistry';
import { RutaProtegida } from './RutaProtegida';
import { PlaceholderView } from './PlaceholderView';
import { Home } from './Home';
import { CalendarioLimpieza, CalendarioOperativo } from '../screens/Calendarios';
import { ReservaDetalle } from '../screens/ReservaDetalle';
import { PrereservasActivas } from '../screens/PrereservasActivas';
import { CobranzaSaldos } from '../screens/CobranzaSaldos';
import { HistoricoReservas } from '../screens/HistoricoReservas';
import { IngresosPeriodo } from '../screens/IngresosPeriodo';
import { GastosListado } from '../screens/GastosListado';
import { CrearBloqueo } from '../screens/CrearBloqueo';
import { CrearReserva } from '../screens/CrearReserva';
import { CargarGasto } from '../screens/CargarGasto';
import { RegistrarCobro } from '../screens/RegistrarCobro';
import { CuentaCorriente } from '../screens/CuentaCorriente';

/**
 * Pantallas reales ya implementadas (action -> componente). Los placeholders se reemplazan
 * por bloque. Lecturas (sub-slice 1): A03/A04/A05/A06/A12/A24/A25/A13. Escrituras (sub-slice 2):
 * B2 A08, B3 A07, B4 A11, B5 A10-MP (cobranza.registrar_cobro). W10 (cobranza.registrar_saldo)
 * queda fuera del registry: deprecated-in-place en backend, sin pantalla en el portal.
 */
const PANTALLAS: Record<string, ComponentType> = {
  'calendario.limpieza': CalendarioLimpieza,
  'calendario.operativo': CalendarioOperativo,
  'reserva.detalle': ReservaDetalle,
  'prereservas.activas': PrereservasActivas,
  'cobranza.saldos': CobranzaSaldos,
  'cobranza.registrar_cobro': RegistrarCobro,
  'historico.reservas': HistoricoReservas,
  'ingresos.cobrados_periodo': IngresosPeriodo,
  'gastos.listado': GastosListado,
  'bloqueo.crear_manual': CrearBloqueo,
  'reserva.crear_manual': CrearReserva,
  'cargar.gasto_interno': CargarGasto,
  'cuenta_corriente.al_dia': CuentaCorriente,
};

/**
 * Tabla de rutas del portal (D-FE-12). Se deriva de ACTION_REGISTRY (presentacion-only,
 * D-FE-09): cada `ruta` se cablea a su pantalla (real si esta en PANTALLAS, si no el
 * placeholder), envuelta en el guard de rol (RutaProtegida). El registry NO se toca.
 * `path` quita el slash inicial de `ruta`; los NavLink usan la `ruta` absoluta.
 * Ruta desconocida -> redirect a `/`.
 */
export function AppRoutes() {
  return (
    <Routes>
      <Route index element={<Home />} />
      {Object.values(ACTION_REGISTRY).map((meta) => {
        const Pantalla = PANTALLAS[meta.action];
        return (
          <Route
            key={meta.action}
            path={meta.ruta.replace(/^\//, '')}
            element={
              <RutaProtegida action={meta.action}>
                {Pantalla ? <Pantalla /> : <PlaceholderView meta={meta} />}
              </RutaProtegida>
            }
          />
        );
      })}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
