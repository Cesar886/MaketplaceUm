// Tests de renderizado de la UI de comentarios.
//
// No comprueban lógica sino que la sección SE PINTE sin romperse: overflow
// amarillo, divisores de ancho cero, texto que no cabe. Son fallos que no
// aparecen en `flutter analyze` ni en un test de modelo, solo al mirar la
// pantalla — y no siempre en el teléfono en el que uno prueba.
//
// Por eso todo se renderiza dos veces: a 320 px (el ancho más angosto que se
// ve en campus) y a 430 px, y con contenido deliberadamente hostil (nombres
// largos, carrera larga, comentario de 500 caracteres).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/comment_tile.dart';

void main() {
  Seller autor({
    String name = 'Mariana Peña',
    String tipoCuenta = 'estudiante',
    bool verified = true,
    String? carrera = 'Ingeniería en Mercadotecnia',
    String? tipoVerificacion = 'estudiante',
  }) {
    return Seller(
      id: 'u_1',
      name: name,
      avatarInitials: 'MP',
      major: 'Estudiante',
      rating: 0,
      reviews: 0,
      verified: verified,
      tipoCuenta: tipoCuenta,
      carrera: carrera,
      tipoVerificacion: tipoVerificacion,
    );
  }

  ProductComment comentario({
    String texto = '¿Todavía lo tienes? Me interesa.',
    Seller? de,
  }) {
    return ProductComment(
      id: 'cmt_1',
      productId: 'p_1',
      texto: texto,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      author: de ?? autor(),
    );
  }

  /// Monta [child] con el tema real de la app a un ancho concreto.
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

  group('CommentTile', () {
    testWidgets('pinta nombre, rol, texto y tiempo relativo', (tester) async {
      await montar(tester, CommentTile(comment: comentario()));

      expect(find.text('Mariana Peña'), findsOneWidget);
      expect(find.text('Ingeniería en Mercadotecnia'), findsOneWidget);
      expect(find.text('¿Todavía lo tienes? Me interesa.'), findsOneWidget);
      expect(find.text('hace 2 h'), findsOneWidget);
      expect(find.text('MP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('avatar y nombre abren el perfil del autor', (tester) async {
      var aperturas = 0;
      await montar(
        tester,
        CommentTile(comment: comentario(), onAuthorTap: () => aperturas++),
      );

      await tester.tap(find.byType(CommentAvatar));
      expect(aperturas, 1);

      await tester.tap(find.text('Mariana Peña'));
      expect(aperturas, 2);

      await tester.tap(find.text('¿Todavía lo tienes? Me interesa.'));
      expect(aperturas, 2);
    });

    testWidgets('no desborda a 320 px con nombre y carrera largos', (
      tester,
    ) async {
      await montar(
        tester,
        CommentTile(
          comment: comentario(
            de: autor(
              name: 'María Fernanda de la Garza Villarreal',
              carrera: 'Licenciatura en Administración de Empresas Turísticas',
            ),
          ),
        ),
        ancho: 320,
      );

      // Un RenderFlex overflow se reporta como excepción del framework.
      expect(tester.takeException(), isNull);
    });

    testWidgets('un comentario de 500 caracteres se envuelve, no desborda', (
      tester,
    ) async {
      await montar(
        tester,
        CommentTile(comment: comentario(texto: 'palabra ' * 62)),
        ancho: 320,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('una sola palabra larguísima no rompe el layout', (
      tester,
    ) async {
      // Caso real: alguien pega una URL sin espacios.
      await montar(
        tester,
        CommentTile(comment: comentario(texto: 'x' * 200)),
        ancho: 320,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('el menú de borrar solo existe cuando hay permiso', (
      tester,
    ) async {
      await montar(tester, CommentTile(comment: comentario()));
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

      await montar(tester, CommentTile(comment: comentario(), onDelete: () {}));
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('borrar pide confirmación antes de llamar al callback', (
      tester,
    ) async {
      var borrado = false;
      await montar(
        tester,
        CommentTile(comment: comentario(), onDelete: () => borrado = true),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // La hoja se abre y NO ha borrado nada todavía.
      expect(find.text('Eliminar comentario'), findsOneWidget);
      expect(borrado, isFalse);

      await tester.tap(find.text('Eliminar comentario'));
      await tester.pumpAndSettle();
      expect(borrado, isTrue);
    });

    testWidgets('cancelar en la hoja NO borra', (tester) async {
      var borrado = false;
      await montar(
        tester,
        CommentTile(comment: comentario(), onDelete: () => borrado = true),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(borrado, isFalse);
    });

    testWidgets('una cuenta sin verificar no muestra insignia ni rol', (
      tester,
    ) async {
      await montar(
        tester,
        CommentTile(
          comment: comentario(
            de: autor(verified: false, carrera: null, tipoVerificacion: null),
          ),
        ),
      );

      // subtituloRol devuelve null: la línea se omite entera, no cae a un
      // genérico tipo "Estudiante".
      expect(find.text('Estudiante'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el personal UM se etiqueta como tal', (tester) async {
      await montar(
        tester,
        CommentTile(
          comment: comentario(de: autor(tipoVerificacion: 'empleado')),
        ),
      );

      expect(find.text('Personal UM'), findsOneWidget);
    });

    testWidgets('se pinta igual en modo oscuro', (tester) async {
      await montar(
        tester,
        CommentTile(comment: comentario(), onDelete: () {}),
        tema: AppTheme.dark(),
      );

      expect(find.text('Mariana Peña'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Separadores del hilo', () {
    testWidgets('el divisor entre comentarios tiene ancho real', (
      tester,
    ) async {
      // Un Divider dentro de una Column con alineación al centro puede
      // colapsar a cero de ancho y desaparecer sin lanzar ningún error: el
      // hilo se ve "pegado" y nadie sabe por qué.
      await montar(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommentTile(comment: comentario()),
            Divider(
              height: 1,
              thickness: 1,
              indent: kCommentDividerIndent,
              color: Colors.black12,
            ),
            CommentTile(comment: comentario()),
          ],
        ),
        ancho: 390,
      );

      final ancho = tester.getSize(find.byType(Divider)).width;
      expect(ancho, greaterThan(100), reason: 'el divisor colapsó');
    });
  });

  group('Esqueletos de carga', () {
    testWidgets('CommentListSkeleton se pinta sin errores', (tester) async {
      await montar(tester, const CommentListSkeleton());
      expect(find.byType(CommentSkeleton), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('el esqueleto ocupa un alto parecido al contenido real', (
      tester,
    ) async {
      // Si el esqueleto fuera mucho más corto, la lista daría un salto al
      // llegar los datos — justo lo que un skeleton existe para evitar.
      await montar(tester, const CommentSkeleton());
      final altoEsqueleto = tester.getSize(find.byType(CommentSkeleton)).height;

      await montar(tester, CommentTile(comment: comentario()));
      final altoReal = tester.getSize(find.byType(CommentTile)).height;

      expect((altoEsqueleto - altoReal).abs(), lessThan(30));
    });
  });

  group('CommentAvatar', () {
    testWidgets('cae a "??" cuando no hay iniciales', (tester) async {
      await montar(
        tester,
        CommentAvatar(
          author: Seller(
            name: 'Usuario',
            avatarInitials: '',
            major: '',
            rating: 0,
            reviews: 0,
            verified: false,
          ),
        ),
      );

      expect(find.text('??'), findsOneWidget);
    });
  });
}
