const db = require('../database');
const { attachRelations } = require('./products');

// Dentro de los primeros DIVERSITY_WINDOW resultados, como máximo
// DIVERSITY_MAX_PER_SELLER productos pueden ser del mismo vendedor.
const DIVERSITY_WINDOW = 20;
const DIVERSITY_MAX_PER_SELLER = 2;

/**
 * Reordena `products` (ya viene ordenado por score DESC) para que dentro de
 * la ventana [0, windowSize) no haya más de maxPerSeller productos del mismo
 * vendedor. Los productos que exceden el cupo se difieren hacia el final,
 * preservando el orden relativo de score entre ellos.
 */
function applyDiversity(products, windowSize = DIVERSITY_WINDOW, maxPerSeller = DIVERSITY_MAX_PER_SELLER) {
  const picked = [];
  const sellerCount = new Map();

  for (const product of products) {
    if (picked.length >= windowSize) break;
    const count = sellerCount.get(product.seller) || 0;
    if (count < maxPerSeller) {
      picked.push(product);
      sellerCount.set(product.seller, count + 1);
    }
  }

  const pickedIds = new Set(picked.map(p => p.id));
  const rest = products.filter(p => !pickedIds.has(p.id));
  return [...picked, ...rest];
}

function register(app) {
  // GET /api/feed — feed personalizado por device_id (+ user_id opcional)
  app.get('/api/feed', (req, res) => {
    const deviceId = req.query.device_id;
    const userId = req.query.user_id || null;
    const limit = Math.min(parseInt(req.query.limit, 10) || 60, 200);
    const offset = parseInt(req.query.offset, 10) || 0;

    if (!deviceId) {
      return res.status(400).json({ error: 'device_id es obligatorio' });
    }

    // Se pide más de lo necesario (limit + margen) para que, tras aplicar
    // diversidad, la ventana de resultados siga teniendo `limit` productos
    // aunque algunos se difieran por cupo de vendedor.
    const ranked = db.getFeedRanked({ deviceId, userId, limit: limit + DIVERSITY_WINDOW, offset });
    const diversified = applyDiversity(ranked).slice(0, limit);
    // getFeedRanked ya normaliza cada fila vía rowToProduct (images/extras
    // parseados, camelCase), pero no trae sellerObj/categoryObj/ratings —
    // eso lo agrega attachRelations, el mismo helper que usa GET /products,
    // para que el cliente reciba exactamente el mismo shape sin importar
    // qué endpoint lo sirvió.
    const enriched = attachRelations(diversified, userId || deviceId);

    res.json({
      deviceId,
      userId,
      count: enriched.length,
      products: enriched,
    });
  });

  // POST /api/interacciones — registra vista/favorito/contacto de un producto
  app.post('/api/interacciones', (req, res) => {
    const { deviceId, userId, productId, tipo } = req.body || {};

    if (!deviceId || !productId || !tipo) {
      return res.status(400).json({ error: 'deviceId, productId y tipo son obligatorios' });
    }
    if (!['vista', 'favorito', 'contacto'].includes(tipo)) {
      return res.status(400).json({ error: "tipo debe ser 'vista', 'favorito' o 'contacto'" });
    }

    const product = db.getProductById(productId);
    if (!product) {
      return res.status(404).json({ error: 'Producto no encontrado' });
    }

    db.registrarInteraccion({
      deviceId,
      userId: userId || null,
      productId,
      category: product.category,
      tipo,
    });

    res.status(201).json({ ok: true });
  });
}

module.exports = { register, applyDiversity };
