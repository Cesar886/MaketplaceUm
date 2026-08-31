// Preguntas y respuestas públicas sobre una publicación.
//
// Reparto de permisos, distinto al de los comentarios y a propósito:
//
//   LEER    cualquiera, con o sin sesión. Es información del producto:
//           media pregunta respondida ahorra un chat.
//   PREGUNTAR  cualquier cuenta CON SESIÓN. No se exige verificación: aquí
//           no se está opinando sobre nadie, se está pidiendo un dato, y
//           poner un trámite delante de eso solo manda la duda al chat.
//   RESPONDER  únicamente el dueño de la publicación. Es la firma de la
//           respuesta: si respondiera cualquiera, el hilo dejaría de valer.
//
// Nadie puede preguntar en su propio producto: no aporta y es el atajo
// obvio para fabricarse un hilo de preguntas "frecuentes" a modo.

const db = require('../database');
const { requireAuth } = require('../auth');
const { sendPush } = require('../push');
const { sanitizarPregunta, sanitizarRespuesta, LARGO_MAXIMO } = require('../validation/comentarios');

/**
 * Espera mínima entre dos preguntas del MISMO usuario, en cualquier
 * publicación. Frena el tecleo compulsivo repartido entre varios hilos, que
 * el límite por producto no vería.
 */
const SEGUNDOS_ENTRE_PREGUNTAS = 30;

/**
 * Tope de preguntas de un usuario en UNA publicación por ventana. Es el
 * límite que importa: el daño no es preguntar mucho en la app, es inundar
 * la publicación de alguien más. Tres da para preguntar, repreguntar y
 * corregirse; la cuarta ya es otra cosa.
 */
const MAX_PREGUNTAS_POR_PRODUCTO = 3;
const VENTANA_HORAS = 24;

/** Preview del texto en la notificación push. */
const LARGO_PREVIEW = 80;

function nuevoIdPregunta() {
  return `q_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

function nuevoIdNotificacion() {
  return `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
}

/** Recorta un texto para que quepa en el cuerpo de una notificación. */
function preview(texto) {
  return texto.length > LARGO_PREVIEW ? `${texto.slice(0, LARGO_PREVIEW)}…` : texto;
}

function register(app) {
  const { products } = require('../data');

  // ─── GET /api/products/:id/questions ────────────────────────────
  // Público. Dos modos en el mismo endpoint:
  //   ?preview=true[&limit=3]  → las pocas que se asoman en el detalle,
  //                              priorizando respondidas recientes.
  //   ?limit=20&cursor=...     → listado completo, keyset (created_at|id).
  //   &filter=pending          → solo las que faltan por responder.
  app.get('/api/products/:id/questions', (req, res) => {
    try {
      const producto = products.find(p => p.id === req.params.id);
      if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });

      // Los dos contadores van en ambos modos: el detalle pinta con ellos
      // el "Ver las N preguntas" y el chip de pendientes del dueño, sin
      // tener que pedir el listado completo solo para contar.
      const total = db.countProductQuestions(producto.id);
      const pendingCount = db.countPendingProductQuestions(producto.id);

      if (req.query.preview === 'true') {
        const limite = Math.min(
          parseInt(req.query.limit, 10) || db.PREGUNTAS_PREVIEW,
          db.PREGUNTAS_PREVIEW,
        );
        return res.json({
          questions: db.getProductQuestionsPreview(producto.id, { limit: limite }),
          // El preview no pagina: devolver un cursor invitaría a paginarlo
          // y su orden (respondidas primero) no es paginable por keyset.
          nextCursor: null,
          total,
          pendingCount,
        });
      }

      const { questions, nextCursor } = db.getProductQuestions(producto.id, {
        limit: req.query.limit,
        cursor: req.query.cursor,
        filter: req.query.filter,
      });

      res.json({ questions, nextCursor, total, pendingCount });
    } catch (err) {
      console.error('Error en GET /api/products/:id/questions:', err);
      res.status(500).json({ error: 'No se pudieron cargar las preguntas.' });
    }
  });

  // ─── POST /api/products/:id/questions ───────────────────────────
  // Requiere sesión. No requiere verificación.
  app.post('/api/products/:id/questions', requireAuth, (req, res) => {
    try {
      const producto = products.find(p => p.id === req.params.id);
      if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });

      const autorId = req.user.id;

      // Server-side y no solo ocultando el botón: el cliente es sugerencia,
      // esto es la regla.
      if (producto.seller === autorId) {
        return res.status(403).json({
          error: 'No puedes preguntar en tu propia publicación.',
          code: 'ES_TU_PRODUCTO',
        });
      }

      const saneado = sanitizarPregunta(req.body ? req.body.texto : undefined);
      if (saneado.error) return res.status(400).json({ error: saneado.error });

      const desdeUltima = db.segundosDesdeUltimaPregunta(autorId);
      if (desdeUltima !== null && desdeUltima < SEGUNDOS_ENTRE_PREGUNTAS) {
        const faltan = SEGUNDOS_ENTRE_PREGUNTAS - desdeUltima;
        return res.status(429).json({
          error: `Espera ${faltan} segundo${faltan === 1 ? '' : 's'} antes de preguntar de nuevo.`,
          retryAfter: faltan,
        });
      }

      const recientes = db.contarPreguntasRecientes(autorId, producto.id, VENTANA_HORAS);
      if (recientes >= MAX_PREGUNTAS_POR_PRODUCTO) {
        return res.status(429).json({
          error: `Ya hiciste ${MAX_PREGUNTAS_POR_PRODUCTO} preguntas en esta publicación. Espera a que te respondan.`,
          code: 'LIMITE_POR_PRODUCTO',
          retryAfter: VENTANA_HORAS * 3600,
        });
      }

      const pregunta = db.createProductQuestion(
        nuevoIdPregunta(),
        producto.id,
        producto.seller,
        autorId,
        saneado.value,
      );

      // Aviso al dueño. El deep link lleva a la pantalla de preguntas de
      // ESA publicación, resaltando la pregunta concreta — el vendedor
      // viene a responder una, no a revisar el hilo entero.
      if (producto.seller) {
        const titulo = 'Nueva pregunta';
        const cuerpo = `${pregunta.author.name} preguntó en "${producto.title}": ${preview(saneado.value)}`;
        const datos = {
          type: 'product_question',
          productId: producto.id,
          questionId: pregunta.id,
        };

        db.createNotification(
          nuevoIdNotificacion(),
          producto.seller,
          'product_question',
          titulo,
          cuerpo,
          datos,
        );
        sendPush([producto.seller], titulo, cuerpo, datos);
      }

      res.status(201).json({
        question: pregunta,
        total: db.countProductQuestions(producto.id),
        pendingCount: db.countPendingProductQuestions(producto.id),
      });
    } catch (err) {
      console.error('Error en POST /api/products/:id/questions:', err);
      res.status(500).json({ error: 'No se pudo publicar la pregunta. Intenta de nuevo.' });
    }
  });

  // ─── DELETE /api/products/:id/questions/:questionId ───────────
  // Puede borrar quien preguntó o el vendedor que recibió la pregunta.
  app.delete('/api/products/:id/questions/:questionId', requireAuth, (req, res) => {
    try {
      const producto = products.find(p => p.id === req.params.id);
      if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });

      const fila = db.getProductQuestionRow(req.params.questionId);
      if (!fila || fila.product_id !== producto.id) {
        return res.status(404).json({ error: 'Pregunta no encontrada' });
      }

      const actorId = req.user.id;
      const esAutor = fila.asked_by === actorId;
      const esVendedor = fila.seller_id === actorId;
      if (!esAutor && !esVendedor) {
        return res.status(403).json({
          error: 'No puedes eliminar esta pregunta.',
          code: 'NO_PUEDES_ELIMINAR_PREGUNTA',
        });
      }

      db.deleteProductQuestion(fila.id);

      res.json({
        success: true,
        total: db.countProductQuestions(producto.id),
        pendingCount: db.countPendingProductQuestions(producto.id),
      });
    } catch (err) {
      console.error('Error en DELETE /api/products/:id/questions/:questionId:', err);
      res.status(500).json({ error: 'No se pudo eliminar la pregunta.' });
    }
  });

  // ─── POST /api/questions/:id/answer ─────────────────────────────
  // Solo el dueño de la publicación. Si ya había respuesta, la corrige.
  app.post('/api/questions/:id/answer', requireAuth, (req, res) => {
    try {
      const fila = db.getProductQuestionRow(req.params.id);
      if (!fila) return res.status(404).json({ error: 'Pregunta no encontrada' });

      // Se compara contra seller_id de la FILA, no contra nada que venga en
      // el body ni en la query: el cliente no participa en esta decisión.
      if (fila.seller_id !== req.user.id) {
        return res.status(403).json({
          error: 'Solo quien publicó puede responder esta pregunta.',
          code: 'NO_ERES_EL_VENDEDOR',
        });
      }

      const saneado = sanitizarRespuesta(req.body ? req.body.texto : undefined);
      if (saneado.error) return res.status(400).json({ error: saneado.error });

      const yaHabiaRespuesta = !!fila.answer_text;
      const pregunta = db.answerProductQuestion(fila.id, saneado.value);

      // Al que preguntó se le avisa: sin esto tendría que volver a entrar a
      // la publicación a ver si le contestaron. En una corrección también,
      // porque para él una respuesta editada es una respuesta nueva.
      if (fila.asked_by && fila.asked_by !== req.user.id) {
        const titulo = yaHabiaRespuesta ? 'Respuesta actualizada' : 'Respondieron tu pregunta';
        const producto = products.find(p => p.id === fila.product_id);
        const nombreProducto = producto ? producto.title : 'una publicación';
        const cuerpo = `Sobre "${nombreProducto}": ${preview(saneado.value)}`;
        const datos = {
          type: 'question_answered',
          productId: fila.product_id,
          questionId: fila.id,
        };

        db.createNotification(
          nuevoIdNotificacion(),
          fila.asked_by,
          'question_answered',
          titulo,
          cuerpo,
          datos,
        );
        sendPush([fila.asked_by], titulo, cuerpo, datos);
      }

      res.json({
        question: pregunta,
        pendingCount: db.countPendingProductQuestions(fila.product_id),
      });
    } catch (err) {
      console.error('Error en POST /api/questions/:id/answer:', err);
      res.status(500).json({ error: 'No se pudo guardar la respuesta. Intenta de nuevo.' });
    }
  });
}

module.exports = {
  register,
  SEGUNDOS_ENTRE_PREGUNTAS,
  MAX_PREGUNTAS_POR_PRODUCTO,
  VENTANA_HORAS,
  LARGO_MAXIMO,
};
