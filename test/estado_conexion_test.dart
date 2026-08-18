import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/utils/estado_conexion.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  final ahora = DateTime.utc(2026, 8, 17, 12, 0);

  setUpAll(inicializarTraducciones);

  group('etiquetaUltimaActividad', () {
    test('sin fecha no hay etiqueta', () {
      expect(etiquetaUltimaActividad(null, ahora: ahora), isNull);
    });

    test('hace menos de un minuto se redondea a "hace un momento"', () {
      final label = etiquetaUltimaActividad(
        ahora.subtract(const Duration(seconds: 20)),
        ahora: ahora,
      );
      expect(label, 'Activo hace un momento');
    });

    test('minutos y horas se muestran tal cual', () {
      expect(
        etiquetaUltimaActividad(
          ahora.subtract(const Duration(minutes: 5)),
          ahora: ahora,
        ),
        'Activo hace 5 min',
      );
      expect(
        etiquetaUltimaActividad(
          ahora.subtract(const Duration(hours: 2)),
          ahora: ahora,
        ),
        'Activo hace 2 h',
      );
    });

    test('a los pocos días sigue mostrándose', () {
      expect(
        etiquetaUltimaActividad(
          ahora.subtract(const Duration(days: 3)),
          ahora: ahora,
        ),
        'Activo hace 3 d',
      );
    });

    test('pasada una semana deja de mostrarse', () {
      // Más allá de eso el dato ya no informa de nada útil ("activo hace 4
      // meses" solo hace ruido) y expone más historial del necesario.
      expect(
        etiquetaUltimaActividad(
          ahora.subtract(const Duration(days: 7, hours: 1)),
          ahora: ahora,
        ),
        isNull,
      );
    });

    test('una fecha futura por desfase de reloj no dice "en 3 minutos"', () {
      expect(
        etiquetaUltimaActividad(
          ahora.add(const Duration(minutes: 3)),
          ahora: ahora,
        ),
        'Activo hace un momento',
      );
    });
  });

  group('EstadoConexion.desdeJson', () {
    test('lee isOnline y lastActive de una respuesta del backend', () {
      final estado = EstadoConexion.desdeJson({
        'isOnline': true,
        'lastActive': null,
      });
      expect(estado.enLinea, isTrue);
      expect(estado.ultimaActividad, isNull);
    });

    test('parsea lastActive en ISO 8601', () {
      final estado = EstadoConexion.desdeJson({
        'isOnline': false,
        'lastActive': '2026-08-17T09:00:00.000Z',
      });
      expect(estado.enLinea, isFalse);
      expect(estado.ultimaActividad, DateTime.utc(2026, 8, 17, 9));
    });

    test('un JSON sin campos de presencia da un estado desconectado', () {
      // Pasa contra un backend viejo: la pantalla tiene que seguir pintando.
      final estado = EstadoConexion.desdeJson(const {});
      expect(estado.enLinea, isFalse);
      expect(estado.ultimaActividad, isNull);
    });

    test('una fecha corrupta se ignora en vez de romper el parseo', () {
      final estado = EstadoConexion.desdeJson({
        'isOnline': false,
        'lastActive': 'ayer por la tarde',
      });
      expect(estado.ultimaActividad, isNull);
    });
  });
}
