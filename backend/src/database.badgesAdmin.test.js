// Cuentas del dueño: todas las insignias desbloqueadas, siempre.
//
// El primer intento comparaba `sellers.email` contra
// '1220326@alumno.um.edu.mx' y por eso NUNCA se activó: ese correo es el
// institucional, y el flujo de verificación no lo escribe en `sellers.email`
// (ahí vive el correo de Google con el que se inicia sesión). El
// institucional se guarda en `verificaciones.correo_institucional`, así que
// la condición era falsa para todas las filas de la base.
//
// Estos tests fijan las dos formas de reconocer la cuenta —por correo de
// login y por correo institucional verificado— y que el reconocimiento llegue
// a los cuatro sitios que arman el objeto del autor, no solo a `rowToSeller`.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-badges-')),
  'test.db',
);

const db = require('./database');

db.initDatabase();

let contador = 0;

function crearUsuario(email) {
  const id = `u_badges_${++contador}`;
  // `sellers.email` es UNIQUE y varios casos usan el mismo correo de dueño,
  // así que cada uno estrena fila en vez de chocar con la del anterior.
  db.getDb()
    .prepare('DELETE FROM sellers WHERE lower(trim(email)) = lower(trim(?))')
    .run(email);
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness, verified, socio_fundador, tipo_cuenta)
       VALUES (?, ?, ?, 'TT', '', 0, 0, 0, 'estudiante')`,
    )
    .run(id, `Test ${id}`, email);
  return id;
}

function verificarCon(usuarioId, correoInstitucional, estado = 'verificado') {
  db.getDb()
    .prepare(
      `INSERT INTO verificaciones (usuario_id, tipo_cuenta, estado, correo_institucional, creado_en)
       VALUES (?, 'estudiante', ?, ?, datetime('now'))`,
    )
    .run(usuarioId, estado, correoInstitucional);
  db.refrescarCuentasDueno();
}

function seller(id) {
  return db.rowToSeller(
    db.getDb().prepare('SELECT * FROM sellers WHERE id = ?').get(id),
  );
}

// ═══ Reconocimiento de la cuenta ═════════════════════════════

test('se reconoce por el correo de login de Google', () => {
  const id = crearUsuario('cesar8herrera@gmail.com');
  db.refrescarCuentasDueno();

  assert.strictEqual(db.esUsuarioTodosLosBadges(id), true);
});

test('se reconoce por el correo institucional verificado', () => {
  // El caso que el primer intento no cubría: quien entra con Google tiene un
  // `sellers.email` que NO es el institucional.
  const id = crearUsuario('otro-correo-cualquiera@gmail.com');
  verificarCon(id, '1220326@alumno.um.edu.mx');

  assert.strictEqual(db.esUsuarioTodosLosBadges(id), true);
});

test('una verificación pendiente con ese correo no basta', () => {
  // Si bastara con la fila, cualquiera podría pedir la verificación con ese
  // correo y llevarse los badges mientras el trámite sigue abierto.
  const id = crearUsuario('impostor@gmail.com');
  verificarCon(id, '1220326@alumno.um.edu.mx', 'pendiente');

  assert.strictEqual(db.esUsuarioTodosLosBadges(id), false);
});

test('el correo se compara sin distinguir mayúsculas ni espacios', () => {
  const id = crearUsuario('  CESAR4Herrera@Gmail.COM  ');
  db.refrescarCuentasDueno();

  assert.strictEqual(db.esUsuarioTodosLosBadges(id), true);
});

test('una cuenta cualquiera no se lleva nada', () => {
  const id = crearUsuario('alguien@gmail.com');
  db.refrescarCuentasDueno();

  assert.strictEqual(db.esUsuarioTodosLosBadges(id), false);
  assert.strictEqual(seller(id).verified, false);
  assert.strictEqual(seller(id).socioFundador, false);
});

// ═══ Que llegue a todos los sitios que pintan insignias ══════

test('rowToSeller da verificado y socio fundador aunque la fila diga 0', () => {
  const id = crearUsuario('cesar8herrera@gmail.com');
  db.refrescarCuentasDueno();

  const s = seller(id);
  assert.strictEqual(s.verified, true);
  assert.strictEqual(s.socioFundador, true);
});

test('revocar la verificación en la fila no se las quita', () => {
  // El punto de que sea hardcodeado: ningún flujo normal puede apagarlo.
  const id = crearUsuario('cesar8herrera@gmail.com');
  db.refrescarCuentasDueno();
  db.getDb()
    .prepare('UPDATE sellers SET verified = 0, socio_fundador = 0 WHERE id = ?')
    .run(id);

  assert.strictEqual(seller(id).verified, true);
});

function crearProducto(duenoId) {
  const id = `p_badges_${++contador}`;
  db.getDb()
    .prepare('INSERT INTO products (id, title, price, seller) VALUES (?, ?, ?, ?)')
    .run(id, 'Bici', '100', duenoId);
  return id;
}

test('el autor de un comentario también sale con las insignias', () => {
  // `rowToProductComment` arma el autor a mano desde el JOIN, sin pasar por
  // `rowToSeller`: si la regla vive solo ahí, el comentario sale sin palomita.
  const autorId = crearUsuario('cesar8herrera@gmail.com');
  db.refrescarCuentasDueno();
  const productoId = crearProducto(autorId);

  const comentario = db.createProductComment(
    `c_badges_${++contador}`,
    productoId,
    autorId,
    'Un comentario',
  );

  assert.strictEqual(comentario.author.verified, true);
  assert.strictEqual(comentario.author.socioFundador, true);
});

test('el autor de una pregunta también sale con las insignias', () => {
  const vendedorId = crearUsuario('vendedor-cualquiera@gmail.com');
  const autorId = crearUsuario('cesar4herrera@gmail.com');
  db.refrescarCuentasDueno();
  const productoId = crearProducto(vendedorId);

  const pregunta = db.createProductQuestion(
    `q_badges_${++contador}`,
    productoId,
    vendedorId,
    autorId,
    '¿Sigue disponible?',
  );

  assert.strictEqual(pregunta.author.verified, true);
  assert.strictEqual(pregunta.author.socioFundador, true);
});
