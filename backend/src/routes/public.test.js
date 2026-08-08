// Tests de la proyección pública de un producto.
//
// El punto crítico es lo que NO sale: esta respuesta alimenta una página web
// indexable, así que un campo de contacto filtrado ahí convierte el catálogo
// en un directorio de teléfonos raspable. Por eso los tests afirman sobre la
// ausencia de campos, no solo sobre la presencia.

const test = require('node:test');
const assert = require('node:assert');

const { aVistaPublica } = require('./public');

/** Producto completo tal como lo deja `attachRelations`. */
function productoCompleto(extra = {}) {
  return {
    id: 'p_1',
    title: 'Bicicleta de montaña',
    description: 'Poco uso, frenos de disco.',
    price: 2400,
    previousPrice: 3000,
    discountLabel: '-20%',
    images: ['/uploads/a.webp', '/uploads/b.webp'],
    publishedAgo: 'hace 2 días',
    locationLat: 25.18,
    locationLng: -99.82,
    views: 137,
    stock_quantity: 1,
    computed_status: 'available',
    computed_status_detail: null,
    is_available: true,
    categoryObj: { id: 'c_dep', name: 'Deportes', icon: '⚽' },
    sellerObj: {
      id: 's_1',
      name: 'Ana Valdés',
      phone: '+528112345678',
      avatarInitials: 'AV',
      major: 'Estudiante',
      isBusiness: false,
      verified: true,
      tipoCuenta: 'estudiante',
      carrera: 'Ingeniería en Sistemas Computacionales',
      tipoVerificacion: 'estudiante',
      locationLat: 25.18,
      locationLng: -99.82,
    },
    ...extra,
  };
}

test('no expone el teléfono del vendedor por ningún camino', () => {
  const vista = aVistaPublica(productoCompleto());
  const serializado = JSON.stringify(vista);

  assert.ok(!serializado.includes('+528112345678'), 'el teléfono se filtró');
  assert.strictEqual(vista.vendedor.phone, undefined);
  assert.strictEqual(vista.vendedor.telefono, undefined);
});

test('no arrastra campos internos aunque vengan en el producto', () => {
  const vista = aVistaPublica(
    productoCompleto({ email: 'ana@um.edu.mx', password_hash: 'x', seller: 's_1' }),
  );
  const serializado = JSON.stringify(vista);

  assert.ok(!serializado.includes('ana@um.edu.mx'));
  assert.ok(!serializado.includes('password_hash'));
  // `views` es un contador interno: no aporta nada a la vista pública y
  // revela volumen de tráfico del catálogo.
  assert.strictEqual(vista.views, undefined);
  assert.strictEqual(vista.stock_quantity, undefined);
});

test('incluye lo que la página necesita para renderizar', () => {
  const vista = aVistaPublica(productoCompleto());

  assert.strictEqual(vista.titulo, 'Bicicleta de montaña');
  assert.strictEqual(vista.precio, 2400);
  assert.strictEqual(vista.precioAnterior, 3000);
  assert.deepStrictEqual(vista.fotos, ['/uploads/a.webp', '/uploads/b.webp']);
  assert.strictEqual(vista.estado, 'available');
  assert.strictEqual(vista.disponible, true);
  assert.strictEqual(vista.categoria.nombre, 'Deportes');
  assert.strictEqual(vista.vendedor.nombre, 'Ana Valdés');
  assert.strictEqual(vista.vendedor.verificado, true);
  assert.strictEqual(
    vista.vendedor.carrera,
    'Ingeniería en Sistemas Computacionales',
  );
});

test('omite la ubicación cuando el vendedor NO es un negocio', () => {
  const vista = aVistaPublica(productoCompleto());
  // Un particular no debe quedar geolocalizado en una página indexable.
  assert.strictEqual(vista.ubicacion, null);
});

test('incluye la ubicación cuando el vendedor es un negocio', () => {
  const producto = productoCompleto();
  producto.sellerObj.isBusiness = true;
  const vista = aVistaPublica(producto);

  assert.deepStrictEqual(vista.ubicacion, { lat: 25.18, lng: -99.82 });
});

test('un negocio sin coordenadas no inventa una ubicación', () => {
  const producto = productoCompleto({ locationLat: null, locationLng: null });
  producto.sellerObj.isBusiness = true;

  assert.strictEqual(aVistaPublica(producto).ubicacion, null);
});

test('propaga el estado de vendido en vez de ocultar el producto', () => {
  const vista = aVistaPublica(
    productoCompleto({ computed_status: 'sold', is_available: false }),
  );

  assert.strictEqual(vista.estado, 'sold');
  assert.strictEqual(vista.disponible, false);
});

test('tolera un producto sin fotos, sin categoría y sin vendedor', () => {
  const vista = aVistaPublica({
    id: 'p_2',
    title: 'Sin nada',
    description: '',
    price: 0,
    computed_status: 'available',
    is_available: true,
    images: null,
    categoryObj: null,
    sellerObj: null,
  });

  assert.deepStrictEqual(vista.fotos, []);
  assert.strictEqual(vista.categoria, null);
  assert.strictEqual(vista.vendedor, null);
  assert.strictEqual(vista.ubicacion, null);
});
