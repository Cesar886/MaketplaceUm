#!/usr/bin/env node
/**
 * Crea un usuario de prueba COMPRADOR en Mercado Pago.
 *
 * Por qué existe: los usuarios de prueba se "gastan". El comprador que
 * estábamos usando quedó en un estado en el que Mercado Pago le exige
 * validar un código enviado por e-mail para poder entrar al checkout, y un
 * usuario de prueba no tiene buzón real: no hay forma de sacarlo de ahí. La
 * salida documentada es crear otro.
 *
 * Importante: el usuario tiene que crearse con las credenciales de LA MISMA
 * aplicación que usa el vendedor, o el checkout falla aunque las dos cuentas
 * sean de prueba.
 *
 * Endpoint: POST /users/test_user
 * Credencial: access_token de LA PLATAFORMA (el del .env).
 *
 * Imprime el e-mail y la CONTRASEÑA del usuario creado. Guárdalos: Mercado
 * Pago no los vuelve a mostrar. Ejecutar EN EL SERVIDOR:
 *
 *   node scripts/crear-usuario-prueba.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { config } = require('../src/payments/config');

async function main() {
  if (!String(config.accessToken).startsWith('TEST-')) {
    console.error(
      'Las credenciales del .env NO son de prueba (TEST-). Crear usuarios de '
      + 'prueba con credenciales de producción no tiene sentido.',
    );
    process.exit(1);
  }

  const res = await fetch('https://api.mercadopago.com/users/test_user', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.accessToken}`,
      'Content-Type': 'application/json',
    },
    // MLM = México. Tiene que coincidir con el país de la aplicación.
    body: JSON.stringify({ site_id: 'MLM' }),
  });

  const datos = await res.json();
  if (!res.ok) {
    console.error(`Mercado Pago respondió ${res.status}:`, JSON.stringify(datos));
    process.exit(1);
  }

  console.log('\n═══ Comprador de prueba creado ═══\n');
  console.log(`  id:         ${datos.id}`);
  console.log(`  e-mail:     ${datos.email}`);
  console.log(`  contraseña: ${datos.password}`);
  console.log(`  nickname:   ${datos.nickname}`);
  console.log('\nGuárdalos ahora: Mercado Pago no los vuelve a mostrar.\n');
}

main().catch((e) => { console.error(e); process.exit(1); });
