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
  app.get('/api/sellers/:id', optionalAuth, (req, res) => {
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });
    if (req.user && req.user.id === seller.id) {
      const rawRow = db.getDb().prepare('SELECT email FROM sellers WHERE id = ?').get(seller.id);
      return res.json({ ...seller, email: rawRow.email || null });
    }
    res.json(seller);
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

    const { name, phone, businessDescription, businessCategory, businessHours } = req.body;

    // ─── Validar todo antes de escribir nada (evita estado a medias) ──
    if (name !== undefined) {
      const nameError = validateName(name);
      if (nameError) return res.status(400).json({ error: nameError });
    }
    const phoneError = validatePhone(phone);
    if (phoneError) return res.status(400).json({ error: phoneError });

    let normalizedHours;
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
    }

    const updated = sellers.find(s => s.id === req.params.id);
    const rawRow = db.getDb().prepare('SELECT phone, email FROM sellers WHERE id = ?').get(req.params.id);
    res.json({ ...updated, phone: rawRow.phone || null, email: rawRow.email || null });
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
