// Capturas de revisión visual de las preguntas dinámicas por categoría.
//
// NO es un test de regresión: no compara contra un golden guardado, solo
// escribe PNGs en build/capturas_atributos/ para poder MIRAR cómo queda cada
// pantalla sin compilar la app entera. Nunca falla por diferencias de
// píxeles, así que no estorba en CI ni hay que regenerar nada al cambiar un
// color.
//
// Se ejecuta a mano cuando se toca el diseño de estas secciones:
//
//   CAPTURAS=1 flutter test test/atributos_capturas_test.dart
//
// Sin esa variable los tests montan las pantallas igual (así una excepción de
// layout sigue saliendo en la corrida normal) pero no escriben los PNG:
// rasterizar por software cada captura cuesta minutos.
//
// Carga Roboto de verdad desde el SDK porque el entorno de prueba no resuelve
// Google Fonts: con la tipografía de respaldo los anchos se van un 80 % y la
// captura no representaría nada.

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/category_attributes_form.dart';
import 'package:mercadito_um/widgets/product_attributes_section.dart';
import 'package:mercadito_um/widgets/product_card.dart';

const _dirSalida = 'build/capturas_atributos';

/// Escribir los PNG solo se pide a mano, con `CAPTURAS=1`.
final _generarPng = Platform.environment['CAPTURAS'] == '1';

Future<void> _cargarRoboto() async {
  const raiz = '/home/daniel/flutter/bin/cache/artifacts/material_fonts';
  for (final familia in ['Roboto']) {
    final loader = FontLoader(familia);
    for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
      final archivo = File('$raiz/Roboto-$peso.ttf');
      if (!archivo.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.sublistView(archivo.readAsBytesSync())),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _cargarRoboto();
    Directory(_dirSalida).createSync(recursive: true);
  });

  /// Envuelve el widget con el tema real, forzando Roboto como familia para
  /// que el texto se vea en la captura.
  Widget marco(Widget child, {required Color fondo}) {
    final base = AppTheme.light();
    return RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
          primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
        ),
        home: Scaffold(backgroundColor: fondo, body: child),
      ),
    );
  }

  /// El PNG del árbol montado. Se pinta desde el [RepaintBoundary] que [marco]
  /// pone por fuera: el elemento del MaterialApp no es una capa propia y su
  /// renderObject no se puede convertir a imagen.
  Future<Uint8List> pintarAPng(WidgetTester tester) async {
    final objeto = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final imagen = await objeto.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  }

  Future<void> capturar(WidgetTester tester, String nombre) async {
    // Sin CAPTURAS=1 los tests montan igual todas las pantallas —que es lo que
    // atrapa un overflow o una excepción de layout— pero no escriben el PNG:
    // rasterizar por software cada captura tarda minutos, y pagarlos en cada
    // `flutter test` volvería la suite inusable para todo lo demás.
    if (!_generarPng) return;
    File('$_dirSalida/$nombre.png').writeAsBytesSync(await pintarAPng(tester));
  }

  Product producto({
    required String categoria,
    required String nombreCategoria,
    Map<String, dynamic> atributos = const {},
    List<Map<String, dynamic>> destacados = const [],
    String titulo = 'Sudadera Champion talla grande',
    String descripcion = 'Poco uso, sin manchas ni detalles',
  }) {
    return Product.fromJson({
      'id': 'p_1',
      'title': titulo,
      'price': 350,
      'description': descripcion,
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'categoryObj': {'id': categoria, 'name': nombreCategoria, 'emoji': '👕'},
      'images': <String>[],
      'extras': <dynamic>[],
      'views': 128,
      'atributos': atributos,
      'atributosDestacados': destacados,
    });
  }

  testWidgets('captura · formulario de publicar (ropa)', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    var respuestas = <String, dynamic>{
      'precio_negociable': true,
      'lugar_entrega': 'Campus',
      'talla': 'M',
      'estado_ropa': 'Poco uso',
    };

    await tester.pumpWidget(
      marco(
        SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: StatefulBuilder(
            builder: (context, setState) => CategoryAttributesForm(
              categoryId: 'clothes',
              respuestas: respuestas,
              onChanged: (v) => setState(() => respuestas = v),
            ),
          ),
        ),
        fondo: const Color(0xFFFFFFFF),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '01_publicar_ropa');
  });

  testWidgets('captura · formulario con condicionales abiertos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 2, 1100 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    var respuestas = <String, dynamic>{
      'tiene_garantia': true,
      'duracion_garantia': '3 meses',
      'estado_electronico': 'Seminuevo',
      'garantia_vigente': true,
      'con_quien_garantia': 'Best Buy',
      'tiene_desperfecto': false,
    };

    await tester.pumpWidget(
      marco(
        SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: StatefulBuilder(
            builder: (context, setState) => CategoryAttributesForm(
              categoryId: 'electronics',
              respuestas: respuestas,
              onChanged: (v) => setState(() => respuestas = v),
            ),
          ),
        ),
        fondo: const Color(0xFFFFFFFF),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '02_publicar_electronicos_condicionales');
  });

  testWidgets('captura · formulario con selección múltiple (hospedaje)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 2, 1250 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    var respuestas = <String, dynamic>{
      // Con un chip propio en cada pregunta: la captura tiene que mostrar
      // que se ven igual que los del catálogo, con su ✕ para quitarlos.
      'incluye_renta': ['Luz', 'Agua', 'Internet', 'Wifi 300mb'],
      'requisitos': ['Aval', 'Depósito', 'Sin fiadores'],
      'acepta_mascotas': true,
      'exclusivo_para': 'Solo estudiantes',
    };

    await tester.pumpWidget(
      marco(
        SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: StatefulBuilder(
            builder: (context, setState) => CategoryAttributesForm(
              categoryId: 'housing',
              respuestas: respuestas,
              onChanged: (v) => setState(() => respuestas = v),
            ),
          ),
        ),
        fondo: const Color(0xFFFFFFFF),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '03_publicar_hospedaje_multiselect');
  });

  testWidgets('captura · detalle de producto', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 620 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      marco(
        SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ProductAttributesSection(
            product: producto(
              categoria: 'housing',
              nombreCategoria: 'Hospedaje',
              atributos: {
                'acepta_devoluciones': false,
                'precio_negociable': true,
                // Sin `lugar_entrega`: hospedaje ya no la pregunta —una renta
                // se visita, no se entrega— y la sección no la pintaría.
                'incluye_renta': ['Luz', 'Agua', 'Internet', 'Wifi 300mb'],
                'requisitos': ['Aval', 'Depósito', 'Sin fiadores'],
                'acepta_mascotas': true,
                'exclusivo_para': 'Solo estudiantes',
                'monto_deposito': r'$3,000',
                'distancia_universidad': '10 min caminando',
              },
            ),
          ),
        ),
        fondo: const Color(0xFFFFFFFF),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '04_detalle_hospedaje');
  });

  testWidgets('captura · detalle de ropa', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 420 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      marco(
        SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ProductAttributesSection(
            product: producto(
              categoria: 'clothes',
              nombreCategoria: 'Ropa',
              atributos: {
                'acepta_devoluciones': true,
                'precio_negociable': false,
                'talla': 'M',
                'marca': 'Champion',
                'condicion_etiqueta': 'Usado',
                'estado_ropa': 'Poco uso',
                'cambio_talla': true,
              },
            ),
          ),
        ),
        fondo: const Color(0xFFFFFFFF),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '05_detalle_ropa');
  });

  testWidgets('captura · cuadrícula del home con badges', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 320 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    Widget celda(Product p) => SizedBox(
      width: 171,
      height: 171 / 0.64,
      child: ProductCard(product: p, heroEnabled: false),
    );

    await tester.pumpWidget(
      marco(
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              celda(
                producto(
                  categoria: 'clothes',
                  nombreCategoria: 'Ropa',
                  destacados: [
                    {'key': 'talla', 'label': 'Talla', 'value': 'M'},
                    {
                      'key': 'estado_ropa',
                      'label': 'Estado',
                      'value': 'Poco uso',
                    },
                  ],
                ),
              ),
              const SizedBox(width: 12),
              celda(
                producto(
                  categoria: 'books',
                  nombreCategoria: 'Libros',
                  titulo: 'Cálculo de una variable, Stewart',
                  descripcion: 'Con anotaciones a lápiz',
                  destacados: [
                    {
                      'key': 'estado_libro',
                      'label': 'Estado',
                      'value': 'Con detalles/subrayado',
                    },
                    {'key': 'edicion', 'label': 'Edición', 'value': 'Original'},
                  ],
                ),
              ),
            ],
          ),
        ),
        fondo: const Color(0xFFF6F6F4),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '06_home_cuadricula');
  });

  testWidgets('captura · resultados de búsqueda', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 300 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      marco(
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              SizedBox(
                height: 122,
                child: ProductCard(
                  product: producto(
                    categoria: 'clothes',
                    nombreCategoria: 'Ropa',
                    destacados: [
                      {'key': 'talla', 'label': 'Talla', 'value': 'M'},
                      {
                        'key': 'estado_ropa',
                        'label': 'Estado',
                        'value': 'Poco uso',
                      },
                    ],
                  ),
                  horizontal: true,
                  heroEnabled: false,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 122,
                child: ProductCard(
                  product: producto(
                    categoria: 'food',
                    nombreCategoria: 'Comida',
                    titulo: 'Sushi casero por charola',
                    descripcion: 'Hago entregas en el campus',
                    destacados: [
                      {
                        'key': 'opciones_veg',
                        'label': '¿Tienes opciones vegetarianas/veganas?',
                        'value': 'Opción veggie',
                      },
                      {
                        'key': 'tipo_entrega',
                        'label': 'Entrega',
                        'value': 'Entrega a domicilio',
                      },
                    ],
                  ),
                  horizontal: true,
                  heroEnabled: false,
                ),
              ),
            ],
          ),
        ),
        fondo: const Color(0xFFF6F6F4),
      ),
    );
    await tester.pumpAndSettle();
    await capturar(tester, '07_busqueda_resultados');
  });
}
