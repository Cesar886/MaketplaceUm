import 'package:flutter/material.dart';

/// Los dos dominios institucionales que puede elegir el usuario al verificar
/// su cuenta, y todo lo que cambia con esa elección.
///
/// El dominio elegido ES lo que distingue a un alumno del personal: no hay
/// toggle ni texto aparte. El [tipo] viaja EXPLÍCITO al backend (nunca se
/// deduce allá del dominio) y se valida contra el correo en
/// `backend/src/validation/verificacion.js` — si no coinciden, 400.
enum DominioUM {
  alumno(
    dominio: 'alumno.um.edu.mx',
    tipo: 'estudiante',
    emoji: '🎓',
    etiquetaCampo: 'Matrícula',
    mensajeInvalido: 'Tu matrícula son 7 dígitos',
  ),
  personal(
    dominio: 'um.edu.mx',
    tipo: 'empleado',
    emoji: '🏢',
    etiquetaCampo: 'Usuario institucional',
    mensajeInvalido: 'Tu usuario va como nombre.apellido',
  );

  const DominioUM({
    required this.dominio,
    required this.tipo,
    required this.emoji,
    required this.etiquetaCampo,
    required this.mensajeInvalido,
  });

  /// Dominio sin arroba. Debe coincidir con `VERIFICATION_STUDENT_DOMAINS` /
  /// `VERIFICATION_STAFF_DOMAINS` del backend.
  final String dominio;

  /// Lo que se manda al backend como `tipo`: 'estudiante' | 'empleado'.
  final String tipo;

  final String emoji;

  /// Etiqueta del campo de texto una vez elegido el dominio.
  final String etiquetaCampo;

  /// Aviso cuando lo tecleado no cumple el formato de este dominio.
  final String mensajeInvalido;

  /// Lo que se ve en el desplegable y pegado al campo: '@alumno.um.edu.mx'.
  String get sufijo => '@$dominio';

  /// Solo el alumno declara carrera; para el personal el campo ni se muestra.
  bool get pideCarrera => this == DominioUM.alumno;

  /// Longitud exacta de la matrícula, o null si el usuario es de largo libre.
  int? get largoMaximo => this == DominioUM.alumno ? 7 : null;

  /// Teclado numérico para la matrícula, de texto para el usuario del
  /// personal.
  TextInputType get tipoTeclado =>
      this == DominioUM.alumno ? TextInputType.number : TextInputType.text;

  /// Formato que debe cumplir el correo YA CONCATENADO. Réplica de lo que
  /// valida el backend para este mismo tipo.
  RegExp get formatoCorreo => switch (this) {
    DominioUM.alumno => RegExp('^\\d{7}@${RegExp.escape(dominio)}\$'),
    // Tolerante a propósito (nombre.apellido, nombre.apellido.segundo,
    // nombre.apellido2): el formato real de la UM no está confirmado, y
    // bloquear a un empleado legítimo es peor que dejar pasar un correo raro
    // que de todas formas tiene que recibir el código en ese buzón.
    DominioUM.personal => RegExp(
      '^[a-zA-Z]+(\\.[a-zA-Z0-9]+)*@${RegExp.escape(dominio)}\$',
    ),
  };
}
