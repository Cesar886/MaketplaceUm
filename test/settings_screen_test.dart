// Estructura del menú de Configuración.
//
// La mayoría de las filas todavía no hace nada — están puestas para fijar el
// menú antes de que exista el backend detrás. Lo que sí se puede proteger hoy
// es que estén todas, que las que ya tienen pantalla naveguen de verdad, y que
// eliminar cuenta pida confirmación antes de cualquier cosa.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/providers/accent_provider.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/providers/theme_provider.dart';
import 'package:mercadito_um/screens/legal/privacy_screen.dart';
import 'package:mercadito_um/screens/legal/terms_screen.dart';
import 'package:mercadito_um/screens/profile/help_screen.dart';
import 'package:mercadito_um/screens/profile/settings_screen.dart';
import 'package:mercadito_um/widgets/option_tile.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  // La pantalla usa `.tr()`: sin esto pintaría las claves y todas las
  // aserciones de texto en español fallarían.
  setUpAll(inicializarTraducciones);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Viewport alto para que el menú completo quepa sin scroll.
  ///
  /// La alternativa —`scrollUntilVisible` fila por fila— no sirve aquí:
  /// mientras arrastra, el finder no encuentra nada y un `.first` sobre ese
  /// vacío revienta. Con la lista entera montada, cada aserción mira el menú
  /// real sin pelearse con el scroll.
  void viewportAlto(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget pantalla() => appDePrueba(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AccentProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const SettingsScreen(),
    ),
  );

  /// La fila entera, no su texto: `find.text` es ambiguo para "Idioma" (que
  /// también es encabezado) y toca solo el Text, no el ListTile que responde.
  Finder fila(String titulo) => find.widgetWithText(OptionTile, titulo);

  testWidgets('están todas las secciones del menú', (tester) async {
    viewportAlto(tester);
    await pumpEsperandoTraducciones(tester, pantalla());

    for (final seccion in [
      'Apariencia',
      'Sonido y vibración',
      'Idioma',
      'Soporte y legal',
      'Datos',
      'Cuenta',
    ]) {
      expect(find.text(seccion), findsWidgets, reason: 'falta $seccion');
    }
  });

  testWidgets('están todas las filas del menú', (tester) async {
    viewportAlto(tester);
    await pumpEsperandoTraducciones(tester, pantalla());

    for (final fila in [
      'Modo oscuro',
      'Theme',
      'Sonidos de la app',
      'Vibración',
      'Idioma',
      'Centro de ayuda',
      'Reportar un problema',
      'Términos y Condiciones',
      'Política de Privacidad',
      'Aviso de Cookies',
      'Versión de la app',
      'Descargar mis datos',
      'Eliminar cuenta',
    ]) {
      expect(find.text(fila), findsWidgets, reason: 'falta $fila');
    }
  });

  testWidgets('los interruptores de sonido y vibración se mueven', (
    tester,
  ) async {
    viewportAlto(tester);
    await pumpEsperandoTraducciones(tester, pantalla());

    final sonidos = find.ancestor(
      of: find.text('Sonidos de la app'),
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(sonidos).value, isTrue);

    await tester.tap(sonidos);
    await tester.pump();

    expect(tester.widget<SwitchListTile>(sonidos).value, isFalse);
  });

  testWidgets('las filas con pantalla propia navegan de verdad', (
    tester,
  ) async {
    final destinos = <String, Type>{
      'Centro de ayuda': HelpScreen,
      'Términos y Condiciones': TermsScreen,
      'Política de Privacidad': PrivacyScreen,
    };

    viewportAlto(tester);
    await pumpEsperandoTraducciones(tester, pantalla());

    // Un solo montaje y vuelta atrás entre destinos: re-pumpear el mismo
    // árbol no reinicia el Navigator, así que la segunda vuelta seguiría
    // parada en la pantalla que abrió la primera.
    for (final entry in destinos.entries) {
      await tester.tap(fila(entry.key));
      await tester.pumpAndSettle();

      expect(
        find.byType(entry.value),
        findsOneWidget,
        reason: '${entry.key} no abrió su pantalla',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('eliminar cuenta pide confirmación y no borra nada', (
    tester,
  ) async {
    viewportAlto(tester);
    await pumpEsperandoTraducciones(tester, pantalla());

    await tester.tap(fila('Eliminar cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar tu cuenta?'), findsOneWidget);

    // Cancelar cierra sin más.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar tu cuenta?'), findsNothing);

    // Confirmar tampoco borra: por ahora solo avisa que no está disponible.
    await tester.tap(fila('Eliminar cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('próximamente'), findsOneWidget);
  });
}
