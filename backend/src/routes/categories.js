const { categories } = require('../data');
const db = require('../database');

function register(app) {
  app.get('/api/categories', (_req, res) => {
    res.json(categories);
  });

  // GET /api/categories/ranked — todas las categorías ordenadas por
  // engagement reciente (ver database.js: getCategoriesRanked). Home y
  // búsqueda consumen este mismo endpoint para pintar los íconos en el
  // mismo orden.
  app.get('/api/categories/ranked', (_req, res) => {
    res.json(db.getCategoriesRanked());
  });

  // POST /api/categories/:id/tap — registra que se tocó el ícono de una
  // categoría (señal de interés/curiosidad, peso bajo). Fire-and-forget:
  // el tracking nunca debe fallar de forma visible para el cliente.
  app.post('/api/categories/:id/tap', (req, res) => {
    const category = categories.find(c => c.id === req.params.id);
    if (category) {
      db.trackCategoryEngagement(category.id, 'icon_tap');
    }
    res.status(204).end();
  });
}

module.exports = { register };
