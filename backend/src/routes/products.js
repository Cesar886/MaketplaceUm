const { requireAuth } = require('../auth');
const { products, sellers, categories, saveData } = require('../data');

function attachRelations(productsList) {
  return productsList.map(p => ({
    ...p,
    sellerObj: sellers.find(s => s.id === p.seller) || null,
    categoryObj: categories.find(c => c.id === p.category) || null,
  }));
}

function register(app) {
  // GET /api/products – listar con filtros
  app.get('/api/products', (req, res) => {
    const { category, featured, offer, search, seller } = req.query;
    let filtered = [...products];

    if (category) {
      filtered = filtered.filter(p => p.category === category);
    }
    if (featured === 'true') {
      filtered = filtered.filter(p => p.isFeatured);
    }
    if (offer === 'true') {
      filtered = filtered.filter(p => p.isOffer);
    }
    if (seller) {
      filtered = filtered.filter(p => p.seller === seller);
    }
    if (search) {
      const q = search.toLowerCase();
      filtered = filtered.filter(p =>
        p.title.toLowerCase().includes(q) ||
        p.description.toLowerCase().includes(q)
      );
    }

    res.json(attachRelations(filtered));
  });

  // GET /api/products/:id – detalle
  app.get('/api/products/:id', (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({ error: 'Producto no encontrado' });
    res.json(attachRelations([product])[0]);
  });

  // POST /api/products – crear nuevo producto (con imágenes)
  const upload = req.app ? req.app.get('upload') : null; // fallback
  app.post('/api/products', requireAuth, (req, res, next) => {
    const uploadMw = req.app.get('upload');
    uploadMw.array('images', 5)(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: 'Error al subir imágenes: ' + err.message });
      }

      const { title, price, category, description, seller } = req.body;
      if (!title || !price || !category || !description) {
        return res.status(400).json({ error: 'Faltan campos requeridos (title, price, category, description)' });
      }

      // Guardar rutas de las imágenes subidas
      const images = (req.files || []).map(f => `/uploads/${f.filename}`);

      const newProduct = {
        id: `p${Date.now()}`,
        title,
        price,
        category,
        description,
        publishedAgo: 'Ahora mismo',
        seller: seller || 's1',
        images,                              // <-- URLs de imágenes reales
        imageIcon: images.length > 0 ? null : 'inventory_2',
        imageColor: '#607D8B',
        isFeatured: false,
        isOffer: false,
        isFavorite: false,
      };

      products.unshift(newProduct);
      saveData();
      res.status(201).json(attachRelations([newProduct])[0]);
    });
  });

  // PATCH /api/products/:id/favorite – toggle favorito
  app.patch('/api/products/:id/favorite', requireAuth, (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({ error: 'Producto no encontrado' });
    product.isFavorite = !product.isFavorite;
    saveData();
    res.json(attachRelations([product])[0]);
  });
}

module.exports = { register };
