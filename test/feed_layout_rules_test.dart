import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/services/feed_mixer.dart';

// Helpers: los ítems llevan un String como `data` (no Product/Seller reales)
// justamente para probar la regla de posicionamiento de forma aislada — sin
// base de datos, sin modelos de dominio y sin widgets.
FeedItem _p(String id) => FeedItem(FeedItemType.product, id);
FeedItem _w(String id) => FeedItem(FeedItemType.wanted, id);
FeedItem _n(String id) => FeedItem(FeedItemType.business, id);

/// Índices (en la lista ya procesada) donde quedó un negocio.
List<int> _businessIndexes(List<FeedItem> items) => [
  for (var i = 0; i < items.length; i++)
    if (items[i].type == FeedItemType.business) i,
];

/// `data` de los ítems que NO son negocio, en orden.
List<Object> _normalData(List<FeedItem> items) => [
  for (final item in items)
    if (item.type != FeedItemType.business) item.data,
];

/// Índice del último ítem normal. Los negocios que quedan después de él son
/// la cola best-effort, donde ya no hay contenido normal que intercalar.
int _lastNormalIndex(List<FeedItem> items) {
  for (var i = items.length - 1; i >= 0; i--) {
    if (items[i].type != FeedItemType.business) return i;
  }
  return -1;
}

void main() {
  group('applyFeedLayoutRules', () {
    test('ningún negocio cae dentro de la zona de exclusión inicial', () {
      // Negocios en las posiciones 0, 1 y 5: todas prohibidas con top=8.
      final input = [
        _n('n0'),
        _n('n1'),
        _p('p0'), _p('p1'), _p('p2'), _p('p3'),
        _n('n2'),
        _p('p4'), _p('p5'), _p('p6'), _p('p7'),
        _p('p8'), _p('p9'), _p('p10'), _p('p11'),
      ];

      final result = applyFeedLayoutRules(input);

      for (final index in _businessIndexes(result)) {
        expect(
          index,
          greaterThanOrEqualTo(kFeedTopItemsNoBusiness),
          reason: 'negocio en índice $index, dentro de la zona de exclusión',
        );
      }
    });

    test('no quedan dos negocios consecutivos', () {
      final input = [
        for (var i = 0; i < 10; i++) _p('p$i'),
        _n('n0'), _n('n1'), _n('n2'),
        for (var i = 10; i < 30; i++) _p('p$i'),
      ];

      final result = applyFeedLayoutRules(input);

      final indexes = _businessIndexes(result);
      for (var i = 1; i < indexes.length; i++) {
        final gap = indexes[i] - indexes[i - 1] - 1;
        expect(
          gap,
          greaterThanOrEqualTo(kMinGapEntreNegocios),
          reason:
              'negocios en ${indexes[i - 1]} y ${indexes[i]} con solo $gap '
              'ítems normales entre medio',
        );
      }
    });

    test('el orden relativo de las publicaciones normales no cambia', () {
      final input = [
        _n('n0'),
        _p('p0'), _w('w0'), _p('p1'),
        _n('n1'),
        _w('w1'), _p('p2'), _p('p3'), _w('w2'),
        _n('n2'),
        _p('p4'), _p('p5'), _p('p6'), _p('p7'), _p('p8'),
      ];

      final result = applyFeedLayoutRules(input);

      expect(_normalData(result), equals(_normalData(input)));
    });

    test('no pierde ni duplica ítems', () {
      final input = [
        _n('n0'), _n('n1'),
        _p('p0'), _p('p1'), _p('p2'),
        _n('n2'),
        _w('w0'), _w('w1'),
        _n('n3'),
        _p('p3'), _p('p4'), _p('p5'), _p('p6'),
      ];

      final result = applyFeedLayoutRules(input);

      expect(result.length, equals(input.length));
      expect(
        result.map((i) => i.data).toSet(),
        equals(input.map((i) => i.data).toSet()),
      );
    });

    test('un feed que ya cumple las reglas se devuelve intacto', () {
      final input = [
        for (var i = 0; i < 8; i++) _p('p$i'),
        _n('n0'),
        _p('p8'), _p('p9'),
        _n('n1'),
        _p('p10'), _p('p11'), _p('p12'),
      ];

      final result = applyFeedLayoutRules(input);

      expect(result.map((i) => i.data).toList(), equals(input.map((i) => i.data).toList()));
      expect(result.map((i) => i.type).toList(), equals(input.map((i) => i.type).toList()));
    });

    test('mueve el negocio a la primera posición válida, no al final', () {
      // n0 arranca en la posición 0 (prohibida). Con top=4 y gap=2 su primera
      // posición legal es exactamente la 4 — no el final de la lista.
      final input = [
        _n('n0'),
        _p('p0'), _p('p1'), _p('p2'), _p('p3'), _p('p4'), _p('p5'),
      ];

      final result = applyFeedLayoutRules(
        input,
        topItemsNoBusiness: 4,
        minGapEntreNegocios: 2,
      );

      expect(_businessIndexes(result), equals([4]));
    });

    test('los negocios sobrantes al final se anexan, no se descartan', () {
      // Con top=2 y gap=2: n0 cabe en la posición 2. n1 y n2 ya no tienen
      // publicaciones normales para separarse — se anexan igual (best-effort).
      final input = [_n('n0'), _p('p0'), _p('p1'), _n('n1'), _n('n2')];

      final result = applyFeedLayoutRules(
        input,
        topItemsNoBusiness: 2,
        minGapEntreNegocios: 2,
      );

      expect(
        result.map((i) => i.data).toList(),
        equals(['p0', 'p1', 'n0', 'n1', 'n2']),
      );
    });

    test('la invariante de gap se cumple hasta el último ítem normal', () {
      final input = [
        for (var i = 0; i < 12; i++) _p('p$i'),
        _n('n0'), _n('n1'), _n('n2'), _n('n3'),
      ];

      final result = applyFeedLayoutRules(input);

      final lastNormal = _lastNormalIndex(result);
      final indexes = _businessIndexes(
        result,
      ).where((i) => i < lastNormal).toList();
      for (var i = 1; i < indexes.length; i++) {
        expect(
          indexes[i] - indexes[i - 1] - 1,
          greaterThanOrEqualTo(kMinGapEntreNegocios),
        );
      }
    });

    test('una lista vacía devuelve una lista vacía', () {
      expect(applyFeedLayoutRules([]), isEmpty);
    });
  });
}
