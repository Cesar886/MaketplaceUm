const { sellers } = require('../data');

function register(app) {
  app.get('/api/sellers', (_req, res) => {
    res.json(sellers);
  });

  app.get('/api/sellers/:id', (req, res) => {
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });
    res.json(seller);
  });
}

module.exports = { register };
