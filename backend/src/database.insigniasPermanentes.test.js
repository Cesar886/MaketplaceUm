// Rescate de las insignias ya ganadas cuando sube un umbral.
//
// "Leyenda del Mercadito" pasó de 50 a 100 ventas confirmadas. La insignia
// se calcula al vuelo en cada carga del perfil, así que sin el registro de
// concesiones el cambio se la habría quitado a todo el que la tuviera entre
// 50 y 99 ventas. La migración que la rescata tiene que correr UNA sola vez:
// lo que se prueba aquí es que rescata a quien ya la tenía y que no sigue
// condecorando a quien llegue después.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-insignias-perm-')),
  'test.db',
);

const db = require('./database');

db.initDatabase();

let contador = 0;

function vendedorCon(ventas) {
  const id = `seller_perm_${++contador}`;
  db.getDb()
    .prepare(
      `INSERT INTO sellers (id, name, avatarInitials, major, isBusiness, verified)
       VALUES (?, ?, 'PP', '', 0, 1)`,
    )
    .run(id, `Perm ${id}`);
  const stmt = db.getDb().prepare(
    `INSERT INTO orders (id, buyer_id, vendor_id, amount, status)
     VALUES (?, ?, ?, 100, 'paid')`,
  );
  for (let i = 0; i < ventas; i++) stmt.run(`ordp_${id}_${i}`, id, id);
  return id;
}

/** Simula una base anterior a este cambio: sin la tabla de concesiones. */
function volverAMigrar() {
  db.getDb().exec('DROP TABLE IF EXISTS insignias_otorgadas');
  db.initDatabase();
}

test('rescata a quien tenía la Leyenda con el umbral viejo', () => {
  const conLaVieja = vendedorCon(60);
  const sinElla = vendedorCon(49);

  volverAMigrar();

  assert.strictEqual(db.getInsigniasOtorgadas(conLaVieja).has('leyenda'), true);
  assert.strictEqual(db.getInsigniasOtorgadas(sinElla).has('leyenda'), false);
});

test('no sigue condecorando a quien llegue a 50 ventas después', () => {
  // La tabla ya existe, así que el rescate no vuelve a correr: con el umbral
  // nuevo, 60 ventas ya no son una Leyenda para nadie más.
  const tardio = vendedorCon(60);

  db.initDatabase();

  assert.strictEqual(db.getInsigniasOtorgadas(tardio).has('leyenda'), false);
});

test('el rescate cubre también las otras dos de por vida', () => {
  // Oro y Centenario no cambiaron de umbral hoy, pero se siembran igual para
  // que el día que se muevan no haga falta otra migración de rescate.
  const conOro = vendedorCon(1000); // 1000 × $100 = $100,000 facturados

  volverAMigrar();

  assert.strictEqual(
    db.getInsigniasOtorgadas(conOro).has('vendedor_de_oro'),
    true,
  );
});

test('registrarInsigniaOtorgada es idempotente', () => {
  const id = vendedorCon(0);

  db.registrarInsigniaOtorgada(id, 'leyenda');
  db.registrarInsigniaOtorgada(id, 'leyenda');

  assert.strictEqual(db.getInsigniasOtorgadas(id).size, 1);
});
