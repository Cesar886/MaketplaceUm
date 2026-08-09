// Tests del parseo del detalle de producto (producto + los dos carruseles).
//
// El caso que importa es el de los arrays ausentes o nulos: la pantalla
// decide mostrar u ocultar cada sección con `isEmpty`, así que si el parseo
// dejara pasar un null, el detalle reventaría en el build en vez de
// simplemente no pintar la sección.

import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';

void main() {
  Map<String, dynamic> productoJson(String id, {String? categoria}) {
    return {
      'id': id,
      'title': 'Calculadora científica',
      'price': 450,
      'description': 'Poco uso',
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'sellerObj': {
        'id': 's_1',
        'name': 'Mariana Peña',
        'avatarInitials': 'MP',
        'major': 'Estudiante',
        'isBusiness': false,
        'verified': true,
      },
      'categoryObj': {
        'id': categoria ?? 'c_1',
        'name': 'Libros',
        'emoji': '📚',
      },
      'images': <String>[],
      'extras': <dynamic>[],
    };
  }

  Map<String, dynamic> detalleJson({
    Object? related,
    Object? sellerOther,
    bool incluirClaves = true,
  }) {
    return {
      ...productoJson('p_1'),
      if (incluirClaves) 'relatedProducts': related ?? <dynamic>[],
      if (incluirClaves) 'sellerOtherProducts': sellerOther ?? <dynamic>[],
    };
  }

  test('parsea el producto y sus dos carruseles', () {
    final detalle = ProductDetail.fromJson(
      detalleJson(
        related: [productoJson('p_rel_1'), productoJson('p_rel_2')],
        sellerOther: [productoJson('p_vend_1')],
      ),
    );

    expect(detalle.product.id, 'p_1');
    expect(detalle.relatedProducts.map((p) => p.id), ['p_rel_1', 'p_rel_2']);
    expect(detalle.sellerOtherProducts.map((p) => p.id), ['p_vend_1']);
  });

  test('sin carruseles en la respuesta, las listas quedan vacías', () {
    final detalle = ProductDetail.fromJson(detalleJson(incluirClaves: false));

    expect(detalle.relatedProducts, isEmpty);
    expect(detalle.sellerOtherProducts, isEmpty);
    expect(detalle.product.id, 'p_1');
  });

  test('un null en vez de array no revienta: se trata como vacío', () {
    // Backend viejo, respuesta cacheada o campo perdido en el camino: la
    // pantalla debe ocultar la sección, no caerse al construirla.
    final detalle = ProductDetail.fromJson({
      ...productoJson('p_1'),
      'relatedProducts': null,
      'sellerOtherProducts': null,
    });

    expect(detalle.relatedProducts, isEmpty);
    expect(detalle.sellerOtherProducts, isEmpty);
  });

  test('los productos del carrusel traen vendedor y categoría resueltos', () {
    // Es lo que ProductCard necesita para pintar: si llegaran sin sellerObj
    // la tarjeta saldría con "Vendedor" genérico dentro del carrusel.
    final detalle = ProductDetail.fromJson(
      detalleJson(related: [productoJson('p_rel_1')]),
    );

    final tarjeta = detalle.relatedProducts.single;
    expect(tarjeta.seller.name, 'Mariana Peña');
    expect(tarjeta.category.name, 'Libros');
    expect(tarjeta.price, 450);
  });
}
