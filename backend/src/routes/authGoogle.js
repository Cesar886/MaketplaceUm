// POST /api/auth/google — iniciar sesión o registrarse con Google.
//
// Emite EXACTAMENTE la misma sesión que /api/auth/login: el mismo JWT, la
// misma duración y el mismo objeto `seller`. Es deliberado — así el cliente
// no necesita una segunda ruta de "qué pasa después de loguearse", y no hay
// dos definiciones de sesión que se puedan desincronizar.
//
// Tres desenlaces posibles:
//
//   1. El correo (o el `google_sub`) ya tiene cuenta → 200, inicia sesión.
//   2. No tiene cuenta y el cliente no mandó `registro` → 404
//      GOOGLE_ACCOUNT_NOT_FOUND con el perfil de Google, para que la app
//      lleve al formulario de registro ya prellenado.
//   3. No tiene cuenta y el cliente sí mandó `registro` → 201, crea la
//      cuenta con las MISMAS validaciones que /api/auth/register.
//
// El caso 2 existe porque este marketplace no puede crear una cuenta solo
// con lo que da Google: el registro exige tipo de cuenta, teléfono y al
// menos un método de pago, y nada de eso viene en un idToken.

const express = require('express');
const rateLimit = require('express-rate-limit');

const dbModule = require('../database');
const { generateSession } = require('../auth');
const { getSellerAccess, sendSellerAccessError } = require('../sellerAccess');
const { calcularIniciales } = require('../utils/iniciales');
const googleAuth = require('../services/googleAuth');
const {
  validateName,
  validatePhone,
  validateBusinessHours,
  validatePaymentMethods,
} = require('../validation/sellerProfile');

/** Proveedor de autenticación de una cuenta creada con Google. */
const PROVEEDOR_GOOGLE = 'google';

/**
 * Cómo viaja un vendedor al cliente tras autenticarse. Idéntico al de
 * /api/auth/login — si un día cambia allá, tiene que cambiar aquí.
 */
function sellerParaCliente(row) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    phone: row.phone,
    avatarInitials: row.avatarInitials,
    isBusiness: !!row.isBusiness,
    major: row.major,
    carrera: row.carrera || null,
    tipoVerificacion: row.tipo_verificacion || null,
  };
}

/**
 * Rutas de Google Sign-In.
 *
 * Todo lo externo entra por parámetro para que los tests puedan correr
 * contra una base temporal y un "Google" falso: firmar un idToken con las
 * claves de Google desde un test no es posible.
 *
 * @param {object} deps
 * @param {() => import('better-sqlite3').Database} deps.getDb
 * @param {(idToken: string) => Promise<{sub,email,nombre,foto}>} deps.verificarIdToken
 * @param {(deviceId: string, userId: string) => void} deps.vincularDispositivo
 * @param {() => void} deps.refrescarSellers  Recarga la lista en memoria de data.js.
 */
function crearRutasAuthGoogle({
  getDb,
  verificarIdToken = googleAuth.verificarIdToken,
  vincularDispositivo = () => {},
  refrescarSellers = () => {},
}) {
  const router = express.Router();

  // Mismo freno que /api/auth/anon: es un endpoint que crea sesiones y
  // cuentas, y el coste de verificar un idToken es una llamada de red a
  // Google. 30/hora por IP no estorba a nadie real (un usuario hace una o
  // dos) y corta un bucle de reintentos de un cliente roto.
  const limite = rateLimit({
    windowMs: 60 * 60 * 1000,
    limit: 30,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Demasiados intentos desde esta red. Intenta más tarde.' },
  });

  // El cuerpo entero va dentro de un try/catch por una razón concreta de
  // Express 4: un handler `async` que rechaza NO llega al manejador de
  // errores. La petición se queda colgada sin respuesta y, como el proceso
  // no registra `unhandledRejection`, Node 20 lo MATA — se cae el backend
  // entero (y con él los sockets del chat) por, por ejemplo, un
  // SQLITE_BUSY. Las rutas de login/registro no tienen el problema porque
  // son síncronas; esta tiene que esperar a Google, y por eso es async.
  router.post('/google', limite, async (req, res) => {
    try {
      await manejarGoogle(req, res);
    } catch (err) {
      console.error('[auth/google] error no controlado:', err);
      if (!res.headersSent) {
        res.status(500).json({ error: 'No se pudo completar el inicio de sesión con Google.' });
      }
    }
  });

  async function manejarGoogle(req, res) {
    const { idToken, deviceId, registro } = req.body || {};

    if (!idToken || typeof idToken !== 'string') {
      return res.status(400).json({ error: 'idToken es requerido' });
    }

    let perfil;
    try {
      perfil = await verificarIdToken(idToken);
    } catch (err) {
      if (err && err.codigo) {
        // El `error` lleva el CÓDIGO (no la frase) porque el cliente decide
        // qué hacer con cada caso: reintentar, mandar a registro, o pintar
        // el mensaje. La frase para el usuario va en `message`, igual que
        // en los 401 de auth.js.
        return res.status(err.status || 401).json({ error: err.codigo, message: err.message });
      }
      console.error('[auth/google] error inesperado verificando idToken:', err);
      return res.status(500).json({ error: 'No se pudo verificar el inicio de sesión con Google.' });
    }

    const db = getDb();
    const email = perfil.email.trim();

    // Se busca primero por `google_sub` y solo después por correo: el `sub`
    // es el identificador estable de la cuenta de Google, mientras que el
    // correo puede cambiar. Buscar solo por correo crearía una cuenta nueva
    // a quien cambió su dirección en Google.
    const existente =
      db.prepare('SELECT * FROM sellers WHERE google_sub = ?').get(perfil.sub) ||
      db.prepare('SELECT * FROM sellers WHERE email = ? COLLATE NOCASE').get(email);

    if (existente) {
      // Google ya probó la identidad. Antes de vincular el sub, actualizar
      // foto, asociar dispositivo o emitir tokens se aplica la misma puerta
      // de suspensión/baneo que al login con contraseña.
      const accountAccess = getSellerAccess(db, existente.id);
      if (!accountAccess.allowed) return sendSellerAccessError(res, accountAccess);

      // Primera vez que esta cuenta entra con Google: se guarda el `sub`
      // para reconocerla después. NO se cambia `auth_provider`: una cuenta
      // que ya tenía contraseña la conserva y puede seguir entrando con
      // ella — vincular Google añade una puerta, no cierra la otra.
      if (existente.google_sub !== perfil.sub) {
        db.prepare('UPDATE sellers SET google_sub = ? WHERE id = ?').run(perfil.sub, existente.id);
        existente.google_sub = perfil.sub;
      }
      // La foto de Google solo se guarda si la cuenta no tenía ninguna: si
      // el usuario ya subió su propia foto aquí, pisarla en cada login sería
      // deshacerle un cambio que hizo a propósito.
      if (perfil.foto && !existente.avatarUrl) {
        db.prepare('UPDATE sellers SET avatarUrl = ? WHERE id = ?').run(perfil.foto, existente.id);
        existente.avatarUrl = perfil.foto;
      }
      refrescarSellers();

      if (deviceId) vincularDispositivo(deviceId, existente.id);
      return res.json({
        ...generateSession(existente.id),
        seller: sellerParaCliente(existente),
        created: false,
      });
    }

    // ─── No existe: hace falta completar el registro ───────────
    if (!registro || typeof registro !== 'object') {
      return res.status(404).json({
        error: 'GOOGLE_ACCOUNT_NOT_FOUND',
        message: 'No hay ninguna cuenta con ese correo. Completa tu registro.',
        // Lo que la app necesita para prellenar el formulario. El correo va
        // aquí y NO se acepta de vuelta desde el cliente en el paso
        // siguiente: el correo de la cuenta sale siempre del idToken.
        google: { email, name: perfil.nombre, picture: perfil.foto },
      });
    }

    const { userType, phone, paymentMethods, businessHours, name } = registro;

    // El nombre del formulario gana: alguien puede querer registrarse con un
    // nombre de negocio distinto al de su cuenta personal de Google.
    const nombre = (typeof name === 'string' && name.trim()) || perfil.nombre || '';
    const nameError = validateName(nombre);
    if (nameError) return res.status(400).json({ error: nameError });

    const phoneError = validatePhone(phone);
    if (phoneError) return res.status(400).json({ error: phoneError });

    let horarioNormalizado = {};
    if (userType === 'negocio' && businessHours !== undefined) {
      const resultado = validateBusinessHours(businessHours);
      if (resultado.error) return res.status(400).json({ error: resultado.error });
      horarioNormalizado = resultado.value;
    }

    const metodos = validatePaymentMethods(paymentMethods, { required: true });
    if (metodos.error) return res.status(400).json({ error: metodos.error });

    // Misma regla que /api/auth/register: 'tarjeta' exige una cuenta de
    // Mercado Pago conectada, y una cuenta que nace en este request todavía
    // no puede tenerla (el OAuth ocurre después, desde el perfil).
    if ((metodos.value || []).includes('tarjeta')) {
      return res.status(400).json({
        error: 'Para aceptar tarjeta primero conecta tu cuenta de Mercado Pago desde tu perfil.',
      });
    }

    const emailSlug = email.split('@')[0].replace(/[^a-zA-Z0-9]/g, '').toLowerCase();
    const sufijo = Math.random().toString(36).slice(2, 6);
    const sellerId = `u_${emailSlug}_${sufijo}`;

    let major = '';
    if (userType === 'estudiante') major = 'Estudiante';
    else if (userType === 'negocio') major = 'Negocio • Establecimiento';
    else if (userType === 'particular') major = 'Particular';

    // Un userType desconocido cae a 'particular', el tipo menos privilegiado.
    const tipoCuenta = ['estudiante', 'negocio', 'particular'].includes(userType)
      ? userType
      : 'particular';
    if (!major) major = 'Particular';

    db.prepare(`
      INSERT INTO sellers (id, name, email, phone, avatarInitials, major, isBusiness,
        rating, reviews, verified, tipo_cuenta, businessHours, paymentMethods,
        password_hash, auth_provider, google_sub, avatarUrl, created_at)
      VALUES (@id, @name, @email, @phone, @avatarInitials, @major, @isBusiness,
        0, 0, 0, @tipo_cuenta, @businessHours, @paymentMethods,
        NULL, @auth_provider, @google_sub, @avatarUrl, datetime('now'))
    `).run({
      id: sellerId,
      name: nombre.trim(),
      email,
      phone: (phone || '').trim(),
      avatarInitials: calcularIniciales(nombre),
      major,
      isBusiness: userType === 'negocio' ? 1 : 0,
      tipo_cuenta: tipoCuenta,
      businessHours: JSON.stringify(horarioNormalizado),
      paymentMethods: JSON.stringify(metodos.value),
      // `password_hash` va explícitamente en NULL y `auth_provider` en
      // 'google': juntos son lo que impide que /api/auth/register trate esta
      // fila como "cuenta legacy" y le ponga la contraseña que le manden.
      auth_provider: PROVEEDOR_GOOGLE,
      google_sub: perfil.sub,
      avatarUrl: perfil.foto,
    });
    // Misma regla que el registro con contraseña para cuentas oficiales.
    dbModule.anularMetodosPagoCuentasDueno();
    refrescarSellers();

    if (deviceId) vincularDispositivo(deviceId, sellerId);

    const creado = db.prepare('SELECT * FROM sellers WHERE id = ?').get(sellerId);
    return res.status(201).json({
      ...generateSession(sellerId),
      seller: sellerParaCliente(creado),
      created: true,
    });
  }

  return router;
}

/** Montaje real en la app (index.js). */
function register(app) {
  const { sellers } = require('../data');
  app.use(
    '/api/auth',
    crearRutasAuthGoogle({
      getDb: () => dbModule.getDb(),
      verificarIdToken: googleAuth.verificarIdToken,
      vincularDispositivo: (deviceId, userId) => dbModule.linkDeviceToUser(deviceId, userId),
      refrescarSellers: () => {
        sellers.length = 0;
        sellers.push(...dbModule.getSellers());
      },
    }),
  );
}

module.exports = { register, crearRutasAuthGoogle, PROVEEDOR_GOOGLE };
