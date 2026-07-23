import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'auth/login_screen.dart';

class PublishProductScreen extends StatefulWidget {
  const PublishProductScreen({super.key});

  @override
  State<PublishProductScreen> createState() => _PublishProductScreenState();
}

class _PublishProductScreenState extends State<PublishProductScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  String _selectedCategoryId = 'other';
  String? _selectedPlanId;
  List<MarketplaceCategory> _categories = [];
  List<HighlightPlan> _plans = [];
  bool _loading = true;
  bool _publishing = false;

  // ─── Imágenes reales ─────────────────────────────────────
  final List<XFile> _selectedImages = [];
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getCategories(),
        ApiService.getHighlightPlans(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<MarketplaceCategory>;
        _plans = results[1] as List<HighlightPlan>;
        if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first.id;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(
      limit: 5 - _selectedImages.length,
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

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final price = _priceController.text.trim();

    if (title.isEmpty || description.isEmpty || price.isEmpty) {
      _showError('Completa todos los campos requeridos');
      return;
    }
    if (_selectedImages.isEmpty) {
      _showError('Agrega al menos una foto del producto');
      return;
    }

    setState(() => _publishing = true);
    try {
      // El vendedor se obtiene del JWT en el backend (requireAuth),
      // no se envía desde el cliente.
      await ApiService.createProduct(
        title: title,
        price: '\$$price',
        category: _selectedCategoryId,
        description: description,
        imagePaths: _selectedImages.map((xf) => xf.path).toList(),
      );
      if (!mounted) return;
      _titleController.clear();
      _descriptionController.clear();
      _priceController.clear();
      setState(() => _selectedImages.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto publicado exitosamente')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Error al publicar: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (_loading) {
      return const SafeArea(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isLoggedIn) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_circle_outline_rounded,
                  size: 64, color: AppColors.muted),
              const SizedBox(height: 20),
              Text('Publica tus productos',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              const Text(
                'Inicia sesión o crea una cuenta para empezar a vender en el campus.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('Iniciar sesión'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          Text('Publicar producto',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text(
            'Completa la información básica para publicar tu producto en el marketplace.',
            style: TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // ─── Fotos ──────────────────────────────────────
          Text('Fotos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _AddPhotoTile(
                  hasImages: _selectedImages.isNotEmpty,
                  onPickGallery: _pickImages,
                  onPickCamera: _pickCamera,
                ),
                const SizedBox(width: 10),
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
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Estado, punto de entrega, detalles importantes...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixText: r'$ ',
              labelText: 'Precio',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategoryId,
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
          const SizedBox(height: 24),
          _HighlightSection(
            plans: _plans,
            selectedPlanId: _selectedPlanId,
            onSelectPlan: (planId) => setState(
              () => _selectedPlanId =
                  _selectedPlanId == planId ? null : planId,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _publishing ? null : _publish,
            icon: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.publish_rounded),
            label: Text(_publishing ? 'Publicando...' : 'Publicar ahora'),
          ),
        ],
      ),
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
              hasImages ? Icons.add_photo_alternate_rounded : Icons.add_a_photo_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(height: 8),
            const Text(
              'Subir fotos',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Miniatura de imagen seleccionada ─────────────────────────
class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({
    required this.file,
    required this.onRemove,
  });

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
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.file(
              File(file.path),
              fit: BoxFit.cover,
              width: 104,
              height: 110,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_rounded, color: AppColors.muted),
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
              child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Destaca tu publicación',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Opcional',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Publicar es gratis. Si eliges un plan, tu producto aparece primero en Destacados.',
            style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
                height: 1.35),
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
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.orange : AppColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(plan.description,
                      style: const TextStyle(
                          color: AppColors.muted, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              plan.price,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
