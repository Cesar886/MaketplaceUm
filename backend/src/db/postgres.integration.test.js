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
      AND (title LIKE ? ESCAPE '\\' OR "ownerName" LIKE ? ESCAPE '\\'
        OR "ownerId" LIKE ? ESCAPE '\\')
    ORDER BY "createdAt" DESC, id DESC LIMIT ? OFFSET ?`;
  const query = bindParameters(sql, [
    'product', 'pending', '%libro%', '%libro%', '%libro%', 20, 0,
  ]);

  const plan = await database.query(`EXPLAIN ${query.text}`, query.values);
  assert.ok(plan.rows.length > 0);
});
