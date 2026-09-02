import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models.dart';

/// Subtítulo de rol que va bajo el nombre de un usuario: la carrera si es
/// alumno, 'role.um_staff'.tr() si es personal de la universidad, y la etiqueta de
/// registro ([Seller.major]) para negocios y particulares.
///
/// Es la ÚNICA fuente del copy: perfil propio, perfil público del vendedor y
/// detalle de producto salen todos de aquí, para que cambiar el texto o las
/// reglas no obligue a tocar tres pantallas y se desincronicen entre sí.
///
/// Devuelve null cuando no hay ningún dato de rol que mostrar, y entonces la
/// línea se OMITE por completo. No hay fallback a 'Estudiante': ese genérico
/// aparecía tanto en una cuenta sin verificar como en una verificada a la que
/// le falta la carrera, así que no distinguía nada y sugería un respaldo
/// institucional que el backend no había comprobado.
///
/// [incluirEstudiante] a false deja fuera la carrera y 'role.um_staff': en los
/// comentarios del detalle de producto solo interesa distinguir negocios y
/// particulares del resto, no publicar qué estudia cada quien al pie de cada
/// comentario.
String? subtituloRol(Seller seller, {bool incluirEstudiante = true}) {
  // Negocio y particular conservan la etiqueta fija que se les asignó al
  // registrarse. `major` NO se toca ni se reescribe: hay tres lugares que
  // derivan datos de su contenido literal (`database.js` deduce tipo_cuenta
  // e isBusiness, `auth_provider.dart` deduce el AccountType), así que sigue
  // siendo un campo de datos además de una etiqueta.
  if (seller.tipoCuenta != 'estudiante') {
    return seller.major.isEmpty ? null : seller.major;
  }

  if (!incluirEstudiante) return null;

  // De aquí para abajo, cuenta de estudiante: alumno y personal comparten
  // tipoCuenta y se distinguen por `tipoVerificacion`, que solo se llena al
  // verificarse. Sin verificar no hay nada comprobado que enseñar.
  if (!seller.verified) return null;

  if (seller.tipoVerificacion == 'empleado') return 'role.um_staff'.tr();

  final carrera = seller.carrera;
  return (carrera != null && carrera.isNotEmpty) ? carrera : null;
}

/// Renderiza [subtituloRol] o nada. Absorbe el espacio superior para que al
/// omitirse la línea no quede el hueco del `SizedBox` que la separaba del
/// nombre.
class SubtituloRol extends StatelessWidget {
  const SubtituloRol({
    super.key,
    required this.seller,
    this.style,
    this.espacioArriba = 0,
    this.maxLines,
    this.incluirEstudiante = true,
  });

  final Seller seller;
  final TextStyle? style;
  final double espacioArriba;
  final int? maxLines;
  final bool incluirEstudiante;

  @override
  Widget build(BuildContext context) {
    final texto = subtituloRol(seller, incluirEstudiante: incluirEstudiante);
    if (texto == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: espacioArriba),
      child: Text(
        texto,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
