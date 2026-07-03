import { useCallback, useEffect, useState, type Dispatch, type SetStateAction } from 'react';
import { AMBIENTE } from '../lib/ambiente';

// Persistencia de borrador de formularios sobre sessionStorage (nativo, sin dependencias).
//
// Que resuelve: cuando una pantalla-formulario se desmonta y remonta -navegacion interna
// del portal (AppShell sobrevive al cambio de ruta pero la pantalla no), remonte del arbol,
// o recarga por descarte de la pestana en el celular-, el estado `useState` del form vuelve
// a su valor inicial y se pierde lo tipeado. Este hook restaura el form al montar y lo guarda
// en cada cambio, para que sobreviva a cualquiera de esos caminos sin depender de cual ocurra.
//
// Que guarda: SOLO el estado del form (el `valor`). Nunca errores, resultado, estado incierto,
// JWT, sesion ni nada de auth: eso vive en otros estados y no se toca.
//
// Ciclo de vida de la clave (la decide la pantalla, no el hook):
//   - restaura al montar (lazy init);
//   - persiste en cada cambio del `valor`;
//   - NO limpia al desmontar -> por eso la navegacion interna del portal no borra el borrador;
//   - la pantalla llama `limpiar()` en el exito y en "crear otra".
//
// sessionStorage (no localStorage): sobrevive a la recarga/descarte de la MISMA pestana, pero
// se borra al cerrarla -> minimo residuo de datos personales del huesped. Ademas TTL de 24h:
// un borrador mas viejo se descarta al restaurar (defensa para pestanas que quedan abiertas dias).

const TTL_MS = 24 * 60 * 60 * 1000; // 24h

interface Sobre<T> {
  t: number; // epoch ms del ultimo guardado (para el TTL)
  v: Partial<T>; // snapshot del form
}

function claveDe(id: string): string {
  // Ej.: id 'a07-crear-reserva:v1' -> 'vd:test:draft:a07-crear-reserva:v1'.
  // Versionada (la version va dentro del id) y por ambiente: un cambio de forma del form se
  // resuelve bumpeando el sufijo :vN en la pantalla, sin migrar borradores viejos.
  return `vd:${AMBIENTE}:draft:${id}`;
}

function leer<T>(clave: string): Partial<T> | null {
  try {
    const raw = sessionStorage.getItem(clave);
    if (raw === null) return null;
    const sobre = JSON.parse(raw) as { t?: unknown; v?: Partial<T> };
    if (typeof sobre.t !== 'number' || Date.now() - sobre.t > TTL_MS) {
      try { sessionStorage.removeItem(clave); } catch { /* noop */ }
      return null; // vencido o corrupto
    }
    return sobre.v ?? null;
  } catch {
    return null; // JSON invalido o storage inaccesible (modo privado, deshabilitado)
  }
}

export interface UseBorradorResult<T> {
  valor: T;
  setValor: Dispatch<SetStateAction<T>>;
  /** Borra el borrador de ESTE formulario (exito, "crear otra"). Referencia estable. */
  limpiar: () => void;
}

/**
 * Borrador persistente para un formulario. Reutilizable: cada pantalla pasa su propio `id`
 * (con version, ej. 'a07-crear-reserva:v1') y su objeto `inicial`. Conviene que `inicial` sea
 * una constante de modulo (estable entre renders).
 */
export function useBorradorPersistente<T extends object>(
  id: string,
  inicial: T,
): UseBorradorResult<T> {
  const clave = claveDe(id);

  // Lazy init: restaura una sola vez, en el primer render (sin flash de vacio). Merge sobre
  // `inicial`: si el form gano un campo nuevo sin bumpear version, no queda `undefined` en un
  // input controlado; los campos guardados pisan a los iniciales.
  const [valor, setValor] = useState<T>(() => {
    const restaurado = leer<T>(clave);
    return restaurado ? ({ ...inicial, ...restaurado } as T) : inicial;
  });

  // Persiste en cada cambio. Sin cleanup: al desmontar NO se borra, asi la navegacion interna
  // del portal conserva el borrador (se restaura al volver).
  useEffect(() => {
    const sobre: Sobre<T> = { t: Date.now(), v: valor };
    try { sessionStorage.setItem(clave, JSON.stringify(sobre)); } catch { /* noop */ }
  }, [clave, valor]);

  const limpiar = useCallback(() => {
    try { sessionStorage.removeItem(clave); } catch { /* noop */ }
  }, [clave]);

  return { valor, setValor, limpiar };
}

/**
 * Barrido de TODOS los borradores del ambiente actual. Pensado para el logout (evitar que en
 * un dispositivo compartido el proximo operador vea un borrador ajeno). Todavia SIN cablear:
 * se conecta en el mini-bloque de logout. Exportada aca por cohesion del hook.
 */
export function limpiarBorradores(): void {
  try {
    const prefijo = `vd:${AMBIENTE}:draft:`;
    for (const k of Object.keys(sessionStorage)) {
      if (k.startsWith(prefijo)) sessionStorage.removeItem(k);
    }
  } catch { /* noop */ }
}
