import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

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

  /// Detecta el dominio (alumno/personal) a partir de la PARTE LOCAL de lo
  /// que se lleva tecleado (lo de antes del arroba).
  ///
  /// Los primeros 2 caracteres (posiciones 0 y 1) no son determinantes y se
  /// ignoran. A partir de la posición 2 se evalúa cada carácter: el primero
  /// que sea un dígito asigna alumno; el primero que sea una letra asigna
  /// personal. Un carácter que no sea ni dígito ni letra (p. ej. un punto) no
  /// decide nada y se sigue evaluando el siguiente.
  ///
  /// Devuelve null mientras siga siendo ambiguo (menos de 3 caracteres, o
  /// ningún carácter decisivo todavía): hasta saber el dominio no se sabe qué
  /// formato exigirle a lo tecleado, así que no se puede validar ni enviar.
  ///
  /// Vive aquí, junto al enum, y no dentro de la pantalla: es una regla pura
  /// —texto entra, dominio sale— y así se puede probar sin levantar la
  /// pantalla de verificación entera.
  static DominioUM? detectarDesde(String texto) {
    for (var i = 2; i < texto.length; i++) {
      final c = texto.codeUnitAt(i);
      // 0-9
      if (c >= 0x30 && c <= 0x39) return DominioUM.alumno;
      // A-Z / a-z
      if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
        return DominioUM.personal;
      }
    }
    return null;
  }

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

/// Escribe el dominio detectado dentro del propio campo de texto, en cuanto
/// [DominioUM.detectarDesde] lo resuelve, y lo mantiene ahí como una cola
/// intocable: el usuario solo edita la parte local (lo de antes del arroba).
///
/// Toda la lógica vive en el formatter y no en un listener del controlador
/// porque el formatter es el único punto por el que pasan TODAS las
/// ediciones (teclado, pegar, autocorrección del IME) ANTES de que el texto
/// llegue al controlador: así el campo nunca llega a mostrar un estado
/// intermedio con el dominio a medio borrar.
///
/// El dominio se recalcula en cada tecla a partir de la parte local, así que
/// borrar hasta volver a ser ambiguo (menos de 3 caracteres) lo quita solo, y
/// vaciar el campo lo deja vacío del todo.
class DominioSufijoFormatter extends TextInputFormatter {
  const DominioSufijoFormatter();

  /// Lo que el usuario realmente escribió: todo lo anterior al primer arroba.
  /// El resto del texto es siempre sufijo puesto por este formatter.
  static String parteLocal(String texto) {
    final i = texto.indexOf('@');
    return i == -1 ? texto : texto.substring(0, i);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    var local = parteLocal(nuevo.text);

    // Caso borde: borrado hacia adelante (tecla Supr) con el cursor pegado al
    // arroba. Es la única edición que puede comerse el arroba, y deja el
    // dominio viejo pegado a la parte local ('1220326alumno.um.edu.mx'). Se
    // le recorta para no acabar duplicándolo al volver a añadir el sufijo.
    if (!nuevo.text.contains('@') && anterior.text.contains('@')) {
      final dominioAnterior = DominioUM.detectarDesde(
        parteLocal(anterior.text),
      );
      if (dominioAnterior != null && local.endsWith(dominioAnterior.dominio)) {
        local = local.substring(
          0,
          local.length - dominioAnterior.dominio.length,
        );
      }
    }

    final dominio = DominioUM.detectarDesde(local);
    final texto = dominio == null ? local : '$local${dominio.sufijo}';

    // El cursor nunca puede quedar dentro del sufijo: se recorta al final de
    // la parte local. Al autocompletar, el offset que traía el usuario ya
    // apunta dentro de la parte local, así que no salta a ningún lado — el
    // dominio simplemente aparece a su derecha.
    final seleccion = nuevo.selection;
    return TextEditingValue(
      text: texto,
      selection: seleccion.isValid
          ? TextSelection(
              baseOffset: seleccion.baseOffset.clamp(0, local.length),
              extentOffset: seleccion.extentOffset.clamp(0, local.length),
              affinity: seleccion.affinity,
            )
          : TextSelection.collapsed(offset: local.length),
      // Sin región de composición: el sufijo que añadimos no forma parte de
      // lo que el IME cree estar componiendo, y dejarla viva hace que algunos
      // teclados reescriban encima del dominio.
      composing: TextRange.empty,
    );
  }
}
