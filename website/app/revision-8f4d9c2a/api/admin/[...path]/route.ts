import { NextRequest } from 'next/server';

import {
  adminToken,
  backendError,
  backendHeaders,
  backendPayload,
  backendUrl,
  clearAdminCookie,
  json,
  mutationIsSameOrigin,
  readAdminJson,
} from '../../_shared';

type Context = { params: Promise<{ path: string[] }> };

const ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,179}$/;
const CONFIG_KEY = /^(negocio_verificado|negocio_sin_verificar|um_verificado|um_sin_verificar|externo)$/;

function allowedPath(method: string, segments: string[]) {
  const joined = segments.join('/');
  if (method === 'GET') {
    if (['dashboard', 'users', 'publications', 'config', 'audit-log', 'reports'].includes(joined)) return true;
    return segments.length === 2 && segments[0] === 'users' && ID.test(segments[1]);
  }
  if (method === 'PUT' || method === 'DELETE') {
    if (segments.length === 2 && segments[0] === 'config' && CONFIG_KEY.test(segments[1])) return true;
  }
  if (method === 'PATCH') {
    if (segments.length === 2 && segments[0] === 'reports' && ID.test(segments[1])) return true;
    if (segments.length === 3 && segments[0] === 'users'
        && ID.test(segments[1]) && segments[2] === 'status') return true;
    if (segments.length === 4 && segments[0] === 'publications'
        && ['product', 'wanted'].includes(segments[1]) && ID.test(segments[2])
        && segments[3] === 'spam') return true;
  }
  if (method === 'POST') {
    if (joined === 'users/bulk/status') return true;
    return segments.length === 3 && segments[0] === 'users'
      && ID.test(segments[1]) && segments[2] === 'reset-limits';
  }
  if (method === 'DELETE') {
    return segments.length === 3 && segments[0] === 'publications'
      && ['product', 'wanted'].includes(segments[1]) && ID.test(segments[2]);
  }
  return false;
}

async function proxy(request: NextRequest, context: Context) {
  const segments = (await context.params).path;
  if (!Array.isArray(segments) || !allowedPath(request.method, segments)) {
    return json({ error: 'Ruta administrativa no permitida.' }, 404);
  }
  if (request.method !== 'GET' && !mutationIsSameOrigin(request)) {
    return json({ error: 'Solicitud administrativa no autorizada.' }, 403);
  }
  const token = adminToken(request);
  if (!token) return json({ error: 'Sesión administrativa requerida.' }, 401);

  let body: unknown;
  if (request.method !== 'GET') {
    try {
      body = await readAdminJson(request);
    } catch (error) {
      if (error instanceof Error && error.message === 'PAYLOAD_TOO_LARGE') {
        return json({ error: 'La solicitud supera el límite permitido.' }, 413);
      }
      return json({ error: 'El cuerpo JSON es obligatorio.' }, 400);
    }
  }

  const endpoint = `/api/admin/${segments.map(encodeURIComponent).join('/')}${request.nextUrl.search}`;
  try {
    const response = await fetch(backendUrl(endpoint), {
      method: request.method,
      headers: backendHeaders(token, request.method !== 'GET'),
      body: request.method === 'GET' ? undefined : JSON.stringify(body),
      cache: 'no-store',
      signal: AbortSignal.timeout(12_000),
    });
    const payload = await backendPayload(response);
    const result = response.ok
      ? json(payload, response.status)
      : json({ ...payload, error: backendError(payload, 'No se pudo completar la operación.') }, response.status);
    if (response.status === 401 || response.status === 403) clearAdminCookie(result);
    return result;
  } catch {
    return json({ error: 'No se pudo conectar al servicio administrativo.' }, 502);
  }
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
