import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/product_questions_screen.dart';
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
  State<ProductQuestionsSection> createState() => _ProductQuestionsSectionState();
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
      final pagina = await ApiService.getProductQuestionsPreview(widget.productId);
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

  bool get _esDueno {
    final auth = context.read<AuthProvider>();
    return auth.backendSellerId != null &&
        auth.backendSellerId == widget.productOwnerId;
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
          content: const Text('Inicia sesión para hacer una pregunta'),
          action: SnackBarAction(
            label: 'Iniciar sesión',
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
      final nueva = await ApiService.askProductQuestion(widget.productId, texto);
      if (!mounted) return;
      setState(() {
        // Entra arriba: es la que el usuario acaba de escribir y quiere ver.
        _preguntas = [nueva, ..._preguntas].take(3).toList();
        _total += 1;
        _pendientes += 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pregunta enviada. Te avisamos cuando respondan.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeDeError(e))),
      );
    }
  }

  String _mensajeDeError(Object error) {
    final texto = error.toString().replaceFirst('Exception: ', '');
    return texto.length > 140 ? 'No se pudo enviar la pregunta.' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final esDueno = _esDueno;

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
            Icon(
              Icons.forum_outlined,
              size: 18,
              color: context.colors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              'Preguntas y respuestas',
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
          QuestionTile(question: pregunta, sellerName: widget.sellerName),
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
                label: const Text('Hacer una pregunta'),
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
                    ? 'Ver las $_total preguntas'
                    : 'Ver todas',
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
      child: TextButton.icon(
        onPressed: onPreguntar,
        style: TextButton.styleFrom(
          foregroundColor: context.colors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('¿Tienes una duda? Pregúntale al vendedor'),
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
            cantidad == 1 ? '1 sin responder' : '$cantidad sin responder',
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
Future<String?> mostrarModalPregunta(
  BuildContext context, {
  String titulo = 'Hacer una pregunta',
  String etiqueta = 'Escribe tu pregunta',
  String textoBoton = 'Enviar pregunta',
  String? valorInicial,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (contextoHoja) => _HojaTexto(
      titulo: titulo,
      etiqueta: etiqueta,
      textoBoton: textoBoton,
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
  late final TextEditingController _controller =
      TextEditingController(text: widget.valorInicial);

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
