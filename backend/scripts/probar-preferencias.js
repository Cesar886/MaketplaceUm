#!/usr/bin/env node
/**
 * Aislar QUÉ campo del payload rompe el checkout de Mercado Pago.
 *
 * Contexto: el checkout carga "Oh, no, algo anduvo mal" con una preferencia
 * que MP acepta sin rechistar (HTTP 200, con su init_point). Cambiar el
 * enlace de producción a sandbox no lo arregló, así que el problema no es
 * a QUÉ checkout se manda, sino QUÉ tiene dentro la preferencia.
 *
 * Este script crea varias preferencias con el token del MISMO vendedor,
 * variando UN campo cada vez, e imprime el enlace de cada una. Abriéndolas
 * en el navegador se ve cuál carga el formulario de pago y cuál no: la
 * primera que funcione señala el campo culpable.
 *
 * Crea objetos reales en Mercado Pago, pero no cobra nada y las
 * preferencias caducan solas. Ejecutar EN EL SERVIDOR:
 *
 *   node scripts/probar-preferencias.js <mp_user_id_del_vendedor>
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const db = require('../src/database');
db.initDatabase();

const { config } = require('../src/payments/config');
const mp = require('../src/payments/mpClient');
const { tokenVigenteDeVendedor } = require('../src/payments/vendorTokens');

const ITEM = {
  id: 'diag-1',
  title: 'Prueba de diagnóstico',
  quantity: 1,
  unit_price: 50,
  currency_id: config.currency || 'MXN',
};

const BACK_URLS = {
  success: `${config.appPublicUrl}/api/payments/wallet/return?r=ok`,
  pending: `${config.appPublicUrl}/api/payments/wallet/return?r=pendiente`,
  failure: `${config.appPublicUrl}/api/payments/wallet/return?r=error`,
};

// Cada caso quita UNA cosa respecto del anterior. El orden va de "lo que
// manda el código hoy" a "lo mínimo que Mercado Pago acepta".
const CASOS = [
  {
    nombre: 'A · igual que el código (con marketplace_fee)',
    preferencia: {
      items: [ITEM],
      marketplace_fee: 2.5,
      external_reference: `diag-a-${Date.now()}`,
      notification_url: `${config.appPublicUrl}/api/payments/webhook`,
      statement_descriptor: 'MERCADITOUM',
      back_urls: BACK_URLS,
      auto_return: 'approved',
      expires: true,
      expiration_date_to: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    },
  },
  {
    nombre: 'B · SIN marketplace_fee (todo lo demás igual)',
    preferencia: {
      items: [ITEM],
      external_reference: `diag-b-${Date.now()}`,
      notification_url: `${config.appPublicUrl}/api/payments/webhook`,
      statement_descriptor: 'MERCADITOUM',
      back_urls: BACK_URLS,
      auto_return: 'approved',
      expires: true,
      expiration_date_to: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    },
  },
  {
    nombre: 'C · sin fee, sin auto_return, sin expires',
    preferencia: {
      items: [ITEM],
      external_reference: `diag-c-${Date.now()}`,
      notification_url: `${config.appPublicUrl}/api/payments/webhook`,
      back_urls: BACK_URLS,
    },
  },
  {
    nombre: 'D · mínima: solo los items',
    preferencia: { items: [ITEM] },
  },
];

/** El vendedor a probar: el que se pida, o el único conectado si hay uno. */
function elegirVendedor(pedido) {
  const filas = db.getDb().prepare(
    `SELECT seller_id, mp_user_id FROM vendor_payment_accounts
     WHERE revoked_at IS NULL`,
  ).all();

  if (pedido) {
    return filas.find(f => f.seller_id === pedido || String(f.mp_user_id) === pedido) || null;
  }
  if (filas.length === 1) return filas[0];
  console.error('Vendedores conectados:');
  filas.forEach(f => console.error(`  seller_id=${f.seller_id} mp_user_id=${f.mp_user_id}`));
  return null;
}

async function main() {
  const vendedor = elegirVendedor(process.argv[2]);
  if (!vendedor) {
    console.error('Uso: node scripts/probar-preferencias.js <seller_id | mp_user_id>');
    process.exit(1);
  }

  const token = await tokenVigenteDeVendedor(vendedor.seller_id);
  if (!token?.accessToken) {
    console.error(`No hay token vigente para el vendedor ${vendedor.seller_id}`);
    process.exit(1);
  }

  const quien = await mp.validarTokenVendedor(token.accessToken).catch(() => null);
  console.log(`Vendedor: id=${quien?.id} nick=${quien?.nickname}`);
  console.log(`Plataforma: ${String(config.accessToken).startsWith('TEST-') ? 'TEST-' : 'APP_USR-'}\n`);

  for (const caso of CASOS) {
    try {
      const pref = await mp.crearPreferencia({
        accessTokenVendedor: token.accessToken,
        idempotencyKey: `diag-${caso.nombre[0]}-${Date.now()}`,
        preferencia: caso.preferencia,
      });
      console.log(`${caso.nombre}\n  OK  ${pref.init_point}\n`);
    } catch (e) {
      console.log(`${caso.nombre}\n  FALLÓ  ${e.message} ${JSON.stringify(e.detalle || {})}\n`);
    }
  }
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
