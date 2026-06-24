/** Estado de carga generico de pantalla (D-FE-13/18). */
export function Cargando({ mensaje = 'Cargando...' }: { mensaje?: string }) {
  return (
    <div className="flex items-center gap-3 rounded-2xl border border-sand bg-white px-6 py-8 text-reed">
      <span
        className="h-4 w-4 animate-spin rounded-full border-2 border-river border-t-transparent"
        aria-hidden
      />
      <span>{mensaje}</span>
    </div>
  );
}
