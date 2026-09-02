// Los requisitos que una cuenta debe cumplir para quedar verificada.
//
// El validador es la única fuente de esta regla: lo consumen el cierre de la
// verificación, el cierre automático al conectar Mercado Pago y el endpoint
// que pinta el checklist en la app. Si cada uno tuviera su propia versión,
// el checklist diría "todo listo" mientras el backend sigue rechazando.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-requisitos-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.PAYMENTS_ENCRYPTION_KEY = crypto.randomBytes(32).toString('hex');
// La mayoría de este archivo prueba la validación ORIGINAL del requisito de
// Mercado Pago, que solo aplica con el flag encendido (ver
// payments/config.js#mercadoPagoHabilitado). El caso de "flag apagado" tiene
// su propio test más abajo, que lo apaga puntualmente.
process.env.MERCADO_PAGO_HABILITADO = 'true';

const db = require('../database');
db.initDatabase();

const store = require('../payments/store');
const {
  requisitosDeVerificacion,
  cumpleTodos,
  primerFaltante,
} = require('./requisitosVerificacion');

const HORARIO_VALIDO = JSON.stringify({
  '0': { open: '09:00', close: '18:00' },
  '1': { open: '09:00', close: '18:00' },
});

let n = 0;

/** Crea un vendedor. Por defecto cumple TODO menos lo que se le quite. */
function crearVendedor({
  horario = HORARIO_VALIDO,
  metodos = ['efectivo'],
  conectarMp = false,
  esNegocio = true,
  logoUrl = '/uploads/logo-test.webp',
  avatarUrl = null,
} = {}) {
  const id = `u_req_${++n}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness,
       verified, tipo_cuenta, businessHours, paymentMethods, logoUrl, avatarUrl)
     VALUES (?, ?, ?, 'TT', '', ?, 0, ?, ?, ?, ?, ?)`,
  ).run(id, `Test ${id}`, `${id}@x.com`, esNegocio ? 1 : 0,
    esNegocio ? 'negocio' : 'estudiante', horario,
    metodos === null ? null : JSON.stringify(metodos), logoUrl, avatarUrl);

  if (conectarMp) {
    store.guardarCuentaVendedor(id, {
      mpUserId: `mp_${id}`,
      accessToken: 'tok',
      refreshToken: 'ref',
      expiresIn: 3600,
      publicKey: 'APP_USR-pk',
    });
  }
  return id;
}

function crearProducto(sellerId, { stock = 5 } = {}) {
  const id = `p_req_${++n}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category, stock_quantity)
     VALUES (?, ?, '100', 100, ?, 'otros', ?)`,
  ).run(id, `Producto ${id}`, sellerId, stock);
  return id;
}

const req = (id, lista) => lista.find(r => r.id === id);

// ─── Happy path ─────────────────────────────────────────────────

test('un vendedor que cumple todo pasa los cuatro requisitos', () => {
  const v = crearVendedor();
  crearProducto(v);

  const lista = requisitosDeVerificacion(v);

  assert.strictEqual(lista.length, 4, 'son cuatro requisitos, ni más ni menos');
  assert.ok(lista.every(r => r.cumplido), JSON.stringify(lista, null, 2));
  assert.strictEqual(cumpleTodos(v), true);
  assert.strictEqual(primerFaltante(v), null);
});

test('sin productos publicados el requisito de stock se da por cumplido', () => {
  // No tener nada publicado no es un incumplimiento: es no haber empezado.
  const v = crearVendedor();
  assert.strictEqual(req('stock_productos', requisitosDeVerificacion(v)).cumplido, true);
});

// ─── Horario ────────────────────────────────────────────────────

test('sin horario configurado no se puede verificar', () => {
  const v = crearVendedor({ horario: null });
  const r = req('horario', requisitosDeVerificacion(v));

  assert.strictEqual(r.cumplido, false);
  assert.ok(r.detalle, 'tiene que decir qué falta');
  assert.strictEqual(r.accion, 'editar_perfil', 'la app usa esto para navegar');
  assert.strictEqual(cumpleTodos(v), false);
});

test('un horario vacío tampoco cuenta como configurado', () => {
  const v = crearVendedor({ horario: '{}' });
  assert.strictEqual(req('horario', requisitosDeVerificacion(v)).cumplido, false);
});

test('un horario corrupto se trata como ausente, no revienta', () => {
  const v = crearVendedor({ horario: 'no-es-json' });
  assert.strictEqual(req('horario', requisitosDeVerificacion(v)).cumplido, false);
});

test('basta un solo día configurado', () => {
  const v = crearVendedor({
    horario: JSON.stringify({ '2': { open: '08:00', close: '14:00' } }),
  });
  assert.strictEqual(req('horario', requisitosDeVerificacion(v)).cumplido, true);
});

test('a quien no es negocio no se le exige horario: no puede guardarlo', () => {
  // routes/sellers.js solo persiste `businessHours` cuando el vendedor es
  // negocio. Exigírselo a un alumno o a una cuenta externa era pedirles algo
  // imposible: el requisito quedaba en ✗ para siempre y el botón de enviar
  // el código, apagado para siempre.
  const v = crearVendedor({ esNegocio: false, horario: null });

  assert.strictEqual(req('horario', requisitosDeVerificacion(v)).cumplido, true);
  assert.strictEqual(cumpleTodos(v), true, 'un alumno sin horario sí se verifica');
});

test('el horario sigue siendo obligatorio para el negocio', () => {
  const v = crearVendedor({ esNegocio: true, horario: null });
  assert.strictEqual(req('horario', requisitosDeVerificacion(v)).cumplido, false);
  assert.strictEqual(cumpleTodos(v), false);
});

test('quien no es negocio y sí configuró horario también cumple', () => {
  const v = crearVendedor({ esNegocio: false });
  assert.strictEqual(req('horario', requisitosDeVerificacion(v)).cumplido, true);
});

test('basta con que UNA de las dos columnas diga negocio para exigir horario', () => {
  // tipo_cuenta es la canónica y isBusiness la anterior. Si divergen (filas
  // viejas, migraciones a medias), el requisito se queda del lado estricto:
  // pedir el horario de más es barato; dejar verificar a un negocio sin
  // horario publicado, no.
  const id = 'u_req_divergente';
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, isBusiness,
       verified, tipo_cuenta, businessHours, paymentMethods)
     VALUES (?, 'Divergente', 'div@x.com', 'TT', '', 0, 0, 'negocio', NULL, ?)`,
  ).run(id, JSON.stringify(['efectivo']));

  assert.strictEqual(req('horario', requisitosDeVerificacion(id)).cumplido, false);
});

test('el requisito de horario se sigue listando para todos, cumplido o no', () => {
  // No se oculta: el checklist tiene el mismo largo para las tres cuentas,
  // así nadie ve aparecer un requisito nuevo al cambiar de tipo.
  const alumno = crearVendedor({ esNegocio: false, horario: null });
  assert.strictEqual(requisitosDeVerificacion(alumno).length, 4);
  assert.ok(req('horario', requisitosDeVerificacion(alumno)));
});

// ─── Métodos de pago ────────────────────────────────────────────

test('sin ningún método de pago no se puede verificar', () => {
  const v = crearVendedor({ metodos: null });
  assert.strictEqual(req('metodos_pago', requisitosDeVerificacion(v)).cumplido, false);
});

test('una lista vacía de métodos tampoco vale', () => {
  const v = crearVendedor({ metodos: [] });
  assert.strictEqual(req('metodos_pago', requisitosDeVerificacion(v)).cumplido, false);
});

// ─── Mercado Pago: solo si acepta tarjeta ───────────────────────

test('quien NO acepta tarjeta se verifica sin conectar Mercado Pago', () => {
  const v = crearVendedor({ metodos: ['efectivo'], conectarMp: false });
  crearProducto(v);

  const r = req('mercadopago', requisitosDeVerificacion(v));
  assert.strictEqual(r.cumplido, true,
    'exigirle una cuenta de cobros a quien solo acepta efectivo no tiene sentido');
  assert.strictEqual(cumpleTodos(v), true);
});

test('quien acepta tarjeta SIN conectar Mercado Pago no se verifica', () => {
  const v = crearVendedor({ metodos: ['efectivo', 'tarjeta'], conectarMp: false });

  const r = req('mercadopago', requisitosDeVerificacion(v));
  assert.strictEqual(r.cumplido, false);
  assert.strictEqual(r.accion, 'conectar_mercadopago');
});

test('quien acepta tarjeta y conectó Mercado Pago sí cumple', () => {
  const v = crearVendedor({ metodos: ['tarjeta'], conectarMp: true });
  assert.strictEqual(req('mercadopago', requisitosDeVerificacion(v)).cumplido, true);
});

test('desconectarse vuelve a incumplir el requisito', () => {
  const v = crearVendedor({ metodos: ['tarjeta'], conectarMp: true });
  store.desconectarVendedor(v, { motivo: 'prueba', por: 'user' });
  assert.strictEqual(req('mercadopago', requisitosDeVerificacion(v)).cumplido, false);
});

test('con MERCADO_PAGO_HABILITADO=false nadie queda bloqueado por no conectar, ni siquiera aceptando tarjeta', () => {
  const anterior = process.env.MERCADO_PAGO_HABILITADO;
  process.env.MERCADO_PAGO_HABILITADO = 'false';
  try {
    const v = crearVendedor({ metodos: ['efectivo', 'tarjeta'], conectarMp: false });
    crearProducto(v);

    const r = req('mercadopago', requisitosDeVerificacion(v));
    assert.strictEqual(r.cumplido, true,
      'con el flag apagado el requisito de cuenta de cobros se da por cumplido');
    assert.strictEqual(cumpleTodos(v), true);
  } finally {
    process.env.MERCADO_PAGO_HABILITADO = anterior;
  }
});

// ─── Stock ──────────────────────────────────────────────────────

test('un producto sin stock definido bloquea la verificación', () => {
  const v = crearVendedor();
  crearProducto(v, { stock: null });

  const r = req('stock_productos', requisitosDeVerificacion(v));
  assert.strictEqual(r.cumplido, false);
  assert.strictEqual(r.accion, 'revisar_productos');
});

test('el requisito nombra los productos concretos que faltan', () => {
  const v = crearVendedor();
  const p1 = crearProducto(v, { stock: null });
  const p2 = crearProducto(v, { stock: null });
  crearProducto(v, { stock: 3 });

  const r = req('stock_productos', requisitosDeVerificacion(v));
  assert.strictEqual(r.productos.length, 2,
    'decir "algún producto" obliga a revisarlos todos a mano');
  assert.deepStrictEqual(r.productos.map(p => p.id).sort(), [p1, p2].sort());
  assert.ok(r.productos.every(p => p.title), 'la app pinta el título, no el id');
});

test('stock 0 cuenta como definido: agotado es una respuesta', () => {
  const v = crearVendedor();
  crearProducto(v, { stock: 0 });
  assert.strictEqual(req('stock_productos', requisitosDeVerificacion(v)).cumplido, true);
});

test('un producto pausado o vendido no bloquea: ya no está a la venta', () => {
  const v = crearVendedor();
  const p = crearProducto(v, { stock: null });
  db.getDb().prepare('UPDATE products SET manual_status = ? WHERE id = ?').run('paused', p);

  assert.strictEqual(req('stock_productos', requisitosDeVerificacion(v)).cumplido, true);
});

// ─── Mensaje al usuario ─────────────────────────────────────────

test('primerFaltante devuelve el requisito incumplido, con su mensaje', () => {
  const v = crearVendedor({ horario: null });
  const falta = primerFaltante(v);

  assert.strictEqual(falta.id, 'horario');
  assert.ok(falta.detalle);
  assert.ok(falta.titulo);
});

test('el orden es estable: siempre se pide lo mismo primero', () => {
  // Si el orden bailara, alguien que arregla lo que se le pide vería
  // aparecer otro requisito distinto cada vez, sin saber cuántos faltan.
  const v = crearVendedor({ horario: null, metodos: null });
  assert.deepStrictEqual(
    requisitosDeVerificacion(v).map(r => r.id),
    ['horario', 'metodos_pago', 'mercadopago', 'stock_productos'],
  );
});

test('un vendedor que no existe no cumple nada y no revienta', () => {
  const lista = requisitosDeVerificacion('u_fantasma');
  assert.strictEqual(lista.length, 4);
  assert.ok(lista.some(r => !r.cumplido));
  assert.strictEqual(cumpleTodos('u_fantasma'), false);
});
