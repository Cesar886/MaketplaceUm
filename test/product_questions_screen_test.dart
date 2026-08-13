// Tests de la pantalla "todas las preguntas".
//
// Van contra un cliente HTTP falso inyectado en ApiService, no contra mocks
// de cada método: así se ejerce el circuito completo (la pantalla pide,
// parsea, pinta, responde y vuelve a pintar), que es donde de verdad se
// rompen estas pantallas. Un servidor real no sirve aquí: el binding de
// flutter_test intercepta HttpClient y devuelve 400 a todo.
//
// Lo que se protege:
//
//  1. El input de respuesta lo ve SOLO el dueño. Es la mitad visible de la
//     regla que el backend hace cumplir con un 403; si se colara para
//     cualquiera, el usuario descubriría el permiso a base de errores.
//  2. Responder actualiza la fila en el sitio, sin recargar la pantalla.
//  3. El deep link resalta la pregunta a la que apuntaba la notificación, y
//     el resalte se desvanece solo.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/providers/auth_provider.dart';
import 'package:mercadito_um/screens/product_questions_screen.dart';
import 'package:mercadito_um/services/api_service.dart';
import 'package:provider/provider.dart';

/// AuthProvider de prueba: lo único que la pantalla le consulta es si hay
/// sesión y con qué id, que es lo que decide si se puede responder.
class _AuthFalso extends AuthProvider {
  _AuthFalso({this.sellerId});

  final String? sellerId;

  @override
  bool get isLoggedIn => sellerId != null;

  @override
  String? get backendSellerId => sellerId;
}

void main() {
  late List<Map<String, dynamic>> preguntas;
  late List<String> respuestasEnviadas;

  Map<String, dynamic> pregunta(
    String id, {
    String texto = '¿Sigue disponible?',
    String? respuesta,
  }) {
    return {
      'id': id,
      'productId': 'p_1',
      'questionText': texto,
      'answerText': respuesta,
      'status': respuesta == null ? 'pending' : 'answered',
      'createdAt': '2026-08-08T18:00:00Z',
      'answeredAt': respuesta == null ? null : '2026-08-08T19:00:00Z',
      'author': {
        'id': 'u_1',
        'name': 'Mariana Peña',
        'avatarInitials': 'MP',
        'major': 'Estudiante',
        'isBusiness': false,
        'verified': true,
        'tipoCuenta': 'estudiante',
      },
    };
  }

  /// Backend falso con el mismo contrato que routes/questions.js.
  http.Response responder(http.Request request) {
    final ruta = request.url.path;

    if (request.method == 'GET' && ruta.endsWith('/questions')) {
      final soloPendientes = request.url.queryParameters['filter'] == 'pending';
      final visibles = soloPendientes
          ? preguntas.where((q) => q['status'] == 'pending').toList()
          : preguntas;
      return http.Response(
        jsonEncode({
          'questions': visibles,
          'nextCursor': null,
          'total': preguntas.length,
          'pendingCount':
              preguntas.where((q) => q['status'] == 'pending').length,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (request.method == 'POST' && ruta.endsWith('/answer')) {
      final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
      final texto = cuerpo['texto'] as String;
      respuestasEnviadas.add(texto);
      final id = ruta.split('/')[ruta.split('/').length - 2];
      final fila = preguntas.firstWhere((q) => q['id'] == id);
      fila['answerText'] = texto;
      fila['status'] = 'answered';
      fila['answeredAt'] = '2026-08-08T20:00:00Z';
      return http.Response(
        jsonEncode({'question': fila, 'pendingCount': 0}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    return http.Response('{"error":"no encontrado"}', 404);
  }

  setUp(() {
    preguntas = [];
    respuestasEnviadas = [];
    ApiService.clienteDePrueba = MockClient((req) async => responder(req));
  });

  tearDown(ApiService.restaurarCliente);

  Future<void> montar(
    WidgetTester tester, {
    String? sesionDe,
    String? destacar,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _AuthFalso(sellerId: sesionDe),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ProductQuestionsScreen(
            productId: 'p_1',
            productOwnerId: 'v_1',
            sellerName: 'Ana Valdés',
            destacarPreguntaId: destacar,
          ),
        ),
      ),
    );
    // Un par de vueltas para que resuelvan la carga inicial y, si hay deep
    // link, el desplazamiento hasta la pregunta.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('lista las preguntas del producto con sus respuestas', (
    tester,
  ) async {
    preguntas = [
      pregunta('q_1', texto: '¿Sigue disponible?'),
      pregunta('q_2', texto: '¿Aceptas transferencia?', respuesta: 'Sí, claro.'),
    ];

    await montar(tester);

    expect(find.text('¿Sigue disponible?'), findsOneWidget);
    expect(find.text('¿Aceptas transferencia?'), findsOneWidget);
    expect(find.text('Sí, claro.'), findsOneWidget);
    expect(find.text('Respuesta de Ana Valdés'), findsOneWidget);
  });

  testWidgets('un comprador no ve el botón de responder', (tester) async {
    preguntas = [pregunta('q_1')];

    await montar(tester, sesionDe: 'u_9');

    expect(find.text('Pendiente de respuesta'), findsOneWidget);
    expect(find.text('Responder'), findsNothing);
    // A él sí se le ofrece preguntar.
    expect(find.text('Hacer una pregunta'), findsOneWidget);
  });

  testWidgets('un visitante sin sesión tampoco ve el botón de responder', (
    tester,
  ) async {
    preguntas = [pregunta('q_1')];

    await montar(tester);

    expect(find.text('Responder'), findsNothing);
  });

  testWidgets(
    'el dueño ve responder en las pendientes y editar en las respondidas',
    (tester) async {
      preguntas = [
        pregunta('q_1'),
        pregunta('q_2', texto: '¿Envías?', respuesta: 'Dentro del campus.'),
      ];

      await montar(tester, sesionDe: 'v_1');

      expect(find.text('Responder'), findsOneWidget);
      expect(find.text('Editar respuesta'), findsOneWidget);
      // Y para él no hay barra de "hacer una pregunta": es su publicación.
      expect(find.text('Hacer una pregunta'), findsNothing);
    },
  );

  testWidgets('el dueño responde en línea y la pregunta se actualiza sola', (
    tester,
  ) async {
    preguntas = [pregunta('q_1', texto: '¿Sigue disponible?')];

    await montar(tester, sesionDe: 'v_1');

    await tester.tap(find.text('Responder'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Sí, hasta el viernes.');
    await tester.pump();

    await tester.tap(find.text('Publicar respuesta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(respuestasEnviadas, ['Sí, hasta el viernes.']);
    expect(find.text('Sí, hasta el viernes.'), findsWidgets);
    expect(find.text('Pendiente de respuesta'), findsNothing);
  });

  testWidgets('la respuesta vacía no se puede enviar', (tester) async {
    preguntas = [pregunta('q_1')];

    await montar(tester, sesionDe: 'v_1');
    await tester.tap(find.text('Responder'));
    await tester.pump();

    final boton = tester.widget<FilledButton>(find.byType(FilledButton));

    expect(boton.onPressed, isNull, reason: 'debe estar deshabilitado');
    expect(respuestasEnviadas, isEmpty);
  });

  testWidgets('el deep link resalta la pregunta a la que apunta', (
    tester,
  ) async {
    preguntas = [
      pregunta('q_1', texto: 'Primera'),
      pregunta('q_2', texto: 'La de la notificación'),
    ];

    await montar(tester, destacar: 'q_2');

    final destacada = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('La de la notificación'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final otra = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Primera'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    expect(
      (destacada.decoration! as BoxDecoration).color,
      isNot(Colors.transparent),
    );
    expect((otra.decoration! as BoxDecoration).color, Colors.transparent);

    // Deja correr el temporizador que apaga el resalte: si el test termina
    // con él pendiente, el binding lo reporta como fuga.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('el resalte se desvanece solo', (tester) async {
    preguntas = [pregunta('q_1', texto: 'La de la notificación')];

    await montar(tester, destacar: 'q_1');

    // Más que la duración del resalte.
    await tester.pump(const Duration(seconds: 4));

    final tile = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('La de la notificación'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );

    expect((tile.decoration! as BoxDecoration).color, Colors.transparent);
  });

  testWidgets('sin preguntas invita a ser el primero', (tester) async {
    preguntas = [];

    await montar(tester, sesionDe: 'u_9');

    expect(
      find.text('Sé el primero en preguntar sobre esta publicación.'),
      findsOneWidget,
    );
  });

  testWidgets('al dueño sin preguntas se le dice que nadie ha preguntado', (
    tester,
  ) async {
    preguntas = [];

    await montar(tester, sesionDe: 'v_1');

    expect(
      find.text('Todavía nadie ha preguntado en esta publicación.'),
      findsOneWidget,
    );
  });
}
