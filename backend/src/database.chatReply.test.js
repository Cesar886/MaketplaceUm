// Tests de "responder a un mensaje" en el chat.
//
// Lo que de verdad se puede romper en silencio aquí:
//
//  1. Que `replyTo` llegue sin resolver (solo el id). Compila, la API responde
//     200, y la burbuja del otro usuario aparece sin cita. Por eso se afirma
//     sobre el contenido del citado, no sobre el id.
//  2. Que se acepte citar un mensaje de OTRA conversación. Eso no es un bug
//     cosmético: pinta el texto de un chat ajeno dentro del propio.
//  3. Que el borrado lógico del mensaje citado se lleve por delante la
//     respuesta. La respuesta debe sobrevivir mostrando el placeholder.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
const tmpDb = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-chat-reply-')),
  'test.db',
);
process.env.MERCADITO_DB_PATH = tmpDb;

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

function sembrarConversacion(convId, { buyer = 'u_buyer', seller = 'u_seller' } = {}) {
  raw.prepare(`
    INSERT OR REPLACE INTO conversations (id, product_id, buyer_id, seller_id)
    VALUES (?, ?, ?, ?)
  `).run(convId, 'prod_1', buyer, seller);
  return convId;
}

test('un mensaje normal no trae cita', () => {
  const conv = sembrarConversacion('conv_normal');
  db.createMessage('m_normal', conv, 'u_buyer', 'hola');

  const [msg] = db.getMessages(conv);
  assert.strictEqual(msg.replyToMessageId, null);
  assert.strictEqual(msg.replyTo, null);
});

test('la respuesta trae el mensaje citado ya resuelto', () => {
  const conv = sembrarConversacion('conv_cita');
  db.createMessage('m_original', conv, 'u_seller', '¿Sigue disponible?');
  db.createMessage('m_respuesta', conv, 'u_buyer', 'Sí, claro', null, 'm_original');

  const msgs = db.getMessages(conv);
  const respuesta = msgs.find(m => m.id === 'm_respuesta');

  assert.strictEqual(respuesta.replyToMessageId, 'm_original');
  assert.ok(respuesta.replyTo, 'replyTo debe venir resuelto, no solo el id');
  assert.strictEqual(respuesta.replyTo.text, '¿Sigue disponible?');
  assert.strictEqual(respuesta.replyTo.senderId, 'u_seller');
});

test('se puede responder a un mensaje con imagen', () => {
  const conv = sembrarConversacion('conv_imagen');
  db.createMessage('m_foto', conv, 'u_seller', '', '/uploads/foto.webp');
  db.createMessage('m_resp_foto', conv, 'u_buyer', 'Bonita', null, 'm_foto');

  const respuesta = db.getMessages(conv).find(m => m.id === 'm_resp_foto');
  assert.strictEqual(respuesta.replyTo.imageUrl, '/uploads/foto.webp');
  assert.strictEqual(respuesta.replyTo.text, '');
});

test('el orden cronológico no cambia por el LEFT JOIN de la cita', () => {
  const conv = sembrarConversacion('conv_orden');
  // created_at explícito: el default tiene resolución de segundo y tres
  // inserciones seguidas caerían en el mismo instante.
  const ins = raw.prepare(`
    INSERT INTO messages (id, conversation_id, sender_id, text, created_at, read)
    VALUES (?, ?, ?, ?, ?, 0)
  `);
  ins.run('m_1', conv, 'u_buyer', 'uno', '2026-08-01 10:00:00');
  ins.run('m_2', conv, 'u_seller', 'dos', '2026-08-01 10:00:01');
  ins.run('m_3', conv, 'u_buyer', 'tres', '2026-08-01 10:00:02');
  raw.prepare('UPDATE messages SET reply_to_message_id = ? WHERE id = ?')
    .run('m_1', 'm_3');

  assert.deepStrictEqual(
    db.getMessages(conv).map(m => m.id),
    ['m_1', 'm_2', 'm_3'],
  );
});

test('messageBelongsToConversation rechaza un mensaje de otro chat', () => {
  const convA = sembrarConversacion('conv_a');
  const convB = sembrarConversacion('conv_b');
  db.createMessage('m_en_a', convA, 'u_buyer', 'privado de A');

  assert.strictEqual(db.messageBelongsToConversation('m_en_a', convA), true);
  assert.strictEqual(db.messageBelongsToConversation('m_en_a', convB), false);
  assert.strictEqual(db.messageBelongsToConversation('no_existe', convA), false);
});

test('borrar el mensaje citado no borra la respuesta: muestra el placeholder', () => {
  const conv = sembrarConversacion('conv_borrado');
  db.createMessage('m_borrable', conv, 'u_seller', 'texto original');
  db.createMessage('m_resp_borrable', conv, 'u_buyer', 'te respondo', null, 'm_borrable');

  db.deleteMessage('m_borrable', 'u_seller');

  const respuesta = db.getMessages(conv).find(m => m.id === 'm_resp_borrable');
  assert.ok(respuesta, 'la respuesta debe seguir existiendo');
  assert.strictEqual(respuesta.replyTo.text, '[Mensaje eliminado]');
});
