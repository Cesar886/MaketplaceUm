import { NextRequest, NextResponse } from 'next/server';

const backend = (process.env.API_URL ?? 'http://127.0.0.1:3000').replace(/\/$/, '');

function json(payload: unknown, status = 200) {
  const response = NextResponse.json(payload, { status });
  response.headers.set('Cache-Control', 'private, no-store');
  response.headers.set('X-Content-Type-Options', 'nosniff');
  return response;
}

function trustedOrigin(request: NextRequest) {
  const configured = process.env.NEXT_PUBLIC_SITE_URL;
  if (configured) {
    try {
      return new URL(configured).origin;
    } catch {
      return null;
    }
  }
  return process.env.NODE_ENV === 'production' ? null : request.nextUrl.origin;
}

function mutationIsSameOrigin(request: NextRequest) {
  const origin = request.headers.get('origin');
  const fetchSite = request.headers.get('sec-fetch-site');
  return !!origin
    && origin === trustedOrigin(request)
    && (!fetchSite || fetchSite === 'same-origin')
    && request.headers.get('x-revision-csrf') === '1'
    && request.headers.get('content-type')?.toLowerCase().startsWith('application/json');
}

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

function authHeaders(actor?: string | null) {
  const key = process.env.REVISION_API_KEY;
  if (!key) throw new Error('REVISION_API_KEY no está configurada.');
  return {
    'content-type': 'application/json',
    'x-revision-api-key': key,
    ...(actor ? { 'x-revision-actor': actor } : {}),
  };
}

export async function GET(request: NextRequest) {
  const documentPath = request.nextUrl.searchParams.get('document');
  if (documentPath) {
    if (!/^\/uploads\/[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(documentPath)) {
      return json({ error: 'Documento inválido.' }, 400);
    }
    try {
      const response = await fetch(
        backend + '/api/revision/documento?path=' + encodeURIComponent(documentPath),
        {
          headers: authHeaders(),
          cache: 'no-store',
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!response.ok || !response.body) {
        return json({ error: 'Documento no encontrado.' }, response.status);
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
      endpoint = '/api/revision/historial';
    } else if (view === 'accounts') {
      const accountId = request.nextUrl.searchParams.get('accountId');
      if (accountId) {
        endpoint = '/api/revision/cuentas/' + encodeURIComponent(accountId);
      } else {
        const query = new URLSearchParams();
        for (const key of ['page', 'limit', 'type', 'verified', 'q']) {
          const value = request.nextUrl.searchParams.get(key);
          if (value !== null) query.set(key, value);
        }
        endpoint = '/api/revision/cuentas?' + query.toString();
      }
    } else {
      endpoint = '/api/revision/verificaciones?status=pending';
    }

    const response = await fetch(backend + endpoint, {
      headers: authHeaders(),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    const payload = await response.json() as {
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
    return json(payload, response.status);
  } catch {
    return json({ error: 'No se pudo conectar al backend de revisión.' }, 502);
  }
}

export async function POST(request: NextRequest) {
  if (!mutationIsSameOrigin(request)) {
    return json({ error: 'Solicitud administrativa no autorizada.' }, 403);
  }

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
      ? `${backend}/api/revision/cuentas/${encodeURIComponent(id)}/verificacion`
      : `${backend}/api/revision/verificaciones/${encodeURIComponent(id)}/${action}`;
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: authHeaders(request.headers.get('x-revision-admin')),
      body: JSON.stringify(body),
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
    });
    return json(await response.json(), response.status);
  } catch {
    return json({ error: 'No se pudo conectar al backend de revisión.' }, 502);
  }
}
