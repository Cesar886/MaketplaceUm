import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/recent_products_service.dart';
import '../widgets/badges.dart';
import '../widgets/product_card.dart';
import 'auth/login_screen.dart';
import 'legal/cookies_screen.dart';
import 'legal/privacy_screen.dart';
import 'legal/terms_screen.dart';
import 'my_listings_screen.dart';
import 'product_detail_screen.dart';
import 'profile/edit_profile_screen.dart';
import 'profile/help_screen.dart';
import 'profile/highlight_plans_screen.dart';
import 'profile/safety_tips_screen.dart';
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
  Seller? _seller;

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
        ApiService.getSeller(sellerId),
      ]);
      if (!mounted) return;
      final seller = results[1] as Seller;
      setState(() {
        _listings = results[0] as List<Product>;
        _sellerRating = seller.rating;
        _sellerReviews = seller.reviews;
        _seller = seller;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  /// Carga (no bloqueante) los productos vistos recientemente, para la
  /// sección "Vistos recientemente" del perfil.
  Future<void> _loadRecentProducts() async {
    try {
      final ids = await RecentProductsService.getRecentIds();
      if (ids.isEmpty) return;

      final all = await ApiService.getProducts();
      final Map<String, Product> productMap = {
        for (final p in all) p.id: p,
      };

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
              const Icon(Icons.person_outline_rounded,
                  size: 64, color: AppColors.muted),
              const SizedBox(height: 16),
              const Text(
                'Inicia sesión para ver tu perfil',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen()),
                ),
                child: const Text('Iniciar sesión'),
              ),
            ],
          ),
        ),
      );
    }

    final user = auth.currentUser!;
    final userName = user['name'] as String;

    // Iniciales para el avatar
    final initials = userName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    final activeCount = _listings
        .where((p) => p.status != ListingStatus.expired)
        .length;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => Future.wait([_loadListings(), _loadRecentProducts()]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            Text('Perfil', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),

            // ─── Card de usuario ────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.12),
                            child: _seller?.logoUrl != null &&
                                    _seller!.logoUrl!.isNotEmpty
                                ? ClipOval(
                                    child: Image.network(
                                      '${ApiService.baseUrl}${_seller!.logoUrl}',
                                      width: 76,
                                      height: 76,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Text(
                                        initials,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          color: AppColors.primaryDark,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: InkWell(
                              onTap: () async {
                                if (_seller == null) return;
                                final result = await Navigator.of(context)
                                    .push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) =>
                                        EditProfileScreen(seller: _seller!),
                                  ),
                                );
                                if (result == true) _loadListings();
                              },
                              customBorder: const CircleBorder(),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
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
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  _typeIcon(auth.accountType),
                                  size: 14,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  auth.accountTypeLabel,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            VerificationStatusBadge(
                              accountType: auth.accountType,
                              verificationStatus: auth.verificationStatus,
                              compact: true,
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
                          label: 'Calificación',
                          icon: Icons.star_rounded,
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: '$_sellerReviews',
                          label: 'Opiniones',
                          icon: Icons.reviews_rounded,
                        ),
                      ),
                      Expanded(
                        child: _ProfileMetric(
                          value: '$activeCount',
                          label: 'Activas',
                          icon: Icons.store_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── Card de verificación ───────────────────────
            _VerificationCard(auth: auth),
            const SizedBox(height: 16),

            // ─── Opciones del perfil ────────────────────────
            _ProfileOption(
              icon: Icons.inventory_2_rounded,
              title: 'Mis publicaciones',
              subtitle: 'Activas, destacadas y expiradas',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const MyListingsScreen()),
              ),
            ),
            _ProfileOption(
              icon: Icons.shield_rounded,
              title: 'Confianza y seguridad',
              subtitle: 'Recomendaciones para comprar en campus',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const SafetyTipsScreen()),
              ),
            ),
            _ProfileOption(
              icon: Icons.payments_rounded,
              title: 'Planes para destacar',
              subtitle: 'Consulta opciones de visibilidad pagada',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const HighlightPlansScreen()),
              ),
            ),
            _ProfileOption(
              icon: Icons.help_rounded,
              title: 'Ayuda',
              subtitle: 'Preguntas frecuentes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
              ),
            ),

            // ─── Vistos recientemente ───────────────────────────
            if (_recentProducts.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Vistos recientemente',
                  style: TextStyle(
                    color: AppColors.muted,
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

            // ─── Modo oscuro ────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 10),
              child: Text(
                'Apariencia',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _DarkModeToggle(),

            // ─── Sección legal ──────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 10),
              child: Text(
                'Legal',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _ProfileOption(
              icon: Icons.description_rounded,
              title: 'Términos y Condiciones',
              subtitle: 'Reglas de uso de la plataforma',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TermsScreen(),
                ),
              ),
            ),
            _ProfileOption(
              icon: Icons.shield_rounded,
              title: 'Política de Privacidad',
              subtitle: 'Protección de tus datos personales',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacyScreen(),
                ),
              ),
            ),
            _ProfileOption(
              icon: Icons.cookie_rounded,
              title: 'Aviso de Cookies',
              subtitle: 'Uso de cookies en la app',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CookiesScreen(),
                ),
              ),
            ),

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
                        builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3)),
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
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.auth});

  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    // Si ya está verificado, mostrar estado positivo
    if (auth.verificationStatus == VerificationStatus.aprobada) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.teal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.teal.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: VerificationStatusBadge(
                accountType: auth.accountType,
                verificationStatus: auth.verificationStatus,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _verifiedTitle(auth),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _verifiedSubtitle(auth),
                    style: const TextStyle(
                      color: AppColors.muted,
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

    // Estado pendiente
    if (auth.verificationStatus == VerificationStatus.pendiente) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded,
                color: AppColors.gold, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verificación en revisión',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 3),
                  Text(
                    'Tus documentos están siendo revisados por el equipo.',
                    style: TextStyle(
                      color: AppColors.muted,
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

    // No iniciada → mostrar opción para verificar
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const _ProfileVerificationRedirect(),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.teal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.teal.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.badge_rounded,
                  color: AppColors.teal),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Verifica tu cuenta',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 3),
                  Text(
                    'Obtén un badge de confianza para tus compradores.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  String _verifiedTitle(AuthProvider auth) {
    switch (auth.accountType) {
      case AccountType.estudiante:
        return 'Credencial universitaria verificada';
      case AccountType.particular:
        return 'Identidad verificada';
      case AccountType.negocio:
        return 'Negocio confirmado';
    }
  }

  String _verifiedSubtitle(AuthProvider auth) {
    switch (auth.accountType) {
      case AccountType.estudiante:
        return 'Badge "Verificado UM" visible para generar confianza.';
      case AccountType.particular:
        return 'Badge "Identidad verificada" activo en tu perfil.';
      case AccountType.negocio:
        return 'Badge "Negocio confirmado" activo en tu perfil.';
    }
  }
}

/// Pantalla temporal de redirección para verificación desde perfil.
/// En una versión completa llevaría a un formulario de verificación.
class _ProfileVerificationRedirect extends StatelessWidget {
  const _ProfileVerificationRedirect();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.badge_rounded,
                  size: 64, color: AppColors.teal),
              const SizedBox(height: 20),
              Text(
                'Verificación de cuenta',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Puedes iniciar tu verificación desde el registro o contactar al administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            child: const Text('Ver todos'),
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
        Icon(icon, color: AppColors.gold),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DarkModeToggle extends StatelessWidget {
  const _DarkModeToggle();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SwitchListTile(
        secondary: Icon(
          theme.darkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          color: AppColors.primary,
        ),
        title: const Text(
          'Modo oscuro',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Cambia el tema de la interfaz'),
        value: theme.darkMode,
        onChanged: (_) => theme.toggleDarkMode(),
        activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
        activeThumbColor: AppColors.primary,
      ),
    );
  }
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap ??
            () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title mock')),
                ),
      ),
    );
  }
}
