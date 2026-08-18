import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/verification_requirement.dart';

/// Checklist de lo que falta para verificar la cuenta, con ✓/✗ por requisito.
///
/// Se pinta ANTES del botón de verificar, no después de fallar. Intentar y
/// fallar enseña un requisito por intento: con la lista delante, la persona
/// ve de un vistazo todo lo que le falta y en qué orden resolverlo.
///
/// Los requisitos los evalúa el backend y aquí solo se dibujan — ver
/// [VerificationRequirement] para por qué la app no reimplementa la regla.
class VerificationChecklist extends StatelessWidget {
  const VerificationChecklist({
    super.key,
    required this.requisitos,
    required this.onAccion,
  });

  final List<VerificationRequirement> requisitos;

  /// Lleva a resolver un requisito concreto: recibe su `accion`
  /// ('editar_perfil', 'conectar_mercadopago', 'revisar_productos').
  final void Function(VerificationRequirement requisito) onAccion;

  @override
  Widget build(BuildContext context) {
    if (requisitos.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final faltan = requisitos.where((r) => !r.cumplido).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                faltan == 0
                    ? Icons.verified_rounded
                    : Icons.checklist_rtl_rounded,
                size: 18,
                color: faltan == 0 ? AppColors.success : colors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  faltan == 0
                      ? 'checklist.ready'.tr()
                      : 'checklist.missing'.plural(faltan),
                  style: AppTypography.heading(14.5, color: colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final requisito in requisitos)
            _FilaRequisito(requisito: requisito, onAccion: onAccion),
        ],
      ),
    );
  }
}

class _FilaRequisito extends StatelessWidget {
  const _FilaRequisito({required this.requisito, required this.onAccion});

  final VerificationRequirement requisito;
  final void Function(VerificationRequirement) onAccion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ok = requisito.cumplido;
    final color = ok ? AppColors.success : AppColors.danger;

    return InkWell(
      // Un requisito cumplido no lleva a ninguna parte: no hay nada que
      // arreglar, y dejarlo tocable invita a tocarlo para nada.
      onTap: ok ? null : () => onAccion(requisito),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    requisito.titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: colors.ink,
                    ),
                  ),
                  // El detalle solo cuando falta: en un requisito cumplido es
                  // ruido que alarga la lista y esconde lo que sí importa.
                  if (!ok) ...[
                    const SizedBox(height: 3),
                    Text(
                      requisito.detalle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!ok) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 18, color: colors.muted),
            ],
          ],
        ),
      ),
    );
  }
}
