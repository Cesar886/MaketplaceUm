import { NextRequest, NextResponse } from 'next/server';

import {
  adminToken,
  backendError,
  backendHeaders,
  backendPayload,
  backendUrl,
  clearAdminCookie,
  json,
  mutationIsSameOrigin,
} from './_shared';

type ReviewRequestPayload = {
  business?: { logoUrl?: string | null };
  account?: { logoUrl?: string | null; avatarUrl?: string | null };
  documents?: Array<{ url: string }>;
};

function proxyDocumentUrls(item: ReviewRequestPayload, pathname: string) {
  for (const key of ['logoUrl', 'avatarUrl'] as const) {
    const value = item.account?.[key];
    if (value && /^\/uploads\/[a-zA-Z0-9._-]+$/.test(value)) {
      item.account![key] = pathname + '?document=' + encodeURIComponent(value);
    }
  }
  if (item.business?.logoUrl
      && /^\/uploads\/[a-zA-Z0-9._-]+$/.test(item.business.logoUrl)) {
    item.business.logoUrl = pathname
      + '?document=' + encodeURIComponent(item.business.logoUrl);
  }
  for (const document of item.documents ?? []) {
    if (/^\/uploads\/[a-zA-Z0-9._-]+$/.test(document.url)) {
      document.url = pathname + '?document=' + encodeURIComponent(document.url);
    }
  }
}

export async function GET(request: NextRequest) {
  const token = adminToken(request);
  if (!token) return json({ error: 'Sesión administrativa requerida.' }, 401);

  const documentPath = request.nextUrl.searchParams.get('document');
  if (documentPath) {
    if (!/^\/uploads\/[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(documentPath)) {
      return json({ error: 'Documento inválido.' }, 400);
    }
    try {
      const response = await fetch(
        backendUrl('/api/admin/revision/documento?path=' + encodeURIComponent(documentPath)),
        {
          headers: backendHeaders(token),
          cache: 'no-store',
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!response.ok || !response.body) {
        const result = json({ error: 'Documento no encontrado.' }, response.status);
        if (response.status === 401 || response.status === 403) clearAdminCookie(result);
        return result;
      }
      return new NextResponse(response.body, {
        status: response.status,
        headers: {
          'content-type': response.headers.get('content-type')
            ?? 'application/octet-stream',
          'cache-control': 'private, no-store',
          'content-disposition': 'inline',
          'x-content-type-options': 'nosniff',
        },
      });
    } catch {
      return json({ error: 'No se pudo cargar el documento.' }, 502);
    }
  }

  const view = request.nextUrl.searchParams.get('view') ?? 'pending';
  if (!['pending', 'accounts', 'history'].includes(view)) {
    return json({ error: 'Vista inválida.' }, 400);
  }

  try {
    let endpoint: string;
    if (view === 'history') {
      endpoint = '/api/admin/revision/historial';
    } else if (view === 'accounts') {
      const accountId = request.nextUrl.searchParams.get('accountId');
      if (accountId) {
        endpoint = '/api/admin/revision/cuentas/' + encodeURIComponent(accountId);
      } else {
        const query = new URLSearchParams();
        for (const key of ['page', 'limit', 'type', 'verified', 'q']) {
          const value = request.nextUrl.searchParams.get(key);
          if (value !== null) query.set(key, value);
        }
        endpoint = '/api/admin/revision/cuentas?' + query.toString();
      }
    } else {
      endpoint = '/api/admin/revision/verificaciones?status=pending';
    }

    const response = await fetch(backendUrl(endpoint), {
      headers: backendHeaders(token),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    const payload = await backendPayload(response) as {
      requests?: ReviewRequestPayload[];
      entries?: Array<{ request?: ReviewRequestPayload | null }>;
    };

    const isAccountDetail = view === 'accounts'
      && request.nextUrl.searchParams.has('accountId');
    if (response.ok && (view !== 'accounts' || isAccountDetail)) {
      const items = view === 'pending'
        ? payload.requests ?? []
        : isAccountDetail
          ? [payload as ReviewRequestPayload]
          : (payload.entries ?? []).flatMap(entry =>
              entry.request ? [entry.request] : [],
            );
      for (const item of items) {
        proxyDocumentUrls(item, request.nextUrl.pathname);
      }
    }
    const result = json(payload, response.status);
    if (response.status === 401 || response.status === 403) clearAdminCookie(result);
    return result;
  } catch {
    return json({ error: 'No se pudo conectar al backend de revisión.' }, 502);
  }
}

export async function POST(request: NextRequest) {
  if (!mutationIsSameOrigin(request)) {
    return json({ error: 'Solicitud administrativa no autorizada.' }, 403);
  }

  const token = adminToken(request);
  if (!token) return json({ error: 'Sesión administrativa requerida.' }, 401);

  const id = request.nextUrl.searchParams.get('id');
  const action = request.nextUrl.searchParams.get('action');
  if (
    !id
    || !['approve', 'reject', 'revoke', 'restore', 'set-verification']
      .includes(action ?? '')
  ) {
    return json({ error: 'Acción inválida.' }, 400);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'El cuerpo JSON es obligatorio.' }, 400);
  }

  try {
    const endpoint = action === 'set-verification'
      ? `/api/admin/revision/cuentas/${encodeURIComponent(id)}/verificacion`
      : `/api/admin/revision/verificaciones/${encodeURIComponent(id)}/${action}`;
    const response = await fetch(backendUrl(endpoint), {
      method: 'POST',
      headers: backendHeaders(token, true),
      body: JSON.stringify(body),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    const payload = await backendPayload(response);
    const result = response.ok
      ? json(payload, response.status)
      : json({ error: backendError(payload, 'No se pudo guardar la decisión.') }, response.status);
    if (response.status === 401 || response.status === 403) clearAdminCookie(result);
    return result;
  } catch {
    return json({ error: 'No se pudo conectar al backend de revisión.' }, 502);
  }
}
