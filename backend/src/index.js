// Fija la zona horaria del proceso a la del campus (América/Monterrey),
// sin importar en qué timezone esté configurado el host donde corra este
// servidor (muchos hosts cloud usan UTC por defecto). Todo el cálculo de
// disponibilidad por horario de negocio (computeProductStatus, Nivel 4) y
// otras comparaciones de fecha/hora en el código (día de la semana, reset
// diario de stock) usan `new Date()` en hora local del proceso — sin esto,
// "hora local" podía significar UTC en producción y desalinear la
// comparación contra los horarios que los negocios configuran pensando en
// hora de Monterrey. Debe ejecutarse antes de cualquier require que pueda
// crear un Date (por eso va como primera línea del archivo).
process.env.TZ = 'America/Monterrey';

// Credenciales y configuración desde backend/.env (SMTP, Twilio, JWT_SECRET,
// dominios institucionales). Va antes de cualquier require que lea
// process.env al cargarse — validation/verificacion.js y auth.js lo hacen.
// Si el archivo no existe, dotenv no falla: se usan los valores por defecto.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

// Confirmación de que el .env llegó al proceso. Va ANTES del require de
// auth.js a propósito: si JWT_SECRET falta, auth.js lanza al cargarse y sin
// esta línea el log no diría por qué. Nunca imprime el secreto, solo si está.
// Un secreto distinto entre restarts invalida todos los tokens ya emitidos,
// y ese fue justo el incidente de 2026-08.
console.log(
  `[boot] JWT_SECRET: ${process.env.JWT_SECRET ? 'OK' : 'FALTA'} — ` +
  `VERIFICATION_STUDENT_DOMAINS: ${process.env.VERIFICATION_STUDENT_DOMAINS || '(default)'}`,
);

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const bcrypt = require('bcryptjs');
const {
  generateSession,
  generateAnonToken,
  refreshSession,
  revokeRefreshToken,
  requireAuth,
  verificarToken,
  esCuentaDeGoogle,
} = require('./auth');
const {
  corsOrigin,
  adminCorsOrigin,
  securityHeaders,
  createAuthLimiters,
  createAnonymousSessionLimiter,
  configureProxy,
} = require('./security');
const { crearRegistroPresencia } = require('./presence');
const { sellers, saveData, registerSeller, updateSellerField } = require('./data');
const { validateName, validateEmail, validatePassword, validatePhone, validateBusinessHours, validatePaymentMethods } = require('./validation/sellerProfile');
const { getSellerAccess, sendSellerAccessError } = require('./sellerAccess');

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
  require('./routes/verificacion'),
  require('./routes/admin'),
  // El router heredado `/api/revision/*` aceptaba una llave compartida y
  // permitia evitar JWT, TOTP y la auditoria administrativa. La pagina
  // historica `/revision-8f4d9c2a` ya pasa por el BFF de Next y por
  // `/api/admin/revision/*`, asi que no se monta este segundo acceso en el
  // servidor de produccion. El modulo se conserva para reutilizar su logica
  // dentro de routes/admin.js y para las pruebas del flujo existente.
  require('./routes/public'),
  require('./routes/comments'),
  require('./routes/questions'),
  require('./routes/search'),
  require('./routes/clientErrors'),
  require('./routes/privacy'),
  require('./routes/secreto'),
  // Iniciar sesión / registrarse con Google. Responde 503 mientras falten
  // los Client ID en .env; el login con correo y contraseña no depende de él.
  require('./routes/authGoogle'),
  // Pagos con Mercado Pago (split payments). Aislado en su propia carpeta
  // para que sea fácil de auditar por separado; no arranca nada al cargarse
  // y responde 503 mientras falten credenciales en .env.
  require('./payments/routes'),
];

// Igual que el log de JWT_SECRET arriba: dice si los pagos están listos y,
// si no, exactamente qué falta — nunca los valores. Sin esto, una variable
// faltante (p.ej. MP_WEBHOOK_SECRET) solo se descubre cuando el webhook ya
// lleva rato fallando en silencio con 401 en producción.
{
  const { resumenSeguro } = require('./payments/config');
  const resumen = resumenSeguro();
  console.log(
    `[boot] Pagos (Mercado Pago): ${resumen.configurado ? 'OK' : 'SIN CONFIGURAR'}` +
    (resumen.configurado ? '' : ` — faltan: ${resumen.faltantes.join(', ')}`),
  );
}

const app = express();
configureProxy(app);
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: corsOrigin,
    methods: ['GET', 'POST'],
    credentials: false,
  },
});

const PORT = process.env.PORT || 3000;
const API_BIND_HOST = String(process.env.API_BIND_HOST || '127.0.0.1').trim();
if (!API_BIND_HOST || /[\u0000-\u001f\u007f/\\]/.test(API_BIND_HOST)) {
  throw new Error('API_BIND_HOST no es valido.');
}

// Middleware
app.disable('x-powered-by');
app.use(securityHeaders);
// El namespace administrativo tiene una política más estrecha que la API de
// la app. Se monta antes del CORS general para que hasta los preflight fallen
// cerrados salvo que el origen sea exactamente ADMIN_PANEL_ORIGIN.
app.use('/api/admin', cors({
  origin: adminCorsOrigin,
  methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  credentials: false,
  maxAge: 600,
}));
app.use(cors({ origin: corsOrigin, methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'], maxAge: 86400 }));
app.use(express.json({ limit: '1mb', strict: true }));
// Los archivos de /uploads son inmutables por construcción: el nombre lo
// genera multer como `product_${Date.now()}_${random}` en cada subida, así
// que cambiar la foto de un producto produce un archivo NUEVO con otra URL y
// la vieja nunca cambia de contenido. Eso es justo la precondición de
// `immutable`, y permite el año completo que recomienda el RFC 8246 en vez
// del `max-age=0` anterior — que obligaba a revalidar cada foto en cada
// scroll contra un servidor que entrega estáticos a ~20 KB/s.
app.use('/uploads', (req, res, next) => {
  const fileUrl = '/uploads/' + path.basename(req.path);
  const esEvidenciaPrivada = db.getDb().prepare(
    'SELECT 1 FROM verification_documents WHERE file_url = ? LIMIT 1',
  ).get(fileUrl);
  // Responder 404, no 401: la ruta pública no debe revelar ni siquiera que el
  // nombre corresponde a un documento de identidad. El panel usa su endpoint
  // autenticado /api/revision/documento.
  if (esEvidenciaPrivada) return res.status(404).end();
  return next();
});
app.use(
  '/uploads',
  express.static(path.join(__dirname, '..', 'uploads'), {
    maxAge: '365d',
    immutable: true,
  })
);

// ─── Socket.IO ──────────────────────────────────────────────
// Compartir la instancia io para que las rutas puedan emitir eventos
app.set('io', io);

// ─── Presencia ──────────────────────────────────────────────
// Quién está en línea se deduce de los sockets abiertos: no hace falta
// heartbeat ni columna persistida (ver presence.js y la migración 37).
//
// Los eventos viajan por salas `presence:<userId>`, no a los interlocutores
// uno por uno: así el detalle de un vendedor con el que aún no hay chat
// también recibe cambios en vivo, y el filtro de privacidad se aplica UNA
// vez —al suscribirse— en vez de en cada emisión.
const presencia = crearRegistroPresencia({
  guardarUltimaActividad: (userId, iso) => db.setUltimaActividad(userId, iso),
  emitirCambio: ({ userId, online, lastActive }) => {
    // Si el usuario oculta su estado nadie pudo suscribirse a su sala, pero
    // se comprueba igual: la preferencia puede haber cambiado mientras
    // había suscriptores vivos.
    if (!db.getPresencia(userId).comparteEstado) return;
    io.to(`presence:${userId}`).emit('presence:update', { userId, online, lastActive });
  },
});
app.set('presencia', presencia);

// El handshake es lo que autentica al socket, igual que el Bearer autentica
// una petición REST. Antes no había nada: `join:conversation` aceptaba
// cualquier id de cualquier socket anónimo, y a esa sala se emite el texto
// íntegro de cada mensaje (routes/chat.js). Bastaba con enumerar ids de
// conversación para leer el marketplace entero en vivo (hallazgo C-02).
//
// El token va en `auth` del handshake y no en la query: la query se escribe
// en los logs de acceso de cualquier proxy que haya delante.
//
// Se exige a TODO socket, incluidos los invitados — que desde ahora también
// tienen token (POST /api/auth/anon). Sin credencial no hay conexión, así
// que ninguna sala tiene que preguntarse si su socket tiene identidad.
io.use((socket, next) => {
  const token = socket.handshake.auth && socket.handshake.auth.token;
  const userId = verificarToken(token);
  if (!userId) {
    return next(new Error('UNAUTHORIZED'));
  }
  socket.data.userId = userId;
  next();
});

io.on('connection', (socket) => {
  console.log(`🟢 Cliente Socket.IO conectado: ${socket.id} (${socket.data.userId})`);

  // La presencia se enciende con la conexión: el token ya se validó en el
  // handshake, así que no hace falta un `register:user` que la reafirme.
  presencia.conectar(socket.data.userId, socket.id);
  socket.join(`user:${socket.data.userId}`);

  // Unirse a una sala de conversación, solo si se participa en ella.
  //
  // La pertenencia se consulta a la BD en cada intento y no se cachea: una
  // conversación cambia de participantes cuando se crea, y un socket puede
  // vivir horas.
  const validRealtimeId = value => typeof value === 'string'
    && value.length > 0 && value.length <= 180
    && !/[\u0000-\u001f\u007f]/.test(value);

  socket.on('join:conversation', (conversationId) => {
    if (!validRealtimeId(conversationId)) return;
    if (!db.esParticipanteDeConversacion(conversationId, socket.data.userId)) {
      console.warn(
        `[socket] ${socket.data.userId} intentó unirse a conv:${conversationId} sin participar en ella`,
      );
      return;
    }
    socket.join(`conv:${conversationId}`);
    console.log(`  → ${socket.id} se unió a conv:${conversationId}`);
  });

  // Salir de una sala de conversación
  socket.on('leave:conversation', (conversationId) => {
    if (!validRealtimeId(conversationId)) return;
    socket.leave(`conv:${conversationId}`);
    console.log(`  → ${socket.id} salió de conv:${conversationId}`);
  });

  // Indicador de escritura. El `userId` que se reemite es el del socket
  // autenticado y no el que venga en el payload: si no, cualquiera podría
  // hacer aparecer "Fulano está escribiendo…" en un chat ajeno.
  //
  // No hace falta comprobar pertenencia aquí porque `socket.to(sala)` solo
  // alcanza a una sala en la que este socket ya está, y entrar exige serlo.
  socket.on('typing:start', (payload = {}) => {
    const { conversationId } = payload;
    if (!validRealtimeId(conversationId)
        || !db.esParticipanteDeConversacion(conversationId, socket.data.userId)) return;
    socket.to(`conv:${conversationId}`).emit('typing:start', { userId: socket.data.userId });
  });

  socket.on('typing:stop', (payload = {}) => {
    const { conversationId } = payload;
    if (!validRealtimeId(conversationId)
        || !db.esParticipanteDeConversacion(conversationId, socket.data.userId)) return;
    socket.to(`conv:${conversationId}`).emit('typing:stop', { userId: socket.data.userId });
  });

  // Unirse a la sala de un producto: quien tenga abierto ese detalle recibe
  // los comentarios nuevos sin recargar (ver routes/comments.js). Mismo
  // patrón que las salas de conversación, con prefijo distinto para que un
  // id de producto y uno de conversación nunca colisionen en la misma sala.
  socket.on('join:product', (productId) => {
    if (!validRealtimeId(productId)) return;
    socket.join(`product:${productId}`);
    console.log(`  → ${socket.id} se unió a product:${productId}`);
  });

  socket.on('leave:product', (productId) => {
    if (!validRealtimeId(productId)) return;
    socket.leave(`product:${productId}`);
    console.log(`  → ${socket.id} salió de product:${productId}`);
  });

  // Compatibilidad con clientes ya instalados, que siguen emitiendo esto
  // tras conectar. Ya no hace nada: la sala personal y la presencia se
  // resuelven en la conexión, a partir del token del handshake.
  //
  // Antes este handler hacía `socket.join('user:' + userId)` ANTES de validar
  // el token y solo usaba la validación para decidir la presencia — de modo
  // que cualquiera podía entrar en la sala personal de otro y recibir sus
  // avisos de conversación con solo escribir su id (hallazgo C-02).
  socket.on('register:user', () => {});

  // Seguir el estado en línea de otro usuario (su fila en la lista de chats,
  // o su perfil abierto). La privacidad se resuelve aquí: si cualquiera de
  // los dos oculta su estado, la suscripción simplemente no se concede y el
  // cliente nunca recibe eventos de esa persona.
  socket.on('presence:subscribe', (userIds) => {
    const objetivos = (Array.isArray(userIds) ? userIds : [userIds]).slice(0, 100);
    const visorId = socket.data.userId;
    if (!visorId || !db.getPresencia(visorId).comparteEstado) return;

    const suscritos = [];
    const enLinea = [];
    for (const objetivoId of objetivos) {
      if (!validRealtimeId(objetivoId)) continue;
      if (!db.getPresencia(objetivoId).comparteEstado) continue;
      socket.join(`presence:${objetivoId}`);
      suscritos.push(objetivoId);
      if (presencia.estaEnLinea(objetivoId)) enLinea.push(objetivoId);
    }
    // Estado inicial en la misma vuelta: sin esto la pantalla se queda con lo
    // que trajo el REST hasta que alguien cambie de estado.
    //
    // Va `subscribed` además de `online` para que el cliente pueda APAGAR a
    // quien se fue mientras la app estaba en segundo plano: con solo la lista
    // de conectados no habría forma de distinguir "está offline" de "no
    // pregunté por él", y el punto verde se quedaría pegado.
    socket.emit('presence:snapshot', { subscribed: suscritos, online: enLinea });
  });

  socket.on('presence:unsubscribe', (userIds) => {
    const objetivos = (Array.isArray(userIds) ? userIds : [userIds]).slice(0, 100);
    for (const objetivoId of objetivos) {
      if (validRealtimeId(objetivoId)) socket.leave(`presence:${objetivoId}`);
    }
  });

  socket.on('disconnect', () => {
    console.log(`🔴 Cliente Socket.IO desconectado: ${socket.id}`);
    presencia.desconectar(socket.id);
  });
});

// Registrar rutas
for (const route of routes) {
  route.register(app);
}

// ─── Auth ──────────────────────────────────────────────────

// Iniciales del avatar por defecto. La implementación vive en
// utils/iniciales.js porque ahora también la usa el alta de cuentas con
// Google, y dos copias acabarían calculando iniciales distintas.
const { calcularIniciales: computeInitials } = require('./utils/iniciales');

// Límite de intentos fallidos de login: tras LOGIN_MAX_ATTEMPTS seguidos,
// la cuenta se bloquea LOGIN_LOCKOUT_MINUTES para frenar fuerza bruta.
const LOGIN_MAX_ATTEMPTS = 8;
const LOGIN_LOCKOUT_MINUTES = 15;

// Login: valida email + password contra el hash guardado en el backend
// (bcrypt). El backend es la única autoridad real de credenciales — antes
// esto vivía solo en el SQLite local del dispositivo (sqflite), por lo que
// una cuenta registrada en un dispositivo/instalación no podía loguearse
// desde otro, aunque el email/password fueran correctos.
const authLimiters = createAuthLimiters();

app.post('/api/auth/login', ...authLimiters, (req, res) => {
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
    // Una cuenta de Google no tiene contraseña que comparar, así que esto no
    // es un intento fallido: no se cuenta contra el bloqueo por fuerza bruta
    // (si no, tres toques al botón equivocado dejarían la cuenta bloqueada).
    // Decir el motivo aquí no filtra qué correos existen — quien pregunta ya
    // conoce el correo — y sin él el usuario reintentaría una contraseña que
    // nunca existió.
    if (esCuentaDeGoogle(row)) {
      return res.status(409).json({
        error: 'GOOGLE_ACCOUNT',
        message: 'Esa cuenta usa Google. Entra con el botón "Continuar con Google".',
      });
    }

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

  // La contraseña correcta prueba la identidad, pero no concede acceso por
  // sí sola: suspensión/baneo se valida justo antes de emitir una sesión.
  // Hacerlo después de bcrypt evita revelar por correo el estado de cuentas
  // a quien no demostró conocer su credencial.
  const accountAccess = getSellerAccess(db.getDb(), row.id);
  if (!accountAccess.allowed) return sendSellerAccessError(res, accountAccess);

  // Login exitoso: resetear el contador de intentos fallidos y el bloqueo.
  if (row.failed_login_attempts || row.locked_until) {
    db.getDb()
      .prepare('UPDATE sellers SET failed_login_attempts = 0, locked_until = NULL WHERE id = ?')
      .run(row.id);
  }

  if (deviceId) db.linkDeviceToUser(deviceId, row.id);
  const session = generateSession(row.id);
  res.json({
    ...session,
    seller: {
      id: row.id,
      name: row.name,
      email: row.email,
      phone: row.phone,
      avatarInitials: row.avatarInitials,
      isBusiness: !!row.isBusiness,
      major: row.major,
      // Rol verificado (ver widgets/user_role.dart). Null hasta que la
      // cuenta pase por verificación; el cliente omite la línea en ese caso.
      carrera: row.carrera || null,
      tipoVerificacion: row.tipo_verificacion || null,
    },
  });
});

// Register: crea un perfil de vendedor en el backend (con password real)
// y devuelve un JWT.
app.post('/api/auth/register', ...authLimiters, (req, res) => {
  const { name, email, phone, userType, password, deviceId, businessHours, paymentMethods } = req.body;

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

  let normalizedHours = {};
  if (userType === 'negocio' && businessHours !== undefined) {
    const hoursResult = validateBusinessHours(businessHours);
    if (hoursResult.error) return res.status(400).json({ error: hoursResult.error });
    normalizedHours = hoursResult.value;
  }


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
    } else if (esCuentaDeGoogle(existingRow)) {
      // Cuenta creada con Google: no tiene password_hash, pero NO es una
      // cuenta legacy a la que se le pueda poner una. Sin esta rama, saber
      // el correo de alguien que entró con Google bastaría para asignarle
      // una contraseña aquí y quedarse con su cuenta.
      return res.status(409).json({
        error: 'GOOGLE_ACCOUNT',
        message: 'Esa cuenta usa Google. Entra con el botón "Continuar con Google".',
      });
    }

    // Esta rama tambien funciona como login para cuentas existentes. Debe
    // compartir exactamente la misma puerta administrativa que /auth/login;
    // de lo contrario /auth/register seria un bypass de una suspension.
    const accountAccess = getSellerAccess(db.getDb(), existingRow.id);
    if (!accountAccess.allowed) return sendSellerAccessError(res, accountAccess);

    if (!existingRow.password_hash) {
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
    const session = generateSession(existingRow.id);
    return res.json({
      ...session,
      seller: {
        id: existingRow.id,
        name: existingRow.name,
        email: existingRow.email,
        phone: existingRow.phone,
        avatarInitials: existingRow.avatarInitials,
        isBusiness: !!existingRow.isBusiness,
        major: existingRow.major,
        carrera: existingRow.carrera || null,
        tipoVerificacion: existingRow.tipo_verificacion || null,
      },
      created: false,
    });
  }

  // Métodos de pago aceptados: obligatorio para toda cuenta nueva (negocio
  // o no), al menos 1 del catálogo fijo. Solo se exige aquí — la rama de
  // arriba (email ya existe) se comporta como login y no debe romperse por
  // un cliente viejo que no mande este campo.
  const paymentMethodsResult = validatePaymentMethods(paymentMethods, { required: true });
  if (paymentMethodsResult.error) return res.status(400).json({ error: paymentMethodsResult.error });

  // 'tarjeta' exige una cuenta de Mercado Pago conectada, y una cuenta que
  // se está creando en este mismo request todavía no puede tenerla: el OAuth
  // ocurre después, desde el perfil o el flujo de verificación. Aceptarlo
  // aquí dejaría el método puesto sin nada detrás.
  if ((paymentMethodsResult.value || []).includes('tarjeta')) {
    return res.status(400).json({
      error: 'Para aceptar tarjeta primero conecta tu cuenta de Mercado Pago desde tu perfil.',
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

  // `tipo_cuenta` es la columna canónica que consulta el sistema de
  // verificación, en vez de re-derivar el tipo desde `major` (una etiqueta
  // de UI) cada vez. Un userType desconocido cae a 'particular', el tipo
  // menos privilegiado.
  const tipoCuenta = ['estudiante', 'negocio', 'particular'].includes(userType)
    ? userType
    : 'particular';

  const newSeller = {
    id: sellerId,
    name: name.trim(),
    email: email.trim(),
    phone: (phone || '').trim(),
    avatarInitials: computeInitials(name),
    major,
    isBusiness: userType === 'negocio',
    businessHours: normalizedHours,
    paymentMethods: paymentMethodsResult.value,
    rating: 0,
    reviews: 0,
    verified: false,
    tipo_cuenta: tipoCuenta,
    password_hash: bcrypt.hashSync(password, 10),
  };

  registerSeller(newSeller);

  // Vincula el historial anónimo acumulado bajo este deviceId (favoritos,
  // vistas, contactos) a la cuenta recién creada, para no perder afinidad
  // de feed acumulada mientras el usuario navegaba sin sesión.
  if (deviceId) db.linkDeviceToUser(deviceId, newSeller.id);

  const session = generateSession(newSeller.id);
  res.status(201).json({
    ...session,
    seller: {
      id: newSeller.id,
      name: newSeller.name,
      email: newSeller.email,
      phone: newSeller.phone,
      avatarInitials: newSeller.avatarInitials,
      isBusiness: newSeller.isBusiness,
      major: newSeller.major,
      // Cuenta recién creada: aún no pasó por verificación, así que ambos
      // van explícitos en null en vez de ausentes.
      carrera: null,
      tipoVerificacion: null,
    },
    created: true,
  });
});

// Sesión de invitado: permite chatear sin cuenta (ver generateAnonToken).
//
// Sustituye al UUID que la app se generaba sola y mandaba como `senderId`.
// Aquel identificador lo elegía el cliente, así que el backend no tenía forma
// de distinguir al invitado legítimo de quien copiaba su id de un mensaje;
// éste lo emite y lo firma el servidor.
//
// Con límite por IP porque es el único endpoint que crea sesiones sin
// credencial alguna: sin freno, es una fuente gratuita de tokens válidos.
app.post(
  '/api/auth/anon',
  createAnonymousSessionLimiter(),
  (req, res) => {
    if (typeof req.body?.deviceId !== 'string'
        || !/^[A-Za-z0-9._:-]{8,180}$/.test(req.body.deviceId)) {
      return res.status(400).json({ error: 'Identificador de instalación inválido.' });
    }
    const { token, anonId } = generateAnonToken();
    res.status(201).json({ token, anonId });
  },
);

// Renueva el JWT de acceso usando la sesión persistente guardada en el
// dispositivo. El refresh token no caduca: solo deja de funcionar por logout
// o revocación explícita. Una rotación de JWT_SECRET no lo invalida.
app.post('/api/auth/refresh', (req, res) => {
  const renewed = refreshSession(req.body?.refreshToken);
  if (!renewed) {
    return res.status(401).json({
      error: 'SESSION_INVALIDATED',
      message: 'La sesión ya no está disponible.',
    });
  }
  return res.json({ token: renewed.token });
});

// Migra sin fricción las sesiones emitidas por versiones anteriores de la
// app: mientras su JWT viejo siga vigente, obtiene la credencial persistente
// una sola vez y queda dentro del flujo nuevo.
app.post('/api/auth/refresh/bootstrap', requireAuth, (req, res) => {
  res.json(generateSession(req.user.id));
});

app.post('/api/auth/logout', requireAuth, (req, res) => {
  if (req.user.jti && req.user.exp) {
    db.getDb().prepare(
      `INSERT OR REPLACE INTO revoked_sessions (jti, user_id, expires_at)
       VALUES (?, ?, ?)`,
    ).run(req.user.jti, req.user.id, req.user.exp);
  }
  revokeRefreshToken(req.body?.refreshToken, req.user.id);
  res.status(204).end();
});

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Respuestas uniformes: no filtrar stack traces, nombres de archivos ni
// detalles del parser al cliente.
app.use((req, res) => res.status(404).json({ error: 'Ruta no encontrada.' }));
app.use((error, _req, res, _next) => {
  const status = error.status === 403 ? 403
    : error.type === 'entity.too.large' ? 413
      : error instanceof SyntaxError && error.status === 400 ? 400 : 500;
  if (status === 500) console.error('[api] Error no controlado:', error);
  const message = status === 403 ? 'Origen no permitido.'
    : status === 413 ? 'La solicitud supera el limite permitido.'
      : status === 400 ? 'JSON invalido.' : 'Error interno del servidor.';
  res.status(status).json({ error: message });
});

server.listen(PORT, API_BIND_HOST, () => {
  console.log(`🚀 Marketplace UM API corriendo en http://${API_BIND_HOST}:${PORT}`);
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

// Desatora cuentas que quedaron esperando SOLO conectar Mercado Pago antes
// de apagar MERCADO_PAGO_HABILITADO (ver requisitosVerificacion.js). Solo al
// arrancar: no hace falta un intervalo porque después de esta pasada ya no
// quedan filas que reconciliar hasta el próximo despliegue.
require('./routes/verificacion').reconciliarVerificacionesPendientesPorMercadoPago();

// Retargeting por interés: cada 15 minutos se recalcula el score de interés
// y se avisa a quien corresponda de los productos publicados en la ventana.
//
// El intervalo es la ventana de agrupación: subirlo junta más publicaciones
// en un mismo aviso (menos pushes, menos inmediatez) y bajarlo hace lo
// contrario. No se ejecuta al arrancar a propósito: un reinicio no debe
// disparar una tanda de notificaciones fuera del ritmo normal.
const { ejecutarJobRetargeting } = require('./notifications/retargeting');
const RETARGETING_INTERVALO_MS = 15 * 60 * 1000;
setInterval(() => {
  ejecutarJobRetargeting().catch(err =>
    console.error('[retargeting] el job periódico falló:', err.message)
  );
}, RETARGETING_INTERVALO_MS);
