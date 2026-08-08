import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';

void main() {
  Map<String, dynamic> json({
    String createdAt = '2026-08-08T18:00:00Z',
    Map<String, dynamic>? author,
    Map<String, dynamic>? product,
  }) {
    return {
      'id': 'cmt_1',
      'productId': 'p_1',
      'texto': 'Me interesa',
      'createdAt': createdAt,
      'author': author ??
          {
            'id': 'u_1',
            'name': 'Mariana Peña',
            'avatarInitials': 'MP',
            'major': 'Estudiante',
            'isBusiness': false,
            'verified': true,
            'tipoCuenta': 'estudiante',
            'carrera': 'Ingeniería en Mercadotecnia',
            'tipoVerificacion': 'estudiante',
          },
      if (product != null) 'product': product,
    };
  }

  test('parsea el comentario y su autor', () {
    final c = ProductComment.fromJson(json());

    expect(c.id, 'cmt_1');
    expect(c.productId, 'p_1');
    expect(c.texto, 'Me interesa');
    expect(c.author.name, 'Mariana Peña');
    expect(c.author.carrera, 'Ingeniería en Mercadotecnia');
    expect(c.author.verified, isTrue);
  });

  test('createdAt se interpreta como UTC y se pasa a hora local', () {
    // El backend guarda UTC. Si se leyera como hora local, el "hace 2 h"
    // saldría corrido por el offset del dispositivo — seis horas en campus.
    final c = ProductComment.fromJson(json(createdAt: '2026-08-08T18:00:00Z'));

    expect(c.createdAt.isUtc, isFalse, reason: 'debe quedar en hora local');
    expect(
      c.createdAt.toUtc(),
      DateTime.utc(2026, 8, 8, 18, 0, 0),
    );
  });

  test('un createdAt sin zona se asume UTC, no local', () {
    // Formato crudo de SQLite ('YYYY-MM-DD HH:MM:SS'). Es UTC aunque no lo
    // diga, y `DateTime.parse` lo leería como local si no se le agrega la Z.
    final c = ProductComment.fromJson(json(createdAt: '2026-08-08 18:00:00'));

    expect(c.createdAt.toUtc(), DateTime.utc(2026, 8, 8, 18, 0, 0));
  });

  test('un createdAt basura no revienta el parseo del hilo', () {
    final c = ProductComment.fromJson(json(createdAt: 'no-es-una-fecha'));
    expect(c.texto, 'Me interesa');
  });

  test('sin datos del producto, título y miniatura quedan en null', () {
    // Es el caso del hilo dentro del detalle: ya sabes en qué publicación
    // estás, así que el backend no repite el producto en cada fila.
    final c = ProductComment.fromJson(json());

    expect(c.productTitle, isNull);
    expect(c.productImage, isNull);
  });

  test('en el feed del perfil, el id del producto sale de `product`', () {
    final c = ProductComment.fromJson({
      'id': 'cmt_2',
      'texto': 'Excelente vendedor',
      'createdAt': '2026-08-08T18:00:00Z',
      'author': {'id': 'u_2', 'name': 'Ana', 'avatarInitials': 'AN'},
      'product': {
        'id': 'p_99',
        'title': 'Audífonos Sony',
        'image': '/uploads/sony.webp',
      },
    });

    expect(c.productId, 'p_99');
    expect(c.productTitle, 'Audífonos Sony');
    expect(c.productImage, '/uploads/sony.webp');
  });

  test('un autor sin campos cae a defaults en vez de lanzar', () {
    // Cuenta borrada: el comentario sigue en pie y el hilo no debe romperse.
    final c = ProductComment.fromJson(json(author: const {}));

    expect(c.author.name, '');
    expect(c.author.verified, isFalse);
    expect(c.author.tipoCuenta, 'particular');
  });

  test('ProductCommentPage conserva el total, no el tamaño de la página', () {
    final page = ProductCommentPage.fromJson({
      'comments': [json()],
      'total': 42,
      'nextCursor': '2026-08-08 18:00:00|cmt_1',
    });

    expect(page.comments.length, 1);
    expect(page.total, 42);
    expect(page.hasMore, isTrue);
  });

  test('sin nextCursor, la página se declara final', () {
    final page = ProductCommentPage.fromJson({
      'comments': <dynamic>[],
      'total': 0,
      'nextCursor': null,
    });

    expect(page.hasMore, isFalse);
    expect(page.comments, isEmpty);
  });
}
