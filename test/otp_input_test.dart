import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/widgets/otp_input.dart';

void main() {
  Future<String?> montar(WidgetTester tester, {String? valorInicial}) async {
    String? completado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpInput(onCompleto: (codigo) => completado = codigo),
        ),
      ),
    );
    return completado;
  }

  testWidgets('muestra 6 casillas', (tester) async {
    await montar(tester);
    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('avanza a la siguiente casilla al escribir un dígito', (
    tester,
  ) async {
    await montar(tester);
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.pump();

    final segundo = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(segundo.focusNode!.hasFocus, isTrue);
  });

  testWidgets('avisa el código completo cuando se llenan las 6 casillas', (
    tester,
  ) async {
    String? completado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpInput(onCompleto: (codigo) => completado = codigo),
        ),
      ),
    );

    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byType(TextField).at(i), '${i + 1}');
      await tester.pump();
    }

    expect(completado, '123456');
  });

  testWidgets('no avisa mientras el código está incompleto', (tester) async {
    String? completado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpInput(onCompleto: (codigo) => completado = codigo),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byType(TextField).at(i), '1');
      await tester.pump();
    }

    expect(completado, isNull);
  });

  testWidgets('reparte un código pegado entre las 6 casillas', (tester) async {
    String? completado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpInput(onCompleto: (codigo) => completado = codigo),
        ),
      ),
    );

    // Pegar en la primera casilla debe llenar las seis, no truncar a un
    // dígito: es lo que pasa al usar el autofill del SMS o copiar del correo.
    await tester.enterText(find.byType(TextField).at(0), '987654');
    await tester.pump();

    expect(completado, '987654');
  });

  testWidgets('solo acepta dígitos', (tester) async {
    await montar(tester);
    await tester.enterText(find.byType(TextField).at(0), 'a');
    await tester.pump();

    final primero = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(primero.controller!.text, '');
  });

  testWidgets('regresa a la casilla anterior al borrar una vacía', (
    tester,
  ) async {
    await montar(tester);
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.pump();

    // La casilla 1 está enfocada y vacía: Backspace debe devolver el foco a
    // la 0 en vez de no hacer nada.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final primero = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(primero.focusNode!.hasFocus, isTrue);
  });

  testWidgets('limpiar() vacía todas las casillas', (tester) async {
    final llave = GlobalKey<OtpInputState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpInput(key: llave, onCompleto: (_) {}),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), '123456');
    await tester.pump();

    llave.currentState!.limpiar();
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      final campo = tester.widget<TextField>(find.byType(TextField).at(i));
      expect(campo.controller!.text, '');
    }
  });
}
