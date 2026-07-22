const express = require('express');
const cors = require('cors');
const path = require('path');
const multer = require('multer');
const { generateToken, requireAuth } = require('./auth');
const { sellers } = require('./data');

const routes = [
  require('./routes/categories'),
  require('./routes/products'),
  require('./routes/sellers'),
  require('./routes/cart'),
  require('./routes/listings'),
  require('./routes/highlightPlans'),
];

const app = express();
const PORT = process.env.PORT || 3000;

// ─── Configuración de multer para subida de imágenes ──────
const UPLOADS_DIR = path.join(__dirname, '..', 'uploads');
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `product_${Date.now()}_${Math.random().toString(36).slice(2, 6)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB por imagen
  fileFilter: (_req, file, cb) => {
    const allowed = /\.(jpg|jpeg|png|gif|webp)$/i;
    cb(null, allowed.test(path.extname(file.originalname)));
  },
});

// Middleware
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(UPLOADS_DIR));
app.set('upload', upload); // exponer multer a las rutas

// Registrar rutas
for (const route of routes) {
  route.register(app);
}

// ─── Auth ──────────────────────────────────────────────────
// Login: cualquier seller registrado puede obtener un token
app.post('/api/auth/login', (req, res) => {
  const { sellerId } = req.body;
  if (!sellerId) {
    return res.status(400).json({ error: 'sellerId es requerido' });
  }
  const seller = sellers.find(s => s.id === sellerId);
  if (!seller) {
    return res.status(404).json({ error: 'Vendedor no encontrado' });
  }
  const token = generateToken(seller.id);
  res.json({ token, seller: { id: seller.id, name: seller.name, avatarInitials: seller.avatarInitials } });
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Mercadito UM API corriendo en http://localhost:${PORT}`);
});
