// Capturas de revisión visual del encabezado del perfil público
// (SellerProfileHeader) al ancho real del teléfono. No compara contra
// goldens: solo escribe PNGs en build/capturas_perfil/ para poder mirar el
// diseño del banner.
//
//   CAPTURAS=1 flutter test test/perfil_banner_capturas_test.dart

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/screens/seller_profile_screen.dart';
import 'package:mercadito_um/utils/estado_conexion.dart';
import 'package:mercadito_um/widgets/seller_profile_header.dart';
import 'package:mercadito_um/widgets/seller_profile_skeleton.dart';

const _dirSalida = 'build/capturas_perfil';
final _generarPng = Platform.environment['CAPTURAS'] == '1';

/// El entorno de prueba no descarga Google Fonts, así que `AppTypography`
/// pide familias ("Baloo2", "WorkSans" y sus variantes `Familia_peso`) que no
/// existen y el texto sale en cajas de tofu. Se registra Roboto —el que ya
/// trae el SDK— bajo todos esos nombres: la captura no reproduce la
/// tipografía real, pero sí tamaños, pesos y saltos de línea.
Future<void> _cargarRoboto() async {
  // La caché del SDK está en un sitio distinto según cómo se instaló Flutter
  // (snap, tarball en ~/flutter, /opt), así que se prueban los candidatos en
  // vez de fijar una ruta que solo funciona en una máquina.
  final raices = [
    for (final base in [
      '${Platform.environment['HOME']}/snap/flutter/common/flutter',
      '${Platform.environment['HOME']}/flutter',
      '/opt/flutter',
    ])
      '$base/bin/cache/artifacts/material_fonts',
  ];
  final raiz = raices.firstWhere(
    (r) => Directory(r).existsSync(),
    orElse: () => '',
  );
  final datos = <ByteData>[];
  for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
    final archivo = File('$raiz/Roboto-$peso.ttf');
    if (!archivo.existsSync()) continue;
    datos.add(ByteData.sublistView(archivo.readAsBytesSync()));
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
    // `runAsync` (necesario para codificar el PNG) deja que google_fonts
    // intente bajar las tipografías de verdad contra la red y falle. Con
    // Roboto ya registrado bajo esos nombres, la descarga no aporta nada,
    // así que se apaga y se ignora la queja que suelta al no encontrarlas.
    GoogleFonts.config.allowRuntimeFetching = false;
    if (_generarPng) {
      final reportarOriginal = reportTestException;
      reportTestException = (details, descripcion) {
        if (details.exception.toString().contains('GoogleFonts')) return;
        reportarOriginal(details, descripcion);
      };
    }
    await _cargarRoboto();
    Directory(_dirSalida).createSync(recursive: true);
  });

  Seller vendedor({
    String name = 'Panadería La Espiga',
    String major = 'Negocio',
    String tipoCuenta = 'negocio',
    String? descripcion =
        'Pan dulce y salado horneado el mismo día. Pedidos por mensaje, entrega en campus.',
    String? colorAcento,
    bool elite = false,
  }) {
    return Seller(
      id: 's_1',
      name: name,
      avatarInitials: 'PE',
      major: major,
      rating: 4.9,
      reviews: 32,
      verified: true,
      tipoCuenta: tipoCuenta,
      businessDescription: descripcion,
      colorAcento: colorAcento,
      vendedorConfiable: true,
      respondeRapido: true,
      rachaSemanas: 6,
      aniversarioAnios: 1,
      leyendaMercadito: elite,
      vendedorDeOro: elite,
      ratingPerfecto: elite,
      cienCincoEstrellas: elite,
      siempreResponde: elite,
      respuestaInstantanea: elite,
      esVendedorNuevo: elite,
      enigmaPosicion: elite ? 3 : null,
    );
  }

  Future<void> montarYCapturar(
    WidgetTester tester,
    String nombre, {
    required Seller seller,
    required ThemeData tema,
    required Color fondo,
    double alto = 620,
  }) async {
    tester.view.physicalSize = Size(390, alto);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tema.copyWith(
            textTheme: tema.textTheme.apply(fontFamily: 'Roboto'),
            primaryTextTheme: tema.primaryTextTheme.apply(fontFamily: 'Roboto'),
          ),
          home: Scaffold(
            backgroundColor: fondo,
            appBar: AppBar(title: const Text('Perfil')),
            body: ListView(
              padding: EdgeInsets.zero,
              children: [
                SellerProfileHeader(
                  seller: seller,
                  estadoConexion: EstadoConexion.desconocido,
                  colorBanner: colorBannerDePrueba(tema),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final excepcion = tester.takeException();
    if (_generarPng) {
      final objeto = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final imagen = objeto.toImageSync(pixelRatio: 2);
      final datos = await tester.runAsync(
        () => imagen.toByteData(format: ImageByteFormat.png),
      );
      File(
        '$_dirSalida/$nombre.png',
      ).writeAsBytesSync(datos!.buffer.asUint8List());
    }
    expect(excepcion, isNull);
  }

  testWidgets('negocio, tema claro', (tester) async {
    await montarYCapturar(
      tester,
      'negocio_claro',
      seller: vendedor(),
      tema: AppTheme.light(),
      fondo: AppColors.background,
    );
  });

  // El caso que dio pie a esto: una cuenta que las ganó TODAS. No hay tope
  // de cuántas se pintan, así que lo que se revisa aquí es que la fila se
  // reparta en varias líneas sin desbordar.
  testWidgets('todas las insignias, tema claro', (tester) async {
    await montarYCapturar(
      tester,
      'todas_las_insignias_claro',
      seller: vendedor(elite: true),
      tema: AppTheme.light(),
      fondo: AppColors.background,
      alto: 900,
    );
  });

  // La pantalla entera con el acento del vendedor: AppBar arriba y botón de
  // contactar abajo, los dos en el color que eligió él y no el visitante.
  // Es lo que se revisa aquí — que los tres bloques se lean como una sola
  // pieza y no como un banner de color pegado sobre una pantalla neutra.
  testWidgets('pantalla con el acento del vendedor, tema claro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final seller = vendedor(colorAcento: 'wine');
    final tema = temaDeVendedor(seller, Brightness.light);
    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tema.copyWith(
            textTheme: tema.textTheme.apply(fontFamily: 'Roboto'),
            primaryTextTheme: tema.primaryTextTheme.apply(fontFamily: 'Roboto'),
          ),
          home: Builder(
            builder: (context) {
              final colorBanda = colorDeBannerDeVendedor(
                seller,
                Brightness.light,
              );
              return Scaffold(
                // Igual que la pantalla real: la banda pasa por detrás de la
                // AppBar, que va sin fondo propio. Lo que se revisa en la
                // captura es justo eso — que no quede una línea donde antes
                // terminaba la barra y empezaba el banner.
                extendBodyBehindAppBar: true,
                appBar: AppBar(
                  title: const Text('Perfil'),
                  backgroundColor: Colors.transparent,
                  foregroundColor: tintaSobreBanda(colorBanda),
                  titleTextStyle: tema.appBarTheme.titleTextStyle?.copyWith(
                    color: tintaSobreBanda(colorBanda),
                    fontFamily: 'Roboto',
                  ),
                  iconTheme: IconThemeData(color: tintaSobreBanda(colorBanda)),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                ),
                body: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SellerProfileHeader(
                      seller: seller,
                      estadoConexion: EstadoConexion.desconocido,
                      colorBanner: colorBanda,
                      espacioSuperior:
                          MediaQuery.paddingOf(context).top + kToolbarHeight,
                    ),
                  ],
                ),
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: Icon(
                        Icons.chat_bubble,
                        color: context.colors.onPrimary,
                      ),
                      label: const Text('Contactar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: context.colors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final excepcion = tester.takeException();
    if (_generarPng) {
      final objeto = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final imagen = objeto.toImageSync(pixelRatio: 2);
      final datos = await tester.runAsync(
        () => imagen.toByteData(format: ImageByteFormat.png),
      );
      File(
        '$_dirSalida/pantalla_acento_vendedor.png',
      ).writeAsBytesSync(datos!.buffer.asUint8List());
    }
    expect(excepcion, isNull);
  });

  testWidgets('estudiante sin descripción, tema claro', (tester) async {
    await montarYCapturar(
      tester,
      'estudiante_claro',
      seller: vendedor(
        name: 'Mariana Peña',
        major: 'Estudiante',
        tipoCuenta: 'estudiante',
        descripcion: null,
      ),
      tema: AppTheme.light(),
      fondo: AppColors.background,
    );
  });

  testWidgets('nombre largo sin descripción, tema claro', (tester) async {
    await montarYCapturar(
      tester,
      'nombre_largo_claro',
      seller: vendedor(
        name: 'Comercializadora y Papelería del Campus Universitario',
        descripcion: null,
      ),
      tema: AppTheme.light(),
      fondo: AppColors.background,
    );
  });

  // El skeleton se captura junto al header para poder comparar de un
  // vistazo que la cabecera no salta al terminar de cargar.
  testWidgets('skeleton, tema claro', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tema = AppTheme.light();
    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tema,
          home: Scaffold(
            backgroundColor: AppColors.background,
            extendBodyBehindAppBar: true,
            // Sin fondo, igual que en la pantalla real: el esqueleto ocupa
            // también el sitio de la barra.
            appBar: AppBar(
              title: const Text('Perfil'),
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.ink,
              titleTextStyle: tema.appBarTheme.titleTextStyle?.copyWith(
                color: AppColors.ink,
                fontFamily: 'Roboto',
              ),
              iconTheme: const IconThemeData(color: AppColors.ink),
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
            ),
            body: const SellerProfileSkeleton(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    if (!_generarPng) return;
    final objeto = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final imagen = objeto.toImageSync(pixelRatio: 2);
    final datos = await tester.runAsync(
      () => imagen.toByteData(format: ImageByteFormat.png),
    );
    File(
      '$_dirSalida/skeleton_claro.png',
    ).writeAsBytesSync(datos!.buffer.asUint8List());
  });

  testWidgets('negocio, tema oscuro', (tester) async {
    await montarYCapturar(
      tester,
      'negocio_oscuro',
      seller: vendedor(),
      tema: AppTheme.dark(),
      fondo: AppColors.darkBackground,
    );
  });
}

Color colorBannerDePrueba(ThemeData tema) =>
    tema.extension<AppColorSet>()!.primary;
