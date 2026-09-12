import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/services/api_service.dart';
import 'package:mercadito_um/widgets/publication_limit_notice.dart';

class _AuthDePrueba extends AuthProvider {
  @override
  AccountType get accountType => AccountType.particular;

  @override
  bool get isVerified => false;

  @override
  String? get backendSellerId => 'seller-dinamico';
}

void main() {
  late _AuthDePrueba auth;

  setUp(() {
    auth = _AuthDePrueba();
    ApiService.setToken('token-de-prueba');
  });

  tearDown(() {
    ApiService.clearToken();
    ApiService.restaurarCliente();
  });

  void montarBackend(Map<String, dynamic> policy) {
    ApiService.clienteDePrueba = MockClient((request) async {
      expect(request.url.path, endsWith('/api/me/publication-policy'));
      expect(request.headers['Authorization'], 'Bearer token-de-prueba');
      return http.Response(
        jsonEncode(policy),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  Future<void> montar(WidgetTester tester, {required bool wanted}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicationLimitNotice(auth: auth, wanted: wanted),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('productos muestra la política vigente devuelta por el panel', (
    tester,
  ) async {
    montarBackend({
      'productsActive': 77,
      'productsDaily': 12,
      'wantedActive': 9,
      'wantedDaily': 4,
      'durationDays': 91,
    });

    await montar(tester, wanted: false);

    expect(
      find.text(
        'Tu cuenta permite 77 publicaciones activas, 12 nuevas al día y duran 91 días.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('se busca usa los campos dinámicos de su propio límite', (
    tester,
  ) async {
    montarBackend({
      'productsActive': 77,
      'productsDaily': 12,
      'wantedActive': 9,
      'wantedDaily': 4,
      'durationDays': 91,
    });

    await montar(tester, wanted: true);

    expect(
      find.text(
        'Tu cuenta permite 9 publicaciones activas, 4 nuevas al día y duran 91 días.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('un cambio del panel aparece aunque el formulario siga abierto', (
    tester,
  ) async {
    var requestCount = 0;
    ApiService.clienteDePrueba = MockClient((request) async {
      requestCount++;
      final updated = requestCount > 1;
      return http.Response(
        jsonEncode({
          'productsActive': updated ? 55 : 8,
          'productsDaily': updated ? 7 : 2,
          'wantedActive': 3,
          'wantedDaily': 1,
          'durationDays': updated ? 80 : 30,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await montar(tester, wanted: false);
    expect(find.textContaining('8 publicaciones activas'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(requestCount, 2);
    expect(
      find.text(
        'Tu cuenta permite 55 publicaciones activas, 7 nuevas al día y duran 80 días.',
      ),
      findsOneWidget,
    );
  });
}
