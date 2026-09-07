const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

function safeBackupDirectory(database) {
  const configured = String(process.env.MERCADITO_BACKUP_DIR || '').trim();
  const databaseFile = database.prepare('PRAGMA database_list').all()
    .find(entry => entry.name === 'main')?.file;
  if (!databaseFile) throw new Error('No se pudo resolver el archivo SQLite principal.');
  const directory = configured
    ? path.resolve(configured)
    : path.join(path.dirname(databaseFile), 'backups');
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  return directory;
}

/**
 * Crea una instantanea consistente (incluye WAL) antes de una operacion
 * masiva. VACUUM INTO falla si el destino existe, asi que nunca sobrescribe
 * un respaldo previo. La comprobacion quick_check evita continuar con una
 * copia truncada o ilegible.
 */
function createAdminBackup(database, label = 'admin-bulk') {
  const safeLabel = String(label).replace(/[^a-z0-9_-]/gi, '-').slice(0, 40) || 'admin-bulk';
  const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/[.]/g, '-');
  const filename = `mercadito-${safeLabel}-${timestamp}-${crypto.randomBytes(4).toString('hex')}.db`;
  const destination = path.join(safeBackupDirectory(database), filename);

  database.prepare('VACUUM INTO ?').run(destination);
  try {
    fs.chmodSync(destination, 0o600);
    const copy = new Database(destination, { readonly: true, fileMustExist: true });
    try {
      const check = copy.pragma('quick_check', { simple: true });
      if (check !== 'ok') throw new Error(`quick_check: ${check}`);
    } finally {
      copy.close();
    }
  } catch (error) {
    try { fs.unlinkSync(destination); } catch {}
    throw new Error(`El backup SQLite no paso la verificacion: ${error.message}`);
  }

  return destination;
}

module.exports = { createAdminBackup };
