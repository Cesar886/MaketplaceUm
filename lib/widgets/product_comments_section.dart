import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/verification_screen.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import 'comment_tile.dart';

/// Cuántos comentarios trae la carga inicial y cada "Ver más".
const int _kPaginaComentarios = 10;

/// Tope de caracteres. Replicado en el backend (validation/comentarios.js) y
/// como CHECK en la tabla; acá solo sirve para que el contador y el
/// `maxLength` del input coincidan con lo que el servidor va a aceptar.
const int _kLargoMaximo = 500;

/// Sección de comentarios del detalle de producto: hilo paginado, borrado
/// con permiso, comentarios en vivo por Socket.IO y el campo para escribir
/// (o la invitación a verificarse, si la cuenta todavía no lo está).
class ProductCommentsSection extends StatefulWidget {
  const ProductCommentsSection({
    super.key,
    required this.productId,
    required this.productOwnerId,
  });

  final String productId;

  /// Id del dueño de la publicación: puede borrar cualquier comentario del
  /// hilo (moderación de lo suyo), no solo los propios.
  final String productOwnerId;

  @override
  State<ProductCommentsSection> createState() => _ProductCommentsSectionState();
}

class _ProductCommentsSectionState extends State<ProductCommentsSection> {
  final List<ProductComment> _comentarios = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  StreamSubscription<Map<String, dynamic>>? _subNuevo;
  StreamSubscription<Map<String, dynamic>>? _subBorrado;

  bool _cargandoInicial = true;
  bool _cargandoMas = false;
  bool _enviando = false;
  String? _error;
  String? _cursor;
  int _total = 0;

  /// Ids que llegaron por socket o que acaba de escribir el usuario. Solo
  /// esos se animan al aparecer: si se animara toda la lista, cada "Ver más"
  /// haría parpadear comentarios que ya estaban en pantalla.
  final Set<String> _recienLlegados = {};

  @override
  void initState() {
    super.initState();
    _cargarPrimeraPagina();
    _suscribirseAlProducto();
  }

  @override
  void dispose() {
    // Salir de la sala es obligatorio: el socket es único y compartido para
    // toda la app, así que una sala que no se abandona sigue recibiendo
    // eventos de un producto que el usuario ya cerró.
    ChatSocketService.instance.leaveProduct(widget.productId);
    _subNuevo?.cancel();
    _subBorrado?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _suscribirseAlProducto() {
    final socket = ChatSocketService.instance;
    // `connect()` es idempotente: si el chat ya lo abrió, esto no hace nada.
    socket.connect();
    socket.joinProduct(widget.productId);

    _subNuevo = socket.onNewComment.listen((evento) {
      if (!mounted) return;
      if (evento['productId'] != widget.productId) return;
      final crudo = evento['comment'];
      if (crudo is! Map) return;

      final nuevo = ProductComment.fromJson(Map<String, dynamic>.from(crudo));
      // El autor ya lo insertó localmente al recibir la respuesta del POST;
      // sin este filtro lo vería duplicado cuando le llegue su propio evento.
      if (_comentarios.any((c) => c.id == nuevo.id)) return;

      setState(() {
        _comentarios.insert(0, nuevo);
        _recienLlegados.add(nuevo.id);
        _total++;
      });
    });

    _subBorrado = socket.onCommentDeleted.listen((evento) {
      if (!mounted) return;
      if (evento['productId'] != widget.productId) return;
      final id = evento['commentId'];
      if (id is! String) return;

      setState(() {
        final quitados = _comentarios.length;
        _comentarios.removeWhere((c) => c.id == id);
        if (_comentarios.length < quitados && _total > 0) _total--;
      });
    });
  }

  Future<void> _cargarPrimeraPagina() async {
    try {
      final pagina = await ApiService.getProductComments(
        widget.productId,
        limit: _kPaginaComentarios,
      );
      if (!mounted) return;
      setState(() {
        _comentarios
          ..clear()
          ..addAll(pagina.comments);
        _cursor = pagina.nextCursor;
        _total = pagina.total;
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
      final pagina = await ApiService.getProductComments(
        widget.productId,
        cursor: _cursor,
        limit: _kPaginaComentarios,
      );
      if (!mounted) return;
      setState(() {
        // Un comentario puede haber llegado por socket mientras se pedía la
        // página; el cursor evita que el servidor lo repita, pero no cuesta
        // nada blindar el caso.
        final yaEstan = _comentarios.map((c) => c.id).toSet();
        _comentarios.addAll(
          pagina.comments.where((c) => !yaEstan.contains(c.id)),
        );
        _cursor = pagina.nextCursor;
        _total = pagina.total;
        _cargandoMas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoMas = false);
      _avisar('comments.load_more_error'.tr());
    }
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _enviando) return;

    setState(() => _enviando = true);
    try {
      final nuevo = await ApiService.postProductComment(
        widget.productId,
        texto,
      );
      if (!mounted) return;
      setState(() {
        // Se inserta local en vez de esperar el eco del socket: el autor debe
        // ver su comentario al instante aunque el socket esté caído.
        if (!_comentarios.any((c) => c.id == nuevo.id)) {
          _comentarios.insert(0, nuevo);
          _recienLlegados.add(nuevo.id);
          _total++;
        }
        _controller.clear();
        _enviando = false;
      });
      _focus.unfocus();
    } on ComentarioNoVerificadoException catch (e) {
      // La cuenta perdió la verificación entre que se pintó el input y el
      // envío. Se rebota el estado para que aparezca la tarjeta correcta.
      if (!mounted) return;
      setState(() => _enviando = false);
      _avisar(e.message);
      await context.read<AuthProvider>().refrescarEstadoVerificacion();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _avisar(_mensajeDeError(e));
    }
  }

  Future<void> _borrar(ProductComment comentario) async {
    // Optimista: se quita ya y se repone si el backend rechaza. Borrar es la
    // acción que más se siente lenta cuando espera al servidor.
    final indice = _comentarios.indexWhere((c) => c.id == comentario.id);
    if (indice == -1) return;

    setState(() {
      _comentarios.removeAt(indice);
      if (_total > 0) _total--;
    });

    try {
      await ApiService.deleteProductComment(widget.productId, comentario.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comentarios.insert(indice, comentario);
        _total++;
      });
      _avisar(_mensajeDeError(e));
    }
  }

  String _mensajeDeError(Object error) {
    final texto = error.toString().replaceFirst('Exception: ', '');
    return texto.isEmpty || texto.length > 140 ? 'errors.generic'.tr() : texto;
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Puede borrar el autor del comentario o el dueño de la publicación.
  bool _puedeBorrar(ProductComment comentario, String? usuarioId) {
    if (usuarioId == null) return false;
    return comentario.author.id == usuarioId ||
        widget.productOwnerId == usuarioId;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usuarioId = auth.backendSellerId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Encabezado(total: _total, cargando: _cargandoInicial),
        const SizedBox(height: 14),
        if (_cargandoInicial)
          const CommentListSkeleton()
        else if (_error != null)
          _EstadoError(mensaje: _error!, onReintentar: _cargarPrimeraPagina)
        else if (_comentarios.isEmpty)
          const _EstadoVacio()
        else
          _ListaComentarios(
            comentarios: _comentarios,
            recienLlegados: _recienLlegados,
            puedeBorrar: (c) => _puedeBorrar(c, usuarioId),
            onBorrar: _borrar,
          ),
        if (!_cargandoInicial && _error == null && _cursor != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: _cargandoMas ? null : _cargarMas,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.accent,
              ),
              child: _cargandoMas
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  // Con clamp: el total viene del servidor y la lista crece
                  // también por socket, así que un total momentáneamente
                  // desfasado no debe pintar "Ver más comentarios (-2)".
                  : Text(
                      _total > _comentarios.length
                          ? 'comments.see_more_count'.tr(
                              namedArgs: {
                                'n': '${_total - _comentarios.length}',
                              },
                            )
                          : 'comments.see_more'.tr(),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        // Anónimo o sin verificar: no hay input, hay invitación. El backend
        // rechaza igual (403), pero mostrar un campo que siempre falla es
        // peor que no mostrarlo.
        if (auth.isLoggedIn && auth.isVerified)
          _CampoComentario(
            controller: _controller,
            focus: _focus,
            enviando: _enviando,
            onEnviar: _enviar,
          )
        else
          const TarjetaVerificaParaComentar(),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.total, required this.cargando});

  final int total;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.mode_comment_outlined,
          size: 18,
          color: context.colors.accent,
        ),
        const SizedBox(width: 8),
        Text(
          // El contador se omite mientras carga en vez de mostrar "(0)", que
          // se leería como "no hay comentarios" justo antes de aparecer.
          cargando
              ? 'profile.comments'.tr()
              : 'comments.title_count'.tr(namedArgs: {'n': '$total'}),
          style: AppTypography.heading(16, color: context.colors.ink),
        ),
      ],
    );
  }
}

class _ListaComentarios extends StatelessWidget {
  const _ListaComentarios({
    required this.comentarios,
    required this.recienLlegados,
    required this.puedeBorrar,
    required this.onBorrar,
  });

  final List<ProductComment> comentarios;
  final Set<String> recienLlegados;
  final bool Function(ProductComment) puedeBorrar;
  final void Function(ProductComment) onBorrar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < comentarios.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 18),
            Divider(
              height: 1,
              thickness: 1,
              indent: kCommentDividerIndent,
              color: context.colors.border.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 18),
          ],
          _AparicionSuave(
            key: ValueKey(comentarios[i].id),
            animar: recienLlegados.contains(comentarios[i].id),
            child: CommentTile(
              comment: comentarios[i],
              onDelete: puedeBorrar(comentarios[i])
                  ? () => onBorrar(comentarios[i])
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// Fade-in de un comentario recién llegado. Solo opacidad y un
/// desplazamiento mínimo: la idea es que se note que algo apareció, no
/// montar una animación de entrada.
class _AparicionSuave extends StatefulWidget {
  const _AparicionSuave({super.key, required this.child, required this.animar});

  final Widget child;
  final bool animar;

  @override
  State<_AparicionSuave> createState() => _AparicionSuaveState();
}

class _AparicionSuaveState extends State<_AparicionSuave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppAnimations.medium,
    // Un comentario que ya estaba en la lista arranca en su estado final:
    // repaginar no debe hacer parpadear lo que ya se veía.
    value: widget.animar ? 0 : 1,
  );

  // Se crea UNA vez, no en build(): una CurvedAnimation nueva por
  // reconstrucción se suscribe al controller y nunca se libera, y el hilo se
  // reconstruye en cada comentario que llega por socket.
  late final CurvedAnimation _curva = CurvedAnimation(
    parent: _controller,
    curve: AppAnimations.easeOut,
  );

  late final Animation<Offset> _desplazamiento = Tween<Offset>(
    begin: const Offset(0, -0.06),
    end: Offset.zero,
  ).animate(_curva);

  @override
  void initState() {
    super.initState();
    if (widget.animar) _controller.forward();
  }

  @override
  void dispose() {
    _curva.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curva,
      child: SlideTransition(position: _desplazamiento, child: widget.child),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 40,
              color: context.colors.muted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'comments.be_first'.tr(),
              style: TextStyle(fontSize: 14, color: context.colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoError extends StatelessWidget {
  const _EstadoError({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onReintentar,
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoComentario extends StatelessWidget {
  const _CampoComentario({
    required this.controller,
    required this.focus,
    required this.enviando,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enviando;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focus,
            enabled: !enviando,
            maxLength: _kLargoMaximo,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            style: AppTypography.body(14.5, color: context.colors.ink),
            decoration: InputDecoration(
              hintText: 'comments.input_hint'.tr(),
              // El contador solo estorba hasta que estás cerca del tope; el
              // TextField lo respeta igual sin pintarlo.
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: context.colors.surfaceMuted,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: context.colors.accent,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SizedBox(
            width: 42,
            height: 42,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, valor, _) {
                final habilitado = !enviando && valor.text.trim().isNotEmpty;
                return IconButton.filled(
                  onPressed: habilitado ? onEnviar : null,
                  style: IconButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    disabledBackgroundColor: context.colors.muted.withValues(
                      alpha: 0.2,
                    ),
                  ),
                  icon: enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  tooltip: 'comments.post'.tr(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Reemplaza al campo de texto cuando la cuenta no puede comentar.
///
/// Sin borde ni sombra: la separa del hilo un tinte del color de marca, no
/// una caja — la misma línea que el resto de la app.
class TarjetaVerificaParaComentar extends StatelessWidget {
  const TarjetaVerificaParaComentar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: context.colors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'comments.verify_title'.tr(),
                  style: AppTypography.heading(14.5, color: context.colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'comments.verify_body'.tr(),
            style: TextStyle(fontSize: 13, color: context.colors.muted),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // Sin sesión no hay tipo de cuenta que verificar: primero hay
              // que iniciarla, y de eso ya se encarga el resto de la app.
              onPressed: !auth.isLoggedIn
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            VerificationScreen(tipo: auth.accountType),
                      ),
                    ),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              icon: Text('comments.verify_action'.tr()),
              label: const Icon(Icons.arrow_forward_rounded, size: 16),
            ),
          ),
          if (!auth.isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'comments.verify_login'.tr(),
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
