#!/usr/bin/env node
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const bcrypt = require('bcryptjs');
const qrcode = require('qrcode');
const speakeasy = require('speakeasy');
const db = require('../src/database');
const {
  adminAuthConfigured,
  encryptTotpSecret,
  normalizeAdminUsername,
} = require('../src/adminAuth');

async function main() {
  const username = normalizeAdminUsername(process.env.ADMIN_CREATE_USERNAME);
  const password = String(process.env.ADMIN_CREATE_PASSWORD || '');

  if (!adminAuthConfigured()) {
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

  db.initDatabase();
  const database = db.getDb();
  if (database.prepare('SELECT 1 FROM admins WHERE username = ?').get(username)) {
    throw new Error('Ese administrador ya existe; no se sobrescribio ninguna credencial.');
  }

  const totp = speakeasy.generateSecret({
    length: 32,
    issuer: 'Marketplace UM',
    name: `Marketplace UM (${username})`,
  });
  const passwordHash = await bcrypt.hash(password, 12);
  const result = database.prepare(
    `INSERT INTO admins (username, password_hash, totp_secret_encrypted)
     VALUES (?, ?, ?)`,
  ).run(username, passwordHash, encryptTotpSecret(totp.base32));

  // Evita que futuros imports accidentales del proceso puedan leer la clave.
  delete process.env.ADMIN_CREATE_PASSWORD;

  const terminalQr = await qrcode.toString(totp.otpauth_url, {
    type: 'terminal',
    small: true,
    errorCorrectionLevel: 'M',
  });
  process.stdout.write(
    `\nAdministrador #${result.lastInsertRowid} (${username}) creado.\n`
      + 'Escanea este QR ahora; no se guardara otra copia legible del secreto:\n\n'
      + terminalQr
      + '\nDespues, elimina ADMIN_CREATE_USERNAME y ADMIN_CREATE_PASSWORD del entorno.\n',
  );
}

main().catch(error => {
  console.error(`No se pudo crear el administrador: ${error.message}`);
  process.exitCode = 1;
});
