// El script de borrado de cuentas, contra una base desechable.
//
// Se prueba porque es destructivo y porque su razón de ser es justo lo que un
// `DELETE FROM sellers` no hace: `products.seller`, `conversations.buyer_id`,
// `conversations.seller_id` y `messages.sender_id` no tienen foreign key, así
// que nadie limpia eso por nosotros. Lo que estos tests fijan es que NO queden
// huérfanos y que la cuenta de al lado no pierda nada.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const RUTA_SCRIPT = path.join(__dirname, 'eliminar-cuenta.js');

function nuevaBase() {
  return path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-borrar-')),
    'test.db',
  );
}

function correr(rutaDb, args) {
  return execFileSync(process.execPath, [RUTA_SCRIPT, ...args], {
    env: { ...process.env, MERCADITO_DB_PATH: rutaDb },
    encoding: 'utf8',
  });
}

/** Base con dos cuentas: la que se borra y una vecina que debe sobrevivir. */
function sembrar(rutaDb) {
  process.env.MERCADITO_DB_PATH = rutaDb;
  delete require.cache[require.resolve('../src/database')];
  const db = require('../src/database');
  db.initDatabase();
  const c = db.getDb();

  const insertarUsuario = (id, email) =>
    c.prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, tipo_cuenta)
       VALUES (?, ?, ?, 'TT', '', 0, 0, 'estudiante')`,
    ).run(id, `N ${id}`, email);

  insertarUsuario('u_borrar', 'borrar@gmail.com');
  insertarUsuario('u_vecino', 'vecino@gmail.com');

  c.prepare('INSERT INTO products (id, title, price, seller) VALUES (?, ?, ?, ?)')
    .run('p_borrar', 'Bici', '100', 'u_borrar');
  c.prepare('INSERT INTO products (id, title, price, seller) VALUES (?, ?, ?, ?)')
    .run('p_vecino', 'Mesa', '200', 'u_vecino');

  // Comentario del vecino SOBRE el producto que va a desaparecer: se va con
  // el producto, o queda apuntando a una publicación inexistente.
  c.prepare(
    'INSERT INTO product_comments (id, product_id, user_id, texto) VALUES (?, ?, ?, ?)',
  ).run('cm_1', 'p_borrar', 'u_vecino', 'Hola');

  // Conversación en la que el borrado es el VENDEDOR: el hilo vive en la
  // bandeja del vecino, y es el que más duele dejar colgado.
  db.createConversation('conv_1', 'p_borrar', 'u_vecino', 'u_borrar');
  db.createMessage('m_1', 'conv_1', 'u_vecino', 'Hola', null, null);
  db.createMessage('m_2', 'conv_1', 'u_borrar', 'Sí, disponible', null, null);

  // Conversación entre dos cuentas que se quedan: no se toca.
  db.createConversation('conv_2', 'p_vecino', 'u_vecino', 'u_vecino');
  db.createMessage('m_3', 'conv_2', 'u_vecino', 'Nota', null, null);

  c.prepare('INSERT INTO notifications (id, user_id, type, title, body) VALUES (?, ?, ?, ?, ?)')
    .run('n_1', 'u_borrar', 'new_message', 'T', 'B');

  c.close();
}

function abrir(rutaDb) {
  const Database = require('better-sqlite3');
  return new Database(rutaDb, { readonly: true });
}

test('el dry-run no escribe nada', () => {
  const rutaDb = nuevaBase();
  sembrar(rutaDb);

  const salida = correr(rutaDb, ['borrar@gmail.com']);
  assert.match(salida, /DRY-RUN/);

  const c = abrir(rutaDb);
  assert.strictEqual(
    c.prepare("SELECT COUNT(*) n FROM sellers WHERE id = 'u_borrar'").get().n,
    1,
    'la cuenta debe seguir ahí tras un dry-run',
  );
  c.close();
});

test('--force borra la cuenta sin dejar huérfanos', () => {
  const rutaDb = nuevaBase();
  sembrar(rutaDb);

  correr(rutaDb, ['borrar@gmail.com', '--force']);
  const c = abrir(rutaDb);

  assert.strictEqual(
    c.prepare("SELECT COUNT(*) n FROM sellers WHERE id = 'u_borrar'").get().n,
    0,
  );

  // Ni un producto, conversación o mensaje apuntando a quien ya no existe.
  const productosHuerfanos = c.prepare(
    'SELECT COUNT(*) n FROM products WHERE seller NOT IN (SELECT id FROM sellers)',
  ).get().n;
  const convHuerfanas = c.prepare(`
    SELECT COUNT(*) n FROM conversations
     WHERE buyer_id NOT IN (SELECT id FROM sellers)
        OR seller_id NOT IN (SELECT id FROM sellers)
  `).get().n;
  const mensajesHuerfanos = c.prepare(
    'SELECT COUNT(*) n FROM messages WHERE conversation_id NOT IN (SELECT id FROM conversations)',
  ).get().n;
  const comentariosHuerfanos = c.prepare(
    'SELECT COUNT(*) n FROM product_comments WHERE product_id NOT IN (SELECT id FROM products)',
  ).get().n;

  assert.strictEqual(productosHuerfanos, 0, 'productos huérfanos');
  assert.strictEqual(convHuerfanas, 0, 'conversaciones huérfanas');
  assert.strictEqual(mensajesHuerfanos, 0, 'mensajes huérfanos');
  assert.strictEqual(comentariosHuerfanos, 0, 'comentarios huérfanos');

  c.close();
});

test('la cuenta de al lado no pierde nada suyo', () => {
  const rutaDb = nuevaBase();
  sembrar(rutaDb);

  correr(rutaDb, ['borrar@gmail.com', '--force']);
  const c = abrir(rutaDb);

  assert.strictEqual(
    c.prepare("SELECT COUNT(*) n FROM sellers WHERE id = 'u_vecino'").get().n,
    1,
  );
  assert.strictEqual(
    c.prepare("SELECT COUNT(*) n FROM products WHERE id = 'p_vecino'").get().n,
    1,
  );
  assert.strictEqual(
    c.prepare("SELECT COUNT(*) n FROM conversations WHERE id = 'conv_2'").get().n,
    1,
  );
  assert.strictEqual(
    c.prepare("SELECT COUNT(*) n FROM messages WHERE id = 'm_3'").get().n,
    1,
  );
  c.close();
});

test('deja un respaldo consistente antes de borrar', () => {
  const rutaDb = nuevaBase();
  sembrar(rutaDb);

  correr(rutaDb, ['borrar@gmail.com', '--force']);

  const respaldos = fs
    .readdirSync(path.dirname(rutaDb))
    .filter(f => f.includes('pre-eliminar-cuenta'));
  assert.strictEqual(respaldos.length, 1, 'debe haber exactamente un respaldo');

  // El respaldo sirve de verdad: la cuenta borrada sigue dentro.
  const copia = abrir(path.join(path.dirname(rutaDb), respaldos[0]));
  assert.strictEqual(
    copia.prepare("SELECT COUNT(*) n FROM sellers WHERE id = 'u_borrar'").get().n,
    1,
  );
  copia.close();
});

test('un correo que no existe no rompe nada', () => {
  const rutaDb = nuevaBase();
  sembrar(rutaDb);

  const salida = correr(rutaDb, ['nadie@gmail.com', '--force']);
  assert.match(salida, /Sin cuenta para nadie@gmail\.com/);

  const c = abrir(rutaDb);
  assert.strictEqual(c.prepare('SELECT COUNT(*) n FROM sellers').get().n, 2);
  c.close();
});
