const crypto = require('crypto');
const rateLimit = require('express-rate-limit');

// A diferencia de casi todo el resto de la API, este endpoint no tiene
// requireAuth: se dispara desde el arranque de la app y en medio de fallos
// de red, momentos en los que puede no haber sesión ni token todavía. Eso
// lo deja alcanzable por cualquiera que sepa la IP del servidor. La
// frecuencia se acota por instalación y nunca por IP: una sola salida NAT
// puede representar a toda la universidad.
const VENTANA_MINUTOS = 1;
const MAX_PETICIONES_POR_INSTALACION = 20;

// Tope de caracteres por campo antes de loguear. No es una validación de
// "forma" (no rechaza el request) — es un tope duro para que un payload de
// varios MB no se vuelque completo al archivo de log.
const MAX_LARGO_CAMPO = 500;
const MAX_LARGO_STACK = 2000;

const PLATAFORMAS_VALIDAS = new Set(['android', 'ios', 'web', 'desktop']);

// Secuencias de escape ANSI/CSI y OSC completas — no basta con quitar el
// byte ESC suelto: dejar el resto de la secuencia (p. ej. "[31m" de un
// "\x1B[31m") le deja al terminal de quien lea el log con `pm2 logs` texto
// de control real, capaz de mover el cursor, cambiar colores o, en
// terminales vulnerables, más que eso.
// eslint-disable-next-line no-control-regex
const PATRON_ANSI = /\x1B(?:\[[0-9;?]*[a-zA-Z]|\][^\x07\x1B]*(?:\x07|\x1B\\))/g;

/**
 * Deja el texto seguro para escribirlo en el log:
 *  - fuera las secuencias ANSI (arriba) y los caracteres de control salvo,
 *    opcionalmente, `\n` — un stack trace real es multilínea por diseño y
 *    colapsarlo a una sola línea lo haría ilegible, así que [permitirSaltos]
 *    lo respeta. Lo que SIEMPRE se quita es `\r` (permite falsificar el
 *    inicio de una línea de log ya escrita) y el resto de caracteres de
 *    control — eso es lo que habilitaría inyección de logs.
 *  - recortado a [maxLargo], con un aviso de cuánto se cortó — así un
 *    payload de cientos de KB (Express ya topa a 100kb por defecto) no se
 *    vuelca completo a una sola entrada de log.
 */
function sanear(valor, maxLargo, { permitirSaltos = false } = {}) {
  if (typeof valor !== 'string') return null;
  const patronControl = permitirSaltos
    // eslint-disable-next-line no-control-regex
    ? /[\x00-\x09\x0B-\x1F\x7F]+/g
    // eslint-disable-next-line no-control-regex
    : /[\x00-\x1F\x7F]+/g;
  const limpio = valor
    .replace(PATRON_ANSI, ' ')
    .replace(patronControl, ' ')
    .trim();
  if (limpio.length === 0) return null;
  if (limpio.length <= maxLargo) return limpio;
  return `${limpio.slice(0, maxLargo)}… (+${limpio.length - maxLargo} caracteres recortados)`;
}

function register(app) {
  // POST /api/client-errors — recibe errores técnicos que la app atrapó y le
  // mostró al usuario ya traducidos (ver lib/services/api_error.dart). El
  // usuario nunca ve esto: es para que quede en los logs del servidor y se
  // pueda diagnosticar sin depender de que alguien reporte el problema.
  // Fire-and-forget desde el cliente, así que nunca debe romper nada aquí:
  // siempre responde 204 aunque el cuerpo venga incompleto.
  app.post(
    '/api/client-errors',
    rateLimit({
      windowMs: VENTANA_MINUTOS * 60 * 1000,
      limit: MAX_PETICIONES_POR_INSTALACION,
      keyGenerator: req => crypto.createHash('sha256').update(
        `client-error:${String(req.body?.installationId || '')}`,
      ).digest('base64url'),
      // Clientes antiguos todavía no envían installationId. No se les mete
      // en un bucket global que volvería a bloquear a toda la universidad.
      skip: req => typeof req.body?.installationId !== 'string'
        || !/^[A-Za-z0-9._:-]{8,180}$/.test(req.body.installationId),
      standardHeaders: 'draft-7',
      legacyHeaders: false,
      // 204 y no un error: este endpoint es fire-and-forget, así que un
      // cliente que se pasa del límite no debe recibir una excepción nueva
      // que reportar — el rate limit se aplica en silencio.
      handler: (_req, res) => res.status(204).end(),
    }),
    (req, res) => {
      const { contexto, error, stack, plataforma } = req.body || {};

      const plataformaSegura = PLATAFORMAS_VALIDAS.has(plataforma)
        ? plataforma
        : '?';
      const contextoSeguro = sanear(contexto, MAX_LARGO_CAMPO) || 'Error';
      const errorSeguro = sanear(error, MAX_LARGO_CAMPO) || '(sin detalle)';

      console.error(
        `📱 [client-error] ${plataformaSegura} — ${contextoSeguro}: ${errorSeguro}`,
      );

      const stackSeguro = sanear(stack, MAX_LARGO_STACK, {
        permitirSaltos: true,
      });
      if (stackSeguro) console.error(stackSeguro);

      res.status(204).end();
    },
  );
}

module.exports = { register, sanear };
