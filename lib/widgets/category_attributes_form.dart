import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../constants/atributos_categoria.dart';

/// Formulario de las preguntas dinámicas de una categoría.
///
/// Es un widget **controlado**: no guarda las respuestas, las recibe en
/// [respuestas] y avisa cada cambio por [onChanged]. Lo único que administra
/// por su cuenta son los [TextEditingController] de los campos de texto, que
/// no pueden vivir en el padre porque el juego de campos cambia con la
/// categoría.
///
/// Diseño: sin caja alrededor ni bordes por pregunta. Cada pregunta se separa
/// por aire, no por líneas, y los controles (chips y el segmentado Sí/No)
/// cargan todo el peso visual. Un formulario de hasta doce preguntas
/// encajonadas se lee como un trámite; suelto se lee como una conversación.
class CategoryAttributesForm extends StatefulWidget {
  const CategoryAttributesForm({
    super.key,
    required this.categoryId,
    required this.respuestas,
    required this.onChanged,
    this.faltantes = const {},
  });

  /// Categoría seleccionada. Al cambiar, el formulario se rearma entero.
  final String categoryId;

  /// Respuestas actuales, con la key de la pregunta como llave.
  final Map<String, dynamic> respuestas;

  /// Se llama con el mapa YA depurado (sin campos condicionales huérfanos ni
  /// respuestas de otra categoría), listo para mandarse al servidor tal cual.
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Keys de preguntas obligatorias que quedaron sin responder al intentar
  /// publicar. Se pintan en rojo. Hoy siempre llega vacío — ninguna pregunta
  /// del catálogo es obligatoria— pero el camino está completo para poder
  /// activarlas desde la config sin tocar la UI.
  final Set<String> faltantes;

  @override
  State<CategoryAttributesForm> createState() => _CategoryAttributesFormState();
}

class _CategoryAttributesFormState extends State<CategoryAttributesForm> {
  /// Un controller por pregunta de texto, creados bajo demanda.
  ///
  /// El controller es la fuente de verdad de lo que se ve escrito, y el mapa
  /// de respuestas del padre es la de lo que se va a enviar. Mantenerlos
  /// iguales es responsabilidad de esta clase: ver [_actualizar], que limpia
  /// el controller de toda respuesta que la depuración haya descartado.
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _sincronizarControllers();
  }

  @override
  void didUpdateWidget(CategoryAttributesForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo al cambiar de categoría: durante la escritura normal el controller
    // ya es la fuente de verdad y reescribirlo movería el cursor al inicio.
    if (oldWidget.categoryId != widget.categoryId) {
      _sincronizarControllers();
    }
  }

  void _sincronizarControllers() {
    for (final pregunta in preguntasDeCategoria(widget.categoryId)) {
      if (!_esTexto(pregunta)) continue;
      final valor = widget.respuestas[pregunta.key];
      final texto = valor == null ? '' : valor.toString();
      final controller = _controllers.putIfAbsent(
        pregunta.key,
        () => TextEditingController(text: texto),
      );
      if (controller.text != texto) controller.text = texto;
    }
  }

  bool _esTexto(AtributoPregunta p) =>
      p.tipo == AtributoTipo.texto || p.tipo == AtributoTipo.numero;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Aplica un cambio y avisa al padre con el mapa ya depurado. Depurar en
  /// cada cambio (y no solo al publicar) mantiene una sola verdad: lo que el
  /// padre tiene es exactamente lo que se va a enviar.
  void _actualizar(String key, dynamic valor) {
    final siguiente = Map<String, dynamic>.from(widget.respuestas);
    if (valor == null) {
      siguiente.remove(key);
    } else {
      siguiente[key] = valor;
    }

    final depurado = depurarRespuestas(siguiente, widget.categoryId);

    // Apagar un switch descarta el campo condicional que colgaba de él, pero
    // su controller no se entera: el campo deja de pintarse con el texto
    // todavía dentro. Al reencender el switch reaparecía escrito —"6 meses"—
    // sin estar en las respuestas, y se publicaba sin esa garantía. Lo que
    // se ve y lo que se manda tienen que ser lo mismo.
    for (final entry in _controllers.entries) {
      if (!depurado.containsKey(entry.key) && entry.value.text.isNotEmpty) {
        entry.value.clear();
      }
    }

    widget.onChanged(depurado);
  }

  @override
  Widget build(BuildContext context) {
    final preguntas = preguntasDeCategoria(
      widget.categoryId,
    ).where((p) => p.aplicaCon(widget.respuestas)).toList();

    if (preguntas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 18,
              color: context.colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'attributes.product_details'.tr(),
              style: AppTypography.heading(15, color: context.colors.ink),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'attributes.optional_hint'.tr(),
          style: AppTypography.body(12.5, color: context.colors.muted),
        ),
        const SizedBox(height: 18),
        for (final pregunta in preguntas)
          Padding(
            // El aire va abajo de cada pregunta, no alrededor: así los campos
            // condicionales quedan pegados al switch del que cuelgan.
            padding: EdgeInsets.only(
              bottom: 18,
              left: pregunta.showIfKey != null ? 14 : 0,
            ),
            child: _buildPregunta(pregunta),
          ),
      ],
    );
  }

  Widget _buildPregunta(AtributoPregunta pregunta) {
    switch (pregunta.tipo) {
      case AtributoTipo.booleano:
        return _BooleanRow(
          pregunta: pregunta,
          valor: widget.respuestas[pregunta.key] as bool?,
          enFalta: widget.faltantes.contains(pregunta.key),
          onChanged: (v) => _actualizar(pregunta.key, v),
        );

      case AtributoTipo.seleccion:
        return _SelectField(
          pregunta: pregunta,
          valor: widget.respuestas[pregunta.key] as String?,
          enFalta: widget.faltantes.contains(pregunta.key),
          onChanged: (v) => _actualizar(pregunta.key, v),
        );

      case AtributoTipo.seleccionMultiple:
        final crudo = widget.respuestas[pregunta.key];
        return _MultiSelectField(
          // El único hijo con estado propio (si su campo de texto está
          // abierto). Sin key, Flutter reusaría el State por posición: abrir
          // "+ Agregar" en "¿qué incluye la renta?" y que apareciera otra
          // pregunta arriba movería el campo abierto a "¿qué requisitos
          // pides?", con lo escrito a medias adentro.
          key: ValueKey(pregunta.key),
          pregunta: pregunta,
          valores: crudo is List ? crudo.cast<String>() : const [],
          enFalta: widget.faltantes.contains(pregunta.key),
          onChanged: (v) => _actualizar(pregunta.key, v.isEmpty ? null : v),
        );

      case AtributoTipo.texto:
      case AtributoTipo.numero:
        return _TextoField(
          pregunta: pregunta,
          controller: _controllers.putIfAbsent(
            pregunta.key,
            TextEditingController.new,
          ),
          enFalta: widget.faltantes.contains(pregunta.key),
          onChanged: (v) => _actualizar(pregunta.key, v.isEmpty ? null : v),
        );
    }
  }
}

/// Etiqueta de una pregunta. El asterisco solo aparece en las obligatorias.
class _EtiquetaPregunta extends StatelessWidget {
  const _EtiquetaPregunta({required this.pregunta, required this.enFalta});

  final AtributoPregunta pregunta;
  final bool enFalta;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: traducirCatalogo(pregunta.label),
        children: [
          if (pregunta.obligatoria)
            TextSpan(
              text: ' *',
              style: TextStyle(color: context.colors.danger),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: enFalta ? context.colors.danger : context.colors.ink,
      ),
    );
  }
}

/// Pregunta de sí/no: etiqueta a la izquierda, segmentado compacto a la
/// derecha. Tres estados, no dos — volver a tocar la opción elegida la
/// deselecciona y la pregunta queda sin responder.
///
/// Un `Switch` no serviría: solo distingue encendido de apagado, y aquí "no
/// contesté" tiene que verse distinto de "dije que no". Con un switch, todas
/// las preguntas nacerían respondidas con un "no" que nadie eligió.
class _BooleanRow extends StatelessWidget {
  const _BooleanRow({
    required this.pregunta,
    required this.valor,
    required this.enFalta,
    required this.onChanged,
  });

  final AtributoPregunta pregunta;
  final bool? valor;
  final bool enFalta;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _EtiquetaPregunta(pregunta: pregunta, enFalta: enFalta),
        ),
        const SizedBox(width: 12),
        _OpcionSiNo(
          texto: 'common.yes'.tr(),
          activo: valor == true,
          onTap: () => onChanged(valor == true ? null : true),
        ),
        const SizedBox(width: 6),
        _OpcionSiNo(
          texto: 'No',
          activo: valor == false,
          onTap: () => onChanged(valor == false ? null : false),
        ),
      ],
    );
  }
}

class _OpcionSiNo extends StatelessWidget {
  const _OpcionSiNo({
    required this.texto,
    required this.activo,
    required this.onTap,
  });

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: activo
              ? primary.withValues(alpha: 0.12)
              : context.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: activo ? primary : context.colors.muted,
          ),
        ),
      ),
    );
  }
}

/// Pregunta de una sola opción: etiqueta arriba y chips debajo. Chips y no un
/// `DropdownButton` porque los catálogos son de dos a cuatro opciones cortas:
/// caben a la vista y elegir cuesta un toque en vez de tres.
class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.pregunta,
    required this.valor,
    required this.enFalta,
    required this.onChanged,
  });

  final AtributoPregunta pregunta;
  final String? valor;
  final bool enFalta;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EtiquetaPregunta(pregunta: pregunta, enFalta: enFalta),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final opcion in pregunta.options)
              _Chip(
                // Se traduce solo lo que se ve: `opcion` sigue siendo el
                // valor en español que se guarda y se manda al servidor.
                texto: traducirCatalogo(opcion),
                activo: valor == opcion,
                // Volver a tocar la opción elegida la deselecciona: sin eso,
                // una pregunta opcional se vuelve irreversible en cuanto se
                // toca por accidente.
                onTap: () => onChanged(valor == opcion ? null : opcion),
              ),
          ],
        ),
      ],
    );
  }
}

/// Pregunta de varias opciones (qué incluye la renta, qué requisitos pides).
///
/// Cuando la pregunta trae `permiteCustom`, después de los chips del catálogo
/// va uno de "+ Agregar" que se convierte en un campo de texto: lo que el
/// usuario escriba entra a la MISMA lista que los predefinidos, sin marca que
/// los distinga. El detalle del producto pinta ambos igual y el servidor los
/// guarda en el mismo campo — un chip propio no es un dato de otra clase, es
/// una opción que al catálogo le faltaba.
class _MultiSelectField extends StatefulWidget {
  const _MultiSelectField({
    super.key,
    required this.pregunta,
    required this.valores,
    required this.enFalta,
    required this.onChanged,
  });

  final AtributoPregunta pregunta;
  final List<String> valores;
  final bool enFalta;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_MultiSelectField> createState() => _MultiSelectFieldState();
}

class _MultiSelectFieldState extends State<_MultiSelectField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// El chip "+ Agregar" está abierto como campo de texto.
  bool _escribiendo = false;

  @override
  void initState() {
    super.initState();
    // El borde de foco se pinta a mano (el campo no es un TextField con
    // decoración del tema), así que hay que repintar al entrar y salir.
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Los valores que no salieron del catálogo: los escribió el usuario.
  List<String> get _propios => widget.valores
      .where((v) => !widget.pregunta.options.contains(v))
      .toList();

  /// Emite la lista ordenada como la guarda el servidor: primero las opciones
  /// del catálogo en el orden de la config —para que dos publicaciones con lo
  /// mismo incluido se lean igual—, después las propias en el orden en que se
  /// escribieron, que ahí es el único orden que significa algo.
  void _emitir(List<String> valores) {
    final opciones = widget.pregunta.options;
    widget.onChanged([
      ...opciones.where(valores.contains),
      ...valores.where((v) => !opciones.contains(v)),
    ]);
  }

  void _alternar(String valor) {
    _emitir(
      widget.valores.contains(valor)
          ? widget.valores.where((v) => v != valor).toList()
          : [...widget.valores, valor],
    );
  }

  void _abrirInput() {
    setState(() => _escribiendo = true);
    // El foco se pide después del frame: el campo todavía no existe en el
    // árbol cuando se llama a setState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _cerrarInput() {
    _controller.clear();
    if (mounted) setState(() => _escribiendo = false);
  }

  /// Convierte lo escrito en un chip y deja el campo listo para el siguiente.
  ///
  /// Un texto vacío o repetido simplemente cierra el campo: son errores del
  /// dedo, no algo que valga una alerta.
  void _confirmar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return _cerrarInput();

    bool igual(String otro) => otro.toLowerCase() == texto.toLowerCase();

    // Escribir "luz" cuando "Luz" es un chip del catálogo no crea un chip
    // propio casi idéntico al de al lado: enciende el que ya existe. Quien
    // escribe no está pensando en cuáles opciones venían y cuáles no.
    final delCatalogo = widget.pregunta.options.where(igual).firstOrNull;
    if (delCatalogo != null) {
      if (!widget.valores.contains(delCatalogo)) _alternar(delCatalogo);
      return _cerrarInput();
    }

    // El tope también se respeta aquí y no solo escondiendo el chip de
    // "+ Agregar": al editar una publicación los valores llegan de fuera y
    // podrían venir ya en el límite.
    final repetido = widget.valores.any(igual);
    if (!repetido && _propios.length < maxOpcionesCustom) {
      _emitir([...widget.valores, texto]);
    }
    _cerrarInput();
  }

  @override
  Widget build(BuildContext context) {
    final propios = _propios;
    final cabenMas = propios.length < maxOpcionesCustom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EtiquetaPregunta(pregunta: widget.pregunta, enFalta: widget.enFalta),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final opcion in widget.pregunta.options)
              _Chip(
                texto: traducirCatalogo(opcion),
                activo: widget.valores.contains(opcion),
                onTap: () => _alternar(opcion),
              ),
            // Los propios van siempre seleccionados —existen porque el usuario
            // los escribió— así que su toque no alterna: los quita.
            for (final propio in propios)
              _Chip(
                texto: propio,
                activo: true,
                quitable: true,
                onTap: () => _alternar(propio),
              ),
            if (widget.pregunta.permiteCustom)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.94,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _escribiendo
                    ? _CustomChipInput(
                        key: const ValueKey('input'),
                        controller: _controller,
                        focus: _focus,
                        onConfirmar: _confirmar,
                      )
                    : cabenMas
                    ? _ChipAgregar(
                        key: const ValueKey('agregar'),
                        onTap: _abrirInput,
                      )
                    // Con el tope alcanzado no queda ni el hueco: un chip
                    // deshabilitado solo invita a tocarlo para nada.
                    : const SizedBox.shrink(key: ValueKey('tope')),
              ),
          ],
        ),
      ],
    );
  }
}

/// Chip que abre el campo de texto. Va en outline y no relleno: los rellenos
/// de esta fila significan "elegido", y este no es una opción sino una acción.
/// El "+" toma el gris del texto secundario para no competir con los chips
/// activos, que son lo que hay que poder contar de un vistazo.
class _ChipAgregar extends StatelessWidget {
  const _ChipAgregar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 15, color: context.colors.muted),
            const SizedBox(width: 4),
            Text(
              'Agregar',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El chip "+ Agregar" abierto: un campo del mismo alto y con el mismo radio,
/// para que la fila no salte al abrirlo. El borde se tiñe del acento mientras
/// tiene el foco —un halo de 2px, no una sombra dura— y el botón de confirmar
/// vive dentro del chip: en un teclado móvil el "enter" no siempre está a la
/// vista, y sin él no habría forma obvia de cerrar lo escrito.
class _CustomChipInput extends StatelessWidget {
  const _CustomChipInput({
    super.key,
    required this.controller,
    required this.focus,
    required this.onConfirmar,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    final enfocado = focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: 190,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: enfocado ? accent : context.colors.border),
        boxShadow: enfocado
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 3,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              // El tope se aplica al escribir y no al confirmar: enterarse de
              // que sobran letras justo cuando el chip ya no aparece es peor
              // que no poder teclear la vigésimo primera.
              maxLength: maxLargoOpcionCustom,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.colors.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: 'attributes.type_and_enter'.tr(),
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  color: context.colors.muted,
                ),
              ),
              onSubmitted: (_) => onConfirmar(),
              // Tocar fuera cierra el campo, y lo que ya estaba escrito se
              // vuelve chip en vez de perderse: quien escribió "Wifi 300mb" y
              // se distrajo tocando otra pregunta no quiso descartarlo.
              onTapOutside: (_) => onConfirmar(),
            ),
          ),
          IconButton(
            onPressed: onConfirmar,
            icon: const Icon(Icons.check_rounded, size: 16),
            color: context.colors.accent,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Agregar',
          ),
        ],
      ),
    );
  }
}

/// Chip de opción. Sin borde cuando está apagado — el relleno tenue basta
/// para leerlo como tocable, y ocho chips con borde en una misma pantalla se
/// vuelven una reja.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.texto,
    required this.activo,
    required this.onTap,
    this.quitable = false,
  });

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  /// Solo los chips escritos por el usuario: llevan una ✕ a la vista —y no
  /// escondida tras una pulsación larga— porque un chip con un texto que solo
  /// existe aquí no se lee como algo que se pueda apagar tocándolo. La ✕ es
  /// lo que dice que se puede deshacer; quien lo hace sigue siendo [onTap].
  final bool quitable;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: activo
              ? primary.withValues(alpha: 0.12)
              : context.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La palomita y la ✕ dirían lo mismo dos veces: un chip propio
            // solo existe si está elegido.
            if (activo && !quitable) ...[
              Icon(Icons.check_rounded, size: 14, color: primary),
              const SizedBox(width: 5),
            ],
            Text(
              texto,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                color: activo ? primary : context.colors.ink,
              ),
            ),
            if (quitable) ...[
              const SizedBox(width: 5),
              // La ✕ no tiene gesto propio: el blanco es el chip entero, que
              // ya quita el valor al tocarlo. Un ícono de 14 px con su propio
              // onTap sería un objetivo del tamaño de una uña, y agrandarlo
              // con padding estiraría el chip a lo alto.
              Icon(Icons.close_rounded, size: 14, color: primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Campo de texto libre (o numérico). Usa el mismo `InputDecoration` del tema
/// que el resto del formulario de publicar, así que no necesita estilo propio.
class _TextoField extends StatelessWidget {
  const _TextoField({
    required this.pregunta,
    required this.controller,
    required this.enFalta,
    required this.onChanged,
  });

  final AtributoPregunta pregunta;
  final TextEditingController controller;
  final bool enFalta;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: pregunta.tipo == AtributoTipo.numero
          ? TextInputType.number
          : TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: pregunta.obligatoria
            ? '${traducirCatalogo(pregunta.label)} *'
            : traducirCatalogo(pregunta.label),
        hintText: pregunta.placeholder == null
            ? null
            : traducirCatalogo(pregunta.placeholder!),
        errorText: enFalta ? 'attributes.missing_answer'.tr() : null,
      ),
      onChanged: (v) => onChanged(v.trim()),
    );
  }
}
