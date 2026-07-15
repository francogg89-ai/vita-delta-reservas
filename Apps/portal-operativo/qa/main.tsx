// Entry del harness. NO es el entry de produccion (`index.html` de la raiz -> `src/main.tsx`).
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { AuthContext, type AuthState } from '../src/auth/AuthProvider';
import { AppShell } from '../src/app/AppShell';
import { BarraQA } from './BarraQA';
import { QAProvider } from './store';
import { instalarRedFalsa } from './stubs/red';
import '../src/index.css';

// Las ACCIONES de la sesion son configurables (SB-UI-6-FIX2). Antes estaban clavadas con A30 y A31
// siempre presentes, asi que el fail-closed del CONTENEDOR nunca se ejercitaba: se probaba
// renderizando `HistoricoVista` con `faltaAccion:true`, que es asumir la conclusion. Ahora se le
// saca la accion a la sesion y se mira que hace la pantalla real -- incluido si sale a la red.
//
//   ?acciones=ambas    (default)  A30 + A31
//   ?acciones=solo-a30            falta A31
//   ?acciones=solo-a31            falta A30
//   ?acciones=ninguna             faltan las dos
const A30 = 'cuenta_corriente.historico';
const A31 = 'cuenta_corriente.historico_acumulados';
const BASE = ['cuenta_corriente.detalle', 'reservas.historico', 'gastos.cargar'];

const PERFILES: Record<string, string[]> = {
  ambas: [A30, A31, ...BASE],
  'solo-a30': [A30, ...BASE],
  'solo-a31': [A31, ...BASE],
  ninguna: [...BASE],
};

const perfil = new URLSearchParams(window.location.search).get('acciones') ?? 'ambas';

// Sesion falsa: el AppShell REAL se monta con esto. Sin red, sin backend, sin login.
const SESION: AuthState = {
  status: 'autenticado',
  contexto: {
    nombre: 'Franco (QA)',
    rol: 'socio',
    acciones: PERFILES[perfil] ?? PERFILES.ambas,
  },
  errorMessage: null,
  login: async () => ({ ok: true }) as never,
  logout: async () => undefined,
  reintentarContexto: async () => undefined,
};

// El harness NO hace una sola llamada real: se intercepta `window.fetch` ANTES de montar nada.
// En modo ?contenedor=1 esto permite que corran de verdad HistoricoCuentaCorriente, useAction
// (con su reqId) y callPortal (con su envelope). Lo unico falso es el cable.
instalarRedFalsa();

const arbol = (
  <QAProvider>
    <MemoryRouter initialEntries={['/cuenta-corriente/historico']}>
      <AuthContext.Provider value={SESION}>
        <AppShell />
      </AuthContext.Provider>
    </MemoryRouter>
    <BarraQA />
  </QAProvider>
);

// StrictMode monta, DESMONTA y REMONTA: se crean DOS instancias de cada hook y las peticiones se
// reparten entre ellas. Para el resto del harness eso esta bien (es lo que pasa en dev, y ademas
// ejercita el cleanup). Pero el host de `reqId` necesita exactamente lo contrario: UNA instancia
// con DOS corridas del efecto. Con StrictMode, la peticion "vieja" pertenece a una instancia
// muerta y la descarta el cleanup -- el `reqId` no llega a intervenir. Por eso ahi se apaga.
const aislarInstancia = new URLSearchParams(window.location.search).get('host') === 'requid';

createRoot(document.getElementById('root')!).render(
  aislarInstancia ? arbol : <StrictMode>{arbol}</StrictMode>
);
