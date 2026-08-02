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
  List<MarketplaceCategory> _categories = [];
  String? _selectedCategoryId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getWantedPosts(status: 'abierta', category: _selectedCategoryId),
        ApiService.getCategories(),
      ]);
      final posts = results[0] as List<WantedPost>;
      final categories = results[1] as List<MarketplaceCategory>;
      if (mounted) {
        setState(() {
          _posts = posts;
          _categories = categories;
        });
      }
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String?>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas las categorías'),
                ),
                for (final category in _categories)
                  DropdownMenuItem<String?>(
                    value: category.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(category.icon, color: category.color, size: 20),
                        const SizedBox(width: 10),
                        Text(category.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() => _selectedCategoryId = value);
                _load();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
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
          ),
        ],
      ),
    );
  }
}
