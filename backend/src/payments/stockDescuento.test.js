// Descuento de inventario al confirmar un pago.
//
// Va dentro de la misma transacción que marca la orden como pagada, y solo
// en la TRANSICIÓN a 'approved'. Mercado Pago reenvía el mismo webhook varias
// veces y no garantiza el orden: un descuento que se dispare en cada
// notificación deja el inventario en negativo sin que nadie haya comprado
// nada de más.

const test = require('node:test');
const assert = require('node:assert');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-stock-')),
  'test.db',
);
process.env.JWT_SECRET = 'secreto-de-prueba';
process.env.PAYMENTS_ENCRYPTION_KEY = crypto.randomBytes(32).toString('hex');

const db = require('../database');
db.initDatabase();
const store = require('./store');

let n = 0;

function crearVendedor() {
  const id = `u_stk_${++n}`;
  db.getDb().prepare(
    `INSERT INTO sellers (id, name, email, avatarInitials, major, verified)
     VALUES (?, ?, ?, 'TT', '', 1)`,
  ).run(id, `V ${id}`, `${id}@x.com`);
  return id;
}

function crearProducto(sellerId, stock) {
  const id = `p_stk_${++n}`;
  db.getDb().prepare(
    `INSERT INTO products (id, title, price, priceNum, seller, category, stock_quantity)
     VALUES (?, ?, '100', 100, ?, 'otros', ?)`,
  ).run(id, `Prod ${id}`, sellerId, stock);
  return id;
}

const stockDe = (id) => db.getDb()
  .prepare('SELECT stock_quantity FROM products WHERE id = ?').get(id).stock_quantity;

/** Id de pago único: `orders.mp_payment_id` es UNIQUE en toda la tabla. */
const nuevoPago = () => `pay_stk_${++n}`;

function crearOrden(compradorId, vendedorId, items) {
  return store.crearOrden({
    id: `ord_stk_${++n}`,
    buyerId: compradorId,
    vendorId: vendedorId,
    amount: 100,
    applicationFee: 5,
    currency: 'MXN',
    origin: 'direct',
    items,
  });
}

test('un pago aprobado descuenta la cantidad comprada', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, 10);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 3, unitPrice: 100, title: 'X' },
  ]);

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });

  assert.strictEqual(stockDe(p), 7);
});

test('el webhook repetido NO vuelve a descontar', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, 10);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 2, unitPrice: 100, title: 'X' },
  ]);

  // MP reenvía la misma notificación varias veces. Es el caso normal, no
  // el raro: sin la guarda de transición, tres entregas dejan el stock en 4.
  for (let i = 0; i < 3; i++) {
    store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });
  }

  assert.strictEqual(stockDe(p), 8);
});

test('un pago pendiente o rechazado no toca el inventario', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, 5);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 1, unitPrice: 100, title: 'X' },
  ]);

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'in_process' });
  assert.strictEqual(stockDe(p), 5, 'el dinero todavía no llegó');

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'rejected' });
  assert.strictEqual(stockDe(p), 5, 'un rechazo no vendió nada');
});

test('el pendiente que luego se aprueba sí descuenta, una sola vez', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, 5);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 1, unitPrice: 100, title: 'X' },
  ]);

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'in_process' });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });

  assert.strictEqual(stockDe(p), 4);
});

test('el stock nunca baja de cero', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, 1);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 5, unitPrice: 100, title: 'X' },
  ]);

  // No debería poder pasar (el checkout valida antes), pero si pasa, un
  // inventario negativo es peor que uno en cero: rompe todos los cálculos
  // de disponibilidad que asumen >= 0.
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });

  assert.strictEqual(stockDe(p), 0);
});

test('una orden de varios productos los descuenta todos', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p1 = crearProducto(vendedor, 10);
  const p2 = crearProducto(vendedor, 4);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p1, quantity: 2, unitPrice: 100, title: 'A' },
    { productId: p2, quantity: 1, unitPrice: 100, title: 'B' },
  ]);

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });

  assert.strictEqual(stockDe(p1), 8);
  assert.strictEqual(stockDe(p2), 3);
});

test('un producto sin stock definido se salta sin romper el pago', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, null);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 1, unitPrice: 100, title: 'X' },
  ]);

  // Quedan productos viejos con stock NULL. Tumbar el registro de un pago ya
  // cobrado por eso sería mucho peor que no descontar.
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });

  const orden2 = db.getDb().prepare('SELECT * FROM orders WHERE id = ?').get(orden.id);
  assert.strictEqual(orden2.payment_status, 'approved');
  assert.strictEqual(stockDe(p), null);
});

test('un reembolso posterior no vuelve a descontar', () => {
  const pago = nuevoPago();
  const comprador = crearVendedor();
  const vendedor = crearVendedor();
  const p = crearProducto(vendedor, 5);
  const orden = crearOrden(comprador, vendedor, [
    { productId: p, quantity: 2, unitPrice: 100, title: 'X' },
  ]);

  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'approved' });
  store.actualizarPagoDeOrden(orden.id, { mpPaymentId: pago, paymentStatus: 'refunded' });

  assert.strictEqual(stockDe(p), 3);
});
