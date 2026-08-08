import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../utils/tiempo_relativo.dart';
import 'app_shimmer.dart';
import 'badges.dart';
import 'user_role.dart';

/// Diámetro del avatar. Fijo y compartido con [CommentSkeleton] y con la
/// sangría de los separadores, para que el esqueleto y el contenido real
/// ocupen exactamente el mismo alto y la lista no salte al cargar.
const double _kAvatarSize = 36;

/// Espacio entre el avatar y el texto. Sumado a [_kAvatarSize] da la sangría
/// del separador, que arranca alineado con el nombre y no con el avatar.
const double _kAvatarGap = 12;

/// Sangría izquierda de los separadores entre comentarios.
const double kCommentDividerIndent = _kAvatarSize + _kAvatarGap + 4;

/// Avatar circular con iniciales, o el logo si la cuenta es un negocio que
/// subió uno. Mismo tratamiento que el perfil: fondo del color de marca al
/// 12% e iniciales en el color de acento.
class CommentAvatar extends StatelessWidget {
  const CommentAvatar({super.key, required this.author, this.size = _kAvatarSize});

  final Seller author;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iniciales = Text(
      author.avatarInitials.isEmpty ? '??' : author.avatarInitials,
      style: TextStyle(
        fontSize: size * 0.35,
        fontWeight: FontWeight.w700,
        color: context.colors.accent,
      ),
    );

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: author.logoUrl != null && author.logoUrl!.isNotEmpty
          ? ClipOval(
              child: Image.network(
                '${ApiService.baseUrl}${author.logoUrl}',
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => iniciales,
              ),
            )
          : iniciales,
    );
  }
}

/// Un comentario dentro del hilo de una publicación.
///
/// Sin tarjeta ni borde: lo que separa un comentario del siguiente es el
/// aire y un divisor de un pixel, siguiendo la línea del resto de la app.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.onDelete,
  });

  final ProductComment comment;

  /// Null cuando el usuario actual no puede borrar este comentario: sin
  /// permiso, el botón "..." ni siquiera se pinta.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final autor = comment.author;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommentAvatar(author: autor),
        const SizedBox(width: _kAvatarGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      autor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(14.5),
                    ),
                  ),
                  if (autor.verified) ...[
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: InsigniaVerificada.desdeTipo(
                        autor.tipoCuenta,
                        compact: true,
                        size: 15,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    tiempoRelativo(comment.createdAt),
                    style: TextStyle(fontSize: 12, color: context.colors.muted),
                  ),
                  if (onDelete != null)
                    _MenuComentario(onDelete: onDelete!)
                  else
                    // Reserva el ancho del botón para que el tiempo relativo
                    // quede a la misma altura en todas las filas, tenga o no
                    // menú quien las mira.
                    const SizedBox(width: 8),
                ],
              ),
              SubtituloRol(
                seller: autor,
                espacioArriba: 2,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                comment.texto,
                style: AppTypography.body(14.5, color: context.colors.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Botón "..." con la única acción que hoy existe sobre un comentario.
/// Abre una hoja inferior en vez de un menú flotante porque el objetivo es
/// más grande con el pulgar y porque ahí cabe la confirmación sin un
/// segundo diálogo encima.
class _MenuComentario extends StatelessWidget {
  const _MenuComentario({required this.onDelete});

  final VoidCallback onDelete;

  Future<void> _abrir(BuildContext context) async {
    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              title: const Text(
                'Eliminar comentario',
                style: TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('No se puede deshacer'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ListTile(
              leading: Icon(Icons.close_rounded,
                  color: sheetContext.colors.muted),
              title: const Text('Cancelar'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );

    if (confirmado == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 22,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 18,
        splashRadius: 18,
        color: context.colors.muted,
        icon: const Icon(Icons.more_horiz_rounded),
        tooltip: 'Opciones del comentario',
        onPressed: () => _abrir(context),
      ),
    );
  }
}

/// Esqueleto de un comentario, con la misma métrica que [CommentTile] para
/// que la lista no dé un salto al cambiar de carga a contenido.
class CommentSkeleton extends StatelessWidget {
  const CommentSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(
            width: _kAvatarSize,
            height: _kAvatarSize,
            shape: BoxShape.circle,
          ),
          const SizedBox(width: _kAvatarGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 130, height: 13),
                SizedBox(height: 6),
                ShimmerBox(width: 90, height: 11),
                SizedBox(height: 10),
                ShimmerBox(width: double.infinity, height: 12),
                SizedBox(height: 6),
                ShimmerBox(width: 200, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Varios [CommentSkeleton] con el mismo espaciado que la lista real.
class CommentListSkeleton extends StatelessWidget {
  const CommentListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          const CommentSkeleton(),
        ],
      ],
    );
  }
}
