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

  testWidgets('colorea de azul la insignia de estudiante', (tester) async {
    await montar(tester, const InsigniaVerificada(tipo: AccountType.estudiante));
    expect(iconoDe(tester).color, AppColors.primary);
    expect(find.text('Estudiante verificado'), findsOneWidget);
  });

  testWidgets('colorea de teal la insignia de negocio', (tester) async {
    await montar(tester, const InsigniaVerificada(tipo: AccountType.negocio));
    expect(iconoDe(tester).color, AppColors.teal);
    expect(find.text('Negocio verificado'), findsOneWidget);
  });

  testWidgets('usa un color neutro para la cuenta externa', (tester) async {
    await montar(tester, const InsigniaVerificada(tipo: AccountType.particular));
    expect(iconoDe(tester).color, AppColors.muted);
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
    expect(iconoDe(tester).color, AppColors.teal);
  });

  testWidgets('un tipo de cuenta desconocido cae al estilo neutro', (
    tester,
  ) async {
    await montar(tester, const InsigniaVerificada.desdeTipo('marciano'));
    expect(iconoDe(tester).color, AppColors.muted);
  });
}
