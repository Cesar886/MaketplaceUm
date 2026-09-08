// Tests de las dos consultas que alimentan las secciones nuevas del detalle
// de producto: "También te puede interesar" y "Más de este vendedor".
//
// Lo que de verdad se puede romper en silencio aquí:
//
//  1. Las exclusiones. Un producto del MISMO vendedor colado en
//     `relatedProducts` no rompe nada: simplemente aparece dos veces en la
//     pantalla, una en cada carrusel. Igual el producto actual recomendándose
//     a sí mismo.
//  2. El orden por tramos. Primero misma categoría, y solo si falta cupo,
//     coincidencia de palabras del título. Si el tramo se invirtiera, la
//     sección seguiría llena y con productos plausibles — solo que peores.
//  3. La prioridad de disponibilidad. Un producto vendido o pausado no debe
//     desplazar a uno disponible igual de relevante, pero tampoco hay que
//     esconderlo del todo: si no hay cupo suficiente de disponibles, debe
//     aparecer como relleno, siempre después de todos los disponibles.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Debe fijarse antes de requerir database.js: la ruta se resuelve al importar.
process.env.MERCADITO_DB_PATH = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), 'mercadito-related-')),
  'test.db',
);

const db = require('./database');
db.initDatabase();
const raw = db.getDb();

let contador = 0;

/**
 * Inserta un producto. `diasAtras` controla la recencia, que es lo que
 * ordena dentro de cada tramo cuando no hay interacciones.
 */
function sembrarProducto({
  id,
  title,
  category = 'cat_libros',
  seller = 's_otro',
  diasAtras = 0,
  manualStatus = null,
  status = null,
  stock = null,
} = {}) {
  const n = ++contador;
  id = id || `p_${n}`;
  // Título único y sin palabras compartidas con los demás: si todos se
  // llamaran "Producto N", el tramo de keywords los emparejaría entre sí y
  // los tests de categoría y de orden estarían midiendo otra cosa.
  title = title || `Xilofono${n}`;

  // Las consultas públicas descartan publicaciones huérfanas y cuentas
  // restringidas. Cada fixture debe representar un vendedor real activo.
  raw.prepare(`
    INSERT OR IGNORE INTO sellers (id, name, avatarInitials, admin_status)
    VALUES (?, ?, 'TP', 'active')
  `).run(seller, `Test ${seller}`);

  raw.prepare(`
    INSERT INTO products (id, title, price, priceNum, category, description, seller,
                          created_at, manual_status, status, stock_quantity)
    VALUES (@id, @title, '100', 100, @category, 'desc', @seller,
            datetime('now', '-' || @diasAtras || ' days'), @manualStatus, @status, @stock)
  `).run({ id, title, category, seller, diasAtras, manualStatus, status, stock });
  return { id, title, category, seller };
}

function ids(productos) {
  return productos.map(p => p.id);
}

// ═══ relatedProducts ═════════════════════════════════════════

test('trae productos de la misma categoría, sin el actual ni los del mismo vendedor', () => {
  const actual = sembrarProducto({ id: 'r1_actual', seller: 's_yo', category: 'cat_r1' });
  const mismoVendedor = sembrarProducto({ id: 'r1_mio', seller: 's_yo', category: 'cat_r1' });
  const otro = sembrarProducto({ id: 'r1_otro', seller: 's_ajeno', category: 'cat_r1' });
  const otraCategoria = sembrarProducto({ id: 'r1_lejano', seller: 's_ajeno', category: 'cat_r1_otra' });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.ok(relacionados.includes(otro.id), 'falta el producto de la misma categoría');
  assert.ok(!relacionados.includes(actual.id), 'el producto se recomienda a sí mismo');
  assert.ok(!relacionados.includes(mismoVendedor.id), 'se coló un producto del mismo vendedor');
  assert.ok(!relacionados.includes(otraCategoria.id), 'se coló uno sin relación alguna');
});

test('si falta cupo, completa con coincidencia de palabras del título', () => {
  const actual = sembrarProducto({
    id: 'r2_actual',
    title: 'Calculadora científica Casio',
    category: 'cat_r2',
    seller: 's_yo',
  });
  const mismaCategoria = sembrarProducto({ id: 'r2_cat', category: 'cat_r2', seller: 's_a' });
  const porTitulo = sembrarProducto({
    id: 'r2_titulo',
    title: 'Calculadora gráfica seminueva',
    category: 'cat_r2_distinta',
    seller: 's_b',
  });
  const sinRelacion = sembrarProducto({
    id: 'r2_nada',
    title: 'Bicicleta de montaña',
    category: 'cat_r2_distinta',
    seller: 's_c',
  });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.deepStrictEqual(
    relacionados,
    [mismaCategoria.id, porTitulo.id],
    'la misma categoría va primero y el match por título después',
  );
  assert.ok(!relacionados.includes(sinRelacion.id));
});

test('las palabras cortas del título no arrastran productos sin relación', () => {
  // "de", "la", "un" aparecen en medio catálogo: si contaran como keyword,
  // la sección se llenaría de ruido en cuanto la categoría no diera cupo.
  const actual = sembrarProducto({
    id: 'r3_actual',
    title: 'Mesa de la sala',
    category: 'cat_r3',
    seller: 's_yo',
  });
  sembrarProducto({ id: 'r3_ruido', title: 'Zapatos de la playa', category: 'cat_r3_otra', seller: 's_x' });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.deepStrictEqual(relacionados, []);
});

test('dentro del mismo tramo, lo más reciente va primero', () => {
  const actual = sembrarProducto({ id: 'r4_actual', category: 'cat_r4', seller: 's_yo' });
  const viejo = sembrarProducto({ id: 'r4_viejo', category: 'cat_r4', seller: 's_a', diasAtras: 40 });
  const nuevo = sembrarProducto({ id: 'r4_nuevo', category: 'cat_r4', seller: 's_b', diasAtras: 0 });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.deepStrictEqual(relacionados, [nuevo.id, viejo.id]);
});

test('un producto con interacciones le gana a uno igual de reciente sin ellas', () => {
  const actual = sembrarProducto({ id: 'r5_actual', category: 'cat_r5', seller: 's_yo' });
  const frio = sembrarProducto({ id: 'r5_frio', category: 'cat_r5', seller: 's_a' });
  const caliente = sembrarProducto({ id: 'r5_caliente', category: 'cat_r5', seller: 's_b' });

  for (let i = 0; i < 5; i++) {
    db.registrarInteraccion({
      deviceId: `d_${i}`,
      userId: null,
      productId: caliente.id,
      category: 'cat_r5',
      tipo: 'contacto',
    });
  }

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.deepStrictEqual(relacionados, [caliente.id, frio.id]);
});

test('vendidos, pausados y agotados solo aparecen como relleno, después de todos los disponibles', () => {
  const actual = sembrarProducto({ id: 'r6_actual', category: 'cat_r6', seller: 's_yo' });
  // diasAtras distinto para que el orden dentro de "no disponibles" sea
  // determinista (el más reciente primero, igual que el resto de la sección).
  const vendido = sembrarProducto({
    id: 'r6_vendido', category: 'cat_r6', seller: 's_a', manualStatus: 'sold', diasAtras: 3,
  });
  const pausado = sembrarProducto({
    id: 'r6_pausado', category: 'cat_r6', seller: 's_b', manualStatus: 'paused', diasAtras: 2,
  });
  const agotado = sembrarProducto({
    id: 'r6_agotado', category: 'cat_r6', seller: 's_c', stock: 0, diasAtras: 1,
  });
  const vivo = sembrarProducto({ id: 'r6_vivo', category: 'cat_r6', seller: 's_d', stock: 3, diasAtras: 0 });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.deepStrictEqual(relacionados, [vivo.id, agotado.id, pausado.id, vendido.id]);
});

test('si los disponibles ya llenan el cupo, ningún no disponible entra', () => {
  const actual = sembrarProducto({ id: 'r6b_actual', category: 'cat_r6b', seller: 's_yo' });
  sembrarProducto({ id: 'r6b_vendido', category: 'cat_r6b', seller: 's_a', manualStatus: 'sold' });
  const disp1 = sembrarProducto({ id: 'r6b_disp1', category: 'cat_r6b', seller: 's_b', diasAtras: 1 });
  const disp2 = sembrarProducto({ id: 'r6b_disp2', category: 'cat_r6b', seller: 's_c', diasAtras: 0 });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 2 }));

  assert.deepStrictEqual(relacionados, [disp2.id, disp1.id]);
});

test('el relleno de no disponibles respeta el mismo criterio de relación (categoría antes que keyword)', () => {
  // Título único en todo el archivo: la base se comparte entre tests, así
  // que reusar palabras de otro test filtraría productos ajenos por keyword.
  const actual = sembrarProducto({
    id: 'r6c_actual', title: 'Termo acampar reforzado', category: 'cat_r6c', seller: 's_yo',
  });
  const disponibleCategoria = sembrarProducto({
    id: 'r6c_disp', category: 'cat_r6c', seller: 's_a',
  });
  const noDisponibleCategoria = sembrarProducto({
    id: 'r6c_nodisp_cat', category: 'cat_r6c', seller: 's_b', manualStatus: 'sold',
  });
  const noDisponiblePorTitulo = sembrarProducto({
    id: 'r6c_nodisp_titulo', title: 'Termo acampar plegable', category: 'cat_r6c_otra',
    seller: 's_c', manualStatus: 'paused',
  });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 3 }));

  assert.deepStrictEqual(
    relacionados,
    [disponibleCategoria.id, noDisponibleCategoria.id, noDisponiblePorTitulo.id],
    'disponible primero; entre los no disponibles, misma categoría antes que match por título',
  );
});

test('apartado y en negociación sí se recomiendan: siguen a la venta', () => {
  const actual = sembrarProducto({ id: 'r7_actual', category: 'cat_r7', seller: 's_yo' });
  sembrarProducto({ id: 'r7_apartado', category: 'cat_r7', seller: 's_a', manualStatus: 'reserved' });
  sembrarProducto({ id: 'r7_negociando', category: 'cat_r7', seller: 's_b', manualStatus: 'negotiating' });

  const relacionados = ids(db.getRelatedProducts(actual, { limit: 10 }));

  assert.strictEqual(relacionados.length, 2);
});

test('respeta el límite', () => {
  const actual = sembrarProducto({ id: 'r8_actual', category: 'cat_r8', seller: 's_yo' });
  for (let i = 0; i < 15; i++) {
    sembrarProducto({ id: `r8_${i}`, category: 'cat_r8', seller: `s_${i}` });
  }

  assert.strictEqual(db.getRelatedProducts(actual, { limit: 10 }).length, 10);
  assert.strictEqual(db.getRelatedProducts(actual, { limit: 3 }).length, 3);
});

test('sin nada relacionado devuelve un array vacío, no null', () => {
  const actual = sembrarProducto({ id: 'r9_actual', category: 'cat_r9_sola', seller: 's_yo' });

  const relacionados = db.getRelatedProducts(actual, { limit: 10 });

  assert.deepStrictEqual(relacionados, []);
});

test('devuelve productos ya normalizados, no filas crudas de SQLite', () => {
  const actual = sembrarProducto({ id: 'r10_actual', category: 'cat_r10', seller: 's_yo' });
  sembrarProducto({ id: 'r10_otro', category: 'cat_r10', seller: 's_a' });

  const [relacionado] = db.getRelatedProducts(actual, { limit: 10 });

  // rowToProduct: images/extras parseados y precio numérico. Es lo que
  // attachRelations espera recibir para dejar el shape del feed.
  assert.ok(Array.isArray(relacionado.images));
  assert.ok(Array.isArray(relacionado.extras));
  assert.strictEqual(typeof relacionado.price, 'number');
});

// ═══ sellerOtherProducts ═════════════════════════════════════

test('trae los otros productos del vendedor, del más reciente al más viejo', () => {
  const actual = sembrarProducto({ id: 'v1_actual', seller: 's_v1' });
  const viejo = sembrarProducto({ id: 'v1_viejo', seller: 's_v1', diasAtras: 30 });
  const nuevo = sembrarProducto({ id: 'v1_nuevo', seller: 's_v1', diasAtras: 1 });
  const ajeno = sembrarProducto({ id: 'v1_ajeno', seller: 's_v1_otro' });

  const otros = ids(db.getSellerOtherProducts('s_v1', { excludeProductId: actual.id, limit: 10 }));

  assert.deepStrictEqual(otros, [nuevo.id, viejo.id]);
  assert.ok(!otros.includes(ajeno.id));
});

test('no incluye vendidos, pausados ni agotados del vendedor', () => {
  const actual = sembrarProducto({ id: 'v2_actual', seller: 's_v2' });
  sembrarProducto({ id: 'v2_vendido', seller: 's_v2', manualStatus: 'sold' });
  sembrarProducto({ id: 'v2_agotado', seller: 's_v2', stock: 0 });
  const vivo = sembrarProducto({ id: 'v2_vivo', seller: 's_v2' });

  const otros = ids(db.getSellerOtherProducts('s_v2', { excludeProductId: actual.id, limit: 10 }));

  assert.deepStrictEqual(otros, [vivo.id]);
});

test('un vendedor con una sola publicación devuelve array vacío', () => {
  const actual = sembrarProducto({ id: 'v3_actual', seller: 's_v3' });

  const otros = db.getSellerOtherProducts('s_v3', { excludeProductId: actual.id, limit: 10 });

  assert.deepStrictEqual(otros, []);
});

test('sin vendedor no hay sección: array vacío en vez de reventar', () => {
  assert.deepStrictEqual(db.getSellerOtherProducts(null, { excludeProductId: 'x', limit: 10 }), []);
});

test('respeta el límite del vendedor', () => {
  const actual = sembrarProducto({ id: 'v4_actual', seller: 's_v4' });
  for (let i = 0; i < 14; i++) sembrarProducto({ id: `v4_${i}`, seller: 's_v4' });

  assert.strictEqual(
    db.getSellerOtherProducts('s_v4', { excludeProductId: actual.id, limit: 10 }).length,
    10,
  );
});
