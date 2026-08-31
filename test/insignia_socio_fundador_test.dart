// La insignia "Socio Fundador": la otorga el admin a mano
// (backend/scripts/otorgar-socio-fundador.js), ninguna cuenta la gana sola.
//
// Lo que se protege: que use la MISMA palomita que la verificación
// (`verified_rounded`) pero en verde — no un ícono distinto, porque
// reemplaza a la insignia azul en vez de convivir con ella (ver los call
// sites en profile_screen.dart y seller_profile_screen.dart, que muestran
// una u otra, nunca las dos) — y que el modelo la traiga en false por
// default: un `Seller.fromJson` sin el campo (backend viejo, o cualquier
// cuenta sin la insignia) NO debe regalarla por accidente.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/badges.dart';

void main() {
  Future<void> montar(WidgetTester tester, Widget hijo) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: hijo)),
      ),
    );
  }

  testWidgets('la variante compacta es la misma palomita, pero verde', (
    tester,
  ) async {
    await montar(tester, const InsigniaSocioFundador(compact: true));

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(
      icono.icon,
      Icons.verified_rounded,
      reason: 'el mismo ícono que InsigniaVerificada: reemplaza, no compite',
    );
    expect(icono.color, isNot(AppColors.verifiedBlue));
  });

  testWidgets('la variante completa muestra la etiqueta', (tester) async {
    await montar(tester, const InsigniaSocioFundador());

    expect(find.text('Socio Fundador'), findsOneWidget);
  });

  testWidgets('el tamaño de la variante compacta es configurable', (
    tester,
  ) async {
    await montar(tester, const InsigniaSocioFundador(compact: true, size: 24));

    expect(tester.widget<Icon>(find.byType(Icon)).size, 24);
  });

  testWidgets('junto a InsigniaVerificada, solo debe pintarse una de las dos', (
    tester,
  ) async {
    // Reproduce la decisión real de los call sites: cuando socioFundador
    // es true, se pinta esta y NO InsigniaVerificada — nunca las dos
    // palomitas una junto a la otra diciendo lo mismo dos veces.
    final socioFundador = Seller.fromJson({
      'id': 'u_1',
      'name': 'Ana',
      'socioFundador': true,
    }).socioFundador;
    await montar(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (socioFundador)
            const InsigniaSocioFundador(compact: true)
          else
            const InsigniaVerificada.desdeTipo('estudiante', compact: true),
        ],
      ),
    );

    expect(find.byType(Icon), findsOneWidget);
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.verified_rounded);
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      isNot(AppColors.verifiedBlue),
    );
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
