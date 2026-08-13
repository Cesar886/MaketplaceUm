// Tests del modelo de preguntas y respuestas.
//
// El punto delicado es el estado: `status` y `answerText` llegan por
// separado y la UI decide con ellos si pinta la respuesta o el badge de
// "pendiente". Una respuesta visible con badge de pendiente al lado, o al
// revés, es el tipo de incoherencia que no rompe nada y se ve fatal.

import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';

void main() {
  Map<String, dynamic> autorJson() => {
    'id': 'u_1',
    'name': 'Mariana Peña',
    'avatarInitials': 'MP',
    'major': 'Estudiante',
    'isBusiness': false,
    'verified': true,
    'tipoCuenta': 'estudiante',
    'carrera': 'Ingeniería en Mercadotecnia',
    'tipoVerificacion': 'estudiante',
  };

  Map<String, dynamic> preguntaJson({
    String? answerText,
    String? status,
    String? answeredAt,
    bool incluirStatus = true,
  }) {
    return {
      'id': 'q_1',
      'productId': 'p_1',
      'questionText': '¿Sigue disponible?',
      'answerText': answerText,
      if (incluirStatus)
        'status': status ?? (answerText == null ? 'pending' : 'answered'),
      'createdAt': '2026-08-08T18:00:00Z',
      'answeredAt': answeredAt,
      'author': autorJson(),
    };
  }

  test('una pregunta sin responder llega pendiente y sin respuesta', () {
    final q = ProductQuestion.fromJson(preguntaJson());

    expect(q.id, 'q_1');
    expect(q.questionText, '¿Sigue disponible?');
    expect(q.answerText, isNull);
    expect(q.status, 'pending');
    expect(q.answeredAt, isNull);
    expect(q.isAnswered, isFalse);
  });

  test('una pregunta respondida trae respuesta, estado y fecha', () {
    final q = ProductQuestion.fromJson(
      preguntaJson(
        answerText: 'Sí, me quedan dos.',
        answeredAt: '2026-08-08T19:30:00Z',
      ),
    );

    expect(q.answerText, 'Sí, me quedan dos.');
    expect(q.status, 'answered');
    expect(q.isAnswered, isTrue);
    expect(q.answeredAt, isNotNull);
  });

  test('las fechas se interpretan como UTC y pasan a hora local', () {
    // El backend guarda UTC. Si se leyera como local, el "hace 2 h" saldría
    // corrido por el offset del dispositivo — seis horas en campus.
    final q = ProductQuestion.fromJson(
      preguntaJson(answerText: 'Sí', answeredAt: '2026-08-08T19:30:00Z'),
    );

    expect(q.createdAt.isUtc, isFalse);
    expect(q.createdAt.toUtc(), DateTime.utc(2026, 8, 8, 18));
    expect(q.answeredAt!.toUtc(), DateTime.utc(2026, 8, 8, 19, 30));
  });

  test('sin campo status se deduce del texto de la respuesta', () {
    // Defensa contra una respuesta vieja o recortada: lo que no puede pasar
    // es pintar una respuesta y marcarla como pendiente.
    final conRespuesta = ProductQuestion.fromJson(
      preguntaJson(answerText: 'Sí, todavía', incluirStatus: false),
    );
    final sinRespuesta = ProductQuestion.fromJson(
      preguntaJson(incluirStatus: false),
    );

    expect(conRespuesta.status, 'answered');
    expect(conRespuesta.isAnswered, isTrue);
    expect(sinRespuesta.status, 'pending');
    expect(sinRespuesta.isAnswered, isFalse);
  });

  test('una respuesta vacía cuenta como no respondida', () {
    final q = ProductQuestion.fromJson(preguntaJson(answerText: ''));

    expect(q.answerText, isNull);
    expect(q.isAnswered, isFalse);
  });

  test('el autor se resuelve con lo mínimo para pintar su insignia', () {
    final q = ProductQuestion.fromJson(preguntaJson());

    expect(q.author.name, 'Mariana Peña');
    expect(q.author.verified, isTrue);
    expect(q.author.carrera, 'Ingeniería en Mercadotecnia');
  });

  test('la página trae filas, cursor y los dos contadores', () {
    final pagina = ProductQuestionPage.fromJson({
      'questions': [preguntaJson(), preguntaJson(answerText: 'Sí')],
      'nextCursor': '2026-08-08 18:00:00|q_1',
      'total': 12,
      'pendingCount': 4,
    });

    expect(pagina.questions.length, 2);
    expect(pagina.total, 12);
    expect(pagina.pendingCount, 4);
    expect(pagina.hasMore, isTrue);
  });

  test('una página sin cursor es la última', () {
    final pagina = ProductQuestionPage.fromJson({
      'questions': <dynamic>[],
      'total': 0,
      'pendingCount': 0,
    });

    expect(pagina.questions, isEmpty);
    expect(pagina.hasMore, isFalse);
  });

  test('una respuesta sin la clave questions no revienta', () {
    final pagina = ProductQuestionPage.fromJson(const {});

    expect(pagina.questions, isEmpty);
    expect(pagina.total, 0);
    expect(pagina.pendingCount, 0);
  });
}
