import { construirMenu, type ActionMeta } from '../lib/actionRegistry';

interface MenuProps {
  acciones: string[];
  seleccion: string | null;
  onSelect: (meta: ActionMeta) => void;
}

export function Menu({ acciones, seleccion, onSelect }: MenuProps) {
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
            {g.items.map((item) => {
              const activo = item.action === seleccion;
              return (
                <li key={item.action}>
                  <button
                    type="button"
                    onClick={() => onSelect(item)}
                    aria-current={activo ? 'page' : undefined}
                    className={
                      'w-full rounded-lg px-3 py-2 text-left text-sm transition ' +
                      (activo
                        ? 'bg-river-light font-medium text-river-dark'
                        : 'text-ink hover:bg-mist')
                    }
                  >
                    {item.label}
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </nav>
  );
}
