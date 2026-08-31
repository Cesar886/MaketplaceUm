// Tests de la capa de datos de preguntas y respuestas.
//
// Los puntos que se rompen en silencio:
//
//  1. El orden del PREVIEW. Es la regla de negocio con más criterio metido
//     dentro (respondidas recientes primero, pendientes de relleno) y si se
//     invirtiera seguiría devolviendo tres preguntas plausibles — solo que
//     las menos útiles para quien mira el producto.
//  2. La paginación por keyset. Igual que en comentarios: un cursor mal
//     armado no da error, da una fila repetida o una fila saltada. Por eso
//     hay un test que inserta EN MEDIO de la paginación.
//  3. Que responder no duplique. "Una sola respuesta por pregunta" es una
//     regla que solo se ve rota mirando el conteo de filas.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-questions-')),
  'test.db',
);

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

let contador = 0;

function sembrarVendedor(id, extra = {}) {
  raw.prepare(`
    INSERT OR REPLACE INTO sellers (id, name, avatarInitials, major, tipo_cuenta, carrera, tipo_verificacion, verified)
    VALUES (@id, @name, @avatarInitials, @major, @tipoCuenta, @carrera, @tipoVerificacion, @verified)
  `).run({
    id,
    name: `Usuario ${id}`,
    avatarInitials: 'UU',
    major: 'Estudiante',
    tipoCuenta: 'estudiante',
    carrera: null,
    tipoVerificacion: null,
    verified: 0,
    ...extra,
  });
  return id;
}

function sembrarProducto(id, sellerId) {
  raw.prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller, created_at)
    VALUES (?, ?, '100', 100, 'cat', 'desc', ?, datetime('now'))
  `).run(id, `Producto ${id}`, sellerId);
  return id;
}

/**
 * Crea una pregunta. `minutosAtras` permite construir un orden temporal
 * determinista sin dormir el test.
 */
function preguntar(productId, sellerId, askedBy, texto, { minutosAtras = 0 } = {}) {
  const id = `q_${++contador}`;
  const pregunta = db.createProductQuestion(id, productId, sellerId, askedBy, texto);
  if (minutosAtras > 0) {
    raw.prepare(
      "UPDATE product_questions SET created_at = datetime('now', '-' || ? || ' minutes') WHERE id = ?",
    ).run(minutosAtras, id);
  }
  return pregunta;
}

function responder(id, texto, { minutosAtras = 0 } = {}) {
  const respondida = db.answerProductQuestion(id, texto);
  if (minutosAtras > 0) {
    raw.prepare(
      "UPDATE product_questions SET answered_at = datetime('now', '-' || ? || ' minutes') WHERE id = ?",
    ).run(minutosAtras, id);
  }
  return respondida;
}

function ids(preguntas) {
  return preguntas.map(q => q.id);
}

// ═══ Creación y forma ════════════════════════════════════════

test('una pregunta nace pendiente, sin respuesta y con su autor resuelto', () => {
  sembrarVendedor('v_1');
  sembrarVendedor('u_1', { name: 'Mariana Peña', avatarInitials: 'MP', verified: 1 });
  sembrarProducto('p_1', 'v_1');

  const pregunta = preguntar('p_1', 'v_1', 'u_1', '¿Sigue disponible?');

  assert.strictEqual(pregunta.questionText, '¿Sigue disponible?');
  assert.strictEqual(pregunta.answerText, null);
  assert.strictEqual(pregunta.status, 'pending');
  assert.strictEqual(pregunta.answeredAt, null);
  assert.strictEqual(pregunta.author.id, 'u_1');
  assert.strictEqual(pregunta.author.name, 'Mariana Peña');
  assert.strictEqual(pregunta.author.verified, true);
});

test('la pregunta no expone datos sensibles del que preguntó', () => {
  sembrarVendedor('v_2');
  sembrarVendedor('u_2');
  raw.prepare('UPDATE sellers SET phone = ?, email = ? WHERE id = ?')
    .run('+528112345678', 'privado@ejemplo.com', 'u_2');
  sembrarProducto('p_2', 'v_2');

  const pregunta = preguntar('p_2', 'v_2', 'u_2', '¿Aceptas transferencia?');
  const serializado = JSON.stringify(pregunta);

  assert.ok(!serializado.includes('+528112345678'), 'se filtró el teléfono');
  assert.ok(!serializado.includes('privado@ejemplo.com'), 'se filtró el correo');
  assert.strictEqual(pregunta.author.phone, undefined);
  assert.strictEqual(pregunta.author.email, undefined);
});

test('una cuenta borrada deja su pregunta en pie, con autor genérico', () => {
  sembrarVendedor('v_3');
  sembrarVendedor('u_3');
  sembrarProducto('p_3', 'v_3');
  const pregunta = preguntar('p_3', 'v_3', 'u_3', '¿Tienes más fotos?');

  raw.prepare('DELETE FROM sellers WHERE id = ?').run('u_3');
  const releida = db.getProductQuestionById(pregunta.id);

  assert.strictEqual(releida.questionText, '¿Tienes más fotos?');
  assert.strictEqual(releida.author.name, 'Usuario');
  assert.strictEqual(releida.author.avatarInitials, '??');
});

// ═══ Responder ═══════════════════════════════════════════════

test('responder marca la pregunta como respondida y sella la fecha', () => {
  sembrarVendedor('v_4');
  sembrarVendedor('u_4');
  sembrarProducto('p_4', 'v_4');
  const pregunta = preguntar('p_4', 'v_4', 'u_4', '¿Color negro?');

  const respondida = db.answerProductQuestion(pregunta.id, 'Sí, me quedan dos.');

  assert.strictEqual(respondida.answerText, 'Sí, me quedan dos.');
  assert.strictEqual(respondida.status, 'answered');
  assert.ok(respondida.answeredAt, 'answered_at debe quedar sellado');
});

test('responder dos veces edita: no crea una segunda respuesta', () => {
  sembrarVendedor('v_5');
  sembrarVendedor('u_5');
  sembrarProducto('p_5', 'v_5');
  const pregunta = preguntar('p_5', 'v_5', 'u_5', '¿Cuánto mide?');

  db.answerProductQuestion(pregunta.id, 'Como 30 cm.');
  const corregida = db.answerProductQuestion(pregunta.id, 'Perdón, 35 cm.');

  assert.strictEqual(corregida.answerText, 'Perdón, 35 cm.');
  assert.strictEqual(db.countProductQuestions('p_5'), 1, 'se duplicó la fila');
});

test('status nunca queda desincronizado con answer_text', () => {
  sembrarVendedor('v_6');
  sembrarVendedor('u_6');
  sembrarProducto('p_6', 'v_6');
  const pregunta = preguntar('p_6', 'v_6', 'u_6', '¿Envías?');
  db.answerProductQuestion(pregunta.id, 'Sí, dentro del campus.');

  const fila = db.getProductQuestionRow(pregunta.id);

  assert.strictEqual(fila.status, 'answered');
  assert.ok(fila.answer_text);
});

// ═══ Preview ═════════════════════════════════════════════════

test('el preview pone las respondidas recientes antes que las pendientes', () => {
  sembrarVendedor('v_7');
  sembrarVendedor('u_7');
  sembrarProducto('p_7', 'v_7');

  const pendienteNueva = preguntar('p_7', 'v_7', 'u_7', 'Pendiente reciente');
  const respondidaVieja = preguntar('p_7', 'v_7', 'u_7', 'Respondida vieja', { minutosAtras: 600 });
  const respondidaNueva = preguntar('p_7', 'v_7', 'u_7', 'Respondida nueva', { minutosAtras: 500 });
  responder(respondidaVieja.id, 'Respuesta vieja', { minutosAtras: 400 });
  responder(respondidaNueva.id, 'Respuesta nueva', { minutosAtras: 10 });

  const preview = db.getProductQuestionsPreview('p_7', { limit: 3 });

  assert.deepStrictEqual(ids(preview), [
    respondidaNueva.id,
    respondidaVieja.id,
    pendienteNueva.id,
  ]);
});

test('si no hay respondidas, el preview se llena con pendientes recientes', () => {
  sembrarVendedor('v_8');
  sembrarVendedor('u_8');
  sembrarProducto('p_8', 'v_8');

  const vieja = preguntar('p_8', 'v_8', 'u_8', 'Vieja', { minutosAtras: 100 });
  const nueva = preguntar('p_8', 'v_8', 'u_8', 'Nueva', { minutosAtras: 1 });

  const preview = db.getProductQuestionsPreview('p_8', { limit: 3 });

  assert.deepStrictEqual(ids(preview), [nueva.id, vieja.id]);
});

test('el preview respeta su límite', () => {
  sembrarVendedor('v_9');
  sembrarVendedor('u_9');
  sembrarProducto('p_9', 'v_9');
  for (let i = 0; i < 6; i++) preguntar('p_9', 'v_9', 'u_9', `Pregunta ${i}`);

  assert.strictEqual(db.getProductQuestionsPreview('p_9', { limit: 3 }).length, 3);
});

test('un producto sin preguntas devuelve lista vacía, no null', () => {
  sembrarVendedor('v_10');
  sembrarProducto('p_10', 'v_10');

  assert.deepStrictEqual(db.getProductQuestionsPreview('p_10', { limit: 3 }), []);
  assert.strictEqual(db.countProductQuestions('p_10'), 0);
  assert.strictEqual(db.countPendingProductQuestions('p_10'), 0);
});

// ═══ Listado paginado ════════════════════════════════════════

test('el listado va de la más reciente a la más antigua', () => {
  sembrarVendedor('v_11');
  sembrarVendedor('u_11');
  sembrarProducto('p_11', 'v_11');
  const vieja = preguntar('p_11', 'v_11', 'u_11', 'Vieja', { minutosAtras: 60 });
  const media = preguntar('p_11', 'v_11', 'u_11', 'Media', { minutosAtras: 30 });
  const nueva = preguntar('p_11', 'v_11', 'u_11', 'Nueva');

  const { questions } = db.getProductQuestions('p_11', { limit: 10 });

  assert.deepStrictEqual(ids(questions), [nueva.id, media.id, vieja.id]);
});

test('paginar no repite ni salta filas aunque entren preguntas en medio', () => {
  sembrarVendedor('v_12');
  sembrarVendedor('u_12');
  sembrarProducto('p_12', 'v_12');
  const originales = [];
  for (let i = 0; i < 5; i++) {
    originales.push(preguntar('p_12', 'v_12', 'u_12', `Original ${i}`, { minutosAtras: 100 - i }));
  }

  const primera = db.getProductQuestions('p_12', { limit: 2 });
  assert.ok(primera.nextCursor, 'debe haber cursor de continuación');

  // Alguien pregunta mientras el usuario está paginando: entra en el TOPE,
  // que es justo lo que un OFFSET desplazaría.
  preguntar('p_12', 'v_12', 'u_12', 'Intrusa');

  const segunda = db.getProductQuestions('p_12', { limit: 2, cursor: primera.nextCursor });
  const tercera = db.getProductQuestions('p_12', { limit: 2, cursor: segunda.nextCursor });

  const vistas = [...ids(primera.questions), ...ids(segunda.questions), ...ids(tercera.questions)];
  assert.strictEqual(new Set(vistas).size, vistas.length, 'hay filas repetidas');
  // Las 5 originales tienen que haber salido, ninguna saltada.
  for (const original of originales) {
    assert.ok(vistas.includes(original.id), `se saltó ${original.questionText}`);
  }
});

test('la última página no devuelve cursor', () => {
  sembrarVendedor('v_13');
  sembrarVendedor('u_13');
  sembrarProducto('p_13', 'v_13');
  preguntar('p_13', 'v_13', 'u_13', 'Única');

  const { questions, nextCursor } = db.getProductQuestions('p_13', { limit: 20 });

  assert.strictEqual(questions.length, 1);
  assert.strictEqual(nextCursor, null);
});

test('filter=pending devuelve solo las que faltan por responder', () => {
  sembrarVendedor('v_14');
  sembrarVendedor('u_14');
  sembrarProducto('p_14', 'v_14');
  const respondida = preguntar('p_14', 'v_14', 'u_14', 'Ya respondida');
  const pendiente = preguntar('p_14', 'v_14', 'u_14', 'Sin responder');
  db.answerProductQuestion(respondida.id, 'Listo');

  const { questions } = db.getProductQuestions('p_14', { limit: 10, filter: 'pending' });

  assert.deepStrictEqual(ids(questions), [pendiente.id]);
  assert.strictEqual(db.countPendingProductQuestions('p_14'), 1);
  assert.strictEqual(db.countProductQuestions('p_14'), 2);
});

test('el listado de un producto no arrastra preguntas de otro', () => {
  sembrarVendedor('v_15');
  sembrarVendedor('u_15');
  sembrarProducto('p_15a', 'v_15');
  sembrarProducto('p_15b', 'v_15');
  const deA = preguntar('p_15a', 'v_15', 'u_15', 'De A');
  preguntar('p_15b', 'v_15', 'u_15', 'De B');

  const { questions } = db.getProductQuestions('p_15a', { limit: 10 });

  assert.deepStrictEqual(ids(questions), [deA.id]);
});

test('el límite pedido se acota al máximo permitido', () => {
  sembrarVendedor('v_16');
  sembrarVendedor('u_16');
  sembrarProducto('p_16', 'v_16');
  for (let i = 0; i < 3; i++) preguntar('p_16', 'v_16', 'u_16', `P${i}`);

  // Un cliente pidiendo 5000 no debe poder barrer la tabla de un tirón.
  const { questions } = db.getProductQuestions('p_16', { limit: 5000 });
  assert.ok(questions.length <= db.PREGUNTAS_MAX_POR_PAGINA);
});

// ═══ Eliminación ═════════════════════════════════════════════

test('eliminar una pregunta la saca del hilo y recalcula contadores', () => {
  sembrarVendedor('v_21');
  sembrarVendedor('u_21');
  sembrarProducto('p_21', 'v_21');
  const respondida = preguntar('p_21', 'v_21', 'u_21', 'Respondida');
  preguntar('p_21', 'v_21', 'u_21', 'Pendiente');
  responder(respondida.id, 'Sí');

  assert.strictEqual(db.deleteProductQuestion(respondida.id), true);

  assert.strictEqual(db.getProductQuestionRow(respondida.id), undefined);
  assert.strictEqual(db.countProductQuestions('p_21'), 1);
  assert.strictEqual(db.countPendingProductQuestions('p_21'), 1);
  assert.strictEqual(db.deleteProductQuestion(respondida.id), false);
});

// ═══ Anti-spam ═══════════════════════════════════════════════

test('cuenta las preguntas recientes de un usuario en un producto', () => {
  sembrarVendedor('v_17');
  sembrarVendedor('u_17');
  sembrarVendedor('u_17b');
  sembrarProducto('p_17', 'v_17');
  sembrarProducto('p_17b', 'v_17');

  preguntar('p_17', 'v_17', 'u_17', 'Una');
  preguntar('p_17', 'v_17', 'u_17', 'Dos');
  // Ruido que NO debe contar: otro usuario, y el mismo usuario en otro
  // producto. El límite es por par usuario+publicación.
  preguntar('p_17', 'v_17', 'u_17b', 'De otro');
  preguntar('p_17b', 'v_17', 'u_17', 'En otro producto');

  assert.strictEqual(db.contarPreguntasRecientes('u_17', 'p_17', 24), 2);
});

test('las preguntas viejas salen de la ventana del límite', () => {
  sembrarVendedor('v_18');
  sembrarVendedor('u_18');
  sembrarProducto('p_18', 'v_18');
  preguntar('p_18', 'v_18', 'u_18', 'Vieja', { minutosAtras: 60 * 30 });
  preguntar('p_18', 'v_18', 'u_18', 'Reciente');

  assert.strictEqual(db.contarPreguntasRecientes('u_18', 'p_18', 24), 1);
});

test('segundosDesdeUltimaPregunta es null si el usuario nunca preguntó', () => {
  sembrarVendedor('u_19');
  assert.strictEqual(db.segundosDesdeUltimaPregunta('u_19'), null);
});

test('segundosDesdeUltimaPregunta cuenta desde la última, no la primera', () => {
  sembrarVendedor('v_20');
  sembrarVendedor('u_20');
  sembrarProducto('p_20', 'v_20');
  preguntar('p_20', 'v_20', 'u_20', 'Hace rato', { minutosAtras: 45 });
  preguntar('p_20', 'v_20', 'u_20', 'Ahora');

  const segundos = db.segundosDesdeUltimaPregunta('u_20');

  assert.ok(segundos !== null && segundos < 60, `esperaba ~0 s, dio ${segundos}`);
});
