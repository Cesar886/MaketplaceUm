import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/config/locales.dart';

/// Utilidades para montar pantallas traducidas en widget tests.
///
/// Sin esto, un `pumpWidget` de cualquier pantalla migrada a i18n pinta las
/// CLAVES en vez del texto ('settings.title' en lugar de 'Configuración').
///
/// Por qué NO se usa el camino normal (montar `EasyLocalization` y dejar que
/// su `LocalizationsDelegate` cargue los JSON):
///
/// ese delegate es `async` siempre, y mientras no resuelve, el widget
/// `Localizations` de Flutter no pinta a sus hijos. Dentro de un test el reloj
/// está falseado, así que la carga solo avanza a base de `runAsync`. Funciona
/// para el PRIMER test de un archivo y deja el árbol vacío en todos los
/// siguientes — el síntoma es un `expect` de texto que falla con "Found 0
/// widgets" aunque la clave exista.
///
/// La salida es aprovechar que `'clave'.tr()` sin `context` resuelve contra
/// `Localization.instance`, un singleton. Se carga una vez en `setUpAll` y a
/// partir de ahí toda la app traduce, sin delegate y sin esperas.

/// Carga el diccionario real en el singleton que usa `.tr()`.
///
/// Llamar una vez en `setUpAll`. Lee los JSON de verdad de
/// `assets/translations/`, no un doble: así un test que afirma
/// "Configuración" falla si alguien borra esa clave del archivo.
Future<void> inicializarTraducciones({Locale locale = AppLocales.es}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // easy_localization guarda el idioma elegido en SharedPreferences, y en un
  // test no hay plugin nativo detrás.
  SharedPreferences.setMockInitialValues({});

  Future<Translations> leer(Locale cual) async {
    final crudo = await rootBundle.loadString(
      '${AppLocales.rutaTraducciones}/${cual.languageCode}.json',
    );
    return Translations(jsonDecode(crudo) as Map<String, dynamic>);
  }

  Localization.load(
    locale,
    translations: await leer(locale),
    fallbackTranslations: await leer(AppLocales.fallback),
  );
}

/// `MaterialApp` de prueba con el idioma cableado.
///
/// El `EasyLocalization` de fuera existe solo para que `context.locale`
/// funcione (Configuración lo usa para enseñar el idioma activo). Las
/// traducciones NO salen de él sino del singleton que cargó
/// [inicializarTraducciones], y por eso el `MaterialApp` de dentro va sin
/// `localizationsDelegates` propios: añadirlos reintroduciría la espera
/// asíncrona que rompe los tests a partir del segundo.
///
/// [home] puede traer sus propios providers encima de la pantalla; lo único
/// que importa es que queden por debajo del `MaterialApp`.
Widget appDePrueba(Widget home, {Locale locale = AppLocales.es}) {
  return EasyLocalization(
    supportedLocales: AppLocales.localesSoportados,
    path: AppLocales.rutaTraducciones,
    fallbackLocale: AppLocales.fallback,
    startLocale: locale,
    child: MaterialApp(home: home),
  );
}

/// Monta un árbol de [appDePrueba] y lo deja listo para los `expect`.
Future<void> pumpEsperandoTraducciones(
  WidgetTester tester,
  Widget arbolEnvuelto,
) async {
  await tester.pumpWidget(arbolEnvuelto);
  await tester.pump();
}
