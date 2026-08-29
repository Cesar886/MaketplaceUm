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

  // Esquema de deep link de la app, para devolver al vendedor a Marketplace
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
 * Interruptor global de Mercado Pago para TODO el backend.
 *
 * Espejo del flag `kMercadoPagoHabilitado` del frontend
 * (lib/features/payments/mercado_pago_flag.dart): mientras la app tenga la
 * integración comentada/oculta, nadie puede completar el paso de "conectar
 * cuenta de cobros" desde ningún lado, así que exigirlo en el backend
 * dejaría a cuentas negocio/estudiante/externo atoradas en 'pendiente' para
 * siempre sin ninguna forma de resolverlo.
 *
 * Por defecto está APAGADO (hace falta 'true' exacto para encenderlo), al
 * revés que `comisionHabilitada()`: ahí un apagado accidental cuesta dinero,
 * aquí un ENCENDIDO accidental sin que el frontend tenga la integración lista
 * es lo que bloquea usuarios — así que el valor por defecto es el lado
 * seguro para este interruptor en concreto.
 *
 * TODO: Mercado Pago pendiente para próxima actualización — cuando el
 * frontend reactive `kMercadoPagoHabilitado`, poner
 * `MERCADO_PAGO_HABILITADO=true` en el .env de cada entorno. No hace falta
 * tocar código: ver requisitosVerificacion.js, que ya usa este flag para
 * decidir si el requisito de cuenta de cobros aplica.
 */
function mercadoPagoHabilitado() {
  return String(process.env.MERCADO_PAGO_HABILITADO || '').toLowerCase() === 'true';
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

/**
 * Traza detallada del flujo de pago: qué entra por el webhook, cómo se
 * resuelve la orden, qué contestó MP y qué se guardó.
 *
 * Existe porque perseguir un pago que "se hizo pero no aparece" con los logs
 * de siempre obliga a adivinar en qué de los seis pasos se rompió. Con esto
 * encendido cada paso deja su línea y el fallo se señala solo.
 *
 * Apagado por defecto: son ~8 líneas por notificación y MP reenvía cada
 * evento varias veces. Lo imprescindible —el estado final de la orden y
 * TODOS los fallos— se registra siempre, con esto apagado.
 */
function depuracionPagos() {
  return String(process.env.DEBUG_PAGOS || '').toLowerCase() === 'true';
}

/**
 * Log de traza: solo sale con `DEBUG_PAGOS=true`.
 *
 * Se consulta la variable en cada llamada, no al arrancar, para poder
 * encenderla con `pm2 restart --update-env` sin editar código.
 */
function traza(mensaje) {
  if (depuracionPagos()) console.log(`[pagos][traza] ${mensaje}`);
}

/**
 * Deja un valor ajeno en condiciones de entrar en una línea de log.
 *
 * Hace falta de verdad: el webhook registra `topic`, `action` y `data.id`
 * ANTES de validar la firma, o sea que son datos de quien llame, sea quien
 * sea. Un salto de línea ahí permite escribir líneas enteras inventadas en
 * el log —"[pagos] Orden ord_x → approved", por ejemplo—, y este log es
 * justo donde miramos para saber si un pago entró. Un log que se puede
 * falsificar no sirve para decidir nada.
 */
function paraLog(valor, maximo = 120) {
  if (valor === undefined || valor === null) return '—';
  const limpio = String(valor).replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  return limpio.length > maximo ? `${limpio.slice(0, maximo)}…` : limpio;
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
  mercadoPagoHabilitado,
  forzarSandboxInitPoint,
  depuracionPreferencia,
  depuracionPagos,
  traza,
  paraLog,
  estaConfigurado,
  assertConfigurado,
  faltantes,
  redirectUri,
  resumenSeguro,
};
