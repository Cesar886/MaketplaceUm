const { categories } = require('../data');

function register(app) {
  app.get('/api/categories', (_req, res) => {
    res.json(categories);
  });
}

module.exports = { register };
