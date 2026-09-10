// Tests del manejo central de errores de red.
//
// Este archivo existe por un incidente: con el backend caído, la app pintaba
// "SocketException: Connection refused... address = 164.90.129.213, port =
// 47956, uri=http://164.90.129.213:3000/api/chat/send" en la pantalla de
// chat. La regla que se protege aquí es una sola y no admite excepciones:
// NADA de lo que devuelva este módulo puede contener IP, puerto, URI, nombre
// de excepción ni stack trace.
//
// Por eso el test central no comprueba textos concretos sino la AUSENCIA de
// esas huellas sobre un lote de excepciones reales: comprobar que un mensaje
// dice "Revisa tu conexión" no impide que además arrastre la IP al final.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mercadito_um/services/api_error.dart';

import 'helpers/localizacion_de_prueba.dart';

void main() {
  // Los mensajes de este módulo ya salen del diccionario de i18n: sin
  // cargarlo, `.tr()` devolvería la clave cruda ('errors.timeout').
  setUpAll(inicializarTraducciones);

  /// La excepción tal cual la lanzó el dispositivo en el incidente.
  final socketReal = const SocketException(
    'Connection refused',
    osError: OSError('Connection refused', 111),
    address: null,
    port: 47956,
  );

  /// Huellas que jamás pueden aparecer en un mensaje mostrado.
  void esperarSinFugas(String mensaje) {
    final prohibido = <String, Pattern>{
      'una IP': RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b'),
      'una URL': RegExp(r'https?://'),
      'una URI': RegExp(r'uri\s*=', caseSensitive: false),
      'un puerto': RegExp(r'port\s*=', caseSensitive: false),
      'una dirección': RegExp(r'address\s*=', caseSensitive: false),
      'un nombre de excepción': RegExp(r'Exception'),
      'un errno': RegExp(r'errno', caseSensitive: false),
      'un OS Error': RegExp(r'OS Error', caseSensitive: false),
      'un frame de stack': RegExp(r'#\d+\s'),
    };
    prohibido.forEach((que, patron) {
      expect(
        mensaje.contains(patron),
        isFalse,
        reason: 'el mensaje mostrado filtró $que: "$mensaje"',
      );
    });
  }

  group('clasificación de fallos de red', () {
    test('un connection refused se vuelve consejo de conexión', () {
      final mensaje = mensajeDeError(socketReal);

      expect(mensaje, 'Revisa tu conexión e intenta de nuevo.');
      esperarSinFugas(mensaje);
    });

    test('el texto exacto del incidente no filtra infraestructura', () {
      // Reproduce la forma completa del error reportado, con IP y URI dentro.
      final comoEnProduccion = http.ClientException(
        'SocketException: Connection refused (OS Error: Connection refused, '
        'errno = 111), address = 164.90.129.213, port = 47956',
        Uri.parse('http://164.90.129.213:3000/api/chat/send'),
      );

      final mensaje = mensajeDeError(comoEnProduccion);

      esperarSinFugas(mensaje);
      expect(mensaje, isNot(contains('164.90.129.213')));
      expect(mensaje, isNot(contains('47956')));
      expect(mensaje, isNot(contains('/api/chat/send')));
    });

    test('un timeout pide reintentar, no revisar la conexión', () {
      // Distinguirlos importa: si el servidor tarda, decirle al usuario que
      // revise su wifi lo manda a buscar un problema que no tiene.
      final mensaje = mensajeDeError(
        TimeoutException('tardó', const Duration(seconds: 15)),
      );

      expect(mensaje, contains('tardando'));
      esperarSinFugas(mensaje);
    });

    test('un fallo de TLS se trata como problema de conexión', () {
      final mensaje = mensajeDeError(const HandshakeException('cert roto'));

      expect(mensaje, 'Revisa tu conexión e intenta de nuevo.');
      esperarSinFugas(mensaje);
    });

    test('cualquier excepción de red conocida sale limpia', () {
      final lote = <Object>[
        socketReal,
        const SocketException('Failed host lookup: api.mercadito.um'),
        http.ClientException(
          'Connection closed before full header was received',
        ),
        const HttpException('Invalid statusCode: 500'),
        TimeoutException('sin respuesta'),
        const HandshakeException('handshake'),
        const OSError('Network is unreachable', 101),
      ];

      for (final error in lote) {
        esperarSinFugas(mensajeDeError(error));
      }
    });
  });

  group('respuestas con código de error', () {
    test('un 4xx muestra el mensaje del backend tal cual', () {
      // Estos SÍ están redactados para el usuario: generalizarlos sería
      // perder la única explicación útil que tiene para corregir.
      final e = ApiException.deRespuesta(
        400,
        mensajeDelServidor: 'El comentario no puede estar vacío.',
      );

      expect(e.mensaje, 'El comentario no puede estar vacío.');
      expect(e.categoria, CategoriaError.cliente);
    });

    test('un 4xx sin mensaje del backend cae a un genérico', () {
      final e = ApiException.deRespuesta(404);

      expect(e.mensaje, isNotEmpty);
      esperarSinFugas(e.mensaje);
    });

    test('un 5xx NO usa el cuerpo: puede ser el HTML de nginx', () {
      final e = ApiException.deRespuesta(
        500,
        mensajeDelServidor: '<html><head><title>502 Bad Gateway</title>',
      );

      expect(
        e.mensaje,
        'Algo salió mal de nuestro lado, intenta en unos minutos.',
      );
      expect(e.mensaje, isNot(contains('html')));
      expect(e.categoria, CategoriaError.servidor);
    });

    test('excepcionDeRespuesta lee el error de un JSON de 4xx', () {
      final res = http.Response(
        '{"error":"Ya calificaste este producto"}',
        409,
      );

      final e = excepcionDeRespuesta(res);

      expect(e.mensaje, 'Ya calificaste este producto');
      expect(e.statusCode, 409);
    });

    test('excepcionDeRespuesta sobrevive a un cuerpo que no es JSON', () {
      // Es el caso real de un 502: nginx contesta HTML y el jsonDecode
      // reventaría, sustituyendo el error real por un FormatException.
      final res = http.Response(
        '<html><body><h1>502 Bad Gateway</h1></body></html>',
        502,
      );

      final e = excepcionDeRespuesta(res);

      expect(e.categoria, CategoriaError.servidor);
      esperarSinFugas(e.mensaje);
    });

    test('un 4xx sin cuerpo usa el contexto de quien llama', () {
      final res = http.Response('', 400);

      final e = excepcionDeRespuesta(
        res,
        fallback: 'No se pudo enviar el mensaje.',
      );

      expect(e.mensaje, 'No se pudo enviar el mensaje.');
    });
  });

  group('ApiException', () {
    test('toString devuelve el mensaje seguro, nunca el detalle técnico', () {
      // Es lo que hace que un `'Error: $e'` olvidado en cualquier pantalla
      // siga sin filtrar nada. Es la última línea de defensa del sistema.
      final e = ApiException.deRed(socketReal);

      esperarSinFugas(e.toString());
      expect(e.toString(), e.mensaje);
      expect(e.detalleTecnico, isNotNull, reason: 'el detalle debe guardarse');
    });

    test('interpolar la excepción en un string no filtra nada', () {
      final e = ApiException.deRed(
        http.ClientException(
          'Connection refused, address = 164.90.129.213, port = 3000',
          Uri.parse('http://164.90.129.213:3000/api/chat/send'),
        ),
      );

      esperarSinFugas('Error al enviar: $e');
    });

    test('solo se reintenta lo que puede arreglarse solo', () {
      expect(ApiException.deRed(socketReal).valeLaPenaReintentar, isTrue);
      expect(
        ApiException.deRespuesta(500).valeLaPenaReintentar,
        isTrue,
        reason: 'un 5xx puede ser pasajero',
      );
      expect(
        ApiException.deRespuesta(
          400,
          mensajeDelServidor: 'Falta el texto',
        ).valeLaPenaReintentar,
        isFalse,
        reason: 'reintentar un 400 da exactamente el mismo 400',
      );
    });
  });

  group('mensajes propios de la app', () {
    test('un mensaje redactado por la app se respeta', () {
      final mensaje = mensajeDeError(
        Exception('El comentario no puede estar vacío.'),
      );

      expect(mensaje, 'El comentario no puede estar vacío.');
    });

    test('un texto con pinta técnica cae al fallback', () {
      final mensaje = mensajeDeError(
        Exception('type _Map<String, dynamic> is not a subtype of List'),
        fallback: 'No se pudo cargar.',
      );

      expect(mensaje, 'No se pudo cargar.');
    });

    test('un volcado largo cae al fallback aunque no tenga palabras clave', () {
      final mensaje = mensajeDeError(
        Exception('a' * 400),
        fallback: 'No se pudo cargar.',
      );

      expect(mensaje, 'No se pudo cargar.');
    });

    test('un error nulo devuelve el fallback', () {
      expect(mensajeDeError(null, fallback: 'Algo falló.'), 'Algo falló.');
    });

    test('un mensaje del backend con una URL dentro se descarta', () {
      // Un endpoint mal hecho podría devolver una URL interna en su `error`.
      // Aunque venga de un 4xx, el texto no se pinta si arrastra rutas.
      final mensaje = mensajeDeError(
        Exception('Falló al llamar a http://10.0.0.4:3000/api/interno'),
        fallback: 'No se pudo completar.',
      );

      expect(mensaje, 'No se pudo completar.');
      esperarSinFugas(mensaje);
    });
  });

  group('reporte de errores al backend', () {
    // Regresión de un crash en producción: con el dispositivo sin red, cada
    // llamada a registrarErrorTecnico lanzaba
    // "Invalid argument(s): Invalid status code 0" como excepción NO
    // capturada. El culpable era el manejador de error del propio envío:
    // `catchError((_) => http.Response('', 0))`, y `http.Response` rechaza
    // cualquier status por debajo de 100. O sea, la función que existe para
    // tragarse los fallos de red era la que los convertía en un crash.
    //
    // La regla que se protege: registrarErrorTecnico NUNCA puede propagar
    // una excepción, ni síncrona ni asíncrona, pase lo que pase con la red.

    tearDown(restaurarClienteDeReporte);

    test('un envío que falla no propaga excepción', () async {
      clienteDeReportePrueba = _ClienteQueFalla();

      registrarErrorTecnico(
        'Fallo de red',
        const SocketException('Connection refused'),
        StackTrace.current,
      );

      // El fallo del envío es asíncrono: sin este respiro la prueba
      // terminaría antes de que la excepción tuviera ocasión de escapar, y
      // pasaría incluso con el bug presente.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('el envío ocurre de verdad cuando hay red', () async {
      final cliente = _ClienteQueRegistra();
      clienteDeReportePrueba = cliente;

      registrarErrorTecnico('Contexto de prueba', Exception('detalle'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cliente.llamadas, 1);
    });
  });
}

/// Cliente que simula un dispositivo sin red: falla igual que `http` cuando
/// no puede abrir el socket.
class _ClienteQueFalla extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(http.ClientException('Connection closed', request.url));
}

/// Cliente que cuenta los envíos, para comprobar que silenciar el error no
/// significó dejar de mandar el reporte.
class _ClienteQueRegistra extends http.BaseClient {
  int llamadas = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    llamadas++;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}
