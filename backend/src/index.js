const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const { generateToken, requireAuth } = require('./auth');
const { sellers, saveData, registerSeller, updateSellerField } = require('./data');

const routes = [
  require('./routes/categories'),
  require('./routes/products'),
  require('./routes/sellers'),
  require('./routes/cart'),
  require('./routes/listings'),
  require('./routes/highlightPlans'),
  require('./routes/notifications'),
  require('./routes/chat'),
  require('./routes/wanted'),
];

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
});

const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

// ─── Socket.IO ──────────────────────────────────────────────
// Compartir la instancia io para que las rutas puedan emitir eventos
app.set('io', io);

io.on('connection', (socket) => {
  console.log(`🟢 Cliente Socket.IO conectado: ${socket.id}`);

  // Unirse a una sala de conversación
  socket.on('join:conversation', (conversationId) => {
    socket.join(`conv:${conversationId}`);
    console.log(`  → ${socket.id} se unió a conv:${conversationId}`);
  });

  // Salir de una sala de conversación
  socket.on('leave:conversation', (conversationId) => {
    socket.leave(`conv:${conversationId}`);
    console.log(`  → ${socket.id} salió de conv:${conversationId}`);
  });

  // Indicador de escritura
  socket.on('typing:start', ({ conversationId, userId }) => {
    socket.to(`conv:${conversationId}`).emit('typing:start', { userId });
  });

  socket.on('typing:stop', ({ conversationId, userId }) => {
    socket.to(`conv:${conversationId}`).emit('typing:stop', { userId });
  });

  // Unirse a una sala personal para recibir notificaciones de nuevas conversaciones
  socket.on('register:user', (userId) => {
    socket.join(`user:${userId}`);
    console.log(`  → ${socket.id} registrado como user:${userId}`);
  });

  socket.on('disconnect', () => {
    console.log(`🔴 Cliente Socket.IO desconectado: ${socket.id}`);
  });
});

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
  res.json({ token, seller: { id: seller.id, name: seller.name, email: seller.email, phone: seller.phone, avatarInitials: seller.avatarInitials } });
});

// Register: crea un perfil de vendedor en el backend y devuelve un JWT
app.post('/api/auth/register', (req, res) => {
  const { name, email, phone, userType } = req.body;

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
    // Ya registrado: actualizar teléfono si cambió
    if (phone && phone.trim() !== existing.phone) {
      updateSellerField(existing.id, 'phone', phone.trim());
    }
    const token = generateToken(existing.id);
    return res.json({
      token,
      seller: { id: existing.id, name: existing.name, email: existing.email, phone: existing.phone, avatarInitials: existing.avatarInitials },
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
    email: email.trim(),
    phone: (phone || '').trim(),
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
    seller: { id: newSeller.id, name: newSeller.name, email: newSeller.email, phone: newSeller.phone, avatarInitials: newSeller.avatarInitials },
    created: true,
  });
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Mercadito UM API corriendo en http://localhost:${PORT}`);
});
