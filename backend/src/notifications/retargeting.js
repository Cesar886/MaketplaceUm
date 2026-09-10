/**
 * Job de retargeting: convierte los productos recién publicados en pushes
 * hacia quienes mostraron interés en esa categoría, respetando las reglas de
 * frecuencia.
 *
 * Corre por lotes en vez de dentro del POST /api/products a propósito. Un
 * vendedor que sube cinco productos seguidos generaría cinco evaluaciones
 * casi simultáneas, y aunque el capping impediría cinco pushes, el resultado
 * dependería del orden de llegada. Juntando la ventana, un sujeto recibe un
 * único aviso que dice "3 nuevos en Electrónicos" en lugar de una carrera
 * entre tres productos por el mismo hueco.
 */

const db = require('../database');
const {
  sendPush
} = require('../push');
const interes = require('./interes');
const frecuencia = require('./frecuencia');

/**
 * Encola un producto recién publicado para que la siguiente pasada del job
 * lo evalúe. Se llama desde el POST de productos.
 *
 * Es best-effort: encolar no debe poder tumbar la publicación de un
 * producto, que es la operación que al usuario le importa.
 */
async function encolarProducto(productId) {
  if (!productId) return;
  try {
    await db.getDb().prepare(`
      INSERT OR IGNORE INTO interest_notification_queue (product_id, created_at)
      VALUES (?, datetime('now'))
    `).run(productId);
  } catch (err) {
    console.error('[retargeting] no se pudo encolar el producto:', err.message);
  }
}

/**
 * Lee la cola pendiente y la marca procesada en la misma transacción.
 *
 * Marcar antes de enviar es deliberado: si el envío falla a media lista, el
 * coste es un aviso perdido; si en cambio se marcara al final y el proceso
 * muriera, la siguiente pasada volvería a anunciar los mismos productos, que
 * es el fallo que sí se nota desde el teléfono.
 */
async function tomarLotePendiente(limite = 200) {
  const raw = db.getDb();
  return await raw.transaction(async () => {
    // Primero se fija QUÉ filas entran en el lote, y ese conjunto exacto es
    // el que se marca y el que se lee. Antes eran dos consultas con su propio
    // LIMIT —una con JOIN a products y otra sin— y en cuanto la cola tenía
    // huérfanos (producto borrado; aquí no hay FK) los dos conjuntos se
    // desalineaban: las últimas filas del lote se anunciaban sin quedar
    // marcadas y volvían a salir en la pasada siguiente.
    const ids = (await raw.prepare(`
      SELECT product_id FROM interest_notification_queue
      WHERE processed_at IS NULL
      ORDER BY created_at
      LIMIT ?
    `).all(limite)).map(fila => fila.product_id);
    if (ids.length === 0) return [];
    const huecos = ids.map(() => '?').join(',');

    // Se marcan TODAS las del lote, incluidas las que el JOIN de abajo
    // descartará por producto borrado: si no, esas filas se quedarían dando
    // vueltas en la cola para siempre.
    await raw.prepare(`
      UPDATE interest_notification_queue
      SET processed_at = datetime('now')
      WHERE product_id IN (${huecos})
    `).run(...ids);
    return await raw.prepare(`
      SELECT q.product_id AS productId,
             p.category   AS categoryId,
             p.title      AS title,
             p.seller     AS sellerId,
             p.priceNum   AS priceNum
      FROM interest_notification_queue q
      JOIN products p ON p.id = q.product_id
      WHERE q.product_id IN (${huecos})
      ORDER BY q.created_at
    `).all(...ids);
  })();
}

/**
 * Redacta el push según por qué le toca a este sujeto.
 *
 * `interest_match` es alguien que estuvo mirando esa categoría hace poco:
 * el mensaje puede permitirse ser explícito sobre eso. `category_follow` es
 * alguien que la sigue a mano y puede no haberla visitado en semanas, así
 * que decirle "coincide con lo que viste" sonaría inventado.
 */
function redactarMensaje({
  motivo,
  nombreCategoria,
  productos
}) {
  const titulo = motivo === 'interest_match' ? `Coincide con lo que viste en ${nombreCategoria}` : `Nuevo en ${nombreCategoria}`;
  const cuerpo = productos.length === 1 ? `${productos[0].title} — $${productos[0].priceNum ?? 0}` : `${productos.length} publicaciones nuevas para ti`;
  return {
    titulo,
    cuerpo
  };
}

/**
 * Una pasada completa del job.
 *
 * @returns {Promise<{lote, categorias, enviados, omitidos}>} resumen para logs y tests
 */
async function ejecutarJobRetargeting() {
  // El snapshot de interés se recalcula al inicio de cada pasada: es lo que
  // aplica el decaimiento y purga a los que llevan 7 días sin aparecer.
  await interes.refrescarInteres();
  const pendientes = await tomarLotePendiente();
  const resumen = {
    lote: pendientes.length,
    categorias: 0,
    enviados: 0,
    omitidos: {}
  };
  if (pendientes.length === 0) return resumen;

  // Agrupar por categoría: un sujeto recibe como mucho un aviso por
  // categoría, con todos los productos nuevos de esta ventana dentro.
  const porCategoria = new Map();
  for (const fila of pendientes) {
    if (!fila.categoryId) continue;
    if (!porCategoria.has(fila.categoryId)) porCategoria.set(fila.categoryId, []);
    porCategoria.get(fila.categoryId).push(fila);
  }
  resumen.categorias = porCategoria.size;
  const nombresCategoria = new Map((await db.getCategories()).map(c => [c.id, c.name || c.id]));

  // Un sujeto sale como mucho una vez por pasada aunque sea elegible en
  // varias categorías. El capping por categoría lo permitiría, pero recibir
  // dos pushes en el mismo segundo es exactamente la saturación que este
  // sistema existe para evitar.
  const yaAvisados = new Set();
  for (const [categoryId, productos] of porCategoria) {
    const nombreCategoria = nombresCategoria.get(categoryId) || categoryId;
    const vendedores = new Set(productos.map(p => p.sellerId));
    for (const candidato of await interes.getSujetosElegibles(categoryId)) {
      const {
        subjectId,
        motivo
      } = candidato;
      if (yaAvisados.has(subjectId)) {
        contar(resumen.omitidos, 'ya_avisado_en_esta_pasada');
        continue;
      }
      // Nadie recibe un aviso de su propia publicación.
      if (vendedores.has(subjectId)) {
        contar(resumen.omitidos, 'es_el_vendedor');
        continue;
      }

      // Un sujeto anónimo no tiene campana —GET /api/notifications exige
      // sesión—, así que sin token FCM no le queda ningún canal por el que
      // enterarse. Registrar el envío de todas formas le gastaría uno de sus
      // tres avisos semanales y, a los tres, la reducción adaptativa pausaría
      // la categoría por no abrir algo que nunca llegó a existir. Una cuenta
      // sin token sí sigue adelante: la notificación in-app la espera.
      if (esAnonimo(subjectId) && (await db.getPushTokensForUser(subjectId)).length === 0) {
        contar(resumen.omitidos, 'sin_canal_de_entrega');
        continue;
      }
      const veredicto = await frecuencia.puedeEnviar(subjectId, categoryId);
      if (!veredicto.permitido) {
        contar(resumen.omitidos, veredicto.motivo);
        continue;
      }
      const {
        titulo,
        cuerpo
      } = redactarMensaje({
        motivo,
        nombreCategoria,
        productos
      });
      const productIds = productos.map(p => p.productId);

      // La notificación in-app solo tiene sentido para cuentas: la campana
      // se lee desde GET /api/notifications, que exige sesión. Un sujeto
      // anónimo recibe el push y nada más.
      let notificationId = null;
      if (!esAnonimo(subjectId)) {
        notificationId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
        await db.createNotification(notificationId, subjectId, frecuencia.TIPO_RETARGETING, titulo, cuerpo, {
          category: categoryId,
          productIds,
          motivo
        });
      }
      await frecuencia.registrarEnvio({
        subjectId,
        categoryId,
        productIds,
        notificationId
      });
      yaAvisados.add(subjectId);
      resumen.enviados++;

      // El push se manda sin await dentro del bucle para no serializar una
      // ronda de red por sujeto; los fallos se registran, no se propagan,
      // porque el log del envío ya está escrito y reintentarlo duplicaría.
      (await sendPush([subjectId], titulo, cuerpo, {
        type: frecuencia.TIPO_RETARGETING,
        category: categoryId,
        productId: productIds.length === 1 ? productIds[0] : '',
        notificationId: notificationId || '',
        motivo
      })).catch(err => console.error('[retargeting] fallo al enviar push:', err.message));
    }
  }
  console.log(`[retargeting] lote=${resumen.lote} categorías=${resumen.categorias} enviados=${resumen.enviados}`, resumen.omitidos);
  return resumen;
}
function contar(mapa, clave) {
  mapa[clave] = (mapa[clave] || 0) + 1;
}

// Coincide con el formato que genera AnonymousId en la app y que valida
// /api/notifications/register-push-anon.
function esAnonimo(subjectId) {
  return typeof subjectId === 'string' && subjectId.startsWith('anon_');
}
module.exports = {
  encolarProducto,
  tomarLotePendiente,
  redactarMensaje,
  ejecutarJobRetargeting,
  esAnonimo
};
