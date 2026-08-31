import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import 'cart_screen.dart';
import 'chat_list_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'notifications_screen.dart';
import 'offers_screen.dart';
import 'product_detail_screen.dart';
import 'product_questions_screen.dart';
import 'profile_screen.dart';
import 'publish_product_screen.dart';
import 'wanted_post_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _unreadChatCount = 0;
  int _unreadNotifCount = 0;

  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  StreamSubscription<Map<String, List<String>>>? _snapshotSub;

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
    WidgetsBinding.instance.addObserver(this);
    recargarContadores();
    _abrirPresencia();

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
      // Navegar al chat. Al volver hay que refrescar los badges: el chat ya
      // marcó todo como leído en el servidor, pero estos contadores se
      // cargaron antes de abrirlo.
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(
                conversationId: convId,
                productId: productId ?? '',
              ),
            ),
          )
          .then((_) {
            if (mounted) recargarContadores();
          });
    } else if (type == 'new_product' && productId != null) {
      // Navegar al detalle del producto
      _openProduct(productId);
    } else if (type == 'product_comment' && productId != null) {
      // "Comentaron tu publicación": se abre el detalle YA desplazado al
      // hilo. Quien toca esta notificación viene a leer el comentario, no a
      // revisar el producto desde arriba.
      _openProduct(productId, irAComentarios: true);
    } else if ((type == 'product_question' || type == 'question_answered') &&
        productId != null) {
      // Preguntas: se abre directo la pantalla del hilo, resaltando la
      // pregunta concreta. No se pasa por el detalle porque quien toca esto
      // viene a responder (o a leer la respuesta) una pregunta puntual, y
      // dejarlo en el detalle lo obligaría a ir a buscarla.
      _openQuestions(productId, data['questionId'] as String?);
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
              title: Text('nav.publish_product'.tr()),
              subtitle: Text('nav.publish_product_subtitle'.tr()),
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
              title: Text('nav.publish_wanted'.tr()),
              subtitle: Text('nav.publish_wanted_subtitle'.tr()),
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

  /// Abre el hilo de preguntas de una publicación, opcionalmente anclado a
  /// una pregunta concreta. Necesita el producto para saber quién es el
  /// dueño (de eso depende si se puede responder ahí mismo) y su nombre.
  Future<void> _openQuestions(String productId, String? questionId) async {
    try {
      final product = await ApiService.getProduct(productId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductQuestionsScreen(
            productId: product.id,
            productOwnerId: product.seller.id,
            sellerName: product.seller.name,
            destacarPreguntaId: questionId,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Recarga los badges de chats y notificaciones.
  ///
  /// Es público porque las pantallas que abren un chat tienen que llamarlo al
  /// volver: abrir la conversación marca sus mensajes y notificaciones como
  /// leídos en el servidor, pero el badge de esta barra se calculó antes y se
  /// quedaba mostrando el número viejo hasta que el usuario cambiaba de
  /// pestaña. Se alcanza con `findAncestorStateOfType<MainShellState>()`,
  /// igual que hace HomeScreen para cambiar de pestaña.
  Future<void> recargarContadores() async {
    try {
      // Ya no hace falta resolver el userId: el contador de chats sale de la
      // bandeja del token, que el backend determina por sí mismo.
      final results = await Future.wait([
        ApiService.getConversations(),
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
    if (index == 4 || index == 0) recargarContadores();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceSub?.cancel();
    _snapshotSub?.cancel();
    // Limpiar callback para evitar memory leaks
    if (PushService.instance.onNotificationTap != null) {
      PushService.instance.onNotificationTap = null;
    }
    super.dispose();
  }

  /// Abre la conexión de tiempo real en cuanto hay sesión, no al entrar a la
  /// lista de chats.
  ///
  /// Antes `connect()` + `registerUser()` vivían en ChatListScreen, y con la
  /// presencia eso significaría aparecer "en línea" solo mientras se mira la
  /// pantalla de mensajes — que es justo cuando menos falta hace.
  void _abrirPresencia() {
    final auth = context.read<AuthProvider>();
    final sellerId = auth.backendSellerId;
    if (sellerId == null) return;

    final socket = ChatSocketService.instance;
    socket.connect();
    // El token es lo que autoriza a marcar presencia: sin él el servidor
    // une el socket a la sala pero no enciende el punto (ver register:user).
    socket.registerUser(sellerId, token: ApiService.token);

    // Los eventos se escuchan UNA vez, aquí y no en cada pantalla: quien
    // pinta el puntito lee de PresenceService, así que basta con que alguien
    // lo mantenga al día. El guardia evita duplicar las suscripciones cada
    // vez que la app vuelve de segundo plano.
    if (_presenceSub != null) return;
    final presencia = context.read<PresenceService>();
    _presenceSub = socket.onPresenceUpdate.listen(presencia.aplicarEvento);
    _snapshotSub = socket.onPresenceSnapshot.listen((datos) {
      presencia.aplicarSnapshot(
        consultados: datos['subscribed'] ?? const [],
        enLinea: datos['online'] ?? const [],
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final socket = ChatSocketService.instance;

    if (state == AppLifecycleState.resumed) {
      _abrirPresencia();
      return;
    }
    // Al pasar a segundo plano se cierra el transporte a propósito: es lo que
    // hace que el "desconectado" del otro lado sea verdad en vez de esperar a
    // que el sistema mate el proceso. Los mensajes que lleguen mientras tanto
    // siguen avisando por push (FCM), que para eso está.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      socket.disconnect();
      if (mounted) context.read<PresenceService>().limpiar();
    }
  }

  void openNotifications() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        )
        .then((_) => recargarContadores());
  }

  @override
  Widget build(BuildContext context) {
    // Fondo claro detrás de las pestañas (Inicio, Ofertas, Chat, Perfil no
    // tienen su propio AppBar) → íconos oscuros en la barra de estado.
    // Explícito porque, sin AppBar propio, Flutter no lo recalcula solo
    // al volver aquí desde una pantalla con header oscuro.
    // El botón "atrás" del sistema nunca cierra la app desde una pestaña que
    // no sea Inicio: primero vuelve a Inicio, y recién ahí un segundo "atrás"
    // sale. Sin esto, estando en Chats o Perfil el gesto salía de la app de
    // golpe, porque el IndexedStack no es una pila de rutas y el Navigator no
    // tenía nada que desapilar. Las pantallas apiladas (detalle, chat, etc.)
    // no pasan por aquí: siguen volviendo paso a paso hasta caer en el shell.
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        selectTab(0);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                        label: 'nav.home'.tr(),
                        index: 0,
                        currentIndex: _currentIndex,
                        onTap: selectTab,
                        badge: _unreadNotifCount > 0 ? _unreadNotifCount : null,
                      ),
                      _NavItem(
                        icon: Icons.local_offer_outlined,
                        selectedIcon: Icons.local_offer_rounded,
                        label: 'nav.offers'.tr(),
                        index: 1,
                        currentIndex: _currentIndex,
                        onTap: selectTab,
                      ),
                      _PublishFab(onTap: () => _showPublishMenu(context)),
                      _NavItem(
                        icon: Icons.chat_outlined,
                        selectedIcon: Icons.chat_rounded,
                        label: 'nav.chat'.tr(),
                        index: 4,
                        currentIndex: _currentIndex,
                        onTap: selectTab,
                        badge: _unreadChatCount > 0 ? _unreadChatCount : null,
                      ),
                      _NavItem(
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        label: 'nav.profile'.tr(),
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

  /// El nombre de la pestaña. NO se dibuja: la barra es solo de íconos, con el
  /// "+" de oro al centro, y cuatro etiquetas de 10px alrededor lo rodeaban de
  /// ruido. Se conserva porque un ícono suelto no dice nada a un lector de
  /// pantalla: va como etiqueta semántica y como tooltip.
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    // Sobre la barra los estados se separan por LUMINOSIDAD, no por tono:
    // solo el ítem activo va al foreground pleno y los demás se apagan.
    //
    // El acento del tema no puede participar aquí: con el swatch navy
    // `colors.accent` es #1B2A4A, exactamente el color de esta barra, así que
    // un "activo en color de acento" desaparecería en 2 de los 8 swatches.
    // Todo lo que se dibuje sobre la barra tiene que derivar de [onPrimary],
    // que es el único foreground que la paleta garantiza legible sobre
    // [primary] sea cual sea el swatch elegido.
    //
    // El inactivo baja de 62% a 55% (#989FAE sobre navy, 5.35:1 — sigue
    // holgadamente sobre AA) para que la navegación deje de competir con las
    // categorías y con el contenido de las tarjetas.
    final selected = index == currentIndex;
    final color = selected
        ? context.colors.onPrimary
        : context.colors.onPrimary.withValues(alpha: 0.55);

    Widget iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 24,
      color: color,
    );

    if (badge != null && badge! > 0) {
      // El contador va con el tema al revés del que se ve en la barra, pero
      // con el swatch que la persona eligió — ver [contadorSobrePrimary], que
      // es donde está el porqué y contra qué se verificó.
      //
      // Antes iba en `AppColors.danger`, un ladrillo que no participa de la
      // paleta: se leía, pero era el único punto de la app donde el color no
      // seguía la elección del usuario.
      final contador = context.colors.contadorSobrePrimary;
      iconWidget = Badge.count(
        count: badge!,
        backgroundColor: contador.fondo,
        textColor: contador.texto,
        child: iconWidget,
      );
    }

    // Sin etiqueta debajo, lo que distingue al activo es la luminosidad del
    // ícono y su escala; el área tocable sigue siendo todo el alto de la
    // barra, que es lo que importa para el dedo.
    return Expanded(
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: () => onTap(index),
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: AnimatedScale(
                scale: selected ? 1.14 : 1.0,
                duration: AppAnimations.fast,
                curve: AppAnimations.spring,
                child: iconWidget,
              ),
            ),
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
        // El "+" se pinta INVERTIDO respecto a la barra: relleno en
        // [onPrimary] y el glifo en [primary], al revés que todo lo demás.
        //
        // Antes usaba `colors.primary` para el relleno — el mismo color que
        // la barra que lo contiene, 1.00:1: el botón era literalmente
        // invisible y solo lo delataba su sombra. Es el resto de cuando el
        // FAB era `AppColors.gold`; al pasar todo a la paleta por contexto,
        // el oro se mapeó a `primary` y nadie miró que ahí `primary` ya era
        // el fondo.
        //
        // La inversión da 14.22:1 contra la barra navy — el máximo alcanzable
        // — y es el ÚNICO elemento de la barra que invierte la relación
        // relleno/foreground, que es lo que lo separa de las cinco pestañas y
        // lo deja como la acción principal. Además sale gratis en los ocho
        // swatches: sobre barra pastel se vuelve un círculo navy con el "+"
        // pastel, sin una sola rama condicional.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.onPrimary,
            shape: BoxShape.circle,
            // La sombra se queda en el color de la barra: sobre la barra no
            // se ve (es su mismo tono) pero asienta el círculo contra el
            // borde superior y contra el contenido que pasa por debajo.
            boxShadow: AppShadows.accent(context.colors.primary),
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              Icons.add_rounded,
              color: context.colors.primary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
