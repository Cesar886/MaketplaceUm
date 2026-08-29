import 'package:easy_localization/easy_localization.dart';
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
    claveEtiquetaCampo: 'verification.field_student_id',
    claveMensajeInvalido: 'verification.invalid_student_id',
  ),
  personal(
    dominio: 'um.edu.mx',
    tipo: 'empleado',
    emoji: '🏢',
    claveEtiquetaCampo: 'verification.field_staff_user',
    claveMensajeInvalido: 'verification.invalid_staff_user',
  );

  const DominioUM({
    required this.dominio,
    required this.tipo,
    required this.emoji,
    required this.claveEtiquetaCampo,
    required this.claveMensajeInvalido,
  });

  /// Dominio sin arroba. Debe coincidir con `VERIFICATION_STUDENT_DOMAINS` /
  /// `VERIFICATION_STAFF_DOMAINS` del backend.
  final String dominio;

  /// Lo que se manda al backend como `tipo`: 'estudiante' | 'empleado'.
  final String tipo;

  final String emoji;

  /// Clave de traducción de la etiqueta del campo. Se guarda la clave y no el
  /// texto porque el enum es `const`: `.tr()` no se puede evaluar aquí, y el
  /// idioma puede cambiar sin reiniciar la app.
  final String claveEtiquetaCampo;

  /// Clave del aviso cuando lo tecleado no cumple el formato de este dominio.
  final String claveMensajeInvalido;

  /// Etiqueta del campo de texto una vez elegido el dominio, ya traducida.
  String get etiquetaCampo => claveEtiquetaCampo.tr();

  /// Aviso, ya traducido, cuando lo tecleado no cumple el formato.
  String get mensajeInvalido => claveMensajeInvalido.tr();

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
