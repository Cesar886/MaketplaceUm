// Tests de los endpoints de preguntas y respuestas.
//
// Aquí viven las reglas que NO pueden depender del cliente:
//
//  1. Responde solo el dueño. Es la regla de la que cuelga todo el valor
//     del hilo: si otro pudiera responder, una respuesta dejaría de ser
//     "lo dijo el vendedor". Se prueba mandando el intento con sesión
//     válida de otra cuenta, que es como se vería un cliente manipulado.
//  2. Nadie pregunta en su propio producto.
//  3. Preguntar NO exige verificación (a diferencia de comentar), solo
//     sesión. Es fácil "arreglar" esto de más copiando el guard de
//     comentarios, y el síntoma sería un 403 a usuarios legítimos.
//  4. Una pregunta, una respuesta: repetir el POST edita, no duplica.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-preguntas-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken } = require('../auth');

db.initDatabase();

const { products } = require('../data');
const { register, MAX_PREGUNTAS_POR_PRODUCTO } = require('./questions');

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

let contador = 0;

function crearUsuario({ verificado = false } = {}) {
  const id = `u_${++contador}`;
  db.getDb().prepare(`
    INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
    VALUES (?, ?, ?, 'UU', '', 0, ?, 'estudiante')
  `).run(id, `Usuario ${id}`, `${id}@ejemplo.com`, verificado ? 1 : 0);
  return { id, token: generateToken(id) };
}

function crearProducto(duenoId) {
  const id = `p_${++contador}`;
  db.getDb().prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller, created_at)
    VALUES (?, ?, '100', 100, 'cat', 'desc', ?, datetime('now'))
  `).run(id, `Producto ${id}`, duenoId);
  const producto = db.getProductById(id);
  products.push(producto);
  return producto;
}

/**
 * Escenario completo: un producto, su dueño y alguien que pregunta. Las
 * preguntas van con `saltarEspera` porque el rate limit global (30 s entre
 * preguntas del mismo usuario) frenaría al segundo POST de cualquier test.
 */
function escenario() {
  const dueno = crearUsuario();
  const curioso = crearUsuario();
  const producto = crearProducto(dueno.id);
  return { dueno, curioso, producto };
}

/** Envejece las preguntas de un usuario para esquivar la espera mínima. */
function envejecerPreguntas(userId, minutos = 5) {
  db.getDb().prepare(
    "UPDATE product_questions SET created_at = datetime('now', '-' || ? || ' minutes') WHERE asked_by = ?",
  ).run(minutos, userId);
}

async function pedir(ruta, { metodo = 'GET', token, cuerpo } = {}) {
  const res = await fetch(`${baseUrl}${ruta}`, {
    method: metodo,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}

function preguntar(producto, usuario, texto = '¿Sigue disponible?') {
  return pedir(`/api/products/${producto.id}/questions`, {
    metodo: 'POST',
    token: usuario.token,
    cuerpo: { texto },
  });
}

function responder(questionId, usuario, texto = 'Sí, todavía lo tengo.') {
  return pedir(`/api/questions/${questionId}/answer`, {
    metodo: 'POST',
    token: usuario.token,
    cuerpo: { texto },
  });
}

// ═══ Preguntar ═══════════════════════════════════════════════

test('cualquier cuenta con sesión puede preguntar, sin estar verificada', () => {
  const { producto, curioso } = escenario();

  return preguntar(producto, curioso).then(res => {
    assert.strictEqual(res.status, 201, JSON.stringify(res.body));
    assert.strictEqual(res.body.question.status, 'pending');
    assert.strictEqual(res.body.question.answerText, null);
    assert.strictEqual(res.body.question.author.verified, false);
  });
});

test('sin sesión no se puede preguntar', async () => {
  const { producto } = escenario();

  const res = await pedir(`/api/products/${producto.id}/questions`, {
    metodo: 'POST',
    cuerpo: { texto: '¿Hola?' },
  });

  assert.strictEqual(res.status, 401);
});

test('el dueño no puede preguntar en su propia publicación', async () => {
  const { producto, dueno } = escenario();

  const res = await preguntar(producto, dueno);

  assert.strictEqual(res.status, 403);
  assert.strictEqual(res.body.code, 'ES_TU_PRODUCTO');
  assert.strictEqual(db.countProductQuestions(producto.id), 0);
});

test('una pregunta vacía o de puro marcado se rechaza', async () => {
  const { producto, curioso } = escenario();

  const vacia = await preguntar(producto, curioso, '   ');
  assert.strictEqual(vacia.status, 400);

  // Puro marcado: al quitar las etiquetas no queda texto. El contenido
  // DENTRO de una etiqueta sí sobrevive (se limpia el marcado, no el
  // mensaje), así que el caso vacío es este y no "<b>hola</b>".
  const soloEtiquetas = await preguntar(producto, curioso, '<br/><hr/>');
  assert.strictEqual(soloEtiquetas.status, 400);
});

test('el texto se guarda saneado, sin etiquetas HTML', async () => {
  const { producto, curioso } = escenario();

  const res = await preguntar(producto, curioso, '¿Tienes <b>más</b> fotos?');

  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.body.question.questionText, '¿Tienes más fotos?');
});

test('preguntar en un producto inexistente da 404', async () => {
  const { curioso } = escenario();

  const res = await pedir('/api/products/no_existe/questions', {
    metodo: 'POST',
    token: curioso.token,
    cuerpo: { texto: '¿Hola?' },
  });

  assert.strictEqual(res.status, 404);
});

test('hay una espera mínima entre preguntas del mismo usuario', async () => {
  const { producto, curioso } = escenario();

  const primera = await preguntar(producto, curioso, 'Primera');
  assert.strictEqual(primera.status, 201);

  const segunda = await preguntar(producto, curioso, 'Segunda, inmediata');
  assert.strictEqual(segunda.status, 429);
  assert.ok(segunda.body.retryAfter > 0);
});

test('un usuario no puede inundar la misma publicación', async () => {
  const { producto, curioso } = escenario();

  for (let i = 0; i < MAX_PREGUNTAS_POR_PRODUCTO; i++) {
    const res = await preguntar(producto, curioso, `Pregunta ${i}`);
    assert.strictEqual(res.status, 201, `la #${i} debería pasar`);
    envejecerPreguntas(curioso.id);
  }

  const unaMas = await preguntar(producto, curioso, 'Una más');
  assert.strictEqual(unaMas.status, 429);
  assert.strictEqual(unaMas.body.code, 'LIMITE_POR_PRODUCTO');
});

test('el límite es por publicación, no por usuario: puede preguntar en otra', async () => {
  const { producto, curioso } = escenario();
  const otroProducto = crearProducto(crearUsuario().id);

  for (let i = 0; i < MAX_PREGUNTAS_POR_PRODUCTO; i++) {
    await preguntar(producto, curioso, `Pregunta ${i}`);
    envejecerPreguntas(curioso.id);
  }

  const enOtro = await preguntar(otroProducto, curioso, '¿Y este?');
  assert.strictEqual(enOtro.status, 201, JSON.stringify(enOtro.body));
});

// ═══ Responder ═══════════════════════════════════════════════

test('el dueño responde y la pregunta pasa a respondida', async () => {
  const { producto, dueno, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);

  const res = await responder(creada.question.id, dueno);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.question.status, 'answered');
  assert.strictEqual(res.body.question.answerText, 'Sí, todavía lo tengo.');
  assert.ok(res.body.question.answeredAt);
  assert.strictEqual(res.body.pendingCount, 0);
});

test('otro usuario con sesión válida NO puede responder: 403', async () => {
  const { producto, curioso } = escenario();
  const intruso = crearUsuario({ verificado: true });
  const { body: creada } = await preguntar(producto, curioso);

  const res = await responder(creada.question.id, intruso, 'Yo contesto por él');

  assert.strictEqual(res.status, 403);
  assert.strictEqual(res.body.code, 'NO_ERES_EL_VENDEDOR');
  // Y no dejó rastro: la pregunta sigue pendiente y sin texto de respuesta.
  const fila = db.getProductQuestionRow(creada.question.id);
  assert.strictEqual(fila.status, 'pending');
  assert.strictEqual(fila.answer_text, null);
});

test('ni siquiera el que preguntó puede responderse a sí mismo', async () => {
  const { producto, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);

  const res = await responder(creada.question.id, curioso, 'Me respondo solo');

  assert.strictEqual(res.status, 403);
});

test('sin sesión no se puede responder', async () => {
  const { producto, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);

  const res = await pedir(`/api/questions/${creada.question.id}/answer`, {
    metodo: 'POST',
    cuerpo: { texto: 'Hola' },
  });

  assert.strictEqual(res.status, 401);
});

test('responder de nuevo edita la respuesta, no crea otra', async () => {
  const { producto, dueno, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);

  await responder(creada.question.id, dueno, 'Como 30 cm.');
  const corregida = await responder(creada.question.id, dueno, 'Perdón, 35 cm.');

  assert.strictEqual(corregida.status, 200);
  assert.strictEqual(corregida.body.question.answerText, 'Perdón, 35 cm.');
  assert.strictEqual(db.countProductQuestions(producto.id), 1);
});

test('una respuesta vacía se rechaza y no borra la que ya había', async () => {
  const { producto, dueno, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);
  await responder(creada.question.id, dueno, 'Respuesta buena');

  const res = await responder(creada.question.id, dueno, '   ');

  assert.strictEqual(res.status, 400);
  assert.strictEqual(
    db.getProductQuestionRow(creada.question.id).answer_text,
    'Respuesta buena',
  );
});

test('responder una pregunta inexistente da 404', async () => {
  const { dueno } = escenario();

  const res = await responder('q_no_existe', dueno);

  assert.strictEqual(res.status, 404);
});

// ═══ Listados ════════════════════════════════════════════════

test('el listado es público: se lee sin sesión', async () => {
  const { producto, curioso } = escenario();
  await preguntar(producto, curioso, '¿Pregunta pública?');

  const res = await pedir(`/api/products/${producto.id}/questions`);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.questions.length, 1);
  assert.strictEqual(res.body.total, 1);
  assert.strictEqual(res.body.pendingCount, 1);
});

test('el preview prioriza respondidas y trae los contadores', async () => {
  const { producto, dueno, curioso } = escenario();
  const otroCurioso = crearUsuario();

  const { body: primera } = await preguntar(producto, curioso, 'Será respondida');
  await preguntar(producto, otroCurioso, 'Quedará pendiente');
  await responder(primera.question.id, dueno);

  const res = await pedir(`/api/products/${producto.id}/questions?preview=true&limit=3`);

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.questions[0].id, primera.question.id);
  assert.strictEqual(res.body.questions[0].status, 'answered');
  assert.strictEqual(res.body.total, 2);
  assert.strictEqual(res.body.pendingCount, 1);
  assert.strictEqual(res.body.nextCursor, null);
});

test('filter=pending devuelve solo lo que falta por responder', async () => {
  const { producto, dueno, curioso } = escenario();
  const otroCurioso = crearUsuario();
  const { body: respondida } = await preguntar(producto, curioso, 'Respondida');
  const { body: pendiente } = await preguntar(producto, otroCurioso, 'Pendiente');
  await responder(respondida.question.id, dueno);

  const res = await pedir(`/api/products/${producto.id}/questions?filter=pending`);

  assert.deepStrictEqual(
    res.body.questions.map(q => q.id),
    [pendiente.question.id],
  );
});

test('el listado pagina con cursor y no repite', async () => {
  const { producto } = escenario();
  const ids = [];
  for (let i = 0; i < 4; i++) {
    const quien = crearUsuario();
    const { body } = await preguntar(producto, quien, `Pregunta ${i}`);
    ids.push(body.question.id);
  }

  const primera = await pedir(`/api/products/${producto.id}/questions?limit=2`);
  assert.strictEqual(primera.body.questions.length, 2);
  assert.ok(primera.body.nextCursor);

  const segunda = await pedir(
    `/api/products/${producto.id}/questions?limit=2&cursor=${encodeURIComponent(primera.body.nextCursor)}`,
  );

  const vistas = [
    ...primera.body.questions.map(q => q.id),
    ...segunda.body.questions.map(q => q.id),
  ];
  assert.strictEqual(new Set(vistas).size, 4);
  for (const id of ids) assert.ok(vistas.includes(id));
});

test('el listado de un producto inexistente da 404', async () => {
  const res = await pedir('/api/products/no_existe/questions');
  assert.strictEqual(res.status, 404);
});

test('la respuesta nunca expone datos de contacto del que preguntó', async () => {
  const { producto, curioso } = escenario();
  db.getDb().prepare('UPDATE sellers SET phone = ? WHERE id = ?')
    .run('+528112345678', curioso.id);

  await preguntar(producto, curioso, '¿Me lo apartas?');
  const res = await pedir(`/api/products/${producto.id}/questions`);

  assert.ok(!JSON.stringify(res.body).includes('+528112345678'));
});

// ═══ Notificaciones ══════════════════════════════════════════

test('preguntar avisa al dueño con el deep link a la pregunta', async () => {
  const { producto, dueno, curioso } = escenario();

  const { body } = await preguntar(producto, curioso, '¿Sigue disponible?');

  const notificaciones = db.getNotifications(dueno.id);
  assert.strictEqual(notificaciones.length, 1);
  const notif = notificaciones[0];
  assert.strictEqual(notif.type, 'product_question');
  assert.strictEqual(notif.data.productId, producto.id);
  assert.strictEqual(
    notif.data.questionId,
    body.question.id,
    'sin questionId el deep link no puede resaltar la pregunta',
  );
});

test('responder avisa al que preguntó, no al vendedor', async () => {
  const { producto, dueno, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);
  const notifsDuenoAntes = db.getNotifications(dueno.id).length;

  await responder(creada.question.id, dueno);

  const delCurioso = db.getNotifications(curioso.id);
  assert.strictEqual(delCurioso.length, 1);
  assert.strictEqual(delCurioso[0].type, 'question_answered');
  assert.strictEqual(delCurioso[0].data.questionId, creada.question.id);
  assert.strictEqual(
    db.getNotifications(dueno.id).length,
    notifsDuenoAntes,
    'el vendedor no debe recibir aviso de su propia respuesta',
  );
});

test('corregir la respuesta también avisa, como respuesta actualizada', async () => {
  const { producto, dueno, curioso } = escenario();
  const { body: creada } = await preguntar(producto, curioso);

  await responder(creada.question.id, dueno, 'Primera versión');
  await responder(creada.question.id, dueno, 'Versión corregida');

  const avisos = db.getNotifications(curioso.id);
  assert.strictEqual(avisos.length, 2);
  assert.strictEqual(avisos[0].title, 'Respuesta actualizada');
});
