#!/usr/bin/env node
/**
 * Elimina una o varias cuentas y TODO lo que cuelga de ellas.
 *
 * ======================= LEER ANTES DE CORRER =========================
 * `sellers` NO tiene foreign key hacia lo que de verdad importa:
 * `products.seller`, `conversations.buyer_id`, `conversations.seller_id` y
 * `messages.sender_id` son columnas TEXT sueltas, sin `ON DELETE CASCADE`.
 *
 * Es decir: un `DELETE FROM sellers WHERE email = ...` a secas NO limpia
 * nada. Deja productos en el catálogo con un vendedor inexistente y
 * conversaciones colgadas en la bandeja de LA OTRA PERSONA, con el
 * interlocutor en null. Por eso este script existe y por eso borra en un
 * orden explícito en vez de confiar en la cascada.
 *
 * Alcance de un borrado, por cuenta:
 *   1. Sus productos, y lo que cuelga de esos productos (comentarios,
 *      preguntas, calificaciones, carritos, historial de precio…). Si no,
 *      se cambian unos huérfanos por otros.
 *   2. Sus conversaciones —como comprador Y como vendedor— con todos sus
 *      mensajes. Se borra la conversación entera, no solo sus mensajes:
 *      media conversación apuntando a un fantasma es peor que ninguna.
 *   3. Lo que solo le pertenece a la cuenta (notificaciones, tokens push,
 *      intereses, carrito, verificación, pagos…).
 *   4. La fila de `sellers`.
 *
 * Uso:
 *   node scripts/eliminar-cuenta.js <correo> [<correo>...]     → dry-run
 *   node scripts/eliminar-cuenta.js <correo> --force           → borra
 *
 * Sin `--force` no escribe NADA: solo cuenta y enseña qué se llevaría por
 * delante. Con `--force` respalda la base antes de tocarla.
 * ======================================================================
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const db = require('../src/database');

const args = process.argv.slice(2);
const FORCE = args.includes('--force');
const correos = args
  .filter(a => !a.startsWith('--'))
  .map(c => c.trim().toLowerCase());

if (correos.length === 0) {
  console.error('Uso: node scripts/eliminar-cuenta.js <correo> [...] [--force]');
  process.exit(2);
}

db.initDatabase();
const conexion = db.getDb();

// ─── Qué se borra, y en qué orden ──────────────────────────────────────
//
// El orden importa: lo que cuelga de los productos y de las conversaciones
// se va ANTES que los productos y las conversaciones mismas, para poder
// seguir identificándolo con un subquery.

/** Tablas cuyas filas mueren con el PRODUCTO del usuario. */
const POR_PRODUCTO = [
  ['product_comments', 'product_id'],
  ['product_questions', 'product_id'],
  ['product_ratings', 'product_id'],
  ['cart', 'productId'],
  ['price_history', 'product_id'],
  ['interacciones_dispositivo', 'product_id'],
  ['interest_notification_queue', 'product_id'],
  ['listings', 'productId'],
  ['order_items', 'product_id'],
];

/** Tablas cuyas filas mueren con la CONVERSACIÓN del usuario. */
const POR_CONVERSACION = [
  ['messages', 'conversation_id'],
  ['conversation_deletions', 'conversation_id'],
];

/** Tablas donde la fila es del usuario y punto. `[tabla, columna]`. */
const POR_USUARIO = [
  ['product_comments', 'user_id'],
  ['product_questions', 'asked_by'],
  ['product_questions', 'seller_id'],
  ['product_ratings', 'user_id'],
  ['cart', 'user_id'],
  ['category_interests', 'user_id'],
  ['notifications', 'user_id'],
  ['push_tokens', 'user_id'],
  ['secret_solves', 'user_id'],
  ['interacciones_dispositivo', 'user_id'],
  ['conversation_deletions', 'user_id'],
  ['verificaciones', 'usuario_id'],
  ['wanted_posts', 'user_id'],
  ['wanted_posts', 'resolved_with_user_id'],
  ['orders', 'buyer_id'],
  ['orders', 'vendor_id'],
  ['saved_cards', 'seller_id'],
  ['saved_cards', 'vendor_id'],
  ['buyer_mp_customers', 'seller_id'],
  ['buyer_mp_customers', 'vendor_id'],
  ['payment_oauth_states', 'seller_id'],
  ['vendor_payment_accounts', 'seller_id'],
];

/** ¿Existe la tabla? El esquema creció por migraciones y no toda base las
 *  tiene todas; una tabla ausente no es un error, es una versión distinta. */
const tablas = new Set(
  conexion
    .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
    .all()
    .map(f => f.name),
);

function existe(tabla, columna) {
  if (!tablas.has(tabla)) return false;
  return conexion
    .prepare(`PRAGMA table_info(${tabla})`)
    .all()
    .some(c => c.name === columna);
}

function contar(sql, params) {
  return conexion.prepare(`SELECT COUNT(*) AS n FROM ${sql}`).get(...params).n;
}

// ─── Resolver las cuentas ──────────────────────────────────────────────

const marcadores = correos.map(() => '?').join(', ');
const cuentas = conexion
  .prepare(
    `SELECT id, name, email FROM sellers
      WHERE lower(trim(email)) IN (${marcadores})`,
  )
  .all(...correos);

const noEncontrados = correos.filter(
  c => !cuentas.some(u => (u.email || '').trim().toLowerCase() === c),
);
for (const correo of noEncontrados) {
  console.log(`⚠️  Sin cuenta para ${correo} — se ignora.`);
}
if (cuentas.length === 0) {
  console.log('Nada que borrar.');
  process.exit(0);
}

const ids = cuentas.map(u => u.id);
const idsMarcadores = ids.map(() => '?').join(', ');
const subProductos = `SELECT id FROM products WHERE seller IN (${idsMarcadores})`;
const subConversaciones = `SELECT id FROM conversations WHERE buyer_id IN (${idsMarcadores}) OR seller_id IN (${idsMarcadores})`;

// ─── Plan: cada paso sabe contarse y ejecutarse ────────────────────────

const pasos = [];

for (const [tabla, columna] of POR_PRODUCTO) {
  if (!existe(tabla, columna)) continue;
  pasos.push({
    etiqueta: `${tabla}.${columna} (de sus productos)`,
    sql: `${tabla} WHERE ${columna} IN (${subProductos})`,
    params: ids,
  });
}
for (const [tabla, columna] of POR_CONVERSACION) {
  if (!existe(tabla, columna)) continue;
  pasos.push({
    etiqueta: `${tabla}.${columna} (de sus conversaciones)`,
    sql: `${tabla} WHERE ${columna} IN (${subConversaciones})`,
    params: [...ids, ...ids],
  });
}
for (const [tabla, columna] of POR_USUARIO) {
  if (!existe(tabla, columna)) continue;
  pasos.push({
    etiqueta: `${tabla}.${columna}`,
    sql: `${tabla} WHERE ${columna} IN (${idsMarcadores})`,
    params: ids,
  });
}
pasos.push({
  etiqueta: 'conversations (como comprador o vendedor)',
  sql: `conversations WHERE buyer_id IN (${idsMarcadores}) OR seller_id IN (${idsMarcadores})`,
  params: [...ids, ...ids],
});
pasos.push({
  etiqueta: 'products',
  sql: `products WHERE seller IN (${idsMarcadores})`,
  params: ids,
});
pasos.push({
  etiqueta: 'sellers',
  sql: `sellers WHERE id IN (${idsMarcadores})`,
  params: ids,
});

// ─── Informe ───────────────────────────────────────────────────────────

console.log('\nCuentas a eliminar:');
for (const u of cuentas) {
  console.log(`  • ${u.id}  ${u.email}  (${u.name || 'sin nombre'})`);
}

console.log('\nFilas que se borrarán:');
let total = 0;
for (const paso of pasos) {
  const n = contar(paso.sql, paso.params);
  total += n;
  if (n > 0) console.log(`  ${String(n).padStart(5)}  ${paso.etiqueta}`);
}
console.log(`  ${'─'.repeat(5)}\n  ${String(total).padStart(5)}  filas en total\n`);

if (!FORCE) {
  console.log('DRY-RUN: no se escribió nada. Repite con --force para borrar.');
  process.exit(0);
}

// ─── Respaldo y ejecución ──────────────────────────────────────────────

const rutaDb = conexion.name;
const sello = new Date().toISOString().replace(/[:.]/g, '-');
const rutaRespaldo = path.join(
  path.dirname(rutaDb),
  `${path.basename(rutaDb)}.pre-eliminar-cuenta.${sello}.bak`,
);

// `VACUUM INTO` y no copiar el archivo: con WAL activo, un `cp` puede
// llevarse una base a medio checkpoint. Esto produce un archivo consistente.
conexion.prepare('VACUUM INTO ?').run(rutaRespaldo);
console.log(`Respaldo: ${rutaRespaldo} (${fs.statSync(rutaRespaldo).size} bytes)`);

const borrar = conexion.transaction(() => {
  for (const paso of pasos) {
    const res = conexion.prepare(`DELETE FROM ${paso.sql}`).run(...paso.params);
    if (res.changes > 0) {
      console.log(`  -${String(res.changes).padStart(4)}  ${paso.etiqueta}`);
    }
  }
});
borrar();

console.log('\n✅ Listo. Reinicia el backend para que suelte los vendedores que');
console.log('   tiene en memoria:  pm2 restart mercadito-backend');
