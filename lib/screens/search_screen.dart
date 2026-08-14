import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialCategoryId, this.initialQuery});

  final String? initialCategoryId;
  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutoRefreshMixin {
  final _queryController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();
  final _sellerController = TextEditingController();
  String? _selectedCategoryId;
  List<Product> _allProducts = [];
  List<MarketplaceCategory> _categories = [];
  bool _loading = true;
  bool _showFilters = false;
  double _sortValue = 0; // 0 = recientes, 1 = menor precio, 2 = mayor precio

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _queryController.text = widget.initialQuery!;
      ApiService.recordSearchQuery(widget.initialQuery!);
    }
    _loadData();
  }

  @override
  Future<void> onAutoRefresh() => _loadData();

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getProducts(),
        ApiService.getCategoriesRanked(),
      ]);
      if (!mounted) return;
      setState(() {
        _allProducts = results[0] as List<Product>;
        _categories = results[1] as List<MarketplaceCategory>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _sellerController.dispose();
    super.dispose();
  }

  List<Product> get _filteredResults {
    final query = _queryController.text.trim().toLowerCase();
    final minPrice = double.tryParse(_minPriceController.text.trim());
    final maxPrice = double.tryParse(_maxPriceController.text.trim());
    final sellerQuery = _sellerController.text.trim().toLowerCase();

    var filtered = _allProducts.where((product) {
      // Categoría
      if (_selectedCategoryId != null &&
          product.category.id != _selectedCategoryId) {
        return false;
      }
      // Texto
      if (query.isNotEmpty &&
          !product.title.toLowerCase().contains(query) &&
          !product.category.name.toLowerCase().contains(query)) {
        return false;
      }
      // Precio mínimo
      if (minPrice != null && product.price < minPrice) return false;
      // Precio máximo
      if (maxPrice != null && product.price > maxPrice) return false;
      // Vendedor
      if (sellerQuery.isNotEmpty &&
          !product.seller.name.toLowerCase().contains(sellerQuery)) {
        return false;
      }
      return true;
    }).toList();

    // Ordenar
    if (_sortValue == 1) {
      filtered.sort((a, b) => a.price.compareTo(b.price));
    } else if (_sortValue == 2) {
      filtered.sort((a, b) => b.price.compareTo(a.price));
    }
    // Por defecto (0): mantener orden original (recientes primero)

    return filtered;
  }

  bool get _hasActiveFilters =>
      _minPriceController.text.isNotEmpty ||
      _maxPriceController.text.isNotEmpty ||
      _sellerController.text.isNotEmpty;

  void _clearFilters() {
    _minPriceController.clear();
    _maxPriceController.clear();
    _sellerController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredResults;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Buscar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          // ─── Barra de búsqueda ─────────────────────────────
          TextField(
            controller: _queryController,
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) => ApiService.recordSearchQuery(value),
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Libro, electronico, servicio...',
              suffixIcon: IconButton(
                icon: Icon(
                  _showFilters ? Icons.filter_list_off : Icons.tune_rounded,
                  color: _hasActiveFilters ? context.colors.primary : null,
                ),
                onPressed: () => setState(() => _showFilters = !_showFilters),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Filtros avanzados (colapsables) ───────────────
          if (_showFilters) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasActiveFilters
                      ? context.colors.primary.withValues(alpha: 0.4)
                      : context.colors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.filter_alt_rounded,
                        size: 18,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Filtros avanzados',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.colors.ink,
                        ),
                      ),
                      const Spacer(),
                      if (_hasActiveFilters)
                        TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Precio mínimo / máximo
                  Text(
                    'Rango de precio',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minPriceController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixText: r'$ ',
                            hintText: 'Mín',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '-',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            prefixText: r'$ ',
                            hintText: 'Máx',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Vendedor
                  Text(
                    'Vendedor',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sellerController,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                      hintText: 'Nombre del vendedor',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Categorías ────────────────────────────────────
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
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: _selectedCategoryId == category.id,
                      label: Text(category.name),
                      avatar: Icon(
                        category.icon,
                        size: 18,
                        color: normalizeCategoryColor(
                          category.color,
                          Theme.of(context).brightness,
                        ),
                      ),
                      onSelected: (_) {
                        ApiService.registerCategoryTap(category.id);
                        setState(() => _selectedCategoryId = category.id);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ─── Resultados header ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_loading && results.isNotEmpty)
                DropdownButton<double>(
                  value: _sortValue,
                  underline: const SizedBox(),
                  isDense: true,
                  style: TextStyle(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Más recientes')),
                    DropdownMenuItem(value: 1, child: Text('Menor precio')),
                    DropdownMenuItem(value: 2, child: Text('Mayor precio')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortValue = v);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ─── Lista de resultados ────────────────────────────
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (results.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No se encontraron resultados.',
                  style: TextStyle(color: context.colors.muted),
                ),
              ),
            )
          else
            for (final product in results) ...[
              SizedBox(
                // 122 y no 118, igual que en ofertas: con un título de dos
                // renglones MÁS la fila de atributos destacados (que sustituyó
                // a la descripción y es más alta que ella), el contenido pide
                // exactamente esos 4 px de más.
                height: 122,
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
