const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const multer = require('multer');
const { sellers, categories, updateSellerField } = require('../data');
const { requireAuth, optionalAuth } = require('../auth');
const db = require('../database');
const {
  validateName,
  validatePhone,
  validateBusinessDescription,
  validateBusinessCategory,
  validateBusinessHours,
  validateLocation,
  validatePaymentMethods,
  validateColorAcento,
  validateSocialUrl,
  validateWhatsappNumber,
} = require('../validation/sellerProfile');

const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');

const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.png';
      cb(null, `logo_${Date.now()}_${Math.random().toString(36).slice(2, 6)}${ext}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    cb(null, /\.(jpg|jpeg|png|gif|webp)$/i.test(path.extname(file.originalname)));
  },
});

function register(app) {
  app.get('/api/sellers', (_req, res) => {
    res.json(sellers);
  });

  // El email es privado: solo se incluye en la respuesta si quien pide el
  // perfil es el propio dueño (Bearer token cuyo sub coincide con :id).
  // El resto de campos, incluido phone, ya son públicos vía rowToSeller.
  // Métricas que se calculan al vuelo en vez de cachearse en la fila: la
  // racha cambia sola con el paso del tiempo (una semana sin publicar la
  // rompe sin que nadie escriba nada), así que un caché estaría mintiendo
  // hasta el siguiente evento que lo refrescara.
  function conMetricas(seller) {
    return {
      ...seller,
      rachaSemanas: db.computeRachaPublicaciones(seller.id),
      respondeRapido:
        seller.medianResponseMinutes !== null &&
        seller.medianResponseMinutes <= db.FEED_WEIGHTS.FAST_REPLY_MAX_MINUTES,
      // El producto fijado se verifica al leer: si se borró o ya no es del
      // vendedor, se devuelve null en vez de un ID colgante que el cliente
      // tendría que resolver a una tarjeta vacía.
      productoFijadoId: productoFijadoVigente(seller),
    };
  }

  function productoFijadoVigente(seller) {
    if (!seller.productoFijadoId) return null;
    const row = db.getDb()
      .prepare('SELECT seller FROM products WHERE id = ?')
      .get(seller.productoFijadoId);
    return row && row.seller === seller.id ? seller.productoFijadoId : null;
  }

  app.get('/api/sellers/:id', optionalAuth, (req, res) => {
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });
    if (req.user && req.user.id === seller.id) {
      const rawRow = db.getDb().prepare('SELECT email FROM sellers WHERE id = ?').get(seller.id);
      return res.json({ ...conMetricas(seller), email: rawRow.email || null });
    }
    res.json(conMetricas(seller));
  });

  // PATCH /api/sellers/:id — editar el propio perfil (usuario o negocio).
  // Campos de usuario: name, phone. Campos exclusivos de negocio
  // (businessDescription, businessCategory): solo se aplican si isBusiness.
  app.patch('/api/sellers/:id', requireAuth, (req, res) => {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });

    const {
      name, phone, businessDescription, businessCategory, businessHours,
      locationLat, locationLng, paymentMethods, colorAcento, productoFijadoId,
      facebookUrl, instagramUrl, whatsappNumber, tiktokUrl, twitterUrl,
    } = req.body;

    // ─── Validar todo antes de escribir nada (evita estado a medias) ──
    if (name !== undefined) {
      const nameError = validateName(name);
      if (nameError) return res.status(400).json({ error: nameError });
    }
    const phoneError = validatePhone(phone);
    if (phoneError) return res.status(400).json({ error: phoneError });

    // Métodos de pago: a diferencia de horario/descripción/ubicación, esto
    // aplica a CUALQUIER vendedor (negocio o no) — no está gated por
    // isBusiness. Si se manda, debe quedar al menos 1 (no se permite vaciar
    // por completo desde edición de perfil).
    let normalizedPaymentMethods;
    if (paymentMethods !== undefined) {
      const paymentMethodsResult = validatePaymentMethods(paymentMethods, { required: true });
      if (paymentMethodsResult.error) return res.status(400).json({ error: paymentMethodsResult.error });
      normalizedPaymentMethods = paymentMethodsResult.value;
    }

    // Personalización del perfil. A diferencia de descripción/horario, NO
    // está restringida a negocios: cualquier vendedor puede elegir su color
    // y fijar una publicación.
    const colorError = validateColorAcento(colorAcento);
    if (colorError) return res.status(400).json({ error: colorError });

    // Fijar exige ser dueño del producto. Sin esta comprobación, cualquiera
    // podría fijar la publicación de otro en su propio perfil y presentarla
    // como suya.
    if (productoFijadoId !== undefined && productoFijadoId !== null) {
      if (typeof productoFijadoId !== 'string') {
        return res.status(400).json({ error: 'productoFijadoId inválido' });
      }
      const producto = db.getDb()
        .prepare('SELECT seller FROM products WHERE id = ?')
        .get(productoFijadoId);
      if (!producto) {
        return res.status(400).json({ error: 'La publicación no existe' });
      }
      if (producto.seller !== seller.id) {
        return res.status(403).json({ error: 'Esa publicación no es tuya' });
      }
    }

    let normalizedHours;
    let normalizedLocation;
    let normalizedFacebook, normalizedInstagram, normalizedTiktok, normalizedTwitter, normalizedWhatsapp;
    // La ubicación de perfil (Nivel 1) es exclusiva de negocios, igual que
    // horario/descripción/categoría: un usuario normal no puede guardarla
    // mandando estos campos manualmente al endpoint.
    if (seller.isBusiness) {
      const descriptionError = validateBusinessDescription(businessDescription);
      if (descriptionError) return res.status(400).json({ error: descriptionError });
      const categoryIds = categories.map(c => c.id);
      const categoryError = validateBusinessCategory(businessCategory, categoryIds);
      if (categoryError) return res.status(400).json({ error: categoryError });
      if (businessHours !== undefined) {
        const hoursResult = validateBusinessHours(businessHours);
        if (hoursResult.error) return res.status(400).json({ error: hoursResult.error });
        normalizedHours = hoursResult.value;
      }
      if (locationLat !== undefined || locationLng !== undefined) {
        const locationResult = validateLocation(locationLat, locationLng);
        if (locationResult.error) return res.status(400).json({ error: locationResult.error });
        normalizedLocation = locationResult.value; // { lat, lng } o null (borra la ubicación)
      }
      if (facebookUrl !== undefined) {
        const r = validateSocialUrl('facebook', facebookUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedFacebook = r.value;
      }
      if (instagramUrl !== undefined) {
        const r = validateSocialUrl('instagram', instagramUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedInstagram = r.value;
      }
      if (tiktokUrl !== undefined) {
        const r = validateSocialUrl('tiktok', tiktokUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedTiktok = r.value;
      }
      if (twitterUrl !== undefined) {
        const r = validateSocialUrl('twitter', twitterUrl);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedTwitter = r.value;
      }
      if (whatsappNumber !== undefined) {
        const r = validateWhatsappNumber(whatsappNumber);
        if (r.error) return res.status(400).json({ error: r.error });
        normalizedWhatsapp = r.value;
      }
    }

    // ─── Aplicar cambios ────────────────────────────────────────────
    if (name !== undefined) {
      const trimmedName = name.trim();
      updateSellerField(seller.id, 'name', trimmedName);
      const initials = trimmedName.split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase();
      updateSellerField(seller.id, 'avatarInitials', initials);
    }
    if (phone !== undefined) {
      updateSellerField(seller.id, 'phone', phone.trim());
    }
    if (normalizedPaymentMethods !== undefined) {
      updateSellerField(seller.id, 'paymentMethods', JSON.stringify(normalizedPaymentMethods));
    }
    if (colorAcento !== undefined) {
      // null limpia el campo y devuelve el perfil al color de marca.
      updateSellerField(seller.id, 'colorAcento', colorAcento);
    }
    if (productoFijadoId !== undefined) {
      updateSellerField(seller.id, 'producto_fijado_id', productoFijadoId);
    }
    if (seller.isBusiness) {
      if (businessDescription !== undefined) {
        updateSellerField(seller.id, 'businessDescription', businessDescription.trim());
      }
      if (businessCategory !== undefined) {
        updateSellerField(seller.id, 'businessCategory', businessCategory);
      }
      if (normalizedHours !== undefined) {
        updateSellerField(seller.id, 'businessHours', JSON.stringify(normalizedHours));
      }
      if (normalizedLocation !== undefined) {
        updateSellerField(seller.id, 'location_lat', normalizedLocation ? normalizedLocation.lat : null);
        updateSellerField(seller.id, 'location_lng', normalizedLocation ? normalizedLocation.lng : null);
      }
      if (normalizedFacebook !== undefined) {
        updateSellerField(seller.id, 'facebook_url', normalizedFacebook);
      }
      if (normalizedInstagram !== undefined) {
        updateSellerField(seller.id, 'instagram_url', normalizedInstagram);
      }
      if (normalizedTiktok !== undefined) {
        updateSellerField(seller.id, 'tiktok_url', normalizedTiktok);
      }
      if (normalizedTwitter !== undefined) {
        updateSellerField(seller.id, 'twitter_url', normalizedTwitter);
      }
      if (normalizedWhatsapp !== undefined) {
        updateSellerField(seller.id, 'whatsapp_number', normalizedWhatsapp);
      }
    }

    const updated = sellers.find(s => s.id === req.params.id);
    const rawRow = db.getDb().prepare('SELECT phone, email FROM sellers WHERE id = ?').get(req.params.id);
    res.json({ ...conMetricas(updated), phone: rawRow.phone || null, email: rawRow.email || null });
  });

  // Borra un archivo de /uploads referenciado por una URL pública tipo
  // "/uploads/xxx.webp", sin lanzar si ya no existe (best-effort).
  function deleteUploadedFile(publicUrl) {
    if (!publicUrl || !publicUrl.startsWith('/uploads/')) return;
    const filePath = path.join(UPLOADS_DIR, path.basename(publicUrl));
    fs.unlink(filePath, (err) => {
      if (err && err.code !== 'ENOENT') {
        console.error('Error eliminando archivo huérfano:', filePath, err.message);
      }
    });
  }

  // POST /api/sellers/:id/logo – subir logo del negocio (multipart, dueño-only)
  app.post('/api/sellers/:id/logo', requireAuth, (req, res) => {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });

    upload.single('logo')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: 'Error al subir logo: ' + err.message });
      }
      if (!req.file) {
        return res.status(400).json({ error: 'No se envió ningún archivo' });
      }

      const previousLogoUrl = seller.logoUrl;

      // Convertir a WebP
      const parsed = path.parse(req.file.path);
      const webpPath = path.join(parsed.dir, parsed.name + '.webp');
      const publicUrl = '/uploads/' + parsed.name + '.webp';

      sharp(req.file.path)
        .resize(256, 256, { fit: 'cover' })
        .webp({ quality: 80 })
        .toFile(webpPath)
        .then(() => {
          fs.unlinkSync(req.file.path);
          updateSellerField(seller.id, 'logoUrl', publicUrl);
          deleteUploadedFile(previousLogoUrl);
          res.json(sellers.find(s => s.id === seller.id));
        })
        .catch((convErr) => {
          console.error('Error convirtiendo logo a WebP:', convErr);
          // Fallback: usar la ruta original (el archivo subido sí existe en disco)
          const fallbackUrl = '/uploads/' + path.basename(req.file.path);
          updateSellerField(seller.id, 'logoUrl', fallbackUrl);
          deleteUploadedFile(previousLogoUrl);
          res.json(sellers.find(s => s.id === seller.id));
        });
    });
  });
}

module.exports = { register };
