import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../app_theme.dart';

/// Envoltura de shimmer con los colores de tema de la app (no grises
/// hardcodeados), para que el efecto se sienta integrado en claro y oscuro.
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.colors.surfaceMuted,
      highlightColor: context.colors.border,
      child: child,
    );
  }
}

/// Bloque base de un skeleton: un rectángulo (o círculo) del color de
/// superficie muted, listo para envolverse en un [AppShimmer] junto con
/// otros bloques hermanos.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 6,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(borderRadius)
            : null,
      ),
    );
  }
}

/// Skeleton genérico para pantallas cuyo contenido final es una lista de
/// tarjetas (chats, favoritos, publicaciones, planes y contactos).
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({
    super.key,
    this.itemCount = 5,
    this.showLeading = true,
    this.padding = const EdgeInsets.fromLTRB(18, 12, 18, 24),
  });

  final int itemCount;
  final bool showLeading;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              if (showLeading) ...[
                const ShimmerBox(width: 48, height: 48, borderRadius: 12),
                const SizedBox(width: 12),
              ],
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 154, height: 14, borderRadius: 4),
                    SizedBox(height: 8),
                    ShimmerBox(height: 12, borderRadius: 4),
                    SizedBox(height: 6),
                    FractionallySizedBox(
                      widthFactor: 0.58,
                      child: ShimmerBox(height: 11, borderRadius: 4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Versión no desplazable para insertar resultados skeleton dentro de otro
/// scroll ya existente, como la búsqueda y las secciones paginadas.
class AppInlineListSkeleton extends StatelessWidget {
  const AppInlineListSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            Container(
              height: 104,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.colors.border),
              ),
              child: const Row(
                children: [
                  ShimmerBox(width: 92, height: 84, borderRadius: 10),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(height: 14, borderRadius: 4),
                        SizedBox(height: 8),
                        ShimmerBox(width: 150, height: 12, borderRadius: 4),
                        Spacer(),
                        ShimmerBox(width: 90, height: 13, borderRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i < itemCount - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Skeleton de pantallas de detalle o formulario que todavía están cargando
/// su configuración remota.
class AppFormSkeleton extends StatelessWidget {
  const AppFormSkeleton({super.key, this.sectionCount = 3});

  final int sectionCount;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        itemCount: sectionCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 172, height: 15, borderRadius: 4),
              const SizedBox(height: 12),
              const ShimmerBox(height: 48, borderRadius: 10),
              if (index.isEven) ...[
                const SizedBox(height: 10),
                const ShimmerBox(height: 48, borderRadius: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Burbujas de conversación mientras se recupera el historial.
class AppChatSkeleton extends StatelessWidget {
  const AppChatSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        children: const [
          Align(
            alignment: Alignment.centerLeft,
            child: ShimmerBox(width: 230, height: 62, borderRadius: 16),
          ),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ShimmerBox(width: 184, height: 52, borderRadius: 16),
          ),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ShimmerBox(width: 264, height: 78, borderRadius: 16),
          ),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ShimmerBox(width: 214, height: 58, borderRadius: 16),
          ),
        ],
      ),
    );
  }
}
