/**
 * Links de las tiendas.
 *
 * PENDIENTE: ambas son placeholders hasta publicar la app. Mientras valgan
 * null, los componentes muestran el mensaje de "muy pronto" en vez de un
 * botón que lleva a una página inexistente — un enlace roto en el CTA
 * principal es peor que no tener botón.
 */
export const APP_STORE_URL: string | null = null;
export const PLAY_STORE_URL: string | null = null;

export type Plataforma = 'ios' | 'android' | 'escritorio';

/**
 * Detecta la plataforma desde el user-agent. Se ejecuta en el cliente: hacerlo
 * en el servidor con `headers()` volvería la ruta dinámica y anularía el ISR,
 * y lo que de verdad importa para WhatsApp (las meta tags) ya se resuelve en
 * el servidor.
 */
export function detectarPlataforma(userAgent: string): Plataforma {
  const ua = userAgent.toLowerCase();
  // iPadOS 13+ se anuncia como Macintosh; el touch lo delata.
  const esIpadModerno =
    ua.includes('macintosh') &&
    typeof navigator !== 'undefined' &&
    navigator.maxTouchPoints > 1;

  if (/iphone|ipad|ipod/.test(ua) || esIpadModerno) return 'ios';
  if (ua.includes('android')) return 'android';
  return 'escritorio';
}

export function urlTienda(plataforma: Plataforma): string | null {
  if (plataforma === 'ios') return APP_STORE_URL;
  if (plataforma === 'android') return PLAY_STORE_URL;
  return null;
}
