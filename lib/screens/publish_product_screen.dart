import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../constants/atributos_categoria.dart';
import '../constants/dias_semana.dart';
import '../features/highlight/destacar_flag.dart';
import '../mock_data.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_error.dart';
import '../services/api_service.dart';
import '../widgets/badges.dart';
import '../widgets/category_attributes_form.dart';
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

/// Pisos de longitud del título y la descripción.
///
/// No son un capricho de UI: el título y la descripción son literalmente lo
/// que se dibuja como `og:title` y `og:description` en la vista previa del
/// link compartido (ver `website/app/producto/[id]/page.tsx`). Diez y veinte
/// caracteres son el mínimo con el que un preview se lee como una
/// publicación real y no como un link basura. Duplicados a propósito en el
/// backend (`backend/src/routes/products.js`), que es la única barrera que
/// un cliente no puede saltarse.
const _minimoTitulo = 10;
const _minimoDescripcion = 20;

class _PublishProductScreenState extends State<PublishProductScreen> {
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

  // ─── Preguntas dinámicas de la categoría ─────────────────
  // El mapa se mantiene SIEMPRE depurado (ver depurarRespuestas): lo que
  // hay aquí es exactamente lo que se manda al publicar, sin un paso de
  // limpieza al final que se pueda olvidar. _atributosFaltantes se llena al
  // intentar publicar con obligatorias sin responder — hoy nunca, porque
  // ninguna pregunta del catálogo lo es.
  Map<String, dynamic> _atributos = {};
  Set<String> _atributosFaltantes = {};

  // ─── Extras opcionales ───────────────────────────────────
  final List<ProductExtra> _extras = [];
  final _extraNameController = TextEditingController();
  final _extraPriceController = TextEditingController();

  // ─── Stock ─────────────────────────────────────────────
  // Ya no hay modo "sin límite": el inventario es obligatorio.
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

  // ─── Métodos de pago ────────────────────────────────────────
  //
  // Se heredan del perfil y no se pueden tocar por publicación: tener el
  // método declarado en dos sitios que pueden decir cosas distintas es una
  // fuente de publicaciones que prometen un cobro que el vendedor no hace.
  // La única excepción es el vendedor que aún no declaró ninguno en su
  // perfil: ahí no hay nada que heredar, y sin esto publicaría sin decirle
  // a nadie cómo pagarle.
  List<String> _sellerPaymentMethods = [];
  final Set<String> _customPaymentMethods = {};
  bool _showPaymentMethodsError = false;

  /// Si esta pantalla es el sitio donde se eligen los métodos de pago.
  ///
  /// Solo cuando el perfil no declara ninguno. Si el perfil ya los tiene, la
  /// publicación los hereda y aquí no se ofrece cambiarlos.
  bool get _eligeMetodosDePago => _sellerPaymentMethods.isEmpty;

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
      _customPaymentMethods.addAll(product.paymentMethods!);
    }
    _currentStatus = product.manualStatus;
    _seller = product.seller;
    // Se depuran al precargar y no solo al guardar: un producto publicado
    // por una versión anterior de la app puede traer respuestas de preguntas
    // que ya no existen, y el formulario no sabría dónde pintarlas.
    _atributos = depurarRespuestas(product.atributos, product.category.id);

    if (product.stockQuantity != null) {
      _autoResetStock = product.stockResetDaily;
      _stockController.text = product.stockQuantity.toString();
    }
  }

  Future<void> _loadData() async {
    try {
      final auth = context.read<AuthProvider>();
      final results = await Future.wait([
        ApiService.getCategories(),
        if (!_isEditing && auth.backendSellerId != null)
          ApiService.getSeller(auth.backendSellerId!),
      ]);
      // TODO: Destacar publicaciones pendiente para próxima actualización -
      // no eliminar. Los planes salieron del Future.wait de arriba (donde
      // eran results[1]) para poder no pedirlos mientras kDestacarHabilitado
      // sea false: ninguna parte del formulario los muestra, así que sería un
      // request de más en cada apertura de "Publicar". Al poner la bandera
      // en true el fetch vuelve solo, sin tocar nada más.
      // Ver features/highlight/destacar_flag.dart.
      final planes = kDestacarHabilitado
          ? await ApiService.getHighlightPlans()
          : const <HighlightPlan>[];
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<MarketplaceCategory>;
        _plans = planes;
        final editingCategoryId = widget.editingProduct?.category.id;
        if (editingCategoryId != null &&
            _categories.any((c) => c.id == editingCategoryId)) {
          _selectedCategoryId = editingCategoryId;
        } else if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first.id;
        }
        if (results.length > 1) {
          final seller = results[1] as Seller;
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
        // TODO: Destacar pendiente para próxima actualización - el fallback
        // a planes mock vuelve solo al poner kDestacarHabilitado en true.
        if (kDestacarHabilitado) _plans = highlightPlans;
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
      title: 'publish.listing_location_title'.tr(),
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
      _showError('publish.error_title_required'.tr());
      return;
    }
    // Un mínimo y no solo "no vacío": el campo obligatorio a secas dejaba
    // pasar títulos como "Jajs", y el título es lo que se pinta como
    // encabezado en la vista previa de WhatsApp cuando alguien comparte el
    // link. Un preview con cuatro letras sin sentido se lee como spam.
    // El mismo piso está en el backend (routes/products.js), que es donde
    // realmente se hace cumplir.
    if (title.length < _minimoTitulo) {
      _showError('publish.error_title_too_short'.tr());
      return;
    }
    if (description.isEmpty) {
      _showError('publish.error_description_required'.tr());
      return;
    }
    if (description.length < _minimoDescripcion) {
      _showError('publish.error_description_too_short'.tr());
      return;
    }
    if (price.isEmpty) {
      _showError('publish.error_price_required'.tr());
      return;
    }
    if (_totalImageCount == 0) {
      _showError('publish.error_photo_required'.tr());
      return;
    }
    // Solo se exige a quien no tiene métodos en el perfil: para el resto no
    // hay nada que elegir aquí, ya vienen heredados.
    if (_eligeMetodosDePago && _customPaymentMethods.isEmpty) {
      setState(() => _showPaymentMethodsError = true);
      _showError('publish.error_payment_required'.tr());
      return;
    }
    if (!_validarAtributos()) return;

    // El inventario es obligatorio: sin una cantidad contra la que descontar
    // al cobrar, se acaba vendiendo algo que ya no existe. El backend lo
    // rechaza igual; esto solo evita el viaje.
    final parsedStock = int.tryParse(_stockController.text.trim());
    if (parsedStock == null || parsedStock < 0) {
      _showError('publish.error_stock_required'.tr());
      return;
    }
    final int stockQuantity = parsedStock;
    final int stockInitial = parsedStock;
    final bool stockResetDaily = _autoResetStock;

    setState(() => _publishing = true);
    try {
      // Asegurar que tenemos un token JWT del backend antes de publicar/editar
      final auth = context.read<AuthProvider>();
      final synced = await auth.ensureBackendSync();
      if (!synced) {
        _showError('errors.auth_expired'.tr());
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
          // null = hereda los del perfil, que es lo correcto siempre que el
          // perfil tenga alguno.
          paymentMethods: _eligeMetodosDePago
              ? _customPaymentMethods.toList()
              : null,
          atributos: _atributos,
        );
        if (!mounted) return;
        _titleController.clear();
        _descriptionController.clear();
        _priceController.clear();
        setState(() {
          _selectedImages.clear();
          // El formulario queda listo para otra publicación: dejar las
          // respuestas anteriores haría que la siguiente saliera con la
          // talla del producto pasado sin que nadie lo note.
          _atributos = {};
          _atributosFaltantes = {};
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('publish.published_ok'.tr())));
      }
    } catch (e, stack) {
      if (!mounted) return;
      _showError(
        mensajeDeError(
          e,
          stack: stack,
          fallback: _isEditing
              ? 'publish.save_error'.tr()
              : 'publish.publish_error'.tr(),
        ),
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
    required int stockQuantity,
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
      // null = hereda los del perfil, que es lo correcto siempre que el
      // perfil tenga alguno.
      paymentMethods: _eligeMetodosDePago
          ? _customPaymentMethods.toList()
          : null,
      atributos: _atributos,
    );

    final warnings = <String>[];

    final newPrice = num.tryParse(price);
    if (newPrice != null && newPrice != product.price) {
      try {
        await ApiService.updateProduct(product.id, newPrice);
      } catch (e, stack) {
        warnings.add(
          'publish.price_update_error'.tr(
            namedArgs: {
              'reason': mensajeDeError(
                e,
                stack: stack,
                fallback: 'publish.try_again'.tr(),
              ),
            },
          ),
        );
      }
    }

    final stockChanged =
        stockQuantity != product.stockQuantity ||
        stockResetDaily != product.stockResetDaily;
    if (stockChanged) {
      try {
        await ApiService.setProductStock(
          product.id,
          quantity: stockQuantity,
          resetDaily: stockResetDaily,
        );
      } catch (e, stack) {
        warnings.add(
          'publish.stock_update_error'.tr(
            namedArgs: {
              'reason': mensajeDeError(
                e,
                stack: stack,
                fallback: 'publish.try_again'.tr(),
              ),
            },
          ),
        );
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          warnings.isEmpty
              ? 'publish.changes_saved'.tr()
              : 'publish.updated_with_warnings'.tr(
                  namedArgs: {'warnings': warnings.join(' · ')},
                ),
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  /// Comprueba las preguntas dinámicas marcadas como obligatorias en la
  /// config y marca en rojo las que falten.
  ///
  /// Hoy no hay ninguna obligatoria, así que esto siempre pasa. Existe
  /// completo igual porque el día que se active un `obligatoria: true` en la
  /// config, el descubrimiento de que la validación nunca se escribió llega
  /// tarde: el servidor devolvería un 400 genérico y el usuario no sabría
  /// cuál de las doce preguntas le falta.
  ///
  /// Solo se exigen las preguntas VISIBLES: una obligatoria que cuelga de un
  /// switch apagado no aplica y no debe bloquear la publicación.
  bool _validarAtributos() {
    final faltantes = preguntasDeCategoria(_selectedCategoryId)
        .where((p) => p.obligatoria)
        .where((p) => p.aplicaCon(_atributos))
        .where((p) => !_atributos.containsKey(p.key))
        .map((p) => p.key)
        .toSet();

    if (faltantes.isEmpty) {
      if (_atributosFaltantes.isNotEmpty) {
        setState(() => _atributosFaltantes = {});
      }
      return true;
    }

    setState(() => _atributosFaltantes = faltantes);
    final primera = preguntasDeCategoria(
      _selectedCategoryId,
    ).firstWhere((p) => p.key == faltantes.first);
    _showError(
      'publish.error_missing_answer'.tr(namedArgs: {'field': primera.label}),
    );
    return false;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addExtra() {
    if (_extras.length >= 8) {
      _showError('publish.error_max_extras'.tr());
      return;
    }
    final name = _extraNameController.text.trim();
    final priceText = _extraPriceController.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      _showError('publish.error_extra_price'.tr());
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
      _showError('publish.error_max_extras'.tr());
      return false;
    }
    if (name.isEmpty) {
      _showError('publish.error_extra_name'.tr());
      return false;
    }
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      _showError(
        'publish.error_extra_price_named'.tr(namedArgs: {'name': name}),
      );
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

    final stock = int.tryParse(_stockController.text.trim());
    if (stock != null && stock <= 0) {
      return (ComputedStatus.soldOut, null, null);
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
        nextDay != null ? nombreDiaEnFrase(nextDay) : null,
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
          'publish.preview_prefix'.tr(),
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
              Expanded(
                child: Text(
                  'publish.available_days'.tr(),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text(
                _selectedDays.isEmpty
                    ? 'publish.all_days'.tr()
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
                label: Text(
                  nombreCortoDia(i),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: selected,
                showCheckmark: false,
                selectedColor: context.colors.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  color: selected ? context.colors.primary : context.colors.ink,
                ),
                side: BorderSide(
                  color: selected
                      ? context.colors.primary.withValues(alpha: 0.4)
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
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'publish.inventory'.tr(),
                  style: AppTypography.heading(15, color: context.colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // El inventario es obligatorio: sin una cantidad contra la que
          // descontar, se acaba vendiendo algo que ya no existe. Se pide
          // aquí y se vuelve a exigir al verificar la cuenta.
          TextField(
            controller: _stockController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'publish.stock_available'.tr(),
              helperText: 'publish.stock_helper'.tr(),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'publish.stock_daily_reset'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'publish.stock_daily_reset_help'.tr(),
              style: const TextStyle(fontSize: 12),
            ),
            value: _autoResetStock,
            onChanged: (val) => setState(() => _autoResetStock = val),
            activeColor: context.colors.primary,
          ),
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
                child: Icon(
                  Icons.add_box_rounded,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'publish.extras'.tr(),
                  style: AppTypography.heading(15, color: context.colors.ink),
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
                  'common.optional'.tr(),
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
            'publish.extras_help'.tr(),
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
                  decoration: InputDecoration(
                    hintText: 'publish.extra_name_hint'.tr(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
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
                  decoration: InputDecoration(
                    hintText: 'publish.price_placeholder'.tr(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _extras.length >= 8
                    ? context.colors.border
                    : context.colors.primary.withValues(alpha: 0.08),
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
                          : context.colors.primary,
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
      content = PublishAuthGate(
        icon: Icons.add_circle_outline_rounded,
        title: 'publish.account_required_title'.tr(),
        subtitle: 'publish.account_required_body'.tr(),
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
      appBar: AppBar(
        title: Text('publish.edit_title'.tr()),
        centerTitle: false,
      ),
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
                child: Text('common.cancel'.tr()),
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
                label: Text(
                  _publishing
                      ? 'publish.saving'.tr()
                      : 'publish.save_changes'.tr(),
                ),
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
            title: Text('publish.choose_other_location'.tr()),
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
                  ? 'publish.change_listing_location'.tr()
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

  /// Sección de métodos de pago de la publicación.
  ///
  /// Con métodos en el perfil, esto es informativo y nada más: se heredan y
  /// no se personalizan por publicación (ver [_eligeMetodosDePago]). Sin
  /// ellos, es el único sitio donde el vendedor puede declararlos, así que
  /// aquí sí se eligen — y son obligatorios, porque publicar sin ninguno deja
  /// al comprador sin forma de pagar.
  Widget _buildPaymentMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'register.section_payments'.tr(),
          style: AppTypography.heading(15, color: context.colors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          _eligeMetodosDePago
              ? 'publish.payment_none_yet'.tr()
              : 'publish.payment_from_profile'.tr(
                  namedArgs: {
                    'methods': _sellerPaymentMethods
                        .map((id) => paymentMethodById(id)?.label ?? id)
                        .join(', '),
                  },
                ),
          style: TextStyle(color: context.colors.muted, fontSize: 13),
        ),
        if (_eligeMetodosDePago) ...[
          const SizedBox(height: 10),
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
                ? 'publish.status_changed'.tr(
                    namedArgs: {'status': status.label},
                  )
                : 'publish.status_reactivated'.tr(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingStatus = false);
      _showError('publish.status_change_error'.tr());
    }
  }

  Color _statusColor(ManualStatus status) {
    switch (status) {
      case ManualStatus.reserved:
        return context.colors.accent;
      case ManualStatus.sold:
        return AppColors.danger;
      case ManualStatus.negotiating:
        return context.colors.primary;
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
        Text(
          'publish.sale_management'.tr(),
          style: AppTypography.heading(15, color: context.colors.ink),
        ),
        const SizedBox(height: 4),
        Text(
          _currentStatus != null
              ? 'publish.status_override_on'.tr()
              : 'publish.status_override_off'.tr(),
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
                label: Text('publish.reactivate'.tr()),
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
          Text(
            'nav.publish_product'.tr(),
            style: AppTypography.heading(22, color: context.colors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'publish.subtitle'.tr(),
            style: AppTypography.body(14, color: context.colors.muted),
          ),
          const SizedBox(height: 20),
        ],

        // ─── Fotos ──────────────────────────────────────
        Text(
          'publish.photos'.tr(),
          style: AppTypography.heading(15, color: context.colors.ink),
        ),
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
          decoration: InputDecoration(
            labelText: 'publish.field_title'.tr(),
            hintText: 'publish.field_title_hint'.tr(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          minLines: 4,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'publish.field_description'.tr(),
            hintText: 'publish.field_description_hint'.tr(),
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
                decoration: InputDecoration(
                  prefixText: r'$ ',
                  labelText: 'publish.field_price'.tr(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
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
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedCategoryId = value;
                    // Las respuestas que no existen en la categoría nueva se
                    // caen aquí mismo, no al enviar: si el usuario vuelve a
                    // la categoría original habiendo cambiado de opinión, no
                    // deben reaparecer respuestas que ya no vio en pantalla.
                    // Las generales sobreviven porque aplican a todas.
                    _atributos = depurarRespuestas(_atributos, value);
                    _atributosFaltantes = {};
                  });
                },
              ),
            ),
          ],
        ),
        if (_isEditing) ...[const SizedBox(height: 12), _buildStatusSection()],

        // ─── Preguntas dinámicas de la categoría ────────
        // Van justo debajo del selector de categoría, que es donde el
        // usuario acaba de decidir qué está vendiendo, y antes de la
        // logística (disponibilidad, pago, ubicación): siguen hablando del
        // producto, no de cómo se entrega.
        const SizedBox(height: 26),
        CategoryAttributesForm(
          categoryId: _selectedCategoryId,
          respuestas: _atributos,
          faltantes: _atributosFaltantes,
          onChanged: (valores) => setState(() {
            _atributos = valores;
            // El error se limpia en cuanto se responde, sin esperar a otro
            // intento de publicar.
            _atributosFaltantes = _atributosFaltantes
                .where((k) => !valores.containsKey(k))
                .toSet();
          }),
        ),

        const SizedBox(height: 8),
        _buildAvailabilityRulesSection(),
        const SizedBox(height: 12),
        _buildExtrasSection(),
        const SizedBox(height: 16),
        _buildPaymentMethodsSection(),
        if (!_isEditing) ...[
          const SizedBox(height: 16),
          _buildLocationSection(),
        ],
        // TODO: Destacar publicaciones pendiente para próxima actualización
        // - no eliminar. La sección de planes del formulario (publicar Y
        // editar) queda oculta mientras kDestacarHabilitado sea false; vuelve
        // sola al poner la bandera en true
        // (ver features/highlight/destacar_flag.dart).
        if (kDestacarHabilitado && _plans.isNotEmpty) ...[
          const SizedBox(height: 24),
          _HighlightSection(
            plans: _plans,
            selectedPlanId: _selectedPlanId,
            // null = sin plan, que es el estado por defecto y gratis. La
            // sección lo manda tanto desde el chip "Sin plan" como al volver
            // a tocar el plan que ya estaba elegido.
            onSelectPlan: (planId) => setState(() => _selectedPlanId = planId),
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
            label: Text('publish.publish_now'.tr()),
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
        PopupMenuItem(
          value: 'gallery',
          child: Row(
            children: [
              Icon(Icons.photo_library_rounded, color: context.colors.primary),
              SizedBox(width: 10),
              Text('publish.gallery'.tr()),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'camera',
          child: Row(
            children: [
              Icon(Icons.camera_alt_rounded, color: context.colors.primary),
              SizedBox(width: 10),
              Text('publish.camera'.tr()),
            ],
          ),
        ),
      ],
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.colors.primary.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasImages
                  ? Icons.add_photo_alternate_rounded
                  : Icons.add_a_photo_rounded,
              color: context.colors.primary,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'publish.upload_photos'.tr(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primary,
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

// ─── Highlight Section ───────────────────────────────────────
//
// TODO: Destacar publicaciones pendiente para próxima actualización - no
// eliminar. Toda esta sección (_HighlightSection, sus chips y _PlanDetail)
// queda sin renderizarse mientras kDestacarHabilitado sea false; se reactiva
// al poner la bandera en true (ver features/highlight/destacar_flag.dart).
//
// Los planes se eligen con una fila de chips y solo se despliega el detalle
// del elegido. Apilar las cuatro tarjetas obligaba a leer cuatro precios y
// cuatro descripciones para tomar una decisión opcional, en medio de un
// formulario que ya es largo.
class _HighlightSection extends StatelessWidget {
  const _HighlightSection({
    required this.plans,
    required this.selectedPlanId,
    required this.onSelectPlan,
  });

  final List<HighlightPlan> plans;
  final String? selectedPlanId;

  /// null = sin plan (gratis).
  final ValueChanged<String?> onSelectPlan;

  /// El plan elegido, o null si se publica gratis.
  HighlightPlan? get _elegido {
    for (final plan in plans) {
      if (plan.id == selectedPlanId) return plan;
    }
    return null;
  }

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
                child: Icon(Icons.star_rounded, color: context.colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'publish.highlight_title'.tr(),
                  style: AppTypography.heading(15, color: context.colors.ink),
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
                  'common.optional'.tr(),
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
            'publish.highlight_help'.tr(),
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // Los chips no caben en pantallas estrechas: se desplazan en vez de
          // envolverse, para que la fila siga leyéndose como una sola tira de
          // opciones y no como dos renglones desalineados.
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selectedPlanId == null,
                    label: Text('publish.no_plan'.tr()),
                    // Deseleccionar tiene que ser una opción visible. Sin este
                    // chip, quien elige un plan por curiosidad solo puede
                    // deshacerlo adivinando que se toca otra vez.
                    onSelected: (_) => onSelectPlan(null),
                  ),
                ),
                for (final plan in plans)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: selectedPlanId == plan.id,
                      label: Text(_etiquetaCorta(plan)),
                      onSelected: (elegido) =>
                          onSelectPlan(elegido ? plan.id : null),
                    ),
                  ),
              ],
            ),
          ),
          // El detalle del elegido. AnimatedSize para que la tarjeta crezca y
          // se encoja en vez de dar un salto al cambiar de plan.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _elegido == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _PlanDetail(plan: _elegido!),
                  ),
          ),
        ],
      ),
    );
  }

  /// Nombre de chip a partir de la duración: "Destacado 7 dias" no cabe en un
  /// chip, y en una fila donde todos empiezan por "Destacado" esa palabra no
  /// distingue nada. Lo que diferencia a los planes es cuánto duran.
  String _etiquetaCorta(HighlightPlan plan) {
    if (plan.days <= 0) return plan.title;
    if (plan.days == 1) return 'publish.plan_24h'.tr();
    if (plan.days >= 30) return 'publish.plan_monthly'.tr();
    return 'home.duration_days'.tr(namedArgs: {'days': '${plan.days}'});
  }
}

/// Lo que se sabe del plan elegido. No es seleccionable: el chip de arriba ya
/// es el control, y una tarjeta que también se pudiera tocar dejaría dos
/// formas de hacer lo mismo a diez píxeles de distancia.
///
/// Sin borde ni radio propio marcado: va teñida, que ya la separa del fondo
/// de la sección sin agregar otra caja dentro de la caja.
class _PlanDetail extends StatelessWidget {
  const _PlanDetail({required this.plan});

  final HighlightPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: AppTypography.heading(15, color: colors.ink),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                plan.price,
                style: AppTypography.label(
                  22,
                  weight: FontWeight.w800,
                  color: colors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.description,
            style: TextStyle(
              color: colors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
