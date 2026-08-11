import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import 'chat_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    _userId = await _getChatUserId();

    // Conectar socket y registrarse para recibir notificaciones
    final socket = ChatSocketService.instance;
    socket.connect();
    if (_userId.isNotEmpty) {
      socket.registerUser(_userId);
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
    super.dispose();
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
      final data = await ApiService.getConversations(userId: _userId);
      if (!mounted) return;
      setState(() {
        _conversations = (data['conversations'] as List<dynamic>)
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList();
        _unreadCount = data['unreadCount'] as int? ?? 0;
        _loading = false;
      });
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
            const Text('Mensajes'),
            if (_unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
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
                          'Sin conversaciones',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Envía un mensaje desde cualquier\nproducto para iniciar un chat.',
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
        product?.title ?? conversation.wantedPostTitle ?? 'Producto';
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
              ? AppColors.primary.withValues(alpha: 0.3)
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
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                backgroundImage:
                    otherUser?.logoUrl != null && otherUser!.logoUrl!.isNotEmpty
                    ? NetworkImage('${ApiService.baseUrl}${otherUser.logoUrl}')
                    : null,
                child: otherUser?.logoUrl == null || otherUser!.logoUrl!.isEmpty
                    ? Text(
                        otherUser?.avatarInitials ?? '?',
                        style: TextStyle(
                          color: context.colors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      )
                    : null,
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
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sobre: $productName',
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
                          : 'Haz clic para ver la conversación',
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
