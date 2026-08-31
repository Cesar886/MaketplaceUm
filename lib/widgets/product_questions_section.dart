import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/product_questions_screen.dart';
import '../screens/seller_profile_screen.dart';
import '../services/api_service.dart';
import 'question_tile.dart';

/// Tope de caracteres de una pregunta. Espejo del backend
/// (validation/comentarios.js) y del CHECK de la tabla: acá solo sirve para
/// que el contador y el `maxLength` coincidan con lo que el servidor acepta,
/// no como única validación.
const int kLargoMaximoPregunta = 500;

/// Sección "Preguntas y respuestas" del detalle de producto.
///
/// Muestra un asomo de las preguntas más útiles (respondidas recientes
/// primero, ver el backend) y lleva a la pantalla completa. Si no hay
/// ninguna, no se pinta ni el encabezado: queda solo la invitación a
/// preguntar, y si además quien mira es el dueño, no queda nada — un bloque
/// vacío en medio del detalle no informa de nada.
class ProductQuestionsSection extends StatefulWidget {
  const ProductQuestionsSection({
    super.key,
    required this.productId,
    required this.productOwnerId,
    required this.sellerName,
  });

  final String productId;

  /// Dueño de la publicación: no puede preguntar (el backend también lo
  /// rechaza) y es el único que puede responder.
  final String productOwnerId;

  final String sellerName;

  @override
  State<ProductQuestionsSection> createState() =>
      _ProductQuestionsSectionState();
}

class _ProductQuestionsSectionState extends State<ProductQuestionsSection> {
  List<ProductQuestion> _preguntas = const [];
  bool _cargando = true;
  int _total = 0;
  int _pendientes = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final pagina = await ApiService.getProductQuestionsPreview(
        widget.productId,
      );
      if (!mounted) return;
      setState(() {
        _preguntas = pagina.questions;
        _total = pagina.total;
        _pendientes = pagina.pendingCount;
        _cargando = false;
      });
    } catch (_) {
      // Sin preguntas visibles la sección se comporta como si no hubiera:
      // esto es un apoyo del detalle, no su contenido, y un mensaje de error
      // aquí abajo solo daría ruido.
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _borrar(ProductQuestion pregunta) async {
    final anteriores = _preguntas;
    final totalAnterior = _total;
    final pendientesAnterior = _pendientes;
    final indice = _preguntas.indexWhere((q) => q.id == pregunta.id);
    if (indice == -1) return;

    setState(() {
      _preguntas = [
        for (final q in _preguntas)
          if (q.id != pregunta.id) q,
      ];
      if (_total > 0) _total -= 1;
      if (!pregunta.isAnswered && _pendientes > 0) _pendientes -= 1;
    });

    try {
      await ApiService.deleteProductQuestion(widget.productId, pregunta.id);
      if (mounted) await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preguntas = anteriores;
        _total = totalAnterior;
        _pendientes = pendientesAnterior;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensajeDeError(e))));
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

  Future<void> _abrirTodas({bool soloPendientes = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductQuestionsScreen(
          productId: widget.productId,
          productOwnerId: widget.productOwnerId,
          sellerName: widget.sellerName,
          empezarEnPendientes: soloPendientes,
        ),
      ),
    );
    // Al volver puede haber preguntas nuevas o respuestas recién escritas.
    if (mounted) _cargar();
  }

  /// Abre el modal para escribir, pidiendo sesión antes si hace falta.
  Future<void> _preguntar() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('questions.login_prompt'.tr()),
          action: SnackBarAction(
            label: 'auth.login_button'.tr(),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
            ),
          ),
        ),
      );
      return;
    }

    final texto = await mostrarModalPregunta(context);
    if (texto == null || !mounted) return;

    try {
      final nueva = await ApiService.askProductQuestion(
        widget.productId,
        texto,
      );
      if (!mounted) return;
      setState(() {
        // Entra arriba: es la que el usuario acaba de escribir y quiere ver.
        _preguntas = [nueva, ..._preguntas].take(3).toList();
        _total += 1;
        _pendientes += 1;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('questions.sent'.tr())));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mensajeDeError(e))));
    }
  }

  String _mensajeDeError(Object error) {
    final texto = error.toString().replaceFirst('Exception: ', '');
    return texto.length > 140 ? 'questions.send_error'.tr() : texto;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final usuarioId = auth.backendSellerId;
    final esDueno = usuarioId != null && usuarioId == widget.productOwnerId;

    // Mientras carga no se pinta nada: el caso más común de una publicación
    // nueva es "sin preguntas", y un esqueleto que después se desvanece
    // dejaría un salto en medio del detalle.
    if (_cargando) return const SizedBox.shrink();

    if (_preguntas.isEmpty) {
      // Al dueño no se le invita a preguntarse a sí mismo, así que no queda
      // nada que mostrar.
      if (esDueno) return const SizedBox.shrink();
      return _InvitacionAPreguntar(onPreguntar: _preguntar);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.forum_outlined, size: 18, color: context.colors.accent),
            const SizedBox(width: 8),
            Text(
              'questions.title'.tr(),
              style: AppTypography.heading(15, color: context.colors.ink),
            ),
            if (esDueno && _pendientes > 0) ...[
              const SizedBox(width: 8),
              _ChipPendientes(
                cantidad: _pendientes,
                onTap: () => _abrirTodas(soloPendientes: true),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        for (final pregunta in _preguntas)
          QuestionTile(
            question: pregunta,
            sellerName: widget.sellerName,
            onAuthorTap: pregunta.author.id.isEmpty
                ? null
                : () => _abrirPerfil(pregunta.author.id),
            onDelete: _puedeBorrar(pregunta, usuarioId)
                ? () => _borrar(pregunta)
                : null,
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (!esDueno)
              TextButton.icon(
                onPressed: _preguntar,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('questions.ask'.tr()),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => _abrirTodas(),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.muted,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                _total > _preguntas.length
                    ? 'questions.see_n'.tr(namedArgs: {'n': '$_total'})
                    : 'questions.see_all'.tr(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Lo único que se muestra cuando la publicación todavía no tiene preguntas:
/// una línea que invita, sin encabezado ni marco que anuncien una sección
/// vacía.
class _InvitacionAPreguntar extends StatelessWidget {
  const _InvitacionAPreguntar({required this.onPreguntar});

  final VoidCallback onPreguntar;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPreguntar,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 18,
              color: context.colors.muted,
            ),
            const SizedBox(width: 6),
            // `Text.rich` dentro de `Flexible` y no dos `Text` sueltos en el
            // Row: la frase entera ronda los 280 px y en un teléfono angosto
            // —o con la fuente del sistema agrandada— dos hijos rígidos
            // desbordaban el Row con la franja amarilla y negra. Así se parte
            // en varias líneas, y el subrayado sigue cayendo solo sobre la
            // parte clicable.
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${'questions.cta_question'.tr()} ',
                      style: TextStyle(color: context.colors.muted),
                    ),
                    // Subrayado a propósito: es lo único de la frase que se
                    // puede tocar, y sin esa marca visual leía como una nota
                    // informativa, no como la invitación clicable que es.
                    TextSpan(
                      text: 'questions.cta_action'.tr(),
                      style: TextStyle(
                        color: context.colors.accent,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: context.colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipPendientes extends StatelessWidget {
  const _ChipPendientes({required this.cantidad, required this.onTap});

  final int cantidad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // `danger` y no un naranja fijo: es el único semántico de la paleta que
    // ya viene resuelto contra el tema (ladrillo en claro, salmón en oscuro),
    // así que el chip se lee igual de bien en ambos y con cualquier swatch.
    final color = context.colors.danger;
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
          child: Text(
            'questions.unanswered_n'.plural(cantidad),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja para escribir una pregunta. Devuelve el texto ya validado en cliente
/// (espejo del backend, no sustituto) o null si se canceló.
/// Los textos son opcionales y se resuelven dentro: un valor por defecto de
/// parámetro tiene que ser constante, y `.tr()` es una llamada.
Future<String?> mostrarModalPregunta(
  BuildContext context, {
  String? titulo,
  String? etiqueta,
  String? textoBoton,
  String? valorInicial,
}) {
  // Locales `final`: dentro del closure de `builder` Dart no conserva la
  // promoción de un parámetro nullable, aunque ya se le haya asignado.
  final tituloFinal = titulo ?? 'questions.ask'.tr();
  final etiquetaFinal = etiqueta ?? 'questions.input_label'.tr();
  final botonFinal = textoBoton ?? 'questions.send'.tr();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (contextoHoja) => _HojaTexto(
      titulo: tituloFinal,
      etiqueta: etiquetaFinal,
      textoBoton: botonFinal,
      valorInicial: valorInicial,
    ),
  );
}

class _HojaTexto extends StatefulWidget {
  const _HojaTexto({
    required this.titulo,
    required this.etiqueta,
    required this.textoBoton,
    this.valorInicial,
  });

  final String titulo;
  final String etiqueta;
  final String textoBoton;
  final String? valorInicial;

  @override
  State<_HojaTexto> createState() => _HojaTextoState();
}

class _HojaTextoState extends State<_HojaTexto> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.valorInicial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valido => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        // Sube con el teclado: si no, el botón de enviar queda debajo.
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.titulo,
            style: AppTypography.heading(16, color: context.colors.ink),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            maxLength: kLargoMaximoPregunta,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: widget.etiqueta,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_valido) Navigator.of(context).pop(_controller.text.trim());
            },
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _valido
                  ? () => Navigator.of(context).pop(_controller.text.trim())
                  : null,
              child: Text(widget.textoBoton),
            ),
          ),
        ],
      ),
    );
  }
}
