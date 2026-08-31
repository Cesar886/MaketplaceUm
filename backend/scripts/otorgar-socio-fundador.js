#!/usr/bin/env node
/**
 * Otorga (o quita) la insignia verde "Socio Fundador" a una cuenta.
 *
 * No hay endpoint ni pantalla de admin para esto A PROPÓSITO: la insignia no
 * la gana ningún dato ni trámite de la cuenta — la decide el admin a mano,
 * cuenta por cuenta — así que no necesita más superficie que un script que
 * solo corre quien tiene acceso al servidor.
 *
 * Identifica la cuenta por, en este orden:
 *   1. `sellers.id` — el identificador interno (ej. u_daniel_2hk5).
 *   2. `sellers.email` — el correo con el que la cuenta se registró.
 *   3. `verificaciones.correo_institucional` — el correo con el que se
 *      verificó (routes/verificacion.js). Existe porque los dos correos NO
 *      son necesariamente el mismo: una cuenta puede haberse registrado con
 *      un correo personal y verificado después con el institucional, y
 *      `sellers.email` se queda con el primero — buscar solo ahí deja
 *      cuentas verificadas "invisibles" para este script aunque el admin
 *      tenga justo el correo institucional a mano.
 *
 * Uso:
 *   node scripts/otorgar-socio-fundador.js <id-o-correo>
 *   node scripts/otorgar-socio-fundador.js <id-o-correo> --quitar
 *
 * Importante: el servidor mantiene a los vendedores cacheados en memoria
 * (ver data.js) y solo los refresca cuando ÉL MISMO escribe en la tabla.
 * Este script corre en un proceso aparte, así que el cambio queda en
 * SQLite pero el servidor que está corriendo no se entera — hace falta
 * reiniciarlo (`pm2 restart <app>`) para que la insignia se vea en la API.
 */

const path = require('node:path');

// El .env trae MERCADITO_DB_PATH si el servidor no usa la ruta por default;
// sin cargarlo, el script escribiría en una base de prueba en vez de en la
// real.
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const db = require('../src/database');

function salir(mensaje, codigo = 1) {
  console.error(mensaje);
  process.exit(codigo);
}

/**
 * Busca la cuenta por id, por `sellers.email` o por
 * `verificaciones.correo_institucional`, en ese orden. Devuelve la primera
 * coincidencia o `undefined`.
 */
function buscarSeller(identificador, conexion) {
  const porId = conexion
    .prepare('SELECT id, name, email, socio_fundador FROM sellers WHERE id = ?')
    .get(identificador);
  if (porId) return porId;

  const porEmail = conexion
    .prepare('SELECT id, name, email, socio_fundador FROM sellers WHERE email = ?')
    .get(identificador);
  if (porEmail) return porEmail;

  return conexion
    .prepare(`
      SELECT s.id, s.name, s.email, s.socio_fundador
      FROM sellers s
      JOIN verificaciones v ON v.usuario_id = s.id
      WHERE v.correo_institucional = ?
    `)
    .get(identificador);
}

function main() {
  const identificador = process.argv[2];
  const quitar = process.argv.includes('--quitar');

  if (!identificador) {
    salir('Uso: node scripts/otorgar-socio-fundador.js <id-o-correo> [--quitar]');
  }

  db.initDatabase();
  const conexion = db.getDb();

  const seller = buscarSeller(identificador, conexion);

  if (!seller) {
    salir(
      `No hay ninguna cuenta con id, email o correo institucional "${identificador}".\n` +
        'Búscala a mano: sqlite3 mercadito_um.db "SELECT id, name, email FROM sellers WHERE name LIKE \'%...%\';"',
    );
  }

  const yaLaTiene = !!seller.socio_fundador;
  if (yaLaTiene === !quitar) {
    console.log(
      `${seller.name} (${seller.id}) ya ${quitar ? 'no tenía' : 'tiene'} la insignia. Nada que hacer.`,
    );
    return;
  }

  conexion
    .prepare('UPDATE sellers SET socio_fundador = ? WHERE id = ?')
    .run(quitar ? 0 : 1, seller.id);

  console.log(
    `${quitar ? 'Quitada' : 'Otorgada'} la insignia Socio Fundador a ${seller.name} (${seller.id}).`,
  );
  console.log('Si el servidor está corriendo, reinícialo (pm2 restart) para que se vea.');
}

main();
