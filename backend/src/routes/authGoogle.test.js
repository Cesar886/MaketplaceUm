// Tests de integración de POST /api/auth/google.
//
// Corren contra una base SQLite temporal creada con el schema y las
// migraciones REALES (MERCADITO_DB_PATH) y un Express real en un puerto
// libre. Lo único sustituido es la verificación del idToken contra Google:
// firmar un token con las claves privadas de Google desde un test no es
// posible, así que se inyecta un verificador falso. Todo lo demás —
// búsqueda de la cuenta, vinculación, validaciones de registro, emisión del
// JWT — es el código real.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-google-')),
  'test.db',
);
// auth.js revienta al cargarse sin JWT_SECRET (a propósito, ver el
// comentario ahí). Tiene que estar puesto ANTES del require.
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../database');
const { verificarToken } = require('../auth');
const { GoogleAuthError } = require('../services/googleAuth');
const { crearRutasAuthGoogle } = require('./authGoogle');

db.initDatabase();

// ─── Doble del verificador de Google ─────────────────────────

// Lo que el "Google" falso responderá a la próxima llamada. Un test que
// quiera simular un token rechazado pone aquí un GoogleAuthError.
let respuestaGoogle = null;
const dispositivosVinculados = [];

const verificarIdTokenFalso = async (idToken) => {
  if (respuestaGoogle instanceof Error) throw respuestaGoogle;
  if (!respuestaGoogle) {
    throw new GoogleAuthError('Token de Google inválido.', 'GOOGLE_TOKEN_INVALIDO', 401);
  }
  assert.equal(typeof idToken, 'string');
  return respuestaGoogle;
};

// ─── Servidor de pruebas ─────────────────────────────────────

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  app.use(
    '/api/auth',
    crearRutasAuthGoogle({
      getDb: () => db.getDb(),
      verificarIdToken: verificarIdTokenFalso,
      vincularDispositivo: (deviceId, userId) =>
        dispositivosVinculados.push({ deviceId, userId }),
      refrescarSellers: () => {},
    }),
  );
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

// ─── Helpers ─────────────────────────────────────────────────

async function postGoogle(body) {
  const res = await fetch(`${baseUrl}/api/auth/google`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

let contador = 0;

function crearUsuarioConPassword(email, password = 'Password1') {
  const id = `u_existente_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, phone, avatarInitials, major,
         isBusiness, verified, tipo_cuenta, password_hash, paymentMethods)
       VALUES (?, 'Ya Registrado', ?, '8112223344', 'YR', 'Estudiante', 0, 0,
         'estudiante', ?, '["efectivo"]')`,
    )
    .run(id, email, bcrypt.hashSync(password, 10));
  return id;
}

function filaPorEmail(email) {
  return db.getDb()
    .prepare('SELECT * FROM sellers WHERE email = ? COLLATE NOCASE')
    .get(email);
}

const REGISTRO_MINIMO = {
  userType: 'estudiante',
  phone: '8110002233',
  paymentMethods: ['efectivo'],
};

// ─── El esquema tiene que soportar cuentas de Google ─────────

test('la migración añade las columnas que necesita una cuenta de Google', () => {
  const cols = db.getDb().prepare("PRAGMA table_info('sellers')").all().map(c => c.name);
  assert.ok(cols.includes('google_sub'), 'falta sellers.google_sub');
  assert.ok(cols.includes('auth_provider'), 'falta sellers.auth_provider');
  assert.ok(cols.includes('avatarUrl'), 'falta sellers.avatarUrl');
});

test('las cuentas que ya existían quedan marcadas como de contraseña', () => {
  const id = crearUsuarioConPassword('provider.default@ejemplo.com');
  const fila = db.getDb().prepare('SELECT auth_provider FROM sellers WHERE id = ?').get(id);
  assert.equal(fila.auth_provider, 'password');
});

// ─── Errores de token ────────────────────────────────────────

test('sin idToken responde 400 sin llamar a Google', async () => {
  respuestaGoogle = null;
  const { status, body } = await postGoogle({});
  assert.equal(status, 400);
  assert.match(body.error, /idToken/);
});

test('un idToken rechazado por Google responde 401 con su código', async () => {
  respuestaGoogle = new GoogleAuthError('Token de Google inválido.', 'GOOGLE_TOKEN_INVALIDO', 401);
  const { status, body } = await postGoogle({ idToken: 'basura' });
  assert.equal(status, 401);
  assert.equal(body.error, 'GOOGLE_TOKEN_INVALIDO');
});

test('mientras falten las credenciales del servidor responde 503', async () => {
  respuestaGoogle = new GoogleAuthError('no configurado', 'GOOGLE_NO_CONFIGURADO', 503);
  const { status, body } = await postGoogle({ idToken: 'x' });
  assert.equal(status, 503);
  assert.equal(body.error, 'GOOGLE_NO_CONFIGURADO');
});

test('un correo fuera del dominio permitido responde 403', async () => {
  respuestaGoogle = new GoogleAuthError('fuera', 'GOOGLE_DOMINIO_NO_PERMITIDO', 403);
  const { status, body } = await postGoogle({ idToken: 'x' });
  assert.equal(status, 403);
  assert.equal(body.error, 'GOOGLE_DOMINIO_NO_PERMITIDO');
});

// ─── Cuenta que ya existe ────────────────────────────────────

test('un correo ya registrado inicia sesión y no crea una cuenta nueva', async () => {
  const id = crearUsuarioConPassword('existente@ejemplo.com');
  respuestaGoogle = {
    sub: 'google-sub-existente',
    email: 'existente@ejemplo.com',
    nombre: 'Nombre En Google',
    foto: 'https://foto',
  };

  const { status, body } = await postGoogle({ idToken: 'x' });

  assert.equal(status, 200);
  assert.equal(body.created, false);
  assert.equal(body.seller.id, id);
  assert.equal(verificarToken(body.token), id);
  assert.equal(typeof body.refreshToken, 'string');
  assert.ok(body.refreshToken.length >= 40);
  // Sigue siendo una cuenta de contraseña: entrar con Google no debe
  // quitarle a nadie su forma de entrar de siempre.
  const fila = filaPorEmail('existente@ejemplo.com');
  assert.equal(fila.auth_provider, 'password');
  assert.ok(fila.password_hash);
  // Pero el `sub` queda vinculado para reconocerla la próxima vez.
  assert.equal(fila.google_sub, 'google-sub-existente');
});

test('el correo se reconoce sin importar mayúsculas', async () => {
  const id = crearUsuarioConPassword('MayUsculas@Ejemplo.com');
  respuestaGoogle = {
    sub: 'google-sub-mayusculas',
    email: 'mayusculas@ejemplo.com',
    nombre: 'X',
    foto: null,
  };
  const { status, body } = await postGoogle({ idToken: 'x' });
  assert.equal(status, 200);
  assert.equal(body.seller.id, id);
});

test('la cuenta se reconoce por su google_sub aunque cambie el correo en Google', async () => {
  const id = crearUsuarioConPassword('correo.viejo@ejemplo.com');
  respuestaGoogle = { sub: 'sub-estable', email: 'correo.viejo@ejemplo.com', nombre: 'X', foto: null };
  await postGoogle({ idToken: 'x' });

  // El usuario cambió su correo en Google: mismo sub, email distinto.
  respuestaGoogle = { sub: 'sub-estable', email: 'correo.nuevo@ejemplo.com', nombre: 'X', foto: null };
  const { status, body } = await postGoogle({ idToken: 'x' });

  assert.equal(status, 200);
  assert.equal(body.seller.id, id, 'debe ser la misma cuenta, no una nueva');
});

test('deviceId vincula el historial anónimo a la cuenta', async () => {
  const id = crearUsuarioConPassword('condevice@ejemplo.com');
  dispositivosVinculados.length = 0;
  respuestaGoogle = { sub: 'sub-device', email: 'condevice@ejemplo.com', nombre: 'X', foto: null };

  await postGoogle({ idToken: 'x', deviceId: 'dispositivo-123' });

  assert.deepEqual(dispositivosVinculados, [{ deviceId: 'dispositivo-123', userId: id }]);
});

// ─── Cuenta que no existe ────────────────────────────────────

test('un correo sin cuenta y sin datos de registro pide completar el registro', async () => {
  respuestaGoogle = {
    sub: 'sub-nuevo',
    email: 'nuevo@ejemplo.com',
    nombre: 'Persona Nueva',
    foto: 'https://foto/nueva.png',
  };

  const { status, body } = await postGoogle({ idToken: 'x' });

  assert.equal(status, 404);
  assert.equal(body.error, 'GOOGLE_ACCOUNT_NOT_FOUND');
  // La app usa esto para prellenar el formulario de registro.
  assert.equal(body.google.email, 'nuevo@ejemplo.com');
  assert.equal(body.google.name, 'Persona Nueva');
  assert.equal(body.google.picture, 'https://foto/nueva.png');
  assert.equal(filaPorEmail('nuevo@ejemplo.com'), undefined, 'no debe crear nada todavía');
});

test('con los datos de registro crea la cuenta y devuelve sesión', async () => {
  respuestaGoogle = {
    sub: 'sub-crea',
    email: 'creada@ejemplo.com',
    nombre: 'Ana Lopez',
    foto: 'https://foto/ana.png',
  };

  const { status, body } = await postGoogle({
    idToken: 'x',
    registro: { ...REGISTRO_MINIMO, paymentMethods: ['efectivo', 'paypal'] },
  });

  assert.equal(status, 201);
  assert.equal(body.created, true);
  assert.equal(body.seller.email, 'creada@ejemplo.com');
  assert.equal(body.seller.name, 'Ana Lopez');
  assert.equal(body.seller.avatarInitials, 'AL');
  assert.equal(body.seller.major, 'Estudiante');
  assert.equal(verificarToken(body.token), body.seller.id);
  assert.equal(typeof body.refreshToken, 'string');
  assert.ok(body.refreshToken.length >= 40);

  const fila = filaPorEmail('creada@ejemplo.com');
  assert.equal(fila.auth_provider, 'google');
  assert.equal(fila.google_sub, 'sub-crea');
  assert.equal(fila.tipo_cuenta, 'estudiante');
  assert.equal(fila.phone, '8110002233');
  assert.equal(fila.avatarUrl, 'https://foto/ana.png');
  // Clave del diseño: una cuenta de Google NO tiene contraseña.
  assert.equal(fila.password_hash, null);
  assert.deepEqual(JSON.parse(fila.paymentMethods), ['efectivo', 'paypal']);
});

test('un negocio guarda su horario y queda marcado como negocio', async () => {
  respuestaGoogle = { sub: 'sub-negocio', email: 'negocio@ejemplo.com', nombre: 'Tacos El Buen Sabor', foto: null };

  const { status, body } = await postGoogle({
    idToken: 'x',
    registro: {
      userType: 'negocio',
      phone: '8110002233',
      paymentMethods: ['efectivo'],
      businessHours: { '1': { open: '09:00', close: '18:00' } },
    },
  });

  assert.equal(status, 201);
  assert.equal(body.seller.isBusiness, true);
  const fila = filaPorEmail('negocio@ejemplo.com');
  assert.equal(fila.tipo_cuenta, 'negocio');
  assert.deepEqual(JSON.parse(fila.businessHours), { '1': { open: '09:00', close: '18:00' } });
});

test('el nombre del formulario gana sobre el que reporta Google', async () => {
  respuestaGoogle = { sub: 'sub-nombre', email: 'nombre@ejemplo.com', nombre: 'Nombre De Google', foto: null };

  const { body } = await postGoogle({
    idToken: 'x',
    registro: { ...REGISTRO_MINIMO, name: 'Nombre Elegido' },
  });

  assert.equal(body.seller.name, 'Nombre Elegido');
});

// ─── Validaciones del registro (las mismas que /auth/register) ──

test('registrarse sin métodos de pago es un 400', async () => {
  respuestaGoogle = { sub: 'sub-sinmetodos', email: 'sinmetodos@ejemplo.com', nombre: 'X Y', foto: null };
  const { status } = await postGoogle({
    idToken: 'x',
    registro: { userType: 'estudiante', phone: '8110002233', paymentMethods: [] },
  });
  assert.equal(status, 400);
  assert.equal(filaPorEmail('sinmetodos@ejemplo.com'), undefined);
});

test('no se puede aceptar tarjeta en una cuenta que se está creando', async () => {
  respuestaGoogle = { sub: 'sub-tarjeta', email: 'tarjeta@ejemplo.com', nombre: 'X Y', foto: null };
  const { status, body } = await postGoogle({
    idToken: 'x',
    registro: { ...REGISTRO_MINIMO, paymentMethods: ['efectivo', 'tarjeta'] },
  });
  assert.equal(status, 400);
  assert.match(body.error, /Mercado Pago/);
});

test('un teléfono inválido es un 400', async () => {
  respuestaGoogle = { sub: 'sub-tel', email: 'tel@ejemplo.com', nombre: 'X Y', foto: null };
  const { status } = await postGoogle({
    idToken: 'x',
    registro: { ...REGISTRO_MINIMO, phone: '123' },
  });
  assert.equal(status, 400);
});

test('un userType desconocido cae a particular, el tipo menos privilegiado', async () => {
  respuestaGoogle = { sub: 'sub-raro', email: 'raro@ejemplo.com', nombre: 'X Y', foto: null };
  await postGoogle({
    idToken: 'x',
    registro: { ...REGISTRO_MINIMO, userType: 'administrador' },
  });
  assert.equal(filaPorEmail('raro@ejemplo.com').tipo_cuenta, 'particular');
});

test('registrar dos veces el mismo correo no duplica la cuenta', async () => {
  respuestaGoogle = { sub: 'sub-dup', email: 'dup@ejemplo.com', nombre: 'X Y', foto: null };
  const primera = await postGoogle({ idToken: 'x', registro: REGISTRO_MINIMO });
  const segunda = await postGoogle({ idToken: 'x', registro: REGISTRO_MINIMO });

  assert.equal(primera.status, 201);
  assert.equal(segunda.status, 200);
  assert.equal(segunda.body.created, false);
  assert.equal(segunda.body.seller.id, primera.body.seller.id);
});

// ─── Un fallo de la base no puede tumbar el proceso ──────────
//
// Esta ruta es `async` (tiene que esperar a Google), y en Express 4 un
// handler async que rechaza NO llega al manejador de errores: la petición se
// queda sin respuesta y, como el proceso no registra `unhandledRejection`,
// Node 20 mata el backend entero — chat incluido — por un SQLITE_BUSY o un
// choque de id. El try/catch de la ruta es lo que convierte eso en un 500.

test('un error de la base responde 500 en vez de tumbar el proceso', async () => {
  const app = express();
  app.use(express.json());
  app.use(
    '/api/auth',
    crearRutasAuthGoogle({
      getDb: () => ({
        prepare() {
          throw new Error('SQLITE_BUSY: database is locked');
        },
      }),
      verificarIdToken: async () => ({
        sub: 'sub-db-rota',
        email: 'dbrota@ejemplo.com',
        nombre: 'DB Rota',
        foto: null,
      }),
    }),
  );
  const srv = http.createServer(app);
  await new Promise(r => srv.listen(0, '127.0.0.1', r));

  try {
    const res = await fetch(`http://127.0.0.1:${srv.address().port}/api/auth/google`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: 'x' }),
    });
    assert.equal(res.status, 500);
    assert.ok((await res.json()).error);
  } finally {
    await new Promise(r => srv.close(r));
  }
});
