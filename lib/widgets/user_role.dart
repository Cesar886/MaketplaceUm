import 'package:flutter/material.dart';

import '../models.dart';

/// Subtítulo de rol que va bajo el nombre de un usuario: la carrera si es
/// alumno, 'Personal UM' si es personal de la universidad, y la etiqueta de
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
String? subtituloRol(Seller seller) {
  // Negocio y particular conservan la etiqueta fija que se les asignó al
  // registrarse. `major` NO se toca ni se reescribe: hay tres lugares que
  // derivan datos de su contenido literal (`database.js` deduce tipo_cuenta
  // e isBusiness, `auth_provider.dart` deduce el AccountType), así que sigue
  // siendo un campo de datos además de una etiqueta.
  if (seller.tipoCuenta != 'estudiante') {
    return seller.major.isEmpty ? null : seller.major;
  }

  // De aquí para abajo, cuenta de estudiante: alumno y personal comparten
  // tipoCuenta y se distinguen por `tipoVerificacion`, que solo se llena al
  // verificarse. Sin verificar no hay nada comprobado que enseñar.
  if (!seller.verified) return null;

  if (seller.tipoVerificacion == 'empleado') return 'Personal UM';

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
  });

  final Seller seller;
  final TextStyle? style;
  final double espacioArriba;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final texto = subtituloRol(seller);
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
