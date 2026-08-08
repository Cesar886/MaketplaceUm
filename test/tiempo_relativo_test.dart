import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/utils/tiempo_relativo.dart';

void main() {
  // Instante fijo para que los tests no dependan del reloj de quien los corre.
  final ahora = DateTime(2026, 8, 8, 12, 0, 0);

  String hace(Duration d) => tiempoRelativo(ahora.subtract(d), ahora: ahora);

  test('menos de un minuto se resume en "hace un momento"', () {
    expect(hace(Duration.zero), 'hace un momento');
    expect(hace(const Duration(seconds: 59)), 'hace un momento');
  });

  test('una fecha en el futuro no dice "en X"', () {
    // Pasa cuando el reloj del dispositivo va atrasado respecto al servidor.
    // "en 3 minutos" sobre un comentario ya publicado se lee como un bug.
    expect(
      tiempoRelativo(ahora.add(const Duration(minutes: 3)), ahora: ahora),
      'hace un momento',
    );
  });

  test('minutos', () {
    expect(hace(const Duration(minutes: 1)), 'hace 1 min');
    expect(hace(const Duration(minutes: 59)), 'hace 59 min');
  });

  test('horas', () {
    expect(hace(const Duration(hours: 1)), 'hace 1 h');
    expect(hace(const Duration(hours: 23)), 'hace 23 h');
  });

  test('días, con singular y plural', () {
    expect(hace(const Duration(days: 1)), 'hace 1 día');
    expect(hace(const Duration(days: 6)), 'hace 6 días');
  });

  test('semanas', () {
    expect(hace(const Duration(days: 7)), 'hace 1 semana');
    expect(hace(const Duration(days: 20)), 'hace 2 semanas');
  });

  test('meses', () {
    expect(hace(const Duration(days: 30)), 'hace 1 mes');
    expect(hace(const Duration(days: 90)), 'hace 3 meses');
  });

  test('años', () {
    expect(hace(const Duration(days: 365)), 'hace 1 año');
    expect(hace(const Duration(days: 800)), 'hace 2 años');
  });

  test('los límites entre unidades no dejan huecos', () {
    // Cada frontera debe caer en la unidad de arriba, sin saltarse a la
    // siguiente ni repetir la anterior.
    expect(hace(const Duration(minutes: 60)), 'hace 1 h');
    expect(hace(const Duration(hours: 24)), 'hace 1 día');
    expect(hace(const Duration(days: 7)), 'hace 1 semana');
    expect(hace(const Duration(days: 30)), 'hace 1 mes');
    expect(hace(const Duration(days: 365)), 'hace 1 año');
  });
}
