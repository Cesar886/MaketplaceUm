/**
 * Comisión de la plataforma.
 *
 * El porcentaje vive en PLATFORM_FEE_PERCENT (backend/.env) y NO tiene
 * valor por defecto: un default silencioso aquí significa cobrar de más o
 * de menos a todos los vendedores sin que nadie lo note.
 */

const { porcentajeComision } = require('./config');

/**
 * Redondeo a 2 decimales.
 *
 * Ni `Math.round(x * 100) / 100` ni `toFixed(2)` sirven tal cual: 1.005 se
 * guarda en binario como 1.00499999…, así que ambos redondean hacia abajo y
 * dan 1.00. Sumar un EPSILON antes de redondear corrige ese sesgo sin
 * afectar a los valores que ya estaban bien (0.1 + 0.2 sigue dando 0.30).
 *
 * Aplicado a miles de cobros, ese medio centavo sistemático es dinero real.
 */
function redondear2(valor) {
  const n = Number(valor);
  if (!Number.isFinite(n)) return NaN;
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * @param {number} monto total de la orden
 * @returns {number} comisión de la plataforma, redondeada a 2 decimales
 */
function calcularComision(monto) {
  if (!Number.isFinite(monto) || monto <= 0) {
    throw new Error('El monto de la orden debe ser un número positivo');
  }
  const comision = redondear2((monto * porcentajeComision()) / 100);
  // La comisión nunca puede igualar o superar el total: dejaría al vendedor
  // en cero o en negativo, y MP rechazaría el pago con un error opaco.
  if (comision >= monto) {
    throw new Error('La comisión calculada iguala o supera el total de la orden');
  }
  return comision;
}

module.exports = { calcularComision, redondear2 };
