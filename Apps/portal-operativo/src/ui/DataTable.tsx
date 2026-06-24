import type { ReactNode } from 'react';

/** Definicion de columna para DataTable (D-FE-15): key, header, alineacion y render de celda. */
export interface Columna<T> {
  key: string;
  header: string;
  align?: 'left' | 'right' | 'center';
  render: (fila: T) => ReactNode;
}

function alinear(a?: 'left' | 'right' | 'center'): string {
  return a === 'right' ? 'text-right' : a === 'center' ? 'text-center' : 'text-left';
}

/**
 * Tabla de lista compartida (D-FE-15). Tabla semantica dentro de un contenedor con scroll
 * horizontal (no recorta en pantallas angostas). Las columnas numericas se alinean a la
 * derecha via `align`. El vacio NO lo maneja DataTable: la pantalla decide Vacio vs tabla
 * (filas:[] != error, D-C-47).
 */
export function DataTable<T>({
  columnas,
  filas,
  filaKey,
}: {
  columnas: Columna<T>[];
  filas: T[];
  filaKey: (fila: T) => string | number;
}) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-sand bg-white">
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-sand bg-mist">
            {columnas.map((c) => (
              <th key={c.key} className={'whitespace-nowrap px-3 py-2 font-medium text-reed ' + alinear(c.align)}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => (
            <tr key={filaKey(f)} className="border-b border-sand/60 last:border-0">
              {columnas.map((c) => (
                <td key={c.key} className={'px-3 py-2 align-top text-ink ' + alinear(c.align)}>
                  {c.render(f)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
