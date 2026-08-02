const path = require('path');
const fs = require('fs');
const sharp = require('sharp');
const multer = require('multer');
const { sellers, saveData, updateSellerField } = require('../data');
const { requireAuth } = require('../auth');

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

  app.get('/api/sellers/:id', (req, res) => {
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });
    res.json(seller);
  });

  // PATCH /api/sellers/:id — editar nombre/teléfono del propio perfil
  app.patch('/api/sellers/:id', requireAuth, (req, res) => {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });

    const { name, phone } = req.body;
    if (typeof name === 'string' && name.trim()) {
      updateSellerField(seller.id, 'name', name.trim());
      const initials = name.trim().split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase();
      updateSellerField(seller.id, 'avatarInitials', initials);
    }
    if (typeof phone === 'string') {
      updateSellerField(seller.id, 'phone', phone.trim());
    }

    res.json(sellers.find(s => s.id === req.params.id));
  });

  // POST /api/sellers/:id/logo – subir logo del negocio (multipart)
  app.post('/api/sellers/:id/logo', (req, res) => {
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({ error: 'Vendedor no encontrado' });

    upload.single('logo')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: 'Error al subir logo: ' + err.message });
      }
      if (!req.file) {
        return res.status(400).json({ error: 'No se envió ningún archivo' });
      }

      // Convertir a WebP
      const parsed = path.parse(req.file.path);
      const webpPath = path.join(parsed.dir, parsed.name + '.webp');
      const publicUrl = '/uploads/' + parsed.name + '.webp';

      sharp(req.file.path)
        .resize(256, 256, { fit: 'cover' })
        .webp({ quality: 80 })
        .toFile(webpPath)
        .then(() => {
          // Eliminar original
          fs.unlinkSync(req.file.path);

          // Actualizar seller
          seller.logoUrl = publicUrl;
          saveData();
          res.json(seller);
        })
        .catch((convErr) => {
          console.error('Error convirtiendo logo a WebP:', convErr);
          // Fallback: usar ruta original
          seller.logoUrl = '/uploads/' + path.basename(req.file.path);
          saveData();
          res.json(seller);
        });
    });
  });
}

module.exports = { register };
