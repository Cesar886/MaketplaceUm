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
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/providers/accent_provider.dart';
import 'package:mercadito_um/providers/theme_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Réplica del MaterialApp de `MyApp`, sin su `home` (SplashScreen), que
  /// es la parte que arrastra Firebase y red.
  Widget appDePrueba() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AccentProvider()),
      ],
      child: Builder(
        builder: (context) {
          final theme = context.watch<ThemeProvider>();
          final swatch = context.watch<AccentProvider>().swatch;
          return MaterialApp(
            theme: AppTheme.light(swatch),
            darkTheme: AppTheme.dark(swatch),
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
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  // ─── Color de acento ──────────────────────────────────────────

  /// Vendedor mínimo con un color ya elegido, como lo devolvería el backend.
  Seller sellerConColor(String? colorAcento) => Seller(
    id: 's1',
    name: 'Yo',
    avatarInitials: 'Y',
    major: '',
    rating: 0,
    reviews: 0,
    verified: false,
    colorAcento: colorAcento,
  );

  testWidgets('el color del perfil repinta el tema tras reinstalar', (
    tester,
  ) async {
    // Instalación limpia: SharedPreferences vacío, así que la app arranca
    // con el color de marca. El color solo puede venir del backend.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    var material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.theme!.appBarTheme.backgroundColor, AccentSwatch.navy.fill);

    // Llega el perfil del servidor (lo que hace `sincronizarDesdeBackend`).
    final context = tester.element(find.text('contenido'));
    context.read<AccentProvider>().adoptarDe(sellerConColor('salvia'));
    await tester.pump();

    material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      material.theme!.appBarTheme.backgroundColor,
      AccentSwatch.salvia.fill,
    );
  });

  testWidgets('el color elegido queda cacheado para el próximo arranque', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    final context = tester.element(find.text('contenido'));
    context.read<AccentProvider>().adoptarDe(sellerConColor('wine'));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accent_swatch'), 'wine');
  });

  testWidgets('el caché local pinta antes de que responda el backend', (
    tester,
  ) async {
    // Segundo arranque: el color ya está en disco, así que la app no debe
    // mostrar el color de marca mientras espera la red.
    SharedPreferences.setMockInitialValues({'accent_swatch': 'lavanda'});
    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      material.theme!.appBarTheme.backgroundColor,
      AccentSwatch.lavanda.fill,
    );
  });

  testWidgets('en oscuro el AppBar no se pinta con el pastel', (tester) async {
    SharedPreferences.setMockInitialValues({
      'dark_mode': true,
      'accent_swatch': 'durazno',
    });
    await tester.pumpWidget(appDePrueba());
    await tester.pump();

    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final oscuro = material.darkTheme!;
    expect(oscuro.appBarTheme.backgroundColor, AppColors.darkBackground);
    // Y el relleno de los botones es la variante oscura, no el pastel.
    expect(oscuro.colorScheme.surface, isNot(AccentSwatch.durazno.fill));
    expect(
      oscuro.extension<AppColorSet>()!.primary,
      AccentSwatch.durazno.darkFill,
    );
  });
}
