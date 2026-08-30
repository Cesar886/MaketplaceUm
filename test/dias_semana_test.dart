// Los nombres de los días en el editor de "Horario de atención".
//
// El bug que motiva estos tests: los widgets guardaban la CLAVE de traducción
// ('weekday_full.wed') en una lista y la pintaban sin llamar a `.tr()`, así que
// las filas mostraban la clave cruda y los chips su recorte a 3 caracteres
// ('wee'). Nada en el i18n estaba roto — la clave existía en los dos idiomas —,
// solo faltaba traducir. Por eso lo que se protege aquí es que el texto que sale
// a pantalla sea el traducido, en español y en inglés.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/app_theme.dart';
import 'package:mercadito_um/config/locales.dart';
import 'package:mercadito_um/constants/dias_semana.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/business_hours_editor.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  Widget envolver(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  Widget editorCon(Map<int, BusinessHoursRange> horas) => envolver(
    BusinessHoursEditor(initialHours: horas, onChanged: (_) {}),
  );

  // 2=miércoles, 3=jueves (0=lunes..6=domingo).
  const horario = {
    2: BusinessHoursRange(open: '09:00', close: '18:00'),
    3: BusinessHoursRange(open: '09:00', close: '18:00'),
  };

  group('en español', () {
    setUp(() => inicializarTraducciones(locale: AppLocales.es));

    test('el nombre largo va con mayúscula inicial', () {
      expect(nombreLargoDia(2), 'Miércoles');
      expect(nombreLargoDia(5), 'Sábado');
    });

    test('el nombre dentro de una frase se queda en minúscula', () {
      expect(nombreDiaEnFrase(2), 'miércoles');
    });

    test('el nombre corto es la abreviatura traducida, no un recorte', () {
      expect(nombreCortoDia(2), 'Mié');
      expect(nombreCortoDia(6), 'Dom');
    });

    testWidgets('los chips muestran la abreviatura completa', (tester) async {
      await tester.pumpWidget(editorCon(const {}));

      for (final abreviatura in ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']) {
        expect(find.text(abreviatura), findsOneWidget);
      }
      // El síntoma exacto del bug: el recorte de la clave a 3 caracteres.
      expect(find.text('wee'), findsNothing);
    });

    testWidgets('las filas muestran el día traducido, no la clave', (
      tester,
    ) async {
      await tester.pumpWidget(editorCon(horario));

      expect(find.text('Miércoles'), findsOneWidget);
      expect(find.text('Jueves'), findsOneWidget);
      expect(find.text('weekday_full.wed'), findsNothing);
      expect(find.text('weekday_full.thu'), findsNothing);
    });

    testWidgets('el nombre del día no se recorta', (tester) async {
      await tester.pumpWidget(editorCon(horario));

      // Solo comprueba que nadie le ponga un recorte al texto ni deje la
      // columna tan estrecha que Flutter marque overflow. El ancho exacto que
      // ocupa 'Miércoles' no se puede afirmar aquí: los widget tests usan una
      // tipografía de prueba monoespaciada que no mide como la real.
      final texto = tester.widget<Text>(find.text('Miércoles'));
      expect(texto.overflow, isNot(TextOverflow.ellipsis));
      expect(tester.takeException(), isNull);
    });
  });

  group('en inglés', () {
    setUp(() => inicializarTraducciones(locale: AppLocales.en));
    // El diccionario es un singleton: se deja en español para no contaminar
    // lo que corra después.
    tearDownAll(() => inicializarTraducciones(locale: AppLocales.es));

    test('los nombres salen en inglés', () {
      expect(nombreLargoDia(2), 'Wednesday');
      expect(nombreDiaEnFrase(2), 'Wednesday');
      expect(nombreCortoDia(2), 'Wed');
    });

    testWidgets('chips y filas usan el idioma activo', (tester) async {
      await tester.pumpWidget(editorCon(horario));

      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Wednesday'), findsOneWidget);
      expect(find.text('Thursday'), findsOneWidget);
      expect(find.text('weekday_full.wed'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
