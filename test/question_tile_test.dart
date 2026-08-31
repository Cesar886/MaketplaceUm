// Tests de renderizado del hilo de preguntas.
//
// No comprueban lógica sino que la pieza SE PINTE bien: que la respuesta se
// distinga de la pregunta, que el badge de pendiente aparezca solo cuando
// toca, y que nada desborde con textos hostiles. Son fallos que no salen en
// `flutter analyze` ni en un test de modelo, solo al mirar la pantalla.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/question_tile.dart';

void main() {
  Seller autor({String name = 'Mariana Peña', bool verified = true}) {
    return Seller(
      id: 'u_1',
      name: name,
      avatarInitials: 'MP',
      major: 'Estudiante',
      rating: 0,
      reviews: 0,
      verified: verified,
      tipoCuenta: 'estudiante',
      carrera: 'Ingeniería en Mercadotecnia',
      tipoVerificacion: 'estudiante',
    );
  }

  ProductQuestion pregunta({
    String texto = '¿Sigue disponible en color negro?',
    String? respuesta,
    Seller? de,
  }) {
    return ProductQuestion(
      id: 'q_1',
      productId: 'p_1',
      questionText: texto,
      answerText: respuesta,
      status: respuesta == null ? 'pending' : 'answered',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      answeredAt: respuesta == null
          ? null
          : DateTime.now().subtract(const Duration(hours: 1)),
      author: de ?? autor(),
    );
  }

  Future<void> montar(
    WidgetTester tester,
    Widget child, {
    double ancho = 390,
    ThemeData? tema,
  }) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: tema ?? AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('una pregunta sin responder muestra el badge de pendiente', (
    tester,
  ) async {
    await montar(tester, QuestionTile(question: pregunta()));

    expect(find.text('¿Sigue disponible en color negro?'), findsOneWidget);
    expect(find.text('Mariana Peña'), findsOneWidget);
    expect(find.text('Pendiente de respuesta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solo el nombre del autor abre su perfil', (tester) async {
    var aperturas = 0;
    await montar(
      tester,
      QuestionTile(question: pregunta(), onAuthorTap: () => aperturas++),
    );

    await tester.tap(find.text('Mariana Peña'));
    expect(aperturas, 1);

    await tester.tap(find.text('¿Sigue disponible en color negro?'));
    expect(aperturas, 1);
  });

  testWidgets('una respondida muestra la respuesta firmada por el vendedor', (
    tester,
  ) async {
    await montar(
      tester,
      QuestionTile(
        question: pregunta(respuesta: 'Sí, me quedan dos.'),
        sellerName: 'Ana Valdés',
      ),
    );

    expect(find.text('Sí, me quedan dos.'), findsOneWidget);
    expect(find.text('Respuesta de Ana Valdés'), findsOneWidget);
    // Ya respondida: el badge de pendiente no debe seguir ahí.
    expect(find.text('Pendiente de respuesta'), findsNothing);
  });

  testWidgets('sin nombre de vendedor la respuesta se firma genérica', (
    tester,
  ) async {
    await montar(
      tester,
      QuestionTile(question: pregunta(respuesta: 'Sí, todavía')),
    );

    expect(find.text('Respuesta del vendedor'), findsOneWidget);
  });

  testWidgets('la respuesta va indentada respecto a la pregunta', (
    tester,
  ) async {
    // Es lo único que marca quién habla: si la sangría se perdiera, pregunta
    // y respuesta se leerían como un solo bloque de texto.
    await montar(
      tester,
      QuestionTile(
        question: pregunta(respuesta: 'Sí, me quedan dos.'),
        sellerName: 'Ana Valdés',
      ),
    );

    final xPregunta = tester
        .getTopLeft(find.text('¿Sigue disponible en color negro?'))
        .dx;
    final xRespuesta = tester.getTopLeft(find.text('Sí, me quedan dos.')).dx;

    expect(xRespuesta, greaterThan(xPregunta));
  });

  testWidgets('el input de respuesta reemplaza al badge de pendiente', (
    tester,
  ) async {
    // Para el dueño, una pregunta pendiente no necesita que le digan que
    // está pendiente: necesita el campo para contestarla.
    await montar(
      tester,
      QuestionTile(
        question: pregunta(),
        respuestaInline: const Text('INPUT DE RESPUESTA'),
      ),
    );

    expect(find.text('INPUT DE RESPUESTA'), findsOneWidget);
    expect(find.text('Pendiente de respuesta'), findsNothing);
  });

  testWidgets('destacada cambia el fondo y sin destacar es transparente', (
    tester,
  ) async {
    await montar(tester, QuestionTile(question: pregunta(), destacada: true));
    final resaltado = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final decoracionResaltada = resaltado.decoration! as BoxDecoration;

    await montar(tester, QuestionTile(question: pregunta()));
    final normal = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final decoracionNormal = normal.decoration! as BoxDecoration;

    expect(decoracionResaltada.color, isNot(Colors.transparent));
    expect(decoracionNormal.color, Colors.transparent);
  });

  testWidgets('textos largos no desbordan a 320 px', (tester) async {
    await montar(
      tester,
      QuestionTile(
        question: pregunta(
          texto: 'Hola, quería preguntar ${'muchísimo texto ' * 20}',
          respuesta: 'Claro que sí, ${'te explico con detalle ' * 20}',
          de: autor(name: 'Comercializadora Universitaria del Norte S.A.'),
        ),
        sellerName: 'Comercializadora Universitaria del Norte S.A. de C.V.',
      ),
      ancho: 320,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('se pinta igual en modo oscuro', (tester) async {
    await montar(
      tester,
      QuestionTile(
        question: pregunta(respuesta: 'Sí, me quedan dos.'),
        sellerName: 'Ana Valdés',
      ),
      tema: AppTheme.dark(),
    );

    expect(find.text('Sí, me quedan dos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el esqueleto se pinta sin errores', (tester) async {
    await montar(tester, const QuestionTileSkeleton());

    expect(tester.takeException(), isNull);
  });
}
