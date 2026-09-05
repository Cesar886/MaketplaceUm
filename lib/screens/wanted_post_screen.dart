import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../mock_data.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';
import '../widgets/location_picker.dart';
import '../widgets/payment_methods.dart';
import '../widgets/publish_auth_gate.dart';
import '../widgets/publish_form_skeleton.dart';
import '../widgets/static_mini_map.dart';

/// Elección de ubicación para una publicación de negocio (Nivel 2): usar la
/// ubicación guardada en el perfil, elegir una puntual para esta
/// publicación, o no agregar ninguna.
enum _LocationChoice { useSaved, custom, none }

class WantedPostScreen extends StatefulWidget {
  const WantedPostScreen({super.key, this.editingPost});

  /// Si viene no-nulo, la pantalla entra en modo edición: precarga los
  /// campos de esta publicación y el botón llama a PUT en vez de POST.
  final WantedPost? editingPost;

  @override
  State<WantedPostScreen> createState() => _WantedPostScreenState();
}

class _WantedPostScreenState extends State<WantedPostScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceMinController = TextEditingController();
  final _priceMaxController = TextEditingController();

  List<MarketplaceCategory> _categories = [];
  String? _selectedCategoryId;
  String _type = 'producto';
  bool _loading = true;
  bool _publishing = false;

  // ─── Ubicación puntual de la publicación (Nivel 2, solo negocios) ──
  double? _savedSellerLat;
  double? _savedSellerLng;
  bool get _hasSavedSellerLocation =>
      _savedSellerLat != null && _savedSellerLng != null;
  _LocationChoice _locationChoice = _LocationChoice.none;
  double? _customLocationLat;
  double? _customLocationLng;

  // ─── Métodos de pago (opcional, hereda del perfil por defecto) ──
  List<String> _sellerPaymentMethods = [];
  bool _customizePaymentMethods = false;
  final Set<String> _customPaymentMethods = {};
  bool _showPaymentMethodsError = false;

  bool get _isEditing => widget.editingPost != null;

  @override
  void initState() {
    super.initState();
    final post = widget.editingPost;
    if (post != null) {
      _titleController.text = post.title;
      _descriptionController.text = post.description ?? '';
      _type = post.type;
      _selectedCategoryId = post.categoryId;
      if (post.priceMin != null) {
        _priceMinController.text = post.priceMin.toString();
      }
      if (post.priceMax != null) {
        _priceMaxController.text = post.priceMax.toString();
      }
      _sellerPaymentMethods = post.sellerObj?.paymentMethods ?? [];
      if (post.paymentMethods != null) {
        _customizePaymentMethods = true;
        _customPaymentMethods.addAll(post.paymentMethods!);
      }
    }
    _loadCategories();
    _loadSellerLocation();
  }

  Future<void> _loadSellerLocation() async {
    if (_isEditing) return;
    final auth = context.read<AuthProvider>();
    if (auth.backendSellerId == null) return;
    try {
      final seller = await ApiService.getSeller(auth.backendSellerId!);
      if (!mounted) return;
      setState(() {
        _sellerPaymentMethods = seller.paymentMethods;
        if (auth.accountType != AccountType.negocio) return;
        _savedSellerLat = seller.locationLat;
        _savedSellerLng = seller.locationLng;
        if (_hasSavedSellerLocation) {
          _locationChoice = _LocationChoice.useSaved;
        }
      });
    } catch (_) {
      // Sin perfil disponible: el formulario simplemente no ofrece
      // "usar la ubicación/métodos guardados", no bloquea el resto.
    }
  }

  Future<void> _pickCustomLocation() async {
    final picked = await LocationPickerScreen.open(
      context,
      initialLat: _customLocationLat,
      initialLng: _customLocationLng,
      title: 'wanted.location_title'.tr(),
    );
    if (picked != null) {
      setState(() {
        _customLocationLat = picked.latitude;
        _customLocationLng = picked.longitude;
        _locationChoice = _LocationChoice.custom;
      });
    }
  }

  (double, double)? get _resolvedLocation {
    switch (_locationChoice) {
      case _LocationChoice.useSaved:
        if (_hasSavedSellerLocation) {
          return (_savedSellerLat!, _savedSellerLng!);
        }
        return null;
      case _LocationChoice.custom:
        if (_customLocationLat != null && _customLocationLng != null) {
          return (_customLocationLat!, _customLocationLng!);
        }
        return null;
      case _LocationChoice.none:
        return null;
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.getCategories();
      if (!mounted) return;
      setState(() => _aplicarCategorias(categories));
    } catch (_) {
      // Respaldo local, igual que publish_product_screen.
      //
      // Sin él la lista quedaba vacía, y un DropdownButton sin items SE
      // AUTO-DESHABILITA: el campo se pintaba con su label "Categoría", el
      // tap no hacía nada y el `catch` mudo no dejaba ni un mensaje. Así se
      // reportó — "no se puede seleccionar una categoría" — sin forma de
      // publicar la búsqueda.
      //
      // `mockCategories` trae los mismos ocho ids que sirve el backend, así
      // que la búsqueda que se publique desde aquí queda igual de bien
      // clasificada que si la lista hubiera llegado por red.
      if (!mounted) return;
      setState(() => _aplicarCategorias(mockCategories));
    }
  }

  /// Fija la lista y deja la selección apuntando a algo que existe en ella.
  ///
  /// La validación importa al editar: la búsqueda pudo guardarse con una
  /// categoría que ya no está en el catálogo, y `DropdownButtonFormField`
  /// revienta si su `value` no coincide con exactamente un item.
  void _aplicarCategorias(List<MarketplaceCategory> categorias) {
    _categories = categorias;
    final vigente =
        _selectedCategoryId != null &&
        categorias.any((c) => c.id == _selectedCategoryId);
    if (!vigente) {
      _selectedCategoryId = categorias.isNotEmpty ? categorias.first.id : null;
    }
    _loading = false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('wanted.error_title_required'.tr());
      return;
    }
    if (_selectedCategoryId == null) {
      _showError('wanted.error_category_required'.tr());
      return;
    }
    if (_customizePaymentMethods && _customPaymentMethods.isEmpty) {
      setState(() => _showPaymentMethodsError = true);
      _showError('wanted.error_payment_required'.tr());
      return;
    }

    setState(() => _publishing = true);
    try {
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();
      final priceMin = double.tryParse(_priceMinController.text.trim());
      final priceMax = double.tryParse(_priceMaxController.text.trim());

      if (_isEditing) {
        // La edición requiere sesión real (JWT), no basta el anonymous id:
        // el backend usa requireAuth para que un no-dueño reciba 403.
        final auth = context.read<AuthProvider>();
        final synced = await auth.ensureBackendSync();
        if (!synced) {
          _showError('errors.auth_expired'.tr());
          return;
        }
        await ApiService.editWantedPost(
          id: widget.editingPost!.id,
          title: title,
          description: description,
          categoryId: _selectedCategoryId!,
          type: _type,
          priceMin: priceMin,
          priceMax: priceMax,
          paymentMethods: _customizePaymentMethods
              ? _customPaymentMethods.toList()
              : null,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('publish.changes_saved'.tr())));
      } else {
        // Publicar también requiere sesión real (JWT): el backend usa
        // requireAuth para que el autor salga del token, no del body.
        final auth = context.read<AuthProvider>();
        final synced = await auth.ensureBackendSync();
        if (!synced) {
          _showError('errors.auth_expired'.tr());
          return;
        }
        final location = _resolvedLocation;
        await ApiService.createWantedPost(
          title: title,
          description: description,
          categoryId: _selectedCategoryId!,
          type: _type,
          priceMin: priceMin,
          priceMax: priceMax,
          locationLat: location?.$1,
          locationLng: location?.$2,
          paymentMethods: _customizePaymentMethods
              ? _customPaymentMethods.toList()
              : null,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('wanted.published'.tr())));
      }
    } catch (e, stack) {
      if (!mounted) return;
      _showError(
        mensajeDeError(
          e,
          stack: stack,
          fallback: _isEditing
              ? 'publish.save_error'.tr()
              : 'wanted.publish_error'.tr(),
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceMinController.dispose();
    _priceMaxController.dispose();
    super.dispose();
  }

  /// Sección de ubicación puntual de la publicación — solo visible para
  /// cuentas de negocio (Nivel 2). Estudiantes/usuarios normales no ven
  /// nada aquí, ni siquiera la opción de agregar ubicación.
  Widget _buildLocationSection({bool showTitle = true}) {
    final auth = context.watch<AuthProvider>();
    if (auth.accountType != AccountType.negocio) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            'publish.location_optional'.tr(),
            style: AppTypography.heading(15, color: context.colors.ink),
          ),
          const SizedBox(height: 10),
        ],
        if (_hasSavedSellerLocation)
          RadioGroup<_LocationChoice>(
            groupValue: _locationChoice,
            onChanged: (value) {
              if (value == null) return;
              if (value == _LocationChoice.custom) {
                _pickCustomLocation();
              } else {
                setState(() => _locationChoice = value);
              }
            },
            child: Column(
              children: [
                RadioListTile<_LocationChoice>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  value: _LocationChoice.useSaved,
                  title: Text('publish.use_business_location'.tr()),
                  subtitle: Text('publish.use_business_location_hint'.tr()),
                ),
                RadioListTile<_LocationChoice>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  value: _LocationChoice.custom,
                  title: Text('wanted.choose_other_location'.tr()),
                ),
                RadioListTile<_LocationChoice>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  value: _LocationChoice.none,
                  title: Text('publish.no_location'.tr()),
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _pickCustomLocation,
            icon: const Icon(Icons.map_outlined),
            label: Text(
              _locationChoice == _LocationChoice.custom
                  ? 'wanted.change_location'.tr()
                  : 'publish.pick_location_map'.tr(),
            ),
          ),
        if (_locationChoice == _LocationChoice.custom &&
            _customLocationLat != null) ...[
          const SizedBox(height: 10),
          StaticMiniMap(
            lat: _customLocationLat,
            lng: _customLocationLng,
            showOpenInMapsButton: false,
            height: 120,
          ),
        ],
      ],
    );
  }

  /// Sección de métodos de pago de la publicación: por defecto hereda los
  /// del perfil; un toggle opcional permite personalizarlos solo para esta
  /// búsqueda.
  Widget _buildPaymentMethodsSection({bool showTitle = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            'wanted.payment_methods_optional'.tr(),
            style: AppTypography.heading(15, color: context.colors.ink),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          _sellerPaymentMethods.isEmpty
              ? 'wanted.payment_from_profile'.tr()
              : 'wanted.payment_using'.tr(
                  namedArgs: {
                    'methods': _sellerPaymentMethods
                        .map((id) => paymentMethodById(id)?.label ?? id)
                        .join(', '),
                  },
                ),
          style: TextStyle(color: context.colors.muted, fontSize: 13),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          value: _customizePaymentMethods,
          onChanged: (value) => setState(() {
            _customizePaymentMethods = value;
            if (!value) _showPaymentMethodsError = false;
          }),
          title: Text('wanted.customize_payment_methods'.tr()),
          activeThumbColor: context.colors.onPrimary,
          activeTrackColor: context.colors.primary,
        ),
        if (_customizePaymentMethods) ...[
          const SizedBox(height: 6),
          PaymentMethodsSelector(
            selected: _customPaymentMethods,
            showError: _showPaymentMethodsError,
            onChanged: (methods) => setState(() {
              _customPaymentMethods
                ..clear()
                ..addAll(methods);
              if (methods.isNotEmpty) _showPaymentMethodsError = false;
            }),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing ? 'wanted.edit_title'.tr() : 'nav.publish_wanted'.tr(),
          ),
        ),
        body: const SafeArea(
          top: false,
          child: PublishFormSkeleton(showPhotos: false, showTypeSelector: true),
        ),
      );
    }
    // Publicar una búsqueda también requiere cuenta (igual que un producto);
    // ver/responder búsquedas de otros no la requiere.
    if (!context.watch<AuthProvider>().isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text('nav.publish_wanted'.tr())),
        body: PublishAuthGate(
          icon: Icons.search_rounded,
          title: 'wanted.auth_gate_title'.tr(),
          subtitle: 'wanted.auth_gate_subtitle'.tr(),
        ),
      );
    }
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'wanted.edit_title'.tr() : 'nav.publish_wanted'.tr(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WantedSectionCard(
                          icon: Icons.tune_rounded,
                          title: 'wanted.type_title'.tr(),
                          subtitle: 'wanted.type_help'.tr(),
                          child: _WantedTypeSelector(
                            selected: _type,
                            onChanged: (value) => setState(() => _type = value),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _WantedSectionCard(
                          icon: Icons.manage_search_rounded,
                          title: 'wanted.details_title'.tr(),
                          subtitle: 'wanted.details_help'.tr(),
                          child: Column(
                            children: [
                              TextField(
                                controller: _titleController,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: 'wanted.what_field'.tr(),
                                  hintText: 'wanted.what_hint'.tr(),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildCategoryField(),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _descriptionController,
                                minLines: 2,
                                maxLines: 3,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: 'wanted.description_optional'.tr(),
                                  alignLabelWithHint: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _WantedSectionCard(
                          icon: Icons.payments_outlined,
                          title: 'wanted.budget_title'.tr(),
                          subtitle: 'wanted.budget_help'.tr(),
                          trailing: _WantedOptionalPill(
                            label: 'common.optional'.tr(),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _priceMinController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    prefixText: r'$ ',
                                    labelText: _type == 'servicio'
                                        ? 'wanted.min_quote'.tr()
                                        : 'wanted.min_price'.tr(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _priceMaxController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    prefixText: r'$ ',
                                    labelText: _type == 'servicio'
                                        ? 'wanted.max_quote'.tr()
                                        : 'wanted.max_price'.tr(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_isEditing &&
                            auth.accountType == AccountType.negocio) ...[
                          const SizedBox(height: 12),
                          _WantedSectionCard(
                            icon: Icons.location_on_rounded,
                            title: 'publish.location_optional'.tr(),
                            trailing: _WantedOptionalPill(
                              label: 'common.optional'.tr(),
                            ),
                            child: _buildLocationSection(showTitle: false),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _WantedSectionCard(
                          icon: Icons.account_balance_wallet_rounded,
                          title: 'wanted.payment_methods_optional'.tr(),
                          trailing: _WantedOptionalPill(
                            label: 'common.optional'.tr(),
                          ),
                          child: _buildPaymentMethodsSection(showTitle: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildSubmitBar(),
        ],
      ),
    );
  }

  Widget _buildCategoryField() {
    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedCategoryId),
      initialValue: _selectedCategoryId,
      isExpanded: true,
      decoration: InputDecoration(labelText: 'publish.field_category'.tr()),
      items: [
        for (final category in _categories)
          DropdownMenuItem(
            value: category.id,
            child: Row(
              children: [
                Icon(
                  category.icon,
                  color: normalizeCategoryColor(
                    category.color,
                    Theme.of(context).brightness,
                  ),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(category.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (value) => setState(() => _selectedCategoryId = value),
    );
  }

  Widget _buildSubmitBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.onPrimary,
                          ),
                        )
                      : Icon(
                          _isEditing
                              ? Icons.check_rounded
                              : Icons.campaign_rounded,
                        ),
                  label: Text(
                    _publishing
                        ? 'publish.saving'.tr()
                        : _isEditing
                        ? 'publish.save_changes'.tr()
                        : 'nav.publish_wanted'.tr(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WantedSectionCard extends StatelessWidget {
  const _WantedSectionCard({
    required this.child,
    this.icon,
    this.title,
    this.subtitle,
    this.trailing,
  });

  final Widget child;
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasHeader = icon != null || title != null || trailing != null;
    return Material(
      color: context.colors.surface,
      elevation: isDark ? 1 : 0.5,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: context.colors.accentTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: context.colors.accent),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            style: AppTypography.heading(
                              15,
                              color: context.colors.ink,
                            ),
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: AppTypography.body(
                              12,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _WantedTypeSelector extends StatelessWidget {
  const _WantedTypeSelector({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _WantedTypeOption(
            icon: Icons.inventory_2_outlined,
            label: 'wanted.type_product'.tr(),
            selected: selected == 'producto',
            onTap: () => onChanged('producto'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _WantedTypeOption(
            icon: Icons.handyman_outlined,
            label: 'wanted.type_service'.tr(),
            selected: selected == 'servicio',
            onTap: () => onChanged('servicio'),
          ),
        ),
      ],
    );
  }
}

class _WantedTypeOption extends StatelessWidget {
  const _WantedTypeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.colors.accentTint : context.colors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? context.colors.accentTintBorder
              : context.colors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: context.colors.accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(
                    13,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: context.colors.ink,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: context.colors.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WantedOptionalPill extends StatelessWidget {
  const _WantedOptionalPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.mutedStrong,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
