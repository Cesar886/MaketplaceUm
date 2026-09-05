import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_shimmer.dart';
import 'auth/login_screen.dart';
import 'chat_screen.dart';
import 'product_detail_screen.dart';
import 'product_questions_screen.dart';
import 'search_screen.dart';

/// Radio y aire de la tarjeta de aviso. Van juntos como constantes porque el
/// riel de color, el skeleton y la tarjeta real tienen que coincidir al pixel:
/// si el skeleton no calca la silueta, la lista "salta" al terminar de cargar.
const double _kTileRadius = 14;
const double _kTileGap = 10;
const double _kRailWidth = 3;
const EdgeInsets _kTilePadding = EdgeInsets.fromLTRB(
  16 + _kRailWidth,
  16,
  16,
  16,
);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await ApiService.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = (data['notifications'] as List<dynamic>)
            .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isLoggedIn) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _EmptyStateGlyph(icon: Icons.notifications_outlined),
                const SizedBox(height: 20),
                Text(
                  'notifications.login_prompt'.tr(),
                  textAlign: TextAlign.center,
                  style: AppTypography.body(14.5, color: context.colors.muted),
                ),
                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  ),
                  child: Text('auth.login_button'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hayNoLeidas = _notifications.any((n) => !n.read);

    return Scaffold(
      appBar: AppBar(
        // El título se queda con el estilo del `appBarTheme` (Baloo 2 sobre
        // `onPrimary`): sobrescribirlo aquí rompería el contraste con el
        // swatch elegido, que es justo lo que el tema ya resuelve.
        title: Text('nav.notifications'.tr()),
        actions: [
          // Antes el botón entraba y salía de golpe al marcar todas, lo que
          // se leía como un parpadeo. Se desvanece, pero deja de recibir
          // toques en cuanto ya no hay nada que marcar.
          AnimatedOpacity(
            opacity: hayNoLeidas ? 1 : 0,
            duration: AppAnimations.fast,
            child: IgnorePointer(
              ignoring: !hayNoLeidas,
              child: TextButton.icon(
                onPressed: _marcarTodasLeidas,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text('notifications.mark_all_read'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.onPrimary,
                  // El color va también en el `textStyle` porque el estilo
                  // explícito gana sobre `foregroundColor` al resolverse.
                  textStyle: AppTypography.label(
                    13.5,
                    color: context.colors.onPrimary,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        // El AppBar debe pintar detrás de la barra de estado; solo el
        // contenido necesita respetar el área segura inferior del teléfono.
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const _NotificationsSkeleton()
              : _notifications.isEmpty
              ? ListView(
                  // La lista tiene que seguir siendo desplazable aunque esté
                  // vacía: es lo que deja tirar hacia abajo para recargar.
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 96),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          const _EmptyStateGlyph(
                            icon: Icons.notifications_off_outlined,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'notifications.empty_title'.tr(),
                            textAlign: TextAlign.center,
                            style: AppTypography.heading(
                              18,
                              color: context.colors.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'notifications.empty_subtitle'.tr(),
                            textAlign: TextAlign.center,
                            style: AppTypography.body(
                              14,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: _kTileGap),
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    return _NotificationTile(
                      notification: notif,
                      onTap: () => _openNotification(notif),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _marcarTodasLeidas() async {
    try {
      await ApiService.markAllNotificationsRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _notifications.length; i++) {
          _notifications[i] = _copiaLeida(_notifications[i]);
        }
      });
    } catch (_) {}
  }

  void _openNotification(NotificationItem notif) async {
    // Marcar como leída
    if (!notif.read) {
      try {
        await ApiService.markNotificationRead(notif.id);
        if (!mounted) return;
        setState(() {
          final idx = _notifications.indexOf(notif);
          if (idx >= 0) {
            _notifications[idx] = _copiaLeida(notif);
          }
        });
      } catch (_) {}
    }

    // Navegar según el tipo
    if (notif.type == 'new_chat' || notif.type == 'new_message') {
      final convId = notif.data['conversationId'] as String?;
      final productId = notif.data['productId'] as String?;
      if (convId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(conversationId: convId, productId: productId ?? ''),
          ),
        );
      }
    } else if (notif.type == 'new_product' || notif.type == 'product_comment') {
      final productId = notif.data['productId'] as String?;
      if (productId != null) {
        try {
          final product = await ApiService.getProduct(productId);
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductDetailScreen(
                product: product,
                // Un aviso de comentario aterriza en el hilo, igual que al
                // tocar la push. Antes esta rama no existía y tocar la
                // notificación desde aquí no hacía nada.
                irAComentarios: notif.type == 'product_comment',
              ),
            ),
          );
        } catch (_) {}
      }
    } else if (notif.type == 'product_question' ||
        notif.type == 'question_answered') {
      final productId = notif.data['productId'] as String?;
      if (productId != null) {
        try {
          final product = await ApiService.getProduct(productId);
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductQuestionsScreen(
                productId: product.id,
                productOwnerId: product.seller.id,
                sellerName: product.seller.name,
                destacarPreguntaId: notif.data['questionId'] as String?,
              ),
            ),
          );
        } catch (_) {}
      }
    } else if (notif.type == ApiService.notifInteresNuevosProductos) {
      // Aviso de publicaciones nuevas en una categoría que le interesa.
      //
      // Registrar la apertura no es telemetría opcional: el backend cuenta
      // como ignorada toda notificación de este tipo sin apertura y, a las
      // tres seguidas, pausa la categoría 14 días. Sin esta rama, quien leía
      // sus avisos desde la campana en lugar de desde la push se autopausaba
      // sin haber hecho nada. `main_shell` hace lo propio al tocar la push.
      final categoryId = notif.data['category'] as String?;
      ApiService.registrarAperturaInteres(
        notificationId: notif.id,
        categoryId: categoryId,
      );

      final productIds =
          (notif.data['productIds'] as List<dynamic>? ?? const <dynamic>[])
              .cast<String>();

      if (productIds.length == 1) {
        try {
          final product = await ApiService.getProduct(productIds.single);
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          );
        } catch (_) {}
      } else if (categoryId != null) {
        // El aviso agrupa varias publicaciones: no hay un detalle concreto al
        // que ir, pero el tile tampoco puede quedarse muerto. La categoría
        // que lo motivó es el destino honesto.
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SearchScreen(initialCategoryId: categoryId),
          ),
        );
      }
    }
  }
}

/// El mismo aviso, ya leído. `NotificationItem` es inmutable y no trae
/// `copyWith`, así que marcar como leída obliga a reconstruirlo campo por
/// campo; hacerlo en un solo sitio evita que las dos rutas que marcan (una
/// sola y todas) se desincronicen al agregar un campo al modelo.
NotificationItem _copiaLeida(NotificationItem n) => NotificationItem(
  id: n.id,
  userId: n.userId,
  type: n.type,
  title: n.title,
  body: n.body,
  data: n.data,
  read: true,
  createdAt: n.createdAt,
);

/// Ícono de estado vacío dentro de un disco teñido, en vez de suelto sobre el
/// fondo: le da peso al centro de la pantalla cuando no hay nada que mostrar.
class _EmptyStateGlyph extends StatelessWidget {
  const _EmptyStateGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: context.colors.accentTint,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 40, color: context.colors.accent),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final NotificationItem notification;
  final VoidCallback onTap;

  IconData _iconForType(String type) {
    switch (type) {
      case 'new_product':
        return Icons.new_releases_rounded;
      case 'new_chat':
      case 'new_message':
        return Icons.chat_rounded;
      case 'product_comment':
        return Icons.mode_comment_outlined;
      case 'product_question':
      case 'question_answered':
        return Icons.forum_outlined;
      case ApiService.notifInteresNuevosProductos:
        return Icons.storefront_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  /// Cada tipo con su color. Antes solo tres tipos tenían uno y el resto caía
  /// en `muted`: media lista se veía apagada, como si esos avisos importaran
  /// menos que los demás.
  Color _colorForType(BuildContext context, String type) {
    switch (type) {
      case 'new_product':
      case ApiService.notifInteresNuevosProductos:
        return context.colors.primary;
      case 'new_chat':
      case 'new_message':
      case 'product_comment':
      case 'product_question':
      case 'question_answered':
        return context.colors.accent;
      default:
        return context.colors.mutedStrong;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leida = notification.read;
    final tipoColor = _colorForType(context, notification.type);
    final cuando = relativeTimeFromIso(notification.createdAt);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kTileRadius),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: leida ? colors.surface : colors.accentTint,
        // El recorte es lo que deja que el riel de color llegue al borde de la
        // tarjeta sin desbordar la esquina redondeada.
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kTileRadius),
          side: BorderSide(
            color: leida ? colors.border : colors.accentTintBorder,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: _kTilePadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: tipoColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _iconForType(notification.type),
                        color: tipoColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: AppTypography.label(
                                    15,
                                    color: colors.ink,
                                    weight: leida
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (!leida) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: colors.primary.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            notification.body,
                            style: AppTypography.body(
                              13,
                              color: colors.muted,
                              weight: FontWeight.w500,
                            ),
                          ),
                          // `relativeTimeFromIso` devuelve cadena vacía si la
                          // fecha no parsea. Antes se pintaba el ISO crudo del
                          // backend tal cual; ahora, si no hay nada legible que
                          // decir, no se dice nada.
                          if (cuando.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              cuando,
                              style: AppTypography.body(
                                11.5,
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Riel del color del tipo, solo en las no leídas: deja ver de un
              // vistazo qué falta por revisar sin depender del punto, que es
              // pequeño y queda al otro extremo de la tarjeta.
              if (!leida)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: _kRailWidth, color: tipoColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista fantasma con la silueta exacta de las tarjetas reales, en lugar del
/// spinner centrado que había antes: la pantalla ya se ve como lo que va a
/// ser mientras llega la respuesta, sin el salto de layout del spinner.
class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: _kTileGap),
      itemBuilder: (_, _) => const _NotificationTileSkeleton(),
    );
  }
}

class _NotificationTileSkeleton extends StatelessWidget {
  const _NotificationTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(_kTileRadius),
        border: Border.all(color: context.colors.border),
        boxShadow: AppShadows.soft,
      ),
      padding: _kTilePadding,
      child: AppShimmer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(width: 44, height: 44, borderRadius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(width: 150, height: 13, borderRadius: 4),
                  SizedBox(height: 10),
                  // Ancho infinito y no nulo: dentro de una columna alineada a
                  // la izquierda las restricciones son laxas, así que un ancho
                  // nulo colapsaría la línea a cero.
                  ShimmerBox(
                    width: double.infinity,
                    height: 11,
                    borderRadius: 4,
                  ),
                  SizedBox(height: 8),
                  ShimmerBox(width: 70, height: 9, borderRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
