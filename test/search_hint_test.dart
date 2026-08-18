// El campo de búsqueda nunca puede quedarse sin placeholder.
//
// El hint tiene dos fuentes: la animación de tecleo sobre los términos que
// devuelve GET /api/search/trending, y una cadena estática de respaldo. El
// respaldo se había reemplazado por un espacio en blanco, así que cuando las
// tendencias no llegaban —el endpoint caído, o la lista vacía, que el propio
// ApiService documenta como respuesta legítima— el buscador se pintaba sin
// una sola pista de qué se podía buscar. Justo el momento en que más falta
// hace.
//
// Estos tests cubren las tres rutas: tendencias sanas, endpoint caído y
// lista vacía.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/screens/search_screen.dart';
import 'package:mercadito_um/services/api_service.dart';

import 'helpers/localizacion_de_prueba.dart';

/// Copia local del respaldo que pinta `SearchScreen` cuando no hay
/// tendencias. Se repite a propósito en vez de exponer una constante en la
/// pantalla: si viviera allí, la igualdad de abajo compararía el valor
/// consigo mismo y pasaría aun con el hint vaciado a ' '.
const hintEstaticoEsperado = 'Libro, electronico, servicio...';

void main() {
  setUpAll(inicializarTraducciones);

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// [trending] null simula el endpoint caído; una lista vacía simula el
  /// "no hay data suficiente todavía" que el backend puede devolver.
  ///
  /// Con [trendingCuelga] la petición nunca resuelve: es la única forma de
  /// congelar el estado "todavía cargando", porque un MockClient responde
  /// tan rápido que en el primer pump las tendencias ya llegaron.
  void montarBackend({List<String>? trending, bool trendingCuelga = false}) {
    ApiService.clienteDePrueba = MockClient((request) async {
      final ruta = request.url.path;

      if (ruta.endsWith('/search/trending')) {
        if (trendingCuelga) return Completer<http.Response>().future;
        if (trending == null) return http.Response('boom', 500);
        return http.Response(
          jsonEncode({'terms': trending}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      // Productos y categorías: la pantalla los pide antes de las
      // tendencias y aborta el resto si fallan, así que tienen que
      // responder aunque no sean lo que se prueba.
      if (ruta.endsWith('/categories/ranked') || ruta.endsWith('/products')) {
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      return http.Response('{}', 404);
    });
  }

  tearDown(ApiService.restaurarCliente);

  /// El hint que está pintado ahora mismo en la barra de búsqueda.
  String hintActual(WidgetTester tester) {
    final campo = tester.widget<TextField>(find.byType(TextField).first);
    return campo.decoration!.hintText!;
  }

  /// Comprueba que el campo esté ofreciendo un ejemplo de búsqueda.
  ///
  /// Primero exige que el hint sea legible por sí solo: esa es la regresión
  /// que importa, y se comprueba sin mirar de dónde sale el texto. La
  /// igualdad contra la copia local viene después, para fijar que además
  /// sea un ejemplo de búsqueda y no un texto cualquiera.
  void esperarHintUtil(WidgetTester tester, {String? reason}) {
    final hint = hintActual(tester);
    expect(
      hint.trim().length,
      greaterThanOrEqualTo(8),
      reason: reason ?? 'el hint quedó en blanco: "$hint"',
    );
    // Un ejemplo de qué buscar, no un texto cualquiera.
    expect(hint, hintEstaticoEsperado, reason: reason);
  }

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(appDePrueba(const SearchScreen()));
    // Las traducciones cargan de forma asíncrona; sin este pump la pantalla
    // todavía no existe cuando el test mira el hint.
    await tester.pump();
    // pumpAndSettle no sirve: la animación de tecleo reprograma su timer
    // para siempre y el settle nunca terminaría.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('mientras las tendencias viajan se ve el hint estático', (
    tester,
  ) async {
    // El campo se pinta antes de que la respuesta llegue: en esa ventana
    // también tiene que decir algo, no quedarse mudo.
    montarBackend(trendingCuelga: true);
    await montar(tester);

    esperarHintUtil(tester);
  });

  testWidgets('si /search/trending falla el hint NO queda en blanco', (
    tester,
  ) async {
    montarBackend(trending: null);
    await montar(tester);

    // Esta es la regresión: el hint era ' ' y el usuario veía el campo mudo.
    esperarHintUtil(
      tester,
      reason: 'el buscador se quedó sin placeholder con el endpoint caído',
    );
  });

  testWidgets('una lista de tendencias vacía también cae al hint estático', (
    tester,
  ) async {
    // 200 con [] es una respuesta válida del backend, no un error: hay que
    // tratarla igual que el fallo, no como "ya hay tendencias".
    montarBackend(trending: const []);
    await montar(tester);

    esperarHintUtil(tester);
  });

  testWidgets('con tendencias el hint pasa a la animación de tecleo', (
    tester,
  ) async {
    montarBackend(trending: const ['audífonos']);
    await montar(tester);

    // El respaldo tiene que ceder el lugar en cuanto hay términos: si se
    // quedara fijo, todo el placeholder rotativo sería código muerto.
    await tester.pump(const Duration(milliseconds: 400));
    final hint = hintActual(tester);
    expect(hint, isNot(hintEstaticoEsperado));
    expect(
      hint.replaceAll('▏', ''),
      // Se teclea letra por letra, así que a mitad de la animación solo hay
      // un prefijo del término — capitalizado, como lo pinta la pantalla.
      predicate<String>((s) => 'Audífonos'.startsWith(s) && s.isNotEmpty),
      reason: 'el hint no está tecleando el término de tendencia',
    );
  });
}
