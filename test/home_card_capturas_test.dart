// Capturas de revisión visual de la tarjeta del feed (ProductCard) en la
// geometría REAL del home: ancho 390, 2 columnas, childAspectRatio 0.64,
// padding 18 y crossAxisSpacing 12 — los mismos números de home_screen.dart.
//
// Igual que atributos_capturas_test.dart: no compara contra goldens, solo
// escribe PNGs en build/capturas_home/ para poder mirar el resultado.
//
//   CAPTURAS=1 flutter test test/home_card_capturas_test.dart

import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/product_card.dart';

const _dirSalida = 'build/capturas_home';
final _generarPng = Platform.environment['CAPTURAS'] == '1';

/// El entorno de prueba no descarga Google Fonts, así que `AppTypography`
/// pide familias ("Baloo2", "WorkSans" y sus variantes `Familia_peso`) que no
/// existen y el texto sale en cajas de tofu. Se registra Roboto bajo TODOS
/// esos nombres: la captura no reproduce la tipografía real, pero sí los
/// tamaños, pesos y saltos de línea, que es lo que se está revisando.
Future<void> _cargarRoboto() async {
  const raiz = '/home/daniel/flutter/bin/cache/artifacts/material_fonts';
  final datos = <ByteData>[];
  for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
    final archivo = File('$raiz/Roboto-$peso.ttf');
    if (!archivo.existsSync()) continue;
    datos.add(ByteData.sublistView(archivo.readAsBytesSync()));
  }

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
  final familias = <String>[
    'Roboto',
    for (final base in ['Baloo2', 'WorkSans'])
      for (final v in variantes) '$base$v',
  ];

  for (final familia in familias) {
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
    await _cargarRoboto();
    Directory(_dirSalida).createSync(recursive: true);
  });

  Widget marco(Widget child, {required ThemeData tema, required Color fondo}) {
    return RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tema.copyWith(
          textTheme: tema.textTheme.apply(fontFamily: 'Roboto'),
          primaryTextTheme: tema.primaryTextTheme.apply(fontFamily: 'Roboto'),
        ),
        home: Scaffold(backgroundColor: fondo, body: child),
      ),
    );
  }

  Future<void> capturar(WidgetTester tester, String nombre) async {
    if (!_generarPng) return;
    final objeto = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final imagen = await objeto.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ImageByteFormat.png);
    File('$_dirSalida/$nombre.png').writeAsBytesSync(datos!.buffer.asUint8List());
  }

  Product producto({
    required String id,
    required String titulo,
    required num precio,
    num? precioAnterior,
    String descripcion = 'Poco uso, sin manchas ni detalles, la vendo por mudanza',
    String categoria = 'clothes',
    String nombreCategoria = 'Ropa',
    List<Map<String, dynamic>> destacados = const [],
    int vistas = 128,
    String publicado = 'hace 2 días',
    bool destacado = false,
    String? estado,
    String? proximoDia,
    String? abreA,
  }) {
    return Product.fromJson({
      'id': id,
      'title': titulo,
      'price': precio,
      if (precioAnterior != null) 'previousPrice': precioAnterior,
      'description': descripcion,
      'publishedAgo': publicado,
      'seller': 's_1',
      'categoryObj': {'id': categoria, 'name': nombreCategoria, 'emoji': '👕'},
      'images': <String>[],
      'extras': <dynamic>[],
      'views': vistas,
      'featured': destacado,
      'atributos': <String, dynamic>{},
      'atributosDestacados': destacados,
      if (estado != null) 'computedStatus': estado,
      if (proximoDia != null) 'nextAvailableDay': proximoDia,
      if (abreA != null) 'opensAt': abreA,
    });
  }

  List<Product> catalogo() => [
    producto(
      id: 'p1',
      titulo: 'Sudadera Champion talla grande casi nueva',
      precio: 350,
      destacados: [
        {'label': 'Talla', 'value': 'M'},
        {'label': 'Estado', 'value': 'Poco uso'},
      ],
    ),
    producto(
      id: 'p2',
      titulo: 'iPhone 13 Pro 256GB',
      precio: 8500,
      precioAnterior: 11000,
      categoria: 'electronics',
      nombreCategoria: 'Electrónicos',
      destacados: [
        {'label': 'Estado', 'value': 'Seminuevo'},
        {'label': 'Garantía', 'value': 'Con garantía vigente'},
      ],
      vistas: 2340,
    ),
    producto(
      id: 'p3',
      titulo: 'Cuarto amueblado a 5 min del campus con todos los servicios',
      precio: 3200,
      categoria: 'housing',
      nombreCategoria: 'Hospedaje',
      destacados: [
        {'label': 'Mascotas', 'value': 'Acepta mascotas'},
      ],
      estado: 'availableOtherDay',
      proximoDia: 'lunes',
      publicado: 'hace 3 semanas',
    ),
    producto(
      id: 'p4',
      titulo: 'Cálculo de una variable — Stewart 8a edición',
      precio: 250,
      categoria: 'books',
      nombreCategoria: 'Libros',
      destacado: true,
      destacados: [
        {'label': 'Estado', 'value': 'Nuevo'},
      ],
      vistas: 42,
      publicado: 'hace 5 min',
    ),
    producto(
      id: 'p5',
      titulo: 'Bicicleta de montaña rodada 29',
      precio: 4800,
      categoria: 'sports',
      nombreCategoria: 'Deportes',
      destacados: const [],
      estado: 'soldOut',
    ),
    producto(
      id: 'p6',
      titulo: 'Pastel de tres leches por rebanada',
      precio: 45,
      categoria: 'food',
      nombreCategoria: 'Comida',
      destacados: [
        {'label': 'Estado', 'value': 'Hecho hoy'},
      ],
      estado: 'closed',
      abreA: '9:00 am',
      vistas: 890,
    ),
  ];

  Future<void> montarGrid(WidgetTester tester, ThemeData tema, Color fondo) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      marco(
        GridView.count(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.62,
          children: [
            for (final p in catalogo()) ProductCard(product: p, onTap: () {}),
          ],
        ),
        tema: tema,
        fondo: fondo,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('captura · grid del home (claro)', (tester) async {
    await montarGrid(tester, AppTheme.light(), const Color(0xFFF7F5F1));
    await capturar(tester, '01_home_grid_claro');
  });

  testWidgets('captura · grid del home (oscuro)', (tester) async {
    await montarGrid(tester, AppTheme.dark(), const Color(0xFF12100E));
    await capturar(tester, '02_home_grid_oscuro');
  });

  testWidgets('captura · tarjeta horizontal', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 560 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      marco(
        ListView(
          padding: const EdgeInsets.all(18),
          children: [
            for (final p in catalogo().take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  height: 130,
                  child: ProductCard(product: p, horizontal: true, onTap: () {}),
                ),
              ),
          ],
        ),
        tema: AppTheme.light(),
        fondo: const Color(0xFFF7F5F1),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await capturar(tester, '03_horizontal_claro');
  });
}
