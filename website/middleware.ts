import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// Next 15.5 exige que el ID de una Server Action sea exactamente 42 caracteres
// hex (SERVER_REFERENCE_ID_LENGTH). Cualquier otra cosa hace que el runtime
// lance "The Server Reference ID did not match the expected format" y llene
// pm2-error.log. El tráfico que lo dispara es externo: bots que fuzzean la
// cabecera ("x") y clientes/escáneres con IDs de 40 hex del formato viejo de
// Next 14. Este sitio no tiene ninguna Server Action, así que se corta antes
// de que React intente resolver la referencia. Si algún día se añade un
// 'use server', los IDs reales siguen pasando porque cumplen el formato.
const SERVER_REFERENCE_ID = /^[0-9a-f]{42}$/;
const REVISION_PATH = '/revision-8f4d9c2a';

async function digest(value: string) {
  return new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)),
  );
}

async function secureEqual(left: string, right: string) {
  const [a, b] = await Promise.all([digest(left), digest(right)]);
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

function basicCredentials(header: string | null) {
  if (!header || header.length > 4096 || !header.startsWith('Basic ')) return null;
  try {
    const bytes = Uint8Array.from(atob(header.slice(6)), char => char.charCodeAt(0));
    const decoded = new TextDecoder().decode(bytes);
    const separator = decoded.indexOf(':');
    if (separator < 1) return null;
    return {
      username: decoded.slice(0, separator),
      password: decoded.slice(separator + 1),
    };
  } catch {
    return null;
  }
}

function secureRevisionResponse(response: NextResponse) {
  response.headers.set('Cache-Control', 'private, no-store');
  response.headers.set('Content-Security-Policy', "frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
  response.headers.set('Referrer-Policy', 'no-referrer');
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('X-Frame-Options', 'DENY');
  response.headers.set('X-Robots-Tag', 'noindex, nofollow, noarchive');
  response.headers.set('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
  response.headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()');
  return response;
}

export async function middleware(request: NextRequest) {
  const actionId = request.headers.get('next-action');
  if (actionId !== null && !SERVER_REFERENCE_ID.test(actionId)) {
    return new NextResponse(null, { status: 400 });
  }

  if (!request.nextUrl.pathname.startsWith(REVISION_PATH)) {
    return NextResponse.next();
  }

  const expectedUsername = process.env.REVISION_ADMIN_USER;
  const expectedPassword = process.env.REVISION_ADMIN_PASSWORD;
  const expectedProxySecret = process.env.REVISION_PROXY_SECRET;
  const proxyConfigured = !!expectedUsername
    && !!expectedProxySecret
    && expectedProxySecret.length >= 32;
  const basicConfigured = !!expectedUsername
    && !expectedUsername.includes(':')
    && !!expectedPassword
    && expectedPassword.length >= 12;
  if (!proxyConfigured && !basicConfigured) {
    return secureRevisionResponse(new NextResponse(
      'El acceso administrativo no está configurado.',
      { status: 503 },
    ));
  }

  let authenticatedUser: string | null = null;
  if (proxyConfigured) {
    const proxyUser = request.headers.get('x-revision-authenticated-user');
    const proxySecret = request.headers.get('x-revision-proxy-secret');
    if (
      proxyUser
      && proxySecret
      && await secureEqual(proxyUser, expectedUsername)
      && await secureEqual(proxySecret, expectedProxySecret)
    ) {
      authenticatedUser = proxyUser;
    }
  }
  if (!authenticatedUser && basicConfigured) {
    const supplied = basicCredentials(request.headers.get('authorization'));
    if (
      supplied
      && await secureEqual(supplied.username, expectedUsername)
      && await secureEqual(supplied.password, expectedPassword)
    ) {
      authenticatedUser = supplied.username;
    }
  }
  if (!authenticatedUser) {
    const response = new NextResponse('Autenticación requerida.', { status: 401 });
    response.headers.set('WWW-Authenticate', 'Basic realm="Revision privada", charset="UTF-8"');
    return secureRevisionResponse(response);
  }

  // Las credenciales terminan en el middleware. El resto de la aplicación
  // recibe solo el nombre administrativo para la bitácora.
  const requestHeaders = new Headers(request.headers);
  requestHeaders.delete('authorization');
  requestHeaders.delete('x-revision-authenticated-user');
  requestHeaders.delete('x-revision-proxy-secret');
  requestHeaders.set('x-revision-admin', authenticatedUser);
  return secureRevisionResponse(NextResponse.next({
    request: { headers: requestHeaders },
  }));
}

export const config = {
  matcher: '/((?!_next/static|_next/image).*)',
};
