import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import 'badges.dart';
import 'mock_product_image.dart';

/// Carrusel unificado de imágenes del producto, estilo Instagram/Airbnb:
/// una sola pieza deslizable que reemplaza la imagen principal + fila de
/// miniaturas. Sin imágenes reales cae al placeholder de categoría; con una
/// sola imagen no muestra puntos ni permite deslizar; con varias, agrega
/// puntos de posición y zoom con pellizco/doble-tap por imagen.
class ProductImageCarousel extends StatefulWidget {
  const ProductImageCarousel({super.key, required this.product});

  final Product product;

  @override
  State<ProductImageCarousel> createState() => _ProductImageCarouselState();
}

class _ProductImageCarouselState extends State<ProductImageCarousel> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.images;

    if (images.isEmpty) {
      return CategoryImagePlaceholder(
        product: widget.product,
        borderRadius: BorderRadius.zero,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          physics: images.length > 1
              ? const PageScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          itemCount: images.length,
          onPageChanged: (index) => setState(() => _page = index),
          itemBuilder: (context, index) {
            return _ZoomableProductImage(
              url: '${ApiService.baseUrl}${images[index]}',
              product: widget.product,
            );
          },
        ),
        if (widget.product.isOffer || widget.product.isFeatured)
          Positioned(
            right: 8,
            top: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.product.isOffer)
                  OfferBadge(
                    label: widget.product.discountLabel,
                    compact: true,
                  ),
                if (widget.product.isOffer && widget.product.isFeatured)
                  const SizedBox(height: 6),
                if (widget.product.isFeatured)
                  const FeaturedBadge(compact: true),
              ],
            ),
          ),
        if (images.length > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: _PageDots(count: images.length, index: _page),
          ),
      ],
    );
  }
}

/// Una imagen del carrusel con pinch-to-zoom y doble-tap para ampliar.
/// `panEnabled` solo se activa mientras la imagen está ampliada, para que
/// el gesto de un dedo no le dispute el swipe horizontal al [PageView].
class _ZoomableProductImage extends StatefulWidget {
  const _ZoomableProductImage({required this.url, required this.product});

  final String url;
  final Product product;

  @override
  State<_ZoomableProductImage> createState() => _ZoomableProductImageState();
}

class _ZoomableProductImageState extends State<_ZoomableProductImage> {
  final _transformationController = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_zoomed) {
      _transformationController.value = Matrix4.identity();
      setState(() => _zoomed = false);
      return;
    }
    final position = details.localPosition;
    const targetScale = 2.8;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * targetScale,
        -position.dy * targetScale,
        0,
        1,
      )
      ..scaleByDouble(targetScale, targetScale, targetScale, 1);
    setState(() => _zoomed = true);
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final nowZoomed = scale > 1.01;
    if (nowZoomed != _zoomed) setState(() => _zoomed = nowZoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transformationController,
        panEnabled: _zoomed,
        minScale: 1,
        maxScale: 4,
        onInteractionEnd: _handleInteractionEnd,
        // `cacheWidth` acotado al ancho real de pantalla: sin él, Flutter
        // decodifica el bitmap a la resolución nativa del archivo aunque acá
        // se vaya a dibujar a lo mucho el ancho del teléfono — con fotos de
        // varios megapixeles eso es el grueso del tiempo de "carga". Mismo
        // criterio que [_RemoteProductImage] en mock_product_image.dart.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ratio = MediaQuery.devicePixelRatioOf(context);
            final cacheWidth = constraints.maxWidth.isFinite
                ? (constraints.maxWidth * ratio).round()
                : null;

            return Image.network(
              widget.url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => CategoryImagePlaceholder(
                product: widget.product,
                borderRadius: BorderRadius.zero,
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: context.colors.surfaceMuted,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Puntos de posición discretos, estilo Instagram: sombra sutil para
/// mantener contraste sobre cualquier imagen de fondo, clara u oscura.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 7 : 6,
          height: active ? 7 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: active ? 0.95 : 0.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        );
      }),
    );
  }
}
