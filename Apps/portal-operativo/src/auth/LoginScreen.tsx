import { useState, type FormEvent } from 'react';
import { useAuth } from './useAuth';

export function LoginScreen() {
  const { login, errorMessage: ctxError } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);

  // Error visible: el del ultimo intento, o el del contexto (ej. "sin acceso al portal").
  const error = localError ?? ctxError;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setLocalError(null);
    setSubmitting(true);
    const res = await login(email, password);
    setSubmitting(false);
    if (!res.ok) setLocalError(res.message ?? 'No se pudo iniciar sesion.');
    // Si ok: AuthProvider cambia el estado y desmonta esta pantalla.
  }

  return (
    <div className="grid min-h-full place-items-center bg-mist px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <h1 className="text-2xl font-semibold tracking-tight text-ink">
            Vita <span className="text-river">Delta</span>
          </h1>
          <p className="mt-1 text-sm text-reed">Portal operativo</p>
        </div>

        <form
          onSubmit={onSubmit}
          className="space-y-4 rounded-2xl border border-sand bg-white p-6 shadow-sm"
        >
          <div className="space-y-1.5">
            <label htmlFor="email" className="block text-sm font-medium text-ink">
              Email
            </label>
            <input
              id="email"
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => {
                setEmail(e.target.value);
                setLocalError(null);
              }}
              placeholder="vos@vitadelta.test"
              className="w-full rounded-lg border border-sand bg-white px-3 py-2 text-ink outline-none placeholder:text-reed/60 focus:border-river focus:ring-2 focus:ring-river/30"
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="password" className="block text-sm font-medium text-ink">
              Contrasena
            </label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => {
                setPassword(e.target.value);
                setLocalError(null);
              }}
              placeholder="********"
              className="w-full rounded-lg border border-sand bg-white px-3 py-2 text-ink outline-none placeholder:text-reed/60 focus:border-river focus:ring-2 focus:ring-river/30"
            />
          </div>

          {error && (
            <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-lg bg-river px-4 py-2.5 font-medium text-white transition hover:bg-river-dark focus:outline-none focus:ring-2 focus:ring-river/40 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {submitting ? 'Entrando...' : 'Entrar'}
          </button>
        </form>

        <p className="mt-6 text-center text-xs text-reed">
          Acceso solo para el equipo de Vita Delta.
        </p>
      </div>
    </div>
  );
}
