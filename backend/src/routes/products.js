const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const { products, sellers, categories, saveData } = require('../data');
const { requireAuth } = require('../auth');

// ─── Helper para subir imágenes: usa multer directamente ────
const multer = require('multer');
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');
const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.jpg';
      cb(null, `product_${Date.now()}_${Math.random().toString(36).slice(2, 6)}${ext}`);
    },
  }),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    cb(null, /\.(jpg|jpeg|png|gif|webp)$/i.test(path.extname(file.originalname)));
  },
});

/**
 * Convierte una imagen a WebP usando sharp.
 * Borra el archivo original y devuelve la ruta pública del .webp.
 */
async function convertToWebp(filePath) {
  const parsed = path.parse(filePath);
  const webpPath = path.join(parsed.dir, parsed.name + '.webp');
  const publicPath = '/uploads/' + parsed.name + '.webp';

  await sharp(filePath)
    .webp({ quality: 80 })
    .toFile(webpPath);

  // Eliminar el archivo original
  fs.unlinkSync(filePath);

  return publicPath;
}

function attachRelations(productsList) {
  return productsList.map(p => ({
    ...p,
    sellerObj: sellers.find(s => s.id === p.seller) || (
      p.seller ? {
        id: p.seller,
        name: p.seller,
        avatarInitials: p.seller.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase(),
        major: '',
        rating: 0,
        reviews: 0,
        verified: false,
      } : null
    ),
    categoryObj: categories.find(c => c.id === p.category) || null,
  }));
}

function register(app) {
  // GET /api/products – listar con filtros
  app.get('/api/products', (req, res) => {
    const { category, featured, offer, search, seller } = req.query;
    let filtered = [...products];

    if (category) filtered = filtered.filter(p => p.category === category);
    if (featured === 'true') filtered = filtered.filter(p => p.isFeatured);
    if (offer === 'true') filtered = filtered.filter(p => p.isOffer);
    if (seller) filtered = filtered.filter(p => p.seller === seller);
    if (search) {
      const q = search.toLowerCase();
      filtered = filtered.filter(p =>
        p.title.toLowerCase().includes(q) || p.description.toLowerCase().includes(q));
    }
    res.json(attachRelations(filtered));
  });

  // GET /api/products/:id – detalle
  app.get('/api/products/:id', (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({ error: 'Producto no encontrado' });
    res.json(attachRelations([product])[0]);
  });

  // POST /api/products – crear nuevo producto (con imágenes opcionales)
  // Requiere autenticación; el vendedor se obtiene del JWT, no del body
  app.post('/api/products', requireAuth, (req, res) => {
    upload.any()(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: 'Error al procesar imágenes: ' + err.message });
      }

      const title = req.body?.title;
      const price = req.body?.price;
      const category = req.body?.category;
      const description = req.body?.description;

      if (!title || !price || !category || !description) {
        return res.status(400).json({ error: 'Faltan campos requeridos (title, price, category, description)' });
      }

      const sellerId = req.user.id;
      const productId = `p${Date.now()}`;

      // Convertir cada imagen a WebP usando Promise.all
      const conversionPromises = (req.files || []).map((file) => {
        return convertToWebp(file.path).catch((convErr) => {
          console.error('Error convirtiendo a WebP:', convErr);
          // Fallback: usar la ruta original si falla la conversión
          return '/uploads/' + path.basename(file.path);
        });
      });

      Promise.all(conversionPromises)
        .then((images) => {
          const newProduct = {
            id: productId,
            title,
            price,
            category,
            description,
            publishedAgo: 'Ahora mismo',
            seller: sellerId,
            images,
            imageIcon: images.length > 0 ? null : 'inventory_2',
            imageColor: '#607D8B',
            isFeatured: false,
            isOffer: false,
            isFavorite: false,
          };

          products.unshift(newProduct);
          saveData();
          res.status(201).json(attachRelations([newProduct])[0]);
        })
        .catch((err) => {
          console.error('Error en POST /api/products:', err);
          res.status(500).json({ error: err.message });
        });
    });
  });

  // DELETE /api/products/:id – eliminar producto (solo el dueño)
  app.delete('/api/products/:id', requireAuth, (req, res) => {
    try {
      const productId = req.params.id;
      const productIndex = products.findIndex(p => p.id === productId);

      if (productIndex === -1) {
        return res.status(404).json({ error: 'Producto no encontrado' });
      }

      const product = products[productIndex];

      if (product.seller !== req.user.id) {
        return res.status(403).json({ error: 'No tienes permiso para eliminar este producto' });
      }

      // Eliminar imágenes del disco
      if (product.images && product.images.length > 0) {
        for (const imgUrl of product.images) {
          const filename = path.basename(imgUrl);
          const filePath = path.join(UPLOADS_DIR, filename);
          if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
          }
        }
      }

      products.splice(productIndex, 1);
      saveData();
      res.json({ success: true, message: 'Producto eliminado' });
    } catch (err) {
      console.error('Error en DELETE /api/products/:id:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // PATCH /api/products/:id/favorite – toggle favorito
  app.patch('/api/products/:id/favorite', (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({ error: 'Producto no encontrado' });
    product.isFavorite = !product.isFavorite;
    saveData();
    res.json(attachRelations([product])[0]);
  });
}

module.exports = { register };
