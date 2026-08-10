import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Manejo central de errores de red: clasifica cualquier excepción y produce
/// un mensaje apto para enseñarle a una persona.
///
/// Existe por un incidente concreto: al caerse el backend, la pantalla de
/// chat pintaba tal cual "SocketException: Connection refused... address =
/// 157.245.247.45, port = 47956, uri=http://.../api/chat/send". Es decir, la
/// app le enseñaba a cualquier usuario la IP, el puerto y la ruta interna de
/// la API. El texto de una excepción de red NUNCA es para el usuario: es para
/// quien desarrolla, y ahí es donde tiene que quedarse.
///
/// La estrategia es de dos capas, a propósito:
///
///   1. [ApiException] se lanza desde el cliente HTTP, así que las llamadas
///      ya reciben un error con mensaje seguro. Y su `toString()` devuelve
///      ese mensaje seguro, de forma que hasta un `'Error: $e'` olvidado en
///      una pantalla imprime algo presentable en vez de la IP.
///   2. [mensajeDeError] es la red de seguridad para todo lo demás: cualquier
///      excepción, venga de donde venga, se traduce antes de pintarse.

/// Qué salió mal, en términos de lo que el usuario puede hacer al respecto.
enum CategoriaError {
  /// No hay red, o la hay pero no llega al servidor (DNS, connection
  /// refused, host inalcanzable). Lo puede resolver el usuario.
  sinConexion,

  /// El servidor no contestó a tiempo. Puede ser la red del usuario o un
  /// backend saturado; el consejo es el mismo.
  timeout,

  /// El servidor contestó con 5xx: está vivo pero roto. NO es culpa del
  /// usuario y no tiene sentido pedirle que revise su conexión.
  servidor,

  /// El servidor contestó con 4xx. Su cuerpo trae un mensaje redactado para
  /// el usuario ("El comentario no puede estar vacío"), que se respeta tal
  /// cual: generalizarlo sería perder la única explicación útil.
  cliente,

  /// Cualquier otra cosa. Se trata como fallo genérico.
  desconocido,
}

const String _mensajeSinConexion =
    'Revisa tu conexión e intenta de nuevo.';
const String _mensajeTimeout =
    'La conexión está tardando demasiado. Intenta de nuevo.';
const String _mensajeServidor =
    'Algo salió mal de nuestro lado, intenta en unos minutos.';
const String _mensajeDesconocido =
    'Algo no salió como esperábamos. Intenta de nuevo.';

/// Error de una llamada a la API, ya traducido.
///
/// [mensaje] es lo único que debe llegar a la pantalla. [detalleTecnico]
/// guarda el error original para el log, y no se expone en `toString()`
/// justamente para que no pueda colarse por descuido.
class ApiException implements Exception {
  const ApiException(
    this.mensaje, {
    required this.categoria,
    this.statusCode,
    this.detalleTecnico,
  });

  /// Fallo de red: nunca llegó a haber respuesta del servidor.
  factory ApiException.deRed(Object error, {StackTrace? stack}) {
    final categoria = _categoriaDeExcepcion(error);
    registrarErrorTecnico('Fallo de red', error, stack);
    return ApiException(
      _mensajePorCategoria(categoria),
      categoria: categoria,
      detalleTecnico: error.toString(),
    );
  }

  /// Fallo con respuesta HTTP. [mensajeDelServidor] solo se usa en 4xx: en
  /// un 5xx el cuerpo suele ser un HTML de nginx o un stack de Node, que no
  /// se le enseña a nadie.
  factory ApiException.deRespuesta(
    int statusCode, {
    String? mensajeDelServidor,
    String? detalleTecnico,
  }) {
    final esCliente = statusCode >= 400 && statusCode < 500;
    final categoria = esCliente
        ? CategoriaError.cliente
        : statusCode >= 500
        ? CategoriaError.servidor
        : CategoriaError.desconocido;

    final mensaje = esCliente && mensajeDelServidor != null &&
            mensajeDelServidor.trim().isNotEmpty
        ? mensajeDelServidor.trim()
        : _mensajePorCategoria(categoria);

    return ApiException(
      mensaje,
      categoria: categoria,
      statusCode: statusCode,
      detalleTecnico: detalleTecnico,
    );
  }

  /// Mensaje seguro, ya pensado para mostrarse.
  final String mensaje;

  final CategoriaError categoria;

  /// Status HTTP cuando lo hubo. Null en un fallo de red.
  final int? statusCode;

  /// El error original, crudo. Para logs y depuración: no se pinta.
  final String? detalleTecnico;

  /// Un reintento tiene sentido: el problema es de conexión o momentáneo.
  bool get valeLaPenaReintentar =>
      categoria == CategoriaError.sinConexion ||
      categoria == CategoriaError.timeout ||
      categoria == CategoriaError.servidor;

  /// Devuelve el mensaje seguro, NO el detalle técnico. Es deliberado: es lo
  /// que hace que un `'Error: $e'` olvidado en cualquier pantalla siga sin
  /// filtrar la infraestructura.
  @override
  String toString() => mensaje;
}

/// Traduce CUALQUIER excepción a un mensaje que se pueda mostrar.
///
/// Es la función que deben usar las pantallas en su `catch`. Nunca devuelve
/// texto de la excepción salvo que venga de un error 4xx del backend o de
/// una excepción propia de la app cuyo mensaje ya esté redactado.
///
/// [fallback] permite dar contexto de la acción que falló ("No se pudo
/// enviar el mensaje.") en los casos que no son de red.
String mensajeDeError(
  Object? error, {
  String fallback = _mensajeDesconocido,
  StackTrace? stack,
}) {
  if (error == null) return fallback;

  // Ya viene traducido: es el camino normal, porque el cliente HTTP convierte
  // los fallos de red antes de que salgan de ApiService.
  if (error is ApiException) return error.mensaje;

  final categoria = _categoriaDeExcepcion(error);
  if (categoria != CategoriaError.desconocido) {
    registrarErrorTecnico('Fallo de red', error, stack);
    return _mensajePorCategoria(categoria);
  }

  // Excepción de la propia app (`throw Exception('El comentario...')`): su
  // mensaje sí está redactado para el usuario. Se limpia el prefijo que Dart
  // le añade y se comprueba que no arrastre nada técnico.
  final texto = _sinPrefijoDeExcepcion(error.toString());
  if (_pareceTecnico(texto)) {
    registrarErrorTecnico('Error no clasificado', error, stack);
    return fallback;
  }
  return texto;
}

/// Registra el error real. Solo en debug: en release no se imprime nada, para
/// que el detalle técnico no acabe en los logs del dispositivo, que son
/// legibles por otras apps en Android.
///
/// Cuando haya un servicio de reporte (Crashlytics/Sentry), este es el único
/// sitio que hay que tocar para empezar a mandárselo.
void registrarErrorTecnico(String contexto, Object error, [StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('⚠️  $contexto: $error');
  if (stack != null) debugPrint(stack.toString());
}

/// Excepciones que significan "no se pudo hablar con el servidor".
CategoriaError _categoriaDeExcepcion(Object error) {
  if (error is TimeoutException) return CategoriaError.timeout;
  if (error is SocketException) return CategoriaError.sinConexion;
  if (error is http.ClientException) return CategoriaError.sinConexion;
  if (error is HandshakeException) return CategoriaError.sinConexion;
  if (error is HttpException) return CategoriaError.sinConexion;
  // Un host que no resuelve llega como esto en algunas plataformas.
  if (error is OSError) return CategoriaError.sinConexion;
  return CategoriaError.desconocido;
}

String _mensajePorCategoria(CategoriaError categoria) {
  switch (categoria) {
    case CategoriaError.sinConexion:
      return _mensajeSinConexion;
    case CategoriaError.timeout:
      return _mensajeTimeout;
    case CategoriaError.servidor:
      return _mensajeServidor;
    case CategoriaError.cliente:
    case CategoriaError.desconocido:
      return _mensajeDesconocido;
  }
}

/// Quita el "Exception: " que Dart antepone al imprimir una excepción.
String _sinPrefijoDeExcepcion(String texto) {
  const prefijos = ['Exception: ', 'FormatException: ', 'Error: '];
  var limpio = texto;
  for (final prefijo in prefijos) {
    if (limpio.startsWith(prefijo)) {
      limpio = limpio.substring(prefijo.length);
    }
  }
  return limpio.trim();
}

/// Huellas de que un texto es técnico y no debe enseñarse.
///
/// Va como lista de señales SOBRE el texto ya clasificado, no como única
/// defensa: lo que de verdad evita la fuga es que los fallos de red se
/// conviertan antes de llegar aquí. Esto atrapa lo que se escape.
final RegExp _huellasTecnicas = RegExp(
  [
    // Direcciones y rutas de infraestructura.
    r'\bhttps?://',
    r'\buri\s*=',
    r'\bport\s*=',
    r'\baddress\s*=',
    // IPv4 literal.
    r'\b\d{1,3}(\.\d{1,3}){3}\b',
    // Nombres de excepciones de Dart/Flutter y errores de plataforma.
    r'Exception\b',
    r'\bError:',
    r'\berrno\b',
    r'OS Error',
    r'_TypeError',
    r'Instance of',
    r'#\d+\s+',
    // Errores de tipo de Dart: no llevan la palabra "Exception" y son de lo
    // más común que sube desde un parseo ("type _Map<String, dynamic> is not
    // a subtype of List").
    r'is not a subtype',
    r'\bNoSuchMethod',
    // Identificadores privados de Dart y tipos con genéricos: ningún mensaje
    // redactado en español lleva `_algo` ni `Algo<Otro>`.
    r'\b_[A-Za-z]\w*',
    r'\b[A-Z]\w*<[^>]*>',
    // Restos de base de datos o de parseo que a veces suben desde el backend.
    r'\bSQLITE',
    r'\bconstraint\b',
    r'\bstack trace\b',
  ].join('|'),
  caseSensitive: false,
);

bool _pareceTecnico(String texto) {
  if (texto.isEmpty) return true;
  // Un mensaje del backend es una frase corta. Un volcado técnico, no.
  if (texto.length > 160) return true;
  return _huellasTecnicas.hasMatch(texto);
}

/// Lee el mensaje de error del cuerpo de una respuesta con fallo.
///
/// El cuerpo de un 5xx muchas veces no es JSON (el HTML de nginx, por
/// ejemplo), así que el decode va protegido: un `FormatException` aquí
/// sustituiría el error real por uno de parseo y despistaría al diagnóstico.
ApiException excepcionDeRespuesta(http.Response res, {String? fallback}) {
  String? mensajeDelServidor;
  try {
    final cuerpo = jsonDecodeSeguro(res.body);
    final valor = cuerpo?['error'] ?? cuerpo?['message'];
    if (valor is String) mensajeDelServidor = valor;
  } catch (_) {
    // Cuerpo no interpretable: se queda el mensaje por categoría.
  }

  if (res.statusCode >= 500) {
    registrarErrorTecnico(
      'Respuesta ${res.statusCode} del servidor',
      res.body.length > 500 ? '${res.body.substring(0, 500)}…' : res.body,
    );
  }

  final excepcion = ApiException.deRespuesta(
    res.statusCode,
    mensajeDelServidor: mensajeDelServidor,
    detalleTecnico: 'HTTP ${res.statusCode}',
  );

  // Un 4xx sin mensaje del backend puede mejorarse con el contexto de quien
  // llama ("No se pudo publicar el comentario") en vez del genérico.
  if (excepcion.categoria == CategoriaError.cliente &&
      mensajeDelServidor == null &&
      fallback != null) {
    return ApiException(
      fallback,
      categoria: CategoriaError.cliente,
      statusCode: res.statusCode,
      detalleTecnico: excepcion.detalleTecnico,
    );
  }
  return excepcion;
}

/// `jsonDecode` que devuelve null en vez de lanzar cuando el cuerpo no es un
/// objeto JSON — el caso de un 502 que responde el HTML de nginx.
Map<String, dynamic>? jsonDecodeSeguro(String cuerpo) {
  if (cuerpo.isEmpty) return null;
  try {
    final decodificado = jsonDecode(cuerpo);
    return decodificado is Map<String, dynamic> ? decodificado : null;
  } catch (_) {
    return null;
  }
}
