import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'app_shimmer.dart';

/// Estado de carga compartido por los formularios de producto y búsqueda.
/// Replica su composición real para que la transición al contenido no salte.
class PublishFormSkeleton extends StatelessWidget {
  const PublishFormSkeleton({
    super.key,
    required this.showPhotos,
    required this.showTypeSelector,
  });

  final bool showPhotos;
  final bool showTypeSelector;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showPhotos) ...[
                    const _SkeletonSection(
                      child: Row(
                        children: [
                          ShimmerBox(width: 88, height: 88, borderRadius: 12),
                          SizedBox(width: 10),
                          ShimmerBox(width: 88, height: 88, borderRadius: 12),
                          SizedBox(width: 10),
                          ShimmerBox(width: 88, height: 88, borderRadius: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showTypeSelector) ...[
                    const _SkeletonSection(
                      child: Row(
                        children: [
                          Expanded(
                            child: ShimmerBox(height: 44, borderRadius: 12),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: ShimmerBox(height: 44, borderRadius: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const _SkeletonSection(
                    child: Column(
                      children: [
                        ShimmerBox(height: 52, borderRadius: 10),
                        SizedBox(height: 10),
                        ShimmerBox(height: 52, borderRadius: 10),
                        SizedBox(height: 10),
                        ShimmerBox(height: 76, borderRadius: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SkeletonSection(
                    child: Row(
                      children: [
                        Expanded(
                          child: ShimmerBox(height: 52, borderRadius: 10),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ShimmerBox(height: 52, borderRadius: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SkeletonSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 210, height: 13, borderRadius: 4),
                        SizedBox(height: 12),
                        ShimmerBox(height: 42, borderRadius: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              ShimmerBox(width: 34, height: 34, borderRadius: 10),
              SizedBox(width: 10),
              Expanded(child: ShimmerBox(height: 14, borderRadius: 4)),
              SizedBox(width: 72),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
