import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../mock_data.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/badges.dart';
import '../widgets/location_picker.dart';
import '../widgets/payment_methods.dart';
import '../widgets/publish_auth_gate.dart';
import '../widgets/static_mini_map.dart';

/// Elección de ubicación para una publicación de negocio (Nivel 2): usar la
/// ubicación guardada en el perfil, elegir una puntual para esta
/// publicación, o no agregar ninguna.
enum _LocationChoice { useSaved, custom, none }

class PublishProductScreen extends StatefulWidget {
  const PublishProductScreen({super.key, this.editingProduct});

  /// Si viene no-nulo, la pantalla entra en modo edición: precarga los
  /// campos de este producto y el botón llama a PUT en vez de POST.
  final Product? editingProduct;

  @override
  State<PublishProductScreen> createState() => _PublishProductScreenState();
}

class _PublishProductScreenState extends State<PublishProductScreen> {
  static const List<String> _dayNames = [
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  // Mismos índices que _dayNames (0=lunes..6=domingo), en minúscula y
  // completos para el texto del badge calculado ("Disponible el miércoles").
  static const List<String> _dayFullNames = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  String _selectedCategoryId = 'other';
  final Set<int> _selectedDays = {};
  String? _selectedPlanId;
  List<MarketplaceCategory> _categories = [];
  List<HighlightPlan> _plans = [];
  bool _loading = true;
  bool _publishing = false;

  bool get _isEditing => widget.editingProduct != null;

  // ─── Imágenes reales ─────────────────────────────────────
  // _existingImageUrls: imágenes ya subidas que se conservan (solo en modo
  // edición). _selectedImages: archivos locales nuevos por subir.
  final List<String> _existingImageUrls = [];
  final List<XFile> _selectedImages = [];
  final _picker = ImagePicker();

  // ─── Extras opcionales ───────────────────────────────────
  final List<ProductExtra> _extras = [];
  final _extraNameController = TextEditingController();
  final _extraPriceController = TextEditingController();

  // ─── Stock ─────────────────────────────────────────────
  bool _isStockLimited = false;
  bool _autoResetStock = false;
  final _stockController = TextEditingController();

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

  // ─── Gestión de venta: estado manual pegajoso (solo editable en modo
  // edición) — null significa "sin override, badge calculado automático".
  ManualStatus? _currentStatus;
  bool _updatingStatus = false;

  // ─── Vendedor actual: solo para alimentar el preview del badge calculado
  // (horario de negocio). En edición viene del propio producto; al publicar
  // uno nuevo se carga en _loadData junto con el resto.
  Seller? _seller;

  @override
  void initState() {
    super.initState();
    _prefillFromEditingProduct();
    _loadData();
  }

  /// Si estamos editando, precarga todos los campos con los valores
  /// actuales del producto. La categoría se ajusta de nuevo en _loadData
  /// una vez que la lista de categorías está disponible.
  void _prefillFromEditingProduct() {
    final product = widget.editingProduct;
    if (product == null) return;

    _titleController.text = product.title;
    _descriptionController.text = product.description;
    _priceController.text = product.price.toStringAsFixed(
      product.price == product.price.roundToDouble() ? 0 : 2,
    );
    _selectedCategoryId = product.category.id;
    _selectedDays.addAll(product.availableDays);
    _existingImageUrls.addAll(product.images);
    _extras.addAll(product.extras);
    _sellerPaymentMethods = product.seller.paymentMethods;
    if (product.paymentMethods != null) {
      _customizePaymentMethods = true;
      _customPaymentMethods.addAll(product.paymentMethods!);
    }
    _currentStatus = product.manualStatus;
    _seller = product.seller;

    if (product.stockQuantity != null) {
      _isStockLimited = true;
      _autoResetStock = product.stockResetDaily;
      _stockController.text = product.stockQuantity.toString();
    }
  }

  Future<void> _loadData() async {
    try {
      final auth = context.read<AuthProvider>();
      final results = await Future.wait([
        ApiService.getCategories(),
        ApiService.getHighlightPlans(),
        if (!_isEditing && auth.backendSellerId != null)
          ApiService.getSeller(auth.backendSellerId!),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<MarketplaceCategory>;
        _plans = results[1] as List<HighlightPlan>;
        final editingCategoryId = widget.editingProduct?.category.id;
        if (editingCategoryId != null &&
            _categories.any((c) => c.id == editingCategoryId)) {
          _selectedCategoryId = editingCategoryId;
        } else if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first.id;
        }
        if (results.length > 2) {
          final seller = results[2] as Seller;
          _seller = seller;
          _savedSellerLat = seller.locationLat;
          _savedSellerLng = seller.locationLng;
          if (_hasSavedSellerLocation) {
            _locationChoice = _LocationChoice.useSaved;
          }
          _sellerPaymentMethods = seller.paymentMethods;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Fallback a datos mock si el API falla
      setState(() {
        _categories = mockCategories;
        _plans = highlightPlans;
        if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first.id;
        }
        _loading = false;
      });
    }
  }

  int get _totalImageCount =>
      _existingImageUrls.length + _selectedImages.length;

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(
      limit: 5 - _totalImageCount,
      imageQuality: 80,
    );
    if (picked.isNotEmpty) {
      setState(() => _selectedImages.addAll(picked));
    }
  }

  Future<void> _pickCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _selectedImages.add(picked));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  Future<void> _pickCustomLocation() async {
    final picked = await LocationPickerScreen.open(
      context,
      initialLat: _customLocationLat,
      initialLng: _customLocationLng,
      title: 'Ubicación de esta publicación',
    );
    if (picked != null) {
      setState(() {
        _customLocationLat = picked.latitude;
        _customLocationLng = picked.longitude;
        _locationChoice = _LocationChoice.custom;
      });
    }
  }

  /// Ubicación final a enviar con la publicación, según la elección del
  /// usuario (o null si no aplica / no configuró ninguna).
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

  Future<void> _publish() async {
    if (!_flushPendingExtra()) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final price = _priceController.text.trim();

    if (title.isEmpty) {
      _showError('Escribe un título para el producto');
      return;
    }
    if (description.isEmpty) {
      _showError('Escribe una descripción del producto');
      return;
    }
    if (price.isEmpty) {
      _showError('Escribe el precio del producto');
      return;
    }
    if (_totalImageCount == 0) {
      _showError('Agrega al menos una foto del producto');
      return;
    }
    if (_customizePaymentMethods && _customPaymentMethods.isEmpty) {
      setState(() => _showPaymentMethodsError = true);
      _showError('Selecciona al menos un método de pago para este producto');
      return;
    }

    int? stockQuantity;
    int? stockInitial;
    bool stockResetDaily = false;

    if (_isStockLimited) {
      final parsedStock = int.tryParse(_stockController.text.trim());
      if (parsedStock == null || parsedStock < 0) {
        _showError('Ingresa una cantidad válida para el stock');
        return;
      }
      stockQuantity = parsedStock;
      stockInitial = parsedStock;
      stockResetDaily = _autoResetStock;
    }

    setState(() => _publishing = true);
    try {
      // Asegurar que tenemos un token JWT del backend antes de publicar/editar
      final auth = context.read<AuthProvider>();
      final synced = await auth.ensureBackendSync();
      if (!synced) {
        _showError('Error de autenticación. Vuelve a iniciar sesión.');
        return;
      }

      if (_isEditing) {
        await _submitEdit(
          title: title,
          price: price,
          description: description,
          stockQuantity: stockQuantity,
          stockResetDaily: stockResetDaily,
        );
      } else {
        // El vendedor se obtiene del JWT en el backend (requireAuth),
        // no se envía desde el cliente.
        final location = _resolvedLocation;
        await ApiService.createProduct(
          title: title,
          price: price,
          category: _selectedCategoryId,
          description: description,
          availableDays: _selectedDays.toList()..sort(),
          extras: _extras.map((e) => e.toJson()).toList(),
          imagePaths: _selectedImages.map((xf) => xf.path).toList(),
          stockQuantity: stockQuantity,
          stockResetDaily: stockResetDaily,
          stockInitial: stockInitial,
          locationLat: location?.$1,
          locationLng: location?.$2,
          paymentMethods: _customizePaymentMethods
              ? _customPaymentMethods.toList()
              : null,
        );
        if (!mounted) return;
        _titleController.clear();
        _descriptionController.clear();
        _priceController.clear();
        setState(() => _selectedImages.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto publicado exitosamente')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showError(
        _isEditing
            ? 'Error al guardar los cambios: $e'
            : 'Error al publicar: $e',
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// Aplica los cambios de edición. Los campos generales (título,
  /// descripción, categoría, imágenes, extras, días) van todos en un solo
  /// PUT. El precio y el stock tienen su propia lógica en el backend
  /// (anti-fraude / reset diario) así que se mandan por separado, y si
  /// alguno de esos dos falla, se avisa sin perder el resto de los cambios
  /// ya guardados.
  Future<void> _submitEdit({
    required String title,
    required String price,
    required String description,
    int? stockQuantity,
    required bool stockResetDaily,
  }) async {
    final product = widget.editingProduct!;

    await ApiService.editProduct(
      productId: product.id,
      title: title,
      category: _selectedCategoryId,
      description: description,
      extras: _extras.map((e) => e.toJson()).toList(),
      availableDays: _selectedDays.toList()..sort(),
      existingImageUrls: _existingImageUrls,
      newImagePaths: _selectedImages.map((xf) => xf.path).toList(),
      paymentMethods: _customizePaymentMethods
          ? _customPaymentMethods.toList()
          : null,
    );

    final warnings = <String>[];

    final newPrice = num.tryParse(price);
    if (newPrice != null && newPrice != product.price) {
      try {
        await ApiService.updateProduct(product.id, newPrice);
      } catch (e) {
        warnings.add('El precio no se pudo actualizar: $e');
      }
    }

    final stockChanged = _isStockLimited
        ? (stockQuantity != product.stockQuantity ||
              stockResetDaily != product.stockResetDaily)
        : product.stockQuantity != null;
    if (_isStockLimited && stockChanged && stockQuantity != null) {
      try {
        await ApiService.setProductStock(
          product.id,
          quantity: stockQuantity,
          resetDaily: stockResetDaily,
        );
      } catch (e) {
        warnings.add('El stock no se pudo actualizar: $e');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          warnings.isEmpty
              ? 'Cambios guardados exitosamente'
              : 'Producto actualizado, con avisos: ${warnings.join(' · ')}',
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addExtra() {
    if (_extras.length >= 8) {
      _showError('Máximo 8 extras por producto');
      return;
    }
    final name = _extraNameController.text.trim();
    final priceText = _extraPriceController.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      _showError('Ingresa un precio válido mayor a cero');
      return;
    }
    setState(() {
      _extras.add(ProductExtra(name: name, extraPrice: price));
      _extraNameController.clear();
      _extraPriceController.clear();
    });
  }

  /// Si el usuario escribió un extra pero no tocó "+" antes de guardar, lo
  /// agrega solo en vez de perderlo en silencio — es fácil olvidar ese paso
  /// y el dato ya está escrito, así que no tiene sentido descartarlo.
  /// Devuelve false (y muestra el error correspondiente) si lo que quedó a
  /// medias no se puede completar solo, para no publicar con datos rotos.
  bool _flushPendingExtra() {
    final name = _extraNameController.text.trim();
    final priceText = _extraPriceController.text.trim();
    if (name.isEmpty && priceText.isEmpty) return true;
    if (_extras.length >= 8) {
      _showError('Máximo 8 extras por producto');
      return false;
    }
    if (name.isEmpty) {
      _showError('Falta el nombre del extra que empezaste a agregar');
      return false;
    }
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      _showError('El extra "$name" necesita un precio válido mayor a cero');
      return false;
    }
    setState(() {
      _extras.add(ProductExtra(name: name, extraPrice: price));
      _extraNameController.clear();
      _extraPriceController.clear();
    });
    return true;
  }

  void _removeExtra(int index) {
    setState(() => _extras.removeAt(index));
  }

  /// Réplica simplificada, en el cliente, de la jerarquía de 5 niveles que
  /// calcula el backend (`computeProductStatus` en products.js) — solo para
  /// dar feedback inmediato en el formulario mientras el vendedor ajusta las
  /// reglas, antes de guardar. La fuente de verdad real sigue siendo el
  /// `computed_status` que devuelve el API en cada lectura.
  (ComputedStatus, String?, String?) _computePreviewStatus() {
    if (_currentStatus != null) {
      final mapped = switch (_currentStatus!) {
        ManualStatus.reserved => ComputedStatus.reserved,
        ManualStatus.sold => ComputedStatus.sold,
        ManualStatus.negotiating => ComputedStatus.negotiating,
        ManualStatus.paused => ComputedStatus.paused,
      };
      return (mapped, null, null);
    }

    if (_isStockLimited) {
      final stock = int.tryParse(_stockController.text.trim());
      if (stock != null && stock <= 0) {
        return (ComputedStatus.soldOut, null, null);
      }
    }

    final today = DateTime.now().weekday - 1; // 0=Lun..6=Dom
    if (_selectedDays.isNotEmpty && !_selectedDays.contains(today)) {
      int? nextDay;
      for (var offset = 1; offset <= 7; offset++) {
        final candidate = (today + offset) % 7;
        if (_selectedDays.contains(candidate)) {
          nextDay = candidate;
          break;
        }
      }
      return (
        ComputedStatus.availableOtherDay,
        nextDay != null ? _dayFullNames[nextDay] : null,
        null,
      );
    }

    final seller = _seller;
    if (seller != null &&
        seller.isBusiness &&
        seller.businessHours.isNotEmpty) {
      final range = seller.businessHours[today];
      if (range == null) {
        return (ComputedStatus.closed, null, null);
      }
      final now = DateTime.now();
      final openParts = range.open.split(':');
      final closeParts = range.close.split(':');
      final openMinutes =
          int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMinutes =
          int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMinutes = now.hour * 60 + now.minute;
      if (nowMinutes < openMinutes) {
        return (ComputedStatus.closed, null, range.open);
      }
      if (nowMinutes >= closeMinutes) {
        return (ComputedStatus.closed, null, null);
      }
    }

    return (ComputedStatus.available, null, null);
  }

  Widget _buildStatusPreview() {
    final (status, nextDay, opensAt) = _computePreviewStatus();
    return Row(
      children: [
        Text(
          'Así se verá: ',
          style: TextStyle(
            color: context.colors.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        AvailabilityBadge(
          status: status,
          nextAvailableDay: nextDay,
          opensAt: opensAt,
        ),
      ],
    );
  }

  /// Agrupa las reglas que alimentan el cálculo automático del badge —
  /// días disponibles e inventario (el horario, cuando aplica, sale del
  /// perfil de negocio y no se edita aquí). No son botones de estado por sí
  /// mismos: son insumos de [computedStatus]. Ver [_buildStatusSection]
  /// para la intervención manual que sí sobreescribe el badge.
  Widget _buildAvailabilityRulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reglas de disponibilidad', style: AppTypography.heading(15)),
        const SizedBox(height: 4),
        Text(
          'El badge que ven los demás se calcula solo a partir de estas reglas (y del horario del negocio, si aplica).',
          style: TextStyle(color: context.colors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        _buildDaySelector(),
        const SizedBox(height: 12),
        _buildStockSection(),
        const SizedBox(height: 12),
        _buildStatusPreview(),
      ],
    );
  }

  Widget _buildDaySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: context.colors.muted,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Días disponibles',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text(
                _selectedDays.isEmpty
                    ? 'Opcional · todos los días'
                    : '${_selectedDays.length}/7',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(7, (i) {
              final selected = _selectedDays.contains(i);
              return FilterChip(
                label: Text(_dayNames[i], style: const TextStyle(fontSize: 12)),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : context.colors.ink,
                ),
                side: BorderSide(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : context.colors.border,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedDays.add(i);
                    } else {
                      _selectedDays.remove(i);
                    }
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStockSection() {
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Inventario', style: AppTypography.heading(15)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '¿Tiene cantidad limitada?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Útil si tienes un número fijo de unidades.',
              style: TextStyle(fontSize: 12),
            ),
            value: _isStockLimited,
            onChanged: (val) => setState(() => _isStockLimited = val),
            activeColor: AppColors.primary,
          ),
          if (_isStockLimited) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _stockController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad disponible hoy',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '¿Se reinicia automáticamente cada día?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'El stock volverá a esta cantidad a medianoche.',
                style: TextStyle(fontSize: 12),
              ),
              value: _autoResetStock,
              onChanged: (val) => setState(() => _autoResetStock = val),
              activeColor: AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExtrasSection() {
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add_box_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Extras opcionales',
                  style: AppTypography.heading(15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Opcional',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r'Tu producto tiene variantes? Agrega extras como "Con estuche +$25", "Impresion a color +$10"',
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // Lista de extras agregados
          ...List.generate(_extras.length, (i) {
            final extra = _extras[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < _extras.length - 1 ? 8 : 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      extra.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '+${Product.formatPrice(extra.extraPrice)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.colors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _removeExtra(i),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_extras.isNotEmpty) const SizedBox(height: 10),
          // Agregar nuevo extra
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _extraNameController,
                  decoration: const InputDecoration(
                    hintText: 'Nombre del extra',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _extraPriceController,
                  decoration: const InputDecoration(
                    hintText: '+ \$0',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _extras.length >= 8
                    ? context.colors.border
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _extras.length >= 8 ? null : _addExtra,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.add_rounded,
                      color: _extras.length >= 8
                          ? context.colors.muted
                          : AppColors.primary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _extraNameController.dispose();
    _extraPriceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (!auth.isLoggedIn) {
      content = const PublishAuthGate(
        icon: Icons.add_circle_outline_rounded,
        title: 'Crea tu cuenta para publicar',
        subtitle:
            'Regístrate para publicar tu producto y que otros estudiantes lo vean. Ver el feed y contactar vendedores no requiere cuenta.',
      );
    } else {
      content = _buildForm();
    }

    // El modo "publicar" vive embebido en la pestaña de MainShell, que ya
    // provee su propio Scaffold/fondo. El modo "editar" en cambio se abre
    // como ruta independiente desde ProductDetailScreen, así que necesita
    // su propio Scaffold + AppBar (título, botón de regreso) y una barra
    // de guardado fija para no perderla al final de un formulario largo.
    if (!_isEditing) {
      return SafeArea(child: content);
    }

    final showSaveBar = !_loading && auth.isLoggedIn;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Editar producto'), centerTitle: false),
      body: SafeArea(top: false, child: content),
      bottomNavigationBar: showSaveBar ? _buildEditSaveBar() : null,
    );
  }

  Widget _buildEditSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(
            top: BorderSide(color: context.colors.border, width: 0.8),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _publishing
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _publishing ? null : _publish,
                icon: _publishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_publishing ? 'Guardando...' : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
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
        Text('Ubicación (opcional)', style: AppTypography.heading(15)),
        const SizedBox(height: 10),
        if (_hasSavedSellerLocation) ...[
          RadioListTile<_LocationChoice>(
            contentPadding: EdgeInsets.zero,
            value: _LocationChoice.useSaved,
            groupValue: _locationChoice,
            onChanged: (v) => setState(() => _locationChoice = v!),
            title: const Text('Usar la ubicación de mi negocio'),
            subtitle: const Text('Recomendado — un solo tap'),
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
            title: const Text('Elegir otra ubicación para esta publicación'),
          ),
          RadioListTile<_LocationChoice>(
            contentPadding: EdgeInsets.zero,
            value: _LocationChoice.none,
            groupValue: _locationChoice,
            onChanged: (v) => setState(() => _locationChoice = v!),
            title: const Text('No agregar ubicación'),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: _pickCustomLocation,
            icon: const Icon(Icons.map_outlined),
            label: Text(
              _locationChoice == _LocationChoice.custom
                  ? 'Cambiar ubicación de esta publicación'
                  : 'Elegir ubicación en el mapa (opcional)',
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
  /// del perfil del vendedor sin ninguna acción; un toggle opcional permite
  /// personalizarlos solo para esta publicación.
  Widget _buildPaymentMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Métodos de pago', style: AppTypography.heading(15)),
        const SizedBox(height: 4),
        Text(
          _sellerPaymentMethods.isEmpty
              ? 'Usa los métodos de tu perfil.'
              : 'Usa: '
                    '${_sellerPaymentMethods.map((id) => paymentMethodById(id)?.label ?? id).join(', ')}.',
          style: TextStyle(color: context.colors.muted, fontSize: 13),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _customizePaymentMethods,
          onChanged: (value) => setState(() {
            _customizePaymentMethods = value;
            if (!value) _showPaymentMethodsError = false;
          }),
          title: const Text('Personalizar métodos de pago para este producto'),
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

  /// Activa (o quita, con `status: null`) un estado manual de inmediato
  /// (independiente del resto del formulario) — mismo endpoint/UX que antes
  /// vivía en el detalle de producto, ahora solo accesible desde "Editar
  /// producto".
  Future<void> _updateStatus(ManualStatus? status) async {
    if (status == _currentStatus || _updatingStatus) return;
    final product = widget.editingProduct!;
    setState(() => _updatingStatus = true);
    try {
      await ApiService.updateProductStatus(product.id, status?.apiValue);
      if (!mounted) return;
      setState(() {
        _currentStatus = status;
        _updatingStatus = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status != null
                ? 'Estado cambiado a "${status.label}"'
                : 'Producto reactivado: el badge vuelve a calcularse automático',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingStatus = false);
      _showError('No se pudo cambiar el estado. Intenta de nuevo.');
    }
  }

  Color _statusColor(ManualStatus status) {
    switch (status) {
      case ManualStatus.reserved:
        return AppColors.orange;
      case ManualStatus.sold:
        return AppColors.danger;
      case ManualStatus.negotiating:
        return AppColors.primary;
      case ManualStatus.paused:
        return context.colors.muted;
    }
  }

  IconData _statusIcon(ManualStatus status) {
    switch (status) {
      case ManualStatus.reserved:
        return Icons.bookmark_rounded;
      case ManualStatus.sold:
        return Icons.sell_rounded;
      case ManualStatus.negotiating:
        return Icons.handshake_rounded;
      case ManualStatus.paused:
        return Icons.pause_circle_rounded;
    }
  }

  /// Intervención manual del vendedor: apartado/vendido/en negociación/
  /// pausado. Estos 4 son "pegajosos" — sobreescriben el badge calculado y
  /// se mantienen hasta que el vendedor presione "Reactivar" o borre la
  /// publicación (no expiran solos con el tiempo, el stock o el calendario).
  /// "Disponible"/"No disponible" ya NO son opciones aquí: son resultados
  /// automáticos de las reglas de "Reglas de disponibilidad" más abajo.
  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gestión de venta', style: AppTypography.heading(15)),
        const SizedBox(height: 4),
        Text(
          _currentStatus != null
              ? 'Este estado sobreescribe el badge automático hasta que lo reactives.'
              : 'Actívalo solo si necesitas anular temporalmente el cálculo automático (ver "Reglas de disponibilidad").',
          style: TextStyle(color: context.colors.muted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...ManualStatus.values.map((status) {
              final selected = status == _currentStatus;
              final color = _statusColor(status);
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _statusIcon(status),
                      size: 18,
                      color: selected ? Colors.white : color,
                    ),
                    const SizedBox(width: 6),
                    Text(status.label),
                  ],
                ),
                selected: selected,
                selectedColor: color,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : context.colors.ink,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: _updatingStatus
                    ? null
                    : (isSelected) {
                        if (!isSelected) return;
                        _updateStatus(status);
                      },
              );
            }),
            if (_currentStatus != null)
              ActionChip(
                avatar: const Icon(
                  Icons.autorenew_rounded,
                  size: 18,
                  color: AppColors.success,
                ),
                label: const Text('Reactivar'),
                labelStyle: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
                onPressed: _updatingStatus ? null : () => _updateStatus(null),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 18, 18, _isEditing ? 12 : 24),
      children: [
        if (!_isEditing) ...[
          Text('Publicar producto', style: AppTypography.heading(22)),
          const SizedBox(height: 6),
          Text(
            'Completa la información básica para publicar tu producto en el marketplace.',
            style: AppTypography.body(14, color: context.colors.muted),
          ),
          const SizedBox(height: 20),
        ],

        // ─── Fotos ──────────────────────────────────────
        Text('Fotos', style: AppTypography.heading(15)),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _AddPhotoTile(
                hasImages: _totalImageCount > 0,
                onPickGallery: _pickImages,
                onPickCamera: _pickCamera,
              ),
              const SizedBox(width: 10),
              for (var i = 0; i < _existingImageUrls.length; i++) ...[
                _ExistingImageThumbnail(
                  url: '${ApiService.baseUrl}${_existingImageUrls[i]}',
                  onRemove: () => _removeExistingImage(i),
                ),
                const SizedBox(width: 10),
              ],
              for (var i = 0; i < _selectedImages.length; i++) ...[
                _ImageThumbnail(
                  file: _selectedImages[i],
                  onRemove: () => _removeImage(i),
                ),
                if (i < _selectedImages.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        TextField(
          controller: _titleController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Título',
            hintText: 'Ej. Calculadora científica Casio',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          minLines: 4,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            hintText: 'Estado, punto de entrega, detalles importantes...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixText: r'$ ',
                  labelText: 'Precio',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Row(
                        children: [
                          Icon(category.icon, color: category.color, size: 20),
                          const SizedBox(width: 10),
                          Text(category.name),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedCategoryId = value);
                },
              ),
            ),
          ],
        ),
        if (_isEditing) ...[
          const SizedBox(height: 12),
          _buildStatusSection(),
        ],
        const SizedBox(height: 20),
        _buildAvailabilityRulesSection(),
        const SizedBox(height: 12),
        _buildExtrasSection(),
        const SizedBox(height: 16),
        _buildPaymentMethodsSection(),
        if (!_isEditing) ...[
          const SizedBox(height: 16),
          _buildLocationSection(),
        ],
        if (_plans.isNotEmpty) ...[
          const SizedBox(height: 24),
          _HighlightSection(
            plans: _plans,
            selectedPlanId: _selectedPlanId,
            onSelectPlan: (planId) => setState(
              () => _selectedPlanId = _selectedPlanId == planId ? null : planId,
            ),
          ),
        ],
        if (!_isEditing) ...[
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish_rounded),
            label: const Text('Publicar ahora'),
          ),
        ],
      ],
    );
  }
}

// ─── Tile para agregar fotos ──────────────────────────────────
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    required this.hasImages,
    required this.onPickGallery,
    required this.onPickCamera,
  });

  final bool hasImages;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'gallery') onPickGallery();
        if (value == 'camera') onPickCamera();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'gallery',
          child: Row(
            children: [
              Icon(Icons.photo_library_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Galería'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'camera',
          child: Row(
            children: [
              Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Cámara'),
            ],
          ),
        ),
      ],
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasImages
                  ? Icons.add_photo_alternate_rounded
                  : Icons.add_a_photo_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Subir fotos',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Miniatura de imagen seleccionada ─────────────────────────
class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 104,
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.file(
              File(file.path),
              fit: BoxFit.cover,
              width: 104,
              height: 110,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.broken_image_rounded, color: context.colors.muted),
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Miniatura de una imagen ya subida (modo edición) ─────────
class _ExistingImageThumbnail extends StatelessWidget {
  const _ExistingImageThumbnail({required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 104,
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: 104,
              height: 110,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.broken_image_rounded, color: context.colors.muted),
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Highlight Section (sin cambios) ─────────────────────────
class _HighlightSection extends StatelessWidget {
  const _HighlightSection({
    required this.plans,
    required this.selectedPlanId,
    required this.onSelectPlan,
  });

  final List<HighlightPlan> plans;
  final String? selectedPlanId;
  final ValueChanged<String> onSelectPlan;

  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Destaca tu publicación',
                  style: AppTypography.heading(15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Opcional',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Publicar es gratis. Si eliges un plan, tu producto aparece primero en Destacados.',
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (final plan in plans) ...[
            _PlanCard(
              plan: plan,
              selected: selectedPlanId == plan.id,
              onTap: () => onSelectPlan(plan.id),
            ),
            if (plan != plans.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final HighlightPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : context.colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.orange : context.colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.orange : context.colors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    plan.description,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              plan.price,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
