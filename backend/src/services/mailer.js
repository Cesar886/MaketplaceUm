// Envío del código de verificación por correo (flujo de estudiante).
//
// Sin credenciales SMTP: en desarrollo imprime el código en consola y lo
// devuelve para que el endpoint lo exponga como `codigo_dev`; en producción
// reporta 'no_disponible' y el endpoint responde 503. Ver envio.js.

const { resolverModoEnvio, esProduccion } = require('./envio');
const { VIGENCIA_MINUTOS } = require('./otp');

const REMITENTE_POR_DEFECTO = 'Mercadito UM <no-reply@um.edu.mx>';

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
    });
  }
  return transporteCache;
}

function cuerpoTexto(codigo) {
  return [
    `Tu código de verificación de Mercadito UM es: ${codigo}`,
    '',
    `El código vence en ${VIGENCIA_MINUTOS} minutos.`,
    'Si no solicitaste verificar tu cuenta, ignora este correo.',
  ].join('\n');
}

function cuerpoHtml(codigo) {
  return `
    <div style="font-family:system-ui,-apple-system,sans-serif;max-width:420px">
      <h2 style="color:#3D5C70;margin-bottom:4px">Verifica tu cuenta</h2>
      <p style="color:#6E6B64;margin-top:0">Mercadito UM</p>
      <p style="font-size:32px;letter-spacing:8px;font-weight:700;color:#1B1A16">${codigo}</p>
      <p style="color:#6E6B64">El código vence en ${VIGENCIA_MINUTOS} minutos.</p>
      <p style="color:#6E6B64;font-size:13px">
        Si no solicitaste verificar tu cuenta, ignora este correo.
      </p>
    </div>
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

  await obtenerTransporte().sendMail({
    from: process.env.SMTP_FROM || REMITENTE_POR_DEFECTO,
    to: correo,
    subject: `Tu código de verificación: ${codigo}`,
    text: cuerpoTexto(codigo),
    html: cuerpoHtml(codigo),
  });
  return { modo };
}

module.exports = { enviarCodigo, estaConfigurado };
