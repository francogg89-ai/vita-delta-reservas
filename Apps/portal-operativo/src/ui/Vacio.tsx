/** Estado "sin resultados". OJO: lista vacia (filas:[]) NO es error (D-C-47). */
export function Vacio({ mensaje = 'Sin resultados.' }: { mensaje?: string }) {
  return (
    <div className="rounded-2xl border border-dashed border-sand bg-white px-6 py-10 text-center text-reed">
      {mensaje}
    </div>
  );
}
