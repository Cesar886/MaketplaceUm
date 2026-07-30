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
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: selectTab,
            height: 68,
            elevation: 0,
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.primary.withValues(alpha: 0.10),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                color: selected ? AppColors.primary : AppColors.muted,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              );
            }),
            destinations: [
              NavigationDestination(
                icon: Badge.count(
                  count: _unreadNotifCount,
                  isLabelVisible: _unreadNotifCount > 0,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.home_outlined),
                ),
                selectedIcon: Badge.count(
                  count: _unreadNotifCount,
                  isLabelVisible: _unreadNotifCount > 0,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.home_rounded),
                ),
                label: 'Inicio',
              ),
              const NavigationDestination(
                icon: Icon(Icons.local_offer_outlined),
                selectedIcon: Icon(Icons.local_offer_rounded),
                label: 'Ofertas',
              ),
              const NavigationDestination(
                icon: Icon(Icons.add_circle_outline_rounded),
                selectedIcon: Icon(Icons.add_circle_rounded),
                label: 'Publicar',
              ),
              const NavigationDestination(
                icon: Icon(Icons.favorite_outline_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: 'Favoritos',
              ),
              NavigationDestination(
                icon: Badge.count(
                  count: _unreadChatCount,
                  isLabelVisible: _unreadChatCount > 0,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.chat_outlined),
                ),
                selectedIcon: Badge.count(
                  count: _unreadChatCount,
                  isLabelVisible: _unreadChatCount > 0,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.chat_rounded),
                ),
                label: 'Mensajes',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
