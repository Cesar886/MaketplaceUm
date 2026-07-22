import 'package:flutter/material.dart';

import '../mock_data.dart';
import '../models.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialCategoryId});

  final String? initialCategoryId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final results = mockProducts.where((product) {
      final matchesCategory =
          _selectedCategoryId == null ||
          product.category.id == _selectedCategoryId;
      final matchesQuery =
          query.isEmpty ||
          product.title.toLowerCase().contains(query) ||
          product.category.name.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          Text('Buscar', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          TextField(
            controller: _queryController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Libro, electronico, servicio...',
              suffixIcon: Icon(Icons.tune_rounded),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: _selectedCategoryId == null,
                    label: const Text('Todos'),
                    avatar: const Icon(Icons.apps_rounded, size: 18),
                    onSelected: (_) =>
                        setState(() => _selectedCategoryId = null),
                  ),
                ),
                for (final category in mockCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: _selectedCategoryId == category.id,
                      label: Text(category.name),
                      avatar: Icon(
                        category.icon,
                        size: 18,
                        color: category.color,
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedCategoryId = category.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${results.length} resultados mock',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Filtros visuales')),
                ),
                icon: const Icon(Icons.sort_rounded),
                label: const Text('Recientes'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final product in results) ...[
            SizedBox(
              height: 118,
              child: ProductCard(
                product: product,
                horizontal: true,
                onTap: () => _openDetail(context, product),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }
}
