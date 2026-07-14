// Entry del harness. NO es el entry de produccion (`index.html` de la raiz -> `src/main.tsx`).
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { AuthContext, type AuthState } from '../src/auth/AuthProvider';
import { AppShell } from '../src/app/AppShell';
import { BarraQA } from './BarraQA';
import { QAProvider } from './store';
import '../src/index.css';

// Sesion falsa: el AppShell REAL se monta con esto. Sin red, sin backend, sin login.
const SESION: AuthState = {
  status: 'autenticado',
  contexto: {
    nombre: 'Franco (QA)',
    rol: 'socio',
    acciones: [
      'cuenta_corriente.historico',
      'cuenta_corriente.historico_acumulados',
      'cuenta_corriente.detalle',
      'reservas.historico',
      'gastos.cargar',
    ],
  },
  errorMessage: null,
  login: async () => ({ ok: true }) as never,
  logout: async () => undefined,
  reintentarContexto: async () => undefined,
};

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QAProvider>
      <MemoryRouter initialEntries={['/cuenta-corriente/historico']}>
        <AuthContext.Provider value={SESION}>
          <AppShell />
        </AuthContext.Provider>
      </MemoryRouter>
      <BarraQA />
    </QAProvider>
  </StrictMode>
);
