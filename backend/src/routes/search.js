const db = require('../database');

const TRENDING_WINDOW_DAYS = 7;
const TRENDING_LIMIT = 12;
const TRENDING_CACHE_MS = 20 * 60 * 1000;

let trendingCache = { data: null, expiresAt: 0 };

function register(app) {
  // GET /api/search/trending — términos más buscados en los últimos
  // TRENDING_WINDOW_DAYS días. Cacheado TRENDING_CACHE_MS: no es tiempo real,
  // no vale la pena recalcular el agregado en cada request.
  app.get('/api/search/trending', (_req, res) => {
    const now = Date.now();
    if (!trendingCache.data || now >= trendingCache.expiresAt) {
      let rows = db.getTrendingSearches({
        days: TRENDING_WINDOW_DAYS,
        limit: TRENDING_LIMIT,
      });
      // Arranque en frío: sin búsquedas registradas el placeholder se
      // quedaría en el texto fijo para siempre. Se cae a categorías reales
      // del catálogo, que ya son dinámicas (dependen de qué hay publicado)
      // y se reemplazan solas en cuanto haya búsquedas de verdad.
      if (rows.length === 0) {
        rows = db.getFallbackSearchTerms({ limit: TRENDING_LIMIT });
      }
      trendingCache = {
        data: rows.map(r => r.queryText),
        expiresAt: now + TRENDING_CACHE_MS,
      };
    }
    res.json({ terms: trendingCache.data });
  });

  // POST /api/search/track — registra una búsqueda ejecutada por el usuario
  // (al presionar buscar/enter, no por cada tecla). Fire-and-forget desde el
  // cliente: nunca debe romper la búsqueda local si esto falla.
  app.post('/api/search/track', (req, res) => {
    const { query } = req.body || {};
    if (typeof query !== 'string') {
      return res.status(400).json({ error: 'query es obligatorio' });
    }
    db.recordSearchQuery(query);
    res.status(204).end();
  });
}

/** Solo para tests: fuerza a que la próxima lectura recalcule el agregado. */
function _resetTrendingCacheForTests() {
  trendingCache = { data: null, expiresAt: 0 };
}

module.exports = { register, _resetTrendingCacheForTests };
