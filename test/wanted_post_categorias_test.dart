// El selector de categoría de "publicar búsqueda" tiene que seguir siendo
// usable cuando GET /api/categories falla.
//
// Bug reportado por usuarios beta: "no se puede seleccionar una categoría".
// La causa no era el cableado del dropdown —está bien— sino que
// _loadCategories se tragaba la excepción y dejaba `_categories` vacío. Un
// DropdownButton sin items SE AUTO-DESHABILITA: el campo se pinta con su
// label, el tap no hace nada y no hay ningún mensaje. Desde fuera es
// indistinguible de un botón roto.
//
// publish_product_screen ya resolvía esto cayendo a `mockCategories`; esta
// pantalla era la única sin esa red. Estos tests fijan el comportamiento en
// las dos rutas para que no se vuelva a ir.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/mock_data.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/screens/wanted_post_screen.dart';
import 'package:mercadito_um/services/api_service.dart';
import 'package:provider/provider.dart';

/// Lo único que la pantalla le pregunta al auth es si hay sesión y con qué
/// id: sin sesión enseña la puerta de registro y nunca llega al formulario.
class _AuthFalso extends AuthProvider {
  @override
  bool get isLoggedIn => true;

  @override
  String? get backendSellerId => 's_1';

  /// La sección de ubicación la consulta en cada build y el real la deriva
  /// de `_currentUser!`, que aquí nunca se llena. Estudiante: es la cuenta
  /// con la que se reportó el bug y la que no ve la sección de ubicación.
  @override
  AccountType get accountType => AccountType.estudiante;
}

/// Las mismas 8 categorías que sirve el backend en producción.
const _categoriasServidor = [
  {
    'id': 'books',
    'name': 'Libros',
    'emoji': '📚',
    'icon': 'menu_book',
    'color': '#2A6FBB',
  },
  {
    'id': 'clothes',
    'name': 'Ropa',
    'emoji': '👔',
    'icon': 'checkroom',
    'color': '#9B5DE5',
  },
  {
    'id': 'food',
    'name': 'Comida',
    'emoji': '🍕',
    'icon': 'restaurant',
    'color': '#E86F2C',
  },
];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// [categoriasFallan] simula el fallo que dispara el bug: el endpoint de
  /// categorías cae y todo lo demás responde normal.
  void montarBackend({required bool categoriasFallan}) {
    ApiService.clienteDePrueba = MockClient((request) async {
      final ruta = request.url.path;

      if (ruta.endsWith('/categories')) {
        if (categoriasFallan) return http.Response('boom', 500);
        return http.Response(
          jsonEncode(_categoriasServidor),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      // _loadSellerLocation pide el perfil; no es lo que se prueba aquí.
      return http.Response('{}', 404);
    });
  }

  tearDown(ApiService.restaurarCliente);

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _AuthFalso(),
        child: const MaterialApp(home: WantedPostScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Abre el desplegable y elige [nombre]. Devuelve false si el campo estaba
  /// inerte (el menú nunca abrió), que es justo el síntoma reportado.
  Future<bool> elegirCategoria(WidgetTester tester, String nombre) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    final opcion = find.text(nombre);
    if (opcion.evaluate().isEmpty) return false;

    await tester.tap(opcion.last);
    await tester.pumpAndSettle();
    return true;
  }

  testWidgets('con el backend sano se puede elegir una categoría', (
    tester,
  ) async {
    montarBackend(categoriasFallan: false);
    await montar(tester);

    expect(await elegirCategoria(tester, 'Ropa'), isTrue);
    expect(find.text('Ropa'), findsWidgets);
  });

  testWidgets('si /categories falla el selector NO queda muerto', (
    tester,
  ) async {
    montarBackend(categoriasFallan: true);
    await montar(tester);

    // Esta es la regresión: antes del fix el menú no abría y el usuario se
    // quedaba sin poder publicar su búsqueda.
    expect(
      await elegirCategoria(tester, 'Ropa'),
      isTrue,
      reason: 'el dropdown quedó inerte: no hay categorías de respaldo',
    );
  });

  testWidgets('el respaldo trae el catálogo local completo', (tester) async {
    montarBackend(categoriasFallan: true);
    await montar(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    // No basta con "alguna" categoría: el respaldo tiene que ofrecer las
    // mismas opciones que el servidor, o la búsqueda se publica mal
    // clasificada.
    for (final categoria in mockCategories) {
      expect(
        find.text(categoria.name),
        findsWidgets,
        reason: 'falta ${categoria.name} en el respaldo',
      );
    }
  });

  testWidgets('el respaldo deja una categoría preseleccionada válida', (
    tester,
  ) async {
    montarBackend(categoriasFallan: true);
    await montar(tester);

    // Publicar valida `_selectedCategoryId != null`; si el respaldo entrara
    // sin selección, el usuario tendría que abrir el menú a fuerza para
    // poder publicar.
    final campo = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(campo.initialValue, isNotNull);
    expect(
      mockCategories.any((c) => c.id == campo.initialValue),
      isTrue,
      reason: 'la preselección apunta a una categoría que no existe',
    );
  });
}
