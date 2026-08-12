import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/utils/fecha_monterrey.dart';

void main() {
  group('horaMonterrey', () {
    test('una fecha de SQLite sin zona se trata como UTC, no como local', () {
      // Formato exacto que emite `datetime('now')`: sin T y sin Z.
      // 05:48 UTC son las 23:48 del día anterior en Monterrey.
      expect(horaMonterrey('2026-08-03 05:48:33'), '23:48');
    });

    test('ISO-8601 con Z da el mismo resultado', () {
      expect(horaMonterrey('2026-08-03T05:48:33Z'), '23:48');
    });

    test('respeta un offset explícito distinto de UTC', () {
      // 12:00 en UTC+2 son las 10:00 UTC → 04:00 en Monterrey.
      expect(horaMonterrey('2026-08-03T12:00:00+02:00'), '04:00');
    });

    test('no aplica horario de verano en ninguna época del año', () {
      // México eliminó el DST en 2022: julio y enero deben desplazarse igual.
      expect(horaMonterrey('2026-07-15 18:00:00'), '12:00');
      expect(horaMonterrey('2026-01-15 18:00:00'), '12:00');
    });

    test('rellena con cero a la izquierda', () {
      expect(horaMonterrey('2026-08-03 14:05:00'), '08:05');
    });

    test('una fecha inválida o vacía no rompe la burbuja', () {
      expect(horaMonterrey(null), '');
      expect(horaMonterrey(''), '');
      expect(horaMonterrey('no es una fecha'), '');
    });
  });

  group('enHoraMonterrey', () {
    test('cruza el cambio de día hacia atrás', () {
      final dt = enHoraMonterrey('2026-08-03 05:48:33')!;
      expect(dt.year, 2026);
      expect(dt.month, 8);
      expect(dt.day, 2); // el día anterior
      expect(dt.hour, 23);
    });

    test('preserva el orden cronológico', () {
      final antes = enHoraMonterrey('2026-08-03 05:48:33')!;
      final despues = enHoraMonterrey('2026-08-03 05:49:00')!;
      expect(antes.isBefore(despues), isTrue);
    });
  });
}
