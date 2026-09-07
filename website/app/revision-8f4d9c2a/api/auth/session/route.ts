import { NextRequest } from 'next/server';

import {
  adminToken,
  backendError,
  backendHeaders,
  backendPayload,
  backendUrl,
  clearAdminCookie,
  json,
} from '../../_shared';

export async function GET(request: NextRequest) {
  const token = adminToken(request);
  if (!token) {
    return json({ error: 'Sesión administrativa requerida.' }, 401);
  }

  try {
    const response = await fetch(backendUrl('/api/admin/auth/session'), {
      headers: backendHeaders(token),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    const payload = await backendPayload(response);
    if (!response.ok) {
      const result = json({
        error: backendError(payload, 'La sesión administrativa ya no es válida.'),
      }, response.status);
      if (response.status === 401 || response.status === 403) clearAdminCookie(result);
      return result;
    }

    if (!payload.admin || typeof payload.admin !== 'object' || Array.isArray(payload.admin)) {
      return json({ error: 'El backend devolvió una sesión inválida.' }, 502);
    }
    return json({ admin: payload.admin });
  } catch {
    return json({ error: 'No se pudo comprobar la sesión administrativa.' }, 502);
  }
}
