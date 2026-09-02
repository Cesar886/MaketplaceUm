// Tests de integración de los endpoints de verificación.
//
// Corren contra una base SQLite temporal creada con el schema y las
// migraciones REALES (MERCADITO_DB_PATH), y contra un servidor Express real
// levantado en un puerto libre. Lo único sustituido son los adaptadores de
// salida (email, SMS y la comprobación HTTP del link), porque mandar correos
// de verdad desde un test no es viable.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-verif-')),
  'test.db',
);
process.env.VERIFICATION_STUDENT_DOMAINS = 'alumno.um.edu.mx';
// auth.js revienta al cargarse si no hay JWT_SECRET (a propósito: ver el
// comentario ahí). El test firma sus propios tokens, así que le basta un
// secreto cualquiera, pero tiene que estar puesto ANTES del require.
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.REVISION_API_KEY = 'revision-prueba';
// Verificar un negocio exige cuenta de pagos conectada, y guardarla cifra el
// token. Sin esta clave, payments/crypto.js revienta al cargarse.
process.env.PAYMENTS_ENCRYPTION_KEY = require('crypto').randomBytes(32).toString('hex');
// Este archivo prueba el flujo de verificación con la validación ORIGINAL de
// Mercado Pago activa (ver payments/config.js#mercadoPagoHabilitado). El
// caso de "flag apagado" (MERCADO_PAGO_HABILITADO=false, el valor real de
// producción hoy) tiene sus propios tests más abajo.
process.env.MERCADO_PAGO_HABILITADO = 'true';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');
const { crearRutasVerificacion } = require('./verificacion');
const { register: registerRevision } = require('./revision');
const { CARRERAS_UM } = require('../validation/carreras');

const CARRERA_VALIDA = CARRERAS_UM[0];

db.initDatabase();

// ─── Dobles de los adaptadores de salida ─────────────────────

const enviados = { email: [], sms: [] };
let linkResponde = { ok: true, motivo: null };

const mailerFalso = {
  enviarCodigo: async (destino, codigo) => {
    enviados.email.push({ destino, codigo });
    return { modo: 'dev' };
  },
};
const smsFalso = {
  enviarCodigo: async (destino, codigo) => {
    enviados.sms.push({ destino, codigo });
    return { modo: 'dev' };
  },
};

// ─── Servidor de pruebas ─────────────────────────────────────

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  app.use(
    '/api/verificacion',
    crearRutasVerificacion({
      getDb: () => db.getDb(),
      mailer: mailerFalso,
      sms: smsFalso,
      verificarLink: async () => linkResponde,
      refrescarSellers: () => {},
    }),
  );
  registerRevision(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

// ─── Helpers ─────────────────────────────────────────────────

let contador = 0;

/**
 * Crea un vendedor real en la base temporal y devuelve su id y token.
 *
 * Por defecto cumple los requisitos de verificación que NO son el objeto de
 * cada test (horario y métodos de pago), para que un test sobre el OTP no
 * falle por algo que no está probando. Los tests que sí van sobre un
 * requisito lo quitan explícitamente.
 */
function crearUsuario(tipoCuenta, {
  verificado = false,
  horario = JSON.stringify({ '0': { open: '09:00', close: '18:00' } }),
  metodos = ['efectivo'],
  logoUrl = '/uploads/foto-test.webp',
} = {}) {
  const id = `u_test_${tipoCuenta}_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness,
         verified, tipo_cuenta, businessHours, paymentMethods, logoUrl)
       VALUES (?, ?, ?, 'TT', '', ?, ?, ?, ?, ?, ?)`,
    )
    .run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0,
      verificado ? 1 : 0, tipoCuenta, horario,
      metodos === null ? null : JSON.stringify(metodos), logoUrl);
  return { id, token: generateToken(id) };
}

/**
 * Deja al vendedor aceptando tarjeta, que es lo que hace obligatoria la
 * cuenta de Mercado Pago. Sin esto, quien solo acepta efectivo se verifica
 * sin conectar nada — que es justamente la regla nueva.
 */
function aceptarTarjeta(usuarioId) {
  db.getDb()
    .prepare('UPDATE sellers SET paymentMethods = ? WHERE id = ?')
    .run(JSON.stringify(['efectivo', 'tarjeta']), usuarioId);
}

async function pedir(ruta, token, cuerpo) {
  const res = await fetch(`${baseUrl}/api/verificacion${ruta}`, {
    method: cuerpo === undefined ? 'GET' : 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  return { status: res.status, body: await res.json() };
}

/**
 * Conecta una cuenta de pagos al vendedor. Completar la verificación lo
 * exige en LOS TRES flujos: una cuenta verificada es una que puede cobrar
 * dentro de la app.
 */
async function subirDocumento(token, tipo, contenido, nombre) {
  const form = new FormData();
  form.append('doc_type', tipo);
  form.append('file', new Blob([contenido], { type: 'image/jpeg' }), nombre);
  const res = await fetch(baseUrl + '/api/verificacion/negocio/documentos', {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token },
    body: form,
  });
  return { status: res.status, body: await res.json() };
}

function conectarPagos(usuarioId) {
  require('../payments/store').guardarCuentaVendedor(usuarioId, {
    mpUserId: `mp_${usuarioId}`,
    accessToken: 'vendor-access-token',
    refreshToken: 'vendor-refresh-token',
    expiresIn: 30 * 24 * 60 * 60,
    publicKey: 'APP_USR-pk',
  });
}

function filaVerificacion(usuarioId) {
  return db.getDb().prepare('SELECT * FROM verificaciones WHERE usuario_id = ?').get(usuarioId);
}

function estaVerificado(usuarioId) {
  return !!db.getDb().prepare('SELECT verified FROM sellers WHERE id = ?').get(usuarioId).verified;
}

// ═══ ESTUDIANTE ══════════════════════════════════════════════

test('un estudiante se verifica con el código enviado a su correo institucional', async () => {
  const usuario = crearUsuario('estudiante');
  conectarPagos(usuario.id);
  const correo = '1220326@alumno.um.edu.mx';

  const solicitud = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: correo,
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(solicitud.status, 200);
  assert.strictEqual(solicitud.body.enviado, true);

  const { codigo } = enviados.email.at(-1);
  assert.match(codigo, /^\d{6}$/);

  const confirmacion = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: codigo,
  });
  assert.strictEqual(confirmacion.status, 200);
  assert.strictEqual(confirmacion.body.verificado, true);

  assert.strictEqual(estaVerificado(usuario.id), true);
  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.estado, 'verificado');
  assert.strictEqual(fila.matricula, '1220326');
  assert.strictEqual(fila.carrera, CARRERA_VALIDA);
  assert.ok(fila.fecha_verificacion);

  // La carrera se copia a `sellers` (bandera rápida para el perfil), igual
  // que `verified`.
  const sellerRow = db.getDb().prepare('SELECT carrera FROM sellers WHERE id = ?').get(usuario.id);
  assert.strictEqual(sellerRow.carrera, CARRERA_VALIDA);
});

test('rechaza una carrera que no está en la lista fija', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1220327@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: 'Licenciatura Inventada',
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'carrera');
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('rechaza la solicitud si no se manda carrera', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1220328@alumno.um.edu.mx',
    tipo: 'estudiante',
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'carrera');
});

// ═══ PERSONAL / EMPLEADO ═════════════════════════════════════

test('el personal se verifica con su correo @um.edu.mx, sin matrícula ni carrera', async () => {
  const usuario = crearUsuario('estudiante');
  conectarPagos(usuario.id);
  const correo = 'cesar.herrera@um.edu.mx';

  const solicitud = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: correo,
    tipo: 'empleado',
  });
  assert.strictEqual(solicitud.status, 200, JSON.stringify(solicitud.body));

  await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  assert.strictEqual(estaVerificado(usuario.id), true);
  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.tipo_verificacion, 'empleado');
  assert.strictEqual(fila.correo_institucional, correo);
  // El personal no tiene matrícula ni carrera: ambas quedan en null.
  assert.strictEqual(fila.matricula, null);
  assert.strictEqual(fila.carrera, null);

  const sellerRow = db
    .getDb()
    .prepare('SELECT carrera, tipo_verificacion FROM sellers WHERE id = ?')
    .get(usuario.id);
  assert.strictEqual(sellerRow.tipo_verificacion, 'empleado');
  assert.strictEqual(sellerRow.carrera, null);
});

test('acepta variantes del usuario del personal (segundo apellido, dígitos)', async () => {
  for (const local of ['ana.lopez.ruiz', 'juan.perez2', 'soporte']) {
    const usuario = crearUsuario('estudiante');
    const res = await pedir('/estudiante/solicitar', usuario.token, {
      correo_institucional: `${local}@um.edu.mx`,
      tipo: 'empleado',
    });
    assert.strictEqual(res.status, 200, `${local} debía aceptarse`);
  }
});

test('rechaza un correo de alumno declarado como empleado', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1220400@alumno.um.edu.mx',
    tipo: 'empleado',
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'correo_institucional');
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('rechaza un correo de empleado declarado como estudiante', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: 'cesar.herrera@um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'correo_institucional');
});

test('rechaza un tipo desconocido o ausente', async () => {
  const usuario = crearUsuario('estudiante');
  for (const tipo of ['admin', '', undefined]) {
    const res = await pedir('/estudiante/solicitar', usuario.token, {
      correo_institucional: '1220401@alumno.um.edu.mx',
      carrera: CARRERA_VALIDA,
      tipo,
    });
    assert.strictEqual(res.status, 400, `tipo=${tipo} debía rechazarse`);
    assert.strictEqual(res.body.campo, 'tipo');
  }
});

test('cambiar de alumno a personal borra la matrícula y la carrera del intento previo', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1220402@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(filaVerificacion(usuario.id).matricula, '1220402');

  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: 'nuevo.empleado@um.edu.mx',
    tipo: 'empleado',
  });
  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.matricula, null);
  assert.strictEqual(fila.carrera, null);
  assert.strictEqual(fila.tipo_verificacion, 'empleado');
});

// ═══ ESTUDIANTE (continuación) ═══════════════════════════════

test('el código deja de existir en la base después de usarse', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1330001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const { codigo } = enviados.email.at(-1);
  await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });

  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.codigo_otp_email, null);
  assert.strictEqual(fila.codigo_otp_email_expira, null);
});

test('el mismo código no sirve dos veces', async () => {
  const usuario = crearUsuario('estudiante');
  conectarPagos(usuario.id);
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1330002@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const { codigo } = enviados.email.at(-1);
  await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });

  // Ya verificado: el endpoint ni siquiera evalúa el código.
  const segundo = await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });
  assert.strictEqual(segundo.status, 409);
});

test('rechaza un correo que no es del dominio institucional', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1220326@gmail.com',
    tipo: 'estudiante',
  });
  assert.strictEqual(res.status, 400);
  assert.match(res.body.error, /institucional/i);
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('rechaza correos con matrícula de longitud distinta a 7 o dominio parecido', async () => {
  const usuario = crearUsuario('estudiante');
  const invalidos = [
    '122032@alumno.um.edu.mx',
    '12203267@alumno.um.edu.mx',
    '1220326@alumno.um.edu.mx.fake.com',
    'daniel@alumno.um.edu.mx',
  ];
  for (const correo_institucional of invalidos) {
    const res = await pedir('/estudiante/solicitar', usuario.token, {
      correo_institucional,
      tipo: 'estudiante',
    });
    assert.strictEqual(res.status, 400, `${correo_institucional} debía rechazarse`);
    assert.strictEqual(res.body.campo, 'correo_institucional');
  }
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('normaliza el correo en mayúsculas antes de validar y guardar', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '  1230001@ALUMNO.UM.EDU.MX  ',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(res.status, 200);

  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.correo_institucional, '1230001@alumno.um.edu.mx');
  assert.strictEqual(fila.matricula, '1230001');
});

test('la matrícula se deriva del correo, ignorando la que mande el cliente', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1230002@alumno.um.edu.mx',
    matricula: '9999999',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(filaVerificacion(usuario.id).matricula, '1230002');
});

test('un código nuevo invalida el anterior', async () => {
  const usuario = crearUsuario('estudiante');
  const cuerpo = {
    correo_institucional: '1230003@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  };
  await pedir('/estudiante/solicitar', usuario.token, cuerpo);
  const primerCodigo = enviados.email.at(-1).codigo;

  await pedir('/estudiante/solicitar', usuario.token, cuerpo);
  const segundoCodigo = enviados.email.at(-1).codigo;
  assert.notStrictEqual(primerCodigo, segundoCodigo);

  const res = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: primerCodigo,
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('rechaza un correo institucional ya usado por otra cuenta verificada', async () => {
  const primero = crearUsuario('estudiante');
  conectarPagos(primero.id);
  const correo = '1440001@alumno.um.edu.mx';
  await pedir('/estudiante/solicitar', primero.token, {
    correo_institucional: correo,
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  await pedir('/estudiante/confirmar', primero.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  const segundo = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', segundo.token, {
    correo_institucional: correo,
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(res.status, 409);
  assert.match(res.body.error, /ya está registrado|ya esta registrado/i);
});

test('rechaza un código incorrecto e informa los intentos restantes', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const res = await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: '000000' });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.intentos_restantes, 4);
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('invalida el código tras 5 intentos fallidos de confirmación', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550002@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const { codigo } = enviados.email.at(-1);

  for (let i = 0; i < 5; i++) {
    await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: '000000' });
  }
  assert.strictEqual(filaVerificacion(usuario.id).codigo_otp_email, null);

  // Ni siquiera el código correcto sirve ya: hay que pedir uno nuevo.
  const res = await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('bloquea el cuarto envío de código dentro de la ventana de 15 minutos', async () => {
  const usuario = crearUsuario('estudiante');
  const cuerpo = {
    correo_institucional: '1660001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  };
  for (let i = 0; i < 3; i++) {
    const ok = await pedir('/estudiante/solicitar', usuario.token, cuerpo);
    assert.strictEqual(ok.status, 200, `el envío ${i + 1} debía pasar`);
  }
  const res = await pedir('/estudiante/solicitar', usuario.token, cuerpo);
  assert.strictEqual(res.status, 429);
  assert.ok(res.body.puede_reintentar_en > 0);
});

test('bloquea el envío a un correo que ya recibió 3 códigos desde otra cuenta', async () => {
  const correo = '1770001@alumno.um.edu.mx';
  const cuerpo = {
    correo_institucional: correo,
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  };
  const primero = crearUsuario('estudiante');
  for (let i = 0; i < 3; i++) {
    await pedir('/estudiante/solicitar', primero.token, cuerpo);
  }

  // Otra cuenta apuntando al mismo correo: el límite es por destino, no solo
  // por usuario, para que N cuentas no puedan bombardear un correo ajeno.
  const segundo = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', segundo.token, cuerpo);
  assert.strictEqual(res.status, 429);
});

// ═══ NEGOCIO ═════════════════════════════════════════════════

test('un negocio se verifica en la misma respuesta, sin cola de revisión', async () => {
  const usuario = crearUsuario('negocio');
  conectarPagos(usuario.id);
  linkResponde = { ok: true, motivo: null };

  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/tacos_um/',
  });

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.estado, 'verificado');
  assert.strictEqual(estaVerificado(usuario.id), true);

  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.nombre_negocio, 'Tacos UM');
  assert.strictEqual(fila.ubicacion_lat, 19.7);
  assert.strictEqual(fila.link_red_social, 'https://www.instagram.com/tacos_um/');
});

test('rechaza el negocio cuando el link no responde, señalando el campo', async () => {
  const usuario = crearUsuario('negocio');
  conectarPagos(usuario.id);
  linkResponde = { ok: false, motivo: 'La página del link no existe.' };

  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/no_existe_12345/',
  });

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.estado, 'rechazado');
  assert.strictEqual(res.body.campo, 'link_red_social');
  assert.ok(res.body.motivo_rechazo);
  assert.strictEqual(estaVerificado(usuario.id), false);
  assert.strictEqual(filaVerificacion(usuario.id).estado, 'rechazado');
});

test('un negocio rechazado puede corregir el dato y verificarse', async () => {
  const usuario = crearUsuario('negocio');
  conectarPagos(usuario.id);
  const datos = {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/roto/',
  };

  linkResponde = { ok: false, motivo: 'La página del link no existe.' };
  await pedir('/negocio/solicitar', usuario.token, datos);

  linkResponde = { ok: true, motivo: null };
  const res = await pedir('/negocio/solicitar', usuario.token, {
    ...datos,
    link_red_social: 'https://www.instagram.com/bueno/',
  });

  assert.strictEqual(res.body.estado, 'verificado');
  assert.strictEqual(estaVerificado(usuario.id), true);
  assert.strictEqual(filaVerificacion(usuario.id).motivo_rechazo, null);
});

test('rechaza un nombre de negocio demasiado corto sin tocar la red', async () => {
  const usuario = crearUsuario('negocio');
  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Ax',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/tacos_um/',
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'nombre_negocio');
});

test('rechaza coordenadas fuera de rango', async () => {
  const usuario = crearUsuario('negocio');
  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 200,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/tacos_um/',
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'ubicacion');
});

test('rechaza un link de un dominio que no es red social ni Maps', async () => {
  const usuario = crearUsuario('negocio');
  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://mi-negocio-inventado.com',
  });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.body.campo, 'link_red_social');
});

// ═══ EXTERNO (particular) ════════════════════════════════════

test('las cuentas externas no pueden iniciar ni completar una verificación', async () => {
  const usuario = crearUsuario('particular');
  const smsAntes = enviados.sms.length;

  const solicitud = await pedir('/externo/solicitar', usuario.token, {
    telefono: '(443) 123-4567',
  });
  assert.strictEqual(solicitud.status, 403);

  const confirmacion = await pedir('/externo/confirmar', usuario.token, {
    codigo_otp: '123456',
  });
  assert.strictEqual(confirmacion.status, 403);
  assert.strictEqual(estaVerificado(usuario.id), false);
  assert.strictEqual(filaVerificacion(usuario.id), undefined);
  assert.strictEqual(enviados.sms.length, smsAntes);
});

// ═══ GUARDAS COMPARTIDAS ═════════════════════════════════════

test('bloquea el flujo si la cuenta ya está verificada', async () => {
  const usuario = crearUsuario('estudiante', { verificado: true });
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1880001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(res.status, 409);
  assert.match(res.body.error, /ya está verificada|ya esta verificada/i);
});

test('impide que un negocio se verifique por el flujo de estudiante', async () => {
  const usuario = crearUsuario('negocio');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1880002@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(res.status, 403);
});

test('impide que un estudiante se verifique por el flujo de negocio', async () => {
  const usuario = crearUsuario('estudiante');
  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/tacos_um/',
  });
  assert.strictEqual(res.status, 403);
});

test('exige autenticación en todos los endpoints', async () => {
  const res = await fetch(`${baseUrl}/api/verificacion/estado`);
  assert.strictEqual(res.status, 401);
});

test('ignora un usuario_id mandado en el body y usa el del token', async () => {
  const victima = crearUsuario('estudiante');
  const atacante = crearUsuario('estudiante');
  conectarPagos(atacante.id);

  await pedir('/estudiante/solicitar', atacante.token, {
    correo_institucional: '1990001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
    usuario_id: victima.id,
  });
  await pedir('/estudiante/confirmar', atacante.token, {
    codigo_otp: enviados.email.at(-1).codigo,
    usuario_id: victima.id,
  });

  assert.strictEqual(estaVerificado(victima.id), false);
  assert.strictEqual(estaVerificado(atacante.id), true);
});

// ═══ GET /estado ═════════════════════════════════════════════

test('reporta el estado inicial de una cuenta que nunca inició verificación', async () => {
  const usuario = crearUsuario('particular');
  const res = await pedir('/estado', usuario.token);
  assert.strictEqual(res.status, 200);

  const { requisitos, ...resto } = res.body;
  assert.deepStrictEqual(resto, {
    tipo_cuenta: 'particular',
    estado: 'pendiente',
    verificado: false,
    motivo_rechazo: null,
    campo_rechazado: null,
    identidad_confirmada: false,
    puede_reintentar_en: 0,
  });

  // El checklist se sirve desde el primer momento: es lo que deja ver qué
  // falta sin tener que intentar verificarse y fallar.
  assert.deepStrictEqual(
    requisitos.map(r => r.id),
    ['horario', 'metodos_pago', 'mercadopago', 'stock_productos'],
  );
  assert.ok(requisitos.every(r => typeof r.cumplido === 'boolean'));
});

test('/estado marca como incumplido el requisito que de verdad falta', async () => {
  // Negocio y no estudiante: el horario solo se le exige al negocio (ver
  // requisitosVerificacion.js), así que es la única cuenta a la que dejarlo
  // sin configurar le marca ✗.
  const usuario = crearUsuario('negocio', { horario: null });
  const res = await pedir('/estado', usuario.token);

  const porId = Object.fromEntries(res.body.requisitos.map(r => [r.id, r]));
  assert.strictEqual(porId.horario.cumplido, false);
  assert.strictEqual(porId.metodos_pago.cumplido, true);
  // No acepta tarjeta, así que la cuenta de cobros no se le exige.
  assert.strictEqual(porId.mercadopago.cumplido, true);
});

test('reporta el estado verificado después de completar el flujo', async () => {
  const usuario = crearUsuario('negocio');
  conectarPagos(usuario.id);
  linkResponde = { ok: true, motivo: null };
  await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Café UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://facebook.com/cafeum',
  });

  const res = await pedir('/estado', usuario.token);
  assert.strictEqual(res.body.estado, 'verificado');
  assert.strictEqual(res.body.verificado, true);
  assert.strictEqual(res.body.tipo_cuenta, 'negocio');
});

test('reporta el motivo y el campo cuando la verificación fue rechazada', async () => {
  const usuario = crearUsuario('negocio');
  linkResponde = { ok: false, motivo: 'La página del link no existe.' };
  await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Café UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://facebook.com/noexiste',
  });

  const res = await pedir('/estado', usuario.token);
  assert.strictEqual(res.body.estado, 'rechazado');
  assert.strictEqual(res.body.campo_rechazado, 'link_red_social');
  assert.ok(res.body.motivo_rechazo);
});

// ═══ NEGOCIO: la cuenta de pagos es requisito ════════════════

test('un negocio SIN Mercado Pago conectado no llega a verificado', async () => {
  const usuario = crearUsuario('negocio');
  aceptarTarjeta(usuario.id);
  linkResponde = { ok: true, motivo: null };

  const res = await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/tacos_um/',
  });

  // 200 y no 4xx: el trámite es válido y sus datos quedan guardados. Lo que
  // pasa es que le falta un requisito, y eso es un ESTADO del trámite, igual
  // que el rechazo por link — no un error de la petición.
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.estado, 'pendiente');
  assert.strictEqual(res.body.campo, 'mercadopago');
  assert.ok(res.body.motivo, 'el negocio tiene que saber qué le falta');
  assert.strictEqual(estaVerificado(usuario.id), false);

  // Y los datos del negocio NO se pierden: al volver tras conectar, no
  // tiene que teclearlo todo otra vez.
  assert.strictEqual(filaVerificacion(usuario.id).nombre_negocio, 'Tacos UM');
});

test('el negocio se verifica al reintentar después de conectar Mercado Pago', async () => {
  const usuario = crearUsuario('negocio');
  aceptarTarjeta(usuario.id);
  linkResponde = { ok: true, motivo: null };
  const datos = {
    nombre_negocio: 'Tacos UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://www.instagram.com/tacos_um/',
  };

  const sinMp = await pedir('/negocio/solicitar', usuario.token, datos);
  assert.strictEqual(sinMp.body.estado, 'pendiente');

  conectarPagos(usuario.id);

  const conMp = await pedir('/negocio/solicitar', usuario.token, datos);
  assert.strictEqual(conMp.body.estado, 'verificado');
  assert.strictEqual(estaVerificado(usuario.id), true);
});

// ═══ ESTUDIANTE Y EXTERNO: la cuenta de pagos también ════════
//
// Conectar Mercado Pago es requisito en los TRES flujos, no solo en negocio:
// una cuenta verificada es una que puede cobrar dentro de la app.

test('un estudiante con el OTP correcto pero SIN Mercado Pago queda pendiente', async () => {
  const usuario = crearUsuario('estudiante');
  aceptarTarjeta(usuario.id);
  const correo = '1220999@alumno.um.edu.mx';

  const sol = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: correo,
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(sol.status, 200, `solicitar: ${JSON.stringify(sol.body)}`);
  const codigo = enviados.email.at(-1).codigo;
  const res = await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });

  // 200 y no 4xx: el código ERA correcto. Lo que falta es un requisito del
  // trámite, y eso es un estado, no un error de la petición.
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.verificado, false);
  assert.strictEqual(res.body.estado, 'pendiente');
  assert.strictEqual(res.body.campo, 'mercadopago');
  assert.ok(res.body.motivo, 'el estudiante tiene que saber qué le falta');
  assert.strictEqual(estaVerificado(usuario.id), false);

  // La identidad SÍ quedó probada: es lo que le permite ir a conectar su
  // cuenta y volver sin repetir el OTP.
  assert.ok(filaVerificacion(usuario.id).identidad_confirmada_en);
});

test('el estudiante se verifica al volver de conectar, sin un código nuevo', async () => {
  const usuario = crearUsuario('estudiante');
  aceptarTarjeta(usuario.id);
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1221000@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const codigo = enviados.email.at(-1).codigo;
  await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });
  assert.strictEqual(estaVerificado(usuario.id), false);

  conectarPagos(usuario.id);

  // Sin `codigo_otp`: conectar Mercado Pago obliga a salir al navegador, un
  // viaje que dura más que los 10 minutos de vida del código. Exigir uno
  // nuevo al volver es el bucle que hace que la gente abandone.
  const res = await pedir('/estudiante/confirmar', usuario.token, {});
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.verificado, true);
  assert.strictEqual(estaVerificado(usuario.id), true);

  // Y la carrera capturada en la solicitud original se copia igual a
  // `sellers`, aunque el paso final ya no evaluara ningún código.
  const fila = db.getDb().prepare('SELECT carrera FROM sellers WHERE id = ?').get(usuario.id);
  assert.strictEqual(fila.carrera, CARRERA_VALIDA);
});

test('un OTP incorrecto no prueba la identidad ni deja retomar sin código', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1221001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });

  const malo = await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: '000000' });
  assert.strictEqual(malo.status, 400);
  assert.strictEqual(filaVerificacion(usuario.id).identidad_confirmada_en, null);

  // Conectar la cuenta de pagos NO puede saltarse la prueba de identidad:
  // sin OTP válido, el atajo de "retomar sin código" no existe.
  conectarPagos(usuario.id);
  const sinCodigo = await pedir('/estudiante/confirmar', usuario.token, {});
  assert.strictEqual(sinCodigo.status, 400);
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('/estado avisa de que solo falta conectar Mercado Pago', async () => {
  const usuario = crearUsuario('estudiante');
  aceptarTarjeta(usuario.id);
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1221002@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  const res = await pedir('/estado', usuario.token);
  assert.strictEqual(res.body.verificado, false);
  assert.strictEqual(res.body.campo_rechazado, 'mercadopago');
  assert.ok(res.body.motivo_rechazo);
  // Con esto la app sabe que puede saltar directo al paso de conectar en vez
  // de volver a pedir un correo y un código.
  assert.strictEqual(res.body.identidad_confirmada, true);
});

// ═══ CIERRE AUTOMÁTICO AL CONECTAR LA CUENTA ═════════════════
//
// Conectar Mercado Pago se hace desde tres sitios y solo uno (el formulario)
// sabe reintentar. El cierre vive en el callback de OAuth, que es por donde
// pasan los tres.

const {
  completarVerificacionPendientePorPagos,
} = require('./verificacion');

test('conectar la cuenta cierra una verificación que solo esperaba eso', async () => {
  const usuario = crearUsuario('estudiante');
  aceptarTarjeta(usuario.id);
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1222000@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });
  assert.strictEqual(estaVerificado(usuario.id), false);

  conectarPagos(usuario.id);
  const cerrada = completarVerificacionPendientePorPagos(usuario.id);

  assert.strictEqual(cerrada, true);
  assert.strictEqual(estaVerificado(usuario.id), true);

  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.estado, 'verificado');
  assert.strictEqual(fila.campo_rechazado, null);
  assert.ok(fila.fecha_verificacion);

  // Las banderas rápidas de `sellers` se copian igual que en el cierre normal.
  const seller = db.getDb()
    .prepare('SELECT carrera, tipo_verificacion FROM sellers WHERE id = ?').get(usuario.id);
  assert.strictEqual(seller.carrera, CARRERA_VALIDA);
  assert.strictEqual(seller.tipo_verificacion, 'estudiante');
});

test('conectar la cuenta NO verifica a quien nunca confirmó su código', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1222001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });

  conectarPagos(usuario.id);

  // Tener con qué cobrar no dice nada sobre quién eres: sin OTP no hay
  // identidad probada, y conectar una cuenta no puede ser un atajo.
  assert.strictEqual(completarVerificacionPendientePorPagos(usuario.id), false);
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('una verificación externa pendiente de antes no se completa al conectar pagos', () => {
  const usuario = crearUsuario('particular');
  db.getDb()
    .prepare(
      `INSERT INTO verificaciones
       (usuario_id, tipo_cuenta, estado, identidad_confirmada_en, campo_rechazado, creado_en)
       VALUES (?, 'particular', 'pendiente', datetime('now'), 'mercadopago', datetime('now'))`,
    )
    .run(usuario.id);

  conectarPagos(usuario.id);

  assert.strictEqual(completarVerificacionPendientePorPagos(usuario.id), false);
  assert.strictEqual(estaVerificado(usuario.id), false);
  assert.strictEqual(filaVerificacion(usuario.id).estado, 'pendiente');
});

test('conectar la cuenta no rescata una verificación rechazada por el link', async () => {
  const usuario = crearUsuario('negocio');
  linkResponde = { ok: false, motivo: 'La página del link no existe.' };
  await pedir('/negocio/solicitar', usuario.token, {
    nombre_negocio: 'Café UM',
    ubicacion_lat: 19.7,
    ubicacion_lng: -101.1,
    link_red_social: 'https://facebook.com/noexiste',
  });
  linkResponde = { ok: true, motivo: null };

  conectarPagos(usuario.id);

  assert.strictEqual(completarVerificacionPendientePorPagos(usuario.id), false);
  assert.strictEqual(estaVerificado(usuario.id), false);
  assert.strictEqual(filaVerificacion(usuario.id).campo_rechazado, 'link_red_social');
});

// ═══ REQUISITOS NUEVOS: horario y stock ══════════════════════
//
// Una cuenta verificada es una a la que se le puede comprar sin sorpresas:
// que diga cuándo atiende y cuánto le queda de cada cosa. Sin esto se dan
// los dos casos que motivaron todo: comprar a un negocio cerrado, y comprar
// algo que ya no existe.

function crearProducto(sellerId, { stock = 5 } = {}) {
  const id = `p_verif_${++contador}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category, stock_quantity)
     VALUES (?, ?, '100', 100, ?, 'otros', ?)`,
  ).run(id, `Producto ${id}`, sellerId, stock);
  return id;
}

test('sin métodos de pago la verificación queda pendiente', async () => {
  const usuario = crearUsuario('estudiante', { metodos: null });
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550001@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });

  const res = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.verificado, false);
  assert.strictEqual(res.body.campo, 'metodos_pago');
  assert.match(res.body.motivo, /pago|Editar perfil/i,
    'tiene que decir exactamente qué configurar y dónde');
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('un alumno sin horario SÍ se verifica: el horario es cosa del negocio', async () => {
  // El perfil de vendedor solo persiste el horario de los negocios (ver
  // routes/sellers.js), así que exigírselo al alumno lo dejaba con un
  // requisito imposible y la verificación bloqueada para siempre.
  const usuario = crearUsuario('estudiante', { horario: null });
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550007@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });

  const res = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  assert.strictEqual(res.body.verificado, true);
  assert.strictEqual(estaVerificado(usuario.id), true);
});

test('la respuesta trae el checklist entero, no solo lo primero que falla', async () => {
  const usuario = crearUsuario('estudiante', { metodos: null });
  crearProducto(usuario.id, { stock: null });
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550002@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });

  const res = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  // Con la lista completa, quien arregla una cosa ve de una vez qué le
  // queda, en vez de descubrirlo de uno en uno a base de reintentos.
  const porId = Object.fromEntries(res.body.requisitos.map(r => [r.id, r]));
  assert.strictEqual(porId.metodos_pago.cumplido, false);
  assert.strictEqual(porId.stock_productos.cumplido, false);
});

test('un producto sin stock definido deja la verificación pendiente', async () => {
  const usuario = crearUsuario('estudiante');
  crearProducto(usuario.id, { stock: null });

  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550003@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const res = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  assert.strictEqual(res.body.verificado, false);
  assert.strictEqual(res.body.campo, 'stock_productos');
  assert.strictEqual(estaVerificado(usuario.id), false);
});

test('el mensaje nombra el producto concreto al que le falta stock', async () => {
  const usuario = crearUsuario('estudiante');
  const p = crearProducto(usuario.id, { stock: null });
  const titulo = db.getDb()
    .prepare('SELECT title FROM products WHERE id = ?').get(p).title;

  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550004@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  const res = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  assert.match(res.body.motivo, new RegExp(titulo),
    'decir "algún producto" obliga al vendedor a revisarlos todos a mano');
});

test('al arreglar el stock se completa la verificación sin código nuevo', async () => {
  const usuario = crearUsuario('estudiante');
  const p = crearProducto(usuario.id, { stock: null });

  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550005@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });
  assert.strictEqual(estaVerificado(usuario.id), false);

  db.getDb().prepare('UPDATE products SET stock_quantity = 7 WHERE id = ?').run(p);

  const res = await pedir('/estudiante/confirmar', usuario.token, {});
  assert.strictEqual(res.body.verificado, true);
  assert.strictEqual(estaVerificado(usuario.id), true);
});

test('conectar Mercado Pago NO verifica si además falta el inventario', async () => {
  // El cierre automático del callback de OAuth tiene que mirar la lista
  // completa. Si solo mirara la cuenta de cobros, conectarla sería una
  // puerta trasera que se salta todos los demás requisitos.
  const usuario = crearUsuario('estudiante');
  crearProducto(usuario.id, { stock: null });
  aceptarTarjeta(usuario.id);

  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550006@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  conectarPagos(usuario.id);

  assert.strictEqual(completarVerificacionPendientePorPagos(usuario.id), false);
  assert.strictEqual(estaVerificado(usuario.id), false);
});


// ═══ NEGOCIO · REVISIÓN MANUAL ═════════════════════════════

test('la solicitud manual guarda responsable y no duplica evidencia al reintentar', async t => {
  const usuario = crearUsuario('negocio', { logoUrl: null });

  t.after(() => {
    const documentos = db.getDb().prepare(
      'SELECT file_url FROM verification_documents WHERE usuario_id = ?',
    ).all(usuario.id);
    for (const documento of documentos) {
      fs.rmSync(
        path.join(__dirname, '..', '..', documento.file_url.slice(1)),
        { force: true },
      );
    }
  });

  db.getDb().prepare(
    'UPDATE sellers SET businessCategory = ? WHERE id = ?',
  ).run('food', usuario.id);

  const frente = await subirDocumento(
    usuario.token,
    'responsible_ine_front',
    'imagen-frente',
    'frente.jpg',
  );
  const reverso = await subirDocumento(
    usuario.token,
    'responsible_ine_back',
    'imagen-reverso',
    'reverso.jpg',
  );
  const evidencia1 = await subirDocumento(
    usuario.token,
    'additional_evidence',
    'mismo-contenido',
    'permiso.jpg',
  );
  const evidencia2 = await subirDocumento(
    usuario.token,
    'additional_evidence',
    'mismo-contenido',
    'permiso-reintento.jpg',
  );

  assert.strictEqual(frente.status, 201, JSON.stringify(frente.body));
  assert.strictEqual(reverso.status, 201, JSON.stringify(reverso.body));
  assert.strictEqual(evidencia1.status, 201, JSON.stringify(evidencia1.body));
  assert.strictEqual(evidencia2.status, 200, JSON.stringify(evidencia2.body));
  assert.strictEqual(evidencia2.body.duplicate, true);

  const solicitud = await pedir('/negocio/solicitar-manual', usuario.token, {
    responsable_nombre: 'María Responsable',
  });
  assert.strictEqual(solicitud.status, 201, JSON.stringify(solicitud.body));
  assert.strictEqual(solicitud.body.estado, 'pendiente');
  assert.strictEqual(estaVerificado(usuario.id), false);
  assert.strictEqual(
    filaVerificacion(usuario.id).responsable_negocio,
    'María Responsable',
  );

  const adicionales = db.getDb().prepare(
    "SELECT COUNT(*) AS n FROM verification_documents WHERE usuario_id = ? AND doc_type = 'additional_evidence'",
  ).get(usuario.id).n;
  assert.strictEqual(adicionales, 1);

  const revision = await fetch(
    baseUrl + '/api/revision/verificaciones?status=pending',
    { headers: { 'x-revision-api-key': 'revision-prueba' } },
  );
  assert.strictEqual(revision.status, 200);
  const cola = await revision.json();
  const enRevision = cola.requests.find(item => item.id === usuario.id);
  assert.ok(enRevision);
  assert.strictEqual(enRevision.business.responsibleName, 'María Responsable');
  assert.deepStrictEqual(
    enRevision.documents.map(documento => documento.type),
    [
      'responsible_ine_front',
      'responsible_ine_back',
      'additional_evidence',
    ],
  );

});

// ═══ MERCADO_PAGO_HABILITADO=false (estado real de producción hoy) ═══
//
// Con el frontend teniendo la integración comentada/oculta (ver
// lib/features/payments/mercado_pago_flag.dart), nadie puede conectar una
// cuenta desde la app. Estos tests prueban que, con el flag apagado, ni una
// solicitud nueva ni una que ya estaba atorada por 'mercadopago' se quedan
// bloqueadas.

test('con el flag apagado, una cuenta negocio que acepta tarjeta se verifica SIN conectar Mercado Pago', async () => {
  const anterior = process.env.MERCADO_PAGO_HABILITADO;
  process.env.MERCADO_PAGO_HABILITADO = 'false';
  try {
    const usuario = crearUsuario('negocio');
    aceptarTarjeta(usuario.id);
    linkResponde = { ok: true, motivo: null };

    const res = await pedir('/negocio/solicitar', usuario.token, {
      nombre_negocio: 'Tacos UM',
      ubicacion_lat: 19.7,
      ubicacion_lng: -101.1,
      link_red_social: 'https://www.instagram.com/tacos_um/',
    });

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.verificado, true);
    assert.strictEqual(estaVerificado(usuario.id), true);
  } finally {
    process.env.MERCADO_PAGO_HABILITADO = anterior;
  }
});

test('reconciliarVerificacionesPendientesPorMercadoPago desatora, con el flag apagado, a quien se quedó esperando SOLO eso', async () => {
  // Simula una cuenta que quedó 'pendiente' por 'mercadopago' ANTES de
  // apagar el flag (con la validación original activa), y comprueba que la
  // reconciliación de arranque (ver index.js) la resuelve sin que nadie
  // toque nada.
  const usuario = crearUsuario('estudiante');
  aceptarTarjeta(usuario.id);

  process.env.MERCADO_PAGO_HABILITADO = 'true';
  const solicitud = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1990002@alumno.um.edu.mx',
    tipo: 'estudiante',
    carrera: CARRERA_VALIDA,
  });
  assert.strictEqual(solicitud.status, 200, `solicitar: ${JSON.stringify(solicitud.body)}`);
  const confirmacion = await pedir('/estudiante/confirmar', usuario.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });
  assert.strictEqual(confirmacion.body.campo, 'mercadopago');
  assert.strictEqual(estaVerificado(usuario.id), false);

  process.env.MERCADO_PAGO_HABILITADO = 'false';
  try {
    const {
      reconciliarVerificacionesPendientesPorMercadoPago,
    } = require('./verificacion');
    const resueltas = reconciliarVerificacionesPendientesPorMercadoPago();

    assert.ok(resueltas >= 1);
    assert.strictEqual(estaVerificado(usuario.id), true);
  } finally {
    process.env.MERCADO_PAGO_HABILITADO = 'true';
  }
});
