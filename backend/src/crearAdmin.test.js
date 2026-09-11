'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

// Reproduce una terminal que conservó las variables de la suite legacy. El
// require del CLI debe corregir NODE_ENV antes de cargar el selector de DB.
process.env.NODE_ENV = 'test';
process.env.MERCADITO_DB_PATH = '/tmp/no-debe-usarse-para-crear-admin.db';
const { createAdmin } = require('../scripts/crear-admin');

test.after(() => {
  delete process.env.MERCADITO_DB_PATH;
});

function dependencies({ initDatabase, getExisting, insert, closeDatabase } = {}) {
  const environment = {
    ADMIN_CREATE_USERNAME: 'Admin.Principal',
    ADMIN_CREATE_PASSWORD: 'una-frase-segura-de-prueba',
  };
  const preparedSql = [];
  const database = {
    prepare(sql) {
      preparedSql.push(sql);
      if (/^SELECT 1 FROM admins/.test(sql)) {
        return { get: getExisting || (async () => undefined) };
      }
      if (/^INSERT INTO admins/.test(sql)) {
        return { run: insert || (async () => ({ changes: 1, lastInsertRowid: 41 })) };
      }
      throw new Error(`SQL inesperado: ${sql}`);
    },
  };
  const databaseModule = {
    initDatabase: initDatabase || (async () => database),
    getDb: () => database,
    closeDatabase: closeDatabase || (async () => {}),
  };
  let output = '';
  return {
    environment,
    preparedSql,
    options: {
      environment,
      databaseModule,
      authConfigured: () => true,
      normalizeUsername: value => String(value).trim().toLowerCase(),
      encryptSecret: value => `encrypted:${value}`,
      passwordHasher: {
        hash: async (value, rounds) => `hash:${rounds}:${value}`,
      },
      totpGenerator: {
        generateSecret: () => ({
          base32: 'JBSWY3DPEHPK3PXP',
          otpauth_url: 'otpauth://totp/Marketplace%20UM',
        }),
      },
      qrRenderer: {
        toString: async () => '<qr-terminal>',
      },
      output: {
        write(value) { output += value; },
      },
    },
    writtenOutput: () => output,
  };
}

test('fuerza PostgreSQL de producción aunque la terminal tuviera variables de test', () => {
  assert.equal(process.env.NODE_ENV, 'production');
});

test('espera init, SELECT e INSERT, solicita RETURNING id y cierra el pool', async () => {
  const events = [];
  let initialized = false;
  const fixture = dependencies({
    initDatabase: async () => {
      events.push('init:start');
      await new Promise(resolve => setImmediate(resolve));
      initialized = true;
      events.push('init:end');
    },
    getExisting: async () => {
      assert.equal(initialized, true, 'el SELECT no debe empezar antes de initDatabase');
      events.push('select:start');
      await new Promise(resolve => setImmediate(resolve));
      events.push('select:end');
      return undefined;
    },
    insert: async (...args) => {
      events.push('insert:start');
      assert.deepEqual(args, [
        'admin.principal',
        'hash:12:una-frase-segura-de-prueba',
        'encrypted:JBSWY3DPEHPK3PXP',
      ]);
      await new Promise(resolve => setImmediate(resolve));
      events.push('insert:end');
      return { changes: 1, lastInsertRowid: 41 };
    },
    closeDatabase: async () => { events.push('close'); },
  });

  const result = await createAdmin(fixture.options);

  assert.deepEqual(result, { id: 41, username: 'admin.principal' });
  assert.deepEqual(events, [
    'init:start', 'init:end',
    'select:start', 'select:end',
    'insert:start', 'insert:end',
    'close',
  ]);
  assert.match(fixture.preparedSql[1], /RETURNING id\s*$/);
  assert.match(fixture.writtenOutput(), /Administrador #41 \(admin\.principal\) creado/);
  assert.equal('ADMIN_CREATE_USERNAME' in fixture.environment, false);
  assert.equal('ADMIN_CREATE_PASSWORD' in fixture.environment, false);
});

test('cierra PostgreSQL y borra credenciales incluso si initDatabase falla', async () => {
  const failure = new Error('falló la conexión inicial');
  let closeCalls = 0;
  const fixture = dependencies({
    initDatabase: async () => { throw failure; },
    closeDatabase: async () => { closeCalls += 1; },
  });

  await assert.rejects(createAdmin(fixture.options), error => error === failure);
  assert.equal(closeCalls, 1);
  assert.equal('ADMIN_CREATE_USERNAME' in fixture.environment, false);
  assert.equal('ADMIN_CREATE_PASSWORD' in fixture.environment, false);
  assert.equal(fixture.preparedSql.length, 0);
});
