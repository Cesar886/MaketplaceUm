'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const backendRoot = path.join(__dirname, '..');

test('database.js siempre selecciona PostgreSQL y exige DATABASE_URL', () => {
  const probe = `
    process.env.NODE_ENV = 'test';
    delete process.env.DATABASE_URL;

    const selected = require('./src/database');
    const postgres = require('./src/database.postgres');
    if (selected !== postgres) {
      throw new Error('database.js seleccionó un adaptador distinto a PostgreSQL');
    }

    selected.initDatabase().then(
      () => { throw new Error('PostgreSQL arrancó sin DATABASE_URL'); },
      error => {
        if (!/DATABASE_URL es obligatoria para PostgreSQL/.test(error.message)) {
          throw error;
        }
      },
    );
  `;
  const result = spawnSync(process.execPath, ['-e', probe], {
    cwd: backendRoot,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
});
