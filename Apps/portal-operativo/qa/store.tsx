// Estado del harness: que fixture se esta mirando. No es parte de la app.
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
import { createContext, useContext, useState, type ReactNode } from 'react';

export interface SeleccionQA {
  a30: string;
  a31: string;
  /** Simula el estado de lectura de cada accion, para probar loading / error / retry. */
  estadoA30: 'data' | 'loading' | 'error' | 'inactivo';
  estadoA31: 'data' | 'loading' | 'error';
  /** Mes APLICADO. Se separa del fixture a proposito: con data de julio y mesApplied '2026-08'
   *  se reproduce el anti-flash real (data vieja contra mes nuevo). */
  mesApplied: string;
  faltaAccion: boolean;
  fotoPendiente: boolean;
  seleccionFueraDePiso: boolean;
  reiniciadoPorPiso: boolean;
}

export const DEFECTO: SeleccionQA = {
  a30: 'F1',
  a31: 'F10',
  estadoA30: 'data',
  estadoA31: 'data',
  mesApplied: '2026-07',
  faltaAccion: false,
  fotoPendiente: false,
  seleccionFueraDePiso: false,
  reiniciadoPorPiso: false,
};

const Ctx = createContext<{ sel: SeleccionQA; set: (s: Partial<SeleccionQA>) => void } | null>(null);

export function QAProvider({ children }: { children: ReactNode }) {
  const [sel, setSel] = useState<SeleccionQA>(DEFECTO);
  const set = (p: Partial<SeleccionQA>) => setSel((v) => ({ ...v, ...p }));
  return <Ctx.Provider value={{ sel, set }}>{children}</Ctx.Provider>;
}

export function useQA() {
  const c = useContext(Ctx);
  if (!c) throw new Error('useQA fuera de QAProvider');
  return c;
}
