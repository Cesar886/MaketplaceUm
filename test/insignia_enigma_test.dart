// La insignia del enigma escondido.
//
// Lo que se protege aquí es sobre todo lo que la insignia NO dice: la
// etiqueta no puede mencionar comentarios, frases ni acertijos, porque el
// perfil de quien lo resolvió lo ve cualquiera y sería la filtración más
// tonta posible del juego. Además, que solo la lleve quien la ganó: un
// `enigmaPosicion` nulo tiene que dejar la fila de insignias como estaba.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/badges.dart';

void main() {
  Future<void> montar(
    WidgetTester tester,
    Widget hijo, {
    Brightness brillo = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brillo),
        home: Scaffold(body: Center(child: hijo)),
      ),
    );
    // MaterialApp interpola el tema con un AnimatedTheme: sin dejar correr
    // esa transición, remontar con otro brillo sigue devolviendo los colores
    // del tema anterior y el test se cree que la insignia no cambia.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('muestra la posición con la que se resolvió', (tester) async {
    await montar(tester, const InsigniaEnigma(posicion: 1));

    expect(find.text('Enigma #1'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byType(Icon)).icon,
      Icons.vpn_key_rounded,
      reason: 'la llave es la firma visual del mundo secreto',
    );
  });

  testWidgets('una posición de tres dígitos sigue cabiendo en una línea', (
    tester,
  ) async {
    await montar(tester, const InsigniaEnigma(posicion: 137));

    expect(find.text('Enigma #137'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la etiqueta no delata cómo se consigue', (tester) async {
    await montar(tester, const InsigniaEnigma(posicion: 4));

    final texto = tester.widget<Text>(find.byType(Text)).data!.toLowerCase();
    for (final palabra in ['comentario', 'frase', 'acertijo', 'secreto']) {
      expect(
        texto.contains(palabra),
        isFalse,
        reason: 'la insignia es pública: no puede contener "$palabra"',
      );
    }
  });

  testWidgets('se aclara en modo oscuro para no perderse contra el fondo', (
    tester,
  ) async {
    await montar(tester, const InsigniaEnigma(posicion: 2));
    final claro = tester.widget<Icon>(find.byType(Icon)).color!;

    await montar(tester, const InsigniaEnigma(posicion: 2), brillo: Brightness.dark);
    final oscuro = tester.widget<Icon>(find.byType(Icon)).color!;

    expect(oscuro, isNot(claro));
    expect(
      oscuro.computeLuminance(),
      greaterThan(claro.computeLuminance()),
      reason: 'sobre fondo oscuro el latón tiene que ser el claro',
    );
  });

  // ─── El modelo ─────────────────────────────────────────────

  test('un vendedor sin la hazaña no trae posición', () {
    final seller = Seller.fromJson({'id': 'u_1', 'name': 'Ana'});

    expect(seller.enigmaPosicion, isNull);
    expect(seller.resolvioElEnigma, isFalse);
  });

  test('la posición llega del backend tal cual', () {
    final seller = Seller.fromJson({
      'id': 'u_1',
      'name': 'Ana',
      'enigmaPosicion': 1,
    });

    expect(seller.enigmaPosicion, 1);
    expect(seller.resolvioElEnigma, isTrue);
  });
}
