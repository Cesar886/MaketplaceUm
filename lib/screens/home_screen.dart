import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/favorite_products_service.dart';
import '../services/feed_mixer.dart';
import '../widgets/app_logo.dart';
import '../widgets/auto_refresh.dart';
import '../widgets/home_grid_skeleton.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
import '../widgets/wanted_post_card.dart';
import 'main_shell.dart';
import 'product_detail_screen.dart';
import 'qr_scanner_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutoRefreshMixin, TickerProviderStateMixin {
  List<Product> _products = [];
  List<MarketplaceCategory> _categories = [];
  List<HighlightPlan> _highlightPlans = [];
  List<Seller> _sellers = [];
  List<WantedPost> _wantedPosts = [];
  bool _loading = true;
  bool _hasPublished = false;
  String? _error;
  String? _selectedCategoryId;
  int _favoriteCount = 0;

  // Semilla del mezclado del feed: se regenera en cada _loadData() (carga
  // inicial y pull-to-refresh) para que el interleaving sea distinto cada
  // vez, pero se mantiene fija entre rebuilds (ej. al filtrar por
  // categoría) para no re-barajar el feed en cada tap.
  int _feedSeed = 0;

  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: AppAnimations.slow + AppAnimations.staggerDelay * 14,
    );
    _loadData();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  double _cardAnimValue(int index) {
    final total = _staggerController.duration!.inMilliseconds.toDouble();
    final start = (AppAnimations.staggerDelay.inMilliseconds * index) / total;
    final end = (start + AppAnimations.slow.inMilliseconds / total).clamp(
      0.0,
      1.0,
    );
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start.clamp(0.0, 1.0), end, curve: AppAnimations.spring),
    ).value;
  }

  @override
  Future<void> onAutoRefresh() => _loadData(silent: true);

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _products.isEmpty) setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      // El feed rankeado distingue deviceId (siempre el anónimo persistido,
      // usado para afinidad por dispositivo) de userId (cuenta real, solo
      // si hay sesión) — son conceptos distintos en el backend aunque acá
      // arriba se resuelvan a uno solo para el resto de los endpoints.
      final deviceId = await AnonymousId.get();
      final backendUserId = auth.isLoggedIn ? auth.backendSellerId : null;
      if (!mounted) return;
      final results = await Future.wait([
        ApiService.getFeed(deviceId: deviceId, userId: backendUserId),
        ApiService.getCategories(),
      ]);
      if (!mounted) return;

      // Highlight plans (banners de "destacar publicación") son contenido
      // secundario del home: si el request falla, no debe tapar el feed
      // principal que sí cargó bien — simplemente no se muestran.
      List<HighlightPlan> loadedHighlightPlans = [];
      try {
        loadedHighlightPlans = await ApiService.getHighlightPlans();
      } catch (_) {
        // Si falla, seguimos con lista vacía
      }

      // Cargar sellers por separado (no debe bloquear el resto)
      List<Seller> loadedSellers = [];
      try {
        loadedSellers = await ApiService.getSellers();
      } catch (_) {
        // Si falla, seguimos con lista vacía
      }

      // Cargar búsquedas abiertas por separado (no debe bloquear el resto)
      List<WantedPost> loadedWantedPosts = [];
      try {
        loadedWantedPosts = await ApiService.getWantedPosts(status: 'abierta');
      } catch (_) {
        // Si falla, seguimos con lista vacía
      }

      // Verificar si el usuario ha publicado artículos
      bool hasPublished = false;
      if (auth.isLoggedIn) {
        try {
          final listings = await ApiService.getListings();
          hasPublished = listings.isNotEmpty;
        } catch (_) {
          // Si falla, asumir que no ha publicado
        }
      }

      setState(() {
        _products = results[0] as List<Product>;
        _categories = results[1] as List<MarketplaceCategory>;
        _highlightPlans = loadedHighlightPlans;
        _sellers = loadedSellers;
        _wantedPosts = loadedWantedPosts;
        _hasPublished = hasPublished;
        _loading = false;
        _error = null;
        _feedSeed = DateTime.now().millisecondsSinceEpoch;
      });
      _staggerController.forward(from: 0);
      // Cargar contador de favoritos (no bloqueante)
      _loadFavoriteCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Mensaje amigable en vez del texto técnico crudo de la excepción
        // (ej. "ClientException: Connection closed..."), que ya se
        // reintentó automáticamente en ApiService antes de llegar aquí.
        _error =
            'No pudimos cargar el inicio. Revisa tu conexión e '
            'intenta de nuevo.';
      });
    }
  }

  Future<void> _loadFavoriteCount() async {
    try {
      final ids = await FavoriteProductsService.getFavoriteIds();
      if (!mounted) return;
      setState(() => _favoriteCount = ids.length);
    } catch (_) {}
  }

  int get _favoriteCountValue => _favoriteCount;

  /// Agrupa productos por vendedor.
  /// Solo incluye vendedores marcados como negocio (isBusiness = true).
  /// Ordenados por: más productos primero, luego verificados.
  List<MapEntry<Seller, List<Product>>> get _businessesWithProducts {
    final Map<String, List<Product>> grouped = {};
    for (final p in _products) {
      grouped.putIfAbsent(p.seller.id, () => []).add(p);
    }
    final result = <MapEntry<Seller, List<Product>>>[];
    for (final seller in _sellers) {
      final products = grouped[seller.id];
      if (products != null && products.isNotEmpty && seller.isBusiness) {
        result.add(MapEntry(seller, products));
      }
    }
    // Ordenar: más productos primero, luego verificados
    result.sort((a, b) {
      final byCount = b.value.length.compareTo(a.value.length);
      if (byCount != 0) return byCount;
      return (b.key.verified ? 1 : 0).compareTo(a.key.verified ? 1 : 0);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppAnimations.medium,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const HomeGridSkeleton(key: ValueKey('home-skeleton'));
    }

    if (_error != null) {
      return SafeArea(
        key: const ValueKey('home-error'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filtered = _selectedCategoryId == null
        ? _products
        : _products.where((p) => p.category.id == _selectedCategoryId).toList();
    final recent = filtered.where((p) => !p.isFeatured).toList();

    return SafeArea(
      key: const ValueKey('home-content'),
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: AppLogo(size: 44)),
                        _ScanQrButton(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const QrScannerScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _NotificationBell(
                          onTap: () {
                            final shell = context
                                .findAncestorStateOfType<MainShellState>();
                            shell?.openNotifications();
                          },
                        ),
                        const SizedBox(width: 4),
                        _FavHeaderButton(
                          itemCount: _favoriteCountValue,
                          onTap: () {
                            final shell = context
                                .findAncestorStateOfType<MainShellState>();
                            shell?.selectTab(3);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SearchBox(onTap: () => _openSearch(context)),
                    const SizedBox(height: 18),
                    _CategoryScroller(
                      categories: _categories,
                      selectedCategoryId: _selectedCategoryId,
                      onCategoryTap: (id) {
                        if (_selectedCategoryId == id) {
                          // Tap en la misma categoría → limpiar filtro
                          setState(() => _selectedCategoryId = null);
                        } else {
                          setState(() => _selectedCategoryId = id);
                        }
                      },
                    ),
                    if (_selectedCategoryId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _CategoryFilterChip(
                          category: _categories.firstWhere(
                            (c) => c.id == _selectedCategoryId,
                            orElse: () => _categories.first,
                          ),
                          onClear: () =>
                              setState(() => _selectedCategoryId = null),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_highlightPlans.isNotEmpty && _hasPublished)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: _HighlightPlansBanner(plans: _highlightPlans),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: SectionHeader(
                  title: 'Para ti',
                  actionLabel: 'Ordenar',
                  onAction: () =>
                      _showMockMessage(context, 'Ordenamiento visual'),
                ),
              ),
            ),
            // ─── Feed mixto: productos + búsquedas + negocios ──────
            // El orden interno de cada tipo respeta el ranking que ya trae
            // del backend (score de /api/feed, recencia de /api/wanted,
            // conteo de productos para negocios) — FeedMixer solo decide
            // cómo se intercalan los BLOQUES entre tipos.
            //
            // Se crea una instancia nueva en cada build() y se drena de un
            // tirón con getAll() porque hoy el home no tiene scroll
            // infinito: no hay "página 2" que deba continuar un cursor a
            // medio bloque, así que no hace falta guardar la instancia
            // entre rebuilds. La semilla (_feedSeed) sí se mantiene fija
            // entre rebuilds (solo cambia en _loadData) para que filtrar
            // por categoría recalcule el mismo orden sobre la lista ya
            // filtrada, en vez de rebarajar en cada tap.
            //
            // Cuando se agregue paginación real, este patrón cambia a:
            // crear el FeedMixer UNA vez en _loadData (semilla nueva ahí),
            // guardarlo en un campo de estado, y pedirle getNextBatch(n) a
            // esa misma instancia cada vez que el scroll dispare la
            // siguiente página — ver el doc de [FeedMixer] para el porqué.
            ..._buildFeedSlivers(
              context,
              FeedMixer(
                products: recent,
                wantedPosts: _wantedPosts,
                businesses: _businessesWithProducts,
                seed: _feedSeed,
              ).getAll(),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
      ),
    );
  }

  /// Traduce el feed ya intercalado (item por item, sin agrupar por bloque)
  /// a slivers.
  ///
  /// Productos y búsquedas fluyen en UN SOLO grid de 2 columnas continuo:
  /// como [FeedMixer] intercala bloques de tamaño variable (2-4 productos,
  /// 1-3 búsquedas...), agrupar cada bloque en su propio `SliverGrid`
  /// dejaba el último ítem de cualquier bloque de tamaño impar solo en su
  /// fila — con la celda vecina en blanco, rompiendo visualmente el patrón
  /// de 2 columnas en medio del feed. Por eso acá se arma UN run de grid
  /// que abarca todos los ítems grid-eables consecutivos, sin importar si
  /// cambian de tipo (producto → búsqueda → producto) dentro del mismo run;
  /// el tipo de cada ítem solo decide qué card dibuja `itemBuilder`, nunca
  /// cuántas columnas ocupa.
  ///
  /// Los negocios SÍ cortan ese grid a propósito — `_BusinessCard` es una
  /// tarjeta ancha con varios productos adentro, pensada para verse a todo
  /// el ancho (`SliverToBoxAdapter`), no para una celda de grid angosta.
  /// Cada vez que aparece un negocio se cierra el run de grid en curso y se
  /// retoma uno nuevo después.
  ///
  /// `productOffset` lleva la cuenta global de productos ya renderizados
  /// para que la animación de stagger siga una progresión continua aunque
  /// los productos estén repartidos en varios runs a lo largo del feed.
  List<Widget> _buildFeedSlivers(
    BuildContext context,
    List<FeedItem> feedItems,
  ) {
    final widgets = <Widget>[];
    var productOffset = 0;
    var i = 0;

    while (i < feedItems.length) {
      final item = feedItems[i];

      if (item.type == FeedItemType.business) {
        final entry = item.data as MapEntry<Seller, List<Product>>;
        widgets.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: _BusinessCard(
                seller: entry.key,
                products: entry.value,
                onProductTap: (p) => _openDetail(context, p),
                onSellerTap: () =>
                    _openSellerProducts(context, entry.key, entry.value),
              ),
            ),
          ),
        );
        i++;
        continue;
      }

      // Run de grid: todos los ítems producto/búsqueda consecutivos, sin
      // cortar por tipo — solo se corta cuando aparece un negocio.
      final runStart = i;
      while (i < feedItems.length &&
          feedItems[i].type != FeedItemType.business) {
        i++;
      }
      final run = feedItems.sublist(runStart, i);

      // Offset de stagger por ítem del run: solo avanza para productos
      // (las búsquedas no animan con _cardAnimValue), -1 para el resto.
      final staggerIndexes = <int>[];
      var productsInRun = 0;
      for (final entry in run) {
        if (entry.type == FeedItemType.product) {
          staggerIndexes.add(productsInRun);
          productsInRun++;
        } else {
          staggerIndexes.add(-1);
        }
      }
      final offset = productOffset;

      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.crossAxisExtent;
              final columns = width >= 720 ? 3 : 2;
              return AnimatedBuilder(
                animation: _staggerController,
                builder: (context, _) {
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 3 ? 0.72 : 0.64,
                    ),
                    itemCount: run.length,
                    itemBuilder: (context, index) {
                      final entry = run[index];
                      if (entry.type == FeedItemType.product) {
                        final product = entry.data as Product;
                        return ProductCard(
                          product: product,
                          onTap: () => _openDetail(context, product),
                          animationValue: _cardAnimValue(
                            offset + staggerIndexes[index],
                          ),
                        );
                      }
                      final post = entry.data as WantedPost;
                      return WantedPostCard(
                        post: post,
                        category: _categoryById(post.categoryId),
                        onTap: () => _openWantedPost(context, post),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      );
      productOffset += productsInRun;
    }

    return widgets;
  }

  MarketplaceCategory? _categoryById(String id) {
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  // Misma pantalla y misma transición que un producto: WantedPost se adapta
  // a la forma de Product para que ambos tipos de publicación se sientan
  // como "la misma publicación" al usuario.
  Future<void> _openWantedPost(BuildContext context, WantedPost post) {
    // Solo refresca el contador de favoritos (lectura local, instantánea):
    // el usuario pudo marcar/desmarcar el producto como favorito en el
    // detalle. No se recarga el feed completo del backend para no
    // reordenar el mezclado (_feedSeed) ni reiniciar la animación de
    // entrada de las tarjetas cada vez que se vuelve al home.
    return Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProductDetailScreen(product: Product.fromWantedPost(post)),
          ),
        )
        .then((_) => _loadFavoriteCount());
  }

  Future<void> _openDetail(BuildContext context, Product product) {
    return Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        )
        .then((_) => _loadFavoriteCount());
  }

  Future<void> _openSellerProducts(
    BuildContext context,
    Seller seller,
    List<Product> products,
  ) async {
    final sorted = List<Product>.from(products)
      ..sort((a, b) => b.isFeatured ? 1 : 0 - (a.isFeatured ? 1 : 0));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SellerProductsScreen(seller: seller, products: sorted),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));
  }

  void _showMockMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HighlightPlansBanner extends StatelessWidget {
  const _HighlightPlansBanner({required this.plans});

  final List<HighlightPlan> plans;

  @override
  Widget build(BuildContext context) {
    final topPlan = plans.first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.trending_up_rounded,
                  color: context.colors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Destaca sin pagar de más',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Desde ${topPlan.price} por ${topPlan.days == 1 ? '24h' : '${topPlan.days} días'}; también hay plan mensual.',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final plan in plans)
                _HighlightPlanChip(label: plan.title, value: plan.price),
            ],
          ),
        ],
      ),
    );
  }
}

class _HighlightPlanChip extends StatelessWidget {
  const _HighlightPlanChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.border),
      ),
      child: Text(
        '$label · $value',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: context.colors.accent,
        ),
      ),
    );
  }
}

class _FavHeaderButton extends StatelessWidget {
  const _FavHeaderButton({required this.itemCount, required this.onTap});

  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onTap,
      icon: Badge.count(
        count: itemCount,
        isLabelVisible: itemCount > 0,
        backgroundColor: AppColors.danger,
        child: const Icon(Icons.favorite_outline_rounded),
      ),
    );
  }
}

class _CategoryFilterChip extends StatefulWidget {
  const _CategoryFilterChip({required this.category, required this.onClear});

  final MarketplaceCategory category;
  final VoidCallback onClear;

  @override
  State<_CategoryFilterChip> createState() => _CategoryFilterChipState();
}

class _CategoryFilterChipState extends State<_CategoryFilterChip> {
  bool _isFollowing = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    try {
      final interests = await ApiService.getCategoryInterests();
      if (!mounted) return;
      setState(() => _isFollowing = interests.contains(widget.category.id));
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_isFollowing) {
        await ApiService.removeCategoryInterest(widget.category.id);
      } else {
        await ApiService.addCategoryInterest(widget.category.id);
      }
      if (!mounted) return;
      setState(() => _isFollowing = !_isFollowing);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al cambiar seguimiento')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.category.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            widget.category.name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.colors.accent,
            ),
          ),
          const SizedBox(width: 8),
          // Botón de seguir/notificaciones
          GestureDetector(
            onTap: _loading ? null : _toggleFollow,
            child: Icon(
              _isFollowing
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 18,
              color: _isFollowing ? AppColors.primary : context.colors.muted,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: widget.onClear,
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: context.colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.colors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Buscar libros, laptops, tutorias...',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.tune_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryScroller extends StatelessWidget {
  const _CategoryScroller({
    required this.categories,
    this.selectedCategoryId,
    this.onCategoryTap,
  });

  final List<MarketplaceCategory> categories;
  final String? selectedCategoryId;
  final void Function(String)? onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        padding: const EdgeInsets.only(left: 2),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedCategoryId;
          return InkWell(
            onTap: () => onCategoryTap?.call(category.id),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 58,
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.10)
                          : context.colors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : context.colors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Icon(category.icon, color: category.color, size: 22),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primary : context.colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta de negocio con logo + publicaciones.
class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.seller,
    required this.products,
    required this.onProductTap,
    required this.onSellerTap,
  });

  final Seller seller;
  final List<Product> products;
  final void Function(Product) onProductTap;
  final VoidCallback onSellerTap;

  @override
  Widget build(BuildContext context) {
    final displayProducts = products.take(4).toList();
    final remaining = products.length - displayProducts.length;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.lifted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header: logo + nombre ──────────────────────────
          InkWell(
            onTap: onSellerTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    child: seller.logoUrl != null && seller.logoUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              '${ApiService.baseUrl}${seller.logoUrl}',
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.store_rounded,
                                color: context.colors.accent,
                                size: 22,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.store_rounded,
                            color: context.colors.accent,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                seller.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            if (seller.verified)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: AppColors.teal,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${products.length} publicación${products.length == 1 ? '' : 'es'}',
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              seller.reviews > 0
                                  ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews})'
                                  : 'Sin calificaciones',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.muted.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          // ─── Productos (sin divisor) ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              height: 110,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          displayProducts.length + (remaining > 0 ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index < displayProducts.length) {
                          final product = displayProducts[index];
                          return ProductCard(
                            product: product,
                            width: 118,
                            onTap: () => onProductTap(product),
                            heroEnabled: false,
                          );
                        }
                        // ─── "Ver todo" minimal ───────────────
                        return SizedBox(
                          width: 90,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onSellerTap,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.primary.withValues(
                                    alpha: 0.04,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.grid_view_rounded,
                                        color: context.colors.muted,
                                        size: 20,
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Ver todo',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: context.colors.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pantalla simple que muestra todos los productos de un negocio.
class _SellerProductsScreen extends StatelessWidget {
  const _SellerProductsScreen({required this.seller, required this.products});

  final Seller seller;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.store_rounded,
                size: 16,
                color: context.colors.accent,
              ),
            ),
            const SizedBox(width: 10),
            Text(seller.name),
          ],
        ),
      ),
      body: SafeArea(
        child: products.isEmpty
            ? Center(
                child: Text(
                  'Este negocio aún no tiene publicaciones.',
                  style: TextStyle(color: context.colors.muted),
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 720 ? 3 : 2;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: columns == 3 ? 0.72 : 0.64,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        return ProductCard(
                          product: products[index],
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ProductDetailScreen(
                                  product: products[index],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// Campana de notificaciones en el header del Home.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unreadCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    try {
      final count = await ApiService.getUnreadNotificationCount();
      if (!mounted) return;
      setState(() => _unreadCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) return const SizedBox.shrink();

    return IconButton.outlined(
      onPressed: () {
        widget.onTap();
        // Reset local count after opening
        setState(() => _unreadCount = 0);
      },
      icon: Badge.count(
        count: _unreadCount,
        isLabelVisible: _unreadCount > 0,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

/// Botón para escanear códigos QR de productos.
class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onTap,
      icon: const Icon(Icons.qr_code_scanner_rounded),
      tooltip: 'Escanear QR',
    );
  }
}
