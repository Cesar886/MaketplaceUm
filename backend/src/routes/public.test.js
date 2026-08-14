// Tests de la proyección pública de un producto.
//
// El punto crítico es lo que NO sale: esta respuesta alimenta una página web
// indexable, así que un campo de contacto filtrado ahí convierte el catálogo
// en un directorio de teléfonos raspable. Por eso los tests afirman sobre la
// ausencia de campos, no solo sobre la presencia.

const test = require('node:test');
const assert = require('node:assert');

const { aVistaPublica, aVistaPublicaBusqueda } = require('./public');

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

test('marca la publicación como producto para que la web sepa qué pintar', () => {
  assert.strictEqual(aVistaPublica(productoCompleto()).tipo, 'producto');
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

// ─── Publicaciones "se busca" ────────────────────────────────────────────
//
// Comparten la URL pública con los productos (/producto/:id), así que pasan
// por el mismo endpoint. La proyección es distinta porque los datos lo son:
// una búsqueda no tiene fotos ni precio único, sino un rango.

/** Publicación "se busca" tal como la deja `attachWantedRelations`. */
function busquedaCompleta(extra = {}) {
  return {
    id: 'w_1',
    userId: 's_1',
    title: 'Busco calculadora TI-84',
    description: 'Para Cálculo II, de preferencia con estuche.',
    categoryId: 'c_lib',
    type: 'producto',
    priceMin: 800,
    priceMax: 1500,
    status: 'abierta',
    createdAt: '2026-08-01T18:30:00.000Z',
    resolvedWithUserId: 's_9',
    locationLat: 25.18,
    locationLng: -99.82,
    views: 42,
    paymentMethods: ['efectivo'],
    postType: 'se_busca',
    categoryObj: { id: 'c_lib', name: 'Libros', icon: '📚' },
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
    },
    ...extra,
  };
}

test('la búsqueda tampoco expone el teléfono ni el id de quien publica', () => {
  const vista = aVistaPublicaBusqueda(busquedaCompleta());
  const serializado = JSON.stringify(vista);

  assert.ok(!serializado.includes('+528112345678'), 'el teléfono se filtró');
  assert.strictEqual(vista.vendedor.phone, undefined);
  // `userId` y `resolvedWithUserId` identifican cuentas: publicarlos permite
  // cruzar quién le compró a quién desde fuera de la app.
  assert.ok(!serializado.includes('s_1'));
  assert.ok(!serializado.includes('s_9'));
  assert.strictEqual(vista.views, undefined);
});

test('incluye el rango de precio y se distingue de un producto', () => {
  const vista = aVistaPublicaBusqueda(busquedaCompleta());

  assert.strictEqual(vista.tipo, 'busqueda');
  assert.strictEqual(vista.titulo, 'Busco calculadora TI-84');
  assert.strictEqual(vista.precioMin, 800);
  assert.strictEqual(vista.precioMax, 1500);
  // No hay un `precio` suelto: la web tiene que decidir cómo pintar el rango,
  // y un precio único inventado ahí mentiría sobre lo que pide el comprador.
  assert.strictEqual(vista.precio, undefined);
  assert.strictEqual(vista.fotos, undefined);
  assert.strictEqual(vista.busca, 'producto');
  assert.strictEqual(vista.categoria.nombre, 'Libros');
});

test('una búsqueda abierta se distingue de una ya resuelta', () => {
  assert.strictEqual(aVistaPublicaBusqueda(busquedaCompleta()).abierta, true);
  assert.strictEqual(
    aVistaPublicaBusqueda(busquedaCompleta({ status: 'resuelta' })).abierta,
    false,
  );
});

test('omite la ubicación de la búsqueda si quien publica no es un negocio', () => {
  assert.strictEqual(aVistaPublicaBusqueda(busquedaCompleta()).ubicacion, null);
});

test('incluye la ubicación de la búsqueda cuando es un negocio', () => {
  const busqueda = busquedaCompleta();
  busqueda.sellerObj.isBusiness = true;

  assert.deepStrictEqual(aVistaPublicaBusqueda(busqueda).ubicacion, {
    lat: 25.18,
    lng: -99.82,
  });
});

test('tolera una búsqueda sin rango, sin categoría y sin publicante', () => {
  const vista = aVistaPublicaBusqueda({
    id: 'w_2',
    title: 'Busco algo',
    description: null,
    type: 'servicio',
    priceMin: null,
    priceMax: null,
    status: 'abierta',
    createdAt: null,
    categoryObj: null,
    sellerObj: null,
  });

  assert.strictEqual(vista.precioMin, null);
  assert.strictEqual(vista.precioMax, null);
  assert.strictEqual(vista.descripcion, '');
  assert.strictEqual(vista.categoria, null);
  assert.strictEqual(vista.vendedor, null);
  assert.strictEqual(vista.ubicacion, null);
  assert.strictEqual(vista.publicadoEn, null);
});
