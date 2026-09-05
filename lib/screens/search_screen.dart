import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/product_card.dart';
import '../widgets/product_grid_metrics.dart';
import 'product_detail_screen.dart';

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

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

  // ─── Placeholder rotativo del buscador ────────────────────
  static const _typingSpeed = Duration(milliseconds: 90);
  static const _deletingSpeed = Duration(milliseconds: 45);
  static const _pauseAtFull = Duration(milliseconds: 2200);
  static const _pauseAtEmpty = Duration(milliseconds: 500);
  static const _cursorBlink = Duration(milliseconds: 500);

  List<String> _trendingSearches = [];
  Timer? _typeTimer;
  Timer? _cursorTimer;
  int _termIndex = 0;
  int _charCount = 0;
  bool _deleting = false;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _queryController.text = widget.initialQuery!;
      _registrarBusqueda(widget.initialQuery!);
    }
    _loadData();
    _cursorTimer = Timer.periodic(_cursorBlink, (_) {
      if (!mounted) return;
      setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  void _restartTyping() {
    _typeTimer?.cancel();
    if (_trendingSearches.isEmpty) return;
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final term = _trendingSearches[_termIndex % _trendingSearches.length];
    final Duration delay;
    if (!_deleting && _charCount >= term.length) {
      delay = _pauseAtFull;
    } else if (_deleting && _charCount <= 0) {
      delay = _pauseAtEmpty;
    } else {
      delay = _deleting ? _deletingSpeed : _typingSpeed;
    }
    _typeTimer = Timer(delay, _tick);
  }

  void _tick() {
    if (!mounted) return;
    final term = _trendingSearches[_termIndex % _trendingSearches.length];
    setState(() {
      if (!_deleting) {
        if (_charCount < term.length) {
          _charCount++;
        } else {
          _deleting = true;
        }
      } else {
        if (_charCount > 0) {
          _charCount--;
        } else {
          _deleting = false;
          _termIndex = (_termIndex + 1) % _trendingSearches.length;
        }
      }
    });
    _scheduleNextTick();
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
      await _loadTrending();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Recarga los términos en tendencia. No bloqueante: si falla, el buscador
  /// se queda con el hint estático en vez de quedarse sin ninguna pista.
  ///
  /// Solo toca el estado cuando la lista de verdad cambió: reasignarla igual
  /// reiniciaría la animación de tecleo a media palabra en cada auto-refresh.
  Future<void> _loadTrending() async {
    try {
      final trending = await ApiService.getTrendingSearches();
      if (!mounted || listEquals(trending, _trendingSearches)) return;
      setState(() {
        _trendingSearches = trending;
        _termIndex = 0;
        _charCount = 0;
        _deleting = false;
      });
      _restartTyping();
    } catch (_) {
      // Si falla, seguimos con lo que ya teníamos.
    }
  }

  /// Cuenta la búsqueda y vuelve a pedir las tendencias, para que el usuario
  /// vea su propio término entrar al placeholder en vez de tener que esperar
  /// al siguiente auto-refresh.
  Future<void> _registrarBusqueda(String value) async {
    await ApiService.recordSearchQuery(value);
    if (!mounted) return;
    await _loadTrending();
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _cursorTimer?.cancel();
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
    final hasTrending = _trendingSearches.isNotEmpty;
    // Hint estático de respaldo: es el que se ve mientras las tendencias
    // viajan por red, y el único que queda si `getTrendingSearches` falla o
    // devuelve la lista vacía (ver `_load`). Dejarlo en blanco deja el campo
    // sin ninguna pista de qué se puede buscar justo cuando el backend ya
    // falló, que es cuando más falta hace.
    final hintText = hasTrending
        ? _capitalize(
                _trendingSearches[_termIndex % _trendingSearches.length],
              ).substring(0, _charCount) +
              (_cursorVisible ? '▏' : '')
        : 'search.hint'.tr();

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text('common.search'.tr())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          // ─── Barra de búsqueda ─────────────────────────────
          TextField(
            controller: _queryController,
            onChanged: (_) => setState(() {}),
            onSubmitted: _registrarBusqueda,
            textInputAction: TextInputAction.search,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: hintText,
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
                        'search.advanced_filters'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.colors.ink,
                        ),
                      ),
                      const Spacer(),
                      if (_hasActiveFilters)
                        TextButton(
                          onPressed: _clearFilters,
                          child: Text('search.clear'.tr()),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Precio mínimo / máximo
                  Text(
                    'search.price_range'.tr(),
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
                          decoration: InputDecoration(
                            prefixText: r'$ ',
                            hintText: 'search.min'.tr(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
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
                          decoration: InputDecoration(
                            prefixText: r'$ ',
                            hintText: 'search.max'.tr(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
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
                    'search.seller'.tr(),
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
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                      ),
                      hintText: 'search.seller_hint'.tr(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
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
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: _selectedCategoryId == category.id,
                      label: Icon(
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
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('search.sort_recent'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text('search.sort_price_asc'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text('search.sort_price_desc'.tr()),
                    ),
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
            const AppInlineListSkeleton()
          else if (results.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'search.no_results'.tr(),
                  style: TextStyle(color: context.colors.muted),
                ),
              ),
            )
          else
            for (final product in results) ...[
              SizedBox(
                // Misma altura que ofertas; el porqué del número está en
                // ProductGridMetrics.horizontalCardHeight.
                height: ProductGridMetrics.horizontalCardHeight,
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
