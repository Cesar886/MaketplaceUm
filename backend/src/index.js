const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const bcrypt = require('bcryptjs');
const { generateToken, requireAuth } = require('./auth');
const { sellers, saveData, registerSeller, updateSellerField } = require('./data');
const { validateName, validateEmail, validatePassword, validatePhone } = require('./validation/sellerProfile');

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
  require('./routes/feed'),
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

// Límite de intentos fallidos de login: tras LOGIN_MAX_ATTEMPTS seguidos,
// la cuenta se bloquea LOGIN_LOCKOUT_MINUTES para frenar fuerza bruta.
const LOGIN_MAX_ATTEMPTS = 8;
const LOGIN_LOCKOUT_MINUTES = 15;

// Login: valida email + password contra el hash guardado en el backend
// (bcrypt). El backend es la única autoridad real de credenciales — antes
// esto vivía solo en el SQLite local del dispositivo (sqflite), por lo que
// una cuenta registrada en un dispositivo/instalación no podía loguearse
// desde otro, aunque el email/password fueran correctos.
app.post('/api/auth/login', (req, res) => {
  const { email, password, deviceId } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'email y password son requeridos' });
  }

  const row = db.getDb()
    .prepare('SELECT * FROM sellers WHERE email = ? COLLATE NOCASE')
    .get(email.trim());

  // Cuenta bloqueada por demasiados intentos fallidos: ni siquiera se evalúa
  // el password mientras dure el bloqueo.
  if (row && row.locked_until && new Date(row.locked_until) > new Date()) {
    const minutesLeft = Math.ceil((new Date(row.locked_until) - new Date()) / 60000);
    return res.status(429).json({
      error: `Demasiados intentos fallidos. Intenta de nuevo en ${minutesLeft} minuto${minutesLeft === 1 ? '' : 's'}.`,
    });
  }

  const valid = row && row.password_hash && bcrypt.compareSync(password, row.password_hash);

  if (!valid) {
    // Solo se cuentan intentos sobre cuentas que existen: no hay nada que
    // bloquear para un email que no está registrado.
    if (row) {
      const attempts = (row.failed_login_attempts || 0) + 1;
      if (attempts >= LOGIN_MAX_ATTEMPTS) {
        const lockedUntil = new Date(Date.now() + LOGIN_LOCKOUT_MINUTES * 60 * 1000).toISOString();
        db.getDb()
          .prepare('UPDATE sellers SET failed_login_attempts = 0, locked_until = ? WHERE id = ?')
          .run(lockedUntil, row.id);
      } else {
        db.getDb()
          .prepare('UPDATE sellers SET failed_login_attempts = ? WHERE id = ?')
          .run(attempts, row.id);
      }
    }
    // Mismo mensaje genérico si el email no existe, el password no coincide,
    // o la cuenta es legacy sin password_hash: no se debe revelar cuál caso ocurrió.
    return res.status(401).json({ error: 'Correo o contraseña incorrectos' });
  }

  // Login exitoso: resetear el contador de intentos fallidos y el bloqueo.
  if (row.failed_login_attempts || row.locked_until) {
    db.getDb()
      .prepare('UPDATE sellers SET failed_login_attempts = 0, locked_until = NULL WHERE id = ?')
      .run(row.id);
  }

  if (deviceId) db.linkDeviceToUser(deviceId, row.id);
  const token = generateToken(row.id);
  res.json({
    token,
    seller: {
      id: row.id,
      name: row.name,
      email: row.email,
      phone: row.phone,
      avatarInitials: row.avatarInitials,
      isBusiness: !!row.isBusiness,
      major: row.major,
    },
  });
});

// Register: crea un perfil de vendedor en el backend (con password real)
// y devuelve un JWT.
app.post('/api/auth/register', (req, res) => {
  const { name, email, phone, userType, password, deviceId } = req.body;

  if (!email) {
    return res.status(400).json({ error: 'email es requerido' });
  }
  const nameError = validateName(name);
  if (nameError) return res.status(400).json({ error: nameError });
  const emailError = validateEmail(email);
  if (emailError) return res.status(400).json({ error: emailError });
  const phoneError = validatePhone(phone);
  if (phoneError) return res.status(400).json({ error: phoneError });
  const passwordError = validatePassword(password);
  if (passwordError) return res.status(400).json({ error: passwordError });

  // Verificar si ya existe un vendedor con este email. Se compara el correo
  // real (case-insensitive), no un slug derivado de la parte local: dos
  // emails distintos que compartan la parte local antes del "@" (distinto
  // dominio, por ejemplo) NO son la misma cuenta y no deben tratarse como tal.
  const existingRow = db.getDb()
    .prepare('SELECT * FROM sellers WHERE email = ? COLLATE NOCASE')
    .get(email.trim());
  if (existingRow) {
    if (existingRow.password_hash) {
      // Ya tiene password real: "registrarse" de nuevo con este email es,
      // de facto, un intento de login. Si el password no coincide, no se
      // puede tomar la cuenta de otra persona con solo saber su correo.
      if (!bcrypt.compareSync(password, existingRow.password_hash)) {
        return res.status(409).json({ error: 'Ya existe una cuenta con este correo.' });
      }
    } else {
      // Cuenta legacy: se creó antes de que el backend guardara password
      // (bug de auth anterior). Se backfillea con el password recién dado.
      const hash = bcrypt.hashSync(password, 10);
      updateSellerField(existingRow.id, 'password_hash', hash);
    }
    // Ya registrado: actualizar teléfono si cambió
    if (phone && phone.trim() !== existingRow.phone) {
      updateSellerField(existingRow.id, 'phone', phone.trim());
      existingRow.phone = phone.trim();
    }
    // Vincula el historial anónimo de este dispositivo a la cuenta existente
    // (p. ej. reinstaló la app y "registró" de nuevo el mismo email).
    if (deviceId) db.linkDeviceToUser(deviceId, existingRow.id);
    const token = generateToken(existingRow.id);
    return res.json({
      token,
      seller: {
        id: existingRow.id,
        name: existingRow.name,
        email: existingRow.email,
        phone: existingRow.phone,
        avatarInitials: existingRow.avatarInitials,
        isBusiness: !!existingRow.isBusiness,
        major: existingRow.major,
      },
      created: false,
    });
  }

  // Generar un ID único basado en el email (parte local + hash corto).
  // Es solo un identificador legible; la unicidad real de cuenta la
  // garantiza el chequeo de email de arriba + el índice UNIQUE en DB.
  const emailSlug = email.split('@')[0].replace(/[^a-zA-Z0-9]/g, '').toLowerCase();
  const suffix = Math.random().toString(36).slice(2, 6);
  const sellerId = `u_${emailSlug}_${suffix}`;

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
    password_hash: bcrypt.hashSync(password, 10),
  };

  registerSeller(newSeller);

  // Vincula el historial anónimo acumulado bajo este deviceId (favoritos,
  // vistas, contactos) a la cuenta recién creada, para no perder afinidad
  // de feed acumulada mientras el usuario navegaba sin sesión.
  if (deviceId) db.linkDeviceToUser(deviceId, newSeller.id);

  const token = generateToken(newSeller.id);
  res.status(201).json({
    token,
    seller: {
      id: newSeller.id,
      name: newSeller.name,
      email: newSeller.email,
      phone: newSeller.phone,
      avatarInitials: newSeller.avatarInitials,
      isBusiness: newSeller.isBusiness,
      major: newSeller.major,
    },
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

// Node cierra los sockets keep-alive inactivos a los 5s por defecto
// (server.keepAliveTimeout). La app fija http.Client() por el tiempo de vida
// del proceso y reutiliza esa conexión al volver a una pantalla tras estar
// inactiva >5s (ej. leyendo un producto), lo que provoca cierres de conexión
// a medio camino ("Connection closed before full header was received") de
// forma intermitente. Se sube a un valor holgado ya que no hay proxy
// intermedio (el cliente pega directo al puerto 3000) que imponga su propio
// límite. headersTimeout debe quedar por encima de keepAliveTimeout.
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;

// Política de limpieza de interacciones_dispositivo: al arrancar y luego
// una vez al día, para no acumular filas indefinidamente por dispositivos
// que abrieron la app una sola vez.
const db = require('./database');
db.limpiarInteraccionesAntiguas();
setInterval(() => db.limpiarInteraccionesAntiguas(), 24 * 60 * 60 * 1000);
