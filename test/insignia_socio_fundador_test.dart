// La insignia verde "Socio Fundador": la otorga el admin a mano
// (backend/scripts/otorgar-socio-fundador.js), ninguna cuenta la gana sola.
//
// Lo que se protege: que sea visualmente distinta de la insignia azul de
// verificación (color e ícono propios, para que no se lea como "otro tipo de
// verificado"), y que el modelo la traiga en false por default — un
// `Seller.fromJson` sin el campo (backend viejo, o cualquier cuenta sin la
// insignia) NO debe regalarla por accidente.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/badges.dart';

void main() {
  Future<void> montar(WidgetTester tester, Widget hijo) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: hijo))));
  }

  testWidgets('la variante compacta es solo el ícono, en verde', (
    tester,
  ) async {
    await montar(tester, const InsigniaSocioFundador(compact: true));

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(icono.icon, Icons.workspace_premium_rounded);
    expect(icono.color, isNot(AppColors.verifiedBlue));
  });

  testWidgets('la variante completa muestra la etiqueta', (tester) async {
    await montar(tester, const InsigniaSocioFundador());

    expect(find.text('Socio Fundador'), findsOneWidget);
  });

  testWidgets('el tamaño de la variante compacta es configurable', (
    tester,
  ) async {
    await montar(
      tester,
      const InsigniaSocioFundador(compact: true, size: 24),
    );

    expect(tester.widget<Icon>(find.byType(Icon)).size, 24);
  });

  // ─── El modelo ─────────────────────────────────────────────

  test('por default un vendedor no lleva la insignia', () {
    final seller = Seller.fromJson({'id': 'u_1', 'name': 'Ana'});

    expect(seller.socioFundador, isFalse);
  });

  test('la insignia llega del backend tal cual', () {
    final seller = Seller.fromJson({
      'id': 'u_1',
      'name': 'Ana',
      'socioFundador': true,
    });

    expect(seller.socioFundador, isTrue);
  });
}
