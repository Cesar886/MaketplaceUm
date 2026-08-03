import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import 'product_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.productId,
    this.sellerId,
    this.product,
  });

  final String conversationId;
  final String? productId;
  final String? sellerId;
  final Product? product;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatSocketService _socket = ChatSocketService.instance;
  List<ChatMessage> _messages = [];
  String? _currentConvId;
  bool _sending = false;
  bool _loading = true;
  bool _loadError = false;
  String _userId = '';
  bool _otherTyping = false;

  // Para debounce del evento typing:stop
  Timer? _typingTimer;
  static const _typingDebounce = Duration(seconds: 2);

  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<String>? _delSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;

  @override
  void initState() {
    super.initState();
    _currentConvId = widget.conversationId;
    _initAsync();
  }

  /// Inicialización asíncrona: obtiene el userId y luego carga mensajes.
  Future<void> _initAsync() async {
    _userId = await _getUserId();

    // Conectar socket y unirse a la sala
    _socket.connect();
    if (_currentConvId != null && _currentConvId!.isNotEmpty) {
      _socket.joinConversation(_currentConvId!);
    }

    _setupSocketListeners();
    if (mounted) _loadMessages();
  }

  void _setupSocketListeners() {
    _msgSub = _socket.onNewMessage.listen((data) {
      if (!mounted) return;
      final msgConvId = data['conversationId'] as String?;
      // Solo aceptar mensajes de la conversación actual
      if (msgConvId != _currentConvId) return;

      final messageData = data['message'] as Map<String, dynamic>?;
      if (messageData == null) return;

      final msg = ChatMessage.fromJson(messageData);
      // No duplicar si ya está en la lista (lo acabamos de enviar nosotros)
      setState(() {
        final exists = _messages.any((m) => m.id == msg.id);
        if (!exists) {
          _messages.add(msg);
        }
      });
      _scrollToBottom();
    });

    _delSub = _socket.onMessageDeleted.listen((messageId) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx >= 0) {
          _messages[idx] = ChatMessage(
            id: _messages[idx].id,
            conversationId: _messages[idx].conversationId,
            senderId: _messages[idx].senderId,
            text: '[Mensaje eliminado]',
            createdAt: _messages[idx].createdAt,
            read: _messages[idx].read,
          );
        }
      });
    });

    _typingSub = _socket.onTyping.listen((data) {
      if (!mounted) return;
      // Solo para la conversación actual
      final dataConvId = data['conversationId'] as String?;
      if (dataConvId != null && dataConvId != _currentConvId) return;

      final typingUserId = data['userId'] as String?;
      // Ignorar si es el mismo usuario
      if (typingUserId == _userId) return;

      setState(() {
        _otherTyping = data['typing'] == true;
      });
    });
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      // Cambió la conversación: salir de la anterior y unirse a la nueva
      if (oldWidget.conversationId.isNotEmpty) {
        _socket.leaveConversation(oldWidget.conversationId);
      }
      _currentConvId = widget.conversationId;
      if (_currentConvId != null && _currentConvId!.isNotEmpty) {
        _socket.joinConversation(_currentConvId!);
      }
      _messages = [];
      _loading = true;
      setState(() {});
      _loadMessages();
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _msgSub?.cancel();
    _delSub?.cancel();
    _typingSub?.cancel();
    // Salir de la sala
    if (_currentConvId != null && _currentConvId!.isNotEmpty) {
      _socket.leaveConversation(_currentConvId!);
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Retorna el userId actual: si hay sesión usa el ID del backend,
  /// si no, usa el ID anónimo de SharedPreferences.
  Future<String> _getUserId() async {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.backendSellerId != null) {
      return auth.backendSellerId!;
    }
    return AnonymousId.get();
  }

  Future<void> _loadMessages() async {
    if (_currentConvId == null || _currentConvId!.isEmpty) {
      if (mounted) setState(() { _loading = false; _loadError = false; });
      return;
    }
    if (mounted) setState(() { _loading = true; _loadError = false; });
    try {
      final messages = await ApiService.getMessages(_currentConvId!, userId: _userId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _loadError = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('❌ Error cargando mensajes del chat: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _messages.isNotEmpty) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String value) {
    if (_currentConvId == null || _currentConvId!.isEmpty) return;

    // Emitir typing:start
    _socket.emitTypingStart(_currentConvId!, _userId);

    // Reiniciar timer de typing:stop
    _typingTimer?.cancel();
    _typingTimer = Timer(_typingDebounce, () {
      _socket.emitTypingStop(_currentConvId!, _userId);
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _textController.clear();

    // Asegurar que se envía typing:stop
    _typingTimer?.cancel();
    if (_currentConvId != null && _currentConvId!.isNotEmpty) {
      _socket.emitTypingStop(_currentConvId!, _userId);
    }

    try {
      final senderId = _userId;

      if (widget.sellerId != null && _currentConvId == widget.conversationId) {
        // Primera vez: enviar y crear conversación
        final result = await ApiService.sendMessage(
          productId: widget.productId ?? '',
          sellerId: widget.sellerId!,
          text: text,
          senderId: senderId,
        );
        if (!mounted) return;
        setState(() {
          _messages = (result['messages'] as List<dynamic>)
              .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
              .toList();
          final newConvId = result['conversationId'] as String?;
          if (newConvId != null && newConvId != _currentConvId) {
            // Unirse a la nueva sala de conversación
            if (_currentConvId != null && _currentConvId!.isNotEmpty) {
              _socket.leaveConversation(_currentConvId!);
            }
            _currentConvId = newConvId;
            _socket.joinConversation(_currentConvId!);
          }
        });
      } else if (_currentConvId != null && _currentConvId!.isNotEmpty) {
        // Enviar en conversación existente
        final result = await ApiService.sendMessage(
          productId: widget.productId ?? '',
          sellerId: widget.sellerId ?? '',
          text: text,
          senderId: senderId,
          conversationId: _currentConvId,
        );
        if (!mounted) return;
        setState(() {
          _messages = (result['messages'] as List<dynamic>)
              .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar mensaje'),
        content: const Text('¿Seguro que quieres eliminar este mensaje?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteMessage(msg.id, senderId: _userId);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexOf(msg);
        if (idx >= 0) {
          _messages[idx] = ChatMessage(
            id: msg.id,
            conversationId: msg.conversationId,
            senderId: msg.senderId,
            text: '[Mensaje eliminado]',
            createdAt: msg.createdAt,
            read: msg.read,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.backendSellerId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (widget.product != null)
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ProductDetailScreen(product: widget.product!),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.product != null)
            _ProductBar(product: widget.product!),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded,
                                size: 48, color: AppColors.muted),
                            const SizedBox(height: 12),
                            const Text(
                              'No se pudieron cargar los mensajes',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _loadMessages,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty && !_otherTyping
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded,
                                    size: 48, color: AppColors.muted),
                                SizedBox(height: 12),
                                Text(
                                  'Envía un mensaje para empezar',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                            itemCount: _messages.length + (_otherTyping ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_otherTyping && index == _messages.length) {
                                return _TypingIndicator();
                              }
                              final msg = _messages[index];
                              final isMine = msg.senderId == currentUserId;
                              final canDelete =
                                  isMine && msg.text != '[Mensaje eliminado]';
                              return _MessageBubble(
                                message: msg,
                                isMine: isMine,
                                showSender: index == 0 ||
                                    _messages[index - 1].senderId !=
                                        msg.senderId,
                                onDelete: canDelete
                                    ? () => _deleteMessage(msg)
                                    : null,
                              );
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _sendMessage(),
                    onChanged: _onTextChanged,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _sendMessage,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador visual de "escribiendo..." como el de WhatsApp
class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(delay: 0),
                const SizedBox(width: 4),
                _Dot(delay: 300),
                const SizedBox(width: 4),
                _Dot(delay: 600),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.muted,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class _ProductBar extends StatelessWidget {
  const _ProductBar({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.champagne,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: product.imageColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(product.imageIcon, color: product.imageColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  Product.formatPrice(product.price),
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'Chat de compra',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.showSender = false,
    this.onDelete,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showSender;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isDeleted = message.text == '[Mensaje eliminado]';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onLongPress: onDelete,
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMine && showSender)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      'Comprador',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDeleted
                    ? AppColors.muted.withValues(alpha: 0.12)
                    : isMine
                        ? AppColors.primary
                        : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                border: isMine
                    ? null
                    : Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    isDeleted ? '[Mensaje eliminado]' : message.text,
                    style: TextStyle(
                      color: isDeleted
                          ? AppColors.muted
                          : isMine
                              ? Colors.white
                              : AppColors.ink,
                      fontSize: 15,
                      height: 1.3,
                      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  if (!isDeleted) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.createdAt),
                          style: TextStyle(
                            color: isMine
                                ? Colors.white.withValues(alpha: 0.7)
                                : AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 4),
                          Icon(
                            message.read
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }
}
