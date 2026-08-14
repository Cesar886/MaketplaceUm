#!/usr/bin/env node
/**
 * Comprueba CONTRA MERCADO PAGO DE VERDAD que el split del pago con la
 * cuenta del comprador está bien montado.
 *
 * Por qué hace falta un script y no basta con los tests: los tests de
 * `walletCheckout.test.js` sustituyen `mpClient.crearPreferencia` por un
 * doble, así que fijan qué le MANDAMOS a Mercado Pago pero no qué hace
 * Mercado Pago con ello. Y justo ahí está el riesgo real de esta
 * integración: en `/v1/payments` la comisión se llama `application_fee` y en
 * `/checkout/preferences` se llama `marketplace_fee`. Mandar el nombre
 * equivocado NO da error — MP ignora el campo en silencio, la preferencia se
 * crea, el comprador paga, y la plataforma no cobra un peso. Un fallo que no
 * levanta ninguna alarma solo se detecta preguntándole a MP.
 *
 * Qué hace exactamente:
 *   1. Toma un vendedor con su cuenta de MP conectada (de la base de datos).
 *   2. Crea una preferencia real con `marketplace_fee`, por el camino del
 *      código de producción (`mpClient.crearPreferencia`).
 *   3. La vuelve a LEER de MP y comprueba que la comisión quedó guardada.
 *   4. La deja caducada al minuto para no dejar basura pagable.
 *
 * Qué NO hace: cobrar. Una preferencia es un presupuesto, no un cargo. Nadie
 * pierde dinero ejecutando esto — pero SÍ crea un objeto en la cuenta real
 * del vendedor, así que no se ejecuta solo desde ningún sitio.
 *
 * Uso:
 *   node scripts/verificar-marketplace-fee.js <vendorId>
 *   node scripts/verificar-marketplace-fee.js --listar
 *
 * Hazlo primero con credenciales de PRUEBA (usuarios de prueba de MP). El
 * resultado con credenciales productivas es el mismo, pero deja la
 * preferencia colgando en la cuenta de un vendedor real.
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const cfg = require('../src/payments/config');

function salir(mensaje, codigo = 1) {
  console.error(mensaje);
  process.exit(codigo);
}

const faltan = cfg.faltantes();
if (faltan.length > 0) {
  salir(`Faltan variables de entorno en backend/.env: ${faltan.join(', ')}`);
}

const db = require('../src/database');
db.initDatabase();

const store = require('../src/payments/store');
const mp = require('../src/payments/mpClient');
const { tokenVigenteDeVendedor } = require('../src/payments/vendorTokens');
const { calcularComision, redondear2 } = require('../src/payments/fees');

/** Vendedores con cuenta conectada, para no adivinar el id a mano. */
function listarConectados() {
  return db.getDb().prepare(`
    SELECT s.id, s.name
    FROM vendor_payment_accounts a
    JOIN sellers s ON s.id = a.seller_id
    WHERE a.revoked_at IS NULL
  `).all();
}

async function main() {
  const arg = process.argv[2];

  if (!arg || arg === '--listar') {
    const conectados = listarConectados();
    if (conectados.length === 0) {
      salir('Ningún vendedor tiene su cuenta de Mercado Pago conectada.');
    }
    console.log('Vendedores con cuenta conectada:\n');
    for (const v of conectados) console.log(`  ${v.id}  ${v.name}`);
    console.log('\nRepite con: node scripts/verificar-marketplace-fee.js <vendorId>');
    return;
  }

  const vendorId = arg;
  const cuenta = store.getCuentaVendedor(vendorId);
  if (!cuenta) salir(`El vendedor ${vendorId} no tiene una cuenta conectada y viva.`);

  const token = await tokenVigenteDeVendedor(vendorId);
  if (!token?.accessToken) salir(`No se pudo obtener un access token vigente de ${vendorId}.`);

  // Un importe redondo hace que el porcentaje se lea de un vistazo.
  const total = 200;
  const comision = redondear2(calcularComision(total));

  console.log(`Vendedor:  ${vendorId}`);
  console.log(`Importe:   ${total} ${cfg.config.moneda}`);
  console.log(`Comisión:  ${comision} (${process.env.PLATFORM_FEE_PERCENT}%)\n`);

  const preferencia = await mp.crearPreferencia({
    accessTokenVendedor: token.accessToken,
    idempotencyKey: `verificacion-${Date.now()}`,
    preferencia: {
      items: [{
        id: 'verificacion',
        title: 'Verificación de marketplace_fee (no cobrar)',
        quantity: 1,
        unit_price: total,
        currency_id: cfg.config.moneda,
      }],
      marketplace_fee: comision,
      external_reference: `verificacion-${Date.now()}`,
      // Un minuto: lo justo para leerla de vuelta y que quede inservible.
      expires: true,
      expiration_date_to: new Date(Date.now() + 60 * 1000).toISOString(),
    },
  });

  console.log(`Preferencia creada: ${preferencia.id}`);

  // El eco de la creación no es prueba suficiente: se relee de MP. Es la
  // diferencia entre "MP aceptó el JSON" y "MP guardó la comisión".
  const guardada = await mp.obtenerPreferencia(preferencia.id, token.accessToken);
  const feeGuardado = guardada?.marketplace_fee;

  console.log(`marketplace_fee según MP: ${JSON.stringify(feeGuardado)}\n`);

  if (Number(feeGuardado) === comision) {
    console.log('✅ El split está bien: Mercado Pago guardó la comisión de la plataforma.');
    console.log(`   De ${total} ${cfg.config.moneda}, ${comision} son de la plataforma`);
    console.log('   y el resto entra a la cuenta del vendedor (menos la comisión de MP).');
    return;
  }

  console.error('❌ Mercado Pago NO guardó la comisión.');
  console.error('   La preferencia se crea igual y el comprador puede pagar, pero la');
  console.error('   plataforma cobraría 0. Revisa que el campo se llame `marketplace_fee`');
  console.error('   (no `application_fee`) y que el token sea el DEL VENDEDOR, no el');
  console.error('   de la plataforma: con el de la plataforma no hay split que hacer.');
  process.exit(1);
}

main().catch((err) => {
  // El detalle de un MpError va al log del servidor por diseño; aquí el
  // servidor es esta terminal y quien la mira es quien despliega.
  const detalle = err instanceof mp.MpError
    ? `status=${err.status} detalle=${JSON.stringify(err.detalle)}`
    : err.stack;
  salir(`\nFalló la verificación: ${err.message}\n${detalle}`);
});
