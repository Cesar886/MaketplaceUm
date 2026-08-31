// Quién puede comentar.
//
// La regla es "cuenta verificada", sin importar por qué flujo pasó: alumnos y
// personal verifican con OTP al correo institucional, negocios y externos con
// OTP al teléfono. Los cuatro terminan con `sellers.verified = 1`, así que la
// puerta es esa bandera y no `tipo_verificacion`, que solo se llena en el
// flujo institucional y dejaría fuera a negocios y externos ya verificados.
//
// Los tests van contra el endpoint real y una base temporal (mismo patrón que
// verificacion.test.js): lo que importa aquí es el permiso tal como lo aplica
// la ruta, no una función suelta.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-comments-')),
  'test.db',
);
// auth.js revienta al cargarse si no hay JWT_SECRET (a propósito: ver el
// comentario ahí). El test firma sus propios tokens, así que le basta un
// secreto cualquiera, pero tiene que estar puesto ANTES del require.
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');

db.initDatabase();

const { products } = require('../data');
const { register } = require('./comments');

// ─── Servidor de pruebas ─────────────────────────────────────

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  register(app);
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
function crearUsuario(tipoCuenta, { verificado = false, tipoVerificacion = null } = {}) {
  const id = `u_test_${tipoCuenta}_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta, tipo_verificacion)
       VALUES (?, ?, ?, 'TT', '', ?, ?, ?, ?)`,
    )
    .run(
      id,
      `Test ${id}`,
      `${id}@ejemplo.com`,
      tipoCuenta === 'negocio' ? 1 : 0,
      verificado ? 1 : 0,
      tipoCuenta,
      tipoVerificacion,
    );
  return { id, token: generateToken(id) };
}

/**
 * Publicación de prueba, con el propio autor como dueño: así el POST no entra
 * al camino de notificación/push, que no es lo que este archivo verifica.
 */
function crearProducto(duenoId) {
  const producto = { id: `p_test_${++contador}`, title: 'Bici', seller: duenoId };
  // En la tabla porque product_comments tiene FOREIGN KEY hacia products, y
  // en el array en memoria porque la ruta resuelve el producto desde ahí.
  db.getDb()
    .prepare('INSERT INTO products (id, title, price, seller) VALUES (?, ?, ?, ?)')
    .run(producto.id, producto.title, '100', duenoId);
  products.push(producto);
  return producto;
}

async function comentar(productoId, token, texto = 'Muy buen producto, gracias.') {
  const res = await fetch(`${baseUrl}/api/products/${productoId}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ texto }),
  });
  return { status: res.status, body: await res.json() };
}

// ═══ Cuentas verificadas: pueden comentar ════════════════════

test('un alumno verificado puede comentar', async () => {
  const usuario = crearUsuario('estudiante', { verificado: true, tipoVerificacion: 'estudiante' });
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token);

  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.body.comment.author.id, usuario.id);
});

test('personal UM verificado puede comentar', async () => {
  const usuario = crearUsuario('estudiante', { verificado: true, tipoVerificacion: 'empleado' });
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token);

  assert.strictEqual(res.status, 201);
});

test('un negocio verificado puede comentar aunque no tenga tipo_verificacion', async () => {
  // Verifica por SMS, así que `tipo_verificacion` queda nula: es exactamente
  // el caso que la puerta anterior (atada a esa columna) dejaba fuera.
  const usuario = crearUsuario('negocio', { verificado: true });
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token);

  assert.strictEqual(res.status, 201, JSON.stringify(res.body));
});

test('un externo verificado puede comentar aunque no tenga tipo_verificacion', async () => {
  // 'particular' es lo que la UI llama "externo".
  const usuario = crearUsuario('particular', { verificado: true });
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token);

  assert.strictEqual(res.status, 201, JSON.stringify(res.body));
});

// ═══ Cuentas sin verificar: no pueden ════════════════════════

for (const tipo of ['estudiante', 'negocio', 'particular']) {
  test(`una cuenta ${tipo} sin verificar recibe 403 NO_VERIFICADO`, async () => {
    const usuario = crearUsuario(tipo);
    const producto = crearProducto(usuario.id);

    const res = await comentar(producto.id, usuario.token);

    assert.strictEqual(res.status, 403);
    assert.strictEqual(res.body.code, 'NO_VERIFICADO');
  });
}

test('sin sesión no se puede comentar', async () => {
  const dueno = crearUsuario('estudiante', { verificado: true });
  const producto = crearProducto(dueno.id);

  const res = await fetch(`${baseUrl}/api/products/${producto.id}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ texto: 'Hola desde el anonimato.' }),
  });

  assert.strictEqual(res.status, 401);
});

test('leer comentarios sigue siendo abierto: no exige sesión ni verificación', async () => {
  const usuario = crearUsuario('negocio', { verificado: true });
  const producto = crearProducto(usuario.id);
  await comentar(producto.id, usuario.token, 'Comentario visible para cualquiera.');

  const res = await fetch(`${baseUrl}/api/products/${producto.id}/comments`);
  const body = await res.json();

  assert.strictEqual(res.status, 200);
  assert.strictEqual(body.total, 1);
});

test('el autor de un comentario trae socioFundador, para la palomita verde', async () => {
  const usuario = crearUsuario('estudiante', { verificado: true });
  db.getDb()
    .prepare('UPDATE sellers SET socio_fundador = 1 WHERE id = ?')
    .run(usuario.id);
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token);

  assert.strictEqual(res.body.comment.author.socioFundador, true);
});

test('el autor de un comentario sin la insignia trae socioFundador en false', async () => {
  const usuario = crearUsuario('estudiante', { verificado: true });
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token);

  assert.strictEqual(res.body.comment.author.socioFundador, false);
});
