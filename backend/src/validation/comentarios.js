// Validación y saneado de texto libre escrito por usuarios: comentarios de
// producto y, con los mismos criterios, preguntas y respuestas.
//
// Igual que validation/sellerProfile.js, cada función devuelve
// `{ error }` o `{ value }` en vez de lanzar, para que la ruta decida el
// código de respuesta sin envolver todo en try/catch.

/** Tope de caracteres. Replicado como CHECK en la tabla (database.js). */
const LARGO_MAXIMO = 500;

// Caracteres de control (menos \n y \t): no se ven, no aportan nada y sí
// sirven para meter ruido invisible o romper un render línea por línea.
const CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;

// Secuencias con forma de etiqueta HTML: `<b>`, `</script>`, `<img ...>`.
// Se exige una letra tras el `<` (o tras `</`) a propósito, para que un
// "5 < 10" o un "precio <100" sobrevivan intactos — son texto legítimo y
// muy común en un marketplace, y borrarlos sería peor que el problema.
const ETIQUETA_HTML = /<\/?[a-zA-Z][^>]*>/g;

/**
 * Sanea un texto libre y valida su longitud.
 *
 * Sobre XSS: la app es Flutter y un `Text` NO interpreta HTML, así que el
 * riesgo real no está en el cliente actual sino en cualquier consumidor que
 * llegue a renderizar esto como HTML (hoy, el sitio de /website). Quitar las
 * etiquetas aquí es defensa en profundidad, no la defensa principal: quien
 * renderice HTML con este texto DEBE escaparlo de todos modos. Lo que sí se
 * garantiza es que lo guardado es texto plano, sin marcado ni control chars.
 *
 * Los mensajes de error se arman con `campo` porque van directos a la UI:
 * "La pregunta no puede estar vacía" en el hilo de preguntas, no un
 * "El comentario..." heredado de otra sección.
 *
 * @param {unknown} entrada texto crudo del cliente
 * @param {{campo?: {articulo: string, nombre: string}, largoMaximo?: number}} opciones
 * @returns {{error: string} | {value: string}}
 */
function sanitizarTexto(entrada, opciones = {}) {
  const { articulo = 'El', nombre = 'comentario' } = opciones.campo || {};
  const largoMaximo = opciones.largoMaximo || LARGO_MAXIMO;
  // Concordancia de género: "La pregunta es requerida" / "El comentario es
  // requerido". Se deduce del artículo en vez de pedir otro parámetro más.
  const femenino = articulo.toLowerCase() === 'la';

  if (typeof entrada !== 'string') {
    return { error: `${articulo} ${nombre} es ${femenino ? 'requerida' : 'requerido'}.` };
  }

  const limpio = entrada
    .replace(CONTROL, '')
    .replace(ETIQUETA_HTML, '')
    // Más de dos saltos seguidos es relleno para acaparar el hilo.
    .replace(/\n{3,}/g, '\n\n')
    // Espacios/tabs repetidos dentro de una línea, sin tocar los saltos.
    .replace(/[^\S\n]{2,}/g, ' ')
    .trim();

  if (limpio.length === 0) {
    return { error: `${articulo} ${nombre} no puede estar ${femenino ? 'vacía' : 'vacío'}.` };
  }
  if (limpio.length > largoMaximo) {
    return { error: `${articulo} ${nombre} no puede pasar de ${largoMaximo} caracteres.` };
  }

  return { value: limpio };
}

/** Texto de un comentario de producto. */
function sanitizarComentario(entrada) {
  return sanitizarTexto(entrada, {
    campo: { articulo: 'El', nombre: 'comentario' },
  });
}

/** Texto de una pregunta pública sobre un producto. */
function sanitizarPregunta(entrada) {
  return sanitizarTexto(entrada, {
    campo: { articulo: 'La', nombre: 'pregunta' },
  });
}

/** Texto de la respuesta del vendedor a una pregunta. */
function sanitizarRespuesta(entrada) {
  return sanitizarTexto(entrada, {
    campo: { articulo: 'La', nombre: 'respuesta' },
  });
}

module.exports = {
  sanitizarTexto,
  sanitizarComentario,
  sanitizarPregunta,
  sanitizarRespuesta,
  LARGO_MAXIMO,
};
