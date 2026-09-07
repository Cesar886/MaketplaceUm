'use client';

import { FormEvent, ReactNode, useEffect, useState } from 'react';

import styles from './revision.module.css';

const authBase = '/revision-8f4d9c2a/api/auth';

type Admin = {
  id: string | number;
  username: string;
};

type AuthPayload = {
  admin?: Admin;
  error?: string;
};

export default function AdminAuthGate({ children }: { children: ReactNode }) {
  const [admin, setAdmin] = useState<Admin | null>(null);
  const [checking, setChecking] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();
    fetch(`${authBase}/session`, {
      cache: 'no-store',
      credentials: 'same-origin',
      signal: controller.signal,
    })
      .then(async response => {
        const payload = await response.json() as AuthPayload;
        if (response.ok && payload.admin) setAdmin(payload.admin);
      })
      .catch(fetchError => {
        if (!(fetchError instanceof DOMException && fetchError.name === 'AbortError')) {
          setError('No se pudo comprobar la sesión. Intenta nuevamente.');
        }
      })
      .finally(() => setChecking(false));
    return () => controller.abort();
  }, []);

  useEffect(() => {
    const expireSession = () => {
      setAdmin(null);
      setPassword('');
      setTotp('');
      setError('Tu sesión expiró. Ingresa de nuevo para continuar.');
    };
    window.addEventListener('mercadito:admin-session-expired', expireSession);
    return () => window.removeEventListener(
      'mercadito:admin-session-expired',
      expireSession,
    );
  }, []);

  async function login(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    if (!username.trim() || !password || !/^\d{6}$/.test(totp)) {
      setError('Completa el usuario, la contraseña y el código de 6 dígitos.');
      return;
    }

    setSubmitting(true);
    try {
      const response = await fetch(`${authBase}/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Revision-CSRF': '1',
        },
        credentials: 'same-origin',
        body: JSON.stringify({
          username: username.trim(),
          password,
          totp,
        }),
      });
      const payload = await response.json() as AuthPayload;
      if (!response.ok || !payload.admin) {
        throw new Error(payload.error || 'No se pudo iniciar sesión.');
      }
      setAdmin(payload.admin);
      setPassword('');
      setTotp('');
    } catch (loginError) {
      setError(loginError instanceof Error
        ? loginError.message
        : 'No se pudo iniciar sesión.');
    } finally {
      setSubmitting(false);
    }
  }

  async function logout() {
    setSubmitting(true);
    setError('');
    try {
      await fetch(`${authBase}/logout`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Revision-CSRF': '1',
        },
        credentials: 'same-origin',
        body: '{}',
      });
    } finally {
      setAdmin(null);
      setPassword('');
      setTotp('');
      setSubmitting(false);
    }
  }

  if (checking) {
    return <p className={styles.state}>Comprobando sesión administrativa…</p>;
  }

  if (!admin) {
    return (
      <section className={styles.loginCard} aria-labelledby="admin-login-title">
        <div className={styles.loginHeading}>
          <p className={styles.eyebrow}>Acceso administrativo</p>
          <h2 id="admin-login-title">Inicia sesión para continuar</h2>
          <p>Necesitas tu contraseña y el código vigente de tu aplicación 2FA.</p>
        </div>
        <form className={styles.loginForm} onSubmit={login}>
          <label>
            <span>Usuario</span>
            <input
              autoCapitalize="none"
              autoComplete="username"
              autoCorrect="off"
              disabled={submitting}
              maxLength={100}
              onChange={event => setUsername(event.target.value)}
              required
              type="text"
              value={username}
            />
          </label>
          <label>
            <span>Contraseña</span>
            <input
              autoComplete="current-password"
              disabled={submitting}
              maxLength={1024}
              onChange={event => setPassword(event.target.value)}
              required
              type="password"
              value={password}
            />
          </label>
          <label>
            <span>Código 2FA</span>
            <input
              aria-describedby="totp-help"
              autoComplete="one-time-code"
              disabled={submitting}
              inputMode="numeric"
              maxLength={6}
              onChange={event => setTotp(event.target.value.replace(/\D/g, '').slice(0, 6))}
              pattern="[0-9]{6}"
              required
              type="text"
              value={totp}
            />
            <small id="totp-help">Ingresa los 6 dígitos de tu app autenticadora.</small>
          </label>
          {error && <p className={styles.loginError} role="alert">{error}</p>}
          <button disabled={submitting} type="submit">
            {submitting ? 'Verificando…' : 'Entrar al panel'}
          </button>
        </form>
      </section>
    );
  }

  return (
    <>
      <div className={styles.adminSessionBar}>
        <div>
          <span>Sesión protegida</span>
          <strong>{admin.username}</strong>
        </div>
        <button disabled={submitting} onClick={logout} type="button">
          {submitting ? 'Cerrando…' : 'Cerrar sesión'}
        </button>
      </div>
      {children}
    </>
  );
}
