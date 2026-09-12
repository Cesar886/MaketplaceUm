'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { bindParameters, sqliteFunctionsToPostgres } = require('./postgres');

test('traduce parámetros posicionales sin tocar literales ni comentarios', () => {
  const query = bindParameters("SELECT '?' AS literal, ? AS valor -- ?\n, (?)::text AS texto", [7, 'ocho']);
  assert.equal(query.text, "SELECT '?' AS literal, $1 AS valor -- ?\n, ($2)::text AS texto");
  assert.deepEqual(query.values, [7, 'ocho']);
});

test('reutiliza parámetros nombrados y conserva casts PostgreSQL', () => {
  const query = bindParameters(
    'SELECT @id AS primero, :id AS segundo, (@dias)::int AS dias',
    [{ id: 'u1', dias: 7 }],
  );
  assert.equal(query.text, 'SELECT $1 AS primero, $1 AS segundo, ($2)::int AS dias');
  assert.deepEqual(query.values, ['u1', 7]);
});

test('convierte funciones SQLite críticas a SQL PostgreSQL parametrizado', () => {
  const query = bindParameters(
    "UPDATE sellers SET auth_invalid_before = MAX(COALESCE(auth_invalid_before, 0), ?) "
      + "WHERE admin_status_until IS ? AND created_at >= datetime('now', '-7 days')",
    [1_800_000_001_000, null],
  );
  assert.match(query.text, /GREATEST\(COALESCE\(auth_invalid_before, 0\), \$1\)/);
  assert.match(query.text, /admin_status_until IS NOT DISTINCT FROM \$2/);
  assert.match(query.text, /CURRENT_TIMESTAMP - INTERVAL '7 days'/);
});

test('INSERT OR IGNORE se convierte en ON CONFLICT DO NOTHING', () => {
  const query = bindParameters(
    'INSERT OR IGNORE INTO categories (id, name) VALUES (?, ?)',
    ['books', 'Libros'],
  );
  assert.equal(
    query.text,
    'INSERT INTO categories (id, name) VALUES ($1, $2) ON CONFLICT DO NOTHING',
  );
});

test('los epochs traducidos no desbordan en 2038', () => {
  assert.match(
    sqliteFunctionsToPostgres("SELECT CAST(strftime('%s', created_at) AS INTEGER) FROM products"),
    /AS BIGINT/,
  );
});

test('preserva alias camelCase que PostgreSQL plegaría a minúsculas', () => {
  assert.equal(
    sqliteFunctionsToPostgres('SELECT created_at AS createdAt FROM products'),
    'SELECT created_at AS "createdAt" FROM products',
  );
});

test('el esquema usa BIGINT para epochs y cortes de sesión', () => {
  const schema = fs.readFileSync(
    path.join(__dirname, '..', '..', 'migrations', 'postgres', '001_initial.sql'),
    'utf8',
  );
  assert.match(schema, /auth_invalid_before BIGINT NOT NULL/);
  assert.match(schema, /admin_revoked_tokens[\s\S]*?expires_at BIGINT NOT NULL/);
  assert.match(schema, /revoked_sessions[\s\S]*?expires_at BIGINT NOT NULL/);
});
