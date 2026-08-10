// Cableado de tema de la app.
//
// El test anterior pumpeaba `MyApp` entero y afirmaba sobre productos mock
// ('iPad 9na gen...', 'Ofertas del campus'). Dejó de ser ejecutable: hoy
// `MyApp` arranca en SplashScreen, que a los 600 ms navega a MainShell, y
// MainShell exige Firebase (`PushService.instance`) y una llamada real al
// backend — ninguno de los dos existe bajo `flutter test`. Un arranque de la
// app completa solo sería testeable inyectando esas dependencias.
//
// Lo que sí se puede proteger sin montar la app entera es lo que `MyApp`
// realmente decide: que el `themeMode` que publica ThemeProvider llegue al
// MaterialApp y cambie el tema pintado. Si alguien rompe esa conexión, la
// app arranca siempre en claro y el switch de modo oscuro deja de servir.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/providers/theme_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Réplica del MaterialApp de `MyApp`, sin su `home` (SplashScreen), que
  /// es la parte que arrastra Firebase y red.
  Widget appDePrueba() {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Builder(
        builder: (context) {
          final theme = context.watch<ThemeProvider>();
          return MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.themeMode,
            home: const Scaffold(body: Text('contenido')),
          );
        },
      ),
    );
  }

  testWidgets('arranca en modo claro', (tester) async {
    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.light);
  });

  testWidgets('el modo oscuro guardado se aplica al arrancar', (tester) async {
    SharedPreferences.setMockInitialValues({'dark_mode': true});

    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.dark);
  });

  testWidgets('alternar el modo oscuro repinta la app en oscuro', (
    tester,
  ) async {
    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    final context = tester.element(find.text('contenido'));
    await context.read<ThemeProvider>().toggleDarkMode();
    await tester.pump();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.themeMode, ThemeMode.dark);
  });

  testWidgets('el tema oscuro y el claro no son el mismo brillo', (
    tester,
  ) async {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });
}
