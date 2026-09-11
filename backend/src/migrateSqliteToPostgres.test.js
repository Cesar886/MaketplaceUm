'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ALLOWED_SOURCE_ONLY_COLUMNS,
  ALLOWED_SOURCE_ONLY_TABLES,
  analyzeSchemaCompatibility,
  assertPostImportState,
  assertRequiredSeedState,
  buildReplacementSql,
  replacementTables,
} = require('../scripts/migrate-sqlite-to-postgres');

const columns = (...names) => names.map(column_name => ({ column_name }));

function historicalSource() {
  return new Map([
    ['categories', columns('id', 'name')],
    ['highlight_plans', columns('id', 'title')],
    ['messages', columns('id', 'text')],
    ['products', columns('id', 'title')],
    ['sellers', columns('id', 'name')],
    ['wanted_posts', columns('id', 'title')],
  ]);
}

function postgresTarget() {
  return new Map([
    ['admins', columns('id', 'username')],
    ['categories', columns('id', 'name')],
    ['config', columns('key', 'products_active')],
    ['highlight_plans', columns('id', 'title')],
    ['messages', columns('id', 'seq', 'text')],
    ['products', columns(
      'id', 'title', 'expires_at', 'moderation_status', 'moderation_reason',
      'moderated_at', 'moderated_by_admin_id',
    )],
    ['sellers', columns(
      'id', 'name', 'profile_views', 'admin_status', 'admin_status_reason',
      'admin_status_until', 'auth_invalid_before', 'deleted_at',
    )],
    ['wanted_posts', columns(
      'id', 'title', 'expires_at', 'moderation_status', 'moderation_reason',
      'moderated_at', 'moderated_by_admin_id',
    )],
  ]);
}

test('el preflight acepta solamente las ausencias historicas clasificadas', () => {
  const compatibility = analyzeSchemaCompatibility(historicalSource(), postgresTarget());

  assert.deepEqual(compatibility.importedTables, [
    'categories', 'highlight_plans', 'messages', 'products', 'sellers', 'wanted_posts',
  ]);
  assert.deepEqual(compatibility.preservedTables, ['admins', 'config']);
  assert.equal(ALLOWED_SOURCE_ONLY_TABLES.size, 0);
  assert.equal(ALLOWED_SOURCE_ONLY_COLUMNS.size, 0);
});

test('el preflight bloquea tablas y columnas SQLite que se perderian', () => {
  const source = historicalSource();
  source.set('legacy_payments', columns('id', 'payload'));
  source.get('products').push({ column_name: 'legacy_secret' });

  assert.throws(
    () => analyzeSchemaCompatibility(source, postgresTarget()),
    error => {
      assert.match(error.message, /tabla SQLite sin destino: legacy_payments/);
      assert.match(error.message, /columna SQLite sin destino: products\.legacy_secret/);
      return true;
    },
  );
});

test('el preflight obliga a clasificar nuevas tablas y columnas PostgreSQL', () => {
  const target = postgresTarget();
  target.set('future_feature', columns('id'));
  target.get('products').push({ column_name: 'future_column' });

  assert.throws(
    () => analyzeSchemaCompatibility(historicalSource(), target),
    error => {
      assert.match(error.message, /tabla PostgreSQL ausente en SQLite y no clasificada: future_feature/);
      assert.match(error.message, /columna PostgreSQL ausente en SQLite y no clasificada: products\.future_column/);
      return true;
    },
  );
});

test('el reemplazo incluye solo tablas del snapshot y nunca usa CASCADE', () => {
  const compatibility = analyzeSchemaCompatibility(historicalSource(), postgresTarget());
  const tables = replacementTables([
    'categories', 'config', 'messages', 'products', 'sellers', 'wanted_posts',
  ], compatibility);

  assert.deepEqual(tables, ['categories', 'messages', 'products', 'sellers', 'wanted_posts']);
  const sql = buildReplacementSql('public', tables);
  assert.match(sql, /^TRUNCATE "public"\."categories"/);
  assert.match(sql, /RESTART IDENTITY$/);
  assert.doesNotMatch(sql, /CASCADE/i);
  assert.doesNotMatch(sql, /"config"/);
});

test('los catalogos incompletos abortan antes del reemplazo', () => {
  assert.doesNotThrow(() => assertRequiredSeedState(new Map([
    ['categories', 8], ['highlight_plans', 4], ['config', 5],
  ]), 'prueba'));
  assert.throws(
    () => assertRequiredSeedState(new Map([['config', 0]]), 'PostgreSQL preservado'),
    /Preflight de catalogos fallo.*config: 0\/5/,
  );
});

test('la validacion final comprueba conteos y que lo preservado no cambie', () => {
  const valid = {
    importedSourceCounts: new Map([['sellers', 17], ['products', 12]]),
    targetCounts: new Map([['sellers', 17], ['products', 12]]),
    preservedBefore: new Map([['config', 5], ['admins', 0]]),
    preservedAfter: new Map([['config', 5], ['admins', 0]]),
  };
  assert.doesNotThrow(() => assertPostImportState(valid));

  assert.throws(
    () => assertPostImportState({
      ...valid,
      targetCounts: new Map([['sellers', 16], ['products', 12]]),
      preservedAfter: new Map([['config', 0], ['admins', 1]]),
    }),
    error => {
      assert.match(error.message, /sellers: SQLite=17, PostgreSQL=16/);
      assert.match(error.message, /config: tabla preservada cambio de 5 a 0/);
      assert.match(error.message, /admins: tabla preservada cambio de 0 a 1/);
      assert.match(error.message, /config: catalogo preservado incompleto \(0\/5\)/);
      return true;
    },
  );
});
