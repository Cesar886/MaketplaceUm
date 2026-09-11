#!/usr/bin/env node
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

// Este comando crea credenciales reales. Debe usar siempre PostgreSQL y su
// política de arranque de producción, incluso si la terminal conserva
// NODE_ENV=test o MERCADITO_DB_PATH de una ejecución anterior.
process.env.NODE_ENV = 'production';

const bcrypt = require('bcryptjs');
const qrcode = require('qrcode');
const speakeasy = require('speakeasy');
const db = require('../src/database');
const {
  adminAuthConfigured,
  encryptTotpSecret,
  normalizeAdminUsername,
} = require('../src/adminAuth');

async function createAdmin({
  environment = process.env,
  databaseModule = db,
  authConfigured = adminAuthConfigured,
  encryptSecret = encryptTotpSecret,
  normalizeUsername = normalizeAdminUsername,
  passwordHasher = bcrypt,
  qrRenderer = qrcode,
  totpGenerator = speakeasy,
  output = process.stdout,
} = {}) {
  try {
    const username = normalizeUsername(environment.ADMIN_CREATE_USERNAME);
    const password = String(environment.ADMIN_CREATE_PASSWORD || '');

    if (!authConfigured()) {
      throw new Error(
        'Configura ADMIN_JWT_SECRET y ADMIN_TOTP_ENCRYPTION_KEY con al menos 32 caracteres.',
      );
    }
    if (!username) {
      throw new Error(
        'ADMIN_CREATE_USERNAME debe tener 3-64 caracteres: letras, numeros, punto, guion o guion bajo.',
      );
    }
    const passwordBytes = Buffer.byteLength(password, 'utf8');
    if (passwordBytes < 14 || passwordBytes > 72) {
      throw new Error('ADMIN_CREATE_PASSWORD debe tener entre 14 y 72 bytes UTF-8.');
    }

    await databaseModule.initDatabase();
    const database = databaseModule.getDb();
    const existing = await database.prepare(
      'SELECT 1 FROM admins WHERE username = ?',
    ).get(username);
    if (existing) {
      throw new Error('Ese administrador ya existe; no se sobrescribio ninguna credencial.');
    }

    const totp = totpGenerator.generateSecret({
      length: 32,
      issuer: 'Marketplace UM',
      name: `Marketplace UM (${username})`,
    });
    const passwordHash = await passwordHasher.hash(password, 12);
    const result = await database.prepare(
      `INSERT INTO admins (username, password_hash, totp_secret_encrypted)
       VALUES (?, ?, ?) RETURNING id`,
    ).run(username, passwordHash, encryptSecret(totp.base32));

    const terminalQr = await qrRenderer.toString(totp.otpauth_url, {
      type: 'terminal',
      small: true,
      errorCorrectionLevel: 'M',
    });
    output.write(
      `\nAdministrador #${result.lastInsertRowid} (${username}) creado.\n`
        + 'Escanea este QR ahora; no se guardara otra copia legible del secreto:\n\n'
        + terminalQr
        + '\nDespues, elimina ADMIN_CREATE_USERNAME y ADMIN_CREATE_PASSWORD del entorno.\n',
    );
    return { id: result.lastInsertRowid, username };
  } finally {
    // Reduce la vida de las credenciales en memoria y permite que el proceso
    // termine cerrando el pool PostgreSQL aun cuando ocurra un error.
    delete environment.ADMIN_CREATE_USERNAME;
    delete environment.ADMIN_CREATE_PASSWORD;
    if (typeof databaseModule.closeDatabase === 'function') {
      await databaseModule.closeDatabase();
    }
  }
}

if (require.main === module) {
  createAdmin().catch(error => {
    console.error(`No se pudo crear el administrador: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = { createAdmin };
