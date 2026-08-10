import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_error.dart';
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
  bool _sendingImage = false;
  bool _loading = true;
  bool _loadError = false;
  String _userId = '';
  bool _otherTyping = false;
  Product? _displayProduct;

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
    _displayProduct = widget.product;
    _initAsync();
  }

  /// Si nos abrieron solo con productId (p. ej. desde la lista de chats o
  /// una notificación push, que no traen el objeto Product completo), lo
  /// buscamos para poder mostrar la barra "sobre qué producto es este chat".
  Future<void> _loadDisplayProduct() async {
    if (_displayProduct != null) return;
    final productId = widget.productId;
    if (productId == null || productId.isEmpty) return;
    try {
      final product = await ApiService.getProduct(productId);
      if (!mounted) return;
      setState(() => _displayProduct = product);
    } catch (_) {
      // Sin producto: la barra simplemente no se muestra.
    }
  }

  /// Inicialización asíncrona: obtiene el userId y luego carga mensajes.
  Future<void> _initAsync() async {
    final userId = await _getUserId();
    if (!mounted) return;
    // setState explícito: build() usa _userId para decidir qué burbujas son
    // "propias" (isMine). Sin este rebuild, si _loadMessages tardara en
    // completarse (o la lista llegara vacía), el chat podría quedar
    // pintado una vez con _userId aún vacío y no repintarse nunca con el
    // identificador correcto.
    setState(() => _userId = userId);
    _loadDisplayProduct();

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
            imageUrl: null,
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
      if (mounted)
        setState(() {
          _loading = false;
          _loadError = false;
        });
      return;
    }
    if (mounted)
      setState(() {
        _loading = true;
        _loadError = false;
      });
    try {
      final messages = await ApiService.getMessages(
        _currentConvId!,
        userId: _userId,
      );
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
      final isNewConversation =
          widget.sellerId != null && _currentConvId == widget.conversationId;
      final result = isNewConversation
          ? await ApiService.sendMessage(
              productId: widget.productId ?? '',
              sellerId: widget.sellerId!,
              text: text,
              senderId: _userId,
            )
          : await ApiService.sendMessage(
              productId: widget.productId ?? '',
              sellerId: widget.sellerId ?? '',
              text: text,
              senderId: _userId,
              conversationId: _currentConvId,
            );
      _applySendResult(result);
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'No se pudo enviar el mensaje. Intenta de nuevo.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Elige una imagen de la galería y la envía al chat. El backend la
  /// convierte a WebP antes de guardarla para que pese menos.
  Future<void> _pickAndSendImage() async {
    if (_sendingImage) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _sendingImage = true);
    try {
      final isNewConversation =
          widget.sellerId != null && _currentConvId == widget.conversationId;
      final result = await ApiService.sendChatImage(
        imagePath: picked.path,
        senderId: _userId,
        productId: widget.productId,
        sellerId: widget.sellerId,
        conversationId: isNewConversation ? null : _currentConvId,
      );
      _applySendResult(result);
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'No se pudo enviar la imagen. Intenta de nuevo.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  /// Aplica la respuesta común de /chat/send y /chat/send-image: actualiza
  /// la lista de mensajes y, si esta era la primera vez que se enviaba
  /// (todavía no existía conversación), se une a la sala recién creada.
  void _applySendResult(Map<String, dynamic> result) {
    if (!mounted) return;
    setState(() {
      _messages = (result['messages'] as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      final newConvId = result['conversationId'] as String?;
      if (newConvId != null && newConvId != _currentConvId) {
        if (_currentConvId != null && _currentConvId!.isNotEmpty) {
          _socket.leaveConversation(_currentConvId!);
        }
        _currentConvId = newConvId;
        _socket.joinConversation(_currentConvId!);
      }
    });
    _scrollToBottom();
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
            imageUrl: null,
          );
        }
      });
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'No se pudo eliminar el mensaje. Intenta de nuevo.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // _userId es el mismo identificador con el que se envían y cargan los
    // mensajes (_getUserId(): backendSellerId si hay sesión, si no el
    // device_id anónimo) — usar cualquier otra fuente aquí (p. ej.
    // auth.backendSellerId directo) rompe la comparación para usuarios
    // anónimos, porque backendSellerId siempre es null para ellos y
    // "msg.senderId == ''" nunca es true.
    final currentUserId = _userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (_displayProduct != null)
            IconButton(
              onPressed: () => _navigateToListing(context, _displayProduct!),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_displayProduct != null)
            _ProductBar(
              product: _displayProduct!,
              onTap: () => _navigateToListing(context, _displayProduct!),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 48,
                          color: context.colors.muted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No se pudieron cargar los mensajes',
                          style: TextStyle(
                            color: context.colors.muted,
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
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: context.colors.muted,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Envía un mensaje para empezar',
                          style: TextStyle(
                            color: context.colors.muted,
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
                        showSender:
                            index == 0 ||
                            _messages[index - 1].senderId != msg.senderId,
                        onDelete: canDelete ? () => _deleteMessage(msg) : null,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(top: BorderSide(color: context.colors.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _sendingImage ? null : _pickAndSendImage,
                  icon: _sendingImage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_outlined),
                ),
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
              color: context.colors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: context.colors.border),
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

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
            decoration: BoxDecoration(
              color: context.colors.muted,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

void _navigateToListing(BuildContext context, Product product) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ProductDetailScreen(product: product)),
  );
}

class _ProductBar extends StatelessWidget {
  const _ProductBar({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.premiumBg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.colors.border)),
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
                child: Icon(
                  product.imageIcon,
                  color: product.imageColor,
                  size: 22,
                ),
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
                      style: TextStyle(
                        color: context.colors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Chat de compra',
                style: TextStyle(color: context.colors.muted, fontSize: 12),
              ),
              const SizedBox(width: 4),
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
    final hasImage = !isDeleted && message.imageUrl != null;
    final hasText = !isDeleted && message.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onLongPress: onDelete,
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isMine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!isMine && showSender)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      'Comprador',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.muted,
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
              padding: EdgeInsets.symmetric(
                horizontal: hasImage && !hasText ? 4 : 14,
                vertical: hasImage && !hasText ? 4 : 10,
              ),
              decoration: BoxDecoration(
                color: isDeleted
                    ? context.colors.muted.withValues(alpha: 0.12)
                    : isMine
                    ? AppColors.primary
                    : context.colors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                border: isMine
                    ? null
                    : Border.all(color: context.colors.border),
              ),
              child: Column(
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (hasImage)
                    Padding(
                      padding: EdgeInsets.only(bottom: hasText ? 6 : 0),
                      child: GestureDetector(
                        onTap: () => _openFullImage(context, message.imageUrl!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            '${ApiService.baseUrl}${message.imageUrl}',
                            width: 220,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : const SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 220,
                              height: 120,
                              child: Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (isDeleted || hasText)
                    Text(
                      isDeleted ? '[Mensaje eliminado]' : message.text,
                      style: TextStyle(
                        color: isDeleted
                            ? context.colors.muted
                            : isMine
                            ? Colors.white
                            : context.colors.ink,
                        fontSize: 15,
                        height: 1.3,
                        fontStyle: isDeleted
                            ? FontStyle.italic
                            : FontStyle.normal,
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
                                : context.colors.muted,
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

  void _openFullImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullImageViewer(imageUrl: '${ApiService.baseUrl}$imageUrl'),
        fullscreenDialog: true,
      ),
    );
  }
}

/// Visor de pantalla completa con zoom para las imágenes del chat.
class _FullImageViewer extends StatelessWidget {
  const _FullImageViewer({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
