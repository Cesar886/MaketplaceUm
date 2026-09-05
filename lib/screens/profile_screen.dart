import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../features/highlight/destacar_flag.dart';
import '../models.dart';
import '../providers/accent_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/recent_products_service.dart';
import '../widgets/badges.dart';
import '../widgets/option_tile.dart';
import '../widgets/product_card.dart';
import '../widgets/profile_banner.dart';
import '../widgets/user_role.dart';
import 'auth/login_screen.dart';
import 'auth/verification_screen.dart';
import 'my_listings_screen.dart';
import 'product_detail_screen.dart';
import 'profile/edit_profile_screen.dart';
import 'profile/highlight_plans_screen.dart';
import 'profile/my_comments_screen.dart';
import 'profile/report_problem_screen.dart';
import 'profile/settings_screen.dart';
import 'recent_products_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Product> _listings = [];
  List<Product> _recentProducts = [];
  double _sellerRating = 0.0;
  int _sellerReviews = 0;
  int _sellerProfileViews = 0;
  Seller? _seller;
  bool _loadingSellerForEdit = false;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadRecentProducts();
  }

  Future<void> _loadListings() async {
    final sellerId = context.read<AuthProvider>().backendSellerId;
    if (sellerId == null) return;
    try {
      final results = await Future.wait([
        ApiService.getProducts(seller: sellerId),
        ApiService.getMyProfile(sellerId),
      ]);
      if (!mounted) return;
      final seller = results[1] as Seller;
      setState(() {
        _listings = results[0] as List<Product>;
        _sellerRating = seller.rating;
        _sellerReviews = seller.reviews;
        _sellerProfileViews = seller.profileViews;
        _seller = seller;
      });
      // El perfil del backend manda sobre el caché local: es lo que hace que
      // un color elegido en otro teléfono aparezca aquí.
      context.read<AccentProvider>().adoptarDe(seller);
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  /// Abre la pantalla de edición de perfil. Si el seller todavía no se
  /// cargó (p. ej. el GET inicial falló por una red lenta o inestable),
  /// reintenta la carga en vez de dejar el botón de editar sin reacción.
  Future<void> _openEditProfile(BuildContext context) async {
    var seller = _seller;
    if (seller == null) {
      setState(() => _loadingSellerForEdit = true);
      await _loadListings();
      seller = _seller;
      if (!mounted) return;
      setState(() => _loadingSellerForEdit = false);
      if (seller == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('profile.load_error'.tr())));
        return;
      }
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditProfileScreen(seller: seller!),
      ),
    );
    if (result == true) _loadListings();
  }

  /// Carga (no bloqueante) los productos vistos recientemente, para la
  /// sección "Vistos recientemente" del perfil.
  Future<void> _loadRecentProducts() async {
    try {
      final ids = await RecentProductsService.getRecentIds();
      if (ids.isEmpty) return;

      final all = await ApiService.getProducts();
      final Map<String, Product> productMap = {for (final p in all) p.id: p};

      final recent = <Product>[];
      for (final id in ids) {
        if (recent.length >= 6) break;
        final p = productMap[id];
        if (p != null) recent.add(p);
      }

      if (!mounted) return;
      setState(() => _recentProducts = recent);
    } catch (_) {
      // Sin conexión o error: la sección simplemente no aparece.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isLoggedIn) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 64,
                color: context.colors.muted,
              ),
              const SizedBox(height: 16),
              Text(
                'profile.login_prompt'.tr(),
                style: TextStyle(color: context.colors.muted),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
                child: Text('auth.login_button'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    final user = auth.currentUser!;
    final userName = user['name'] as String;

    // Iniciales para el avatar
    final initials = userName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    final activeCount = _listings
        .where((p) => p.status != ListingStatus.expired)
        .length;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => Future.wait([
          _loadListings(),
          _loadRecentProducts(),
          auth.refrescarEstadoVerificacion(),
        ]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Text(
              'nav.profile'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),

            // ─── Card de usuario ────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // El banner queda detrás de LA FOTO (esta Stack) y no
                      // de toda la fila: el nombre y la insignia se quedan
                      // fuera para que el tratamiento sea idéntico al de
                      // seller_profile_screen (mismo widget, mismo alcance
                      // — solo el avatar, no el bloque completo).
                      ProfileBanner(
                        color: context.colors.primary,
                        fadeTo: context.colors.surface,
                        // Va suelto dentro de un Row (no envuelto en
                        // SizedBox(width: double.infinity) como el banner
                        // del perfil de vendedor), así que debe encogerse al
                        // ancho de la foto en vez de estirarse a todo el
                        // ancho de la tarjeta.
                        expand: false,
                        // El child aquí es solo el avatar (círculo), no un
                        // bloque con nombre/badges: recorte circular, sin
                        // fade, para que el tinte no asome en las esquinas.
                        circular: true,
                        child: Stack(
                          children: [
                            // El anillo va como borde de un contenedor y no
                            // como `border` del CircleAvatar porque el avatar
                            // recorta su hijo: un borde dibujado dentro se
                            // comería 3px de la foto en vez de rodearla.
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: context.accentLine,
                                  width: 3,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 38,
                                backgroundColor: context.colors.primary
                                    .withValues(alpha: 0.12),
                                child:
                                    _seller?.logoUrl != null &&
                                        _seller!.logoUrl!.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          '${ApiService.baseUrl}${_seller!.logoUrl}',
                                          width: 76,
                                          height: 76,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Text(
                                            initials,
                                            style: TextStyle(
                                              fontSize: 22,
                                              color: context.colors.accent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Text(
                                        initials,
                                        style: TextStyle(
                                          fontSize: 22,
                                          color: context.colors.accent,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: _loadingSellerForEdit
                                    ? null
                                    : () => _openEditProfile(context),
                                customBorder: const CircleBorder(),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: context.colors.primary,
                                    shape: BoxShape.circle,
                                    // El botón se apoya sobre el anillo y la
                                    // tarjeta: sin este contorno del color de
                                    // la tarjeta, un relleno pastel se funde
                                    // con el fondo blanco y pierde su forma.
                                    border: Border.all(
                                      color: context.colors.surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: _loadingSellerForEdit
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: context.colors.onPrimary,
                                          ),
                                        )
                                      : Icon(
                                          Icons.edit_rounded,
                                          color: context.colors.onPrimary,
                                          size: 14,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            // El ícono acompaña al subtítulo, así que la fila
                            // entera desaparece cuando no hay rol que mostrar:
                            // un ícono suelto sin texto no dice nada.
                            if (_subtituloRol != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    _typeIcon(auth.accountType),
                                    size: 14,
                                    color: context.colors.muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _subtituloRol!,
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            // En Wrap y no en Column: en una cuenta que
                            // tiene las dos, la insignia del enigma cabe al
                            // lado de la de verificación, y si no cabe baja
                            // sola sin desbordar la tarjeta.
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                // Socio Fundador reemplaza la palomita azul
                                // por la verde: son la misma palomita, nunca
                                // las dos juntas.
                                if (_seller?.socioFundador ?? false)
                                  const InsigniaSocioFundador()
                                else if (auth.isVerified)
                                  InsigniaVerificada(tipo: auth.accountType),
                                if (_seller?.enigmaPosicion != null)
                                  InsigniaEnigma(
                                    posicion: _seller!.enigmaPosicion!,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileMetric(
                          value: _sellerRating.toStringAsFixed(1),
                          label: 'profile.rating'.tr(),
                          icon: Icons.star_rounded,
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: '$_sellerReviews',
                          label: 'profile.reviews'.tr(),
                          icon: Icons.reviews_rounded,
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: '$activeCount',
                          label: 'profile.active_listings'.tr(),
                          icon: Icons.store_rounded,
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: '$_sellerProfileViews',
                          label: 'profile.views'.tr(),
                          icon: Icons.visibility_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Las cuentas externas no participan en la verificación.
            if (auth.puedeVerificarse) ...[
              _VerificationCard(auth: auth, onVerificado: _loadListings),
              const SizedBox(height: 16),
            ],

            // ─── Opciones del perfil ────────────────────────
            OptionTile(
              icon: Icons.inventory_2_rounded,
              title: 'profile.my_listings'.tr(),
              subtitle: 'profile.my_listings_subtitle'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyListingsScreen(),
                ),
              ),
            ),
            // Comentarios RECIBIDOS, no escritos: lo que respalda a un
            // vendedor es lo que otros dijeron de sus publicaciones. Solo
            // aparece con el id del backend ya resuelto — sin él no hay a
            // quién consultarle los comentarios.
            if (auth.backendSellerId != null)
              OptionTile(
                icon: Icons.mode_comment_rounded,
                title: 'profile.comments'.tr(),
                subtitle: 'profile.comments_subtitle'.tr(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MyCommentsScreen(userId: auth.backendSellerId!),
                  ),
                ),
              ),
            OptionTile(
              icon: Icons.flag_rounded,
              title: 'settings.report_problem'.tr(),
              subtitle: 'settings.report_problem_subtitle'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReportProblemScreen(),
                ),
              ),
            ),
            // TODO: Destacar publicaciones pendiente para próxima
            // actualización - no eliminar. La entrada a los planes de
            // destacado queda oculta mientras kDestacarHabilitado sea false;
            // vuelve sola al poner la bandera en true
            // (ver features/highlight/destacar_flag.dart).
            if (kDestacarHabilitado)
              OptionTile(
                icon: Icons.payments_rounded,
                title: 'profile.highlight_plans'.tr(),
                subtitle: 'profile.highlight_plans_subtitle'.tr(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HighlightPlansScreen(),
                  ),
                ),
              ),
            OptionTile(
              icon: Icons.settings_rounded,
              title: 'settings.title'.tr(),
              subtitle: 'profile.settings_subtitle'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),

            // ─── Vistos recientemente ───────────────────────────
            if (_recentProducts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'profile.recently_viewed'.tr(),
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              _RecentlyViewedSection(
                products: _recentProducts,
                onProductTap: (p) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProductDetailScreen(product: p),
                  ),
                ),
                onViewAll: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecentProductsScreen(),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ─── Cerrar sesión ─────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await auth.logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                    (_) => false,
                  );
                },
                icon: const Icon(Icons.logout_rounded),
                label: Text('profile.logout'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(
                    color: AppColors.danger.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(AccountType type) {
    switch (type) {
      case AccountType.estudiante:
        return Icons.school_rounded;
      case AccountType.particular:
        return Icons.person_rounded;
      case AccountType.negocio:
        return Icons.store_rounded;
    }
  }

  /// Bajo el nombre: la carrera, "Personal UM" o la etiqueta de negocio/
  /// particular. Sale de [subtituloRol] — el mismo cálculo que usan el perfil
  /// público y el detalle de producto — para que el copy no se desincronice
  /// entre las tres pantallas.
  ///
  /// Null mientras el seller aún no carga (el GET inicial puede tardar o
  /// fallar) y cuando no hay rol verificado que mostrar; en ambos casos la
  /// línea se omite en vez de enseñar un genérico.
  String? get _subtituloRol => _seller == null ? null : subtituloRol(_seller!);
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.auth, required this.onVerificado});

  final AuthProvider auth;

  /// Recarga el seller del backend. El AuthProvider solo sabe del estado de
  /// verificación; la carrera y el tipo (alumno/personal) llegan en el seller,
  /// y sin esto el subtítulo del perfil seguiría mostrando el valor anterior
  /// hasta volver a abrir la pantalla.
  final Future<void> Function() onVerificado;

  Future<void> _abrirVerificacion(BuildContext context) async {
    final verificado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VerificationScreen(tipo: auth.accountType),
      ),
    );
    // La pantalla ya actualizó el AuthProvider; esto solo cubre el caso de
    // volver con el gesto de retroceso, donde no hubo resultado.
    if (verificado != true) {
      await auth.refrescarEstadoVerificacion();
      return;
    }
    await onVerificado();
  }

  @override
  Widget build(BuildContext context) {
    if (auth.isVerified) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.colors.accent.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InsigniaVerificada(tipo: auth.accountType),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tituloVerificado(auth),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'profile.badge_visible'.tr(),
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // La solicitud manual permanece pendiente hasta que un administrador la
    // aprueba o rechaza. La tarjeta sigue siendo tocable para consultar el
    // estado actualizado dentro del flujo de verificación.
    final pendiente = auth.solicitudManualPendiente;

    // Rechazada: se explica qué corregir y se ofrece reintentar. Solo aplica
    // al flujo de negocio, el único que puede terminar en rechazo.
    final rechazada = auth.estadoVerificacion == 'rechazado';

    return InkWell(
      onTap: () => _abrirVerificacion(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (rechazada ? AppColors.danger : context.colors.accent)
              .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (rechazada ? AppColors.danger : context.colors.accent)
                .withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                rechazada
                    ? Icons.gpp_bad_rounded
                    : pendiente
                    ? Icons.hourglass_top_rounded
                    : Icons.badge_rounded,
                color: rechazada ? AppColors.danger : context.colors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rechazada
                        ? 'profile.fix_verification'.tr()
                        : pendiente
                        ? 'profile.verification_pending'.tr()
                        : 'profile.verify_account'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    rechazada
                        ? auth.motivoRechazo ?? 'profile.verify_hint'.tr()
                        : pendiente
                        ? 'profile.verification_pending_hint'.tr()
                        : 'profile.verify_hint'.tr(),
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }

  String _tituloVerificado(AuthProvider auth) {
    switch (auth.accountType) {
      case AccountType.estudiante:
        return 'badge.verified_student'.tr();
      case AccountType.particular:
        return 'badge.verified_account'.tr();
      case AccountType.negocio:
        return 'badge.verified_business'.tr();
    }
  }
}

/// Fila horizontal con los últimos productos vistos por el usuario,
/// con acceso al historial completo — vive como sección propia del perfil.
class _RecentlyViewedSection extends StatelessWidget {
  const _RecentlyViewedSection({
    required this.products,
    required this.onProductTap,
    required this.onViewAll,
  });

  final List<Product> products;
  final void Function(Product) onProductTap;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return ProductCard(
                product: product,
                width: 140,
                onTap: () => onProductTap(product),
                heroEnabled: false,
              );
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onViewAll,
            child: Text('profile.see_all'.tr()),
          ),
        ),
      ],
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: context.colors.accent),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.colors.accent,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
