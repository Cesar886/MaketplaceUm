import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Foto de perfil circular con el punto de "en línea" superpuesto.
///
/// Existe para que la regla visual del punto —tamaño, posición, anillo— viva
/// en UN sitio: se usa en la lista de chats (radio 24) y en el perfil de
/// vendedor (radio 40), y la proporción tiene que ser la misma en los dos.
class OnlineStatusAvatar extends StatelessWidget {
  const OnlineStatusAvatar({
    super.key,
    required this.radius,
    required this.enLinea,
    this.imageUrl,
    this.iniciales,
    this.mostrarIconoPorDefecto = false,
  });

  /// Radio del avatar, igual que en [CircleAvatar].
  final double radius;

  /// Si es false el punto no se pinta (esto incluye a quien oculta su estado:
  /// el backend lo entrega como desconectado, ver EstadoConexion).
  final bool enLinea;

  /// URL completa de la foto. Sin ella se pintan las [iniciales] o el icono
  /// predeterminado.
  final String? imageUrl;
  final String? iniciales;

  /// Usa el avatar genérico de persona cuando no hay foto, en vez de las
  /// iniciales. Se activa solo donde la UI necesita comunicar "foto de
  /// perfil" de forma explícita.
  final bool mostrarIconoPorDefecto;

  /// Para encontrar el punto en los tests sin depender del árbol interno.
  static const puntoKey = Key('online-status-dot');

  /// Diámetro del punto (anillo incluido) como fracción del diámetro del
  /// avatar. Con 26% el punto se lee de un vistazo a 48px y sigue mordiendo
  /// solo la esquina a 80px; por encima del 30% empieza a tapar la cara de
  /// la foto, y por debajo del 20% desaparece en la lista.
  static const _proporcionPunto = 0.26;

  /// Grosor del anillo, también proporcional: un borde fijo de 2px se come
  /// medio punto en el avatar chico y no se nota en el grande.
  static const _proporcionAnillo = 0.16;

  @override
  Widget build(BuildContext context) {
    final colores = context.colors;
    final tieneFoto = imageUrl != null && imageUrl!.isNotEmpty;
    final diametroPunto = radius * 2 * _proporcionPunto;

    return SizedBox(
      // Tamaño fijo del avatar: el punto va superpuesto y NO empuja el
      // layout. Si el widget creciera al conectarse alguien, las filas de la
      // lista de chats se moverían solas.
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: colores.primary.withValues(alpha: 0.12),
            backgroundImage: tieneFoto ? NetworkImage(imageUrl!) : null,
            child: tieneFoto
                ? null
                : mostrarIconoPorDefecto
                ? Icon(
                    Icons.person_rounded,
                    size: radius * 1.15,
                    color: colores.accent,
                  )
                : Text(
                    iniciales?.isNotEmpty == true ? iniciales! : '?',
                    style: TextStyle(
                      color: colores.accent,
                      fontWeight: FontWeight.w700,
                      // La tipografía sigue al avatar por la misma razón que
                      // el punto: un tamaño fijo se ve enorme a radio 40.
                      fontSize: radius * 0.66,
                    ),
                  ),
          ),
          if (enLinea)
            Positioned(
              // Esquina inferior derecha, pero metido hacia dentro: pegado al
              // borde exacto el círculo del avatar lo recorta en diagonal.
              right: radius * 0.06,
              bottom: radius * 0.06,
              child: Semantics(
                label: 'presence.online'.tr(),
                child: SizedBox(
                  key: puntoKey,
                  width: diametroPunto,
                  height: diametroPunto,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colores.online,
                      // El anillo del color de la superficie es lo que hace
                      // que el punto "flote" sobre la foto en vez de parecer
                      // una mancha del propio retrato.
                      border: Border.all(
                        color: colores.surface,
                        width: diametroPunto * _proporcionAnillo,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
