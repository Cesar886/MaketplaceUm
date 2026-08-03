import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/location_picker.dart';
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
    }
    _loadCategories();
    _loadSellerLocation();
  }

  Future<void> _loadSellerLocation() async {
    if (_isEditing) return;
    final auth = context.read<AuthProvider>();
    if (auth.accountType != AccountType.negocio ||
        auth.backendSellerId == null) {
      return;
    }
    try {
      final seller = await ApiService.getSeller(auth.backendSellerId!);
      if (!mounted) return;
      setState(() {
        _savedSellerLat = seller.locationLat;
        _savedSellerLng = seller.locationLng;
        if (_hasSavedSellerLocation) {
          _locationChoice = _LocationChoice.useSaved;
        }
      });
    } catch (_) {
      // Sin ubicación de negocio: el formulario simplemente no ofrece
      // "usar la guardada", no bloquea el resto de la publicación.
    }
  }

  Future<void> _pickCustomLocation() async {
    final picked = await LocationPickerScreen.open(
      context,
      initialLat: _customLocationLat,
      initialLng: _customLocationLng,
      title: 'Ubicación de esta búsqueda',
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
      setState(() {
        _categories = categories;
        final currentIsValid =
            _selectedCategoryId != null &&
            categories.any((c) => c.id == _selectedCategoryId);
        if (!currentIsValid) {
          _selectedCategoryId = categories.isNotEmpty
              ? categories.first.id
              : null;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Escribe qué estás buscando');
      return;
    }
    if (_selectedCategoryId == null) {
      _showError('Selecciona una categoría');
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
          _showError('Error de autenticación. Vuelve a iniciar sesión.');
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
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados exitosamente')),
        );
      } else {
        // Publicar también requiere sesión real (JWT): el backend usa
        // requireAuth para que el autor salga del token, no del body.
        final auth = context.read<AuthProvider>();
        final synced = await auth.ensureBackendSync();
        if (!synced) {
          _showError('Error de autenticación. Vuelve a iniciar sesión.');
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
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '¡Búsqueda publicada! Te avisaremos si alguien responde.',
            ),
          ),
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
            title: const Text('Elegir otra ubicación para esta búsqueda'),
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
                  ? 'Cambiar ubicación de esta búsqueda'
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Publicar una búsqueda también requiere cuenta (igual que un producto);
    // ver/responder búsquedas de otros no la requiere.
    if (!context.watch<AuthProvider>().isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Publicar búsqueda')),
        body: const PublishAuthGate(
          icon: Icons.search_rounded,
          title: 'Crea tu cuenta para publicar tu búsqueda',
          subtitle:
              'Regístrate para publicar qué buscas y que te avisemos si alguien responde.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar búsqueda' : 'Publicar búsqueda'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'producto', label: Text('Producto')),
              ButtonSegment(value: 'servicio', label: Text('Servicio')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Qué buscas',
              hintText: 'Ej. Calculadora científica',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
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
                        ? 'Mínimo (cotización)'
                        : 'Precio mínimo',
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
                        ? 'Máximo (cotización)'
                        : 'Precio máximo',
                  ),
                ),
              ),
            ],
          ),
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            _buildLocationSection(),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _publishing ? null : _publish,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: _publishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? 'Guardar cambios' : 'Publicar búsqueda'),
          ),
        ],
      ),
    );
  }
}
