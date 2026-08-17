import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/screens/onboarding_screen.dart';
import 'package:mercadito_um/services/onboarding_service.dart';
import 'package:mercadito_um/widgets/onboarding_illustrations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mercadito_um/providers/accent_provider.dart';

Widget _app({required VoidCallback alTerminar}) {
  return ChangeNotifierProvider(
    create: (_) => AccentProvider(),
    child: MaterialApp(home: OnboardingScreen(onFinish: alTerminar)),
  );
}

void main() {
  group('OnboardingService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a fresh install has not seen the onboarding', () async {
      expect(await OnboardingService.hasSeenOnboarding(), isFalse);
    });

    test('markSeen makes it stick', () async {
      await OnboardingService.markSeen();

      expect(await OnboardingService.hasSeenOnboarding(), isTrue);
    });

    test('reset brings it back for the next launch', () async {
      await OnboardingService.markSeen();
      await OnboardingService.reset();

      expect(await OnboardingService.hasSeenOnboarding(), isFalse);
    });
  });

  group('OnboardingScreen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('opens on the first slide', (tester) async {
      await tester.pumpWidget(_app(alTerminar: () {}));

      expect(find.text(slidesOnboarding.first.titulo), findsOneWidget);
    });

    testWidgets('draws an illustration, not a bare text screen', (
      tester,
    ) async {
      await tester.pumpWidget(_app(alTerminar: () {}));

      expect(find.byType(OnboardingIllustration), findsWidgets);
    });

    testWidgets('the last slide is reachable and ends the flow', (
      tester,
    ) async {
      var termino = false;
      await tester.pumpWidget(_app(alTerminar: () => termino = true));

      // Avanzar hasta la última: el botón primario lleva de slide en slide.
      for (var i = 0; i < slidesOnboarding.length - 1; i++) {
        await tester.tap(find.byKey(const Key('onboarding-primario')));
        await tester.pumpAndSettle();
      }

      expect(find.text(slidesOnboarding.last.titulo), findsOneWidget);
      expect(find.text('Empezar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-primario')));
      await tester.pumpAndSettle();

      expect(termino, isTrue);
      expect(await OnboardingService.hasSeenOnboarding(), isTrue);
    });

    testWidgets('skipping ends the flow and records it as seen', (
      tester,
    ) async {
      var termino = false;
      await tester.pumpWidget(_app(alTerminar: () => termino = true));

      await tester.tap(find.text('Saltar'));
      await tester.pumpAndSettle();

      // Saltar cuenta como visto: si volviera a aparecer, el botón no
      // estaría saltando nada.
      expect(termino, isTrue);
      expect(await OnboardingService.hasSeenOnboarding(), isTrue);
    });

    testWidgets('hides Skip on the last slide', (tester) async {
      await tester.pumpWidget(_app(alTerminar: () {}));

      for (var i = 0; i < slidesOnboarding.length - 1; i++) {
        await tester.tap(find.byKey(const Key('onboarding-primario')));
        await tester.pumpAndSettle();
      }

      // En la última no queda nada que saltar, y dejarlo compite con
      // "Empezar" justo donde el usuario tiene que decidir.
      expect(find.text('Saltar'), findsNothing);
    });
  });
}
