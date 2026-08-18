// Envío del código de verificación por SMS (flujo de cuenta externa).
//
// Misma interfaz que mailer.js. Twilio todavía no está contratado, así que en
// desarrollo esto opera en modo dev (código en consola). Cuando existan las
// credenciales basta con ponerlas en backend/.env — no hay que tocar código.
//
// Explícitamente SMS, no WhatsApp API.

const { resolverModoEnvio, esProduccion } = require('./envio');
const { VIGENCIA_MINUTOS } = require('./otp');

let clienteCache;

function estaConfigurado() {
  return Boolean(
    process.env.TWILIO_ACCOUNT_SID &&
      process.env.TWILIO_AUTH_TOKEN &&
      process.env.TWILIO_FROM,
  );
}

// twilio se carga de forma perezosa: mientras no haya credenciales el paquete
// nunca se importa, así que su ausencia no puede romper el arranque.
function obtenerCliente() {
  if (!clienteCache) {
    const twilio = require('twilio');
    clienteCache = twilio(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_AUTH_TOKEN,
    );
  }
  return clienteCache;
}

/**
 * @returns {Promise<{ modo: 'proveedor'|'dev'|'no_disponible' }>}
 */
async function enviarCodigo(telefono, codigo) {
  const { modo } = resolverModoEnvio({
    configurado: estaConfigurado(),
    produccion: esProduccion(),
  });

  if (modo === 'dev') {
    console.log(`📱 [modo dev] Código de verificación para ${telefono}: ${codigo}`);
    return { modo };
  }
  if (modo === 'no_disponible') {
    console.error('❌ Twilio no configurado: no se puede enviar el código por SMS.');
    return { modo };
  }

  await obtenerCliente().messages.create({
    from: process.env.TWILIO_FROM,
    to: telefono,
    body:
      `Marketplace UM: tu código de verificación es ${codigo}. ` +
      `Vence en ${VIGENCIA_MINUTOS} minutos.`,
  });
  return { modo };
}

module.exports = { enviarCodigo, estaConfigurado };
