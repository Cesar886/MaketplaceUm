import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
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
                child: OfferCornerTag(label: product.discountLabel ?? 'Oferta'),
              ),
            if (showFeaturedBadge && product.isFeatured)
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

/// Foto remota de producto con dos garantías que `Image.network` pelado no
/// da: que el spinner termina, y que la imagen no se decodifica más grande
/// de lo que se va a dibujar.
///
/// **Por qué el timeout.** `Image.network` no tiene ninguno. Cuando el
/// servidor entrega un archivo pesado a ~20 KB/s, la respuesta es un 200 OK
/// perfectamente válido que tarda un minuto en completarse: `errorBuilder`
/// nunca se dispara — no hay error — y `loadingBuilder` se queda dibujando
/// el spinner todo ese tiempo. El placeholder de categoría existía y estaba
/// bien escrito, pero era inalcanzable justo en el caso en el que hacía
/// falta. Pasado [_timeout] se abandona la carga y se dibuja el fallback,
/// que es una respuesta honesta ("no pudimos traer la foto") en vez de un
/// spinner indefinido.
///
/// El timeout acota el ESTADO DE UI, no la conexión: Flutter no expone forma
/// de cancelar la descarga que `NetworkImage` ya arrancó, así que el socket
/// sigue su curso en segundo plano y, si termina, la imagen queda en el
/// caché de `ImageCache` para la próxima vez que se pida esa URL. Lo que se
/// corrige aquí es que la tarjeta deje de mentirle a quien la mira.
///
/// **Por qué cacheWidth.** Sin él, Flutter decodifica el bitmap a resolución
/// nativa del archivo y lo guarda así en memoria: una foto de 1280 px
/// decodificada para una tarjeta de 180 px gasta ~50x los pixeles que va a
/// dibujar. El ancho sale del `LayoutBuilder` (el ancho real de la celda en
/// este call site) por el `devicePixelRatio` del dispositivo, así que cada
/// sitio pide exactamente lo que dibuja sin tener que pasarle un número a
/// mano a cada uno.
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
        // se deja decidir a Flutter en vez de inventar un número.
        final cacheWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * ratio).round()
            : null;

        return Image.network(
          widget.url,
          height: widget.height,
          width: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          errorBuilder: (_, _, _) => widget.fallback,
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            // Hay pixeles en pantalla (o venían del caché): la carga terminó
            // y el timeout ya no tiene nada que vigilar. Cancelar un Timer no
            // toca el árbol, así que es seguro hacerlo durante el build.
            if (frame != null || wasSynchronouslyLoaded) {
              _temporizador?.cancel();
            }
            return child;
          },
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(
              height: widget.height,
              color: context.colors.surfaceMuted,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
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
                child: OfferCornerTag(label: product.discountLabel ?? 'Oferta'),
              ),
            if (showFeaturedBadge && product.isFeatured)
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
