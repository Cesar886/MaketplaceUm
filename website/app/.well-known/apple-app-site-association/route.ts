import { APPLE_TEAM_ID, BUNDLE_ID_IOS } from '@/lib/app';

/**
 * Apple App Site Association: el equivalente iOS de assetlinks.json, para
 * Universal Links.
 *
 * Preparado por adelantado aunque hoy solo se publique en Android. Servirlo
 * sin Team ID no rompe nada: iOS no verificará el dominio y los links abrirán
 * Safari, que es el fallback web que ya existe.
 *
 * Tres detalles que iOS exige y que son fáciles de incumplir:
 *   1. El archivo NO lleva extensión (.json) en la URL.
 *   2. Debe servirse como `application/json` por HTTPS válido.
 *   3. NO puede haber redirecciones al pedirlo — un 301 lo invalida.
 * Por eso es un Route Handler: los tres puntos quedan bajo control aquí.
 */

export const dynamic = 'force-static';

export function GET() {
  // Sin Team ID el appID quedaría como '.com.example.app', que iOS descarta.
  // Mejor publicar la lista vacía: el archivo existe y es válido, y el día que
  // se llene APPLE_TEAM_ID empieza a funcionar sin tocar nada más.
  const apps = APPLE_TEAM_ID ? [`${APPLE_TEAM_ID}.${BUNDLE_ID_IOS}`] : [];

  const cuerpo = {
    applinks: {
      details: apps.map(appID => ({
        appIDs: [appID],
        components: [
          // Mismo alcance que el intent-filter de Android: solo el detalle de
          // una publicación. La home y el resto del sitio siguen abriendo en
          // el navegador, que es donde tienen sentido.
          {
            '/': '/producto/*',
            comment: 'Detalle de una publicación compartida',
          },
        ],
      })),
    },
    // Reservado para funciones que hoy no se usan (App Clips, contraseñas
    // compartidas). Se declaran vacíos porque iOS los espera presentes.
    webcredentials: { apps },
    appclips: { apps: [] },
  };

  return new Response(JSON.stringify(cuerpo, null, 2), {
    headers: {
      'content-type': 'application/json',
      'cache-control': 'public, max-age=3600',
    },
  });
}
