import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/services/presence_service.dart';
import 'package:mercadito_um/utils/estado_conexion.dart';

void main() {
  late PresenceService presencia;

  setUp(() => presencia = PresenceService());

  test('un usuario desconocido está desconectado, no en un limbo', () {
    expect(presencia.estadoDe('nadie'), EstadoConexion.desconocido);
  });

  test('la semilla del REST queda disponible al instante', () {
    presencia.sembrar('u1', const EstadoConexion(enLinea: true));

    expect(presencia.estadoDe('u1').enLinea, isTrue);
  });

  test('un evento de conexión marca al usuario en línea y avisa', () {
    var avisos = 0;
    presencia.addListener(() => avisos++);

    presencia.aplicarEvento(const {'userId': 'u1', 'online': true});

    expect(presencia.estadoDe('u1').enLinea, isTrue);
    expect(avisos, 1);
  });

  test('un evento de desconexión guarda la última actividad', () {
    presencia.aplicarEvento(const {'userId': 'u1', 'online': true});

    presencia.aplicarEvento(const {
      'userId': 'u1',
      'online': false,
      'lastActive': '2026-08-17T09:00:00.000Z',
    });

    final estado = presencia.estadoDe('u1');
    expect(estado.enLinea, isFalse);
    expect(estado.ultimaActividad, DateTime.utc(2026, 8, 17, 9));
  });

  test('un evento sin userId se ignora sin avisar', () {
    var avisos = 0;
    presencia.addListener(() => avisos++);

    presencia.aplicarEvento(const {'online': true});

    expect(avisos, 0);
  });

  test('un evento que no cambia nada no dispara repintados', () {
    presencia.aplicarEvento(const {'userId': 'u1', 'online': true});
    var avisos = 0;
    presencia.addListener(() => avisos++);

    presencia.aplicarEvento(const {'userId': 'u1', 'online': true});

    expect(avisos, 0, reason: 'la lista de chats se repintaría de más');
  });

  test('el snapshot apaga a quien ya no está en línea', () {
    // El caso real: la app estuvo en segundo plano, el REST trajo a u1 en
    // línea y para cuando vuelve a suscribirse u1 ya se fue.
    presencia.sembrar('u1', const EstadoConexion(enLinea: true));
    presencia.sembrar('u2', const EstadoConexion(enLinea: false));

    presencia.aplicarSnapshot(consultados: ['u1', 'u2'], enLinea: ['u2']);

    expect(presencia.estadoDe('u1').enLinea, isFalse);
    expect(presencia.estadoDe('u2').enLinea, isTrue);
  });

  test('el snapshot no toca a quien no se consultó', () {
    presencia.sembrar('otro', const EstadoConexion(enLinea: true));

    presencia.aplicarSnapshot(consultados: ['u1'], enLinea: []);

    expect(presencia.estadoDe('otro').enLinea, isTrue);
  });

  test('apagar a alguien por snapshot conserva su última actividad conocida', () {
    presencia.sembrar(
      'u1',
      EstadoConexion(enLinea: true, ultimaActividad: DateTime.utc(2026, 8, 17)),
    );

    presencia.aplicarSnapshot(consultados: ['u1'], enLinea: []);

    expect(presencia.estadoDe('u1').ultimaActividad, DateTime.utc(2026, 8, 17));
  });

  test('limpiar borra todo al cerrar sesión', () {
    // Sin esto, la siguiente cuenta que entre en el mismo dispositivo vería
    // el estado en línea que se quedó cacheado de la anterior.
    presencia.sembrar('u1', const EstadoConexion(enLinea: true));

    presencia.limpiar();

    expect(presencia.estadoDe('u1').enLinea, isFalse);
  });
}
