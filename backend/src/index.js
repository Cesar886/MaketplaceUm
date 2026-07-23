const express = require('express');
const cors = require('cors');
const path = require('path');
const { generateToken, requireAuth } = require('./auth');
const { sellers, saveData, registerSeller } = require('./data');

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

// Middleware
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

// Registrar rutas
for (const route of routes) {
  route.register(app);
}

// ─── Auth ──────────────────────────────────────────────────

/**
 * Calcula iniciales a partir de un nombre.
 * Ej: "Daniel Perez" → "DP", "SanksUm" → "SU"
 */
function computeInitials(name) {
  if (!name) return '??';
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return parts.map(w => w[0]).join('').slice(0, 2).toUpperCase();
}

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

// Register: crea un perfil de vendedor en el backend y devuelve un JWT
app.post('/api/auth/register', (req, res) => {
  const { name, email, userType } = req.body;

  if (!name || !email) {
    return res.status(400).json({ error: 'name y email son requeridos' });
  }

  // Generar un ID único basado en el email (parte local + hash corto)
  const emailSlug = email.split('@')[0].replace(/[^a-zA-Z0-9]/g, '').toLowerCase();
  const suffix = Math.random().toString(36).slice(2, 6);
  const sellerId = `u_${emailSlug}_${suffix}`;

  // Verificar si ya existe un vendedor con este email (por el slug)
  const existing = sellers.find(s => s.id.startsWith(`u_${emailSlug}_`));
  if (existing) {
    // Ya registrado, devolver token directamente
    const token = generateToken(existing.id);
    return res.json({
      token,
      seller: { id: existing.id, name: existing.name, avatarInitials: existing.avatarInitials },
      created: false,
    });
  }

  // Determinar major/carrera según tipo de cuenta
  let major = '';
  if (userType === 'estudiante') major = 'Estudiante';
  else if (userType === 'negocio') major = 'Negocio • Establecimiento';
  else if (userType === 'particular') major = 'Particular';

  const newSeller = {
    id: sellerId,
    name: name.trim(),
    avatarInitials: computeInitials(name),
    major,
    isBusiness: userType === 'negocio',
    rating: 0,
    reviews: 0,
    verified: false,
  };

  registerSeller(newSeller);

  const token = generateToken(newSeller.id);
  res.status(201).json({
    token,
    seller: { id: newSeller.id, name: newSeller.name, avatarInitials: newSeller.avatarInitials },
    created: true,
  });
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Mercadito UM API corriendo en http://localhost:${PORT}`);
});
