// Capturas de revisión visual del menú de categorías que abre el logo, en las
// dos presentaciones propuestas y en los dos temas.
//
// Igual que home_card_capturas_test.dart: no compara contra goldens, solo
// escribe PNGs para poder mirar y elegir.
//
//   CAPTURAS=1 flutter test test/menu_categorias_capturas_test.dart
//
// Sin esa variable el archivo se salta entero: es una herramienta de mirar,
// no una prueba de regresión, y no tiene por qué correr en cada `flutter
// test`. Cuando sí corre, el entorno de pruebas no puede bajar las
// tipografías de Google (no hay red) y google_fonts reporta un error por
// familia DESPUÉS de que cada caso terminó; los PNG ya quedaron escritos y
// correctos, con Roboto en lugar de WorkSans. Es la misma limitación que
// arrastran las otras capturas del repo.

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/config/locales.dart';
import 'package:mercadito_um/mock_data.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/providers/theme_provider.dart';
import 'package:mercadito_um/widgets/category_logo_menu.dart';

import 'helpers/localizacion_de_prueba.dart';

const _dirSalida = 'build/capturas_menu_categorias';
final _generarPng = Platform.environment['CAPTURAS'] == '1';

/// Ver la nota de home_card_capturas_test.dart: sin esto el texto sale en
/// cajas de tofu porque las familias de Google Fonts no se descargan aquí.
Future<void> _cargarRoboto() async {
  // La ruta del SDK no es fija (snap, tooling local, CI), así que se buscan
  // varias y se cae a las fuentes del sistema: es preferible una captura con
  // DejaVu a una llena de cajitas de tofu.
  final candidatos = <String>[
    for (final sdk in [
      Platform.environment['FLUTTER_ROOT'],
      '/home/daniel/AppMarinerita/.tooling/flutter',
      '${Platform.environment['HOME']}/flutter',
      '/snap/flutter/current/usr/lib/flutter',
    ])
      if (sdk != null)
        for (final peso in ['Regular', 'Medium', 'Bold', 'Black'])
          '$sdk/bin/cache/artifacts/material_fonts/Roboto-$peso.ttf',
    for (final peso in ['', '-Bold'])
      '/usr/share/fonts/truetype/dejavu/DejaVuSans$peso.ttf',
  ];

  final datos = <ByteData>[];
  for (final ruta in candidatos) {
    final archivo = File(ruta);
    if (!archivo.existsSync()) continue;
    datos.add(ByteData.sublistView(archivo.readAsBytesSync()));
    // Con el primer SDK que responda basta: mezclar Roboto y DejaVu bajo la
    // misma familia deja al motor eligiendo pesos al azar.
    if (datos.length == 4) break;
  }
  if (datos.isEmpty) return;

  const variantes = [
    '',
    '_100',
    '_200',
    '_300',
    '_regular',
    '_500',
    '_600',
    '_700',
    '_800',
    '_900',
  ];
  for (final familia in <String>[
    'Roboto',
    for (final base in ['Baloo2', 'WorkSans'])
      for (final v in variantes) '$base$v',
  ]) {
    final loader = FontLoader(familia);
    for (final d in datos) {
      loader.addFont(Future.value(d));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Sin esto, `AppTypography` intenta bajar las tipografías de
    // fonts.gstatic.com. En el reloj falso del test esa petición nunca vuelve
    // y el archivo se cuelga; dentro de `runAsync` sí vuelve, pero como
    // excepción. Roboto (cargado abajo) cubre el hueco.
    GoogleFonts.config.allowRuntimeFetching = false;
    inicializarTraducciones(locale: AppLocales.es);
    await _cargarRoboto();
    Directory(_dirSalida).createSync(recursive: true);
  });

  /// Publicaciones por categoría de mentira, solo para que el panel lateral
  /// muestre sus contadores en la captura.
  int? conteo(String id) =>
      {'books': 24, 'notes': 12, 'electronics': 8}[id] ?? 3;

  /// Con la descarga apagada, google_fonts protesta una vez por cada familia
  /// que pide `AppTypography`. Es ruido del entorno, no del widget: las
  /// capturas se pintan igual con Roboto. Va dentro de la prueba porque
  /// `testWidgets` reinstala su propio `onError` en cada una.
  void silenciarGoogleFonts() {
    final reportarError = FlutterError.onError;
    FlutterError.onError = (detalles) {
      if (detalles.exception.toString().contains('GoogleFonts')) return;
      reportarError?.call(detalles);
    };
  }

  Future<void> montar(
    WidgetTester tester, {
    required CategoryMenuStyle estilo,
    required ThemeData tema,
    String? seleccionada,
  }) async {
    silenciarGoogleFonts();
    tester.view.physicalSize = const Size(390 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // El bloque "Cuenta y ajustes" del panel lateral lee AuthProvider y
    // ThemeProvider (context.watch); ThemeProvider persiste con
    // SharedPreferences, así que necesita el mock inicial.
    SharedPreferences.setMockInitialValues({});

    final colores = tema.extension<AppColorSet>()!;

    await tester.pumpWidget(
      RepaintBoundary(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: tema.copyWith(
              textTheme: tema.textTheme.apply(fontFamily: 'Roboto'),
              primaryTextTheme: tema.primaryTextTheme.apply(
                fontFamily: 'Roboto',
              ),
            ),
            home: Scaffold(
              backgroundColor: colores.background,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // La banda navy del home, recortada a lo que importa aquí:
                  // el logo a la izquierda y un par de botones a la derecha.
                  Container(
                    color: colores.primary,
                    padding: const EdgeInsets.fromLTRB(16, 44, 12, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: CategoryLogoMenu(
                              style: estilo,
                              categories: mockCategories,
                              selectedCategoryId: seleccionada,
                              countFor: conteo,
                              onCategorySelected: (_) {},
                              onClearCategory: () {},
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  // Un feed de relleno: sin algo debajo no se aprecia cuánto
                  // tapa cada opción, que es media decisión.
                  Expanded(
                    child: GridView.count(
                      padding: const EdgeInsets.all(18),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72,
                      children: [
                        for (var i = 0; i < 6; i++)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colores.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colores.border),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(CategoryLogoMenu)));
    await tester.pumpAndSettle();
  }

  Future<void> capturar(WidgetTester tester, String nombre) async {
    if (!_generarPng) return;
    final objeto = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    // `runAsync`: codificar el PNG es trabajo del engine, fuera del reloj
    // falso del test. Con el menú abierto hay una capa de overlay viva y el
    // await se quedaba colgado esperando un tiempo que nunca corre.
    await tester.runAsync(() async {
      final imagen = await objeto.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ImageByteFormat.png);
      File(
        '$_dirSalida/$nombre.png',
      ).writeAsBytesSync(datos!.buffer.asUint8List());
      imagen.dispose();
    });
  }

  /// Cierra el menú antes de que termine la prueba: dejarlo abierto deja vivo
  /// el overlay (o la ruta modal) del que cuelga la animación, y el
  /// desmontaje se queda esperándola.
  Future<void> cerrar(WidgetTester tester) async {
    await tester.tapAt(const Offset(370, 700));
    await tester.pumpAndSettle();
  }

  testWidgets('captura · opción A dropdown (claro)', (tester) async {
    await montar(
      tester,
      estilo: CategoryMenuStyle.dropdown,
      tema: AppTheme.light(),
    );
    await capturar(tester, 'A1_dropdown_claro');
    await cerrar(tester);
  }, skip: !_generarPng);

  testWidgets('captura · opción A dropdown (oscuro)', (tester) async {
    await montar(
      tester,
      estilo: CategoryMenuStyle.dropdown,
      tema: AppTheme.dark(),
      seleccionada: 'books',
    );
    await capturar(tester, 'A2_dropdown_oscuro_con_filtro');
    await cerrar(tester);
  }, skip: !_generarPng);

  testWidgets('captura · opción B sidebar (claro)', (tester) async {
    await montar(
      tester,
      estilo: CategoryMenuStyle.sidebar,
      tema: AppTheme.light(),
    );
    await capturar(tester, 'B1_sidebar_claro');
    await cerrar(tester);
  }, skip: !_generarPng);

  testWidgets('captura · opción B sidebar (oscuro)', (tester) async {
    await montar(
      tester,
      estilo: CategoryMenuStyle.sidebar,
      tema: AppTheme.dark(),
      seleccionada: 'books',
    );
    await capturar(tester, 'B2_sidebar_oscuro_con_filtro');
    await cerrar(tester);
  }, skip: !_generarPng);
}
