import { NextRequest } from 'next/server';

import {
  backendError,
  backendHeaders,
  backendPayload,
  backendUrl,
  json,
  mutationIsSameOrigin,
  setAdminCookie,
} from '../../_shared';

type LoginBody = {
  username?: unknown;
  password?: unknown;
  totp?: unknown;
};

export async function POST(request: NextRequest) {
  if (!mutationIsSameOrigin(request)) {
    return json({ error: 'Solicitud administrativa no autorizada.' }, 403);
  }

  let body: LoginBody;
  try {
    body = await request.json() as LoginBody;
  } catch {
    return json({ error: 'El cuerpo JSON es obligatorio.' }, 400);
  }

  const username = typeof body.username === 'string' ? body.username.trim() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const totp = typeof body.totp === 'string' ? body.totp.trim() : '';
  if (
    !username
    || username.length > 100
    || !password
    || password.length > 1024
    || !/^\d{6}$/.test(totp)
  ) {
    return json({ error: 'Usuario, contraseña y código de 6 dígitos son obligatorios.' }, 400);
  }

  try {
    const response = await fetch(backendUrl('/api/admin/auth/login'), {
      method: 'POST',
      headers: backendHeaders(null, true),
      body: JSON.stringify({ username, password, totp }),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    const payload = await backendPayload(response);
    if (!response.ok) {
      return json({
        error: backendError(payload, 'No se pudo iniciar sesión.'),
      }, response.status);
    }

    const token = typeof payload.token === 'string' ? payload.token : '';
    const admin = payload.admin;
    if (
      !token
      || token.length > 8192
      || !admin
      || typeof admin !== 'object'
      || Array.isArray(admin)
    ) {
      return json({ error: 'El backend devolvió una sesión inválida.' }, 502);
    }

    // El JWT solo se conserva en la cookie httpOnly; nunca forma parte del JSON
    // que puede leer el código del navegador.
    const result = json({ admin, expiresIn: payload.expiresIn });
    setAdminCookie(result, token, payload.expiresIn);
    return result;
  } catch {
    return json({ error: 'No se pudo conectar al servicio administrativo.' }, 502);
  }
}
