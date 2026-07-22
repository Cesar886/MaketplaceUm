const { requireAuth } = require('../auth');
const { cart, products, saveData } = require('../data');

function register(app) {
  // GET /api/cart
  app.get('/api/cart', (_req, res) => {
    const enriched = cart.map(item => ({
      ...item,
      product: products.find(p => p.id === item.productId) || null,
    }));
    res.json(enriched);
  });

  // POST /api/cart – agregar item
  app.post('/api/cart', requireAuth, (req, res) => {
    const { productId, quantity, meetingPoint } = req.body;
    if (!productId || !quantity) {
      return res.status(400).json({ error: 'productId y quantity son requeridos' });
    }

    const existing = cart.find(item => item.productId === productId);
    if (existing) {
      existing.quantity += quantity;
      if (meetingPoint) existing.meetingPoint = meetingPoint;
    } else {
      cart.push({
        id: `c${Date.now()}`,
        productId,
        quantity,
        meetingPoint: meetingPoint || 'Por definir',
      });
    }

    saveData();
    const enriched = cart.map(item => ({
      ...item,
      product: products.find(p => p.id === item.productId) || null,
    }));
    res.status(201).json(enriched);
  });

  // PUT /api/cart/:id
  app.put('/api/cart/:id', requireAuth, (req, res) => {
    const item = cart.find(i => i.id === req.params.id);
    if (!item) return res.status(404).json({ error: 'Item no encontrado' });

    if (req.body.quantity != null) item.quantity = req.body.quantity;
    if (req.body.meetingPoint) item.meetingPoint = req.body.meetingPoint;
    saveData();

    const enriched = cart.map(i => ({
      ...i,
      product: products.find(p => p.id === i.productId) || null,
    }));
    res.json(enriched);
  });

  // DELETE /api/cart/:id
  app.delete('/api/cart/:id', requireAuth, (req, res) => {
    const idx = cart.findIndex(i => i.id === req.params.id);
    if (idx === -1) return res.status(404).json({ error: 'Item no encontrado' });
    cart.splice(idx, 1);
    saveData();
    res.json({ ok: true });
  });
}

module.exports = { register };
