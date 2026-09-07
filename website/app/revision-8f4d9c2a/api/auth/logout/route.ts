import { NextRequest } from 'next/server';

import {
  adminToken,
  backendHeaders,
  backendUrl,
  clearAdminCookie,
  json,
  mutationIsSameOrigin,
} from '../../_shared';

export async function POST(request: NextRequest) {
  if (!mutationIsSameOrigin(request)) {
    return json({ error: 'Solicitud administrativa no autorizada.' }, 403);
  }

  const token = adminToken(request);
  if (token) {
    try {
      await fetch(backendUrl('/api/admin/auth/logout'), {
        method: 'POST',
        headers: backendHeaders(token, true),
        body: '{}',
        cache: 'no-store',
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      // La cookie local se elimina incluso si el logout remoto es opcional o
      // el backend no está disponible.
    }
  }

  const response = json({ loggedOut: true });
  clearAdminCookie(response);
  return response;
}
