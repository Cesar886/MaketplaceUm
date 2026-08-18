import 'package:easy_localization/easy_localization.dart';

/// Más allá de una semana el dato deja de informar: "activo hace 4 meses" no
/// ayuda a decidir si escribir o no, y sí expone más historial del necesario.
const _limiteUltimaActividad = Duration(days: 7);

/// Estado de conexión de otra persona, tal y como lo entrega el backend.
///
/// Quien oculta su estado (Configuración → Privacidad) llega aquí
/// exactamente igual que quien está desconectado y nunca se ha visto: el
/// backend no distingue los dos casos a propósito, para que esconderse no
/// sea en sí mismo una señal observable.
class EstadoConexion {
  const EstadoConexion({this.enLinea = false, this.ultimaActividad});

  /// Estado por defecto mientras no se sabe nada: desconectado y sin fecha.
  static const desconocido = EstadoConexion();

  final bool enLinea;
  final DateTime? ultimaActividad;

  factory EstadoConexion.desdeJson(Map<String, dynamic> json) {
    final crudo = json['lastActive'];
    return EstadoConexion(
      enLinea: json['isOnline'] == true,
      // `tryParse` y no `parse`: una fecha corrupta o un backend viejo que no
      // manda el campo no deben tumbar el parseo de todo el perfil.
      ultimaActividad: crudo is String ? DateTime.tryParse(crudo) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EstadoConexion &&
      other.enLinea == enLinea &&
      other.ultimaActividad == ultimaActividad;

  @override
  int get hashCode => Object.hash(enLinea, ultimaActividad);
}

/// Texto discreto para debajo del nombre: "Activo hace 5 min".
///
/// Devuelve null cuando no hay nada que decir (sin fecha, o demasiado
/// antigua); la pantalla omite la línea entera en ese caso en vez de pintar
/// un hueco o un "desconectado" que no aporta.
///
/// [ahora] existe solo para los tests; en producción se omite.
String? etiquetaUltimaActividad(DateTime? ultimaActividad, {DateTime? ahora}) {
  if (ultimaActividad == null) return null;

  final delta = (ahora ?? DateTime.now()).difference(ultimaActividad);
  if (delta > _limiteUltimaActividad) return null;

  // No se reutiliza [tiempoRelativo] aunque el cálculo se parezca: aquel
  // devuelve un fragmento ("hace 5 min") pensado para concatenarse, y la
  // frase completa tiene que ser una sola clave de traducción — en inglés
  // el orden cambia ("Active 5 min ago") y una concatenación no sobrevive.

  // Un delta negativo es el reloj del dispositivo adelantado respecto al
  // servidor. "Activo en 3 minutos" se lee como un bug, así que cae en el
  // mismo cubo que recién visto.
  if (delta.isNegative || delta.inMinutes < 1) {
    return 'presence.active_moment'.tr();
  }
  if (delta.inHours < 1) {
    return 'presence.active_minutes'.tr(namedArgs: {'n': '${delta.inMinutes}'});
  }
  if (delta.inDays < 1) {
    return 'presence.active_hours'.tr(namedArgs: {'n': '${delta.inHours}'});
  }
  return 'presence.active_days'.tr(namedArgs: {'n': '${delta.inDays}'});
}
