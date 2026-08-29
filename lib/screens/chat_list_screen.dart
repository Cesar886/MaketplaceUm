import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import '../services/presence_service.dart';
import '../widgets/online_status_avatar.dart';
import 'chat_screen.dart';
import 'main_shell.dart';
import 'seller_profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Conversation> _conversations = [];
  bool _loading = true;
  int _unreadCount = 0;
  String _userId = '';

  StreamSubscription<String>? _convSub;
  StreamSubscription<Map<String, dynamic>>? _msgSub;

  /// Interlocutores cuya presencia se está siguiendo, para poder soltarlos en
  /// el `dispose`: la conexión es única y compartida con el resto de la app.
  List<String> _seguidos = const [];

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    _userId = await _getChatUserId();

    // Conectar socket y registrarse para recibir notificaciones.
    //
    // Con sesión iniciada MainShell ya hizo esto (y con token, que es lo que
    // enciende la presencia); aquí se conserva para el caso anónimo, que no
    // pasa por ese camino pero sí necesita los eventos de mensajes.
    final socket = ChatSocketService.instance;
    socket.connect();
    if (_userId.isNotEmpty) {
      socket.registerUser(_userId, token: ApiService.token);
    }

    // Escuchar actualizaciones de conversaciones
    _convSub = socket.onConversationUpdated.listen((_) {
      if (mounted) _load();
    });

    // Escuchar mensajes nuevos para recargar la lista (por si estamos en la lista y llega un msg)
    _msgSub = socket.onNewMessage.listen((_) {
      if (mounted) _load();
    });

    if (mounted) _load();
  }

  @override
  void dispose() {
    _convSub?.cancel();
    _msgSub?.cancel();
    ChatSocketService.instance.unsubscribePresence(_seguidos);
    super.dispose();
  }

  /// Siembra el estado que trajo el REST y se suscribe a los cambios en vivo.
  ///
  /// Se llama en cada [_load] porque la lista de interlocutores cambia sola
  /// (una conversación nueva llega por socket).
  void _seguirPresencia(List<Conversation> conversaciones) {
    final presencia = context.read<PresenceService>();
    final ids = <String>[];
    for (final conv in conversaciones) {
      final otro = conv.otherUser;
      if (otro == null || otro.id.isEmpty) continue;
      presencia.sembrar(otro.id, otro.estadoConexion);
      ids.add(otro.id);
    }

    final socket = ChatSocketService.instance;
    final anteriores = _seguidos;
    _seguidos = ids;
    // Suscribir ANTES de soltar la tanda anterior, no al revés: las dos
    // listas se solapan casi entera, y en el otro orden los ids repetidos
    // bajarían a cero referencias y provocarían un unsubscribe + subscribe
    // por cada recarga. Así solo viajan las altas y las bajas de verdad.
    socket.subscribePresence(ids);
    socket.unsubscribePresence(anteriores);
  }

  /// Retorna el userId a usar en las peticiones de chat:
  /// - Si el usuario inició sesión → usa su backendSellerId
  /// - Si no → usa su ID anónimo (persistido en SharedPreferences)
  Future<String> _getChatUserId() async {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.backendSellerId != null) {
      return auth.backendSellerId!;
    }
    return AnonymousId.get();
  }

  Future<void> _load() async {
    try {
      // Refrescar userId por si cambió
      _userId = await _getChatUserId();
      final data = await ApiService.getConversations();
      if (!mounted) return;
      final conversaciones = (data['conversations'] as List<dynamic>)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _conversations = conversaciones;
        _unreadCount = data['unreadCount'] as int? ?? 0;
        _loading = false;
      });
      _seguirPresencia(conversaciones);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('chat.title'.tr()),
            if (_unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _conversations.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 64,
                          color: context.colors.muted,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'chat.list_empty_title'.tr(),
                          style: TextStyle(
                            color: context.colors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'chat.list_empty_subtitle'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.colors.muted,
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
                itemCount: _conversations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final auth = context.read<AuthProvider>();
                  final isOwn =
                      auth.isLoggedIn && auth.backendSellerId == conv.sellerId;
                  return _ConversationTile(
                    conversation: conv,
                    isOwn: isOwn,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatScreen(
                            conversationId: conv.id,
                            productId: conv.productId,
                            // No se pasa sellerId — la conversación ya existe.
                            // ChatScreen solo necesita sellerId para crear una nueva.
                          ),
                        ),
                      );
                      _load();
                      // Además del listado, el badge de la barra inferior:
                      // se calculó antes de abrir el chat y ahí sigue con el
                      // conteo viejo.
                      if (context.mounted) {
                        context
                            .findAncestorStateOfType<MainShellState>()
                            ?.recargarContadores();
                      }
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isOwn,
    required this.onTap,
  });

  final Conversation conversation;
  final bool isOwn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUser = conversation.otherUser;
    final product = conversation.product;
    final productName =
        product?.title ??
        conversation.wantedPostTitle ??
        'chat.product_fallback'.tr();
    final unread =
        conversation.lastMessage != null &&
        conversation.lastMessage!.senderId !=
            (isOwn ? conversation.sellerId : conversation.buyerId) &&
        !conversation.lastMessage!.read;

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: unread
              ? context.colors.primary.withValues(alpha: 0.3)
              : context.colors.border,
          width: unread ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Material(
                type: MaterialType.circle,
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: otherUser != null && otherUser.id.isNotEmpty
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SellerProfileScreen(sellerId: otherUser.id),
                          ),
                        )
                      : null,
                  // `watch` y no `read`: es lo que hace que el puntito se
                  // encienda solo cuando llega el evento del socket, sin que
                  // la persona tenga que recargar la lista.
                  child: OnlineStatusAvatar(
                    radius: 24,
                    iniciales: otherUser?.avatarInitials,
                    imageUrl:
                        otherUser?.logoUrl != null &&
                            otherUser!.logoUrl!.isNotEmpty
                        ? '${ApiService.baseUrl}${otherUser.logoUrl}'
                        : null,
                    enLinea: otherUser != null &&
                        context
                            .watch<PresenceService>()
                            .estadoDe(otherUser.id)
                            .enLinea,
                  ),
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
                            otherUser?.name ?? 'Usuario',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: context.colors.ink,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: context.colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'chat.about'.tr(namedArgs: {'product': productName}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      conversation.lastMessagePreview.isNotEmpty
                          ? conversation.lastMessagePreview
                          : 'chat.tap_to_open'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
