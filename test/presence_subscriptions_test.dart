import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/services/presence_subscriptions.dart';

void main() {
  late PresenceSubscriptions subs;

  setUp(() => subs = PresenceSubscriptions());

  test('la primera suscripción a alguien sí viaja al servidor', () {
    expect(subs.agregar(['u1', 'u2']), ['u1', 'u2']);
  });

  test('volver a pedir a alguien ya seguido no repite el emit', () {
    subs.agregar(['u1']);

    expect(subs.agregar(['u1', 'u2']), ['u2']);
  });

  test('soltar a alguien seguido por dos pantallas no lo desuscribe', () {
    // El caso real: la lista de chats sigue a u1 y encima se abre su perfil.
    // Si el `dispose` del perfil dejara la sala, la lista dejaría de recibir
    // sus cambios sin que nada lo delatara.
    subs.agregar(['u1']);
    subs.agregar(['u1']);

    expect(subs.quitar(['u1']), isEmpty);
  });

  test('soltar la última referencia sí desuscribe', () {
    subs.agregar(['u1']);
    subs.agregar(['u1']);
    subs.quitar(['u1']);

    expect(subs.quitar(['u1']), ['u1']);
  });

  test('soltar a alguien que nunca se siguió no devuelve nada', () {
    expect(subs.quitar(['fantasma']), isEmpty);
  });

  test('activos enumera a los seguidos, para rearmarlos tras reconectar', () {
    // Al caerse el transporte el servidor pierde las salas; el cliente tiene
    // que volver a pedirlas o el puntito se queda muerto hasta que se navegue
    // a otra pantalla.
    subs.agregar(['u1', 'u2']);
    subs.quitar(['u2']);

    expect(subs.activos, ['u1']);
  });

  test('limpiar olvida todo y devuelve a los que seguían vivos', () {
    subs.agregar(['u1', 'u2']);

    expect(subs.limpiar(), ['u1', 'u2']);
    expect(subs.agregar(['u1']), ['u1'], reason: 'quedó como no seguido');
  });
}
