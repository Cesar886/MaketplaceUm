// Control de acceso del chat (hallazgo C-01 de la auditoría 2026-08).
//
// Hasta esta corrección los cinco endpoints de chat no pasaban por
// `requireAuth` y tomaban la identidad de `req.body.senderId` /
// `req.query.userId` — datos que escribe quien llama. Con eso se podía leer
// la bandeja de cualquiera, leer cualquier conversación (los ids son
// `conv_<timestamp>_<6 chars>`, enumerables), enviar mensajes suplantando a
// otra persona y borrar los suyos.
//
// Estos tests van contra los endpoints reales, no contra funciones sueltas:
// lo que hay que garantizar es que NO existe ninguna combinación de
// parámetros que devuelva datos ajenos, y eso solo se comprueba en la ruta.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const http = require('node:http');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-chat-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const express = require('express');
const db = require('../database');
const { generateToken, generateAnonToken } = require('../auth');

db.initDatabase();

const { register } = require('./chat');

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
  // `notifyNewMessage` dispara el push sin esperarlo (a propósito: la
  // respuesta no debe quedarse esperando a Firebase). Ese trabajo sigue vivo
  // cuando el último test termina, y el runner lo reporta como "actividad
  // asíncrona después del test" al correr toda la suite en paralelo. Se le da
  // un respiro para que drene antes de cerrar.
  await new Promise(r => setTimeout(r, 300));
  await new Promise(r => servidor.close(r));
});

// ─── Helpers ─────────────────────────────────────────────────

let contador = 0;

function crearUsuario() {
  const id = `u_chat_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
       VALUES (?, ?, ?, 'TT', '', 0, 1, 'estudiante')`,
    )
    .run(id, `Test ${id}`, `${id}@ejemplo.com`);
  return { id, token: generateToken(id) };
}

function crearProducto(duenoId) {
  const id = `p_chat_${++contador}`;
  db.getDb()
    .prepare('INSERT INTO products (id, title, price, seller) VALUES (?, ?, ?, ?)')
    .run(id, 'Bici', '100', duenoId);
  return { id, seller: duenoId };
}

/** Conversación ya existente entre dos usuarios, con un mensaje dentro. */
function crearConversacion(compradorId, vendedorId, productoId) {
  const convId = `conv_${Date.now()}_${(++contador).toString(36)}`;
  db.createConversation(convId, productoId, compradorId, vendedorId);
  const msgId = `msg_${++contador}`;
  db.createMessage(msgId, convId, compradorId, 'Hola, ¿sigue disponible?', null, null);
  return { convId, msgId };
}

function pedir(ruta, { token, metodo = 'GET', cuerpo } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return fetch(`${baseUrl}${ruta}`, {
    method: metodo,
    headers,
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  }).then(async res => ({ status: res.status, body: await res.json().catch(() => null) }));
}

// ═══ Sin token no se entra a ningún endpoint ═════════════════

test('los seis endpoints rechazan una petición sin token', async () => {
  const rutas = [
    ['/api/chat/conversations', 'GET'],
    ['/api/chat/conversations/conv_x/messages', 'GET'],
    ['/api/chat/send', 'POST'],
    ['/api/chat/send-image', 'POST'],
    ['/api/chat/messages/msg_x', 'DELETE'],
  ];
  for (const [ruta, metodo] of rutas) {
    const res = await pedir(ruta, { metodo, cuerpo: metodo === 'POST' ? {} : undefined });
    assert.strictEqual(res.status, 401, `${metodo} ${ruta} debería exigir token`);
  }
});

// ═══ C-01: leer conversaciones ajenas ════════════════════════

test('la bandeja devuelta es la del token, no la del userId de la query', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const carla = crearUsuario();
  const producto = crearProducto(beto.id);
  crearConversacion(ana.id, beto.id, producto.id);

  // Carla pide la bandeja de Ana explícitamente. El parámetro ya no existe,
  // así que debe recibir la SUYA (vacía), nunca la de Ana.
  const res = await pedir(`/api/chat/conversations?userId=${ana.id}`, { token: carla.token });
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(res.body.conversations, []);
});

test('un tercero no puede leer los mensajes de una conversación ajena', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const intrusa = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  const res = await pedir(`/api/chat/conversations/${convId}/messages`, { token: intrusa.token });
  assert.strictEqual(res.status, 403);
  assert.ok(!res.body.messages, 'no debe filtrarse ningún mensaje en el cuerpo del 403');
});

test('pasar el userId de un participante en la query no abre la conversación', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const intrusa = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  // El ataque exacto de antes: el id de un participante es público (aparece
  // como senderId en cada mensaje y como vendedor en el producto).
  const res = await pedir(
    `/api/chat/conversations/${convId}/messages?userId=${ana.id}`,
    { token: intrusa.token },
  );
  assert.strictEqual(res.status, 403);
});

test('los participantes sí leen su conversación', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  for (const usuario of [ana, beto]) {
    const res = await pedir(`/api/chat/conversations/${convId}/messages`, { token: usuario.token });
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.body.messages.length, 1);
  }
});

// ═══ Eliminar conversaciones de la bandeja propia ═══════════

test('un tercero no puede eliminar una conversación ajena', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const intrusa = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  const res = await pedir(`/api/chat/conversations/${convId}`, {
    token: intrusa.token,
    metodo: 'DELETE',
  });

  assert.strictEqual(res.status, 404);
  const bandeja = await pedir('/api/chat/conversations', { token: ana.token });
  assert.ok(bandeja.body.conversations.some(c => c.id === convId));
});

test('eliminar un chat solo lo retira para quien lo elimina y limpia sus badges', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);
  db.createNotification(
    `notif_delete_${++contador}`,
    beto.id,
    'new_message',
    'Nuevo mensaje',
    'Ana te escribió',
    { conversationId: convId },
  );

  assert.strictEqual(db.getUnreadMessageCount(beto.id), 1);
  assert.strictEqual(db.getUnreadNotificationCount(beto.id), 1);

  const eliminada = await pedir(`/api/chat/conversations/${convId}`, {
    token: beto.token,
    metodo: 'DELETE',
  });

  assert.strictEqual(eliminada.status, 200);
  assert.strictEqual(eliminada.body.unreadCount, 0);
  assert.strictEqual(db.getUnreadNotificationCount(beto.id), 0);

  const bandejaBeto = await pedir('/api/chat/conversations', { token: beto.token });
  const bandejaAna = await pedir('/api/chat/conversations', { token: ana.token });
  assert.ok(!bandejaBeto.body.conversations.some(c => c.id === convId));
  assert.ok(bandejaAna.body.conversations.some(c => c.id === convId));

  const mensajesBeto = await pedir(
    `/api/chat/conversations/${convId}/messages`,
    { token: beto.token },
  );
  const mensajesAna = await pedir(
    `/api/chat/conversations/${convId}/messages`,
    { token: ana.token },
  );
  assert.deepStrictEqual(mensajesBeto.body.messages, []);
  assert.strictEqual(mensajesAna.body.messages.length, 1);
  assert.strictEqual(db.getMessages(convId).length, 1, 'el historial compartido no se destruye');
});

test('un mensaje nuevo reactiva el chat sin restaurar el historial eliminado', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  await pedir(`/api/chat/conversations/${convId}`, {
    token: beto.token,
    metodo: 'DELETE',
  });
  const enviada = await pedir('/api/chat/send', {
    token: ana.token,
    metodo: 'POST',
    cuerpo: { conversationId: convId, text: '¿Todavía te interesa?' },
  });
  assert.strictEqual(enviada.status, 201);

  const bandeja = await pedir('/api/chat/conversations', { token: beto.token });
  assert.ok(bandeja.body.conversations.some(c => c.id === convId));

  const historial = await pedir(
    `/api/chat/conversations/${convId}/messages`,
    { token: beto.token },
  );
  assert.deepStrictEqual(
    historial.body.messages.map(m => m.text),
    ['¿Todavía te interesa?'],
  );
});

// ═══ C-01: suplantación al enviar ════════════════════════════

test('el senderId del cuerpo se ignora: el mensaje se firma con el token', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  // Beto escribe diciendo ser Ana.
  const res = await pedir('/api/chat/send', {
    token: beto.token,
    metodo: 'POST',
    cuerpo: { conversationId: convId, text: 'Ya te transferí, mándame el producto', senderId: ana.id },
  });
  assert.strictEqual(res.status, 201);

  const ultimo = res.body.messages[res.body.messages.length - 1];
  assert.strictEqual(ultimo.senderId, beto.id, 'el autor debe ser el dueño del token');
});

test('no se puede escribir en una conversación en la que no se participa', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const intrusa = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId } = crearConversacion(ana.id, beto.id, producto.id);

  const res = await pedir('/api/chat/send', {
    token: intrusa.token,
    metodo: 'POST',
    cuerpo: { conversationId: convId, text: 'hola' },
  });
  assert.strictEqual(res.status, 403);
});

// ═══ C-01: borrado de mensajes ajenos ════════════════════════

test('no se puede borrar el mensaje de otra persona ni pasando su senderId', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const producto = crearProducto(beto.id);
  const { convId, msgId } = crearConversacion(ana.id, beto.id, producto.id);

  const res = await pedir(`/api/chat/messages/${msgId}?senderId=${ana.id}`, {
    token: beto.token,
    metodo: 'DELETE',
  });
  assert.strictEqual(res.status, 404);

  const mensajes = db.getMessages(convId);
  assert.strictEqual(mensajes.length, 1, 'el mensaje debe seguir ahí');
});

test('cada quien puede borrar su propio mensaje', async () => {
  const ana = crearUsuario();
  const beto = crearUsuario();
  const producto = crearProducto(beto.id);
  const { msgId } = crearConversacion(ana.id, beto.id, producto.id);

  const res = await pedir(`/api/chat/messages/${msgId}`, { token: ana.token, metodo: 'DELETE' });
  assert.strictEqual(res.status, 200);
});

// ═══ Invitados: la función sigue viva, pero autenticada ══════

test('un invitado con token puede abrir una conversación y escribir', async () => {
  const vendedor = crearUsuario();
  const producto = crearProducto(vendedor.id);
  const invitado = generateAnonToken();

  const res = await pedir('/api/chat/send', {
    token: invitado.token,
    metodo: 'POST',
    cuerpo: { productId: producto.id, sellerId: vendedor.id, text: '¿Sigue disponible?' },
  });
  assert.strictEqual(res.status, 201);

  const ultimo = res.body.messages[res.body.messages.length - 1];
  assert.strictEqual(ultimo.senderId, invitado.anonId);
});

test('un invitado no puede leer la conversación de otro invitado', async () => {
  const vendedor = crearUsuario();
  const producto = crearProducto(vendedor.id);
  const primero = generateAnonToken();
  const segundo = generateAnonToken();

  const abierta = await pedir('/api/chat/send', {
    token: primero.token,
    metodo: 'POST',
    cuerpo: { productId: producto.id, sellerId: vendedor.id, text: 'hola' },
  });
  const convId = abierta.body.conversationId;

  const res = await pedir(`/api/chat/conversations/${convId}/messages`, { token: segundo.token });
  assert.strictEqual(res.status, 403);
});

test('un id anónimo copiado de un mensaje no sirve para suplantar al invitado', async () => {
  const vendedor = crearUsuario();
  const producto = crearProducto(vendedor.id);
  const invitado = generateAnonToken();

  await pedir('/api/chat/send', {
    token: invitado.token,
    metodo: 'POST',
    cuerpo: { productId: producto.id, sellerId: vendedor.id, text: 'hola' },
  });

  // El atacante conoce `invitado.anonId` (viaja en cada mensaje) y se hace
  // pasar por él con su propio token. Antes esto bastaba; ahora la identidad
  // la fija la firma, no el cuerpo.
  const otro = generateAnonToken();
  const res = await pedir('/api/chat/conversations', { token: otro.token });
  assert.deepStrictEqual(res.body.conversations, []);
});

test('otherUser trae socioFundador y verified, para la palomita del chat', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario();
  db.getDb()
    .prepare('UPDATE sellers SET socio_fundador = 1 WHERE id = ?')
    .run(vendedor.id);
  const producto = crearProducto(vendedor.id);
  crearConversacion(comprador.id, vendedor.id, producto.id);

  const res = await pedir('/api/chat/conversations', { token: comprador.token });

  assert.strictEqual(res.status, 200);
  const conv = res.body.conversations.find(c => c.sellerId === vendedor.id);
  assert.ok(conv, 'la conversación debe aparecer en el listado');
  assert.strictEqual(conv.otherUser.socioFundador, true);
  assert.strictEqual(conv.otherUser.verified, true);
});

// ═══ Chat directo desde el perfil público (sin producto) ═════
//
// El botón "Contactar por chat" del perfil público abre un chat que no es
// SOBRE nada: no hay producto de por medio, solo dos personas. Hasta esta
// corrección el envío moría con un 400 ("productId y sellerId son
// requeridos"), así que el chat abría pero no dejaba mandar nada.
//
// La tabla ya admitía `product_id` NULL desde la migración 10 (la que se
// hizo para los "se busca"); lo que faltaba era la rama que la usa.

test('se puede iniciar un chat sin producto desde el perfil público', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario();

  const res = await pedir('/api/chat/send', {
    token: comprador.token,
    metodo: 'POST',
    cuerpo: { sellerId: vendedor.id, text: 'Hola, vi tu perfil' },
  });

  assert.strictEqual(res.status, 201, JSON.stringify(res.body));
  assert.ok(res.body.conversationId, 'debe devolver el id de la conversación creada');
  assert.strictEqual(res.body.messages.at(-1).text, 'Hola, vi tu perfil');
});

test('un productId vacío se trata como chat directo, no como error', async () => {
  // El cliente manda `productId: ''` (no `undefined`) porque el campo del
  // widget es opcional y cae a cadena vacía. Un `''` NO puede leerse como
  // "producto inválido": es exactamente el caso del perfil público.
  const comprador = crearUsuario();
  const vendedor = crearUsuario();

  const res = await pedir('/api/chat/send', {
    token: comprador.token,
    metodo: 'POST',
    cuerpo: { productId: '', sellerId: vendedor.id, text: 'Hola' },
  });

  assert.strictEqual(res.status, 201, JSON.stringify(res.body));
});

test('el segundo mensaje directo reusa la conversación, no crea otra', async () => {
  // `WHERE product_id = ?` con NULL no empata NUNCA en SQL, así que una
  // búsqueda ingenua devolvería siempre "no existe" y cada mensaje abriría
  // un hilo nuevo. La búsqueda del chat directo tiene que usar `IS NULL`.
  const comprador = crearUsuario();
  const vendedor = crearUsuario();

  const primero = await pedir('/api/chat/send', {
    token: comprador.token,
    metodo: 'POST',
    cuerpo: { sellerId: vendedor.id, text: 'Primero' },
  });
  const segundo = await pedir('/api/chat/send', {
    token: comprador.token,
    metodo: 'POST',
    cuerpo: { sellerId: vendedor.id, text: 'Segundo' },
  });

  assert.strictEqual(segundo.status, 201, JSON.stringify(segundo.body));
  assert.strictEqual(segundo.body.conversationId, primero.body.conversationId);

  const inbox = await pedir('/api/chat/conversations', { token: comprador.token });
  const directas = inbox.body.conversations.filter(c => c.sellerId === vendedor.id);
  assert.strictEqual(directas.length, 1, 'no debe duplicarse el hilo directo');
});

test('si el otro contesta desde MI perfil, sigue siendo el mismo hilo', async () => {
  // Sin producto no hay quién es "comprador" y quién "vendedor": son dos
  // personas hablando. Si A escribe a B desde su perfil y luego B escribe a
  // A desde el suyo, los roles quedan al revés en la tabla; sin buscar en
  // ambos sentidos serían dos hilos paralelos entre las mismas dos personas.
  const ana = crearUsuario();
  const beto = crearUsuario();

  const deAna = await pedir('/api/chat/send', {
    token: ana.token,
    metodo: 'POST',
    cuerpo: { sellerId: beto.id, text: 'Hola Beto' },
  });
  const deBeto = await pedir('/api/chat/send', {
    token: beto.token,
    metodo: 'POST',
    cuerpo: { sellerId: ana.id, text: 'Hola Ana' },
  });

  assert.strictEqual(deBeto.status, 201, JSON.stringify(deBeto.body));
  assert.strictEqual(deBeto.body.conversationId, deAna.body.conversationId);
});

test('un chat directo aparece en la bandeja sin producto ni "se busca"', async () => {
  const comprador = crearUsuario();
  const vendedor = crearUsuario();

  const enviado = await pedir('/api/chat/send', {
    token: comprador.token,
    metodo: 'POST',
    cuerpo: { sellerId: vendedor.id, text: 'Hola' },
  });

  const res = await pedir('/api/chat/conversations', { token: comprador.token });
  const conv = res.body.conversations.find(c => c.id === enviado.body.conversationId);

  assert.ok(conv, 'el chat directo debe listarse en la bandeja');
  assert.strictEqual(conv.product, null);
  assert.strictEqual(conv.wantedPost, null);
  assert.strictEqual(conv.otherUser.id, vendedor.id);
});

test('sigue sin poder enviarse un mensaje a uno mismo sin producto', async () => {
  const solo = crearUsuario();

  const res = await pedir('/api/chat/send', {
    token: solo.token,
    metodo: 'POST',
    cuerpo: { sellerId: solo.id, text: 'Hola yo' },
  });

  assert.strictEqual(res.status, 400);
});

test('sin sellerId y sin conversationId sigue siendo un 400', async () => {
  const comprador = crearUsuario();

  const res = await pedir('/api/chat/send', {
    token: comprador.token,
    metodo: 'POST',
    cuerpo: { text: 'Hola a nadie' },
  });

  assert.strictEqual(res.status, 400);
});
