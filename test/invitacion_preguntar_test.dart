import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/widgets/product_questions_section.dart';

import 'helpers/localizacion_de_prueba.dart';

/// La invitación a preguntar es lo único que se pinta cuando la publicación
/// todavía no tiene preguntas, y su frase ("¿Tienes una duda? Pregúntale al
/// vendedor") ronda los 280 px con la fuente por defecto.
///
/// Cuando eran dos `Text` sueltos dentro de un `Row`, esa frase no tenía
/// forma de partirse: en un teléfono angosto —o con la fuente del sistema
/// agrandada, que es un ajuste de accesibilidad común— el Row desbordaba y
/// Flutter pintaba la franja amarilla y negra encima del detalle del
/// producto. Estos tests fijan que la frase se acomoda en vez de desbordar.
void main() {
  setUpAll(inicializarTraducciones);

  /// Monta la sección en su estado vacío (la llamada al backend falla en un
  /// test, y sin preguntas la sección se reduce a la invitación).
  Future<void> montar(
    WidgetTester tester, {
    required Size tamano,
    double escalaTexto = 1.0,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      appDePrueba(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
            child: const Scaffold(
              body: ProductQuestionsSection(
                productId: 'p1',
                productOwnerId: 'otro_vendedor',
                sellerName: 'Vendedor',
              ),
            ),
          ),
        ),
      ),
    );
    // La carga falla (no hay red en un test) y la sección cae a su estado
    // vacío; `pump` extra para que ese setState llegue a pintarse.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('la invitación no desborda en un teléfono angosto', (
    tester,
  ) async {
    await montar(tester, tamano: const Size(320, 640));

    expect(find.textContaining('Pregúntale al vendedor'), findsOneWidget);
    // Un RenderFlex desbordado se reporta como excepción en los tests: si
    // esto trae algo, la franja amarilla y negra volvió.
    expect(tester.takeException(), isNull);
  });

  testWidgets('la invitación no desborda con la fuente agrandada', (
    tester,
  ) async {
    await montar(tester, tamano: const Size(320, 640), escalaTexto: 1.6);

    expect(find.textContaining('Pregúntale al vendedor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
