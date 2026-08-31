// La única ruta del enigma escondido.
//
// No se anuncia en ninguna parte: se llega a ella desde la pantalla que abre
// el gatillo en comentarios (ver routes/comments.js y secreto/enigma.js). Por
// eso no hay un GET que devuelva el acertijo — el texto vive en el cliente,
// que ya lo tiene en pantalla —, solo el POST que juzga la respuesta.
//
// La respuesta correcta NUNCA sale de este proceso, ni en claro ni hasheada.
// Es la diferencia entre un juego y un juego resuelto con `strings` sobre el
// APK: el cliente puede preguntar "¿es esta?", y nada más.

const db = require('../database');
const { requireAuth } = require('../auth');
const { esRespuestaCorrecta, SEGUNDOS_ENTRE_INTENTOS } = require('../secreto/enigma');

/**
 * Último intento de cada usuario, para el freno entre intentos.
 *
 * En memoria y no en la base, al revés que el rate limit de comentarios: allá
 * lo que se protege es un hilo público de spam y perder la ventana en un
 * reinicio tiene consecuencias visibles; aquí solo se encarece la fuerza
 * bruta contra una respuesta de una palabra, y un reinicio regala, como
 * mucho, un intento. No vale una tabla por eso.
 */
const ultimoIntento = new Map();

function segundosDesdeUltimoIntento(userId) {
  const previo = ultimoIntento.get(userId);
  return previo === undefined ? null : (Date.now() - previo) / 1000;
}

function register(app) {
  // ─── POST /api/secreto/resolver ─────────────────────────────────
  // Juzga una respuesta al acertijo. Requiere sesión: sin usuario no hay a
  // quién ponerle la posición, y el marcador es todo el premio.
  app.post('/api/secreto/resolver', requireAuth, (req, res) => {
    try {
      const userId = req.user.id;

      const desdeUltimo = segundosDesdeUltimoIntento(userId);
      if (desdeUltimo !== null && desdeUltimo < SEGUNDOS_ENTRE_INTENTOS) {
        return res.status(429).json({
          error: 'Respira. Inténtalo de nuevo en un momento.',
          retryAfter: Math.ceil(SEGUNDOS_ENTRE_INTENTOS - desdeUltimo),
        });
      }
      ultimoIntento.set(userId, Date.now());

      const respuesta = req.body ? req.body.respuesta : undefined;

      if (!esRespuestaCorrecta(respuesta)) {
        // 200 y no 400: la petición estaba perfectamente bien formada, la
        // respuesta simplemente no era. Un error HTTP haría que el cliente
        // pintara "algo salió mal" donde debe decir "no es".
        return res.json({ correcto: false });
      }

      const { posicion, solvedAt, repetida } = db.registrarResolucionEnigma(userId);
      res.json({
        correcto: true,
        posicion,
        resueltoEn: solvedAt,
        // Para que la pantalla del premio distinga "lo acabas de lograr" de
        // "ya lo habías logrado y volviste a entrar".
        repetida,
        total: db.contarResolucionesEnigma(),
      });
    } catch (err) {
      console.error('Error en POST /api/secreto/resolver:', err);
      res.status(500).json({ error: 'No se pudo validar la respuesta. Intenta de nuevo.' });
    }
  });
}

module.exports = { register };
