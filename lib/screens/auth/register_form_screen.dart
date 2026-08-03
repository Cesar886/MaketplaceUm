import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/business_hours_editor.dart';
import '../legal/terms_screen.dart';
import '../legal/privacy_screen.dart';
import 'login_screen.dart';
import 'verification_screen.dart';

class RegisterFormScreen extends StatefulWidget {
  const RegisterFormScreen({super.key, required this.userType});

  final String userType;

  @override
  State<RegisterFormScreen> createState() => _RegisterFormScreenState();
}

class _RegisterFormScreenState extends State<RegisterFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // ─── Campos comunes ─────────────────────────────────────────
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  // ─── Campos de estudiante / particular ──────────────────────
  final _nameController = TextEditingController();

  // ─── Campos de negocio ──────────────────────────────────────
  final _businessNameController = TextEditingController();
  final _responsibleNameController = TextEditingController();
  final _businessDescriptionController = TextEditingController();
  String _selectedBusinessCategory = 'food';
  List<MarketplaceCategory> _businessCategories = [];
  XFile? _logoFile;
  bool _loadingCategories = true;
  Map<int, BusinessHoursRange> _businessHours = {};

  final _typeLabels = <String, String>{
    'estudiante': 'Estudiante',
    'particular': 'Particular',
    'negocio': 'Negocio',
  };

  bool get _isBusiness => widget.userType == 'negocio';

  @override
  void initState() {
    super.initState();
    if (_isBusiness) {
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiService.getCategories();
      if (!mounted) return;
      setState(() {
        _businessCategories = cats;
        if (cats.isNotEmpty) _selectedBusinessCategory = cats.first.id;
        _loadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCategories = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _businessNameController.dispose();
    _responsibleNameController.dispose();
    _businessDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null) {
      setState(() => _logoFile = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes aceptar los Términos y Condiciones '
            'y la Política de Privacidad para continuar.',
          ),
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();

    try {
      if (_isBusiness) {
        String displayName = _businessNameController.text.trim();
        if (displayName.isEmpty)
          displayName = _responsibleNameController.text.trim();

        await auth.registerUser(
          name: displayName,
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
          userType: AccountType.negocio,
          businessName: _businessNameController.text.trim(),
          businessType: _selectedBusinessCategory,
          responsibleName: _responsibleNameController.text.trim().isEmpty
              ? null
              : _responsibleNameController.text.trim(),
          businessDescription:
              _businessDescriptionController.text.trim().isEmpty
              ? null
              : _businessDescriptionController.text.trim(),
          logoPath: _logoFile?.path,
          businessHours: _businessHours,
        );
      } else {
        await auth.registerUser(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
          userType: widget.userType == 'estudiante'
              ? AccountType.estudiante
              : AccountType.particular,
        );
      }

      if (!context.mounted) return;

      // Si es negocio con logo, subirlo al backend
      if (_isBusiness && _logoFile != null) {
        final authProvider = context.read<AuthProvider>();
        final sellerId = authProvider.backendSellerId;
        if (sellerId != null) {
          try {
            await ApiService.uploadBusinessLogo(
              sellerId: sellerId,
              imagePath: _logoFile!.path,
            );
          } catch (_) {
            // Si falla la subida del logo, no bloqueamos el registro
          }
        }
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const VerificationScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final typeLabel = _typeLabels[widget.userType] ?? 'Cuenta';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isBusiness ? 'Registrar negocio' : 'Datos básicos - $typeLabel',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isBusiness)
                  ..._buildBusinessHeader()
                else
                  ..._buildStandardHeader(),

                const SizedBox(height: 22),

                if (_isBusiness)
                  ..._buildBusinessSections()
                else
                  ..._buildStandardFields(),

                const SizedBox(height: 14),
                // ─── Aceptación de términos ─────────────────────
                _buildTermsSection(),

                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: auth.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isBusiness ? 'Crear negocio' : 'Crear cuenta'),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '¿Ya tienes cuenta? ',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Inicia sesión',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Headers ──────────────────────────────────────────────────

  List<Widget> _buildStandardHeader() {
    return [
      Text('Tus datos', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        'Completa tu información para crear la cuenta.',
        style: TextStyle(
          color: context.colors.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  List<Widget> _buildBusinessHeader() {
    return [
      Text(
        'Registra tu negocio',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        'Completa los datos de tu negocio para aparecer en el campus.',
        style: TextStyle(
          color: context.colors.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  // ─── Campos estándar (estudiante/particular) ─────────────────

  List<Widget> _buildStandardFields() {
    return [
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Nombre completo',
          prefixIcon: Icon(Icons.person_rounded),
        ),
        textCapitalization: TextCapitalization.words,
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Ingresa tu nombre' : null,
      ),
      const SizedBox(height: 14),
      _buildEmailField(),
      const SizedBox(height: 14),
      _buildPhoneField(),
      const SizedBox(height: 14),
      _buildPasswordField(),
      const SizedBox(height: 14),
      _buildConfirmPasswordField(),
    ];
  }

  // ─── Secciones de negocio ────────────────────────────────────

  List<Widget> _buildBusinessSections() {
    return [
      // ─── Datos del negocio ────────────────────────────────
      _buildSectionTitle('Datos del negocio', Icons.store_rounded),
      const SizedBox(height: 14),
      TextFormField(
        controller: _businessNameController,
        decoration: const InputDecoration(
          labelText: 'Nombre del negocio *',
          hintText: 'Ej. Tacos El Primo, Tutoring Chiapas',
          prefixIcon: Icon(Icons.store_rounded),
        ),
        textCapitalization: TextCapitalization.words,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'Ingresa el nombre del negocio'
            : null,
      ),
      const SizedBox(height: 14),
      _loadingCategories
          ? const LinearProgressIndicator()
          : DropdownButtonFormField<String>(
              initialValue: _selectedBusinessCategory,
              decoration: const InputDecoration(
                labelText: 'Categoría / Giro *',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              items: [
                for (final cat in _businessCategories)
                  DropdownMenuItem(
                    value: cat.id,
                    child: Row(
                      children: [
                        Text(cat.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Text(cat.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _selectedBusinessCategory = v);
              },
            ),
      const SizedBox(height: 14),
      // Logo del negocio (opcional)
      InkWell(
        onTap: _pickLogo,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _logoFile != null ? AppColors.teal : context.colors.border,
            ),
          ),
          child: Row(
            children: [
              if (_logoFile != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(_logoFile!.path),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_rounded),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_rounded,
                    color: AppColors.primary,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _logoFile != null
                      ? 'Logo seleccionado ✓'
                      : 'Logo del negocio (opcional)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _logoFile != null
                        ? AppColors.teal
                        : context.colors.ink,
                  ),
                ),
              ),
              if (_logoFile == null)
                Icon(Icons.upload_file_rounded, color: context.colors.muted),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _businessDescriptionController,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Descripción breve (opcional)',
          hintText:
              'Ej. Vendemos comida casera los martes y jueves en el edificio B',
          alignLabelWithHint: true,
          prefixIcon: Padding(
            padding: EdgeInsets.only(bottom: 32),
            child: Icon(Icons.description_rounded),
          ),
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
      const SizedBox(height: 14),
      BusinessHoursEditor(
        initialHours: _businessHours,
        onChanged: (hours) => _businessHours = hours,
      ),

      const SizedBox(height: 24),
      // ─── Datos de contacto ─────────────────────────────────
      _buildSectionTitle('Datos de contacto', Icons.contacts_rounded),
      const SizedBox(height: 14),
      TextFormField(
        controller: _responsibleNameController,
        decoration: const InputDecoration(
          labelText: 'Nombre del responsable *',
          hintText: '¿Quién está a cargo del negocio?',
          prefixIcon: Icon(Icons.person_rounded),
        ),
        textCapitalization: TextCapitalization.words,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'Ingresa el nombre del responsable'
            : null,
      ),
      const SizedBox(height: 14),
      _buildEmailField(),
      const SizedBox(height: 14),
      _buildPhoneField(),

      const SizedBox(height: 24),
      // ─── Seguridad ─────────────────────────────────────────
      _buildSectionTitle('Seguridad', Icons.lock_rounded),
      const SizedBox(height: 14),
      _buildPasswordField(),
      const SizedBox(height: 14),
      _buildConfirmPasswordField(),
    ];
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  // ─── Campos reutilizables ────────────────────────────────────

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: 'Correo electrónico',
        prefixIcon: Icon(Icons.email_rounded),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Ingresa tu correo';
        if (!v.contains('@')) return 'Correo inválido';
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      decoration: const InputDecoration(
        labelText: 'Teléfono / WhatsApp',
        prefixIcon: Icon(Icons.phone_rounded),
      ),
      keyboardType: TextInputType.phone,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Ingresa tu teléfono' : null,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'Contraseña',
        prefixIcon: const Icon(Icons.lock_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      obscureText: _obscurePassword,
      validator: (v) {
        if (v == null || v.length < 6) return 'Mínimo 6 caracteres';
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      decoration: InputDecoration(
        labelText: 'Confirmar contraseña',
        prefixIcon: const Icon(Icons.lock_rounded),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirm
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
          ),
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      obscureText: _obscureConfirm,
      validator: (v) {
        if (v != _passwordController.text) {
          return 'Las contraseñas no coinciden';
        }
        return null;
      },
    );
  }

  // ─── Términos ─────────────────────────────────────────────────

  Widget _buildTermsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _acceptedTerms
              ? context.colors.border
              : AppColors.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _acceptedTerms,
            onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: RichText(
                textScaler: MediaQuery.of(context).textScaler,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.ink,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Acepto los '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TermsScreen(),
                          ),
                        ),
                        child: const Text(
                          'Términos y Condiciones',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' y la '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PrivacyScreen(),
                          ),
                        ),
                        child: const Text(
                          'Política de Privacidad',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
