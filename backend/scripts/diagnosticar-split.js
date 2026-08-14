#!/usr/bin/env node
/**
 * Diagnóstico del error 2059 de Mercado Pago:
 * "You cannot use application_fee with this payment".
 *
 * Ese error NO es un rechazo del pago ni un problema de la tarjeta: es
 * Mercado Pago diciendo que en ESTE cobro no se puede cobrar comisión de
 * plataforma. Sus dos causas documentadas son:
 *
 *   1. El vendedor conectado es LA MISMA cuenta que es dueña de la
 *      aplicación de Mercado Pago. Nadie puede cobrarse una comisión a sí
 *      mismo, así que MP rechaza el `application_fee` entero.
 *
 *   2. El access token con el que se cobra no salió de un flujo OAuth. El
 *      `application_fee` solo existe cuando quien cobra es un vendedor
 *      vinculado, no la propia plataforma.
 *
 * Este script pregunta a Mercado Pago quién es quién y dice cuál de las dos
 * está pasando. Solo LEE (`GET /users/me`): no crea, no cobra y no modifica
 * nada, ni en la base de datos ni en Mercado Pago.
 *
 * Ejecutar EN EL SERVIDOR, que es donde vive el .env real y la base de datos
 * con las cuentas conectadas:
 *
 *   node scripts/diagnosticar-split.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const db = require('../src/database');
db.initDatabase();

const { config } = require('../src/payments/config');
const store = require('../src/payments/store');
const mp = require('../src/payments/mpClient');
const { tokenVigenteDeVendedor } = require('../src/payments/vendorTokens');

/** 'TEST-…' o 'APP_USR-…' — decide si son credenciales de prueba. */
function tipoDeCredencial(valor) {
  if (!valor) return 'ausente';
  if (valor.startsWith('TEST-')) return 'PRUEBA (TEST-)';
  if (valor.startsWith('APP_USR-')) return 'PRODUCCIÓN (APP_USR-)';
  return 'desconocido';
}

async function quienEs(accessToken) {
  try {
    const yo = await mp.validarTokenVendedor(accessToken);
    return {
      id: String(yo.id),
      nick: yo.nickname,
      email: yo.email,
      siteId: yo.site_id,
    };
  } catch (err) {
    return { error: err.message, status: err.status };
  }
}

async function main() {
  console.log('═══ Credenciales de la plataforma (backend/.env) ═══\n');
  console.log(`  MP_ACCESS_TOKEN: ${tipoDeCredencial(config.accessToken)}`);
  console.log(`  MP_PUBLIC_KEY:   ${tipoDeCredencial(config.publicKey)}`);
  console.log(`  MP_CLIENT_ID:    ${config.clientId ? config.clientId : '(VACÍO)'}`);
  console.log(`  Moneda:          ${config.moneda}`);
  console.log(`  Comisión:        ${process.env.PLATFORM_FEE_PERCENT}%\n`);

  // Quién es la PLATAFORMA: la cuenta dueña de la aplicación de MP.
  const plataforma = await quienEs(config.accessToken);
  if (plataforma.error) {
    console.error(`No se pudo identificar la cuenta de la plataforma: ${plataforma.error}`);
    console.error('Revisa MP_ACCESS_TOKEN en backend/.env.\n');
  } else {
    console.log('═══ Cuenta DUEÑA de la aplicación ═══\n');
    console.log(`  user_id: ${plataforma.id}`);
    console.log(`  nick:    ${plataforma.nick}`);
    console.log(`  email:   ${plataforma.email}`);
    console.log(`  país:    ${plataforma.siteId}\n`);
  }

  // Quiénes son los VENDEDORES conectados por OAuth.
  const conectados = db.getDb().prepare(`
    SELECT a.seller_id, a.mp_user_id, s.name, s.email
    FROM vendor_payment_accounts a
    JOIN sellers s ON s.id = a.seller_id
    WHERE a.revoked_at IS NULL
  `).all();

  console.log('═══ Vendedores con cuenta conectada ═══\n');
  if (conectados.length === 0) {
    console.log('  Ninguno. Sin cuenta conectada no hay cobros posibles.\n');
    return;
  }

  let hayColision = false;

  for (const fila of conectados) {
    console.log(`  Vendedor ${fila.seller_id} — ${fila.name} <${fila.email}>`);
    console.log(`    mp_user_id guardado: ${fila.mp_user_id}`);

    const token = await tokenVigenteDeVendedor(fila.seller_id);
    if (!token?.accessToken) {
      console.log('    ⚠️  Sin access token vigente: tiene que volver a conectar.\n');
      continue;
    }

    const quien = await quienEs(token.accessToken);
    if (quien.error) {
      console.log(`    ⚠️  MP rechazó su token (${quien.status}): ${quien.error}\n`);
      continue;
    }

    console.log(`    según MP:            ${quien.id} (${quien.nick} <${quien.email}>)`);

    // El prefijo del token NO se usa para decidir esto, y antes sí: decía
    // "PRODUCCIÓN (APP_USR-)" de usuarios de prueba, porque MP les da tokens
    // `APP_USR-` igual que a las cuentas reales. Esa línea hizo perseguir una
    // mezcla test/producción que no existía. Lo que sí lo dice es quién es la
    // cuenta: MP nombra a sus usuarios de prueba TESTUSER…/@testuser.com.
    const esPrueba = String(quien.nick || '').startsWith('TESTUSER')
      || String(quien.email || '').endsWith('@testuser.com');
    console.log(`    entorno:             ${esPrueba ? 'CUENTA DE PRUEBA' : 'CUENTA REAL'}`);

    if (!plataforma.error && quien.id === plataforma.id) {
      hayColision = true;
      console.log('    ❌ ES LA MISMA CUENTA QUE LA DUEÑA DE LA APLICACIÓN.');
      console.log('       Esta es la causa del error 2059: no se puede cobrar');
      console.log('       application_fee a uno mismo.\n');
    } else {
      console.log('    ✅ Cuenta distinta de la dueña de la aplicación.\n');
    }
  }

  console.log('═══ Veredicto ═══\n');
  if (hayColision) {
    console.log('  El vendedor conectado y el dueño de la aplicación son la misma');
    console.log('  cuenta de Mercado Pago. Mientras siga así, TODO cobro con');
    console.log('  application_fee va a fallar con 2059, con tarjeta de prueba o');
    console.log('  real, con débito o crédito, y sea cual sea el importe.');
    console.log('');
    console.log('  Solución: desconectar esa cuenta y conectar en su lugar un');
    console.log('  USUARIO DE PRUEBA VENDEDOR creado desde el panel de');
    console.log('  developers de Mercado Pago. El comprador también debe ser un');
    console.log('  usuario de prueba distinto.');
  } else if (!plataforma.error) {
    console.log('  Las cuentas son distintas, así que la causa 1 queda descartada.');
    console.log('  Quedan por revisar, en el panel de Mercado Pago:');
    console.log('   · Que la aplicación esté creada con el modelo de integración');
    console.log('     "Marketplace" (no se puede cambiar después: hay que crear');
    console.log('     otra aplicación si se eligió mal).');
    console.log('   · Que el token del vendedor venga del OAuth de ESA aplicación');
    console.log('     y no de otra.');
  }
}

main().catch((err) => {
  console.error(`\nFalló el diagnóstico: ${err.message}`);
  process.exit(1);
});
