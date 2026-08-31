// Apertura de un aviso de retargeting desde la campana.
//
// No es telemetría opcional: el backend cuenta como "ignorada" toda
// notificación de este tipo sin `opened_at`, y a las tres seguidas pausa la
// categoría 14 días. La pantalla de notificaciones no tenía rama para
// `interest_new_product`, así que quien leía sus avisos desde la campana en
// vez de desde la push acababa autopausándose sin tocar nada.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/screens/notifications_screen.dart';
import 'package:mercadito_um/screens/search_screen.dart';
import 'package:mercadito_um/services/api_service.dart';

import 'helpers/localizacion_de_prueba.dart';

/// Lo único que la pantalla consulta es si hay sesión.
class _AuthFalso extends AuthProvider {
  @override
  bool get isLoggedIn => true;
}

void main() {
  setUpAll(inicializarTraducciones);

  late List<Map<String, dynamic>> aperturas;

  setUp(() {
    aperturas = [];
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(ApiService.restaurarCliente);

  /// Monta la campana con un único aviso de retargeting.
  Future<void> montar(WidgetTester tester, {required List<String> productIds}) async {
    ApiService.clienteDePrueba = MockClient((request) async {
      final ruta = request.url.path;

      if (request.method == 'GET' && ruta.endsWith('/notifications')) {
        return http.Response(
          jsonEncode({
            'notifications': [
              {
                'id': 'notif_1',
                'userId': 'u1',
                'type': ApiService.notifInteresNuevosProductos,
                'title': 'Coincide con lo que viste en Libros',
                'body': '${productIds.length} publicaciones nuevas para ti',
                'data': {
                  'category': 'libros',
                  'productIds': productIds,
                  'motivo': 'interest_match',
                },
                'read': false,
                'createdAt': '2026-08-31T12:00:00Z',
              },
            ],
            'unreadCount': 1,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      if (request.method == 'POST' && ruta.endsWith('/notifications/interest-opened')) {
        aperturas.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"success":true,"marcadas":1}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }

      return http.Response('{}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _AuthFalso(),
        child: MaterialApp(theme: AppTheme.light(), home: const NotificationsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('abrir el aviso desde la campana registra la apertura', (tester) async {
    await montar(tester, productIds: ['p1', 'p2', 'p3']);

    await tester.tap(find.text('Coincide con lo que viste en Libros'));
    await tester.pumpAndSettle();

    expect(aperturas, hasLength(1), reason: 'sin esto el backend la da por ignorada');
    expect(aperturas.single['notificationId'], 'notif_1');
    expect(aperturas.single['categoryId'], 'libros');
  });

  testWidgets('un aviso que agrupa varias publicaciones abre la categoría', (tester) async {
    // No hay un detalle concreto al que ir, pero el tile no puede quedarse
    // muerto: se aterriza en la categoría que motivó el aviso.
    await montar(tester, productIds: ['p1', 'p2', 'p3']);

    await tester.tap(find.text('Coincide con lo que viste en Libros'));
    await tester.pumpAndSettle();

    final buscador = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(buscador.initialCategoryId, 'libros');
  });
}
