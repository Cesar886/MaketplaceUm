import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/product_questions_section.dart';
import '../widgets/question_tile.dart';
import 'seller_profile_screen.dart';

/// Cuántas preguntas trae cada página.
const int _kPorPagina = 20;

/// Cuánto dura el resalte de la pregunta a la que apuntaba una notificación.
/// Lo suficiente para encontrarla con la vista; después se desvanece solo,
/// porque un resalte permanente se convierte en ruido en cuanto ya la viste.
const Duration _kDuracionResalte = Duration(seconds: 3);

/// Cuántas páginas se pueden encadenar buscando la pregunta de un deep link
/// antes de rendirse. Sin tope, una notificación vieja sobre un hilo enorme
/// dispararía una cascada de peticiones al abrir.
const int _kMaxPaginasBuscando = 5;

/// Todas las preguntas de una publicación.
///
/// Es la pantalla a la que llega el vendedor desde la notificación ("te
/// preguntaron") y el comprador desde "ver todas". Por eso hace dos cosas
/// que el preview del detalle no: pagina, y deja responder ahí mismo a quien
/// puede hacerlo.
class ProductQuestionsScreen extends StatefulWidget {
  const ProductQuestionsScreen({
    super.key,
    required this.productId,
    required this.productOwnerId,
    required this.sellerName,
    this.destacarPreguntaId,
    this.empezarEnPendientes = false,
  });

  final String productId;
  final String productOwnerId;
  final String sellerName;

  /// Pregunta a la que apuntaba el deep link de una notificación: al abrir
  /// se desplaza hasta ella y se resalta un momento.
  final String? destacarPreguntaId;

  /// Abre ya filtrado por "sin responder" — es como entra el vendedor desde
  /// el chip de pendientes.
  final bool empezarEnPendientes;

  @override
  State<ProductQuestionsScreen> createState() => _ProductQuestionsScreenState();
}

class _ProductQuestionsScreenState extends State<ProductQuestionsScreen> {
  final ScrollController _scroll = ScrollController();
  final List<ProductQuestion> _preguntas = [];

  /// Ancla por pregunta, para poder desplazarse hasta una concreta.
  final Map<String, GlobalKey> _anclas = {};

  bool _cargandoInicial = true;
  bool _cargandoMas = false;
  bool _soloPendientes = false;
  String? _cursor;
  String? _error;
  int _total = 0;
  int _pendientes = 0;

  /// Id resaltado ahora mismo. Se limpia solo tras [_kDuracionResalte].
  String? _resaltada;

  /// Pregunta con el input de respuesta abierto (solo para el dueño).
  String? _respondiendo;

  @override
  void initState() {
    super.initState();
    _soloPendientes = widget.empezarEnPendientes;
    _scroll.addListener(_alDesplazar);
    _cargarInicial();
  }

  @override
  void dispose() {
    _scroll.removeListener(_alDesplazar);
    _scroll.dispose();
    super.dispose();
  }

  void _alDesplazar() {
    if (!_scroll.hasClients || _cargandoMas || _cursor == null) return;
    final falta = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (falta < 400) _cargarMas();
  }

  Future<void> _cargarInicial() async {
    setState(() {
      _cargandoInicial = true;
      _error = null;
      _preguntas.clear();
      _anclas.clear();
      _cursor = null;
    });

    try {
      final pagina = await ApiService.getProductQuestions(
        widget.productId,
        limit: _kPorPagina,
        soloPendientes: _soloPendientes,
      );
      if (!mounted) return;
      setState(() {
        _preguntas.addAll(pagina.questions);
        _cursor = pagina.nextCursor;
        _total = pagina.total;
        _pendientes = pagina.pendingCount;
        _cargandoInicial = false;
      });
      await _irALaPreguntaDelDeepLink();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoInicial = false;
        _error = 'questions.load_error'.tr();
      });
    }
  }

  Future<bool> _cargarMas() async {
    if (_cursor == null || _cargandoMas) return false;
    setState(() => _cargandoMas = true);
    try {
      final pagina = await ApiService.getProductQuestions(
        widget.productId,
        cursor: _cursor,
        limit: _kPorPagina,
        soloPendientes: _soloPendientes,
      );
      if (!mounted) return false;
      setState(() {
        _preguntas.addAll(pagina.questions);
        _cursor = pagina.nextCursor;
        _total = pagina.total;
        _pendientes = pagina.pendingCount;
        _cargandoMas = false;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _cargandoMas = false);
      return false;
    }
  }

  /// Busca la pregunta del deep link, paginando si hace falta, y la deja a
  /// la vista y resaltada. Si no aparece (fue borrada, o el hilo creció
  /// demasiado), la pantalla se queda como está: haber llegado al hilo
  /// correcto ya es la mitad del trabajo.
  Future<void> _irALaPreguntaDelDeepLink() async {
    final objetivo = widget.destacarPreguntaId;
    if (objetivo == null) return;

    var paginas = 0;
    while (!_preguntas.any((q) => q.id == objetivo) &&
        _cursor != null &&
        paginas < _kMaxPaginasBuscando) {
      final hubo = await _cargarMas();
      if (!hubo) break;
      paginas++;
    }

    if (!mounted || !_preguntas.any((q) => q.id == objetivo)) return;

    setState(() => _resaltada = objetivo);

    // Un frame para que el ancla exista ya montada antes de buscarla.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // `mounted` del State no dice nada sobre ESTE contexto: el ancla pudo
    // desmontarse al reciclarse la fila mientras se cargaban páginas.
    final contexto = _anclas[objetivo]?.currentContext;
    if (contexto != null && contexto.mounted) {
      await Scrollable.ensureVisible(
        contexto,
        duration: AppAnimations.slow,
        curve: AppAnimations.easeOut,
        alignment: 0.2,
      );
    }

    await Future<void>.delayed(_kDuracionResalte);
    if (mounted) setState(() => _resaltada = null);
  }

  Future<void> _cambiarFiltro(bool soloPendientes) async {
    if (_soloPendientes == soloPendientes) return;
    setState(() => _soloPendientes = soloPendientes);
    await _cargarInicial();
  }

  Future<void> _preguntar() async {
    final texto = await mostrarModalPregunta(context);
    if (texto == null || !mounted) return;
    try {
      final nueva = await ApiService.askProductQuestion(
        widget.productId,
        texto,
      );
      if (!mounted) return;
      setState(() {
        _preguntas.insert(0, nueva);
        _total += 1;
        _pendientes += 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _responder(ProductQuestion pregunta, String texto) async {
    try {
      final actualizada = await ApiService.answerProductQuestion(
        pregunta.id,
        texto,
      );
      if (!mounted) return;
      setState(() {
        final i = _preguntas.indexWhere((q) => q.id == pregunta.id);
        if (i != -1) _preguntas[i] = actualizada;
        _respondiendo = null;
        // Si se está viendo el filtro de pendientes, la recién respondida ya
        // no pertenece a esa lista: se saca para que el filtro no mienta.
        if (_soloPendientes) _preguntas.removeWhere((q) => q.id == pregunta.id);
        if (!pregunta.isAnswered && _pendientes > 0) _pendientes -= 1;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _borrar(ProductQuestion pregunta) async {
    final indice = _preguntas.indexWhere((q) => q.id == pregunta.id);
    if (indice == -1) return;

    final totalAnterior = _total;
    final pendientesAnterior = _pendientes;
    setState(() {
      _preguntas.removeAt(indice);
      if (_respondiendo == pregunta.id) _respondiendo = null;
      if (_total > 0) _total -= 1;
      if (!pregunta.isAnswered && _pendientes > 0) _pendientes -= 1;
    });

    try {
      await ApiService.deleteProductQuestion(widget.productId, pregunta.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preguntas.insert(indice, pregunta);
        _total = totalAnterior;
        _pendientes = pendientesAnterior;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  bool _puedeBorrar(ProductQuestion pregunta, String? usuarioId) {
    if (usuarioId == null) return false;
    return pregunta.author.id == usuarioId ||
        widget.productOwnerId == usuarioId;
  }

  void _abrirPerfil(String sellerId) {
    if (sellerId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SellerProfileScreen(sellerId: sellerId),
      ),
    );
  }

  GlobalKey _anclaDe(String id) => _anclas.putIfAbsent(id, () => GlobalKey());

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usuarioId = auth.backendSellerId;
    final esDueno = usuarioId != null && usuarioId == widget.productOwnerId;

    return Scaffold(
      appBar: AppBar(
        // El total va en el título y no como línea aparte: es el dato que
        // dice de un vistazo si el hilo tiene una pregunta o cuarenta.
        title: Text(
          _total > 0
              ? 'questions.title_count'.tr(namedArgs: {'n': '$_total'})
              : 'questions.title'.tr(),
        ),
        bottom: esDueno && (_pendientes > 0 || _soloPendientes)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _FiltroPendientes(
                  soloPendientes: _soloPendientes,
                  pendientes: _pendientes,
                  onCambiar: _cambiarFiltro,
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _cargarInicial,
        child: _cuerpo(esDueno, usuarioId),
      ),
      // El dueño no pregunta en lo suyo: para él no hay barra de acción.
      bottomNavigationBar: esDueno
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: ElevatedButton.icon(
                  onPressed: _preguntar,
                  icon: const Icon(Icons.help_outline_rounded, size: 18),
                  label: Text('questions.ask'.tr()),
                ),
              ),
            ),
    );
  }

  Widget _cuerpo(bool esDueno, String? usuarioId) {
    if (_cargandoInicial) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        children: const [
          QuestionTileSkeleton(),
          QuestionTileSkeleton(),
          QuestionTileSkeleton(),
        ],
      );
    }

    if (_error != null) {
      return _MensajeCentrado(
        icono: Icons.cloud_off_rounded,
        texto: _error!,
        accion: TextButton(
          onPressed: _cargarInicial,
          child: Text('common.retry'.tr()),
        ),
      );
    }

    if (_preguntas.isEmpty) {
      return _MensajeCentrado(
        icono: Icons.forum_outlined,
        texto: _soloPendientes
            ? 'questions.none_pending'.tr()
            : esDueno
            ? 'questions.empty'.tr()
            : 'questions.be_first'.tr(),
      );
    }

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      // Siempre desplazable, para que el "deslizar para refrescar" funcione
      // aunque la lista sea corta.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _preguntas.length + (_cursor != null ? 1 : 0),
      separatorBuilder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Divider(height: 20, color: context.colors.border),
      ),
      itemBuilder: (context, index) {
        if (index >= _preguntas.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final pregunta = _preguntas[index];
        return KeyedSubtree(
          key: _anclaDe(pregunta.id),
          child: QuestionTile(
            question: pregunta,
            sellerName: widget.sellerName,
            destacada: _resaltada == pregunta.id,
            onAuthorTap: pregunta.author.id.isEmpty
                ? null
                : () => _abrirPerfil(pregunta.author.id),
            respuestaInline: esDueno
                ? _AccionesDelVendedor(
                    pregunta: pregunta,
                    abierto: _respondiendo == pregunta.id,
                    onAbrir: () => setState(() => _respondiendo = pregunta.id),
                    onCancelar: () => setState(() => _respondiendo = null),
                    onEnviar: (texto) => _responder(pregunta, texto),
                  )
                : null,
            onDelete: _puedeBorrar(pregunta, usuarioId)
                ? () => _borrar(pregunta)
                : null,
          ),
        );
      },
    );
  }
}

/// Alternador entre "todas" y "sin responder". Solo lo ve el dueño, y solo
/// si tiene (o tenía) pendientes: si no, es un control que no hace nada.
class _FiltroPendientes extends StatelessWidget {
  const _FiltroPendientes({
    required this.soloPendientes,
    required this.pendientes,
    required this.onCambiar,
  });

  final bool soloPendientes;
  final int pendientes;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text('questions.filter_all'.tr()),
              selected: !soloPendientes,
              onSelected: (_) => onCambiar(false),
            ),
            ChoiceChip(
              label: Text(
                pendientes > 0
                    ? 'questions.unanswered_count'.tr(
                        namedArgs: {'n': '$pendientes'},
                      )
                    : 'questions.unanswered'.tr(),
              ),
              selected: soloPendientes,
              onSelected: (_) => onCambiar(true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que puede hacer el dueño sobre una pregunta: responder si está
/// pendiente, corregir si ya respondió. Va debajo de la pregunta, en línea,
/// para que responder no signifique cambiar de pantalla.
class _AccionesDelVendedor extends StatefulWidget {
  const _AccionesDelVendedor({
    required this.pregunta,
    required this.abierto,
    required this.onAbrir,
    required this.onCancelar,
    required this.onEnviar,
  });

  final ProductQuestion pregunta;
  final bool abierto;
  final VoidCallback onAbrir;
  final VoidCallback onCancelar;
  final Future<void> Function(String texto) onEnviar;

  @override
  State<_AccionesDelVendedor> createState() => _AccionesDelVendedorState();
}

class _AccionesDelVendedorState extends State<_AccionesDelVendedor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.pregunta.answerText ?? '',
  );
  bool _enviando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    await widget.onEnviar(texto);
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.abierto) {
      // Cerrado: la respuesta ya existente la pinta QuestionTile, así que
      // aquí solo va el botón que abre el input.
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.onAbrir,
          style: TextButton.styleFrom(
            foregroundColor: context.colors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          icon: Icon(
            widget.pregunta.isAnswered
                ? Icons.edit_outlined
                : Icons.reply_rounded,
            size: 16,
          ),
          label: Text(
            widget.pregunta.isAnswered
                ? 'questions.edit_answer'.tr()
                : 'Responder',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          maxLength: kLargoMaximoPregunta,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'questions.answer_label'.tr(),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Row(
          children: [
            TextButton(
              onPressed: _enviando ? null : widget.onCancelar,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.muted,
              ),
              child: Text('common.cancel'.tr()),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _controller.text.trim().isEmpty || _enviando
                  ? null
                  : _enviar,
              child: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('questions.post_answer'.tr()),
            ),
          ],
        ),
      ],
    );
  }
}

class _MensajeCentrado extends StatelessWidget {
  const _MensajeCentrado({
    required this.icono,
    required this.texto,
    this.accion,
  });

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView y no Center para que el "deslizar para refrescar" siga
      // funcionando con la lista vacía.
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(
          icono,
          size: 40,
          color: context.colors.muted.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: AppTypography.body(14.5, color: context.colors.muted),
        ),
        if (accion != null) ...[
          const SizedBox(height: 8),
          Center(child: accion!),
        ],
      ],
    );
  }
}
