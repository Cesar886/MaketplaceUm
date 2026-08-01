import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

class WantedPostDetailScreen extends StatefulWidget {
  const WantedPostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<WantedPostDetailScreen> createState() => _WantedPostDetailScreenState();
}

class _WantedPostDetailScreenState extends State<WantedPostDetailScreen> {
  WantedPost? _post;
  bool _loading = true;
  bool _busy = false;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = context.read<AuthProvider>();
    _userId = await AnonymousId.resolve(
      isLoggedIn: auth.isLoggedIn,
      backendSellerId: auth.backendSellerId,
    );
    try {
      final post = await ApiService.getWantedPost(widget.postId);
      if (mounted) setState(() => _post = post);
    } catch (_) {
      // _post queda null; el build muestra el estado de error.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond() async {
    setState(() => _busy = true);
    try {
      final conversationId = await ApiService.respondToWantedPost(widget.postId, userId: _userId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: conversationId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    try {
      final updated = await ApiService.resolveWantedPost(widget.postId, userId: _userId);
      if (!mounted) return;
      setState(() => _post = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marcada como resuelta')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final post = _post;
    if (post == null) {
      return const Scaffold(body: Center(child: Text('No se pudo cargar la búsqueda')));
    }
    final isOwner = post.userId == _userId;

    return Scaffold(
      appBar: AppBar(title: const Text('Se busca')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (post.description != null) Text(post.description!),
            const SizedBox(height: 8),
            Text(post.isService ? 'Servicio' : 'Producto',
                style: const TextStyle(color: AppColors.muted)),
            if (post.isResolved) ...[
              const SizedBox(height: 16),
              const Chip(label: Text('Resuelta')),
            ],
            const Spacer(),
            if (!post.isResolved)
              FilledButton(
                onPressed: _busy ? null : (isOwner ? _resolve : _respond),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(isOwner ? 'Marcar como resuelta' : 'Responder'),
              ),
          ],
        ),
      ),
    );
  }
}
