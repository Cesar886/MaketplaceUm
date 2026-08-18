// El parseo del link entrante es la parte del deep linking que se puede
// probar sin plataforma: decide si un Uri que llegó de fuera identifica una
// publicación de Marketplace UM y cuál.
//
// Importa porque el intent-filter de Android es más laxo que lo que la app
// debe aceptar (captura cualquier /producto/… del dominio), y porque en
// escritorio o por un link pegado a mano puede llegar cualquier cosa.

import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/services/deep_link_parser.dart';

/// Azúcar para leer los casos como el link tal cual llega.
String? idDe(String url) => idDePublicacionEnLink(Uri.parse(url));

void main() {
  group('links del sitio', () {
    test('extrae el id de un link compartido', () {
      expect(idDe('https://mercaditoum.site/producto/p_123'), 'p_123');
    });

    test('acepta el subdominio www, que un link pegado a mano puede traer', () {
      expect(idDe('https://www.mercaditoum.site/producto/p_123'), 'p_123');
    });

    test('ignora query y fragmento, que agregan al reenviar por redes', () {
      expect(
        idDe('https://mercaditoum.site/producto/p_123?utm_source=wa#foto'),
        'p_123',
      );
    });

    test('decodifica un id escapado en la URL', () {
      expect(idDe('https://mercaditoum.site/producto/p%20123'), 'p 123');
    });

    test('acepta http, porque un link viejo puede no traer TLS', () {
      expect(idDe('http://mercaditoum.site/producto/p_123'), 'p_123');
    });
  });

  group('links que NO son de una publicación', () {
    test('rechaza otro dominio aunque la ruta calce', () {
      // Un dominio parecido es el caso que de verdad importa: sin este
      // chequeo, un link de phishing abriría la app como si fuera propio.
      expect(idDe('https://mercaditoum.site.malo.com/producto/p_123'), isNull);
      expect(idDe('https://otrositio.com/producto/p_123'), isNull);
    });

    test('rechaza otra ruta del mismo dominio', () {
      expect(idDe('https://mercaditoum.site/'), isNull);
      expect(idDe('https://mercaditoum.site/blog/p_123'), isNull);
    });

    test('rechaza la ruta sin id', () {
      expect(idDe('https://mercaditoum.site/producto'), isNull);
      expect(idDe('https://mercaditoum.site/producto/'), isNull);
    });

    test('rechaza un id vacío o solo espacios', () {
      expect(idDe('https://mercaditoum.site/producto/%20'), isNull);
    });

    test('rechaza segmentos de más, que no son un id', () {
      expect(idDe('https://mercaditoum.site/producto/p_123/editar'), isNull);
    });

    test('rechaza el deep link de Mercado Pago', () {
      // Llega por el otro intent-filter y lo maneja el flujo de pagos; este
      // servicio no debe intentar abrirlo como si fuera una publicación.
      expect(idDe('mercaditoum://payments/connected'), isNull);
    });
  });

  group('esquema propio de los códigos QR', () {
    test('extrae el id de un QR de producto', () {
      expect(idDe('mercaditoum://product/p_123'), 'p_123');
    });

    test('extrae el id de un QR de búsqueda', () {
      expect(idDe('mercaditoum://wanted/w_123'), 'w_123');
    });

    test('rechaza un host desconocido del esquema propio', () {
      expect(idDe('mercaditoum://otracosa/p_123'), isNull);
    });
  });
}
