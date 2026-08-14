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
              'Detalles del producto',
              style: AppTypography.heading(15, color: context.colors.ink),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Todo es opcional, pero responderlo evita la mitad de las preguntas por chat.',
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
        text: pregunta.label,
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
        Expanded(child: _EtiquetaPregunta(pregunta: pregunta, enFalta: enFalta)),
        const SizedBox(width: 12),
        _OpcionSiNo(
          texto: 'Sí',
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
                texto: opcion,
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
class _MultiSelectField extends StatelessWidget {
  const _MultiSelectField({
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
                texto: opcion,
                activo: valores.contains(opcion),
                onTap: () {
                  // Se reconstruye desde `options` en vez de agregar al final,
                  // para que el orden guardado no dependa del orden en que el
                  // usuario fue tocando.
                  final elegidos = valores.contains(opcion)
                      ? valores.where((v) => v != opcion).toSet()
                      : {...valores, opcion};
                  onChanged(
                    pregunta.options.where(elegidos.contains).toList(),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Chip de opción. Sin borde cuando está apagado — el relleno tenue basta
/// para leerlo como tocable, y ocho chips con borde en una misma pantalla se
/// vuelven una reja.
class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.activo, required this.onTap});

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
            if (activo) ...[
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
        labelText: pregunta.obligatoria ? '${pregunta.label} *' : pregunta.label,
        hintText: pregunta.placeholder,
        errorText: enFalta ? 'Falta responder' : null,
      ),
      onChanged: (v) => onChanged(v.trim()),
    );
  }
}
