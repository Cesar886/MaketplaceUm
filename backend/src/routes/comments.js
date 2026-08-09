// Comentarios públicos en una publicación.
//
// Asimetría deliberada de permisos: LEER es abierto (cualquiera, con o sin
// sesión, incluido un dispositivo anónimo) y ESCRIBIR exige una cuenta
// verificada. Los comentarios son el respaldo social de un vendedor dentro
// del campus; si los pudiera escribir cualquiera no dirían nada, y si hubiera
// que iniciar sesión para leerlos no servirían de respaldo ante quien todavía
// no se registra.

const db = require('../database');
const { requireAuth } = require('../auth');
const { sendPush } = require('../push');
const { sanitizarComentario, LARGO_MAXIMO } = require('../validation/comentarios');

/**
 * Espera mínima entre dos comentarios del MISMO usuario.
 *
 * Va por usuario y contra la base, no por IP en memoria como el rate limit
 * de routes/public.js: ahí lo que se frena es el raspado desde un cliente
 * anónimo, y aquí a una cuenta identificada que inunda un hilo. Un límite
 * por IP dejaría pasar el spam desde el campus (todos tras el mismo NAT) y
 * al mismo tiempo castigaría a usuarios distintos por compartir salida.
 * Contra la base y no en un Map porque un reinicio de PM2 no debe regalar
 * la ventana.
 */
const SEGUNDOS_ENTRE_COMENTARIOS = 10;

/** Preview del texto en la notificación push. */
const LARGO_PREVIEW = 80;

function nuevoIdComentario() {
  return `cmt_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

/**
 * La puerta del feature: comenta cualquier cuenta VERIFICADA, del tipo que
 * sea — alumno, personal UM, negocio o externo.
 *
 * Se mira `sellers.verified` y no `tipo_verificacion` porque esa columna solo
 * se llena en el flujo institucional (OTP al correo, 'estudiante'|'empleado').
 * Negocios y externos verifican por SMS y la dejan nula, así que usarla como
 * puerta los excluiría aun estando verificados. `verified` es la bandera que
 * ponen los cuatro flujos (routes/verificacion.js → marcarVerificado) y la
 * misma que el cliente lee en /verificacion/estado, de modo que lo que el
 * backend permite coincide con lo que la UI ofrece.
 *
 * @param seller Fila de `sellers`, o null/undefined si la cuenta ya no existe.
 */
function puedeComentar(seller) {
  return !!(seller && seller.verified);
}

function register(app) {
  const { products } = require('../data');

  // ─── GET /api/products/:id/comments ─────────────────────────────
  // Público. Paginado por keyset: ?limit=20&cursor=<created_at>|<id>
  app.get('/api/products/:id/comments', (req, res) => {
    try {
      const producto = products.find(p => p.id === req.params.id);
      if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });

      const { comments, nextCursor } = db.getProductComments(req.params.id, {
        limit: req.query.limit,
        cursor: req.query.cursor,
      });

      res.json({
        comments,
        nextCursor,
        // El total va en toda página, no solo en la primera: el header dice
        // "Comentarios (12)" y ese número tiene que seguir siendo correcto
        // después de paginar o de borrar uno.
        total: db.countProductComments(req.params.id),
      });
    } catch (err) {
      console.error('Error en GET /api/products/:id/comments:', err);
      res.status(500).json({ error: 'No se pudieron cargar los comentarios.' });
    }
  });

  // ─── POST /api/products/:id/comments ────────────────────────────
  // Requiere sesión Y verificación institucional.
  app.post('/api/products/:id/comments', requireAuth, (req, res) => {
    try {
      const producto = products.find(p => p.id === req.params.id);
      if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });

      const autorId = req.user.id;
      const autor = db.getDb()
        .prepare('SELECT id, name, verified FROM sellers WHERE id = ?')
        .get(autorId);

      // Token válido cuya cuenta ya no existe. No es 403: no hay nada que
      // verificar, la sesión simplemente dejó de apuntar a algo.
      if (!autor) {
        return res.status(401).json({ error: 'Tu sesión ya no es válida. Inicia sesión de nuevo.' });
      }

      if (!puedeComentar(autor)) {
        return res.status(403).json({
          error: 'Verifica tu cuenta para comentar',
          code: 'NO_VERIFICADO',
        });
      }

      const saneado = sanitizarComentario(req.body ? req.body.texto : undefined);
      if (saneado.error) return res.status(400).json({ error: saneado.error });

      const desdeUltimo = db.segundosDesdeUltimoComentario(autorId);
      if (desdeUltimo !== null && desdeUltimo < SEGUNDOS_ENTRE_COMENTARIOS) {
        const faltan = SEGUNDOS_ENTRE_COMENTARIOS - desdeUltimo;
        return res.status(429).json({
          error: `Espera ${faltan} segundo${faltan === 1 ? '' : 's'} antes de comentar de nuevo.`,
          retryAfter: faltan,
        });
      }

      const comentario = db.createProductComment(
        nuevoIdComentario(),
        producto.id,
        autorId,
        saneado.value,
      );

      // Tiempo real: a quien esté viendo este producto ahora mismo. Mismo
      // patrón de rooms que el chat (`conv:<id>`), ver index.js.
      const io = app.get('io');
      if (io) {
        io.to(`product:${producto.id}`).emit('new:comment', {
          productId: producto.id,
          comment: comentario,
        });
      }

      // Aviso al dueño de la publicación, salvo que se esté comentando a sí
      // mismo. El deep link lleva al detalle YA desplazado a los comentarios
      // (scrollToComments lo consume main_shell.dart).
      if (producto.seller && producto.seller !== autorId) {
        const preview = saneado.value.length > LARGO_PREVIEW
          ? `${saneado.value.slice(0, LARGO_PREVIEW)}…`
          : saneado.value;
        const titulo = 'Nuevo comentario';
        const cuerpo = `${autor.name} comentó en "${producto.title}": ${preview}`;
        const datos = {
          productId: producto.id,
          commentId: comentario.id,
          type: 'product_comment',
          scrollToComments: 'true',
        };

        db.createNotification(
          `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
          producto.seller,
          'product_comment',
          titulo,
          cuerpo,
          datos,
        );
        sendPush([producto.seller], titulo, cuerpo, datos);
      }

      res.status(201).json({
        comment: comentario,
        total: db.countProductComments(producto.id),
      });
    } catch (err) {
      console.error('Error en POST /api/products/:id/comments:', err);
      res.status(500).json({ error: 'No se pudo publicar el comentario. Intenta de nuevo.' });
    }
  });

  // ─── DELETE /api/products/:id/comments/:commentId ───────────────
  // Borra el autor (se arrepintió) o el dueño del producto (modera su
  // propia publicación). Borrado lógico: la fila se marca, no se va.
  app.delete('/api/products/:id/comments/:commentId', requireAuth, (req, res) => {
    try {
      const producto = products.find(p => p.id === req.params.id);
      if (!producto) return res.status(404).json({ error: 'Producto no encontrado' });

      const comentario = db.getProductCommentRow(req.params.commentId);
      // Un comentario de otro producto se trata como inexistente: confirmar
      // que el id existe pero está en otra publicación filtra información
      // sin ninguna razón.
      if (!comentario || comentario.product_id !== producto.id || comentario.deleted_at) {
        return res.status(404).json({ error: 'Comentario no encontrado' });
      }

      const actorId = req.user.id;
      const esAutor = comentario.user_id === actorId;
      const esDuenoDelProducto = producto.seller === actorId;
      if (!esAutor && !esDuenoDelProducto) {
        return res.status(403).json({ error: 'No puedes eliminar este comentario.' });
      }

      const borrado = db.softDeleteProductComment(comentario.id, actorId);
      if (!borrado) {
        // Otra petición ganó la carrera y ya lo marcó. No se emite el evento
        // dos veces, pero para quien llamó el resultado es el mismo.
        return res.json({ success: true, total: db.countProductComments(producto.id) });
      }

      const io = app.get('io');
      if (io) {
        io.to(`product:${producto.id}`).emit('comment:deleted', {
          productId: producto.id,
          commentId: comentario.id,
        });
      }

      res.json({ success: true, total: db.countProductComments(producto.id) });
    } catch (err) {
      console.error('Error en DELETE /api/products/:id/comments/:commentId:', err);
      res.status(500).json({ error: 'No se pudo eliminar el comentario.' });
    }
  });

  // ─── GET /api/users/:id/comments ────────────────────────────────
  // Comentarios que OTROS dejaron en las publicaciones de este usuario —
  // la pestaña "Comentarios" del perfil. Es prueba social, así que lo que
  // interesa es lo recibido, no lo escrito por esa cuenta.
  app.get('/api/users/:id/comments', (req, res) => {
    try {
      const existe = db.getDb()
        .prepare('SELECT 1 FROM sellers WHERE id = ?')
        .get(req.params.id);
      if (!existe) return res.status(404).json({ error: 'Usuario no encontrado' });

      const { comments, nextCursor } = db.getCommentsReceivedBySeller(req.params.id, {
        limit: req.query.limit,
        cursor: req.query.cursor,
      });

      res.json({
        comments,
        nextCursor,
        total: db.countCommentsReceivedBySeller(req.params.id),
      });
    } catch (err) {
      console.error('Error en GET /api/users/:id/comments:', err);
      res.status(500).json({ error: 'No se pudieron cargar los comentarios.' });
    }
  });
}

module.exports = { register, SEGUNDOS_ENTRE_COMENTARIOS, LARGO_MAXIMO };
