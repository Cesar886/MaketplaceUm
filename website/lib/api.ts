import type { PublicacionPublica } from './tipos';

/**
 * URL del backend. Sin `NEXT_PUBLIC_` porque el fetch ocurre en el servidor
 * (Server Component): así la IP del backend no viaja al bundle del cliente.
 */
const API_URL = process.env.API_URL ?? 'http://157.245.247.45:3000';

/** URL pública del sitio, para canonical, OG y el QR. */
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ?? 'https://mercaditoum.site';

/**
 * Vuelve absoluta una ruta de imagen del backend. Las fotos se guardan como
 * '/uploads/x.webp' — relativas al backend, no al sitio, así que concatenar
 * sin más las serviría desde el dominio equivocado.
 */
export function urlFoto(ruta: string): string {
  if (/^https?:\/\//.test(ruta)) return ruta;
  return `${API_URL}${ruta.startsWith('/') ? '' : '/'}${ruta}`;
}

/**
 * Devuelve la publicación (producto o búsqueda), o null si no existe (404).
 *
 * El endpoint resuelve ambas contra el mismo id porque la app comparte una
 * sola forma de URL; qué llegó se distingue por el campo `tipo`.
 *
 * Solo el 404 devuelve null. Cualquier otro fallo (500, red caída, JSON
 * inválido) LANZA: si el backend está mal, la página debe reventar y dejar
 * que Next sirva el error, no fingir que la publicación no existe y emitir un
 * 404 que los buscadores tomarían como permanente.
 */
export async function obtenerPublicacion(
  id: string,
): Promise<PublicacionPublica | null> {
  const res = await fetch(
    `${API_URL}/api/public/productos/${encodeURIComponent(id)}`,
    {
      // Un precio o un "vendido" desactualizado durante un minuto es
      // aceptable; martillear el backend en cada visita compartida, no.
      next: { revalidate: 60 },
    },
  );

  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(
      `El backend respondió ${res.status} para la publicación ${id}`,
    );
  }
  return (await res.json()) as PublicacionPublica;
}
