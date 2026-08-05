// Generación y verificación de códigos OTP de un solo uso.
//
// Los códigos se guardan HASHEADOS en la tabla `verificaciones`: un dump de
// mercadito_um.db no debe alcanzar para verificar la cuenta de alguien más.
// SHA-256 (y no bcrypt) porque el espacio de búsqueda es de solo 10^6: un
// hash lento no aporta seguridad real aquí, y lo que de verdad protege contra
// fuerza bruta es el tope de intentos de confirmación en el endpoint.

const crypto = require('crypto');

const LONGITUD_CODIGO = 6;
const VIGENCIA_MINUTOS = 10;

/** Código numérico de 6 dígitos, con ceros a la izquierda si hacen falta. */
function generarCodigo() {
  return String(crypto.randomInt(0, 10 ** LONGITUD_CODIGO)).padStart(
    LONGITUD_CODIGO,
    '0',
  );
}

function hashCodigo(codigo) {
  return crypto.createHash('sha256').update(String(codigo)).digest('hex');
}

/** Instante de expiración en ISO-8601 UTC, consistente con el resto del schema. */
function calcularExpiracion() {
  return new Date(Date.now() + VIGENCIA_MINUTOS * 60 * 1000).toISOString();
}

/**
 * @returns {{ ok: boolean, razon: null|'sin_codigo'|'expirado'|'incorrecto' }}
 */
function verificarCodigo(codigoIngresado, hashGuardado, expiraEn) {
  if (!hashGuardado || !expiraEn) {
    return { ok: false, razon: 'sin_codigo' };
  }
  if (new Date(expiraEn).getTime() <= Date.now()) {
    return { ok: false, razon: 'expirado' };
  }

  // Se comparan los HASHES, no los códigos: así ambos buffers miden siempre
  // 32 bytes y timingSafeEqual nunca lanza por longitudes distintas, sin
  // importar qué mande el cliente.
  const esperado = Buffer.from(hashGuardado, 'hex');
  const recibido = Buffer.from(hashCodigo(codigoIngresado ?? ''), 'hex');
  if (esperado.length !== recibido.length) {
    return { ok: false, razon: 'incorrecto' };
  }
  return crypto.timingSafeEqual(esperado, recibido)
    ? { ok: true, razon: null }
    : { ok: false, razon: 'incorrecto' };
}

module.exports = {
  generarCodigo,
  hashCodigo,
  verificarCodigo,
  calcularExpiracion,
  LONGITUD_CODIGO,
  VIGENCIA_MINUTOS,
};
