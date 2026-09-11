#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const Database = require('better-sqlite3');

const source = path.resolve(process.argv[2] || path.join(__dirname, '..', 'mercadito_um.db'));
const outputDir = path.resolve(
  process.argv[3] || path.join(__dirname, '..', 'backups', 'sqlite-cutover'),
);

function validate(database, label) {
  const quickCheck = database.pragma('quick_check', { simple: true });
  if (quickCheck !== 'ok') throw new Error(`${label}: quick_check devolvió ${quickCheck}`);
  const foreignKeys = database.pragma('foreign_key_check');
  if (foreignKeys.length) {
    throw new Error(`${label}: ${foreignKeys.length} violaciones de llave foránea`);
  }
}

async function main() {
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) {
    throw new Error(`No existe el SQLite origen: ${source}`);
  }
  fs.mkdirSync(outputDir, { recursive: true, mode: 0o700 });
  fs.chmodSync(outputDir, 0o700);

  const stamp = new Date().toISOString().replaceAll(/[-:.]/g, '').replace('Z', 'Z');
  const destination = path.join(outputDir, `mercadito_um-${stamp}.db`);
  const temporary = `${destination}.tmp`;
  const checksumPath = `${destination}.sha256`;
  let sourceDb;
  let snapshotDb;
  try {
    sourceDb = new Database(source, { readonly: true, fileMustExist: true });
    validate(sourceDb, 'origen');
    await sourceDb.backup(temporary);
    fs.chmodSync(temporary, 0o600);

    snapshotDb = new Database(temporary, { readonly: true, fileMustExist: true });
    validate(snapshotDb, 'snapshot');
    const tables = snapshotDb.prepare(`
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name
    `).all();
    const counts = Object.fromEntries(tables.map(({ name }) => {
      const safeName = name.replaceAll('"', '""');
      return [name, snapshotDb.prepare(`SELECT COUNT(*) AS total FROM "${safeName}"`).get().total];
    }));
    snapshotDb.close();
    snapshotDb = undefined;
    sourceDb.close();
    sourceDb = undefined;

    fs.renameSync(temporary, destination);
    const hash = crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex');
    fs.writeFileSync(checksumPath, `${hash}  ${path.basename(destination)}\n`, { mode: 0o600 });
    process.stdout.write(`${JSON.stringify({ destination, checksumPath, sha256: hash, counts }, null, 2)}\n`);
  } finally {
    try { snapshotDb?.close(); } catch {}
    try { sourceDb?.close(); } catch {}
    try { fs.unlinkSync(temporary); } catch {}
  }
}

main().catch(error => {
  console.error(`No se pudo crear el snapshot SQLite: ${error.message}`);
  process.exitCode = 1;
});
