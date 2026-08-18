// Envío del código de verificación por correo (flujo de estudiante).
//
// Sin credenciales SMTP: en desarrollo imprime el código en consola y lo
// devuelve para que el endpoint lo exponga como `codigo_dev`; en producción
// reporta 'no_disponible' y el endpoint responde 503. Ver envio.js.

const { resolverModoEnvio, esProduccion } = require('./envio');
const { VIGENCIA_MINUTOS } = require('./otp');

const REMITENTE_POR_DEFECTO = 'Marketplace UM <no-reply@um.edu.mx>';

// Tope para cada fase del diálogo SMTP (conexión, saludo, socket).
const TIMEOUT_SMTP_MS = 10000;

let transporteCache;

function estaConfigurado() {
  return Boolean(
    process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS,
  );
}

// nodemailer se carga de forma perezosa: si nunca se envía un correo (modo
// dev), no se paga su require al arrancar el servidor.
function obtenerTransporte() {
  if (!transporteCache) {
    const nodemailer = require('nodemailer');
    transporteCache = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT || 587),
      secure: process.env.SMTP_SECURE === 'true',
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
      // Sin estos límites se heredan los de nodemailer: 30 s de saludo,
      // 2 min de conexión y 10 MINUTOS de socket. Un SMTP que acepta la
      // conexión y luego no contesta deja el request colgado todo ese rato,
      // y el catch de solicitarOtp nunca llega a ejecutarse porque un cuelgue
      // no lanza. Con esto falla rápido y el usuario recibe un 502.
      connectionTimeout: TIMEOUT_SMTP_MS,
      greetingTimeout: TIMEOUT_SMTP_MS,
      socketTimeout: TIMEOUT_SMTP_MS,
    });
  }
  return transporteCache;
}

function cuerpoTexto(codigo) {
  return [
    `Tu código de verificación de Marketplace UM es: ${codigo}`,
    '',
    `El código vence en ${VIGENCIA_MINUTOS} minutos.`,
    'Si no solicitaste verificar tu cuenta, ignora este correo.',
  ].join('\n');
}

function cuerpoTexto(codigo) {
  return [
    `Tu código de verificación de Marketplace UM es: ${codigo}`,
    '',
    `El código vence en ${VIGENCIA_MINUTOS} minutos.`,
    'Si no solicitaste verificar tu cuenta, ignora este correo.',
  ].join('\n');
}

function cuerpoHtml(codigo) {
  return `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#FAF9F6;padding:64px 16px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:400px;">

            <tr>
              <td style="padding-bottom:48px;">
                <span style="color:#1B1A16;font-size:13px;font-weight:600;letter-spacing:1.5px;text-transform:uppercase;">
                  Marketplace UM
                </span>
              </td>
            </tr>

            <tr>
              <td style="padding-bottom:8px;">
                <h1 style="color:#1B1A16;margin:0;font-size:20px;font-weight:600;letter-spacing:-0.2px;">
                  Verifica tu cuenta
                </h1>
              </td>
            </tr>

            <tr>
              <td style="padding-bottom:40px;">
                <p style="color:#8A8680;margin:0;font-size:14px;line-height:1.6;">
                  Ingresa este código para confirmar tu correo institucional.
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding-bottom:12px;border-bottom:1px solid #E8E5DE;">
                <span style="font-size:36px;letter-spacing:12px;font-weight:300;color:#1B1A16;">
                  ${codigo}
                </span>
              </td>
            </tr>

            <tr>
              <td style="padding-top:14px;padding-bottom:56px;">
                <span style="color:#B0ABA1;font-size:12px;letter-spacing:0.3px;">
                  Expira en ${VIGENCIA_MINUTOS} minutos
                </span>
              </td>
            </tr>

            <tr>
              <td style="border-top:1px solid #E8E5DE;padding-top:24px;">
                <p style="color:#B0ABA1;margin:0;font-size:12px;line-height:1.7;">
                  Si no solicitaste este código, puedes ignorar este correo.
                </p>
                <p style="color:#CFCBC2;margin:12px 0 0 0;font-size:11px;">
                  Universidad de Montemorelos
                </p>
              </td>
            </tr>

          </table>
        </td>
      </tr>
    </table>
  `;
}

/**
 * @returns {Promise<{ modo: 'proveedor'|'dev'|'no_disponible' }>}
 */
async function enviarCodigo(correo, codigo) {
  const { modo } = resolverModoEnvio({
    configurado: estaConfigurado(),
    produccion: esProduccion(),
  });

  if (modo === 'dev') {
    console.log(`📧 [modo dev] Código de verificación para ${correo}: ${codigo}`);
    return { modo };
  }
  if (modo === 'no_disponible') {
    console.error('❌ SMTP no configurado: no se puede enviar el código por correo.');
    return { modo };
  }

  // Estos tres logs acotan el hueco donde el request se quedaba mudo: hasta
  // ahora la rama 'proveedor' no imprimía nada, así que un sendMail colgado
  // era indistinguible de un proceso muerto.
  console.log('[verificacion] Intentando enviar correo a:', correo);
  const inicio = Date.now();
  try {
    const info = await obtenerTransporte().sendMail({
      from: process.env.SMTP_FROM || REMITENTE_POR_DEFECTO,
      to: correo,
      subject: `Tu código de verificación: ${codigo}`,
      text: cuerpoTexto(codigo),
      html: cuerpoHtml(codigo),
    });
    console.log(
      `[verificacion] Correo enviado exitosamente en ${Date.now() - inicio}ms, ` +
      `messageId: ${info.messageId}`,
    );
  } catch (error) {
    // Se relanza a propósito: solicitarOtp depende de que esto falle para
    // responder 502 y NO guardar el código en la base (si lo guardara, el
    // usuario quemaría un intento por un código que nunca recibió).
    console.error(
      `[verificacion] Error al enviar correo tras ${Date.now() - inicio}ms ` +
      `(code=${error.code}, command=${error.command}):`,
      error,
    );
    throw error;
  }
  return { modo };
}

module.exports = { enviarCodigo, estaConfigurado };
