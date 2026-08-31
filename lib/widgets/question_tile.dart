import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../utils/tiempo_relativo.dart';
import 'app_shimmer.dart';
import 'badges.dart';

/// Sangría del bloque de respuesta respecto a la pregunta. Es lo único que
/// marca la jerarquía: ni caja, ni borde, ni fondo de color — el turno de
/// quién habla se lee por la posición y el peso tipográfico.
const double _kSangriaRespuesta = 16;

/// Una pregunta con su respuesta, si ya la tiene.
///
/// Pregunta y respuesta se distinguen por tipografía y sangría, no por
/// tarjetas: quien pregunta va en texto normal con su nombre encima; el
/// vendedor responde indentado, en un tono más apagado y con su etiqueta.
/// Es el mismo tratamiento en el preview del detalle y en la pantalla
/// completa, para que no parezcan dos cosas distintas.
class QuestionTile extends StatelessWidget {
  const QuestionTile({
    super.key,
    required this.question,
    this.sellerName,
    this.destacada = false,
    this.respuestaInline,
  });

  final ProductQuestion question;

  /// Nombre del vendedor, para firmar la respuesta ("Respuesta de Ana").
  /// Null cae a un genérico: es útil pero no imprescindible.
  final String? sellerName;

  /// Resalte temporal al llegar desde una notificación. El color lo pone
  /// quien envuelve; aquí solo cambia el fondo del bloque.
  final bool destacada;

  /// Input de respuesta del dueño, cuando aplica. Va como widget y no como
  /// callback para que esta pieza no sepa nada de estado ni de red.
  final Widget? respuestaInline;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.slow,
      curve: AppAnimations.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: destacada ? context.colors.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LineaPregunta(question: question),
          const SizedBox(height: 6),
          Text(
            question.questionText,
            style: AppTypography.body(14.5, color: context.colors.ink),
          ),
          if (question.isAnswered) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: _kSangriaRespuesta),
              child: _BloqueRespuesta(
                question: question,
                sellerName: sellerName,
              ),
            ),
          ] else if (respuestaInline == null) ...[
            const SizedBox(height: 8),
            const _BadgePendiente(),
          ],
          if (respuestaInline != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: _kSangriaRespuesta),
              child: respuestaInline!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Nombre de quien preguntó, su insignia si la tiene, y cuándo.
class _LineaPregunta extends StatelessWidget {
  const _LineaPregunta({required this.question});

  final ProductQuestion question;

  @override
  Widget build(BuildContext context) {
    final autor = question.author;
    return Row(
      children: [
        Flexible(
          child: Text(
            autor.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.heading(14, color: context.colors.ink),
          ),
        ),
        if (autor.verified || autor.socioFundador) ...[
          const SizedBox(width: 5),
          InsigniaCuenta.deSeller(autor, size: 14),
        ],
        const SizedBox(width: 8),
        Text(
          tiempoRelativo(question.createdAt),
          style: TextStyle(fontSize: 12, color: context.colors.muted),
        ),
      ],
    );
  }
}

class _BloqueRespuesta extends StatelessWidget {
  const _BloqueRespuesta({required this.question, this.sellerName});

  final ProductQuestion question;
  final String? sellerName;

  @override
  Widget build(BuildContext context) {
    final fecha = question.answeredAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 13,
              color: context.colors.accent,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                sellerName == null
                    ? 'questions.seller_answer'.tr()
                    : 'questions.answer_from'.tr(
                        namedArgs: {'seller': sellerName!},
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label(
                  12.5,
                  weight: FontWeight.w600,
                  color: context.colors.accent,
                ),
              ),
            ),
            if (fecha != null) ...[
              const SizedBox(width: 8),
              Text(
                tiempoRelativo(fecha),
                style: TextStyle(fontSize: 11.5, color: context.colors.muted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          question.answerText!,
          style: AppTypography.body(14, color: context.colors.muted),
        ),
      ],
    );
  }
}

/// Estado pendiente. Discreto a propósito: informa de que nadie ha
/// contestado todavía sin gritar que el vendedor no atiende.
class _BadgePendiente extends StatelessWidget {
  const _BadgePendiente();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _kSangriaRespuesta),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 13,
            color: context.colors.muted.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 5),
          Text(
            'questions.pending'.tr(),
            style: TextStyle(fontSize: 12, color: context.colors.muted),
          ),
        ],
      ),
    );
  }
}

/// Esqueleto con la misma métrica que [QuestionTile]: dos líneas de texto
/// bajo una de encabezado, para que la lista no salte al cargar.
class QuestionTileSkeleton extends StatelessWidget {
  const QuestionTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(width: 120, height: 14, borderRadius: 4),
            const SizedBox(height: 10),
            const ShimmerBox(height: 13, borderRadius: 4),
            const SizedBox(height: 5),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.6,
              child: const ShimmerBox(height: 13, borderRadius: 4),
            ),
          ],
        ),
      ),
    );
  }
}
