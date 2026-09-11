'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-direct-migration-'));
process.env.MERCADITO_DB_PATH = path.join(tempDir, 'legacy.db');

const db = require('../database');

db.initDatabase();

test.after(() => {
  try { db.getDb().close(); } catch {}
  fs.rmSync(tempDir, { recursive: true, force: true });
});

test('SQLite fusiona duplicados legacy sin romper cortes, reportes ni notificaciones', () => {
  const database = db.getDb();
  database.exec('DROP INDEX idx_conversations_direct_pair_unique');
  database.exec(`
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
      ('sqlite_conv_keep', NULL, NULL, 'alice', 'bob', '2026-01-01T00:00:00Z',
       '2026-01-01T00:01:00Z', 'primero'),
      ('sqlite_conv_duplicate', NULL, NULL, 'bob', 'alice', '2026-01-02T00:00:00Z',
       '2026-01-02T00:01:00Z', 'segundo');

    INSERT INTO messages (
      id, conversation_id, sender_id, text, created_at, read
    ) VALUES
      ('sqlite_msg_keep', 'sqlite_conv_keep', 'alice', 'primero', '2026-01-01T00:01:00Z', 0),
      ('sqlite_msg_duplicate', 'sqlite_conv_duplicate', 'bob', 'segundo', '2026-01-02T00:01:00Z', 0);

    INSERT INTO conversation_deletions (
      conversation_id, user_id, deleted_through_message_id, deleted_at
    ) VALUES
      ('sqlite_conv_keep', 'alice', 'sqlite_msg_keep', '2026-03-01T01:00:00Z'),
      ('sqlite_conv_duplicate', 'alice', 'sqlite_msg_duplicate', '2026-01-02T01:00:00Z');

    INSERT INTO products (id, title, price, seller)
    VALUES ('sqlite_product', 'Producto legado', '0', 'owner');

    INSERT INTO wanted_posts (id, user_id, title, category_id, type)
    VALUES ('sqlite_wanted', 'owner', 'Solicitud legada', 'otros', 'producto');

    INSERT INTO reports (id, reporter_id, target_type, target_id, target_user_id, reason)
    VALUES
      ('sqlite_report', 'alice', 'chat', 'sqlite_conv_duplicate', 'innocent', 'Mensajes sospechosos'),
      ('sqlite_outsider', 'mallory', 'chat', 'sqlite_conv_duplicate', 'innocent', 'Chat ajeno'),
      ('sqlite_user', 'alice', 'user', 'real_user', 'innocent', 'Usuario sospechoso'),
      ('sqlite_product_report', 'alice', 'product', 'sqlite_product', 'innocent', 'Producto sospechoso'),
      ('sqlite_wanted_report', 'alice', 'wanted', 'sqlite_wanted', 'innocent', 'Solicitud sospechosa'),
      ('sqlite_missing', 'alice', 'user', 'missing', 'innocent', 'Objetivo inexistente');

    INSERT INTO notifications (id, user_id, type, title, body, data)
    VALUES
      ('sqlite_notification', 'alice', 'new_message', 'Mensaje', 'Contenido',
       '{"conversationId":"sqlite_conv_duplicate","preserve":"yes"}'),
      ('sqlite_notification_invalid', 'alice', 'legacy', 'Legacy', 'Contenido', '{invalid-json');
  `);
  database.close();

  // Simula el primer arranque después de actualizar el backend.
  db.initDatabase();
  const migrated = db.getDb();
  const conversations = migrated.prepare(`
    SELECT id, last_message_preview FROM conversations
     WHERE product_id IS NULL AND wanted_post_id IS NULL
       AND ((buyer_id = 'alice' AND seller_id = 'bob')
         OR (buyer_id = 'bob' AND seller_id = 'alice'))
  `).all();
  assert.deepEqual(conversations, [{ id: 'sqlite_conv_keep', last_message_preview: 'segundo' }]);
  assert.deepEqual(migrated.prepare(`
    SELECT id, conversation_id FROM messages
     WHERE id LIKE 'sqlite_msg_%' ORDER BY id
  `).all(), [
    { id: 'sqlite_msg_duplicate', conversation_id: 'sqlite_conv_keep' },
    { id: 'sqlite_msg_keep', conversation_id: 'sqlite_conv_keep' },
  ]);
  assert.deepEqual(migrated.prepare(`
    SELECT conversation_id, deleted_through_message_id
      FROM conversation_deletions WHERE user_id = 'alice'
  `).get(), {
    conversation_id: 'sqlite_conv_keep',
    deleted_through_message_id: 'sqlite_msg_duplicate',
  });
  assert.deepEqual(migrated.prepare(`
    SELECT id, target_id, target_user_id FROM reports
     WHERE id LIKE 'sqlite_%' ORDER BY id
  `).all(), [
    { id: 'sqlite_missing', target_id: 'missing', target_user_id: null },
    { id: 'sqlite_outsider', target_id: 'sqlite_conv_keep', target_user_id: null },
    { id: 'sqlite_product_report', target_id: 'sqlite_product', target_user_id: 'owner' },
    { id: 'sqlite_report', target_id: 'sqlite_conv_keep', target_user_id: 'bob' },
    { id: 'sqlite_user', target_id: 'real_user', target_user_id: 'real_user' },
    { id: 'sqlite_wanted_report', target_id: 'sqlite_wanted', target_user_id: 'owner' },
  ]);
  assert.deepEqual(
    JSON.parse(migrated.prepare("SELECT data FROM notifications WHERE id = 'sqlite_notification'").get().data),
    { conversationId: 'sqlite_conv_keep', preserve: 'yes' },
  );
  assert.equal(
    migrated.prepare("SELECT data FROM notifications WHERE id = 'sqlite_notification_invalid'").get().data,
    '{invalid-json',
  );

  assert.throws(() => migrated.prepare(`
    INSERT INTO conversations (id, product_id, wanted_post_id, buyer_id, seller_id)
    VALUES ('sqlite_conv_loser', NULL, NULL, 'bob', 'alice')
  `).run(), /UNIQUE constraint/);
});
