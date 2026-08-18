import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../screens/product_detail_screen.dart';
import '../services/api_service.dart';
import '../utils/tiempo_relativo.dart';
import 'app_shimmer.dart';
import 'comment_tile.dart';

/// Cuántas tarjetas trae cada página.
const int _kPaginaComentarios = 15;

/// Caracteres del fragmento antes de truncar con "…".
const int _kLargoFragmento = 140;

/// Lista de los comentarios que OTROS dejaron en las publicaciones de un
/// usuario — la pestaña "Comentarios" del perfil.
///
/// Muestra lo RECIBIDO y no lo escrito por esa cuenta a propósito: la
/// pestaña existe como prueba social de un vendedor, y el historial de lo
/// que esa persona anduvo comentando por ahí no dice nada sobre si conviene
/// comprarle.
///
/// Se usa igual en el perfil público del vendedor y en la pantalla propia
/// (`MyCommentsScreen`); solo cambian los textos del estado vacío.
class CommentsReceivedList extends StatefulWidget {
  const CommentsReceivedList({
    super.key,
    required this.userId,
    this.esPerfilPropio = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    this.physics,
    this.shrinkWrap = false,
  });

  final String userId;

  /// Cambia el copy del estado vacío entre "Aún no has recibido…" y "Este
  /// vendedor aún no tiene comentarios".
  final bool esPerfilPropio;

  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  @override
  State<CommentsReceivedList> createState() => _CommentsReceivedListState();
}

class _CommentsReceivedListState extends State<CommentsReceivedList> {
  final List<ProductComment> _comentarios = [];

  bool _cargandoInicial = true;
  bool _cargandoMas = false;
  String? _error;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final pagina = await ApiService.getCommentsForUser(
        widget.userId,
        limit: _kPaginaComentarios,
      );
      if (!mounted) return;
      setState(() {
        _comentarios
          ..clear()
          ..addAll(pagina.comments);
        _cursor = pagina.nextCursor;
        _cargandoInicial = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoInicial = false;
        _error = 'comments.load_error'.tr();
      });
    }
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || _cursor == null) return;
    setState(() => _cargandoMas = true);
    try {
      final pagina = await ApiService.getCommentsForUser(
        widget.userId,
        cursor: _cursor,
        limit: _kPaginaComentarios,
      );
      if (!mounted) return;
      setState(() {
        final yaEstan = _comentarios.map((c) => c.id).toSet();
        _comentarios.addAll(
          pagina.comments.where((c) => !yaEstan.contains(c.id)),
        );
        _cursor = pagina.nextCursor;
        _cargandoMas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoMas = false);
    }
  }

  /// Abre el detalle del producto comentado, ya desplazado al hilo: se llega
  /// aquí desde un comentario, así que aterrizar arriba del todo obligaría a
  /// buscar a mano lo que se venía a leer.
  Future<void> _abrirProducto(ProductComment comentario) async {
    final mensajero = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    try {
      final producto = await ApiService.getProduct(comentario.productId);
      if (!mounted) return;
      navegador.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductDetailScreen(product: producto, irAComentarios: true),
        ),
      );
    } catch (_) {
      // Caso real: el dueño borró la publicación pero el comentario sigue
      // referenciándola en una lista ya cargada.
      mensajero.showSnackBar(
        SnackBar(content: Text('comments.listing_gone'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoInicial) {
      return ListView(
        padding: widget.padding,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        children: const [
          _TarjetaSkeleton(),
          _TarjetaSkeleton(),
          _TarjetaSkeleton(),
        ],
      );
    }

    if (_error != null) {
      return _Centrado(
        padding: widget.padding,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: context.colors.muted)),
            const SizedBox(height: 8),
            TextButton(onPressed: _cargar, child: Text('common.retry'.tr())),
          ],
        ),
      );
    }

    if (_comentarios.isEmpty) {
      return _Centrado(
        padding: widget.padding,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: context.colors.muted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              widget.esPerfilPropio
                  ? 'comments.none_received'.tr()
                  : 'comments.seller_none'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.colors.muted),
            ),
            if (widget.esPerfilPropio) ...[
              const SizedBox(height: 6),
              Text(
                'comments.none_received_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: context.colors.muted),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: widget.padding,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        itemCount: _comentarios.length + (_cursor != null ? 1 : 0),
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          indent: kCommentDividerIndent,
          color: context.colors.border.withValues(alpha: 0.5),
        ),
        itemBuilder: (context, index) {
          if (index >= _comentarios.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: TextButton(
                  onPressed: _cargandoMas ? null : _cargarMas,
                  child: _cargandoMas
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('comments.see_more'.tr()),
                ),
              ),
            );
          }

          final comentario = _comentarios[index];
          return _TarjetaComentarioRecibido(
            comentario: comentario,
            onTap: () => _abrirProducto(comentario),
          );
        },
      ),
    );
  }
}

/// Un estado (vacío/error) dentro de un scrollable, para que el
/// RefreshIndicator y el `shrinkWrap` del contenedor sigan funcionando.
class _Centrado extends StatelessWidget {
  const _Centrado({
    required this.child,
    required this.padding,
    required this.physics,
    required this.shrinkWrap,
  });

  final Widget child;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding.add(const EdgeInsets.symmetric(vertical: 32)),
      physics: physics,
      shrinkWrap: shrinkWrap,
      children: [Center(child: child)],
    );
  }
}

class _TarjetaComentarioRecibido extends StatelessWidget {
  const _TarjetaComentarioRecibido({
    required this.comentario,
    required this.onTap,
  });

  final ProductComment comentario;
  final VoidCallback onTap;

  String get _fragmento {
    final texto = comentario.texto.replaceAll('\n', ' ');
    return texto.length <= _kLargoFragmento
        ? texto
        : '${texto.substring(0, _kLargoFragmento).trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CommentAvatar(author: comentario.author),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          comentario.author.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.heading(
                            14.5,
                            color: context.colors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tiempoRelativo(comentario.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fragmento,
                    style: AppTypography.body(14, color: context.colors.ink),
                  ),
                  const SizedBox(height: 10),
                  _ProductoComentado(comentario: comentario),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura + título del producto donde cayó el comentario. Es la pista de
/// a dónde lleva el tap, así que va dentro de la tarjeta y no como una
/// acción aparte.
class _ProductoComentado extends StatelessWidget {
  const _ProductoComentado({required this.comentario});

  final ProductComment comentario;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: 32,
            height: 32,
            child: comentario.productImage != null
                ? Image.network(
                    '${ApiService.baseUrl}${comentario.productImage}',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _MiniaturaVacia(),
                  )
                : _MiniaturaVacia(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            comentario.productTitle ?? 'comments.listing'.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.colors.muted,
            ),
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: context.colors.muted,
        ),
      ],
    );
  }
}

class _MiniaturaVacia extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.surfaceMuted,
      child: Icon(
        Icons.image_outlined,
        size: 16,
        color: context.colors.muted.withValues(alpha: 0.6),
      ),
    );
  }
}

class _TarjetaSkeleton extends StatelessWidget {
  const _TarjetaSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: AppShimmer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            ShimmerBox(width: 36, height: 36, shape: BoxShape.circle),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 130, height: 13),
                  SizedBox(height: 10),
                  ShimmerBox(width: double.infinity, height: 12),
                  SizedBox(height: 6),
                  ShimmerBox(width: 180, height: 12),
                  SizedBox(height: 12),
                  ShimmerBox(width: 160, height: 32, borderRadius: 7),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
