import {
  createContext,
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { supabase } from '../lib/supabase';
import { callPortal, PortalApiError } from '../lib/callPortal';
import type { SesionContexto } from '../lib/types';

export type AuthStatus = 'cargando' | 'anonimo' | 'autenticado' | 'error';

export interface LoginResult {
  ok: boolean;
  message?: string;
}

export interface AuthState {
  status: AuthStatus;
  contexto: SesionContexto | null;
  errorMessage: string | null;
  login: (email: string, password: string) => Promise<LoginResult>;
  logout: () => Promise<void>;
  reintentarContexto: () => Promise<void>;
}

export const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>('cargando');
  const [contexto, setContexto] = useState<SesionContexto | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  // Evita cargar el contexto dos veces (getSession inicial + evento de auth).
  const cargandoContexto = useRef(false);

  /**
   * Primera llamada tras tener sesion: sesion.contexto (A02).
   * Si devuelve no_autorizado, el usuario esta autenticado en Supabase pero no tiene
   * acceso al portal (sin fila en portal_usuarios / activo=false / sesion invalida):
   * se cierra la sesion y se vuelve a login con aviso (contrato §4).
   */
  const cargarContexto = useCallback(async () => {
    if (cargandoContexto.current) return;
    cargandoContexto.current = true;
    setStatus('cargando');
    setErrorMessage(null);
    try {
      const ctx = await callPortal<SesionContexto>('sesion.contexto');
      setContexto(ctx);
      setStatus('autenticado');
    } catch (e) {
      if (e instanceof PortalApiError && e.code === 'no_autorizado') {
        await supabase.auth.signOut();
        setContexto(null);
        setStatus('anonimo');
        setErrorMessage('No tenes acceso al portal. Contacta al administrador.');
      } else {
        const msg =
          e instanceof PortalApiError
            ? e.message
            : 'No se pudo cargar tu sesion. Proba de nuevo.';
        setErrorMessage(msg);
        setStatus('error');
      }
    } finally {
      cargandoContexto.current = false;
    }
  }, []);

  // Sesion inicial + suscripcion a cambios de auth.
  useEffect(() => {
    let activo = true;

    void supabase.auth.getSession().then(({ data }) => {
      if (!activo) return;
      if (data.session) {
        void cargarContexto();
      } else {
        setStatus('anonimo');
      }
    });

    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (!activo) return;
      if (event === 'SIGNED_OUT' || !session) {
        setContexto(null);
        setStatus('anonimo');
        return;
      }
      if (event === 'SIGNED_IN') {
        void cargarContexto();
      }
      // TOKEN_REFRESHED / USER_UPDATED / INITIAL_SESSION con sesion viva:
      // no recargamos el contexto.
    });

    return () => {
      activo = false;
      sub.subscription.unsubscribe();
    };
  }, [cargarContexto]);

  const login = useCallback(
    async (email: string, password: string): Promise<LoginResult> => {
      setErrorMessage(null);
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (error) {
        return { ok: false, message: 'Email o contrasena incorrectos.' };
      }
      // Evita el flash de login mientras llega el evento SIGNED_IN que dispara cargarContexto.
      setStatus('cargando');
      return { ok: true };
    },
    [],
  );

  const logout = useCallback(async () => {
    await supabase.auth.signOut();
    setContexto(null);
    setErrorMessage(null);
    setStatus('anonimo');
  }, []);

  const reintentarContexto = useCallback(async () => {
    await cargarContexto();
  }, [cargarContexto]);

  const value: AuthState = {
    status,
    contexto,
    errorMessage,
    login,
    logout,
    reintentarContexto,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
