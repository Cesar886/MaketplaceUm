import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../features/highlight/destacar_flag.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/anonymous_id.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';
import '../services/favorite_products_service.dart';
import '../services/feed_mixer.dart';
import '../widgets/badges.dart';
import '../widgets/bounce_on_increase.dart';
import '../widgets/category_logo_menu.dart';
import '../widgets/home_grid_skeleton.dart';
import '../widgets/product_card.dart';
import '../widgets/product_grid_metrics.dart';
import '../widgets/wanted_post_card.dart';
import 'main_shell.dart';
import 'product_detail_screen.dart';
import 'qr_scanner_screen.dart';
import 'search_screen.dart';
import 'seller_profile_screen.dart';

/// Qué despliega el logo del home. Las dos opciones están implementadas y
/// comparten datos y callbacks; cambiar de una a otra es cambiar esta línea.
///
/// - [CategoryMenuStyle.dropdown]: overlay compacto que nace en la esquina.
/// - [CategoryMenuStyle.sidebar]: panel lateral con íconos grandes y conteos.
const kEstiloMenuCategorias = CategoryMenuStyle.sidebar;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  List<Product> _products = [];
  List<MarketplaceCategory> _categories = [];
  List<HighlightPlan> _highlightPlans = [];
  List<Seller> _sellers = [];
  List<WantedPost> _wantedPosts = [];
  List<String> _trendingSearches = [];
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

  /// Cada cuánto se re-piden los términos en tendencia del placeholder.
  ///
  /// Va aparte del refresco del feed a propósito: es un solo request diminuto
  /// (una lista de 10 strings), mientras que recargar el home entero re-barajaría
  /// el feed bajo el dedo del usuario. Antes solo se pedían al montar la
  /// pantalla, así que el placeholder se congelaba hasta reabrir la app.
  static const _trendingRefreshInterval = Duration(minutes: 2);

  Timer? _trendingTimer;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: AppAnimations.slow + AppAnimations.staggerDelay * 14,
    );
    _loadData();
    // También al volver de segundo plano: es el momento en que la lista tiene
    // más probabilidad de estar vieja, y el usuario está mirando.
    _lifecycleListener = AppLifecycleListener(onResume: _loadTrending);
    _trendingTimer = Timer.periodic(_trendingRefreshInterval, (_) {
      if (mounted) _loadTrending();
    });
  }

  @override
  void dispose() {
    _trendingTimer?.cancel();
    _lifecycleListener?.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  /// Refresca solo los términos en tendencia. No bloqueante y silencioso: sin
  /// ellos el buscador cae al hint estático, que nunca es motivo de error
  /// visible.
  Future<void> _loadTrending() async {
    try {
      final trending = await ApiService.getTrendingSearches();
      if (!mounted || listEquals(trending, _trendingSearches)) return;
      setState(() => _trendingSearches = trending);
    } catch (_) {
      // Si falla, se conserva la lista anterior.
    }
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
        ApiService.getCategoriesRanked(),
      ]);
      if (!mounted) return;

      // Highlight plans (banners de "destacar publicación") son contenido
      // secundario del home: si el request falla, no debe tapar el feed
      // principal que sí cargó bien — simplemente no se muestran.
      //
      // TODO: Destacar publicaciones pendiente para próxima actualización -
      // no eliminar. Mientras kDestacarHabilitado sea false no se piden los
      // planes, porque el banner que los muestra está oculto y sería un
      // request de más en cada carga del home; la lista queda vacía. Al poner
      // la bandera en true el fetch vuelve solo, sin tocar nada más.
      // Ver features/highlight/destacar_flag.dart.
      List<HighlightPlan> loadedHighlightPlans = [];
      if (kDestacarHabilitado) {
        try {
          loadedHighlightPlans = await ApiService.getHighlightPlans();
        } catch (_) {
          // Si falla, seguimos con lista vacía
        }
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

      // Verificar si el usuario ha publicado artículos.
      //
      // TODO: Destacar publicaciones pendiente para próxima actualización -
      // no eliminar. Este dato existe SOLO para decidir si se muestra el
      // banner de planes, así que mientras kDestacarHabilitado sea false se
      // evita el request extra. Descomentar junto con la bandera.
      // Ver features/highlight/destacar_flag.dart.
      bool hasPublished = false;
      if (kDestacarHabilitado && auth.isLoggedIn) {
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
      // Ambos no bloqueantes: son adornos del home, no el feed.
      _loadFavoriteCount();
      _loadTrending();
    } catch (e, stack) {
      if (!mounted) return;
      // El detalle técnico (ej. "ClientException: Connection closed...") ya
      // se reintentó automáticamente en ApiService antes de llegar aquí, y
      // acá se queda en el backend: al usuario solo le llega el mensaje
      // amigable de mensajeDeError.
      setState(() {
        _loading = false;
        _error = mensajeDeError(
          e,
          stack: stack,
          fallback: 'home.load_error'.tr(),
        );
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
                  label: Text('common.retry'.tr()),
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
    // TODO: Destacar publicaciones pendiente para próxima actualización -
    // no eliminar. El home excluye del feed a los productos destacados
    // (porque irían en su propio bloque), pero con la feature apagada ya no
    // hay forma de quitarle el destacado a una publicación desde la app: si
    // se siguiera filtrando, las que quedaron con isFeatured = true en la
    // base se volverían invisibles de forma permanente. Por eso, mientras
    // kDestacarHabilitado sea false, se muestran como publicaciones normales
    // (sin badge). Ver features/highlight/destacar_flag.dart.
    final recent = kDestacarHabilitado
        ? filtered.where((p) => !p.isFeatured).toList()
        : filtered;

    // El header navy se dibuja HASTA el borde superior (top: false) y se
    // come el inset de la barra de estado él mismo. Es lo que hace que la
    // marca se lea como una banda de la app y no como un logo suelto sobre
    // fondo blanco de plantilla.
    return SafeArea(
      key: const ValueKey('home-content'),
      top: false,
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _NavyHeader(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // El logo es el acceso a todas las categorías. Va
                        // dentro de un Expanded para que los botones de la
                        // derecha no se muevan, pero alineado a la izquierda:
                        // el menú se ancla a su borde, no al centro del hueco.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: CategoryLogoMenu(
                              categories: _categories,
                              selectedCategoryId: _selectedCategoryId,
                              onCategorySelected: _filtrarPorCategoria,
                              onClearCategory: _quitarFiltroDeCategoria,
                              style: kEstiloMenuCategorias,
                              countFor: _publicacionesPorCategoria,
                            ),
                          ),
                        ),
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
                    _SearchBox(
                      trendingTerms: _trendingSearches,
                      onTap: () => _openSearch(context),
                    ),
                  ],
                ),
              ),
            ),
            // Las categorías salen de la banda navy: son contenido
            // navegable, no cromo de marca, y sobre el fondo claro se
            // distinguen de lo que es header fijo.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CategoryScroller(
                      categories: _categories,
                      selectedCategoryId: _selectedCategoryId,
                      onCategoryTap: (id) {
                        // Tap en la categoría ya filtrada → limpiar filtro.
                        // Ese "des-seleccionar" solo existe en la fila: en el
                        // menú del logo la salida es explícita ("Ver todo"),
                        // porque ahí el ítem seleccionado no está a la vista
                        // cuando se abre y volver a tocarlo no se leería como
                        // apagar nada.
                        if (_selectedCategoryId == id) {
                          ApiService.registerCategoryTap(id);
                          _quitarFiltroDeCategoria();
                        } else {
                          _filtrarPorCategoria(id);
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
            // TODO: Destacar publicaciones pendiente para próxima
            // actualización - no eliminar. El banner CTA de planes queda
            // oculto mientras kDestacarHabilitado sea false; vuelve solo al
            // poner la bandera en true
            // (ver features/highlight/destacar_flag.dart).
            if (kDestacarHabilitado &&
                _highlightPlans.isNotEmpty &&
                _hasPublished)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: _HighlightPlansBanner(plans: _highlightPlans),
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
            //
            // applyFeedLayoutRules es un paso de post-proceso sobre la lista
            // ya mezclada: no toca el ranking ni la mezcla, solo corrige las
            // posiciones de negocio que violan las reglas de presentación
            // (nada de negocios en los primeros kFeedTopItemsNoBusiness
            // ítems, ni dos negocios sin publicaciones entre medio). Vive
            // acá afuera del mezclador para poder probarse en aislamiento
            // — ver test/feed_layout_rules_test.dart.
            ..._buildFeedSlivers(
              context,
              applyFeedLayoutRules(
                FeedMixer(
                  products: recent,
                  wantedPosts: _wantedPosts,
                  businesses: _businessesWithProducts,
                  seed: _feedSeed,
                ).getAll(),
              ),
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
              final columns = ProductGridMetrics.columnsFor(width);
              return AnimatedBuilder(
                animation: _staggerController,
                builder: (context, _) {
                  return SliverGrid.builder(
                    gridDelegate: ProductGridMetrics.delegateFor(columns),
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

  /// Cuántas publicaciones del feed ya cargado caen en una categoría.
  ///
  /// Se cuenta sobre `_products` —lo que el usuario realmente puede ver ahora
  /// mismo— y no sobre un total del backend: el número al lado del nombre
  /// promete "esto es lo que vas a encontrar si entras", y un total remoto
  /// mayor que el feed rompería esa promesa. Mientras el feed esté vacío
  /// (primera carga) no se pinta nada en vez de mostrar ceros.
  int? _publicacionesPorCategoria(String categoryId) {
    if (_products.isEmpty) return null;
    return _products.where((p) => p.category.id == categoryId).length;
  }

  /// Filtra el feed por una categoría.
  ///
  /// Único camino para entrar al filtro, lo dispare la fila horizontal o el
  /// menú del logo: los dos tienen que registrar el tap para el ranking de
  /// `getCategoriesRanked()`, no solo uno.
  void _filtrarPorCategoria(String categoryId) {
    ApiService.registerCategoryTap(categoryId);
    setState(() => _selectedCategoryId = categoryId);
  }

  void _quitarFiltroDeCategoria() {
    setState(() => _selectedCategoryId = null);
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
    if (seller.id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SellerProfileScreen(sellerId: seller.id),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));
  }
}

// TODO: Destacar publicaciones pendiente para próxima actualización - no
// eliminar. Este banner y sus chips no se renderizan mientras
// kDestacarHabilitado sea false; se reactivan al poner la bandera en true
// (ver features/highlight/destacar_flag.dart).
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
                  color: context.colors.primary.withValues(alpha: 0.12),
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
                      'home.highlight_cta_title'.tr(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'home.highlight_cta_subtitle'.tr(
                        namedArgs: {
                          'price': '${topPlan.price}',
                          'duration': topPlan.days == 1
                              ? 'home.duration_24h'.tr()
                              : 'home.duration_days'.tr(
                                  namedArgs: {'days': '${topPlan.days}'},
                                ),
                        },
                      ),
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

/// Banda navy del home: marca + búsqueda sobre fondo sólido, extendida por
/// debajo de la barra de estado.
///
/// Lleva su propio [AnnotatedRegion] porque el shell declara íconos oscuros
/// para las pestañas de fondo claro; sobre esta banda oscura harían falta
/// claros, y el anidado más profundo es el que gana en la región que cubre.
class _NavyHeader extends StatelessWidget {
  const _NavyHeader({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Solo la mitad de arriba: la barra de navegación de abajo la sigue
      // declarando el shell, que es quien la pinta.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: context.colors.primary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.primary,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          18,
          MediaQuery.paddingOf(context).top + 14,
          18,
          18,
        ),
        child: child,
      ),
    );
  }
}

/// Botón de ícono del header: contorno claro sobre el navy, para que los
/// tres (QR, campana, favoritos) se lean como un grupo y no como tres
/// controles sueltos de distinto peso.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    Widget content = Icon(icon, size: 20, color: Colors.white);

    if (badgeCount > 0) {
      // Misma regla que el badge de la barra de navegación. Estos botones
      // viven sobre el header pintado con `colors.primary`, así que el badge
      // en `colors.primary` desaparecía dentro de él (1.00:1).
      final contador = context.colors.contadorSobrePrimary;
      content = Badge.count(
        count: badgeCount,
        backgroundColor: contador.fondo,
        textColor: contador.texto,
        child: content,
      );
    }

    // El rebote va por fuera del badge para que la burbuja del contador
    // crezca junto con el ícono: animar solo el ícono deja el número quieto
    // a un lado y el conjunto se ve descoyuntado.
    //
    // Sin háptico: aquí el contador sube al VOLVER del detalle, no bajo el
    // dedo del usuario. Ver BounceOnIncrease.haptic.
    content = BounceOnIncrease(value: badgeCount, child: content);

    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Center(child: content)),
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
    return _HeaderIconButton(
      icon: Icons.favorite_outline_rounded,
      tooltip: 'nav.favorites'.tr(),
      badgeCount: itemCount,
      onTap: onTap,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('home.follow_error'.tr())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.22),
        ),
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
              color: _isFollowing
                  ? context.colors.primary
                  : context.colors.muted,
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

String _capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.onTap, this.trendingTerms = const []});

  final VoidCallback onTap;
  final List<String> trendingTerms;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  static const _typingSpeed = Duration(milliseconds: 90);
  static const _deletingSpeed = Duration(milliseconds: 45);
  static const _pauseAtFull = Duration(milliseconds: 2200);
  static const _pauseAtEmpty = Duration(milliseconds: 500);
  static const _cursorBlink = Duration(milliseconds: 500);

  Timer? _typeTimer;
  Timer? _cursorTimer;
  int _termIndex = 0;
  int _charCount = 0;
  bool _deleting = false;
  bool _cursorVisible = true;

  @override
  void didUpdateWidget(covariant _SearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.trendingTerms, widget.trendingTerms)) {
      _termIndex = 0;
      _charCount = 0;
      _deleting = false;
      _restartTyping();
    }
  }

  @override
  void initState() {
    super.initState();
    _restartTyping();
    _cursorTimer = Timer.periodic(_cursorBlink, (_) {
      if (!mounted) return;
      setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  void _restartTyping() {
    _typeTimer?.cancel();
    if (widget.trendingTerms.isEmpty) return;
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    final term = widget.trendingTerms[_termIndex % widget.trendingTerms.length];
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
    final terms = widget.trendingTerms;
    final term = terms[_termIndex % terms.length];
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
          _termIndex = (_termIndex + 1) % terms.length;
        }
      }
    });
    _scheduleNextTick();
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _cursorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terms = widget.trendingTerms;
    // El backend ya garantiza contenido dinámico: si nadie ha buscado
    // todavía, devuelve las categorías con producto activo. Este texto fijo
    // solo se ve sin red o con el catálogo vacío — nunca en operación normal.
    final hasTerms = terms.isNotEmpty;
    final displayText = hasTerms
        ? _capitalize(terms[_termIndex % terms.length]).substring(0, _charCount)
        : 'home.search_placeholder'.tr();

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: context.colors.border),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.colors.muted),
              SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RichText(
                    textAlign: TextAlign.left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        color: context.colors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(text: displayText),
                        if (hasTerms)
                          TextSpan(
                            text: '▏',
                            style: TextStyle(
                              color: _cursorVisible
                                  ? context.colors.primary
                                  : Colors.transparent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Icon(Icons.tune_rounded, color: context.colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryScroller extends StatefulWidget {
  const _CategoryScroller({
    required this.categories,
    this.selectedCategoryId,
    this.onCategoryTap,
  });

  final List<MarketplaceCategory> categories;
  final String? selectedCategoryId;
  final void Function(String)? onCategoryTap;

  @override
  State<_CategoryScroller> createState() => _CategoryScrollerState();
}

class _CategoryScrollerState extends State<_CategoryScroller> {
  final _controller = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Arranque leve y automático hacia la derecha para insinuar que la
    // fila es desplazable: muchas categorías quedan fuera de pantalla y sin
    // esta pista una fila de íconos se lee como estática.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoScroll());
  }

  void _startAutoScroll() {
    if (!mounted || !_controller.hasClients) return;
    final maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final startOffset = 40.0.clamp(0.0, maxExtent);
    _controller.jumpTo(startOffset);
    _timer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        itemCount: widget.categories.length,
        padding: const EdgeInsets.only(left: 2),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = widget.categories[index];
          final selected = category.id == widget.selectedCategoryId;
          return InkWell(
            onTap: () => widget.onCategoryTap?.call(category.id),
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
                          ? context.colors.primary.withValues(alpha: 0.10)
                          : context.colors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? context.colors.primary
                            : context.colors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      category.icon,
                      color: normalizeCategoryColor(
                        category.color,
                        Theme.of(context).brightness,
                      ),
                      size: 22,
                    ),
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
                      color: selected
                          ? context.colors.primary
                          : context.colors.ink,
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.lifted,
      ),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onSellerTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header: logo + nombre ──────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: context.colors.primary.withValues(
                        alpha: 0.08,
                      ),
                      child:
                          seller.logoUrl != null && seller.logoUrl!.isNotEmpty
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
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: InsigniaVerificada.desdeTipo(
                                    seller.tipoCuenta,
                                    compact: true,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'listings.count'.plural(products.length),
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: context.colors.accent,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                seller.reviews > 0
                                    ? '${seller.rating.toStringAsFixed(1)} (${seller.reviews})'
                                    : 'home.no_ratings'.tr(),
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
              // ─── Productos (sin divisor) ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 175,
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
                                width: 130,
                                onTap: () => onProductTap(product),
                                heroEnabled: false,
                                dense: true,
                                showPrice: false,
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
                                      color: context.colors.primary.withValues(
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
                                            'common.see_all'.tr(),
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

    return _HeaderIconButton(
      icon: Icons.notifications_outlined,
      tooltip: 'nav.notifications'.tr(),
      badgeCount: _unreadCount,
      onTap: () {
        widget.onTap();
        // Reset local count after opening
        setState(() => _unreadCount = 0);
      },
    );
  }
}

/// Botón para escanear códigos QR de productos.
class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HeaderIconButton(
      icon: Icons.qr_code_scanner_rounded,
      tooltip: 'nav.scan_qr'.tr(),
      onTap: onTap,
    );
  }
}
