import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'auth/login_screen.dart';
import 'chat_screen.dart';
import 'product_detail_screen.dart';

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_outlined,
                  size: 64, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text(
                'Inicia sesión para ver tus notificaciones',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen()),
                ),
                child: const Text('Iniciar sesión'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notificaciones'),
          actions: [
            if (_notifications.any((n) => !n.read))
              TextButton(
                onPressed: () async {
                  try {
                    await ApiService.markAllNotificationsRead();
                    if (!mounted) return;
                    setState(() {
                      for (var i = 0; i < _notifications.length; i++) {
                        _notifications[i] = NotificationItem(
                          id: _notifications[i].id,
                          userId: _notifications[i].userId,
                          type: _notifications[i].type,
                          title: _notifications[i].title,
                          body: _notifications[i].body,
                          data: _notifications[i].data,
                          read: true,
                          createdAt: _notifications[i].createdAt,
                        );
                      }
                    });
                  } catch (_) {}
                },
                child: const Text('Leer todas'),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.notifications_off_outlined,
                                  size: 64, color: AppColors.muted),
                              SizedBox(height: 16),
                              Text(
                                'Sin notificaciones',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Sigue categorías para recibir\navisos de nuevos productos.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
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

  void _openNotification(NotificationItem notif) async {
    // Marcar como leída
    if (!notif.read) {
      try {
        await ApiService.markNotificationRead(notif.id);
        if (!mounted) return;
        setState(() {
          final idx = _notifications.indexOf(notif);
          if (idx >= 0) {
            _notifications[idx] = NotificationItem(
              id: notif.id,
              userId: notif.userId,
              type: notif.type,
              title: notif.title,
              body: notif.body,
              data: notif.data,
              read: true,
              createdAt: notif.createdAt,
            );
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
            builder: (_) => ChatScreen(
              conversationId: convId,
              productId: productId ?? '',
            ),
          ),
        );
      }
    } else if (notif.type == 'new_product') {
      final productId = notif.data['productId'] as String?;
      if (productId != null) {
        try {
          final product = await ApiService.getProduct(productId);
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          );
        } catch (_) {}
      }
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final NotificationItem notification;
  final VoidCallback onTap;

  IconData _iconForType(String type) {
    switch (type) {
      case 'new_product':
        return Icons.new_releases_rounded;
      case 'new_chat':
      case 'new_message':
        return Icons.chat_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'new_product':
        return AppColors.primary;
      case 'new_chat':
      case 'new_message':
        return AppColors.teal;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: notification.read ? AppColors.surface : AppColors.champagne,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: notification.read ? AppColors.border : AppColors.premiumBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _colorForType(notification.type)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForType(notification.type),
                  color: _colorForType(notification.type),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.read
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              color: AppColors.ink,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (!notification.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.createdAt,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
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
