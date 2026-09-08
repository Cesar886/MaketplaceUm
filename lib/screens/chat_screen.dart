import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anon_session.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import '../services/notification_cleaner.dart';
import '../services/presence_service.dart';
import '../utils/estado_conexion.dart';
import '../utils/fecha_monterrey.dart';
import '../widgets/badges.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/online_status_avatar.dart';
import 'product_detail_screen.dart';
import 'report_user_sheet.dart';
import 'seller_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    this.productId,
    this.sellerId,
    this.product,
    this.otherUser,
    this.initialDraft,
  });

  final String conversationId;
  final String? productId;
  final String? sellerId;
  final Product? product;

  /// Con quién se está chateando, para pintar su nombre y su punto de "en
  /// línea" en el AppBar. Puede faltar (deep link desde una notificación, por
  /// ejemplo): en ese caso el AppBar cae al título genérico, sin inventar un
  /// interlocutor.
  final ChatUser? otherUser;
  final String? initialDraft;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
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
  ChatRelationship? _relationship;

  /// Mensaje que se está respondiendo, o null si se escribe un mensaje suelto.
  ChatMessage? _replyingTo;

  /// Mensaje resaltado momentáneamente tras saltar a él desde una cita.
  String? _mensajeResaltado;
  Timer? _resaltadoTimer;

  /// Una key por mensaje, para poder hacer scroll hasta él desde su cita.
  /// Se limpian junto con la lista al cambiar de conversación.
  final Map<String, GlobalKey> _messageKeys = {};

  // Para debounce del evento typing:stop
  Timer? _typingTimer;
  static const _typingDebounce = Duration(seconds: 2);

  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<String>? _delSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialDraft?.trim().isNotEmpty == true) {
      _textController.text = widget.initialDraft!.trim();
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _currentConvId = widget.conversationId;
    _displayProduct = widget.product;
    // Semilla + suscripción, igual que en la lista de chats y en el perfil
    // del vendedor: el REST ya trajo el estado en widget.otherUser y el
    // socket se encarga de los cambios mientras el chat siga abierto.
    final otro = widget.otherUser;
    if (otro != null && otro.id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<PresenceService>().sembrar(otro.id, otro.estadoConexion);
      });
      _socket.subscribePresence([otro.id]);
    }
    _initAsync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Con el chat abierto pero la app en segundo plano, los mensajes nuevos
    // sí generan notificación. Al volver, el usuario está mirando justamente
    // esa conversación, así que las notificaciones ya no aplican.
    if (state == AppLifecycleState.resumed) {
      _limpiarNotificacionesDelChat();
    }
  }

  /// Borra de la bandeja del sistema las notificaciones de esta conversación
  /// y marca como leídas sus notificaciones in-app (el badge de la campana).
  ///
  /// Los *mensajes* ya se marcan leídos solos: el GET de mensajes lo hace en
  /// el backend. Lo que faltaba era esto.
  ///
  /// Cubre por igual la entrada normal al chat y el deep link desde una
  /// notificación con la app cerrada, porque en los dos casos se monta este
  /// mismo widget y corre este mismo `initState`.
  Future<void> _limpiarNotificacionesDelChat() async {
    final convId = _currentConvId;
    if (convId == null || convId.isEmpty) return;
    await limpiarNotificacionesDeConversacion(convId);
    await ApiService.markNotificationsReadForConversation(convId);
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
    unawaited(_loadRelationship());

    // Conectar socket y unirse a la sala
    _socket.connect();
    if (_currentConvId != null && _currentConvId!.isNotEmpty) {
      _socket.joinConversation(_currentConvId!);
    }

    _setupSocketListeners();
    _limpiarNotificacionesDelChat();
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
      // La primera respuesta del interlocutor acepta la conversación y debe
      // habilitar el campo de texto sin obligar a cerrar y reabrir el chat.
      if (msg.senderId != _userId) unawaited(_loadRelationship());
      _scrollToBottom();
      // El mensaje se está leyendo en pantalla: si además llegó como push
      // (carrera entre el socket y FCM), esa notificación sobra.
      _limpiarNotificacionesDelChat();
    });

    _delSub = _socket.onMessageDeleted.listen((messageId) {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].comoEliminado();
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
      _limpiarNotificacionesDelChat();
      _messages = [];
      _messageKeys.clear();
      _replyingTo = null;
      _relationship = null;
      _loading = true;
      setState(() {});
      _loadMessages();
      unawaited(_loadRelationship());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _resaltadoTimer?.cancel();
    _msgSub?.cancel();
    _delSub?.cancel();
    _typingSub?.cancel();
    // Salir de la sala
    if (_currentConvId != null && _currentConvId!.isNotEmpty) {
      _socket.leaveConversation(_currentConvId!);
    }
    final otro = widget.otherUser;
    if (otro != null && otro.id.isNotEmpty) {
      _socket.unsubscribePresence([otro.id]);
    }
    _textController.dispose();
    _textFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Retorna el userId actual, solo para decidir qué burbujas son propias.
  ///
  /// Ya NO se manda al backend: la identidad de cada petición sale del token.
  /// Para un invitado es el id que emitió el servidor al crear su sesión, no
  /// un UUID que se generase el dispositivo.
  Future<String> _getUserId() async {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.backendSellerId != null) {
      return auth.backendSellerId!;
    }
    await AnonSession.ensure();
    return AnonSession.anonId ?? '';
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
      final messages = await ApiService.getMessages(_currentConvId!);
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

  Future<void> _loadRelationship() async {
    final otherId = widget.otherUser?.id ?? widget.sellerId;
    if (otherId == null || otherId.isEmpty || otherId == _userId) return;
    try {
      final relationship = await ApiService.getChatRelationship(otherId);
      if (mounted) setState(() => _relationship = relationship);
    } catch (_) {
      // La conversación sigue siendo usable: el servidor aplica las reglas
      // aunque este estado auxiliar no pudiera cargarse para pintar la UI.
    }
  }

  /// Activa el modo respuesta sobre [msg] (llamado desde el swipe).
  void _empezarRespuesta(ChatMessage msg) {
    if (msg.text == '[Mensaje eliminado]') return;
    setState(() => _replyingTo = msg);
    // El swipe pasa por encima del campo de texto sin tocarlo, así que el
    // teclado no se abre solo: hay que pedirle el foco explícitamente para
    // que el usuario pueda escribir la respuesta de una vez.
    _textFocusNode.requestFocus();
  }

  void _cancelarRespuesta() {
    setState(() => _replyingTo = null);
  }

  /// Desplaza la lista hasta el mensaje citado y lo resalta un momento.
  ///
  /// La lista es un [ListView.builder], así que un mensaje lejano puede no
  /// estar construido y su [GlobalKey] no tener contexto. En ese caso se salta
  /// primero a una posición estimada por su índice y se reintenta en el frame
  /// siguiente, cuando ya existe.
  Future<void> _saltarAMensaje(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0) {
      // El citado ya no está en la lista cargada (chat recortado o borrado).
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.original_not_found'.tr())));
      return;
    }

    Future<bool> intentar() async {
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx == null) return false;
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
      return true;
    }

    if (!await intentar()) {
      // Aproximación por índice: suficiente para meter el mensaje en el
      // viewport y que el builder lo construya.
      if (_scrollController.hasClients && _messages.isNotEmpty) {
        final destino =
            _scrollController.position.maxScrollExtent *
            (index / _messages.length);
        await _scrollController.animateTo(
          destino.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await intentar();
    }

    if (!mounted) return;
    setState(() => _mensajeResaltado = messageId);
    _resaltadoTimer?.cancel();
    _resaltadoTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _mensajeResaltado = null);
    });
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
    if (text.isEmpty || _sending || _relationship?.canSend == false) return;

    // Se captura y se limpia ANTES de la petición: el campo de texto ya se
    // vació, y dejar la barra de "respondiendo a" colgada mientras vuela el
    // request se lee como si el envío no hubiera tomado la cita.
    final replyToId = _replyingTo?.id;

    setState(() {
      _sending = true;
      _replyingTo = null;
    });
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
              replyToMessageId: replyToId,
            )
          : await ApiService.sendMessage(
              productId: widget.productId ?? '',
              sellerId: widget.sellerId ?? '',
              text: text,
              conversationId: _currentConvId,
              replyToMessageId: replyToId,
            );
      _applySendResult(result);
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(e, stack: stack, fallback: 'chat.send_error'.tr()),
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
    if (_sendingImage || _relationship?.canSend == false) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final replyToId = _replyingTo?.id;
    setState(() {
      _sendingImage = true;
      _replyingTo = null;
    });
    try {
      final isNewConversation =
          widget.sellerId != null && _currentConvId == widget.conversationId;
      final result = await ApiService.sendChatImage(
        imagePath: picked.path,
        productId: widget.productId,
        sellerId: widget.sellerId,
        conversationId: isNewConversation ? null : _currentConvId,
        replyToMessageId: replyToId,
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
              fallback: 'chat.send_image_error'.tr(),
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
      final relationship = result['relationship'] as Map<String, dynamic>?;
      if (relationship != null) {
        _relationship = ChatRelationship.fromJson(relationship);
      }
    });
    _scrollToBottom();
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chat.delete_message'.tr()),
        content: Text('chat.delete_message_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteMessage(msg.id);
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexOf(msg);
        if (idx >= 0) {
          _messages[idx] = msg.comoEliminado();
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
              fallback: 'chat.delete_message_error'.tr(),
            ),
          ),
        ),
      );
    }
  }

  void _abrirPerfilInterlocutor() {
    final sellerId = widget.otherUser?.id;
    if (sellerId == null || sellerId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SellerProfileScreen(sellerId: sellerId),
      ),
    );
  }

  Future<void> _vaciarChat() async {
    final convId = _currentConvId;
    if (convId == null || convId.isEmpty || _messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('chat.clear_chat_confirm'.tr()),
        content: Text('chat.clear_chat_explanation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text('chat.clear_chat'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiService.deleteConversation(convId);
      await limpiarNotificacionesDeConversacion(convId);
      if (!mounted) return;
      setState(() {
        _messages = [];
        _messageKeys.clear();
        _replyingTo = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('chat.clear_chat_success'.tr())));
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'chat.delete_conversation_error'.tr(),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleMute() async {
    final otherId = widget.otherUser?.id ?? widget.sellerId;
    if (otherId == null || otherId.isEmpty) return;
    final muted = !(_relationship?.mutedByMe ?? false);
    try {
      final relationship = await ApiService.setChatUserMuted(otherId, muted);
      if (!mounted) return;
      setState(() => _relationship = relationship);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (muted ? 'chat.muted_success' : 'chat.unmuted_success').tr(),
          ),
        ),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'chat.relationship_error'.tr(),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleBlock() async {
    final other = widget.otherUser;
    final otherId = other?.id ?? widget.sellerId;
    if (otherId == null || otherId.isEmpty) return;
    final block = !(_relationship?.blockedByMe ?? false);
    if (block) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'chat.block_confirm'.tr(namedArgs: {'user': other?.name ?? ''}),
          ),
          content: Text('chat.block_explanation'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text('chat.block_user'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final relationship = await ApiService.setChatUserBlocked(otherId, block);
      if (!mounted) return;
      setState(() {
        _relationship = relationship;
        _replyingTo = null;
        if (block) _otherTyping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (block ? 'chat.blocked_success' : 'chat.unblocked_success').tr(),
          ),
        ),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'chat.relationship_error'.tr(),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _onMenuAction(String action) async {
    switch (action) {
      case 'profile':
        _abrirPerfilInterlocutor();
        return;
      case 'mute':
        await _toggleMute();
        return;
      case 'block':
        await _toggleBlock();
        return;
      case 'report':
        final other = widget.otherUser;
        if (other != null) {
          await showUserReportSheet(
            context: context,
            userId: other.id,
            userName: other.name,
          );
        }
        return;
      case 'clear':
        await _vaciarChat();
        return;
    }
  }

  String? _relationshipBanner(ChatRelationship? relationship) {
    final state = relationship;
    if (state == null) return null;
    final name = widget.otherUser?.name ?? '';
    if (state.blockedByMe) {
      return 'chat.blocked_by_me'.tr(namedArgs: {'user': name});
    }
    if (state.blockedMe) return 'chat.blocked_by_them'.tr();
    if (state.accepted) return null;
    if (state.awaitingReply) {
      return 'chat.awaiting_reply'.tr(namedArgs: {'user': name});
    }
    final remaining = state.remainingMessages ?? 3;
    if (remaining == 3) {
      return 'chat.first_contact_info'.tr(namedArgs: {'user': name});
    }
    return 'chat.first_contact_remaining'.tr(
      namedArgs: {'count': '$remaining', 'user': name},
    );
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
    final relationshipBanner = _relationshipBanner(_relationship);
    final messagingDisabled = _relationship?.canSend == false;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: widget.otherUser?.id.isNotEmpty == true
              ? _abrirPerfilInterlocutor
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _ChatAppBarTitle(otherUser: widget.otherUser),
          ),
        ),
        actions: [
          if (_displayProduct != null)
            IconButton(
              onPressed: () => _navigateToListing(context, _displayProduct!),
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          if (widget.otherUser?.id.isNotEmpty == true)
            PopupMenuButton<String>(
              tooltip: 'chat.more_options'.tr(),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: _onMenuAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text('chat.view_profile'.tr()),
                  ),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _relationship?.mutedByMe == true
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                    ),
                    title: Text(
                      (_relationship?.mutedByMe == true
                              ? 'chat.unmute_user'
                              : 'chat.mute_user')
                          .tr(),
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  enabled:
                      _currentConvId?.isNotEmpty == true &&
                      _messages.isNotEmpty,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: Text('chat.clear_chat'.tr()),
                  ),
                ),
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: Text('chat.report_user'.tr()),
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _relationship?.blockedByMe == true
                          ? Icons.lock_open_rounded
                          : Icons.block_rounded,
                      color: _relationship?.blockedByMe == true
                          ? null
                          : context.colors.danger,
                    ),
                    title: Text(
                      (_relationship?.blockedByMe == true
                              ? 'chat.unblock_user'
                              : 'chat.block_user')
                          .tr(),
                      style: TextStyle(
                        color: _relationship?.blockedByMe == true
                            ? null
                            : context.colors.danger,
                      ),
                    ),
                  ),
                ),
              ],
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
                ? const AppChatSkeleton()
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
                          'chat.load_error'.tr(),
                          style: TextStyle(
                            color: context.colors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _loadMessages,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('common.retry'.tr()),
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
                          'chat.empty'.tr(),
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
                      final estaBorrado = msg.text == '[Mensaje eliminado]';
                      final canDelete = isMine && !estaBorrado;
                      final key = _messageKeys.putIfAbsent(
                        msg.id,
                        GlobalKey.new,
                      );
                      final burbuja = _MessageBubble(
                        key: key,
                        message: msg,
                        isMine: isMine,
                        showSender:
                            index == 0 ||
                            _messages[index - 1].senderId != msg.senderId,
                        onDelete: canDelete ? () => _deleteMessage(msg) : null,
                        resaltado: _mensajeResaltado == msg.id,
                        onTapCita: msg.replyTo == null
                            ? null
                            : () => _saltarAMensaje(msg.replyTo!.id),
                        citaEsMia: msg.replyTo?.senderId == currentUserId,
                      );
                      // Un mensaje borrado no se puede responder: la cita
                      // mostraría solo el placeholder.
                      if (estaBorrado) return burbuja;
                      return _SwipeToReply(
                        onReply: () => _empezarRespuesta(msg),
                        child: burbuja,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // La barra de "respondiendo a" ocupa todo el ancho del input;
              // sin esto quedaría centrada y encogida al tamaño del texto.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (relationshipBanner != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: messagingDisabled
                          ? context.colors.danger.withValues(alpha: .08)
                          : context.colors.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          messagingDisabled
                              ? Icons.shield_outlined
                              : Icons.info_outline_rounded,
                          size: 17,
                          color: messagingDisabled
                              ? context.colors.danger
                              : context.colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            relationshipBanner,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.colors.mutedStrong,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _QuotedMessage(
                      replyTo: RepliedMessage(
                        id: _replyingTo!.id,
                        senderId: _replyingTo!.senderId,
                        text: _replyingTo!.text,
                        imageUrl: _replyingTo!.imageUrl,
                      ),
                      esMio: _replyingTo!.senderId == currentUserId,
                      onClose: _cancelarRespuesta,
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _sendingImage || messagingDisabled
                          ? null
                          : _pickAndSendImage,
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
                        focusNode: _textFocusNode,
                        enabled: !messagingDisabled,
                        textInputAction: TextInputAction.send,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                        onChanged: _onTextChanged,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'chat.input_hint'.tr(),
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
                      onPressed: _sending || messagingDisabled
                          ? null
                          : _sendMessage,
                      icon: _sending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                // El botón se pinta con `primary`: en los
                                // swatches pastel eso es un relleno CLARO, y
                                // un spinner blanco fijo se perdía encima.
                                color: context.colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Deslizar horizontalmente una burbuja para responderla, como en WhatsApp.
///
/// Se implementa a mano con un [GestureDetector] en vez de traer
/// `flutter_slidable`: aquí no hay acciones que revelar ni panel que quede
/// abierto, solo un desplazamiento con resorte y un umbral. `Dismissible`
/// tampoco sirve, porque su gesto termina descartando el widget.
///
/// El arrastre se limita a la derecha y se amortigua conforme avanza, para que
/// el gesto tenga tope y no se sienta que la burbuja se puede llevar lejos.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});

  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  /// Cuánto hay que arrastrar para que se active la respuesta al soltar.
  static const double _umbral = 56;

  /// Tope duro del desplazamiento visual.
  static const double _maxArrastre = 80;

  late final AnimationController _volver = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  double _offset = 0;
  bool _pasoUmbral = false;

  @override
  void dispose() {
    _volver.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    final nuevo = (_offset + d.delta.dx).clamp(0.0, _maxArrastre);
    // El háptico se dispara UNA vez, al cruzar el umbral: es la señal de que
    // soltar ahora sí va a responder. Repetirlo en cada frame vibraría todo
    // el arrastre.
    if (!_pasoUmbral && nuevo >= _umbral) {
      _pasoUmbral = true;
      HapticFeedback.selectionClick();
    } else if (_pasoUmbral && nuevo < _umbral) {
      _pasoUmbral = false;
    }
    setState(() => _offset = nuevo);
  }

  void _onEnd(DragEndDetails _) {
    final activar = _offset >= _umbral;
    setState(() {
      _offset = 0;
      _pasoUmbral = false;
    });
    if (activar) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final progreso = (_offset / _umbral).clamp(0.0, 1.0);

    return GestureDetector(
      // El arrastre horizontal no compite con el scroll vertical de la lista.
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() {
        _offset = 0;
        _pasoUmbral = false;
      }),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // El ícono asoma por detrás conforme la burbuja se corre.
          Opacity(
            opacity: progreso,
            child: Transform.scale(
              scale: 0.6 + (progreso * 0.4),
              child: Icon(
                Icons.reply_rounded,
                size: 22,
                color: context.colors.muted,
              ),
            ),
          ),
          Transform.translate(offset: Offset(_offset, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// La cita de un mensaje: la barra vertical de color + autor + resumen.
///
/// Se usa en dos sitios con la misma forma, y a propósito: la barra sobre el
/// campo de texto y la cita dentro de la burbuja tienen que verse como la
/// misma cosa para que se entienda que una se convierte en la otra.
class _QuotedMessage extends StatelessWidget {
  const _QuotedMessage({
    required this.replyTo,
    required this.esMio,
    this.sobreBurbujaPropia = false,
    this.onTap,
    this.onClose,
  });

  final RepliedMessage replyTo;

  /// Si el mensaje CITADO es del usuario actual (decide el "Tú" / "Comprador").
  final bool esMio;

  /// La cita va dentro de una burbuja propia (fondo primario) → colores claros.
  final bool sobreBurbujaPropia;

  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    // "Blanco fijo" se leía bien con navy/wine (su onPrimary ES blanco) pero
    // se perdía en los seis swatches pastel, donde el relleno de la burbuja
    // propia es CLARO y onPrimary es tinta oscura. `onPrimary` es
    // precisamente el color pensado para leerse sobre `primary`, sea cual
    // sea el swatch.
    final colorTexto = sobreBurbujaPropia
        ? context.colors.onPrimary.withValues(alpha: 0.85)
        : context.colors.muted;
    final colorAutor = sobreBurbujaPropia
        ? context.colors.onPrimary
        : context.colors.accent;
    final fondo = sobreBurbujaPropia
        ? context.colors.onPrimary.withValues(alpha: 0.15)
        : context.colors.muted.withValues(alpha: 0.10);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: colorAutor, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    esMio ? 'chat.you'.tr() : 'chat.buyer'.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colorAutor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    replyTo.resumen,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: colorTexto),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 8),
                tooltip: 'chat.cancel_reply'.tr(),
              ),
          ],
        ),
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
    MaterialPageRoute<void>(
      builder: (_) => ProductDetailScreen(product: product),
    ),
  );
}

/// Título del AppBar del chat: sin interlocutor conocido cae al genérico
/// "Chat"; con él, muestra su foto (con el punto de "en línea" encima) y su
/// nombre, con "En línea" o "Activo hace X" debajo — igual que en el perfil
/// del vendedor, para que el mismo dato se lea igual en toda la app.
class _ChatAppBarTitle extends StatelessWidget {
  const _ChatAppBarTitle({required this.otherUser});

  final ChatUser? otherUser;

  @override
  Widget build(BuildContext context) {
    final otro = otherUser;
    if (otro == null || otro.id.isEmpty) return Text('nav.chat'.tr());

    // `watch`: el punto y la etiqueta tienen que encenderse y apagarse solos
    // mientras el chat sigue abierto, sin que la persona reabra la pantalla.
    final estadoConexion = context.watch<PresenceService>().estadoDe(otro.id);
    // En línea el punto verde ya lo dice todo — repetirlo en texto ("En
    // línea" debajo Y el punto encima) es ruido, no información. El texto
    // solo entra cuando el punto se apaga y hay algo más preciso que contar:
    // mismo criterio que ya usa el perfil del vendedor.
    final subtitulo = estadoConexion.enLinea
        ? null
        : etiquetaUltimaActividad(estadoConexion.ultimaActividad);

    return Row(
      children: [
        OnlineStatusAvatar(
          radius: 18,
          iniciales: otro.avatarInitials,
          mostrarIconoPorDefecto: true,
          imageUrl: otro.logoUrl != null && otro.logoUrl!.isNotEmpty
              ? '${ApiService.baseUrl}${otro.logoUrl}'
              : null,
          enLinea: estadoConexion.enLinea,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      otro.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (otro.verified || otro.socioFundador) ...[
                    const SizedBox(width: 5),
                    InsigniaCuenta(
                      verified: otro.verified,
                      socioFundador: otro.socioFundador,
                      tipoCuenta: otro.tipoCuenta,
                      size: 15,
                    ),
                  ],
                ],
              ),
              // Altura fija y no condicional: si el texto entra y sale del
              // árbol, el nombre salta un par de píxeles cada vez que la
              // persona se conecta o desconecta. Con la caja siempre puesta,
              // solo cambia lo que hay dentro.
              SizedBox(
                height: 15,
                child: subtitulo == null
                    ? null
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          subtitulo,
                          key: ValueKey(subtitulo),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.colors.muted,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductBar extends StatelessWidget {
  const _ProductBar({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.accentTint,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: context.colors.ink,
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
                'chat.purchase_chat'.tr(),
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
    super.key,
    required this.message,
    required this.isMine,
    this.showSender = false,
    this.onDelete,
    this.resaltado = false,
    this.onTapCita,
    this.citaEsMia = false,
  });

  final ChatMessage message;
  final bool isMine;
  final bool showSender;
  final VoidCallback? onDelete;

  /// Se acaba de saltar a este mensaje desde una cita: destello temporal.
  final bool resaltado;

  /// Tocar la cita salta al mensaje original.
  final VoidCallback? onTapCita;

  /// Si el mensaje CITADO lo escribió el usuario actual.
  final bool citaEsMia;

  @override
  Widget build(BuildContext context) {
    final isDeleted = message.text == '[Mensaje eliminado]';
    final hasImage = !isDeleted && message.imageUrl != null;
    final hasText = !isDeleted && message.text.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        // Destello al llegar aquí desde una cita: sin él, el scroll deja al
        // usuario mirando la lista sin saber cuál de las burbujas era.
        color: resaltado
            ? context.colors.accent.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
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
                    ? context.colors.primary
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
                  if (!isDeleted && message.replyTo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _QuotedMessage(
                        replyTo: message.replyTo!,
                        esMio: citaEsMia,
                        sobreBurbujaPropia: isMine,
                        onTap: onTapCita,
                      ),
                    ),
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
                                : const AppShimmer(
                                    child: ShimmerBox(
                                      width: 220,
                                      height: 220,
                                      borderRadius: 12,
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
                        // El fondo eliminado es siempre neutro (ver
                        // `decoration` arriba), así que su texto va en
                        // `muted` sin importar de quién sea. El resto SÍ
                        // depende del fondo: `ink` solo se lee sobre
                        // `surface` (burbuja ajena); la propia va en
                        // `primary`, y lo único legible ahí es `onPrimary`
                        // — blanco en navy/wine, tinta oscura en los
                        // pasteles.
                        color: isDeleted
                            ? context.colors.muted
                            : isMine
                            ? context.colors.onPrimary
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
                          horaMonterrey(message.createdAt),
                          style: TextStyle(
                            color: isMine
                                ? context.colors.onPrimary.withValues(
                                    alpha: 0.7,
                                  )
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
                            color: context.colors.onPrimary.withValues(
                              alpha: 0.7,
                            ),
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

  void _openFullImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _FullImageViewer(imageUrl: '${ApiService.baseUrl}$imageUrl'),
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
