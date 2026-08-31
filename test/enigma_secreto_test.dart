// El enigma escondido, del lado de la app.
//
// Lo que se protege aquí es lo que no se ve: que la frase NO deje comentario
// en el hilo, que la puerta se abra sola sin snackbar ni error de por medio,
// y que un comentario normal siga comportándose exactamente como antes. Si
// alguna de esas tres se rompe, el secreto deja de ser secreto — un envío que
// aparece publicado, o un "algo salió mal" en pantalla, delatan el mecanismo
// a cualquiera que teclee la frase por casualidad.
//
// Mismo patrón que product_questions_screen_test.dart: cliente HTTP falso
// inyectado en ApiService y el circuito completo de la pantalla, no mocks por
// método. La frase y la respuesta no se escriben aquí: las juzga el servidor,
// así que el falso responde según lo que se le pida simular, y estos tests
// nunca las conocen.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/screens/secreto/enigma_resuelto_screen.dart';
import 'package:mercadito_um/screens/secreto/enigma_screen.dart';
import 'package:mercadito_um/services/api_service.dart';
import 'package:mercadito_um/services/chat_socket_service.dart';
import 'package:mercadito_um/widgets/comment_tile.dart';
import 'package:mercadito_um/widgets/product_comments_section.dart';
import 'package:provider/provider.dart';

import 'helpers/localizacion_de_prueba.dart';

/// Cuenta verificada: la única que puede escribir en el campo, y por tanto la
/// única que puede llegar al gatillo.
class _AuthFalso extends AuthProvider {
  @override
  bool get isLoggedIn => true;

  @override
  bool get isVerified => true;

  @override
  String? get backendSellerId => 'u_1';
}

void main() {
  setUpAll(inicializarTraducciones);

  tearDown(ApiService.restaurarCliente);

  /// Lienzo alto: el acertijo mide más que los 800x600 por defecto del
  /// binding, y con ese tamaño el campo y su botón quedan fuera de la
  /// pantalla — no se pueden ni tocar.
  void lienzoDeTelefono(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Respuesta del hilo: siempre vacío, para que cualquier comentario que
  /// aparezca en pantalla venga del envío y no del historial.
  Map<String, dynamic> hiloVacio() => {
    'comments': <dynamic>[],
    'nextCursor': null,
    'total': 0,
  };

  Map<String, dynamic> comentario(String texto) => {
    'id': 'cmt_1',
    'productId': 'p_1',
    'texto': texto,
    'createdAt': '2026-08-31T18:00:00Z',
    'author': {'id': 'u_1', 'name': 'Ana', 'avatarInitials': 'AN'},
  };

  Future<void> montarSeccion(
    WidgetTester tester, {
    required http.Client cliente,
  }) async {
    lienzoDeTelefono(tester);
    ApiService.clienteDePrueba = cliente;
    await pumpEsperandoTraducciones(
      tester,
      appDePrueba(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => _AuthFalso(),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: ProductCommentsSection(
                productId: 'p_1',
                productOwnerId: 'u_otro',
              ),
            ),
          ),
        ),
      ),
    );
    // Pumps sueltos y no `pumpAndSettle`: la sección abre el socket de la app
    // al montarse, y su temporizador de reconexión no se agota nunca — un
    // `pumpAndSettle` se quedaría girando contra él hasta el timeout.
    await tester.pump();
    await tester.pump();
  }

  /// Cierra el socket que la sección abrió al montarse.
  ///
  /// Tiene que llamarse DENTRO del cuerpo del test, no en un tearDown: el
  /// binding revisa los temporizadores pendientes al terminar el cuerpo, y el
  /// de reconexión del socket (20 s) haría fallar el test antes de que
  /// cualquier tearDown llegue a correr.
  Future<void> cerrarSocket(WidgetTester tester) async {
    ChatSocketService.instance.disconnect();
    await tester.pump();
  }

  Future<void> escribirYEnviar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField), texto);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('un comentario normal se publica en el hilo y no abre nada', (
    tester,
  ) async {
    final cliente = MockClient((req) async {
      if (req.method == 'GET') return http.Response(jsonEncode(hiloVacio()), 200);
      return http.Response(
        jsonEncode({'comment': comentario('Muy buen producto'), 'total': 1}),
        201,
      );
    });

    await montarSeccion(tester, cliente: cliente);
    await escribirYEnviar(tester, 'Muy buen producto');

    expect(find.byType(CommentTile), findsOneWidget);
    expect(find.byType(EnigmaScreen), findsNothing);

    await cerrarSocket(tester);
  });

  testWidgets('la frase secreta abre el enigma y no deja comentario', (
    tester,
  ) async {
    var envios = 0;
    final cliente = MockClient((req) async {
      if (req.method == 'GET') return http.Response(jsonEncode(hiloVacio()), 200);
      envios++;
      // Lo que responde el backend cuando el texto era la frase: aceptado,
      // pero sin comentario que insertar.
      return http.Response(jsonEncode({'secreto': true}), 201);
    });

    await montarSeccion(tester, cliente: cliente);
    await escribirYEnviar(tester, 'la frase que sea');
    // El enigma revela sus versos escalonados durante varios segundos: sin
    // dejarlos correr, el test acaba con esos retrasos aún pendientes.
    await tester.pump(const Duration(seconds: 8));

    expect(envios, 1);
    expect(find.byType(EnigmaScreen), findsOneWidget, reason: 'la puerta se abre sola');
    expect(find.byType(CommentTile), findsNothing, reason: 'el hilo no cambia');
    // Ni rastro de error: el usuario no debe ver un fallo donde hubo un éxito.
    expect(find.byType(SnackBar), findsNothing);

    await cerrarSocket(tester);
  });

  testWidgets('el campo se limpia al cruzar la puerta', (tester) async {
    final cliente = MockClient((req) async {
      if (req.method == 'GET') return http.Response(jsonEncode(hiloVacio()), 200);
      return http.Response(jsonEncode({'secreto': true}), 201);
    });

    await montarSeccion(tester, cliente: cliente);
    await escribirYEnviar(tester, 'la frase que sea');
    await tester.pump(const Duration(seconds: 8));

    // Al volver, el campo no puede seguir con la frase escrita: quedaría a la
    // vista de quien tome el teléfono después.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.controller?.text, isEmpty);

    await cerrarSocket(tester);
  });

  // ═══ La pantalla del acertijo ════════════════════════════════

  Future<void> montarEnigma(
    WidgetTester tester, {
    required http.Client cliente,
  }) async {
    lienzoDeTelefono(tester);
    ApiService.clienteDePrueba = cliente;
    await pumpEsperandoTraducciones(tester, appDePrueba(const EnigmaScreen()));
    // Los versos entran escalonados durante unos segundos; el campo es lo
    // último en aparecer.
    await tester.pump(const Duration(seconds: 8));
  }

  Future<void> responder(WidgetTester tester, String respuesta) async {
    await tester.enterText(find.byType(TextField), respuesta);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('una respuesta equivocada deja al usuario en el acertijo', (
    tester,
  ) async {
    final cliente = MockClient(
      (req) async => http.Response(jsonEncode({'correcto': false}), 200),
    );

    await montarEnigma(tester, cliente: cliente);
    await responder(tester, 'mercadito');

    expect(find.text('No.'), findsOneWidget);
    expect(find.byType(EnigmaResueltoScreen), findsNothing);
  });

  testWidgets('la respuesta correcta lleva a la segunda pantalla con la posición', (
    tester,
  ) async {
    final cliente = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'correcto': true,
          'posicion': 1,
          'total': 1,
          'repetida': false,
          'resueltoEn': '2026-08-31T18:00:00Z',
        }),
        200,
      ),
    );

    await montarEnigma(tester, cliente: cliente);
    await responder(tester, 'la respuesta que sea');
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(EnigmaResueltoScreen), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'el sello con la posición');
    expect(find.textContaining('Nadie llegó'), findsOneWidget);
    // El acertijo queda atrás: se reemplazó, no se apiló.
    expect(find.byType(EnigmaScreen), findsNothing);
  });

  testWidgets('quien ya lo había resuelto no recibe la felicitación de nuevo', (
    tester,
  ) async {
    final cliente = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'correcto': true,
          'posicion': 3,
          'total': 7,
          'repetida': true,
          'resueltoEn': '2026-08-20T18:00:00Z',
        }),
        200,
      ),
    );

    await montarEnigma(tester, cliente: cliente);
    await responder(tester, 'la respuesta que sea');
    await tester.pump(const Duration(seconds: 4));

    expect(find.textContaining('Sigues siendo'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
