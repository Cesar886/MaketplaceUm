import { NextRequest, NextResponse } from 'next/server';
import { createHmac } from 'node:crypto';

// El prefijo __Secure- hace que navegadores compatibles rechacen la cookie si
// alguna regresión intentara emitirla sin HTTPS/Secure.
export const ADMIN_COOKIE_NAME = '__Secure-mercadito_admin_session';
export const ADMIN_PATH = '/revision-8f4d9c2a';

const backend = (process.env.API_URL ?? 'http://127.0.0.1:3000').replace(/\/$/, '');
const MAX_ADMIN_JSON_BYTES = 16 * 1024;

export function json(payload: unknown, status = 200) {
  const response = NextResponse.json(payload, { status });
  response.headers.set('Cache-Control', 'private, no-store');
  response.headers.set('X-Content-Type-Options', 'nosniff');
  return response;
}

export function adminPanelOrigin() {
  const configured = process.env.ADMIN_PANEL_ORIGIN
    ?? process.env.NEXT_PUBLIC_SITE_URL;
  if (!configured) return null;
  try {
    return new URL(configured).origin;
  } catch {
    return null;
  }
}

export function mutationIsSameOrigin(request: NextRequest) {
  const origin = request.headers.get('origin');
  const fetchSite = request.headers.get('sec-fetch-site');
  return !!origin
    && origin === adminPanelOrigin()
    && (!fetchSite || fetchSite === 'same-origin')
    && request.headers.get('x-revision-csrf') === '1'
    && request.headers.get('content-type')?.toLowerCase().startsWith('application/json');
}

export async function readAdminJson<T>(request: NextRequest): Promise<T> {
  const declaredLength = Number(request.headers.get('content-length') || '0');
  if (Number.isFinite(declaredLength) && declaredLength > MAX_ADMIN_JSON_BYTES) {
    throw new Error('PAYLOAD_TOO_LARGE');
  }
  if (!request.body) throw new Error('INVALID_JSON');

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_ADMIN_JSON_BYTES) {
        await reader.cancel();
        throw new Error('PAYLOAD_TOO_LARGE');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(body)) as T;
  } catch {
    throw new Error('INVALID_JSON');
  }
}

function normalizedClientIp(request: NextRequest) {
  // Apache debe sobrescribir X-Real-IP con REMOTE_ADDR. No se usa
  // X-Forwarded-For porque el cliente puede anteponer valores arbitrarios.
  const value = String(request.headers.get('x-real-ip') || '').trim();
  return /^[0-9a-f:.]{2,64}$/i.test(value) ? value : '127.0.0.1';
}

export function signedClientHeaders(request: NextRequest) {
  const sharedSecret = String(process.env.ADMIN_BFF_SHARED_SECRET || '');
  if (sharedSecret.length < 32) {
    throw new Error('ADMIN_BFF_SHARED_SECRET no está configurado.');
  }
  const ip = normalizedClientIp(request);
  const timestamp = String(Math.floor(Date.now() / 1000));
  return {
    'X-Admin-Client-IP': ip,
    'X-Admin-Client-Time': timestamp,
    'X-Admin-Client-Signature': createHmac('sha256', sharedSecret)
      .update(`${timestamp}.${ip}`)
      .digest('hex'),
  };
}

export function adminToken(request: NextRequest) {
  const token = request.cookies.get(ADMIN_COOKIE_NAME)?.value;
  if (!token || token.length > 8192 || /[\u0000-\u001f\u007f]/.test(token)) {
    return null;
  }
  return token;
}

export function backendUrl(pathname: string) {
  if (!pathname.startsWith('/api/admin/')) {
    throw new Error('Ruta administrativa inválida.');
  }
  return backend + pathname;
}

export function backendHeaders(token?: string | null, jsonBody = false) {
  const origin = adminPanelOrigin();
  if (!origin) {
    throw new Error('ADMIN_PANEL_ORIGIN no está configurado.');
  }
  const headers = new Headers({
    Accept: 'application/json',
    Origin: origin,
  });
  if (jsonBody) headers.set('Content-Type', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  return headers;
}

export async function backendPayload(response: Response): Promise<Record<string, unknown>> {
  try {
    const payload = await response.json() as unknown;
    return payload && typeof payload === 'object' && !Array.isArray(payload)
      ? payload as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

export function backendError(payload: Record<string, unknown>, fallback: string) {
  return typeof payload.error === 'string' && payload.error.trim()
    ? payload.error
    : fallback;
}

function cookieMaxAge(expiresIn: unknown) {
  const seconds = typeof expiresIn === 'number'
    ? expiresIn
    : typeof expiresIn === 'string' && /^\d+$/.test(expiresIn)
      ? Number(expiresIn)
      : Number.NaN;
  return Number.isSafeInteger(seconds) && seconds > 0
    ? seconds
    : undefined;
}

export function setAdminCookie(
  response: NextResponse,
  token: string,
  expiresIn: unknown,
) {
  response.cookies.set({
    name: ADMIN_COOKIE_NAME,
    value: token,
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    path: ADMIN_PATH,
    maxAge: cookieMaxAge(expiresIn),
  });
}

export function clearAdminCookie(response: NextResponse) {
  response.cookies.set({
    name: ADMIN_COOKIE_NAME,
    value: '',
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    path: ADMIN_PATH,
    expires: new Date(0),
    maxAge: 0,
  });
}
