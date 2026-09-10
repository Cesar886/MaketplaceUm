import type { PublicacionPublica } from './tipos';

/**
 * URL del backend. Sin `NEXT_PUBLIC_` porque el fetch ocurre en el servidor
 * (Server Component): así la IP del backend no viaja al bundle del cliente.
 */
const API_URL = process.env.API_URL ?? 'http://127.0.0.1:3000';

/** URL pública del sitio, para canonical, OG y el QR. */
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ?? 'https://marketplace-um.me';

/**
 * Vuelve absoluta una ruta de imagen del backend. Las fotos se guardan como
 * '/uploads/x.webp', relativas al backend.
 *
 * Se arma sobre SITE_URL y NO sobre API_URL, aunque el archivo lo sirva el
 * backend. API_URL es una dirección INTERNA ('http://127.0.0.1:3000' en
 * producción): sirve para que este servidor le pida datos al backend, pero
 * como URL pública no existe. Puesta en `og:image`, el crawler de WhatsApp
 * intenta resolver 127.0.0.1 contra sí mismo y la vista previa sale sin foto
 * — que es justo lo que este endpoint entero existe para lograr. En los <img>
 * de la página pasa lo mismo, y además serían contenido inseguro dentro de
 * una página https.
 *
 * El dominio público funciona porque Apache proxea /uploads/ al backend (ver
 * /etc/apache2/sites-enabled/marketplace-um.me-le-ssl.conf), así que la foto
 * sale por HTTPS y del mismo origen que la página.
 */
export function urlFoto(ruta: string): string {
  if (/^https?:\/\//.test(ruta)) return ruta;
  return `${SITE_URL}${ruta.startsWith('/') ? '' : '/'}${ruta}`;
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
