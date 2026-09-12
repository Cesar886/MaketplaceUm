import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/screens/report_product_sheet.dart';
import 'package:mercadito_um/services/api_service.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  setUpAll(inicializarTraducciones);

  tearDown(() {
    ApiService.clearToken();
    ApiService.restaurarCliente();
  });

  testWidgets('reportar una busqueda envia el tipo wanted', (tester) async {
    Map<String, dynamic>? reporteEnviado;
    ApiService.setToken('token-de-prueba');
    ApiService.clienteDePrueba = MockClient((request) async {
      if (request.url.path.endsWith('/reports')) {
        reporteEnviado = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'report': {}}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final busqueda = Product.fromJson({
      'id': 'wanted-123',
      'title': 'Busco calculadora',
      'postType': 'se_busca',
      'sellerObj': {
        'id': 'seller-456',
        'name': 'Daniel',
        'avatarInitials': 'DA',
      },
    });

    await tester.pumpWidget(
      appDePrueba(
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showProductReportSheet(context: context, product: busqueda),
              child: const Text('Abrir reporte'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parece fraude o intento de estafa'));
    await tester.pump();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();

    expect(reporteEnviado, isNotNull);
    expect(reporteEnviado!['targetType'], 'wanted');
    expect(reporteEnviado!['targetId'], 'wanted-123');
  });
}
