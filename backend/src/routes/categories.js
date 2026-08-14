const { categories } = require('../data');
const db = require('../database');
const {
  ATRIBUTOS_GENERALES,
  ATRIBUTOS_POR_CATEGORIA,
  ATRIBUTOS_DESTACADOS,
  GENERALES_EXCLUIDAS,
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
      destacados: ATRIBUTOS_DESTACADOS,
    });
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
