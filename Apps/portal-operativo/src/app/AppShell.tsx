import { useState } from 'react';
import { useAuth } from '../auth/useAuth';
import { Menu } from './Menu';
import { PlaceholderView } from './PlaceholderView';
import type { ActionMeta } from '../lib/actionRegistry';

const ROL_LABEL: Record<string, string> = {
  jenny: 'Limpieza',
  vicky: 'Operacion',
  socio: 'Socio',
};

export function AppShell() {
  const { contexto, logout } = useAuth();
  const [seleccion, setSeleccion] = useState<ActionMeta | null>(null);
  const [navAbierto, setNavAbierto] = useState(false);

  // App solo monta AppShell en estado 'autenticado', con contexto presente.
  if (!contexto) return null;

  const primerNombre = contexto.nombre.split(' ')[0];

  function elegir(meta: ActionMeta) {
    setSeleccion(meta);
    setNavAbierto(false);
  }

  return (
    <div className="flex min-h-full flex-col bg-mist">
      <header className="flex items-center justify-between border-b border-sand bg-white px-4 py-3">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => setNavAbierto((v) => !v)}
            className="rounded-lg p-2 text-ink hover:bg-mist md:hidden"
            aria-label="Abrir o cerrar menu"
            aria-expanded={navAbierto}
          >
            <span className="block h-0.5 w-5 bg-current" />
            <span className="mt-1 block h-0.5 w-5 bg-current" />
            <span className="mt-1 block h-0.5 w-5 bg-current" />
          </button>
          <span className="text-lg font-semibold tracking-tight text-ink">
            Vita <span className="text-river">Delta</span>
          </span>
        </div>

        <div className="flex items-center gap-3">
          <div className="text-right">
            <p className="text-sm font-medium leading-tight text-ink">{contexto.nombre}</p>
            <p className="text-xs leading-tight text-reed">
              {ROL_LABEL[contexto.rol] ?? contexto.rol}
            </p>
          </div>
          <button
            type="button"
            onClick={() => void logout()}
            className="rounded-lg border border-sand px-3 py-1.5 text-sm text-ink transition hover:bg-mist"
          >
            Salir
          </button>
        </div>
      </header>

      <div className="flex flex-1">
        <aside
          className={
            'w-64 shrink-0 border-r border-sand bg-white p-4 md:block ' +
            (navAbierto ? 'block' : 'hidden')
          }
        >
          <Menu
            acciones={contexto.acciones}
            seleccion={seleccion?.action ?? null}
            onSelect={elegir}
          />
        </aside>

        <main className="flex-1 p-6">
          {seleccion ? (
            <PlaceholderView meta={seleccion} />
          ) : (
            <div className="mx-auto max-w-2xl rounded-2xl border border-sand bg-white p-8">
              <h2 className="text-xl font-semibold text-ink">Hola, {primerNombre}</h2>
              <p className="mt-2 text-reed">Elegi una opcion del menu para empezar.</p>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
