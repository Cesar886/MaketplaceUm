const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-expiry-')),
  'test.db',
);

const db = require('./database');
db.initDatabase();

test('un producto vencido conserva íntegra su fila', () => {
  db.insertProduct({
    id: 'expired_product',
    title: 'Producto que venció',
    price: 100,
    description: 'Sigue guardado para poder renovarse',
    seller: 'seller_1',
    images: ['/uploads/original.webp'],
    expiresAt: '2020-01-01T00:00:00.000Z',
  });

  const product = db.getProductById('expired_product');
  assert.ok(product, 'vencer no debe borrar la fila');
  assert.equal(product.title, 'Producto que venció');
  assert.deepEqual(product.images, ['/uploads/original.webp']);
  assert.equal(product.expiresAt, '2020-01-01T00:00:00.000Z');
  assert.equal(
    db.getDb().prepare('SELECT COUNT(*) AS count FROM products WHERE id = ?').get(product.id).count,
    1,
  );
});

test('una búsqueda vencida se oculta del feed pero permanece recuperable', () => {
  db.createWantedPost({
    id: 'expired_wanted',
    userId: 'seller_1',
    title: 'Busco calculadora',
    categoryId: 'electronics',
    type: 'producto',
    expiresAt: '2020-01-01T00:00:00.000Z',
  });

  assert.equal(db.listWantedPosts().some(p => p.id === 'expired_wanted'), false);
  assert.equal(db.getWantedPostById('expired_wanted').title, 'Busco calculadora');
});
