import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import 'cart_screen.dart';
import 'chat_list_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'offers_screen.dart';
import 'product_detail_screen.dart';
import 'profile_screen.dart';
import 'publish_product_screen.dart';
import 'wanted_post_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _unreadChatCount = 0;
  int _unreadNotifCount = 0;

  final _pages = const [
    HomeScreen(),
    OffersScreen(),
    PublishProductScreen(),
    CartScreen(),
    ChatListScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnreadCounts();

    // Manejar taps en notificaciones push
    PushService.instance.onNotificationTap = (data) {
      _handleNotificationTap(data);
    };
  }

  /// Navega a la pantalla correspondiente según los datos de la notificación push.
  void _handleNotificationTap(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type'] as String?;
    final convId = data['conversationId'] as String?;
    final productId = data['productId'] as String?;

    if ((type == 'new_chat' || type == 'new_message') && convId != null) {
      // Navegar al chat
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: convId,
            productId: productId ?? '',
          ),
        ),
      );
    } else if (type == 'new_product' && productId != null) {
      // Navegar al detalle del producto
      _openProduct(productId);
    }
  }

  void _showPublishMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.sell_outlined, color: AppColors.primary),
              title: const Text('Publicar producto'),
              subtitle: const Text('Vende algo que ya tienes'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                selectTab(2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded, color: AppColors.primary),
              title: const Text('Publicar búsqueda'),
              subtitle: const Text('Di qué estás buscando y te notificamos'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WantedPostScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProduct(String productId) async {
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

  Future<void> _loadUnreadCounts() async {
    try {
      String userId;
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn && auth.backendSellerId != null) {
        userId = auth.backendSellerId!;
      } else {
        userId = await AnonymousId.get();
      }
      final results = await Future.wait([
        ApiService.getConversations(userId: userId),
        ApiService.getUnreadNotificationCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _unreadChatCount = (results[0] as Map<String, dynamic>)['unreadCount'] as int? ?? 0;
        _unreadNotifCount = results[1] as int;
      });
    } catch (_) {}
  }

  void selectTab(int index) {
    setState(() => _currentIndex = index);
    // Recargar contadores al navegar a chats o notificaciones
    if (index == 4 || index == 0) _loadUnreadCounts();
  }

  @override
  void dispose() {
    // Limpiar callback para evitar memory leaks
    if (PushService.instance.onNotificationTap != null) {
      PushService.instance.onNotificationTap = null;
    }
    super.dispose();
  }

  void openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ),
    ).then((_) => _loadUnreadCounts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _pages.length; i++)
            HeroMode(enabled: i == _currentIndex, child: _pages[i]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
          ),
          child: SizedBox(
            height: 66,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'Inicio',
                  index: 0,
                  currentIndex: _currentIndex,
                  onTap: selectTab,
                  badge: _unreadNotifCount > 0 ? _unreadNotifCount : null,
                ),
                _NavItem(
                  icon: Icons.local_offer_outlined,
                  selectedIcon: Icons.local_offer_rounded,
                  label: 'Ofertas',
                  index: 1,
                  currentIndex: _currentIndex,
                  onTap: selectTab,
                ),
                _PublishFab(onTap: () => _showPublishMenu(context)),
                _NavItem(
                  icon: Icons.favorite_outline_rounded,
                  selectedIcon: Icons.favorite_rounded,
                  label: 'Favs',
                  index: 3,
                  currentIndex: _currentIndex,
                  onTap: selectTab,
                ),
                _NavItem(
                  icon: Icons.chat_outlined,
                  selectedIcon: Icons.chat_rounded,
                  label: 'Chat',
                  index: 4,
                  currentIndex: _currentIndex,
                  onTap: selectTab,
                  badge: _unreadChatCount > 0 ? _unreadChatCount : null,
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'Perfil',
                  index: 5,
                  currentIndex: _currentIndex,
                  onTap: selectTab,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    final color = selected ? AppColors.primary : AppColors.muted;

    Widget iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 24,
      color: color,
    );

    if (badge != null && badge! > 0) {
      iconWidget = Badge.count(
        count: badge!,
        backgroundColor: AppColors.primary,
        child: iconWidget,
      );
    }

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.14 : 1.0,
                duration: AppAnimations.fast,
                curve: AppAnimations.spring,
                child: iconWidget,
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: AppAnimations.fast,
                curve: AppAnimations.spring,
                style: AppTypography.label(
                  10,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublishFab extends StatelessWidget {
  const _PublishFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.amber,
            shape: BoxShape.circle,
            boxShadow: AppShadows.amber,
          ),
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(Icons.add_rounded, color: AppColors.amberDark, size: 28),
          ),
        ),
      ),
    );
  }
}
