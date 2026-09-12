/**
 * ¿Está abierto este vendedor AHORA?
 *
 * Vive en el servidor y no solo en la app porque de esto depende que un pago
 * se acepte o se rechace: la hora del dispositivo la controla quien lo usa, y
 * un reloj cambiado no puede ser lo que decida si un cobro entra.
 *
 * El horario se guarda como `{ "0": {open, close}, ... }` con 0=lunes..6=domingo
 * y horas "HH:MM" (ver validation/sellerProfile.js, que ya garantiza el
 * formato y que el cierre sea posterior a la apertura).
 */

const db = require('../database');

/** Minutos desde medianoche de una hora "HH:MM". */
function aMinutos(hhmm) {
  const [h, m] = String(hhmm).split(':');
  return Number(h) * 60 + Number(m);
}
function parsearHorario(crudo) {
  if (!crudo) return null;
  try {
    const valor = typeof crudo === 'string' ? JSON.parse(crudo) : crudo;
    if (!valor || typeof valor !== 'object' || Array.isArray(valor)) return null;
    return Object.keys(valor).length > 0 ? valor : null;
  } catch {
    return null;
  }
}

/**
 * Estado de atención de un vendedor.
 *
 * @param {Date} ahora inyectable para poder probar horas concretas sin
 *   depender de cuándo corra el test.
 * @returns {{abierto: boolean, tieneHorario: boolean, abreA: string|null,
 *            diaAbre: number|null}}
 *   `abierto` es true cuando NO hay horario configurado: quien no declara
 *   horario no está "cerrado", simplemente no usa esta función para nada, y
 *   tratarlo como cerrado le bloquearía las ventas sin motivo.
 */
async function estadoDeAtencion(sellerId, ahora = new Date()) {
  const fila = await db.getDb().prepare('SELECT businessHours FROM sellers WHERE id = ?').get(sellerId);
  const horario = parsearHorario(fila?.businessHours);
  if (!horario) {
    return {
      abierto: true,
      tieneHorario: false,
      abreA: null,
      diaAbre: null
    };
  }

  // JS getDay(): 0=domingo..6=sábado → 0=lunes..6=domingo, como lo guarda la
  // app. Es la misma conversión que hace computeProductStatus.
  const hoy = (ahora.getDay() + 6) % 7;
  const minutosAhora = ahora.getHours() * 60 + ahora.getMinutes();
  const deHoy = horario[String(hoy)];
  if (deHoy && minutosAhora >= aMinutos(deHoy.open) && minutosAhora < aMinutos(deHoy.close)) {
    return {
      abierto: true,
      tieneHorario: true,
      abreA: null,
      diaAbre: null
    };
  }

  // Cerrado: se busca la próxima apertura para poder decir "abre a las 9:00"
  // en vez de un "cerrado" a secas, que deja al comprador sin saber cuándo
  // volver. Hoy cuenta si su apertura todavía no llegó.
  if (deHoy && minutosAhora < aMinutos(deHoy.open)) {
    return {
      abierto: false,
      tieneHorario: true,
      abreA: deHoy.open,
      diaAbre: hoy
    };
  }
  for (let i = 1; i <= 7; i++) {
    const dia = (hoy + i) % 7;
    const rango = horario[String(dia)];
    if (rango) {
      return {
        abierto: false,
        tieneHorario: true,
        abreA: rango.open,
        diaAbre: dia
      };
    }
  }
  return {
    abierto: false,
    tieneHorario: true,
    abreA: null,
    diaAbre: null
  };
}
const DIAS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/** Mensaje listo para mostrar cuando el vendedor está cerrado. */
function mensajeCerrado(nombreVendedor, estado) {
  const quien = nombreVendedor || 'Este vendedor';
  if (!estado.abreA) return `${quien} está cerrado en este momento.`;
  const cuando = estado.diaAbre !== null ? ` el ${DIAS[estado.diaAbre]} a las ${estado.abreA}` : ` a las ${estado.abreA}`;
  return `${quien} está cerrado en este momento. Abre${cuando}.`;
}
module.exports = {
  estadoDeAtencion,
  mensajeCerrado,
  DIAS
};
