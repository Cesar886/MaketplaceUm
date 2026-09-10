'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

function safeBackupDirectory() {
  const configured = String(process.env.MERCADITO_BACKUP_DIR || '').trim();
  const directory = configured
    ? path.resolve(configured)
    : path.join(__dirname, '..', 'backups');
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  return directory;
}

function run(command, args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env,
      shell: false,
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    let stderr = '';
    child.stderr.on('data', chunk => {
      if (stderr.length < 8_000) stderr += chunk.toString();
    });
    child.once('error', reject);
    child.once('close', code => {
      if (code === 0) return resolve();
      reject(new Error(`${command} terminó con código ${code}: ${stderr.trim()}`));
    });
  });
}

async function createSqliteTestBackup(database, destination) {
  await database.prepare('VACUUM INTO ?').run(destination);
  fs.chmodSync(destination, 0o600);
  return destination;
}

/**
 * Crea un pg_dump consistente antes de una operación administrativa masiva.
 * La contraseña viaja por PGPASSWORD, no por argumentos visibles en `ps`.
 */
async function createAdminBackup(database, label = 'admin-bulk') {
  const safeLabel = String(label).replace(/[^a-z0-9_-]/gi, '-').slice(0, 40) || 'admin-bulk';
  const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/[.]/g, '-');
  const extension = process.env.DATABASE_URL ? 'dump' : 'db';
  const destination = path.join(
    safeBackupDirectory(),
    `mercadito-${safeLabel}-${timestamp}-${crypto.randomBytes(4).toString('hex')}.${extension}`,
  );

  // Compatibilidad exclusiva con la suite legacy; producción exige URL PG.
  if (!process.env.DATABASE_URL) return createSqliteTestBackup(database, destination);

  const url = new URL(process.env.DATABASE_URL);
  const env = {
    ...process.env,
    PGHOST: url.hostname,
    PGPORT: url.port || '5432',
    PGUSER: decodeURIComponent(url.username),
    PGPASSWORD: decodeURIComponent(url.password),
    PGDATABASE: decodeURIComponent(url.pathname.slice(1)),
    PGSSLMODE: process.env.PGSSL === 'false' ? 'disable' : 'verify-full',
    ...(process.env.PGSSL_CA_FILE ? { PGSSLROOTCERT: path.resolve(process.env.PGSSL_CA_FILE) } : {}),
  };
  const args = [
    '--format=custom',
    '--compress=6',
    '--no-owner',
    '--no-privileges',
    '--file', destination,
  ];
  try {
    await run(process.env.PG_DUMP_BIN || 'pg_dump', args, env);
    fs.chmodSync(destination, 0o600);
    if (fs.statSync(destination).size < 64) throw new Error('pg_dump produjo un archivo vacío.');
    await run(process.env.PG_RESTORE_BIN || 'pg_restore', ['--list', destination], env);
    return destination;
  } catch (error) {
    try { fs.unlinkSync(destination); } catch {}
    throw new Error(`El backup PostgreSQL no pasó la verificación: ${error.message}`);
  }
}

module.exports = { createAdminBackup };
