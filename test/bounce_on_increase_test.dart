import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/bounce_on_increase.dart';

/// Envoltorio que deja cambiar el valor observado desde el test sin
/// reconstruir todo el árbol: [BounceOnIncrease] reacciona en
/// `didUpdateWidget`, así que necesita seguir siendo el MISMO elemento entre
/// pumps para que la comparación viejo/nuevo tenga sentido.
class _Host extends StatefulWidget {
  const _Host({required this.inicial, this.haptic = false});

  final int inicial;
  final bool haptic;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int _valor = widget.inicial;

  void cambiarA(int nuevo) => setState(() => _valor = nuevo);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: BounceOnIncrease(
          value: _valor,
          haptic: widget.haptic,
          child: const Icon(Icons.favorite),
        ),
      ),
    );
  }
}

/// Escala aplicada ahora mismo por el widget.
///
/// Se acota a los descendientes de [BounceOnIncrease]: MaterialApp mete sus
/// propios ScaleTransition (transiciones de página), así que un
/// `find.byType(ScaleTransition)` suelto encuentra varios.
double _escalaActual(WidgetTester tester) {
  final transition = tester.widget<ScaleTransition>(
    find.descendant(
      of: find.byType(BounceOnIncrease),
      matching: find.byType(ScaleTransition),
    ),
  );
  return transition.scale.value;
}

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(const _Host(inicial: 0));

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('rests at scale 1.0 when nothing changed', (tester) async {
    await tester.pumpWidget(const _Host(inicial: 3));

    expect(_escalaActual(tester), 1.0);
  });

  testWidgets('bounces past 1.0 when the value increases', (tester) async {
    await tester.pumpWidget(const _Host(inicial: 0));
    tester.state<_HostState>(find.byType(_Host)).cambiarA(1);
    await tester.pump();

    // A media animación el ícono tiene que estar agrandado; si se quedara en
    // 1.0 el rebote no existe aunque el controller sí corra.
    await tester.pump(const Duration(milliseconds: 90));
    expect(_escalaActual(tester), greaterThan(1.0));
  });

  testWidgets('settles back to 1.0 after bouncing', (tester) async {
    await tester.pumpWidget(const _Host(inicial: 0));
    tester.state<_HostState>(find.byType(_Host)).cambiarA(1);
    await tester.pumpAndSettle();

    expect(_escalaActual(tester), mosCerca(1.0));
  });

  testWidgets('does NOT bounce when the value decreases', (tester) async {
    // Quitar un favorito no se celebra: el rebote marca "se agregó algo", y
    // dispararlo al desmarcar haría que la animación no signifique nada.
    await tester.pumpWidget(const _Host(inicial: 2));
    tester.state<_HostState>(find.byType(_Host)).cambiarA(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(_escalaActual(tester), 1.0);
  });

  testWidgets('does NOT bounce when the value is unchanged', (tester) async {
    await tester.pumpWidget(const _Host(inicial: 2));
    tester.state<_HostState>(find.byType(_Host)).cambiarA(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    expect(_escalaActual(tester), 1.0);
  });

  testWidgets('fires haptic feedback on increase when haptic is on', (
    tester,
  ) async {
    final llamadas = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          llamadas.add(call.arguments as String? ?? '');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const _Host(inicial: 0, haptic: true));
    tester.state<_HostState>(find.byType(_Host)).cambiarA(1);
    await tester.pump();

    expect(llamadas, isNotEmpty);
  });

  testWidgets('stays silent on increase when haptic is off', (tester) async {
    final llamadas = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          llamadas.add(call.arguments as String? ?? '');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const _Host(inicial: 0));
    tester.state<_HostState>(find.byType(_Host)).cambiarA(1);
    await tester.pump();

    expect(llamadas, isEmpty);
  });
}

/// `closeTo` con la tolerancia que necesita una curva con overshoot al cerrar.
Matcher mosCerca(double valor) => closeTo(valor, 0.001);
