// El enigma escondido: el gatillo en comentarios y el marcador de quién lo
// resolvió primero.
//
// Los tests no conocen la frase ni la respuesta como constantes propias: las
// leen del mismo módulo que las valida. Escribirlas aquí en claro las
// publicaría en el repositorio, que es exactamente lo que secreto/enigma.js
// evita — y un test que las repita se convierte en la pista más fácil del
// juego.
//
// Lo que sí se puede afirmar sin destriparlo: que una frase cualquiera NO
// abre la puerta, que la buena no deja rastro en el hilo, y que las
// posiciones se reparten en orden y no se mueven.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-secreto-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');

db.initDatabase();

const { products } = require('../data');
const enigma = require('../secreto/enigma');

// ─── Frase y respuesta, redescubiertas ───────────────────────
//
// Los candidatos se prueban contra el validador real hasta dar con el que
// pasa. Si alguien cambia la frase o la respuesta en enigma.js sin tocar
// esta lista, el test falla con "hay que actualizar los candidatos" en vez
// de fallar en veinte asserts sueltos sin explicar por qué.

function descubrir(candidatos, predicado, queEs) {
  const acertado = candidatos.find(predicado);
  assert.ok(
    acertado,
    `Ninguno de los candidatos de prueba es ${queEs} actual: actualiza esta lista al cambiar secreto/enigma.js`,
  );
  return acertado;
}

const FRASE = descubrir(
  ['el primero en llegar', 'el ultimo en llegar', 'abrete sesamo'],
  enigma.esFraseDeEntrada,
  'la frase de entrada',
);

const RESPUESTA = descubrir(
  ['marketplaceum', 'mercadito', 'espejo'],
  enigma.esRespuestaCorrecta,
  'la respuesta del acertijo',
);

// ─── Servidor de pruebas ─────────────────────────────────────

let baseUrl;
let servidor;

test.before(async () => {
  const app = express();
  app.use(express.json());
  require('./comments').register(app);
  require('./secreto').register(app);
  servidor = http.createServer(app);
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${servidor.address().port}`;
});

test.after(async () => {
  await new Promise(r => servidor.close(r));
});

// ─── Helpers ─────────────────────────────────────────────────

let contador = 0;

function crearUsuario({ verificado = true } = {}) {
  const id = `u_secreto_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
       VALUES (?, ?, ?, 'TT', '', 0, ?, 'estudiante')`,
    )
    .run(id, `Test ${id}`, `${id}@ejemplo.com`, verificado ? 1 : 0);
  return { id, token: generateToken(id) };
}

function crearProducto(duenoId) {
  const producto = { id: `p_secreto_${++contador}`, title: 'Bici', seller: duenoId };
  db.getDb()
    .prepare('INSERT INTO products (id, title, price, seller) VALUES (?, ?, ?, ?)')
    .run(producto.id, producto.title, '100', duenoId);
  products.push(producto);
  return producto;
}

async function comentar(productoId, token, texto) {
  const res = await fetch(`${baseUrl}/api/products/${productoId}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ texto }),
  });
  return { status: res.status, body: await res.json() };
}

async function leerComentarios(productoId) {
  const res = await fetch(`${baseUrl}/api/products/${productoId}/comments`);
  return res.json();
}

async function resolver(token, respuesta) {
  const res = await fetch(`${baseUrl}/api/secreto/resolver`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ respuesta }),
  });
  return { status: res.status, body: await res.json() };
}

/**
 * El endpoint frena intentos seguidos del mismo usuario. Los tests que
 * necesitan varios intentos con la misma cuenta esperan ese hueco en vez de
 * bajarle el freno a producción por comodidad.
 */
function esperarFreno() {
  return new Promise(r => setTimeout(r, (enigma.SEGUNDOS_ENTRE_INTENTOS + 0.2) * 1000));
}

// ═══ El gatillo en comentarios ═══════════════════════════════

test('la frase secreta abre la puerta y no se publica como comentario', async () => {
  const usuario = crearUsuario();
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token, FRASE);

  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.body.secreto, true);
  assert.strictEqual(res.body.comment, undefined, 'no debe devolver un comentario');

  const hilo = await leerComentarios(producto.id);
  assert.strictEqual(hilo.total, 0, 'el hilo debe quedar como si nadie hubiera escrito');
  assert.strictEqual(hilo.comments.length, 0);
});

test('la frase se reconoce con mayúsculas, acentos y puntuación de más', async () => {
  const usuario = crearUsuario();
  const producto = crearProducto(usuario.id);

  const disfrazada = `  ${FRASE.toUpperCase()}...!  `;
  const res = await comentar(producto.id, usuario.token, disfrazada);

  assert.strictEqual(res.body.secreto, true, JSON.stringify(res.body));
});

test('un comentario normal sigue publicándose como siempre', async () => {
  const usuario = crearUsuario();
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token, 'Muy buen producto, gracias.');

  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.body.secreto, undefined);
  assert.strictEqual(res.body.comment.texto, 'Muy buen producto, gracias.');

  const hilo = await leerComentarios(producto.id);
  assert.strictEqual(hilo.total, 1);
});

test('una cuenta sin verificar también dispara el secreto: basta la sesión', async () => {
  const usuario = crearUsuario({ verificado: false });
  const producto = crearProducto(usuario.id);

  const res = await comentar(producto.id, usuario.token, FRASE);

  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.body.secreto, true);

  // Y sigue sin dejar rastro en el hilo.
  const hilo = await leerComentarios(producto.id);
  assert.strictEqual(hilo.total, 0);
});

// ═══ El acertijo ═════════════════════════════════════════════

test('sin sesión no se puede intentar', async () => {
  const res = await resolver(null, RESPUESTA);
  assert.strictEqual(res.status, 401);
});

test('una respuesta equivocada no es un error y no registra nada', async () => {
  const usuario = crearUsuario();

  const res = await resolver(usuario.token, 'una respuesta cualquiera');

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.correcto, false);
  assert.strictEqual(db.getResolucionEnigma(usuario.id), undefined);
});

test('la respuesta correcta registra al usuario y devuelve su posición', async () => {
  const antes = db.contarResolucionesEnigma();
  const usuario = crearUsuario();

  const res = await resolver(usuario.token, RESPUESTA);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.correcto, true);
  assert.strictEqual(res.body.posicion, antes + 1);
  assert.strictEqual(res.body.repetida, false);
  assert.ok(res.body.resueltoEn, 'debe traer la fecha de la hazaña');
});

test('las posiciones se reparten en el orden en que se resuelve', async () => {
  const antes = db.contarResolucionesEnigma();
  const primero = crearUsuario();
  const segundo = crearUsuario();

  const uno = await resolver(primero.token, RESPUESTA);
  const dos = await resolver(segundo.token, RESPUESTA);

  assert.strictEqual(uno.body.posicion, antes + 1);
  assert.strictEqual(dos.body.posicion, antes + 2);
});

test('volver a acertar conserva la posición original', async () => {
  const usuario = crearUsuario();

  const primera = await resolver(usuario.token, RESPUESTA);
  await esperarFreno();
  const segunda = await resolver(usuario.token, RESPUESTA);

  assert.strictEqual(segunda.body.posicion, primera.body.posicion);
  assert.strictEqual(segunda.body.resueltoEn, primera.body.resueltoEn);
  assert.strictEqual(segunda.body.repetida, true, 'la segunda vez no es una hazaña nueva');
});

test('dos intentos seguidos del mismo usuario chocan con el freno', async () => {
  const usuario = crearUsuario();

  await resolver(usuario.token, 'primer tanteo');
  const segundo = await resolver(usuario.token, 'segundo tanteo');

  assert.strictEqual(segundo.status, 429);
  assert.ok(segundo.body.retryAfter >= 1);
});
