const {
  categories
} = require('../data');
const db = require('../database');
const {
  optionalAuth
} = require('../auth');
const {
  ATRIBUTOS_GENERALES,
  ATRIBUTOS_POR_CATEGORIA,
  ATRIBUTOS_DESTACADOS,
  GENERALES_EXCLUIDAS
} = require('../config/atributosCategoria');
function register(app) {
  app.get('/api/categories', (_req, res) => {
    res.json(categories);
  });

  // GET /api/categories/atributos — el catálogo de preguntas dinámicas.
  //
  // El formulario de publicar NO depende de este endpoint: Flutter tiene su
  // propio espejo de la config (lib/constants/atributos_categoria.dart) y
  // pinta el form sin red, igual que hace con las categorías. Esto existe
  // para lo que sí necesita la versión del servidor: una UI de filtros que
  // quiera construir las facetas sin recompilar la app, y para poder
  // verificar desde afuera qué está aceptando el servidor hoy.
  //
  // `generales` NO aplica entero a toda categoría: hay que restarle
  // `generalesExcluidas[categoria]` (y con ella los condicionales que
  // cuelguen de una key excluida). Quien arme facetas con esto y omita esa
  // resta ofrecería filtrar comida por "acepta devoluciones", que ninguna
  // publicación de comida puede responder.
  app.get('/api/categories/atributos', (_req, res) => {
    res.json({
      generales: ATRIBUTOS_GENERALES,
      generalesExcluidas: GENERALES_EXCLUIDAS,
      porCategoria: ATRIBUTOS_POR_CATEGORIA,
      destacados: ATRIBUTOS_DESTACADOS
    });
  });

  // GET /api/categories/ranked — todas las categorías ordenadas por
  // engagement reciente (ver database.js: getCategoriesRanked). Home y
  // búsqueda consumen este mismo endpoint para pintar los íconos en el
  // mismo orden.
  app.get('/api/categories/ranked', async (_req, res) => {
    res.json(await db.getCategoriesRanked());
  });

  // POST /api/categories/:id/tap — registra que se tocó el ícono de una
  // categoría (señal de interés/curiosidad, peso bajo). Fire-and-forget:
  // el tracking nunca debe fallar de forma visible para el cliente.
  //
  // Escribe en dos sitios porque el mismo gesto alimenta dos cosas distintas
  // y una sola llamada desde la app evita que se desincronicen:
  //
  //   - category_engagement_events: agregado global y anónimo, ordena los
  //     íconos de categoría para toda la comunidad.
  //   - interacciones_dispositivo: la señal PERSONAL, que puntúa el interés
  //     de quien tocó y puede acabar en un push de publicaciones nuevas.
  //
  // Lo segundo solo ocurre si viene `deviceId`: sin él no hay a quién
  // atribuir la señal, y la parte global se registra igual.
  app.post('/api/categories/:id/tap', optionalAuth, async (req, res) => {
    const category = categories.find(c => c.id === req.params.id);
    if (category) {
      await db.trackCategoryEngagement(category.id, 'icon_tap');
      const deviceId = req.body?.deviceId;
      if (deviceId) {
        await db.registrarInteraccion({
          deviceId,
          userId: req.user ? req.user.id : null,
          productId: null,
          category: category.id,
          tipo: 'categoria'
        });
      }
    }
    res.status(204).end();
  });
}
module.exports = {
  register
};
