import { NavLink } from 'react-router-dom';
import { construirMenu } from '../lib/actionRegistry';

interface MenuProps {
  acciones: string[];
  /** Se invoca al navegar (cierra el drawer mobile en AppShell). */
  onNavigate?: () => void;
}

export function Menu({ acciones, onNavigate }: MenuProps) {
  const grupos = construirMenu(acciones);

  if (grupos.length === 0) {
    return (
      <p className="px-3 py-2 text-sm text-reed">No hay acciones disponibles para tu rol.</p>
    );
  }

  return (
    <nav className="space-y-6">
      {grupos.map((g) => (
        <div key={g.id}>
          <p className="px-3 text-xs font-semibold uppercase tracking-wide text-reed">
            {g.label}
          </p>
          <ul className="mt-2 space-y-0.5">
            {g.items.map((item) => (
              <li key={item.action}>
                <NavLink
                  to={item.ruta}
                  onClick={onNavigate}
                  className={({ isActive }) =>
                    'block w-full rounded-lg px-3 py-2 text-left text-sm transition ' +
                    (isActive
                      ? 'bg-river-light font-medium text-river-dark'
                      : 'text-ink hover:bg-mist')
                  }
                >
                  {item.label}
                </NavLink>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );
}
