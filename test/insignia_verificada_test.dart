import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/widgets/badges.dart';

void main() {
  Future<void> montar(WidgetTester tester, Widget hijo) {
    return tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: hijo))),
    );
  }

  Icon iconoDe(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon).first);

  testWidgets('usa el mismo ícono de check para los tres tipos de cuenta', (
    tester,
  ) async {
    for (final tipo in AccountType.values) {
      await montar(tester, InsigniaVerificada(tipo: tipo));
      expect(iconoDe(tester).icon, Icons.verified_rounded);
    }
  });

  // El color NO distingue tipos de cuenta a propósito: los tres verificados
  // comparten el mismo azul (estilo Meta/Instagram) para no sugerir que una
  // cuenta es "más confiable" que otra. Lo único que cambia es la etiqueta.
  testWidgets('usa el mismo azul de verificación para los tres tipos', (
    tester,
  ) async {
    for (final tipo in AccountType.values) {
      await montar(tester, InsigniaVerificada(tipo: tipo));
      expect(iconoDe(tester).color, AppColors.verifiedBlue);
    }
  });

  testWidgets('etiqueta a un estudiante verificado', (tester) async {
    await montar(tester, const InsigniaVerificada(tipo: AccountType.estudiante));
    expect(find.text('Estudiante verificado'), findsOneWidget);
  });

  testWidgets('etiqueta a un negocio verificado', (tester) async {
    await montar(tester, const InsigniaVerificada(tipo: AccountType.negocio));
    expect(find.text('Negocio verificado'), findsOneWidget);
  });

  testWidgets('usa la etiqueta genérica para la cuenta externa', (tester) async {
    await montar(tester, const InsigniaVerificada(tipo: AccountType.particular));
    expect(find.text('Verificado'), findsOneWidget);
  });

  testWidgets('la variante compacta muestra solo el ícono, sin etiqueta', (
    tester,
  ) async {
    await montar(
      tester,
      const InsigniaVerificada(tipo: AccountType.estudiante, compact: true),
    );
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text('Estudiante verificado'), findsNothing);
  });

  testWidgets('la variante compacta respeta el tamaño pedido por el call site', (
    tester,
  ) async {
    await montar(
      tester,
      const InsigniaVerificada(
        tipo: AccountType.negocio,
        compact: true,
        size: 18,
      ),
    );
    expect(iconoDe(tester).size, 18);
  });

  testWidgets('construye la insignia a partir del tipo de cuenta del backend', (
    tester,
  ) async {
    await montar(tester, const InsigniaVerificada.desdeTipo('negocio'));
    expect(find.text('Negocio verificado'), findsOneWidget);
  });

  testWidgets('un tipo de cuenta desconocido cae a la etiqueta neutra', (
    tester,
  ) async {
    await montar(tester, const InsigniaVerificada.desdeTipo('marciano'));
    expect(find.text('Verificado'), findsOneWidget);
    expect(find.text('Negocio verificado'), findsNothing);
    expect(find.text('Estudiante verificado'), findsNothing);
  });
}
