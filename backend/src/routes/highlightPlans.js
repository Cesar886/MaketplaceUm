const { highlightPlans } = require('../data');

function register(app) {
  app.get('/api/highlight-plans', (_req, res) => {
    res.json(highlightPlans);
  });
}

module.exports = { register };
