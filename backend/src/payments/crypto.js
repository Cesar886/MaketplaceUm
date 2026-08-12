/**
 * Cifrado en reposo de los tokens de Mercado Pago de los vendedores.
 *
 * El access_token de un vendedor permite cobrar en su nombre. Guardarlo en
 * texto plano significa que cualquiera con una copia del archivo .db —un
 * respaldo mal guardado, un `scp` a un portátil— puede mover dinero de todos
 * los vendedores del marketplace. Por eso van cifrados con AES-256-GCM.
 *
 * GCM y no CBC porque es autenticado: si alguien altera el ciphertext en la
 * base de datos, el descifrado FALLA en vez de devolver basura silenciosa.
 *
 * Formato guardado: "v1.<iv_hex>.<authTag_hex>.<ciphertext_hex>". El prefijo
 * de versión permite rotar el algoritmo más adelante sin adivinar qué es
 * cada fila.
 */

const crypto = require('crypto');
const { config } = require('./config');

const ALGORITMO = 'aes-256-gcm';
const VERSION = 'v1';
const IV_BYTES = 12; // 96 bits, el tamaño recomendado para GCM.

function clave() {
  const hex = config.encryptionKey;
  if (!hex) {
    throw new Error(
      'PAYMENTS_ENCRYPTION_KEY no está definida. Genera una con: openssl rand -hex 32',
    );
  }
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error(
      'PAYMENTS_ENCRYPTION_KEY debe ser exactamente 32 bytes en hexadecimal (64 caracteres). ' +
      'Genera una con: openssl rand -hex 32',
    );
  }
  return Buffer.from(hex, 'hex');
}

/** @param {string} textoPlano @returns {string} cadena guardable en SQLite */
function cifrar(textoPlano) {
  if (typeof textoPlano !== 'string' || textoPlano.length === 0) {
    throw new Error('cifrar() requiere una cadena no vacía');
  }
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITMO, clave(), iv);
  const cifrado = Buffer.concat([cipher.update(textoPlano, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [VERSION, iv.toString('hex'), tag.toString('hex'), cifrado.toString('hex')].join('.');
}

/**
 * @param {string|null} guardado
 * @returns {string|null} null si el valor es nulo; lanza si está corrupto o
 * fue manipulado (nunca devuelve un token a medias).
 */
function descifrar(guardado) {
  if (guardado == null || guardado === '') return null;
  const partes = String(guardado).split('.');
  if (partes.length !== 4 || partes[0] !== VERSION) {
    throw new Error('Valor cifrado con formato desconocido');
  }
  const [, ivHex, tagHex, datosHex] = partes;
  const decipher = crypto.createDecipheriv(ALGORITMO, clave(), Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  // Si el contenido fue alterado, .final() lanza aquí. Es lo que queremos.
  return Buffer.concat([decipher.update(Buffer.from(datosHex, 'hex')), decipher.final()])
    .toString('utf8');
}

module.exports = { cifrar, descifrar };
