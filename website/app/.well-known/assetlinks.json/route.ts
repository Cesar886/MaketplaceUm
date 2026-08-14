import { HUELLAS_SHA256_ANDROID, PAQUETE_ANDROID } from '@/lib/app';

/**
 * Digital Asset Links: le dice a Android que esta app puede abrir los links de
 * este dominio sin pasar por el navegador ni preguntarle al usuario.
 *
 * Es un Route Handler y no un archivo en `public/` a propósito. Sirviéndolo
 * desde aquí se controla el `Content-Type` explícitamente: Android exige
 * `application/json` y rechaza en silencio cualquier otra cosa, que es el modo
 * de fallo más difícil de diagnosticar de todo este mecanismo.
 *
 * Android lo descarga por HTTPS al INSTALAR la app (no en cada link), así que
 * un cambio aquí no surte efecto en instalaciones existentes hasta que el
 * sistema revalide. Para forzarlo en pruebas:
 *   adb shell pm verify-app-links --re-verify <paquete>
 *   adb shell pm get-app-links <paquete>
 */

// Estático: el contenido no depende de la petición, así que Next lo puede
// cachear indefinidamente y servirlo desde el CDN.
export const dynamic = 'force-static';

export function GET() {
  const cuerpo = [
    {
      // `delegate_permission/common.handle_all_urls` es el permiso concreto
      // que habilita App Links; no hay uno más granular por ruta (el filtrado
      // por path vive en el intent-filter del AndroidManifest).
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: PAQUETE_ANDROID,
        sha256_cert_fingerprints: HUELLAS_SHA256_ANDROID,
      },
    },
  ];

  return new Response(JSON.stringify(cuerpo, null, 2), {
    headers: {
      'content-type': 'application/json',
      // Una hora: suficiente para que un CDN absorba el tráfico, y corto para
      // que agregar la huella real se propague el mismo día.
      'cache-control': 'public, max-age=3600',
    },
  });
}
