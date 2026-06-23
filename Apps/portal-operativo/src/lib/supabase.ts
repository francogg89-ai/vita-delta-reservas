import { createClient } from '@supabase/supabase-js';

// Supabase JS se usa SOLO para la capa de auth/sesion (D-FE-10):
// login/logout/refresh/persistencia. NO se usa para hablar con portal-api
// (eso lo hace callPortal con fetch).

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    'Faltan variables de entorno. Defini VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en tu .env (copialas de .env.example).',
  );
}

export const supabase = createClient(url, anonKey, {
  auth: {
    persistSession: true, // la sesion sobrevive al refresh del navegador
    autoRefreshToken: true, // renueva el access_token solo
    detectSessionInUrl: false, // login email+password, sin redirect OAuth
  },
});
