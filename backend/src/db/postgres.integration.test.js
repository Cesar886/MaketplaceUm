'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');
const { bindParameters } = require('./postgres');

const migrationsDir = path.join(__dirname, '..', '..', 'migrations', 'postgres');

async function migratedDatabase() {
  const database = new PGlite();
  const names = fs.readdirSync(migrationsDir)
    .filter(name => name.endsWith('.sql'))
    .sort();
  for (const name of names) {
    await database.exec(fs.readFileSync(path.join(migrationsDir, name), 'utf8'));
  }
  return database;
}

test('las migraciones PostgreSQL se aplican y cargan los catálogos', async t => {
  const database = await migratedDatabase();
  t.after(() => database.close());

  const categories = await database.query('SELECT COUNT(*)::integer AS total FROM categories');
  const plans = await database.query('SELECT COUNT(*)::integer AS total FROM highlight_plans');
  const config = await database.query('SELECT COUNT(*)::integer AS total FROM config');
  assert.equal(categories.rows[0].total, 8);
  assert.equal(plans.rows[0].total, 4);
  assert.equal(config.rows[0].total, 5);
});

test('PostgreSQL planifica la consulta administrativa dinámica', async t => {
  const database = await migratedDatabase();
  t.after(() => database.close());

  const publicationUnion = `
    SELECT 'product' AS kind, p.id, p.title, p.seller AS ownerId,
      COALESCE(s.name, p.seller) AS ownerName, p.created_at AS createdAt,
      p.moderation_status AS moderationStatus, p.status AS domainStatus,
      COALESCE(p.views, 0) AS views
    FROM products p LEFT JOIN sellers s ON s.id = p.seller
    UNION ALL
    SELECT 'wanted' AS kind, w.id, w.title, w.user_id AS ownerId,
      COALESCE(s.name, w.user_id) AS ownerName, w.created_at AS createdAt,
      w.moderation_status AS moderationStatus, w.status AS domainStatus,
      COALESCE(w.views, 0) AS views
    FROM wanted_posts w LEFT JOIN sellers s ON s.id = w.user_id`;
  const sql = `SELECT * FROM (${publicationUnion})
    WHERE kind = ? AND "moderationStatus" = ?
      AND (id LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\'
        OR "ownerName" LIKE ? ESCAPE '\\' OR "ownerId" LIKE ? ESCAPE '\\')
    ORDER BY "createdAt" DESC, id DESC LIMIT ? OFFSET ?`;
  const query = bindParameters(sql, [
    'product', 'pending', '%libro%', '%libro%', '%libro%', '%libro%', 20, 0,
  ]);

  const plan = await database.query(`EXPLAIN ${query.text}`, query.values);
  assert.ok(plan.rows.length > 0);
});

test('la migración 004 fusiona chats directos duplicados antes de imponer unicidad simétrica', async t => {
  const database = new PGlite();
  t.after(() => database.close());

  const names = fs.readdirSync(migrationsDir)
    .filter(name => name.endsWith('.sql'))
    .sort();
  for (const name of names.filter(name => name < '004_')) {
    await database.exec(fs.readFileSync(path.join(migrationsDir, name), 'utf8'));
  }

  await database.exec(`
    INSERT INTO sellers (id, name) VALUES
      ('alice', 'Alice'),
      ('bob', 'Bob'),
      ('owner', 'Owner'),
      ('real_user', 'Real user'),
      ('innocent', 'Innocent');

    INSERT INTO conversations (
      id, product_id, wanted_post_id, buyer_id, seller_id, created_at,
      last_message_at, last_message_preview
    ) VALUES
      ('conv_keep', NULL, NULL, 'alice', 'bob', '2026-01-01T00:00:00Z',
       '2026-01-01T00:01:00Z', 'primero'),
      ('conv_duplicate', NULL, NULL, 'bob', 'alice', '2026-01-02T00:00:00Z',
       '2026-01-02T00:01:00Z', 'segundo');

    INSERT INTO messages (
      id, conversation_id, sender_id, text, created_at, read
    ) VALUES
      ('msg_keep', 'conv_keep', 'alice', 'primero', '2026-01-01T00:01:00Z', 0),
      ('msg_duplicate', 'conv_duplicate', 'bob', 'segundo', '2026-01-02T00:01:00Z', 0);

    INSERT INTO conversation_deletions (
      conversation_id, user_id, deleted_through_message_id, deleted_at
    ) VALUES
      -- Este borrado ocurrió después, pero corta antes. La migración debe
      -- conservar msg_duplicate por su seq mayor, no elegir por deleted_at.
      ('conv_keep', 'alice', 'msg_keep', '2026-03-01T01:00:00Z'),
      ('conv_duplicate', 'alice', 'msg_duplicate', '2026-01-02T01:00:00Z');

    INSERT INTO products (id, title, seller)
    VALUES ('legacy_product', 'Producto legado', 'owner');

    INSERT INTO wanted_posts (id, user_id, title, category_id, type)
    VALUES ('legacy_wanted', 'owner', 'Solicitud legada', 'otros', 'producto');

    INSERT INTO reports (
      id, reporter_id, target_type, target_id, target_user_id, reason
    ) VALUES
      ('report_duplicate_chat', 'alice', 'chat', 'conv_duplicate', 'innocent', 'Mensajes sospechosos'),
      ('report_outsider_chat', 'mallory', 'chat', 'conv_duplicate', 'innocent', 'Chat ajeno'),
      ('report_user', 'alice', 'user', 'real_user', 'innocent', 'Usuario sospechoso'),
      ('report_product', 'alice', 'product', 'legacy_product', 'innocent', 'Producto sospechoso'),
      ('report_wanted', 'alice', 'wanted', 'legacy_wanted', 'innocent', 'Solicitud sospechosa'),
      ('report_missing', 'alice', 'user', 'missing', 'innocent', 'Objetivo inexistente');

    INSERT INTO notifications (id, user_id, type, title, body, data)
    VALUES
      ('notification_duplicate_chat', 'alice', 'new_message', 'Mensaje', 'Contenido',
       '{"conversationId":"conv_duplicate","preserve":"yes"}'),
      ('notification_invalid_json', 'alice', 'legacy', 'Legacy', 'Contenido', '{invalid-json');
  `);

  await database.exec(fs.readFileSync(
    path.join(migrationsDir, '004_unique_direct_conversations.sql'),
    'utf8',
  ));

  const conversations = await database.query(`
    SELECT id, last_message_preview
      FROM conversations
     WHERE product_id IS NULL AND wanted_post_id IS NULL
       AND LEAST(buyer_id, seller_id) = 'alice'
       AND GREATEST(buyer_id, seller_id) = 'bob'
  `);
  assert.deepEqual(conversations.rows, [{ id: 'conv_keep', last_message_preview: 'segundo' }]);

  const messages = await database.query(`
    SELECT id, conversation_id FROM messages ORDER BY id
  `);
  assert.deepEqual(messages.rows, [
    { id: 'msg_duplicate', conversation_id: 'conv_keep' },
    { id: 'msg_keep', conversation_id: 'conv_keep' },
  ]);

  const deletion = await database.query(`
    SELECT conversation_id, deleted_through_message_id
      FROM conversation_deletions WHERE user_id = 'alice'
  `);
  assert.deepEqual(deletion.rows, [{
    conversation_id: 'conv_keep',
    deleted_through_message_id: 'msg_duplicate',
  }]);
  const reports = await database.query(`
    SELECT id, target_id, target_user_id FROM reports ORDER BY id
  `);
  assert.deepEqual(reports.rows, [
    { id: 'report_duplicate_chat', target_id: 'conv_keep', target_user_id: 'bob' },
    { id: 'report_missing', target_id: 'missing', target_user_id: null },
    { id: 'report_outsider_chat', target_id: 'conv_keep', target_user_id: null },
    { id: 'report_product', target_id: 'legacy_product', target_user_id: 'owner' },
    { id: 'report_user', target_id: 'real_user', target_user_id: 'real_user' },
    { id: 'report_wanted', target_id: 'legacy_wanted', target_user_id: 'owner' },
  ]);
  const notifications = await database.query(`
    SELECT id, data FROM notifications
     WHERE id IN ('notification_duplicate_chat', 'notification_invalid_json')
     ORDER BY id
  `);
  assert.deepEqual(JSON.parse(notifications.rows[0].data), {
    conversationId: 'conv_keep',
    preserve: 'yes',
  });
  assert.equal(notifications.rows[1].data, '{invalid-json');

  // El mismo conflict target que usa database.postgres.js debe inferir el
  // índice parcial/de expresión y recuperar el hilo existente sin duplicarlo.
  await database.query(`
    INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id)
    VALUES ('conv_loser', NULL, NULL, 'bob', 'alice')
    ON CONFLICT (LEAST(buyer_id, seller_id), GREATEST(buyer_id, seller_id))
      WHERE product_id IS NULL AND wanted_post_id IS NULL
      DO NOTHING
  `);
  const count = await database.query(`
    SELECT COUNT(*)::integer AS total
      FROM conversations
     WHERE product_id IS NULL AND wanted_post_id IS NULL
       AND LEAST(buyer_id, seller_id) = 'alice'
       AND GREATEST(buyer_id, seller_id) = 'bob'
  `);
  assert.equal(count.rows[0].total, 1);

  await assert.rejects(
    database.query(`
      INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id)
      VALUES ('conv_keep', NULL, NULL, 'carol', 'dave')
      ON CONFLICT (LEAST(buyer_id, seller_id), GREATEST(buyer_id, seller_id))
        WHERE product_id IS NULL AND wanted_post_id IS NULL
        DO NOTHING
    `),
    /unique|duplicate/i,
    'una colisión de PK ajena no se debe suavizar como conflicto de pareja',
  );
});
