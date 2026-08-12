import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/profile_banner.dart';

void main() {
  testWidgets('el gradiente va del color elegido (a 42%) a fadeTo', (
    tester,
  ) async {
    const color = Color(0xFF6B2737); // wine
    const fadeTo = Colors.white;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileBanner(
            color: color,
            fadeTo: fadeTo,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    );

    final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final gradient =
        (decorated.decoration as BoxDecoration).gradient as LinearGradient;

    expect(gradient.colors.first, color.withValues(alpha: 0.42));
    expect(gradient.colors.last, fadeTo);
    // Nunca opaco: un banner sólido detrás del nombre podría bajar el
    // contraste del texto con los swatches oscuros (navy, wine).
    expect(gradient.colors.first.a, closeTo(0.42, 0.01));
  });

  testWidgets('el alto se adapta al child y se extiende extraFade por debajo', (
    tester,
  ) async {
    const childHeight = 92.0;
    const extraFade = 30.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileBanner(
            color: Colors.blue,
            fadeTo: Colors.white,
            extraFade: extraFade,
            child: const SizedBox(width: 92, height: childHeight),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(ProfileBanner));
    // El banner "llega un poco más abajo" del contenido: su alto total es
    // el del contenido MÁS el desvanecido, sin importar qué tan alto sea
    // ese contenido — esto es lo que hace que el mismo widget sirva tanto
    // para "solo el avatar" como para "avatar + nombre".
    expect(size.height, childHeight + extraFade);
  });

  testWidgets('sin extraFade el banner mide exactamente lo del child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileBanner(
            color: Colors.blue,
            fadeTo: Colors.white,
            extraFade: 0,
            child: const SizedBox(width: 92, height: 60),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(ProfileBanner));
    expect(size.height, 60);
  });

  testWidgets('el child se pinta y queda centrado horizontalmente', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ProfileBanner(
              color: Colors.blue,
              fadeTo: Colors.white,
              child: Container(key: const Key('avatar'), width: 80, height: 80),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('avatar')), findsOneWidget);
    final bannerLeft = tester.getTopLeft(find.byType(ProfileBanner)).dx;
    final bannerWidth = tester.getSize(find.byType(ProfileBanner)).width;
    final childCenter = tester.getCenter(find.byKey(const Key('avatar'))).dx;
    expect(childCenter, closeTo(bannerLeft + bannerWidth / 2, 0.5));
  });
}
