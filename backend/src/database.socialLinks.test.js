const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-social-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';

const db = require('./database');

db.initDatabase();

test('las columnas de redes sociales existen en sellers', () => {
  const cols = db.getDb().prepare("PRAGMA table_info('sellers')").all().map(c => c.name);
  for (const col of ['facebook_url', 'instagram_url', 'whatsapp_number', 'tiktok_url', 'twitter_url']) {
    assert.ok(cols.includes(col), `falta la columna ${col}`);
  }
});

test('un negocio ya verificado sin redes sociales queda con estos campos en NULL, sin tocar su verificación', () => {
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, verified, tipo_cuenta)
     VALUES (?, 'Negocio Viejo', 'NV', '', 1, 1, 'negocio')`,
  ).run('seller_social_viejo_1');

  const row = db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get('seller_social_viejo_1');
  assert.strictEqual(row.facebook_url, null);
  assert.strictEqual(row.instagram_url, null);
  assert.strictEqual(row.whatsapp_number, null);
  assert.strictEqual(row.tiktok_url, null);
  assert.strictEqual(row.twitter_url, null);
  assert.strictEqual(row.verified, 1);

  const seller = db.rowToSeller(row);
  assert.strictEqual(seller.facebookUrl, null);
  assert.strictEqual(seller.instagramUrl, null);
  assert.strictEqual(seller.whatsappNumber, null);
  assert.strictEqual(seller.tiktokUrl, null);
  assert.strictEqual(seller.twitterUrl, null);
  assert.strictEqual(seller.verified, true);
});

test('rowToSeller expone los valores guardados', () => {
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, verified, tipo_cuenta,
       facebook_url, instagram_url, whatsapp_number, tiktok_url, twitter_url)
     VALUES (?, 'Negocio Con Redes', 'NR', '', 1, 1, 'negocio',
       'https://facebook.com/negocio', 'https://instagram.com/negocio', '5215512345678',
       'https://tiktok.com/@negocio', 'https://x.com/negocio')`,
  ).run('seller_social_lleno_1');

  const row = db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get('seller_social_lleno_1');
  const seller = db.rowToSeller(row);
  assert.strictEqual(seller.facebookUrl, 'https://facebook.com/negocio');
  assert.strictEqual(seller.instagramUrl, 'https://instagram.com/negocio');
  assert.strictEqual(seller.whatsappNumber, '5215512345678');
  assert.strictEqual(seller.tiktokUrl, 'https://tiktok.com/@negocio');
  assert.strictEqual(seller.twitterUrl, 'https://x.com/negocio');
});
