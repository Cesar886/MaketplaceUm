const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const { products, sellers, categories, saveData } = require('../data');
const { requireAuth } = require('../auth');
const db = require('../database');
const { sendPush } = require('../push');

// Configuración anti-abuso de ofertas
const COOLDOWN_HOURS = 72;

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
        isBusiness: false,
        logoUrl: null,
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
          const priceNum = Number(price);
          const validStatuses = ['available', 'reserved', 'sold', 'negotiating', 'paused', 'unavailable'];
          const status = req.body?.status || 'available';

          const newProduct = {
            id: productId,
            title,
            price: !isNaN(priceNum) && priceNum > 0 ? priceNum : 0,
            category,
            description,
            publishedAgo: 'Ahora mismo',
            seller: sellerId,
            images,
            imageIcon: images.length > 0 ? null : 'inventory_2',
            imageColor: '#607D8B',
            status: validStatuses.includes(status) ? status : 'available',
            extras: Array.isArray(req.body?.extras) ? req.body.extras.map(e => ({
              name: String(e.name || ''),
              extraPrice: Number(e.extraPrice) || 0,
            })).filter(e => e.name) : [],
            isFeatured: false,
            isOffer: false,
            isFavorite: false,
          };

          products.unshift(newProduct);
          saveData();

          // ─── Notificar a usuarios interesados en esta categoría ──
          const interestedUsers = db.getUsersInterestedInCategory(category);
          if (interestedUsers.length > 0) {
            // Filtrar al propio vendedor
            const notifyUsers = interestedUsers.filter(u => u !== sellerId);
            const categoryObj = categories.find(c => c.id === category);
            const catName = categoryObj?.name || category;

            for (const targetUserId of notifyUsers) {
              const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
              db.createNotification(
                notifId,
                targetUserId,
                'new_product',
                `Nuevo producto en ${catName}`,
                `${title} — $${priceNum}`,
                { productId, category }
              );
            }

            // Enviar push masivo a todos los interesados
            sendPush(
              notifyUsers,
              `Nuevo producto en ${catName}`,
              `${title} — $${priceNum}`,
              { productId, category, type: 'new_product' }
            );
          }

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

  // PATCH /api/products/:id/status – cambiar estado de disponibilidad (solo dueño)
  const VALID_STATUSES = ['available', 'reserved', 'sold', 'negotiating', 'paused', 'unavailable'];
  app.patch('/api/products/:id/status', requireAuth, (req, res) => {
    try {
      const product = products.find(p => p.id === req.params.id);
      if (!product) return res.status(404).json({ error: 'Producto no encontrado' });

      if (product.seller !== req.user.id) {
        return res.status(403).json({ error: 'No tienes permiso para cambiar el estado de este producto' });
      }

      const { status } = req.body;
      if (!status || !VALID_STATUSES.includes(status)) {
        return res.status(400).json({
          error: 'Estado inválido. Valores válidos: ' + VALID_STATUSES.join(', '),
        });
      }

      product.status = status;

      // Si se marca como vendido, la oferta expira automáticamente
      if (status === 'sold' && product.isOffer) {
        product.isOffer = false;
        product.previousPrice = null;
        product.discountLabel = null;
        product.offerExpiresAt = null;
      }

      saveData();
      res.json(attachRelations([product])[0]);
    } catch (err) {
      console.error('Error en PATCH /api/products/:id/status:', err);
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

  // PATCH /api/products/:id/featured – toggle destacado (solo el dueño)
  app.patch('/api/products/:id/featured', requireAuth, (req, res) => {
    const product = products.find(p => p.id === req.params.id);
    if (!product) return res.status(404).json({ error: 'Producto no encontrado' });

    if (product.seller !== req.user.id) {
      return res.status(403).json({ error: 'No tienes permiso para destacar este producto' });
    }

    product.isFeatured = !product.isFeatured;
    saveData();
    res.json(attachRelations([product])[0]);
  });

  // PATCH /api/products/:id – editar precio (solo el dueño)
  // Incluye: historial de precios, umbral mínimo 5%, rate limit, expiración de oferta
  app.patch('/api/products/:id', requireAuth, (req, res) => {
    try {
      const product = products.find(p => p.id === req.params.id);
      if (!product) return res.status(404).json({ error: 'Producto no encontrado' });

      if (product.seller !== req.user.id) {
        return res.status(403).json({ error: 'No tienes permiso para editar este producto' });
      }

      const { price } = req.body;

      // Solo procesamos si viene un precio (el endpoint es específico para editar precio)
      if (price === undefined) {
        return res.status(400).json({ error: 'El campo "price" es requerido' });
      }

      const newPrice = Number(price);

      // ─── Validaciones ──────────────────────────────────────
      if (!Number.isFinite(newPrice) || newPrice <= 0) {
        return res.status(400).json({ error: 'El precio debe ser un número positivo mayor a cero' });
      }

      // ─── Extras opcionales ─────────────────────────────────
      if (req.body.extras !== undefined) {
        product.extras = Array.isArray(req.body.extras) ? req.body.extras.map(e => ({
          name: String(e.name || ''),
          extraPrice: Number(e.extraPrice) || 0,
        })).filter(e => e.name) : [];
      }

      // ─── Rate limit: máximo 3 ediciones por hora ────────────
      const editsInLastHour = db.countPriceEditsLastHour(product.id);
      if (editsInLastHour >= 3) {
        return res.status(429).json({
          error: 'Has alcanzado el límite de ediciones de precio (3 por hora). Intenta más tarde.',
        });
      }

      const oldPrice = typeof product.price === 'number'
        ? product.price
        : parseFloat(String(product.price || '0').replace(/[^0-9.]/g, '')) || 0;

      // ─── Cooldown anti-abuso (72 horas) ──────────────────────
      // Revisar cuánto tiempo estuvo activo el precio anterior
      const lastChange = db.getLastPriceChange(product.id);
      let previousActiveHours = Infinity; // Si es el precio inicial sin historial previo

      if (lastChange && lastChange.changed_at) {
        const lastTime = new Date(lastChange.changed_at).getTime();
        previousActiveHours = (Date.now() - lastTime) / (1000 * 60 * 60);
      }

      const isCooldownPassed = previousActiveHours >= COOLDOWN_HOURS;

      // ─── Registrar en price_history el precio anterior ANTES de aplicar el nuevo ───
      db.insertPriceHistory(product.id, oldPrice);

      // ─── Calcular descuento contra el precio más alto de los últimos 30 días ──
      const highestIn30d = db.getHighestPriceInLastDays(product.id, 30);
      const referencePrice = Math.max(oldPrice, highestIn30d || 0);

      if (isCooldownPassed && newPrice < referencePrice && referencePrice > 0) {
        const discountPercent = Math.round((1 - newPrice / referencePrice) * 100);

        if (discountPercent >= 5) {
          // ✅ Activar oferta (cooldown cumplido)
          product.isOffer = true;
          product.previousPrice = referencePrice;
          product.discountLabel = `-${discountPercent}%`;
          const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
          product.offerExpiresAt = expiresAt;
        } else {
          product.isOffer = false;
          product.previousPrice = null;
          product.discountLabel = null;
          product.offerExpiresAt = null;
        }
      } else {
        // Cooldown NO cumplido o precio mayor/igual → no se marca como oferta
        product.isOffer = false;
        product.previousPrice = null;
        product.discountLabel = null;
        product.offerExpiresAt = null;
      }

      // ─── Actualizar precio y guardar ───────────────────────
      product.price = newPrice;
      product.publishedAgo = 'Editado ahora';
      saveData();

      // ─── Notificar push si el producto se marcó como oferta / bajada de precio ───
      if (product.isOffer) {
        const interestedUsers = db.getUsersInterestedInCategory(product.category);
        const notifyUsers = interestedUsers.filter(u => u !== req.user.id);
        if (notifyUsers.length > 0) {
          const notifTitle = `🔥 Bajó de precio: ${product.title}`;
          const notifBody = `¡Ahora a solo $${newPrice}! ${product.discountLabel || ''}`;
          for (const targetUserId of notifyUsers) {
            const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
            db.createNotification(notifId, targetUserId, 'price_drop', notifTitle, notifBody, { productId: product.id });
          }
          sendPush(notifyUsers, notifTitle, notifBody, { productId: product.id, type: 'price_drop' });
        }
      }

      res.json(attachRelations([product])[0]);
    } catch (err) {
      console.error('Error en PATCH /api/products/:id:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // POST /api/products/:id/rate – calificar un producto (anónimo o con sesión)
  app.post('/api/products/:id/rate', (req, res) => {
    try {
      const productId = req.params.id;
      const product = products.find(p => p.id === productId);
      if (!product) return res.status(404).json({ error: 'Producto no encontrado' });

      const { stars, userId } = req.body;
      if (!userId) return res.status(400).json({ error: 'userId es requerido' });
      if (!stars || stars < 1 || stars > 5) {
        return res.status(400).json({ error: 'stars debe ser un número entre 1 y 5' });
      }

      // No puedes calificar tu propio producto
      if (product.seller === userId) {
        return res.status(403).json({ error: 'No puedes calificar tu propio producto' });
      }

      db.upsertProductRating(productId, userId, stars);

      // Obtener stats actualizadas
      const stats = db.getProductRatingStats(productId);
      const userRating = db.getUserProductRating(productId, userId);

      // Actualizar rating del vendedor
      const sellerStats = db.getSellerRatingStats(product.seller);
      const sellerIndex = sellers.findIndex(s => s.id === product.seller);
      if (sellerIndex !== -1) {
        sellers[sellerIndex].rating = sellerStats.rating;
        sellers[sellerIndex].reviews = sellerStats.reviews;
      }

      // Notificar al vendedor de la nueva calificación por push
      if (product.seller && product.seller !== userId) {
        const notifTitle = `⭐ Nueva calificación`;
        const notifBody = `Calificaron tu producto "${product.title}" con ${stars} estrella${stars > 1 ? 's' : ''}`;
        const notifId = `notif_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
        db.createNotification(notifId, product.seller, 'rating', notifTitle, notifBody, { productId: product.id });
        sendPush([product.seller], notifTitle, notifBody, { productId: product.id, type: 'rating' });
      }

      const enriched = attachRelations([product])[0];
      enriched.productRating = stats.average;
      enriched.productReviews = stats.count;
      enriched.userRating = userRating;

      saveData();
      res.json(enriched);
    } catch (err) {
      console.error('Error en POST /api/products/:id/rate:', err);
      res.status(500).json({ error: err.message });
    }
  });

  // GET /api/products/:id/price-history – consultar historial y precio más bajo de 30 días
  app.get('/api/products/:id/price-history', (req, res) => {
    try {
      const productId = req.params.id;
      const product = products.find(p => p.id === productId);
      if (!product) return res.status(404).json({ error: 'Producto no encontrado' });

      const currentPrice = typeof product.price === 'number'
        ? product.price
        : parseFloat(String(product.price || '0').replace(/[^0-9.]/g, '')) || 0;

      const lowest30d = db.getLowestPriceInLastDays(productId, currentPrice, 30);
      const rawHistory = db.getPriceHistoryList(productId, 30);

      res.json({
        lowest_30d: lowest30d,
        current_price: currentPrice,
        history: rawHistory.map(h => ({
          price: h.price,
          changed_at: h.changed_at,
        })),
      });
    } catch (err) {
      console.error('Error en GET /api/products/:id/price-history:', err);
      res.status(500).json({ error: err.message });
    }
  });
}

module.exports = { register };
