import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../constants/atributos_categoria.dart';
import '../models.dart';

/// "Detalles adicionales" del detalle de producto: las respuestas que el
/// vendedor dio a las preguntas dinámicas de su categoría.
///
/// Se pinta como una lista de renglones —etiqueta a la izquierda, respuesta a
/// la derecha— y no como tarjetas: es información de referencia que se lee en
/// diagonal buscando un dato concreto, y una columna de valores alineados se
/// escanea de un vistazo. Sin líneas divisorias entre renglones; el aire y la
/// alineación bastan para separarlos.
///
/// Las preguntas sin responder NO aparecen. Todas son opcionales, así que un
/// producto típico contesta cuatro de doce: pintar los huecos como "—" haría
/// que la sección se leyera como un formulario abandonado en vez de como los
/// datos que sí hay.
class ProductAttributesSection extends StatelessWidget {
  const ProductAttributesSection({super.key, required this.product});

  final Product product;

  /// Las respuestas en el orden del catálogo (no en el orden en que llegaron
  /// del servidor), para que dos productos de la misma categoría se lean
  /// igual. Una respuesta cuya pregunta esta versión de la app no conoce se
  /// omite: llegó de un cliente más nuevo y no hay etiqueta con qué pintarla.
  List<(AtributoPregunta, Object)> _respuestas() {
    final respuestas = <(AtributoPregunta, Object)>[];
    for (final pregunta in preguntasDeCategoria(product.category.id)) {
      // El servidor ya descarta los condicionales huérfanos, pero un producto
      // guardado por una versión anterior podría traerlos; sin esto se vería
      // "la garantía dura 6 meses" en algo que dice no tener garantía.
      if (!pregunta.aplicaCon(product.atributos)) continue;

      final valor = product.atributos[pregunta.key];
      if (valor == null) continue;
      if (valor is String && valor.trim().isEmpty) continue;
      if (valor is List && valor.isEmpty) continue;

      respuestas.add((pregunta, valor as Object));
    }
    return respuestas;
  }

  @override
  Widget build(BuildContext context) {
    final respuestas = _respuestas();
    // Vacío incluye el caso de un producto cuyas únicas respuestas son de
    // preguntas que esta versión de la app no conoce: `atributos` no está
    // vacío pero no hay nada que pintar. Por eso el aire de arriba vive
    // AQUÍ y no en quien llama — desde fuera no se puede saber si la
    // sección va a dibujar algo, y un SizedBox previo dejaría un hueco.
    if (respuestas.isEmpty) return const SizedBox.shrink();

    final chips = _chipsResumen(product.atributos);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 18,
              color: context.colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Detalles adicionales',
              style: AppTypography.heading(15, color: context.colors.ink),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ChipsResumen(chips: chips),
        ],
        const SizedBox(height: 12),
        _AcordeonDetalles(respuestas: respuestas),
      ],
    );
  }

  /// Hasta 3 chips con los datos que más ayudan a decidir de un vistazo,
  /// sin tener que abrir la tabla completa. A diferencia de [_FilaAtributo]
  /// (que detecta bool-vs-texto por el TIPO del dato, sin conocer el
  /// nombre del campo), aquí el criterio es semántico —"¿esto es la
  /// condición del producto?"— y eso no se puede leer del tipo, así que
  /// estas 4 keys sí van hardcodeadas a propósito.
  static List<_ChipDato> _chipsResumen(Map<String, dynamic> atributos) {
    final chips = <_ChipDato>[];

    for (final key in [
      'estado_electronico',
      'estado_ropa',
      'estado_libro',
      'estado_general',
    ]) {
      final valor = atributos[key];
      if (valor is String && valor.trim().isNotEmpty) {
        chips.add(_ChipDato(icon: Icons.grade_outlined, texto: valor));
        break;
      }
    }

    final tieneGarantia =
        atributos['tiene_garantia'] == true ||
        atributos['garantia_vigente'] == true;
    if (tieneGarantia) {
      final duracion = atributos['duracion_garantia'];
      final texto = (duracion is String && duracion.trim().isNotEmpty)
          ? '$duracion de garantía'
          : 'Con garantía';
      chips.add(_ChipDato(icon: Icons.verified_outlined, texto: texto));
    }

    final tiempoUso = atributos['tiempo_uso'];
    if (tiempoUso is String && tiempoUso.trim().isNotEmpty) {
      chips.add(
        _ChipDato(icon: Icons.schedule_outlined, texto: '$tiempoUso de uso'),
      );
    }

    return chips.take(3).toList();
  }
}

class _ChipDato {
  const _ChipDato({required this.icon, required this.texto});

  final IconData icon;
  final String texto;
}

/// Fila horizontal de chips con scroll si no entran, en vez de wrap: el
/// wrap partiría la fila en dos renglones y competiría con el aire que ya
/// deja el título arriba.
class _ChipsResumen extends StatelessWidget {
  const _ChipsResumen({required this.chips});

  final List<_ChipDato> chips;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, chip) in chips.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: context.colors.accentTint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chip.icon, size: 13, color: context.colors.ink),
                  const SizedBox(width: 5),
                  Text(
                    chip.texto,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón "Ver todos los detalles" que expande, con animación propia (no
/// `ExpansionTile` de Material — su barra divisoria y su padding no calzan
/// con el resto de la pantalla), un panel de una sola card con la tabla
/// completa. Colapsado por defecto: el vistazo ya lo dan los chips de
/// arriba, esto es para quien quiere el detalle completo.
class _AcordeonDetalles extends StatefulWidget {
  const _AcordeonDetalles({required this.respuestas});

  final List<(AtributoPregunta, Object)> respuestas;

  @override
  State<_AcordeonDetalles> createState() => _AcordeonDetallesState();
}

class _AcordeonDetallesState extends State<_AcordeonDetalles> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expandido = !_expandido),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ver todos los detalles',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.accent,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expandido ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: context.colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: !_expandido
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.colors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (final (i, entrada) in widget.respuestas.indexed) ...[
                          if (i > 0)
                            Container(
                              height: 1,
                              color: context.colors.border,
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: _FilaAtributo(
                              pregunta: entrada.$1,
                              valor: entrada.$2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _FilaAtributo extends StatelessWidget {
  const _FilaAtributo({required this.pregunta, required this.valor});

  final AtributoPregunta pregunta;
  final Object valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // La etiqueta cede espacio antes que el valor: una pregunta larga
        // puede partirse en dos renglones, pero "Nuevo con etiqueta" cortado
        // a la mitad no se entiende.
        Flexible(
          flex: 5,
          child: Text(
            _etiquetaCorta(pregunta.label),
            style: AppTypography.body(13.5, color: context.colors.muted),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(flex: 6, child: _valorWidget(context)),
      ],
    );
  }

  Widget _valorWidget(BuildContext context) {
    if (valor is bool) {
      return Align(
        alignment: Alignment.centerRight,
        // Aquí siempre "Sí"/"No", nunca el `badgeLabel`: la etiqueta de la
        // pregunta está a la izquierda en el mismo renglón, así que un
        // "Opción veggie" al lado de "Tienes opciones vegetarianas/veganas"
        // solo repetiría. El badgeLabel es para la tarjeta del listado, que
        // no tiene dónde poner la pregunta.
        child: _BadgeBooleano(activo: valor as bool),
      );
    }

    if (valor is List) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in valor as List) _ChipValor(texto: item.toString()),
        ],
      );
    }

    return Text(
      valor.toString(),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: context.colors.ink,
      ),
    );
  }

  /// Las etiquetas del catálogo están redactadas para el formulario, donde se
  /// le pregunta al vendedor ("¿Aceptas devoluciones/reembolsos?"). En el
  /// detalle el lector es el comprador y una columna de doce interrogaciones
  /// se lee como un interrogatorio, así que se quitan los signos y la
  /// mayúscula inicial se conserva.
  static String _etiquetaCorta(String label) {
    return label.replaceAll('¿', '').replaceAll('?', '');
  }
}

/// Respuesta de sí/no. El "sí" se tiñe de verde con palomita porque casi
/// siempre es la respuesta que suma (acepta devoluciones, incluye accesorios);
/// el "no" queda en gris neutro, informativo y sin dramatismo — no aceptar
/// devoluciones es una condición de venta, no un defecto.
class _BadgeBooleano extends StatelessWidget {
  const _BadgeBooleano({required this.activo});

  final bool activo;

  @override
  Widget build(BuildContext context) {
    final color = activo ? context.colors.success : context.colors.muted;
    final texto = activo ? 'Sí' : 'No';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: activo
            ? context.colors.successBg
            : context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            activo ? Icons.check_rounded : Icons.remove_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cada valor de una respuesta de selección múltiple (qué incluye la renta,
/// qué requisitos pide).
class _ChipValor extends StatelessWidget {
  const _ChipValor({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.colors.ink,
        ),
      ),
    );
  }
}
