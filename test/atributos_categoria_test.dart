// Tests de las preguntas dinámicas por categoría, del lado de Flutter:
// el parseo del modelo, la depuración de respuestas, el formulario de
// publicar y la sección del detalle.
//
// El caso que más vale proteger es el del campo condicional: el usuario
// prende "¿tiene garantía?", escribe cuánto dura, y lo vuelve a apagar. Si
// ese texto sobrevive al envío, el detalle termina mostrando una garantía en
// un producto que declara no tenerla — y nadie lo nota hasta que un comprador
// reclama.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/constants/atributos_categoria.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/category_attributes_form.dart';
import 'package:mercadito_um/widgets/product_attributes_section.dart';

void main() {
  Map<String, dynamic> productoJson({
    String categoria = 'clothes',
    Map<String, dynamic>? atributos,
    List<Map<String, dynamic>>? destacados,
  }) {
    return {
      'id': 'p_1',
      'title': 'Sudadera',
      'price': 350,
      'description': 'Poco uso',
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'categoryObj': {'id': categoria, 'name': 'Ropa', 'emoji': '👕'},
      'images': <String>[],
      'extras': <dynamic>[],
      if (atributos != null) 'atributos': atributos,
      if (destacados != null) 'atributosDestacados': destacados,
    };
  }

  Widget envolver(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  // ─── Modelo ────────────────────────────────────────────────

  group('Product.fromJson', () {
    test('sin el campo, atributos queda como mapa vacío y no como null', () {
      // Todas las publicaciones anteriores a esta feature llegan así.
      final producto = Product.fromJson(productoJson());
      expect(producto.atributos, isEmpty);
      expect(producto.atributosDestacados, isEmpty);
    });

    test('las listas se normalizan a List<String>', () {
      // El decodificador de JSON entrega List<dynamic>; sin normalizar aquí,
      // el cast revienta en la pantalla que la consuma.
      final producto = Product.fromJson(
        productoJson(
          categoria: 'housing',
          atributos: {
            'incluye_renta': ['Luz', 'Internet'],
          },
        ),
      );
      expect(producto.atributos['incluye_renta'], isA<List<String>>());
      expect(producto.atributos['incluye_renta'], ['Luz', 'Internet']);
    });

    test('conserva booleanos y textos con su tipo', () {
      final producto = Product.fromJson(
        productoJson(atributos: {'talla': 'M', 'cambio_talla': true}),
      );
      expect(producto.atributos['talla'], 'M');
      expect(producto.atributos['cambio_talla'], isTrue);
    });

    test('un atributos malformado no rompe el parseo', () {
      final json = productoJson()..['atributos'] = 'no soy un mapa';
      expect(Product.fromJson(json).atributos, isEmpty);
    });

    test('parsea los destacados que resolvió el servidor', () {
      final producto = Product.fromJson(
        productoJson(
          destacados: [
            {'key': 'talla', 'label': 'Talla', 'value': 'M'},
          ],
        ),
      );
      expect(producto.atributosDestacados.single.value, 'M');
      expect(producto.atributosDestacados.single.key, 'talla');
    });
  });

  // ─── Depuración de respuestas ──────────────────────────────

  group('depurarRespuestas', () {
    test('descarta las respuestas de otra categoría', () {
      final limpio = depurarRespuestas({'talla': 'M', 'edicion': 'Original'}, 'books');
      expect(limpio, {'edicion': 'Original'});
    });

    test('conserva las generales en cualquier categoría', () {
      final limpio = depurarRespuestas({'precio_negociable': true}, 'food');
      expect(limpio, {'precio_negociable': true});
    });

    test('descarta el condicional si su padre está apagado', () {
      final limpio = depurarRespuestas(
        {'tiene_garantia': false, 'duracion_garantia': '6 meses'},
        'books',
      );
      expect(limpio, {'tiene_garantia': false});
    });

    test('conserva el condicional si su padre está encendido', () {
      final limpio = depurarRespuestas(
        {'tiene_garantia': true, 'duracion_garantia': '6 meses'},
        'books',
      );
      expect(limpio['duracion_garantia'], '6 meses');
    });

    test('descarta textos vacíos y listas vacías', () {
      final limpio = depurarRespuestas(
        {'talla': '   ', 'marca': 'Nike'},
        'clothes',
      );
      expect(limpio, {'marca': 'Nike'});
    });

    test('recorta los espacios de los textos', () {
      expect(depurarRespuestas({'talla': ' M '}, 'clothes'), {'talla': 'M'});
    });

    test('una categoría desconocida deja solo las generales', () {
      final limpio = depurarRespuestas(
        {'precio_negociable': true, 'talla': 'M'},
        'categoria_retirada',
      );
      expect(limpio, {'precio_negociable': true});
    });
  });

  // ─── Formulario de publicar ────────────────────────────────

  group('CategoryAttributesForm', () {
    /// Monta el formulario con estado real, como lo usa la pantalla de
    /// publicar, y expone lo último que se reportó por onChanged.
    Future<Map<String, dynamic> Function()> montar(
      WidgetTester tester, {
      required String categoria,
      Map<String, dynamic> iniciales = const {},
    }) async {
      var respuestas = Map<String, dynamic>.from(iniciales);
      await tester.pumpWidget(
        envolver(
          StatefulBuilder(
            builder: (context, setState) => CategoryAttributesForm(
              categoryId: categoria,
              respuestas: respuestas,
              onChanged: (v) => setState(() => respuestas = v),
            ),
          ),
        ),
      );
      return () => respuestas;
    }

    testWidgets('pinta las generales más las de la categoría', (tester) async {
      await montar(tester, categoria: 'books');
      expect(find.text('¿El precio es negociable?'), findsOneWidget);
      expect(find.text('Estado del libro'), findsOneWidget);
      // Y nada de otra categoría.
      expect(find.text('Estado de la prenda'), findsNothing);
    });

    testWidgets('responder sí a un booleano lo guarda como true', (tester) async {
      final leer = await montar(tester, categoria: 'books');

      final fila = find.ancestor(
        of: find.text('¿El precio es negociable?'),
        matching: find.byType(Row),
      );
      await tester.tap(find.descendant(of: fila.first, matching: find.text('Sí')));
      await tester.pump();

      expect(leer()['precio_negociable'], isTrue);
    });

    testWidgets('volver a tocar la misma opción deja la pregunta sin responder', (
      tester,
    ) async {
      // Sin esto, tocar por accidente una pregunta opcional la vuelve
      // irreversible.
      final leer = await montar(tester, categoria: 'books');
      final fila = find.ancestor(
        of: find.text('¿El precio es negociable?'),
        matching: find.byType(Row),
      );
      final si = find.descendant(of: fila.first, matching: find.text('Sí'));

      await tester.tap(si);
      await tester.pump();
      await tester.tap(si);
      await tester.pump();

      expect(leer().containsKey('precio_negociable'), isFalse);
    });

    testWidgets('el campo condicional aparece solo al encender su padre', (
      tester,
    ) async {
      await montar(tester, categoria: 'books');
      expect(find.text('¿Cuánto dura la garantía?'), findsNothing);

      final fila = find.ancestor(
        of: find.text('¿Tiene garantía?'),
        matching: find.byType(Row),
      );
      await tester.tap(find.descendant(of: fila.first, matching: find.text('Sí')));
      await tester.pumpAndSettle();

      expect(find.text('¿Cuánto dura la garantía?'), findsOneWidget);
    });

    testWidgets('apagar el padre borra lo que se escribió en el hijo', (
      tester,
    ) async {
      final leer = await montar(
        tester,
        categoria: 'books',
        iniciales: {'tiene_garantia': true, 'duracion_garantia': '6 meses'},
      );
      expect(leer()['duracion_garantia'], '6 meses');

      final fila = find.ancestor(
        of: find.text('¿Tiene garantía?'),
        matching: find.byType(Row),
      );
      await tester.tap(find.descendant(of: fila.first, matching: find.text('No')));
      await tester.pumpAndSettle();

      expect(leer().containsKey('duracion_garantia'), isFalse);
      expect(find.text('¿Cuánto dura la garantía?'), findsNothing);
    });

    testWidgets('reencender el padre no deja texto fantasma en el hijo', (
      tester,
    ) async {
      // El campo condicional tiene su propio TextEditingController, que no
      // vive en el mapa de respuestas. Si al apagar el padre se borra el
      // valor pero el controller conserva el texto, al reencenderlo el
      // usuario ve "6 meses" escrito y publica sin esa garantía: lo que se
      // ve y lo que se manda dejan de ser lo mismo.
      final leer = await montar(
        tester,
        categoria: 'books',
        iniciales: {'tiene_garantia': true, 'duracion_garantia': '6 meses'},
      );
      final fila = find.ancestor(
        of: find.text('¿Tiene garantía?'),
        matching: find.byType(Row),
      );

      await tester.tap(find.descendant(of: fila.first, matching: find.text('No')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: fila.first, matching: find.text('Sí')));
      await tester.pumpAndSettle();

      expect(find.text('¿Cuánto dura la garantía?'), findsOneWidget);
      expect(
        find.text('6 meses'),
        findsNothing,
        reason: 'el campo reaparece con texto que ya no está en las respuestas',
      );
      expect(leer().containsKey('duracion_garantia'), isFalse);
    });

    testWidgets('elegir una opción de un select la guarda', (tester) async {
      final leer = await montar(tester, categoria: 'books');
      await tester.tap(find.text('Copia/Fotocopia'));
      await tester.pump();
      expect(leer()['edicion'], 'Copia/Fotocopia');
    });

    testWidgets('el multiselect acumula y ordena según el catálogo', (
      tester,
    ) async {
      final leer = await montar(tester, categoria: 'housing');

      // Se tocan en desorden a propósito: el orden guardado no debe depender
      // de en qué orden fue tocando el usuario.
      await tester.tap(find.text('Internet'));
      await tester.pump();
      await tester.tap(find.text('Luz'));
      await tester.pump();

      expect(leer()['incluye_renta'], ['Luz', 'Internet']);
    });

    testWidgets('deseleccionar el último valor quita la respuesta entera', (
      tester,
    ) async {
      final leer = await montar(tester, categoria: 'housing');
      await tester.tap(find.text('Agua'));
      await tester.pump();
      await tester.tap(find.text('Agua'));
      await tester.pump();
      expect(leer().containsKey('incluye_renta'), isFalse);
    });

    testWidgets('escribir en un campo de texto lo guarda recortado', (
      tester,
    ) async {
      final leer = await montar(tester, categoria: 'clothes');
      await tester.enterText(
        find.widgetWithText(TextField, 'Talla'),
        '  M  ',
      );
      await tester.pump();
      expect(leer()['talla'], 'M');
    });

    testWidgets('los valores iniciales precargan el formulario', (tester) async {
      // Es el caso de editar una publicación existente.
      await montar(
        tester,
        categoria: 'clothes',
        iniciales: {'talla': 'XL', 'estado_ropa': 'Poco uso'},
      );
      expect(find.widgetWithText(TextField, 'XL'), findsOneWidget);
    });
  });

  // ─── Sección del detalle ───────────────────────────────────

  group('ProductAttributesSection', () {
    testWidgets('no pinta nada si no hay respuestas', (tester) async {
      final producto = Product.fromJson(productoJson());
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));
      expect(find.text('Detalles adicionales'), findsNothing);
    });

    testWidgets('muestra etiqueta y valor de cada respuesta', (tester) async {
      final producto = Product.fromJson(
        productoJson(atributos: {'talla': 'M', 'marca': 'Nike'}),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));

      expect(find.text('Detalles adicionales'), findsOneWidget);
      expect(find.text('Talla'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('Marca'), findsOneWidget);
      expect(find.text('Nike'), findsOneWidget);
    });

    testWidgets('omite las preguntas sin responder', (tester) async {
      final producto = Product.fromJson(productoJson(atributos: {'talla': 'M'}));
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));
      expect(find.text('Marca'), findsNothing);
      expect(find.text('Estado de la prenda'), findsNothing);
    });

    testWidgets('los signos de interrogación se quitan de las etiquetas', (
      tester,
    ) async {
      // En el formulario se le pregunta al vendedor; en el detalle el lector
      // es el comprador y una columna de interrogaciones se lee como un
      // interrogatorio.
      final producto = Product.fromJson(
        productoJson(atributos: {'cambio_talla': true}),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));

      expect(find.text('Aplica cambio de talla si no queda'), findsOneWidget);
      expect(find.text('¿Aplica cambio de talla si no queda?'), findsNothing);
    });

    testWidgets('un booleano en false se muestra como No, no se oculta', (
      tester,
    ) async {
      // Que NO acepte devoluciones es justo lo que un comprador necesita
      // saber antes de pagar; ocultarlo sería peor que no preguntarlo.
      final producto = Product.fromJson(
        productoJson(atributos: {'acepta_devoluciones': false}),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));

      expect(find.text('Aceptas devoluciones/reembolsos'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('una selección múltiple se pinta como un chip por valor', (
      tester,
    ) async {
      final producto = Product.fromJson(
        productoJson(
          categoria: 'housing',
          atributos: {
            'incluye_renta': ['Luz', 'Agua', 'Internet'],
          },
        ),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));

      expect(find.text('Luz'), findsOneWidget);
      expect(find.text('Agua'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);
    });

    testWidgets('no muestra un condicional cuyo padre está apagado', (
      tester,
    ) async {
      // El servidor ya los descarta, pero una publicación guardada por una
      // versión anterior podría traerlo.
      final producto = Product.fromJson(
        productoJson(
          atributos: {'tiene_garantia': false, 'duracion_garantia': '6 meses'},
        ),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));
      expect(find.text('6 meses'), findsNothing);
    });

    testWidgets('ignora respuestas de preguntas que esta versión no conoce', (
      tester,
    ) async {
      final producto = Product.fromJson(
        productoJson(atributos: {'talla': 'M', 'pregunta_del_futuro': 'valor'}),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));
      expect(find.text('valor'), findsNothing);
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('no ocupa alto si solo trae respuestas desconocidas', (
      tester,
    ) async {
      // `atributos` no está vacío, así que una guarda por isNotEmpty desde
      // fuera dejaría pasar el espaciado y quedaría un hueco sin sección.
      final producto = Product.fromJson(
        productoJson(atributos: {'pregunta_del_futuro': 'valor'}),
      );
      await tester.pumpWidget(
        envolver(ProductAttributesSection(product: producto)),
      );
      expect(
        tester.getSize(find.byType(ProductAttributesSection)).height,
        0,
      );
    });

    testWidgets('un booleano se muestra como Sí, no con su badgeLabel', (
      tester,
    ) async {
      // El badgeLabel ("Opción veggie") es para la tarjeta del listado, que
      // no tiene dónde poner la pregunta. Aquí la pregunta está en el mismo
      // renglón y repetirla sobraría.
      final producto = Product.fromJson(
        productoJson(categoria: 'food', atributos: {'opciones_veg': true}),
      );
      await tester.pumpWidget(
        envolver(ProductAttributesSection(product: producto)),
      );
      expect(find.text('Sí'), findsOneWidget);
      expect(find.text('Opción veggie'), findsNothing);
    });

    testWidgets('respeta el orden del catálogo, no el del JSON', (tester) async {
      // Dos productos de la misma categoría tienen que leerse igual.
      final producto = Product.fromJson(
        productoJson(
          atributos: {'estado_ropa': 'Nueva', 'talla': 'M', 'precio_negociable': true},
        ),
      );
      await tester.pumpWidget(envolver(ProductAttributesSection(product: producto)));

      double y(String texto) => tester.getTopLeft(find.text(texto)).dy;
      // General primero, luego las de la categoría en el orden de la config.
      expect(y('El precio es negociable'), lessThan(y('Talla')));
      expect(y('Talla'), lessThan(y('Estado de la prenda')));
    });
  });
}
