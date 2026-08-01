import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import 'wanted_post_detail_screen.dart';

class WantedFeedScreen extends StatefulWidget {
  const WantedFeedScreen({super.key});

  @override
  State<WantedFeedScreen> createState() => _WantedFeedScreenState();
}

class _WantedFeedScreenState extends State<WantedFeedScreen> {
  List<WantedPost> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await ApiService.getWantedPosts(status: 'abierta');
      if (mounted) setState(() => _posts = posts);
    } catch (_) {
      // Mantener la lista previa si falla el refresh.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Se busca')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _posts.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No hay búsquedas abiertas por ahora')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            post.isService ? Icons.build_outlined : Icons.shopping_bag_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text(post.title),
                          subtitle: post.description != null ? Text(post.description!) : null,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => WantedPostDetailScreen(postId: post.id),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
