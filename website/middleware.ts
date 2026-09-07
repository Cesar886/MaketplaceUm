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

function secureRevisionResponse(response: NextResponse) {
  response.headers.set('Cache-Control', 'private, no-store');
  response.headers.set('Content-Security-Policy', [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https://tile.openstreetmap.org",
    "font-src 'self'",
    "connect-src 'self'",
    "object-src 'none'",
    "frame-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join('; '));
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

  // La autenticación real vive en `/api/admin/*`. El middleware conserva
  // únicamente los encabezados defensivos de la URL histórica; los Route
  // Handlers validan la cookie httpOnly contra el backend en cada request.
  return secureRevisionResponse(NextResponse.next());
}

export const config = {
  matcher: '/((?!_next/static|_next/image).*)',
};
