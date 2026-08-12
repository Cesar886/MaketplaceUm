import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    // Si la app se abrió desde cero por un tap en notificación (cold
    // start), ese mensaje llegó antes de que este callback existiera.
    // Se procesa ahora que ya hay un Navigator disponible, después del
    // primer frame para no navegar en medio del build inicial.
    final pending = PushService.instance.consumePendingNotification();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleNotificationTap(pending);
      });
    }
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
          builder: (_) =>
              ChatScreen(conversationId: convId, productId: productId ?? ''),
        ),
      );
    } else if (type == 'new_product' && productId != null) {
      // Navegar al detalle del producto
      _openProduct(productId);
    } else if (type == 'product_comment' && productId != null) {
      // "Comentaron tu publicación": se abre el detalle YA desplazado al
      // hilo. Quien toca esta notificación viene a leer el comentario, no a
      // revisar el producto desde arriba.
      _openProduct(productId, irAComentarios: true);
    }
  }

  void _showPublishMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.sell_outlined, color: context.colors.primary),
              title: const Text('Publicar producto'),
              subtitle: const Text('Vende algo que ya tienes'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                selectTab(2);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.search_rounded,
                color: context.colors.primary,
              ),
              title: const Text('Publicar búsqueda'),
              subtitle: const Text('Di qué estás buscando y te notificamos'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WantedPostScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProduct(
    String productId, {
    bool irAComentarios = false,
  }) async {
    try {
      final product = await ApiService.getProduct(productId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(
            product: product,
            irAComentarios: irAComentarios,
          ),
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
        _unreadChatCount =
            (results[0] as Map<String, dynamic>)['unreadCount'] as int? ?? 0;
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
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        )
        .then((_) => _loadUnreadCounts());
  }

  @override
  Widget build(BuildContext context) {
    // Fondo claro detrás de las pestañas (Inicio, Ofertas, Chat, Perfil no
    // tienen su propio AppBar) → íconos oscuros en la barra de estado.
    // Explícito porque, sin AppBar propio, Flutter no lo recalcula solo
    // al volver aquí desde una pantalla con header oscuro.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Arriba, fondo claro → íconos oscuros. Abajo, la barra de navegación
      // navy se extiende por debajo de la barra del sistema, así que ahí los
      // íconos tienen que ser claros: un solo preset no cubre los dos lados.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: context.colors.primary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < _pages.length; i++)
              HeroMode(enabled: i == _currentIndex, child: _pages[i]),
          ],
        ),
        // Barra navy sólida: es el marco frío contra el que el "+" de oro se
        // vuelve el único punto cálido de la pantalla, e imposible de no ver
        // (6:1 contra el navy). Sobre una barra blanca ese mismo botón
        // compite con las tarjetas; sobre navy no compite con nada.
        bottomNavigationBar: Container(
          color: context.colors.primary,
          child: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.primary,
                border: Border(
                  top: BorderSide(
                    color: context.colors.accentTintBorder,
                    width: 0.8,
                  ),
                ),
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
    // Sobre la barra navy los estados se separan por luminosidad, no por
    // tono: blanco para la pestaña activa y un navy claro para las demás.
    // El oro no participa aquí — en esta barra pertenece solo al "+".
    final selected = index == currentIndex;
    final color = selected
        ? Colors.white
        : context.colors.onPrimary.withValues(alpha: 0.62);

    Widget iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 24,
      color: color,
    );

    if (badge != null && badge! > 0) {
      iconWidget = Badge.count(
        count: badge!,
        backgroundColor: context.colors.primary,
        textColor: context.colors.onPrimary,
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
            color: context.colors.primary,
            shape: BoxShape.circle,
            boxShadow: AppShadows.accent(context.colors.primary),
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.add_rounded,
              color: context.colors.onPrimary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
