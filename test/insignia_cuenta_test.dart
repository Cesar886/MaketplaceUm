// InsigniaCuenta: la decisión única de qué palomita pintar junto a un
// nombre — verde de Socio Fundador, azul de verificación, o ninguna.
//
// Existe para que comentarios, preguntas, tarjetas de producto, el feed, el
// chat y los dos perfiles nunca diverjan sobre esta regla. Lo que se
// protege: que Socio Fundador SIEMPRE gane sobre verificado (nunca las dos
// palomitas juntas), y que un vendedor ni verificado ni Socio Fundador no
// pinte nada.

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

  testWidgets('socioFundador gana sobre verified: pinta la verde, no la azul', (
    tester,
  ) async {
    await montar(
      tester,
      const InsigniaCuenta(
        verified: true,
        socioFundador: true,
        tipoCuenta: 'estudiante',
      ),
    );

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(icono.icon, Icons.verified_rounded);
    expect(icono.color, isNot(AppColors.verifiedBlue));
  });

  testWidgets('solo verificado: pinta la azul', (tester) async {
    await montar(
      tester,
      const InsigniaCuenta(
        verified: true,
        socioFundador: false,
        tipoCuenta: 'estudiante',
      ),
    );

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(icono.icon, Icons.verified_rounded);
    expect(icono.color, AppColors.verifiedBlue);
  });

  testWidgets('ni verificado ni Socio Fundador: no pinta nada', (tester) async {
    await montar(
      tester,
      const InsigniaCuenta(verified: false, socioFundador: false),
    );

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('InsigniaCuenta.deSeller toma los tres campos del Seller', (
    tester,
  ) async {
    final seller = Seller.fromJson({
      'id': 'u_1',
      'name': 'Ana',
      'verified': false,
      'socioFundador': true,
    });

    await montar(tester, InsigniaCuenta.deSeller(seller));

    final icono = tester.widget<Icon>(find.byType(Icon));
    expect(icono.color, isNot(AppColors.verifiedBlue));
  });

  // ─── ChatUser: la misma decisión también en el chat ─────────

  test('ChatUser.fromJson trae verified, socioFundador y tipoCuenta', () {
    final otro = ChatUser.fromJson({
      'id': 'u_1',
      'name': 'Ana',
      'verified': true,
      'socioFundador': true,
      'tipoCuenta': 'negocio',
    });

    expect(otro.verified, isTrue);
    expect(otro.socioFundador, isTrue);
    expect(otro.tipoCuenta, 'negocio');
  });

  test('ChatUser.fromJson sin esos campos cae a los defaults seguros', () {
    final otro = ChatUser.fromJson({'id': 'u_1', 'name': 'Ana'});

    expect(otro.verified, isFalse);
    expect(otro.socioFundador, isFalse);
    expect(otro.tipoCuenta, 'particular');
  });

  test('ChatUser.deSeller copia la insignia del Seller original', () {
    final seller = Seller.fromJson({
      'id': 'u_1',
      'name': 'Ana',
      'socioFundador': true,
    });

    expect(ChatUser.deSeller(seller).socioFundador, isTrue);
  });
}
