import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../utils/estado_conexion.dart';
import 'badges.dart';
import 'online_status_avatar.dart';
import 'user_role.dart';

/// Qué tinta aguanta la banda de marca de [banner].
///
/// Se decide por luminancia y no con el `onPrimary` del tema porque la banda
/// lleva el swatch del VENDEDOR, que puede ser claro mientras quien mira tiene
/// el tema oscuro (o al revés): el `onPrimary` del contexto respondería por el
/// color equivocado.
///
/// Vive suelto aquí porque la banda ya no termina donde empieza el header: la
/// AppBar se pinta encima de ella, así que su título necesita exactamente esta
/// misma tinta (ver `SellerProfileScreen`).
Color tintaSobreBanda(Color banner) => banner.computeLuminance() > 0.5
    ? Colors.black.withValues(alpha: 0.87)
    : Colors.white;

/// Encabezado del perfil público: el banner con avatar, nombre, rol,
/// calificación, descripción e insignias.
///
/// Vive fuera de `seller_profile_screen` para que el bloque se pueda montar
/// solo — es la única parte de la pantalla que no necesita red ni providers,
/// y así se prueba y se revisa su diseño sin levantar el perfil entero.
class SellerProfileHeader extends StatelessWidget {
  const SellerProfileHeader({
    super.key,
    required this.seller,
    required this.estadoConexion,
    required this.colorBanner,
    this.espacioSuperior = 0,
  });

  final Seller seller;
  final EstadoConexion estadoConexion;

  /// Ya resuelto por quien monta el header: es el swatch del VENDEDOR, no el
  /// de quien mira (ver `colorDeBannerDeVendedor`).
  final Color colorBanner;

  /// Aire extra ARRIBA del contenido de la banda, en px.
  ///
  /// La pantalla le pasa aquí el alto de la barra de estado más el de la
  /// AppBar, porque la banda se dibuja por DEBAJO de las dos: sin este hueco,
  /// el avatar quedaría tapado por el título. Montado suelto (pruebas,
  /// capturas) va en 0 y la banda empieza donde empieza el widget.
  final double espacioSuperior;

  /// Radio del avatar.
  static const double _radioAvatar = 42;

  @override
  Widget build(BuildContext context) {
    final colores = context.colors;
    final sobreBanda = tintaSobreBanda(colorBanner);
    final sobreBandaSuave = sobreBanda.withValues(alpha: 0.78);

    return Column(
      children: [
        // Banda de marca. Cubre hasta un poco por debajo de la calificación:
        // avatar, nombre, rol y métricas forman un solo bloque sobre color, y
        // lo que sigue (descripción e insignias) cae ya sobre el fondo de
        // página. Su alto lo fija el contenido y no una constante: con un
        // nombre de dos líneas o sin subtítulo de rol, un alto fijo dejaría
        // texto fuera de la banda o un hueco de color vacío debajo.
        Container(
          width: double.infinity,
          // El aire de arriba no es constante: lleva sumado [espacioSuperior]
          // porque la banda arranca DETRÁS de la AppBar y de la barra de
          // estado, no debajo de ellas.
          padding: EdgeInsets.fromLTRB(18, 22 + espacioSuperior, 18, 26),
          decoration: BoxDecoration(
            // Solo las esquinas de abajo: arriba la banda llega hasta el
            // borde de la pantalla, y redondear ahí dejaría dos muescas de
            // fondo asomando por encima.
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(26),
              bottomRight: Radius.circular(26),
            ),
            // La parte superior se conserva sólida: es la misma superficie
            // que ocupa la AppBar fija de la pantalla. Si el degradado o el
            // brillo empezaran detrás de la barra, al terminar la AppBar se
            // vería una costura aunque ambos usaran el mismo swatch.
            //
            // El sombreado comienza ya dentro del contenido del perfil; así
            // se mantiene la profundidad del banner sin convertir la barra
            // en transparente (una barra transparente se vuelve blanca al
            // hacer scroll, cuando el ListView deja de estar detrás de ella).
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomRight,
              stops: const [0, 0.42, 1],
              colors: [
                colorBanner,
                colorBanner,
                Color.lerp(colorBanner, Colors.black, 0.18)!,
              ],
            ),
          ),
          child: Column(
            children: [
              // Aro alrededor del avatar: separa la foto del color de fondo,
              // que si no la absorbe cuando el logo tiene tonos parecidos al
              // swatch del vendedor.
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colores.background,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: OnlineStatusAvatar(
                  radius: _radioAvatar,
                  iniciales: seller.avatarInitials,
                  imageUrl: seller.logoUrl != null
                      ? ApiService.baseUrl + seller.logoUrl!
                      : null,
                  enLinea: estadoConexion.enLinea,
                ),
              ),
              const SizedBox(height: 14),
              // La insignia va DENTRO del párrafo del nombre (un WidgetSpan),
              // no en un Row al lado: con un nombre de negocio largo, el Row
              // la dejaba flotando sola a la derecha del bloque de dos
              // líneas — y antes de eso, con el nombre en un Text suelto,
              // desbordaba el ancho de la pantalla en vez de partirse.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: seller.name),
                    if (seller.verified || seller.socioFundador)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InsigniaCuenta.deSeller(seller, size: 20),
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.heading(
                  22,
                  color: sobreBanda,
                ).copyWith(height: 1.2, letterSpacing: -0.2),
              ),
              SubtituloRol(
                seller: seller,
                espacioArriba: 5,
                style: TextStyle(
                  color: sobreBandaSuave,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              // Calificación y última conexión comparten una sola fila de
              // metadatos, separadas por un punto: antes eran dos líneas
              // centradas más, y el bloque entero se leía como una lista de
              // renglones sueltos sin jerarquía.
              _FilaMetadatos(
                seller: seller,
                estadoConexion: estadoConexion,
                color: sobreBanda,
                colorSuave: sobreBandaSuave,
              ),
            ],
          ),
        ),
        if (seller.businessDescription != null &&
            seller.businessDescription!.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Ancho acotado: a lo ancho de la pantalla la descripción daba
          // renglones de 60+ caracteres, que se leen mal centrados.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              seller.businessDescription!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colores.muted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (_insignias.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            // Sin tope de cuántas se pintan: quien reunió ocho las enseña
            // todas, y el Wrap las reparte en las filas que hagan falta. Si
            // alguien quiere enseñar menos, se apagan una por una desde
            // Ajustes → Mis insignias, que es donde vive esa decisión.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _insignias,
            ),
          ),
        ],
        // Separación con lo que sigue (los enlaces sociales): antes la daba
        // la franja de desvanecido del banner, que ya no existe.
        const SizedBox(height: 18),
      ],
    );
  }

  /// Las insignias del perfil, de la más difícil a la más común.
  ///
  /// El orden es el mismo del catálogo de Ajustes → Mis insignias, para que
  /// la fila de aquí se lea como la lista de allá. Cuáles se ocultan no se
  /// decide en el cliente: el backend ya manda apagados los campos que su
  /// dueño escondió.
  List<Widget> get _insignias => [
    // ── Élite ──
    if (seller.leyendaMercadito) const InsigniaLeyenda(),
    if (seller.vendedorDeOro) const InsigniaVendedorDeOro(),
    // Impecable es el escalón de arriba de Confiable y la sustituye: las dos
    // juntas dirían dos veces "tiene buenas reseñas".
    if (seller.ratingPerfecto)
      const InsigniaImpecable()
    else if (seller.vendedorConfiable)
      const InsigniaVendedorConfiable(),
    if (seller.cienCincoEstrellas) const InsigniaCentenario(),
    if (seller.siempreResponde) const InsigniaSiempreResponde(),
    // ── Básicas ──
    // Instantánea implica "responde rápido": mostrar las dos repetiría el
    // mismo dato en dos badges, así que solo se pinta la más específica.
    if (seller.respuestaInstantanea)
      const RespuestaInstantaneaBadge()
    else if (seller.respondeRapido)
      const RespondeRapidoBadge(),
    if (seller.esVendedorNuevo) const InsigniaVendedorNuevo(),
    // Una sola ventana no es una racha: todo el que publicó algo esta semana
    // tendría el badge y dejaría de significar constancia.
    if (seller.rachaSemanas > 1) RachaBadge(semanas: seller.rachaSemanas),
    if (seller.aniversarioAnios > 0)
      AniversarioBadge(anios: seller.aniversarioAnios),
    // Va al final de la fila: es la más rara de todas y se descubre después
    // de leer las que sí se explican solas.
    if (seller.enigmaPosicion != null)
      InsigniaEnigma(posicion: seller.enigmaPosicion!),
  ];
}

/// Calificación y, cuando aplica, "activo hace X" en una sola línea.
///
/// "Activo hace 5 min" solo aparece cuando NO está en línea: con el punto
/// verde en el avatar, repetirlo en texto sería ruido. Si no hay dato (o es
/// de hace más de una semana) desaparece con su separador, sin dejar hueco.
class _FilaMetadatos extends StatelessWidget {
  const _FilaMetadatos({
    required this.seller,
    required this.estadoConexion,
    required this.color,
    required this.colorSuave,
  });

  final Seller seller;
  final EstadoConexion estadoConexion;

  /// Los dos vienen del llamador y no del tema: esta fila va sobre la banda
  /// de marca, donde la tinta del tema no tendría contraste garantizado.
  final Color color;
  final Color colorSuave;

  @override
  Widget build(BuildContext context) {
    final actividad = estadoConexion.enLinea
        ? null
        : etiquetaUltimaActividad(estadoConexion.ultimaActividad);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La estrella va en el color del texto y no en el acento ámbar:
            // sobre la banda, el ámbar compite con el swatch del vendedor y
            // con algunos (los cálidos) se pierde del todo.
            Icon(Icons.star_rounded, color: color, size: 17),
            const SizedBox(width: 3),
            Text(
              seller.reviews > 0
                  ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews})'
                  : 'home.no_ratings'.tr(),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: color,
              ),
            ),
          ],
        ),
        if (actividad != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: colorSuave,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                actividad,
                style: TextStyle(color: colorSuave, fontSize: 12.5),
              ),
            ],
          ),
      ],
    );
  }
}
