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

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');
const { crearRutasVerificacion } = require('./verificacion');

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
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

// ─── Helpers ─────────────────────────────────────────────────

let contador = 0;

/** Crea un vendedor real en la base temporal y devuelve su id y token. */
function crearUsuario(tipoCuenta, { verificado = false } = {}) {
  const id = `u_test_${tipoCuenta}_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
       VALUES (?, ?, ?, 'TT', '', ?, ?, ?)`,
    )
    .run(id, `Test ${id}`, `${id}@ejemplo.com`, tipoCuenta === 'negocio' ? 1 : 0, verificado ? 1 : 0, tipoCuenta);
  return { id, token: generateToken(id) };
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

function filaVerificacion(usuarioId) {
  return db.getDb().prepare('SELECT * FROM verificaciones WHERE usuario_id = ?').get(usuarioId);
}

function estaVerificado(usuarioId) {
  return !!db.getDb().prepare('SELECT verified FROM sellers WHERE id = ?').get(usuarioId).verified;
}

// ═══ ESTUDIANTE ══════════════════════════════════════════════

test('un estudiante se verifica con el código enviado a su correo institucional', async () => {
  const usuario = crearUsuario('estudiante');
  const correo = '1220326@alumno.um.edu.mx';

  const solicitud = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: correo,
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
  assert.ok(fila.fecha_verificacion);
});

test('el código deja de existir en la base después de usarse', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1330001@alumno.um.edu.mx',
  });
  const { codigo } = enviados.email.at(-1);
  await pedir('/estudiante/confirmar', usuario.token, { codigo_otp: codigo });

  const fila = filaVerificacion(usuario.id);
  assert.strictEqual(fila.codigo_otp_email, null);
  assert.strictEqual(fila.codigo_otp_email_expira, null);
});

test('el mismo código no sirve dos veces', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1330002@alumno.um.edu.mx',
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
  });
  assert.strictEqual(res.status, 200);
  assert.strictEqual(filaVerificacion(usuario.id).matricula, '1230002');
});

test('un código nuevo invalida el anterior', async () => {
  const usuario = crearUsuario('estudiante');
  const cuerpo = { correo_institucional: '1230003@alumno.um.edu.mx' };
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
  const correo = '1440001@alumno.um.edu.mx';
  await pedir('/estudiante/solicitar', primero.token, {
    correo_institucional: correo,
  });
  await pedir('/estudiante/confirmar', primero.token, {
    codigo_otp: enviados.email.at(-1).codigo,
  });

  const segundo = crearUsuario('estudiante');
  const res = await pedir('/estudiante/solicitar', segundo.token, {
    correo_institucional: correo,
  });
  assert.strictEqual(res.status, 409);
  assert.match(res.body.error, /ya está registrado|ya esta registrado/i);
});

test('rechaza un código incorrecto e informa los intentos restantes', async () => {
  const usuario = crearUsuario('estudiante');
  await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1550001@alumno.um.edu.mx',
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
  const cuerpo = { correo_institucional: correo };
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

test('una cuenta externa se verifica con el código enviado por SMS', async () => {
  const usuario = crearUsuario('particular');

  const solicitud = await pedir('/externo/solicitar', usuario.token, {
    telefono: '(443) 123-4567',
  });
  assert.strictEqual(solicitud.status, 200);
  assert.strictEqual(enviados.sms.at(-1).destino, '+524431234567');

  const confirmacion = await pedir('/externo/confirmar', usuario.token, {
    codigo_otp: enviados.sms.at(-1).codigo,
  });
  assert.strictEqual(confirmacion.status, 200);
  assert.strictEqual(estaVerificado(usuario.id), true);
  assert.strictEqual(filaVerificacion(usuario.id).telefono, '+524431234567');
});

test('rechaza un teléfono con menos de 10 dígitos', async () => {
  const usuario = crearUsuario('particular');
  const res = await pedir('/externo/solicitar', usuario.token, { telefono: '44312' });
  assert.strictEqual(res.status, 400);
});

// ═══ GUARDAS COMPARTIDAS ═════════════════════════════════════

test('bloquea el flujo si la cuenta ya está verificada', async () => {
  const usuario = crearUsuario('estudiante', { verificado: true });
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1880001@alumno.um.edu.mx',
  });
  assert.strictEqual(res.status, 409);
  assert.match(res.body.error, /ya está verificada|ya esta verificada/i);
});

test('impide que un negocio se verifique por el flujo de estudiante', async () => {
  const usuario = crearUsuario('negocio');
  const res = await pedir('/estudiante/solicitar', usuario.token, {
    correo_institucional: '1880002@alumno.um.edu.mx',
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

  await pedir('/estudiante/solicitar', atacante.token, {
    correo_institucional: '1990001@alumno.um.edu.mx',
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
  assert.deepStrictEqual(res.body, {
    tipo_cuenta: 'particular',
    estado: 'pendiente',
    verificado: false,
    motivo_rechazo: null,
    campo_rechazado: null,
    puede_reintentar_en: 0,
  });
});

test('reporta el estado verificado después de completar el flujo', async () => {
  const usuario = crearUsuario('negocio');
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
