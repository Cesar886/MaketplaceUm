/**
 * Configuración de Mercado Pago, leída de backend/.env.
 *
 * A diferencia de `auth.js` —que revienta al arrancar si falta JWT_SECRET—
 * aquí la ausencia de credenciales NO tumba el proceso. La razón es que los
 * pagos son una función opcional que se añade sobre una app que ya funciona:
 * si el servidor no arrancara sin credenciales de MP, un despliegue sin
 * configurar dejaría caído también el chat, el feed y todo lo demás.
 *
 * En su lugar, `assertConfigurado()` hace que cada endpoint de pagos
 * responda 503 con un mensaje claro mientras falten credenciales.
 *
 * NINGÚN valor de este archivo debe imprimirse en un log. `resumenSeguro()`
 * existe para poder diagnosticar sin filtrar: dice qué falta, nunca qué vale.
 */

const MP_API_BASE = 'https://api.mercadopago.com';
const MP_AUTH_BASE = 'https://auth.mercadopago.com.mx';

const config = {
  // Clave PÚBLICA. Es la única credencial que puede salir hacia la app:
  // sirve solo para tokenizar tarjetas desde el cliente.
  publicKey: process.env.MP_PUBLIC_KEY || '',

  // Access token de LA PLATAFORMA (nuestra cuenta de Mercado Pago). Se usa
  // para operar Customers y tarjetas guardadas. NUNCA para cobrar: los
  // cobros van con el token del vendedor.
  accessToken: process.env.MP_ACCESS_TOKEN || '',

  // Credenciales de la aplicación, para el flujo OAuth con los vendedores.
  clientId: process.env.MP_CLIENT_ID || '',
  clientSecret: process.env.MP_CLIENT_SECRET || '',

  // Secreto de firma del webhook (panel de MP → Webhooks → clave secreta).
  webhookSecret: process.env.MP_WEBHOOK_SECRET || '',

  // Clave de cifrado en reposo de los tokens de vendedor (32 bytes en hex).
  // Generar con: openssl rand -hex 32
  encryptionKey: process.env.PAYMENTS_ENCRYPTION_KEY || '',

  // URL pública HTTPS del backend. Mercado Pago EXIGE https tanto en el
  // redirect_uri del OAuth como en la URL del webhook: una IP con http
  // simplemente es rechazada al registrarla.
  appPublicUrl: (process.env.APP_PUBLIC_URL || '').replace(/\/$/, ''),

  // Esquema de deep link de la app, para devolver al vendedor a Mercadito
  // después de autorizar en el navegador.
  appDeepLinkScheme: process.env.APP_DEEP_LINK_SCHEME || 'mercaditoum',

  moneda: process.env.MP_CURRENCY || 'MXN',
};

/**
 * Interruptor para cobrar SIN comisión de plataforma.
 *
 * Existe para las pruebas: mientras se prueba la integración contra Mercado
 * Pago, el split es justo la parte que más falla (ver el error 2059) y
 * poder apagarlo aísla "¿el cobro funciona?" de "¿el reparto funciona?".
 *
 * Por defecto está ENCENDIDO, y hace falta escribir exactamente 'false' para
 * apagarlo: cualquier otro valor —vacío, 'no', un typo— deja la comisión
 * puesta. Un interruptor de dinero tiene que fallar hacia cobrar, porque
 * apagarlo por accidente no da ningún error y no se descubre hasta que
 * alguien cuadra las cuentas semanas después.
 */
function comisionHabilitada() {
  return String(process.env.PLATFORM_FEE_ENABLED ?? 'true').toLowerCase() !== 'false';
}

/**
 * FORZAR el `sandbox_init_point` aunque el entorno no sea de pruebas.
 *
 * Ya NO hace falta en el flujo normal: `elegirInitPoint` (routes.js) decide
 * solo, a partir del tipo de credencial con la que se creó la preferencia.
 * Este interruptor queda como salida de emergencia, para forzar el enlace de
 * sandbox en un despliegue sin tocar código si alguna vez la detección no
 * acierta.
 *
 * Importante: SOLO el valor exacto 'true' fuerza algo. Cualquier otro valor
 * —incluido 'false', que es lo que hay escrito en los .env de siempre— deja
 * la decisión automática. Un `MP_USE_SANDBOX_INIT_POINT=false` olvidado en
 * un .env fue precisamente lo que mandó al comprador al checkout de
 * producción con una preferencia de prueba; no puede volver a mandar nada.
 */
function forzarSandboxInitPoint() {
  return String(process.env.MP_USE_SANDBOX_INIT_POINT || '').toLowerCase() === 'true';
}

/**
 * Volcar en el log el payload y la respuesta enteros de cada preferencia.
 *
 * La respuesta de Mercado Pago son ~2 KB por pago, y se registra dos veces
 * (creación y relectura). Es exactamente lo que hace falta mientras se
 * persigue un fallo, y puro ruido el resto del tiempo — un log que nadie
 * puede leer tampoco se lee el día que importa.
 *
 * Apagado por defecto. Lo imprescindible (qué cuenta cobra, qué enlace se
 * entregó, y todos los avisos) se registra siempre, con o sin esto.
 */
function depuracionPreferencia() {
  return String(process.env.MP_DEBUG_PREFERENCIA || '').toLowerCase() === 'true';
}

/** Porcentaje de comisión de la plataforma. Configurable, nunca hardcodeado. */
function porcentajeComision() {
  const crudo = process.env.PLATFORM_FEE_PERCENT;
  const valor = Number.parseFloat(crudo);
  if (!Number.isFinite(valor) || valor < 0 || valor > 100) {
    throw new Error(
      'PLATFORM_FEE_PERCENT no está definido o no es un porcentaje válido (0-100). ' +
      'Defínelo en backend/.env — la comisión no tiene valor por defecto a propósito.',
    );
  }
  return valor;
}

const REQUERIDAS = [
  ['MP_PUBLIC_KEY', 'publicKey'],
  ['MP_ACCESS_TOKEN', 'accessToken'],
  ['MP_CLIENT_ID', 'clientId'],
  ['MP_CLIENT_SECRET', 'clientSecret'],
  ['MP_WEBHOOK_SECRET', 'webhookSecret'],
  ['PAYMENTS_ENCRYPTION_KEY', 'encryptionKey'],
  ['APP_PUBLIC_URL', 'appPublicUrl'],
];

/** Nombres de las variables que faltan. Nunca devuelve valores. */
function faltantes() {
  const falta = REQUERIDAS.filter(([, campo]) => !config[campo]).map(([env]) => env);
  if (!process.env.PLATFORM_FEE_PERCENT) falta.push('PLATFORM_FEE_PERCENT');
  return falta;
}

function estaConfigurado() {
  return faltantes().length === 0;
}

/**
 * Corta la petición con 503 si los pagos no están configurados todavía.
 * Devuelve true si se debe continuar.
 */
function assertConfigurado(res) {
  const falta = faltantes();
  if (falta.length === 0) return true;
  // Los nombres de las variables no son secretos y decirlos ahorra una hora
  // de depuración a quien despliega. Los VALORES nunca se mencionan.
  console.error(`[pagos] Sin configurar. Faltan variables de entorno: ${falta.join(', ')}`);
  res.status(503).json({
    error: 'Los pagos no están disponibles todavía. Intenta más tarde.',
  });
  return false;
}

/** URL de callback del OAuth. Debe coincidir EXACTA con la del panel de MP. */
function redirectUri() {
  return `${config.appPublicUrl}/api/payments/oauth/callback`;
}

function resumenSeguro() {
  return {
    configurado: estaConfigurado(),
    faltantes: faltantes(),
  };
}

module.exports = {
  config,
  MP_API_BASE,
  MP_AUTH_BASE,
  porcentajeComision,
  comisionHabilitada,
  forzarSandboxInitPoint,
  depuracionPreferencia,
  estaConfigurado,
  assertConfigurado,
  faltantes,
  redirectUri,
  resumenSeguro,
};
