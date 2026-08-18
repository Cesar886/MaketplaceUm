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
      if (post.priceMin != null)
        _priceMinController.text = post.priceMin.toString();
      if (post.priceMax != null)
        _priceMaxController.text = post.priceMax.toString();
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
  Widget _buildLocationSection() {
    final auth = context.watch<AuthProvider>();
    if (auth.accountType != AccountType.negocio) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'publish.location_optional'.tr(),
          style: AppTypography.heading(15, color: context.colors.ink),
        ),
        const SizedBox(height: 10),
        if (_hasSavedSellerLocation) ...[
          RadioListTile<_LocationChoice>(
            contentPadding: EdgeInsets.zero,
            value: _LocationChoice.useSaved,
            groupValue: _locationChoice,
            onChanged: (v) => setState(() => _locationChoice = v!),
            title: Text('publish.use_business_location'.tr()),
            subtitle: Text('publish.use_business_location_hint'.tr()),
          ),
          RadioListTile<_LocationChoice>(
            contentPadding: EdgeInsets.zero,
            value: _LocationChoice.custom,
            groupValue: _locationChoice,
            // No marca el radio de inmediato: solo cambia a "custom" si el
            // usuario efectivamente confirma un punto en el selector (ver
            // _pickCustomLocation). Si cancela, el estado no queda a medias
            // (radio en "custom" pero sin coordenadas → se perdería la
            // ubicación silenciosamente al publicar).
            onChanged: (_) => _pickCustomLocation(),
            title: Text('wanted.choose_other_location'.tr()),
          ),
          RadioListTile<_LocationChoice>(
            contentPadding: EdgeInsets.zero,
            value: _LocationChoice.none,
            groupValue: _locationChoice,
            onChanged: (v) => setState(() => _locationChoice = v!),
            title: Text('publish.no_location'.tr()),
          ),
        ] else
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
  Widget _buildPaymentMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'wanted.payment_methods_optional'.tr(),
          style: AppTypography.heading(15, color: context.colors.ink),
        ),
        const SizedBox(height: 4),
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
          value: _customizePaymentMethods,
          onChanged: (value) => setState(() {
            _customizePaymentMethods = value;
            if (!value) _showPaymentMethodsError = false;
          }),
          title: Text('wanted.customize_payment_methods'.tr()),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'wanted.edit_title'.tr() : 'nav.publish_wanted'.tr(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'producto',
                label: Text('wanted.type_product'.tr()),
              ),
              ButtonSegment(
                value: 'servicio',
                label: Text('wanted.type_service'.tr()),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'wanted.what_field'.tr(),
              hintText: 'wanted.what_hint'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'wanted.description_optional'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCategoryId,
            decoration: InputDecoration(
              labelText: 'publish.field_category'.tr(),
            ),
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
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(category.name),
                    ],
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _selectedCategoryId = value),
          ),
          const SizedBox(height: 12),
          Row(
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
              const SizedBox(width: 12),
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
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            _buildLocationSection(),
          ],
          const SizedBox(height: 16),
          _buildPaymentMethodsSection(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _publishing ? null : _publish,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
            ),
            child: _publishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isEditing
                        ? 'publish.save_changes'.tr()
                        : 'nav.publish_wanted'.tr(),
                  ),
          ),
        ],
      ),
    );
  }
}
