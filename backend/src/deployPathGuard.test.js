'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const guard = path.join(__dirname, '..', 'scripts', 'deploy-path-guard.sh');
const dataPaths = `DATA_PATHS=(
  '.env' '.env.*' '*.db' '*.db-wal' '*.db-shm' '*.db.*'
  '*.sqlite' '*.sqlite3' '*.bak' '*.bak.*' '*.dump'
  'backups/' 'backups/**' 'uploads/' 'uploads/**' 'logs/' 'logs/**'
  'data.json' 'infra/postgres/secrets/*_password'
)`;

function inspect(output) {
  const result = spawnSync('bash', ['-c', `
    set -euo pipefail
    ${dataPaths}
    source "$1"
    deploy_find_protected_changes "$2"
  `, 'deploy-guard-test', guard, output], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

test('el guard ignora código y estadísticas del dry-run', () => {
  const output = [
    '<f.st......|src/routes/revision.js',
    '<f.st......|src/routes/search.js',
    '<f.st......|src/adminBackup.js',
    'sent 4,894 bytes  received 308 bytes  2,080.80 bytes/sec',
    'total size is 1,431,746  speedup is 275.23 (DRY RUN)',
  ].join('\n');
  assert.equal(inspect(output), '');
});

test('el guard bloquea datos, backups y secretos PostgreSQL reales', () => {
  const output = [
    '<f+++++++++|mercadito_um.db',
    '*deleting  |infra/postgres/backups/produccion.dump',
    '<f+++++++++|infra/postgres/secrets/postgres_app_password',
    '<f+++++++++|nested/uploads/comprobante.jpg',
  ].join('\n');
  const result = inspect(output);
  assert.match(result, /mercadito_um\.db/);
  assert.match(result, /produccion\.dump/);
  assert.match(result, /postgres_app_password/);
  assert.match(result, /comprobante\.jpg/);
});
