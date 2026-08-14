/**
 * La página que ve el usuario en el NAVEGADOR justo antes de volver a la app.
 *
 * Hay dos momentos en que la app manda a alguien fuera y Mercado Pago lo
 * devuelve a una URL https nuestra, no a la app: el OAuth con el que un
 * vendedor conecta su cuenta, y la vuelta del comprador tras pagar con su
 * cuenta de Mercado Pago. En los dos casos hace falta un puente que
 * traduzca esa URL https en el deep link `mercaditoum://payments/...`.
 *
 * El salto es un BOTÓN y no un redirect automático a propósito: un
 * `location.replace('mercaditoum://…')` en un navegador donde la app no está
 * instalada deja una pantalla de error del sistema sin salida, y en varios
 * navegadores móviles la navegación a un esquema propio desde un script se
 * bloquea en silencio. Un botón siempre funciona o siempre falla de forma
 * visible.
 *
 * La paleta y la tipografía espejan `website/app/globals.css` (que a su vez
 * espeja `lib/app_theme.dart`), para que estas pantallas combinen con la
 * marca aunque no compartan build system con la app ni con la landing.
 */

const ICONO_EXITO = '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" '
  + 'stroke="#a84b37" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">'
  + '<path d="M4 12.5l5 5L20 6.5"/></svg>';

const ICONO_ERROR = '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" '
  + 'stroke="#3d5c70" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">'
  + '<path d="M6 6l12 12M18 6L6 18"/></svg>';

/**
 * Escapa lo que se interpola en el HTML.
 *
 * Ninguno de los textos de hoy viene del usuario, pero estas páginas se
 * sirven en respuesta a un redirect de Mercado Pago con query string, y la
 * distancia entre "hoy son constantes" y "alguien interpola `req.query`
 * aquí" es una línea de código.
 */
function escapar(texto) {
  return String(texto).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
}

/**
 * @param {object} opciones
 * @param {string} opciones.titulo   Encabezado grande.
 * @param {string} opciones.texto    Una línea explicando qué pasó.
 * @param {boolean} opciones.ok      Tiñe el icono; no cambia el layout.
 * @param {string} opciones.deepLink Destino del botón (`mercaditoum://…`).
 * @param {string} [opciones.etiquetaBoton]
 * @returns {string} HTML completo.
 */
function paginaPuente({ titulo, texto, ok, deepLink, etiquetaBoton = 'Volver a Mercadito UM' }) {
  return `<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapar(titulo)}</title>
<style>
 *{box-sizing:border-box}
 body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,system-ui,sans-serif;
      background:#fafaf8;color:#1b1a16;
      display:flex;min-height:100vh;align-items:center;justify-content:center;
      margin:0;padding:24px;line-height:1.55}
 .tarjeta{width:100%;max-width:380px;background:#fff;border-radius:20px;
      box-shadow:0 4px 24px rgba(27,26,22,.08);padding:40px 28px;text-align:center}
 .icono{width:56px;height:56px;border-radius:999px;display:flex;
      align-items:center;justify-content:center;margin:0 auto 20px;
      background:${ok ? 'rgba(168,75,55,.12)' : 'rgba(61,92,112,.1)'}}
 h1{font-size:21px;font-weight:700;letter-spacing:-.01em;color:#2b4150;margin:0 0 10px}
 p{font-size:14px;color:#6e6b64;margin:0 0 28px}
 a{display:inline-block;width:100%;background:#a84b37;color:#fff;text-decoration:none;
   padding:14px 24px;border-radius:12px;font-weight:600;font-size:15px}
 a:active{background:#8f3f2e}
</style></head><body>
<div class="tarjeta">
<div class="icono">${ok ? ICONO_EXITO : ICONO_ERROR}</div>
<h1>${escapar(titulo)}</h1><p>${escapar(texto)}</p>
<a href="${escapar(deepLink)}">${escapar(etiquetaBoton)}</a>
</div>
</body></html>`;
}

module.exports = { paginaPuente, escapar };
