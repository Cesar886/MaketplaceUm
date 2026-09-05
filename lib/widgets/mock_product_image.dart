import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'app_shimmer.dart';
import '../features/highlight/destacar_flag.dart';
import '../models.dart';
import '../services/api_service.dart';
import 'badges.dart';

class MockProductImage extends StatelessWidget {
  const MockProductImage({
    super.key,
    required this.product,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.showFeaturedBadge = true,
    this.photoIndex = 0,
  });

  final Product product;
  final double? height;
  final BorderRadius borderRadius;
  final bool showFeaturedBadge;
  final int photoIndex;

  @override
  Widget build(BuildContext context) {
    // Si hay imágenes reales subidas, mostrarlas
    if (product.images.isNotEmpty) {
      final index = photoIndex < product.images.length ? photoIndex : 0;
      final imageUrl = '${ApiService.baseUrl}${product.images[index]}';

      return ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            _RemoteProductImage(
              url: imageUrl,
              height: height,
              fallback: CategoryImagePlaceholder(
                product: product,
                height: height,
                showFeaturedBadge: showFeaturedBadge,
                photoIndex: photoIndex,
              ),
            ),
            if (showFeaturedBadge && product.isOffer)
              Positioned(
                left: 0,
                top: 0,
                child: OfferCornerTag(
                  label: product.discountLabel ?? 'badge.offer'.tr(),
                ),
              ),
            // TODO: Destacar publicaciones pendiente para próxima
            // actualización - no eliminar. El badge "Destacado" sobre la
            // foto queda oculto mientras kDestacarHabilitado sea false; la
            // etiqueta de oferta de arriba no se toca.
            // Ver features/highlight/destacar_flag.dart.
            if (kDestacarHabilitado && showFeaturedBadge && product.isFeatured)
              const Positioned(
                right: 8,
                top: 8,
                child: FeaturedBadge(compact: true),
              ),
          ],
        ),
      );
    }

    // Sin imágenes reales: mock icon
    return CategoryImagePlaceholder(
      product: product,
      height: height,
      borderRadius: borderRadius,
      showFeaturedBadge: showFeaturedBadge,
      photoIndex: photoIndex,
    );
  }
}

/// Foto remota de producto con tres garantías que `Image.network` pelado no
/// da: que el spinner termina, que la imagen no se decodifica más grande de
/// lo que se va a dibujar, y que la misma foto no se vuelve a bajar de la
/// red cada vez que aparece en una pantalla distinta.
///
/// **Por qué el timeout.** `Image.network` no tiene ninguno. Cuando el
/// servidor entrega un archivo pesado a ~20 KB/s, la respuesta es un 200 OK
/// perfectamente válido que tarda un minuto en completarse: `errorWidget`
/// nunca se dispara — no hay error — y el placeholder se queda dibujando el
/// spinner todo ese tiempo. El placeholder de categoría existía y estaba
/// bien escrito, pero era inalcanzable justo en el caso en el que hacía
/// falta. Pasado [_timeout] se abandona la carga y se dibuja el fallback,
/// que es una respuesta honesta ("no pudimos traer la foto") en vez de un
/// spinner indefinido.
///
/// El timeout acota el ESTADO DE UI, no la conexión: no hay forma de
/// cancelar la descarga que ya arrancó, así que el socket sigue su curso en
/// segundo plano y, si termina, la imagen queda cacheada para la próxima vez
/// que se pida esa URL. Lo que se corrige aquí es que la tarjeta deje de
/// mentirle a quien la mira.
///
/// **Por qué `CachedNetworkImage` y no `Image.network`.** `Image.network`
/// con `cacheWidth` guarda el bitmap decodificado en el `ImageCache` de
/// Flutter bajo una clave que incluye ese ancho — y la celda del grid del
/// home pide un ancho distinto al del carrusel del detalle, así que la
/// MISMA foto generaba dos entradas de caché distintas y se releía por red
/// en cada pantalla nueva (y de vuelta, si la primera ya había sido
/// desalojada). `CachedNetworkImage` cachea en disco por URL sola, sin
/// depender del tamaño con el que se pidió decodificar, así que home →
/// detalle → home reutiliza siempre el mismo archivo.
///
/// **Por qué `memCacheWidth`.** Sin él, se decodifica el bitmap a resolución
/// nativa del archivo: una foto de 1280 px decodificada para una tarjeta de
/// 180 px gasta ~50x los pixeles que va a dibujar. El ancho sale del
/// `LayoutBuilder` (el ancho real de la celda en este call site) por el
/// `devicePixelRatio` del dispositivo, así que cada sitio pide exactamente
/// lo que dibuja sin tener que pasarle un número a mano a cada uno. Esto
/// solo afecta al bitmap en memoria, no a la clave del caché en disco.
class _RemoteProductImage extends StatefulWidget {
  const _RemoteProductImage({
    required this.url,
    required this.height,
    required this.fallback,
  });

  final String url;
  final double? height;
  final Widget fallback;

  @override
  State<_RemoteProductImage> createState() => _RemoteProductImageState();
}

class _RemoteProductImageState extends State<_RemoteProductImage> {
  /// Margen holgado sobre el peor caso esperado una vez que el backend
  /// redimensiona a 1280 px: ~150 KB a ~20 KB/s son unos 8 s. Si se supera
  /// esto, el problema no es que la red vaya lenta.
  static const _timeout = Duration(seconds: 20);

  Timer? _temporizador;
  bool _agotado = false;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  @override
  void didUpdateWidget(_RemoteProductImage viejo) {
    super.didUpdateWidget(viejo);
    // Una celda de grid recicla su State al hacer scroll: si le cambian la
    // URL, el timeout de la foto anterior no aplica a la nueva.
    if (viejo.url != widget.url) {
      _temporizador?.cancel();
      _agotado = false;
      _arrancar();
    }
  }

  void _arrancar() {
    _temporizador = Timer(_timeout, () {
      if (mounted) setState(() => _agotado = true);
    });
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_agotado) return widget.fallback;

    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        // Un ancho no acotado (celda dentro de un scroll horizontal sin
        // tamaño fijo) no da una cifra con la que pedir decodificación; ahí
        // se deja decidir al paquete en vez de inventar un número.
        final memCacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * ratio).round()
            : null;

        return CachedNetworkImage(
          imageUrl: widget.url,
          height: widget.height,
          width: double.infinity,
          fit: BoxFit.cover,
          memCacheWidth: memCacheWidth,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (_, _, _) => widget.fallback,
          imageBuilder: (_, imageProvider) {
            // Hay pixeles listos (de red o de caché): la carga terminó y el
            // timeout ya no tiene nada que vigilar. Sin este cancel, a los 20
            // segundos el `_agotado` reemplazaría por el placeholder una foto
            // que ya se está viendo.
            _temporizador?.cancel();
            // `fit`/`width`/`height` van repetidos aquí a propósito: el
            // adaptador de cached_network_image (`_octoImageBuilder`)
            // DESCARTA el widget que OctoImage ya había construido con esas
            // propiedades y llama a este builder con el ImageProvider crudo.
            // Sin repetirlas, la foto se dibuja sin recortar y las tarjetas
            // del grid quedan con la imagen encogida dentro de la celda.
            return Image(
              image: imageProvider,
              height: widget.height,
              width: double.infinity,
              fit: BoxFit.cover,
            );
          },
          placeholder: (_, _) => AppShimmer(
            child: ShimmerBox(height: widget.height, borderRadius: 0),
          ),
        );
      },
    );
  }
}

/// Placeholder de categoría — se muestra cuando el producto no tiene
/// imágenes reales subidas. Extraído de [MockProductImage] para poder
/// reutilizarlo también en [ProductImageCarousel] cuando `images` está vacío.
class CategoryImagePlaceholder extends StatelessWidget {
  const CategoryImagePlaceholder({
    super.key,
    required this.product,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.showFeaturedBadge = true,
    this.photoIndex = 0,
  });

  final Product product;
  final double? height;
  final BorderRadius borderRadius;
  final bool showFeaturedBadge;
  final int photoIndex;

  @override
  Widget build(BuildContext context) {
    // El placeholder es ausencia de foto, no un producto más: se dibuja con
    // un ícono lineal fino en navy muy tenue sobre el fondo neutro cálido.
    // El bloque gris sólido de antes competía con las fotos reales de la
    // grilla y hacía que la pantalla se leyera como una plantilla a medio
    // llenar.
    final background = Color.lerp(
      context.colors.surfaceMuted,
      product.imageColor,
      0.05 + (photoIndex * 0.02).clamp(0, 0.06),
    )!;
    final accent = context.colors.accent;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: accent.withValues(alpha: 0.08)),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                product.imageIcon,
                size: 40,
                color: accent.withValues(alpha: 0.15),
              ),
            ),
            if (showFeaturedBadge && product.isOffer)
              Positioned(
                left: 0,
                top: 0,
                child: OfferCornerTag(
                  label: product.discountLabel ?? 'badge.offer'.tr(),
                ),
              ),
            // TODO: Destacar publicaciones pendiente para próxima
            // actualización - no eliminar. El badge "Destacado" sobre la
            // foto queda oculto mientras kDestacarHabilitado sea false; la
            // etiqueta de oferta de arriba no se toca.
            // Ver features/highlight/destacar_flag.dart.
            if (kDestacarHabilitado && showFeaturedBadge && product.isFeatured)
              const Positioned(
                right: 8,
                top: 8,
                child: FeaturedBadge(compact: true),
              ),
          ],
        ),
      ),
    );
  }
}
