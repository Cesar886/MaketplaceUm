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

export function middleware(request: NextRequest) {
  const actionId = request.headers.get('next-action');

  if (actionId !== null && !SERVER_REFERENCE_ID.test(actionId)) {
    return new NextResponse(null, { status: 400 });
  }

  return NextResponse.next();
}

export const config = {
  matcher: '/((?!_next/static|_next/image).*)',
};
