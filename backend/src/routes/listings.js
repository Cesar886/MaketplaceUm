const { ownListings, categories, sellers } = require('../data');

function register(app) {
  app.get('/api/listings', (_req, res) => {
    const enriched = ownListings.map(l => ({
      ...l,
      categoryObj: categories.find(c => c.id === l.category) || null,
      sellerObj: sellers.find(s => s.id === l.seller) || null,
    }));
    res.json(enriched);
  });
}

module.exports = { register };
