import { BrowserRouter } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { useAuth } from './auth/useAuth';
import { LoginScreen } from './auth/LoginScreen';
import { AppShell } from './app/AppShell';
import { BannerAmbiente } from './app/BannerAmbiente';
import { MOSTRAR_BANNER } from './lib/ambiente';

function Pantalla() {
  const { status, errorMessage, reintentarContexto, logout } = useAuth();

  if (status === 'cargando') {
    return (
      <div className="grid min-h-full place-items-center bg-mist">
        <p className="text-reed">Cargando...</p>
      </div>
    );
  }

  if (status === 'autenticado') {
    return <AppShell />;
  }

  if (status === 'error') {
    return (
      <div className="grid min-h-full place-items-center bg-mist px-4">
        <div className="w-full max-w-sm rounded-2xl border border-sand bg-white p-6 text-center">
          <p className="text-ink">
            {errorMessage ?? 'Ocurrio un error al cargar tu sesion.'}
          </p>
          <div className="mt-4 flex justify-center gap-2">
            <button
              type="button"
              onClick={() => void reintentarContexto()}
              className="rounded-lg bg-river px-4 py-2 text-sm font-medium text-white transition hover:bg-river-dark"
            >
              Reintentar
            </button>
            <button
              type="button"
              onClick={() => void logout()}
              className="rounded-lg border border-sand px-4 py-2 text-sm text-ink transition hover:bg-mist"
            >
              Salir
            </button>
          </div>
        </div>
      </div>
    );
  }

  // status === 'anonimo'
  return <LoginScreen />;
}

// BrowserRouter envuelve TODA la app (D-FE-12): asi la URL persiste a traves del login
// (deep-link a una ruta sin sesion -> login -> tras autenticar aterriza en la ruta).
// El login/error/cargando no usan rutas, pero viven bajo el Router sin efecto adverso.
export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        {/* Banner de ambiente: fijo arriba de todo, visible incluido pre-login. */}
        <BannerAmbiente />
        {/* h-full = 100% de #root (cadena html/body/#root height:100% en index.css).
            pt-8 reserva la franja del banner fijo (border-box por defecto en Tailwind),
            asi el min-h-full de cada pantalla resuelve contra el area util correcta. */}
        <div className={MOSTRAR_BANNER ? 'h-full pt-8' : 'h-full'}>
          <Pantalla />
        </div>
      </AuthProvider>
    </BrowserRouter>
  );
}
