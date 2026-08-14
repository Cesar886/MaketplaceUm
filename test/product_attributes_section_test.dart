// Rediseño de "Detalles adicionales": chips de resumen siempre visibles +
// acordeón colapsable con la tabla completa. Ver
// lib/widgets/product_attributes_section.dart para el porqué de cada regla.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/product_attributes_section.dart';

void main() {
  Product producto({
    required String categoria,
    Map<String, dynamic> atributos = const {},
  }) {
    return Product.fromJson({
      'id': 'p_1',
      'title': 'Producto de prueba',
      'price': 350,
      'description': 'Descripción de prueba',
      'publishedAgo': 'hace 2 días',
      'seller': 's_1',
      'categoryObj': {'id': categoria, 'name': categoria, 'emoji': '📦'},
      'images': <String>[],
      'extras': <dynamic>[],
      'views': 128,
      'atributos': atributos,
    });
  }

  Widget marco(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );
  }

  testWidgets('sin respuestas no pinta nada', (tester) async {
    await tester.pumpWidget(
      marco(ProductAttributesSection(product: producto(categoria: 'other'))),
    );

    expect(find.text('Ver todos los detalles'), findsNothing);
  });

  testWidgets('chips de resumen: estado, garantía y tiempo de uso', (
    tester,
  ) async {
    await tester.pumpWidget(
      marco(
        ProductAttributesSection(
          product: producto(
            categoria: 'electronics',
            atributos: {
              'estado_electronico': 'Seminuevo',
              'tiene_garantia': true,
              'duracion_garantia': '8 meses',
              'tiempo_uso': '50 días',
            },
          ),
        ),
      ),
    );

    expect(find.text('Seminuevo'), findsOneWidget);
    expect(find.text('8 meses de garantía'), findsOneWidget);
    expect(find.text('50 días de uso'), findsOneWidget);
  });

  testWidgets('sin garantía activa no hay chip de garantía', (tester) async {
    await tester.pumpWidget(
      marco(
        ProductAttributesSection(
          product: producto(
            categoria: 'electronics',
            atributos: {
              'estado_electronico': 'Usado',
              'tiene_garantia': false,
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('garantía'), findsNothing);
  });

  testWidgets('acordeón empieza colapsado y expande al tocar el botón', (
    tester,
  ) async {
    await tester.pumpWidget(
      marco(
        ProductAttributesSection(
          product: producto(
            categoria: 'clothes',
            atributos: {'talla': 'M', 'cambio_talla': true},
          ),
        ),
      ),
    );

    // Colapsado: la fila de la tabla no está en el árbol.
    expect(find.text('Talla'), findsNothing);
    expect(find.text('Ver todos los detalles'), findsOneWidget);

    await tester.tap(find.text('Ver todos los detalles'));
    await tester.pumpAndSettle();

    expect(find.text('Talla'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('booleano expandido se pinta como pill Sí/No', (tester) async {
    await tester.pumpWidget(
      marco(
        ProductAttributesSection(
          product: producto(
            categoria: 'clothes',
            atributos: {'cambio_talla': true},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ver todos los detalles'));
    await tester.pumpAndSettle();

    expect(find.text('Sí'), findsOneWidget);
  });
}
