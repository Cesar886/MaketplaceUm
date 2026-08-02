import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

const _kMaxBusinessDescriptionLength = 280;

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.seller});

  final Seller seller;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _descriptionController;
  String? _selectedCategoryId;
  List<MarketplaceCategory> _categories = [];
  XFile? _pickedPhoto;
  bool _saving = false;

  bool get _isBusiness => widget.seller.isBusiness;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.seller.name);
    _phoneController = TextEditingController(text: widget.seller.phone ?? '');
    _descriptionController =
        TextEditingController(text: widget.seller.businessDescription ?? '');
    _selectedCategoryId = widget.seller.businessCategory;
    if (_isBusiness) _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.getCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Sin categorías: el dropdown queda vacío, no bloquea el resto del formulario.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null) {
      setState(() => _pickedPhoto = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.updateProfile(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        logoPath: _pickedPhoto?.path,
        businessDescription: _isBusiness ? _descriptionController.text.trim() : null,
        businessCategory: _isBusiness ? _selectedCategoryId : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  Widget _buildAvatar() {
    final initials = widget.seller.avatarInitials;
    Widget child;
    if (_pickedPhoto != null) {
      child = ClipOval(
        child: Image.file(
          File(_pickedPhoto!.path),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
        ),
      );
    } else if (widget.seller.logoUrl != null && widget.seller.logoUrl!.isNotEmpty) {
      child = ClipOval(
        child: Image.network(
          '${ApiService.baseUrl}${widget.seller.logoUrl}',
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Text(
            initials,
            style: const TextStyle(
              fontSize: 28,
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } else {
      child = Text(
        initials,
        style: const TextStyle(
          fontSize: 28,
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return InkWell(
      onTap: _pickPhoto,
      customBorder: const CircleBorder(),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: child,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: _buildAvatar()),
              const SizedBox(height: 28),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (_isBusiness) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Rubro del negocio',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  items: [
                    for (final category in _categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selectedCategoryId = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: _kMaxBusinessDescriptionLength,
                  decoration: const InputDecoration(
                    labelText: 'Descripción corta del negocio',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
