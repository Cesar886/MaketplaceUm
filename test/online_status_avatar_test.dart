import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/widgets/online_status_avatar.dart';

void main() {
  Future<void> montar(
    WidgetTester tester, {
    required double radius,
    required bool enLinea,
    String? iniciales,
    bool mostrarIconoPorDefecto = false,
    Brightness brillo = Brightness.light,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: brillo == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: Center(
            child: OnlineStatusAvatar(
              radius: radius,
              iniciales: iniciales ?? 'DP',
              mostrarIconoPorDefecto: mostrarIconoPorDefecto,
              enLinea: enLinea,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('sin conexión no se pinta ningún punto', (tester) async {
    await montar(tester, radius: 24, enLinea: false);

    expect(find.byKey(OnlineStatusAvatar.puntoKey), findsNothing);
  });

  testWidgets('en línea aparece el punto sobre el avatar', (tester) async {
    await montar(tester, radius: 24, enLinea: true);

    expect(find.byKey(OnlineStatusAvatar.puntoKey), findsOneWidget);
  });

  testWidgets('el punto mide el 26% del diámetro del avatar pequeño', (
    tester,
  ) async {
    await montar(tester, radius: 24, enLinea: true);

    final tamano = tester.getSize(find.byKey(OnlineStatusAvatar.puntoKey));
    expect(tamano.width, closeTo(48 * 0.26, 0.01));
    expect(tamano.height, closeTo(48 * 0.26, 0.01));
  });

  testWidgets('el punto escala con el avatar grande del perfil', (
    tester,
  ) async {
    await montar(tester, radius: 40, enLinea: true);

    final tamano = tester.getSize(find.byKey(OnlineStatusAvatar.puntoKey));
    expect(tamano.width, closeTo(80 * 0.26, 0.01));
  });

  testWidgets('el avatar conserva su tamaño exacto con y sin punto', (
    tester,
  ) async {
    // El punto va superpuesto, no apilado: si el widget creciera al estar en
    // línea, las filas de la lista de chats bailarían al conectarse alguien.
    await montar(tester, radius: 24, enLinea: false);
    final sinPunto = tester.getSize(find.byType(OnlineStatusAvatar));

    await montar(tester, radius: 24, enLinea: true);
    final conPunto = tester.getSize(find.byType(OnlineStatusAvatar));

    expect(conPunto, sinPunto);
    expect(conPunto, const Size(48, 48));
  });

  testWidgets('muestra las iniciales cuando no hay foto', (tester) async {
    await montar(tester, radius: 24, enLinea: false, iniciales: 'MG');

    expect(find.text('MG'), findsOneWidget);
  });

  testWidgets('puede mostrar el avatar por defecto cuando no hay foto', (
    tester,
  ) async {
    await montar(
      tester,
      radius: 18,
      enLinea: false,
      iniciales: 'MG',
      mostrarIconoPorDefecto: true,
    );

    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.text('MG'), findsNothing);
  });

  testWidgets('el punto se anuncia a lectores de pantalla', (tester) async {
    // Un color no es información accesible: sin la etiqueta, quien navega con
    // TalkBack/VoiceOver no tiene forma de saber que la persona está en línea.
    final handle = tester.ensureSemantics();
    await montar(tester, radius: 24, enLinea: true);

    expect(find.bySemanticsLabel('En línea'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('el anillo del punto toma el color de la superficie del tema', (
    tester,
  ) async {
    // El anillo existe para separar el punto de la foto; si no siguiera al
    // tema, en modo oscuro sería un halo blanco pegado a la imagen.
    await montar(tester, radius: 24, enLinea: true, brillo: Brightness.dark);

    final punto = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(OnlineStatusAvatar.puntoKey),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoracion = punto.decoration as BoxDecoration;
    expect(decoracion.color, AppColors.onlineOnDark);
    expect(decoracion.border!.top.color, AppColors.darkSurface);
  });
}
