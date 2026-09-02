import { NextRequest, NextResponse } from 'next/server';

const backend = (process.env.API_URL ?? 'http://127.0.0.1:3000').replace(/\/$/, '');

function authHeaders() {
  const key = process.env.REVISION_API_KEY;
  if (!key) throw new Error('REVISION_API_KEY no está configurada.');
  return { 'content-type': 'application/json', 'x-revision-api-key': key };
}

export async function GET(request: NextRequest) {
  const documentPath = request.nextUrl.searchParams.get('document');
  if (documentPath) {
    if (!/^\/uploads\/[a-zA-Z0-9._-]+$/.test(documentPath)) {
      return NextResponse.json({ error: 'Documento inválido.' }, { status: 400 });
    }
    try {
      const response = await fetch(backend + documentPath, {
        cache: 'no-store',
      });
      if (!response.ok || !response.body) {
        return NextResponse.json(
          { error: 'Documento no encontrado.' },
          { status: response.status },
        );
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
      return NextResponse.json(
        { error: 'No se pudo cargar el documento.' },
        { status: 502 },
      );
    }
  }

  const view = request.nextUrl.searchParams.get('view') ?? 'pending';
  if (!['pending', 'history'].includes(view)) {
    return NextResponse.json({ error: 'Vista inválida.' }, { status: 400 });
  }

  try {
    const endpoint = view === 'history'
      ? '/api/revision/historial'
      : '/api/revision/verificaciones?status=pending';
    const response = await fetch(backend + endpoint, {
      headers: authHeaders(),
      cache: 'no-store',
    });
    const payload = await response.json() as {
      requests?: Array<{
        business?: { logoUrl?: string | null };
        documents?: Array<{ url: string }>;
      }>;
    };

    if (response.ok && view === 'pending') {
      for (const item of payload.requests ?? []) {
        if (item.business?.logoUrl
            && /^\/uploads\/[a-zA-Z0-9._-]+$/.test(item.business.logoUrl)) {
          item.business.logoUrl = request.nextUrl.pathname
            + '?document=' + encodeURIComponent(item.business.logoUrl);
        }
        for (const document of item.documents ?? []) {
          document.url = request.nextUrl.pathname
            + '?document=' + encodeURIComponent(document.url);
        }
      }
    }
    return NextResponse.json(payload, { status: response.status });
  } catch {
    return NextResponse.json(
      { error: 'No se pudo conectar al backend de revisión.' },
      { status: 502 },
    );
  }
}

export async function POST(request: NextRequest) {
  const id = request.nextUrl.searchParams.get('id');
  const action = request.nextUrl.searchParams.get('action');
  if (!id || !['approve', 'reject', 'revoke'].includes(action ?? '')) {
    return NextResponse.json({ error: 'Acción inválida.' }, { status: 400 });
  }

  try {
    const body = action === 'approve' ? undefined : await request.json();
    const response = await fetch(
      `${backend}/api/revision/verificaciones/${encodeURIComponent(id)}/${action}`,
      {
        method: 'POST',
        headers: authHeaders(),
        body: body ? JSON.stringify(body) : undefined,
        cache: 'no-store',
      },
    );
    return NextResponse.json(await response.json(), { status: response.status });
  } catch {
    return NextResponse.json(
      { error: 'No se pudo conectar al backend de revisión.' },
      { status: 502 },
    );
  }
}
