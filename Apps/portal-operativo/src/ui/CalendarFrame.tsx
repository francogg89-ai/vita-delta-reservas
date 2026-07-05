import { useCallback, useEffect, useRef, useState } from 'react';

const ALTO_MIN = 240; // px: mientras mide / si no pudiera leer el documento
const SHIM_ID = 'vd-cal-shim';

/**
 * Shim de compatibilidad SIN SCRIPTS (D-FE-14). El HTML de A04 alterna meses con un
 * <script> (querySelectorAll('.tab') + addEventListener + section.style.display). Bajo
 * sandbox sin allow-scripts ese script NO corre, asi que solo queda visible el mes activo.
 * Solucion scriptless: mostrar TODOS los meses (override del display:none INLINE de los
 * <section class="mes"> no-activos: el !important de hoja de autor vence al inline normal)
 * y ocultar los tabs inertes. Es solo CSS -> no eleva permisos (se mantiene opcion A).
 * A03 limpieza es single-view (sin .mes/.tabs/script) -> los selectores no matchean (no-op).
 * Temporal: cuando A03/A04 migren a JSON (P-C-3) el shim desaparece.
 */
const SHIM_CSS =
  'section.mes{display:block !important;}.tabs,.tab{display:none !important;}' +
  // Divisor marcado entre cabanas (microfix UX A04 + A03): borde superior negro en la
  // PRIMERA fila de cada grupo de cabana. Cada calendario nombra esa fila distinto y esas
  // clases ya vienen en el HTML del backend como hook semantico: A04 = r-huesped, A03
  // limpieza = r-mov. Cada selector matchea SOLO su calendario (el otro no tiene esa clase),
  // asi que este mismo shim compartido sirve para los dos. No depende de nth-child(3n) ni
  // cambia HTML/datos. Solo presentacion (D-FE-03). Las 3 filas internas quedan intactas.
  '.r-huesped>td,.r-mov>td{border-top:2px solid #000 !important;}';

/**
 * Render del HTML temporal de los calendarios A03/A04 (D-FE-03 / D-FE-14, opcion A).
 *
 *  - iframe `srcDoc` con `sandbox="allow-same-origin"` y SIN `allow-scripts`: aisla los
 *    estilos del HTML del backend (y los de la app) y NO ejecuta sus scripts. El HTML es
 *    first-party y trae el texto dinamico escapado, asi que same-origin -para MEDIR el alto
 *    y aplicar el shim CSS- es aceptable; los scripts siguen apagados.
 *  - D-FE-03: el `srcDoc` queda con el HTML del backend INTACTO. El shim CSS se agrega como
 *    capa de presentacion aparte, en el <head> del documento ya renderizado (no se
 *    reinterpreta el HTML como datos).
 *  - Autosize: en `onLoad` se inyecta el shim (revela todos los meses) y RECIEN ahi se mide,
 *    para que el alto capture todos los meses visibles. Se re-mide en `resize` de ventana.
 */
export function CalendarFrame({ html, title }: { html: string; title: string }) {
  const ref = useRef<HTMLIFrameElement>(null);
  const [alto, setAlto] = useState(ALTO_MIN);

  const medir = useCallback(() => {
    const doc = ref.current?.contentDocument;
    if (!doc) return;
    const h = Math.max(doc.documentElement?.scrollHeight ?? 0, doc.body?.scrollHeight ?? 0);
    if (h > 0) setAlto(h);
  }, []);

  const onLoad = useCallback(() => {
    const doc = ref.current?.contentDocument;
    // Inyecta el shim CSS una sola vez por documento (revela todos los meses).
    if (doc && doc.head && !doc.getElementById(SHIM_ID)) {
      const st = doc.createElement('style');
      st.id = SHIM_ID;
      st.textContent = SHIM_CSS;
      doc.head.appendChild(st);
    }
    // Medir DESPUES del shim: el documento ya tiene todos los meses visibles.
    medir();
  }, [medir]);

  // El contenido reflowea cuando cambia el ancho de ventana -> re-medir.
  useEffect(() => {
    window.addEventListener('resize', medir);
    return () => window.removeEventListener('resize', medir);
  }, [medir]);

  // HTML nuevo -> alto minimo hasta que onLoad re-inyecte y mida el nuevo documento.
  useEffect(() => {
    setAlto(ALTO_MIN);
  }, [html]);

  return (
    <div className="overflow-hidden rounded-2xl border border-sand bg-white">
      <iframe
        ref={ref}
        title={title}
        srcDoc={html}
        sandbox="allow-same-origin"
        onLoad={onLoad}
        className="block w-full"
        style={{ height: alto, border: 0 }}
      />
    </div>
  );
}
