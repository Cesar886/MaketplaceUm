const db = require('../database');

const TRENDING_WINDOW_DAYS = 7;

/**
 * 10 términos exactos: es lo que el placeholder rotativo alcanza a mostrar
 * antes de dar la vuelta. Más allá de eso la cola son términos con uno o dos
 * votos, ruido que hace ver el buscador aleatorio en vez de popular.
 */
const TRENDING_LIMIT = 10;

/**
 * Techo del caché. Corto a propósito: no es lo que mantiene el agregado
 * fresco (de eso se encarga la revisión de abajo), solo evita que el ranking
 * se quede clavado cuando lo único que cambió es el paso del tiempo —
 * búsquedas que salen de la ventana de 7 días o que dejan de contar como
 * "de hoy".
 */
const TRENDING_CACHE_MS = 60 * 1000;

let trendingCache = { data: null, expiresAt: 0, revision: -1 };

function register(app) {
  // GET /api/search/trending — términos más buscados en los últimos
  // TRENDING_WINDOW_DAYS días.
  //
  // El agregado se cachea porque recalcularlo en cada request sería trabajo
  // repetido, pero el caché se invalida en cuanto alguien busca algo
  // (db.getSearchQueriesRevision cambia). Esa es la diferencia con la
  // versión anterior, que solo expiraba por TTL y en la práctica dejaba el
  // placeholder congelado hasta reiniciar el proceso.
  app.get('/api/search/trending', (_req, res) => {
    const now = Date.now();
    const revision = db.getSearchQueriesRevision();
    if (!trendingCache.data || now >= trendingCache.expiresAt || revision !== trendingCache.revision) {
      let rows = db.getTrendingSearches({
        days: TRENDING_WINDOW_DAYS,
        limit: TRENDING_LIMIT,
      });
      // Arranque en frío: sin búsquedas registradas el placeholder se
      // quedaría en el texto fijo para siempre. Se cae a nombres de
      // productos populares (por vistas/favoritos/contactos), que ya son
      // dinámicos y se parecen a una búsqueda real, no a una categoría del
      // catálogo. Se reemplazan solos en cuanto haya búsquedas de verdad.
      if (rows.length === 0) {
        rows = db.getFallbackSearchTerms({ limit: TRENDING_LIMIT });
      }
      trendingCache = {
        data: rows.map(r => r.queryText),
        expiresAt: now + TRENDING_CACHE_MS,
        revision,
      };
    }
    // Sin esto, cualquier proxy o el propio cliente HTTP puede servir una
    // copia vieja y anular todo el trabajo de invalidación de arriba.
    res.set('Cache-Control', 'no-store');
    res.json({ terms: trendingCache.data });
  });

  // POST /api/search/track — registra una búsqueda ejecutada por el usuario
  // (al presionar buscar/enter, no por cada tecla). Fire-and-forget desde el
  // cliente: nunca debe romper la búsqueda local si esto falla.
  //
  // `deviceId` es opcional y anónimo. Sirve para dos cosas: contar personas
  // en vez de tecleos en el ranking, y descartar el mismo término repetido
  // por el mismo dispositivo en segundos.
  app.post('/api/search/track', (req, res) => {
    const { query, deviceId } = req.body || {};
    if (typeof query !== 'string') {
      return res.status(400).json({ error: 'query es obligatorio' });
    }
    db.recordSearchQuery(query, typeof deviceId === 'string' ? deviceId : null);
    res.status(204).end();
  });
}

/** Solo para tests: fuerza a que la próxima lectura recalcule el agregado. */
function _resetTrendingCacheForTests() {
  trendingCache = { data: null, expiresAt: 0, revision: -1 };
}

module.exports = { register, _resetTrendingCacheForTests };
