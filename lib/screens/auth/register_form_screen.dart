import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../mock_data.dart';
import '../../models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_error.dart';
import '../../services/api_service.dart';
import '../../widgets/business_hours_editor.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/payment_methods.dart';
import '../../widgets/static_mini_map.dart';
import '../legal/terms_screen.dart';
import '../legal/privacy_screen.dart';
import 'login_screen.dart';
import 'account_created_screen.dart';
import 'verification_screen.dart';

class RegisterFormScreen extends StatefulWidget {
  const RegisterFormScreen({super.key, required this.userType, this.google});

  final String userType;

  /// Registro que viene de "Continuar con Google": trae el idToken ya
  /// verificado y el perfil para prellenar. Cuando es null, esta pantalla se
  /// comporta EXACTAMENTE como siempre (correo + contraseña).
  final GoogleRegistroPendiente? google;

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
  double? _locationLat;
  double? _locationLng;

  // ─── Métodos de pago (obligatorio, todos los tipos de cuenta) ──
  final Set<String> _selectedPaymentMethods = {};
  bool _showPaymentMethodsError = false;

  /// Etiqueta del tipo de cuenta para el título. Se resuelve en cada
  /// `build` (no en un campo `final`) porque el idioma puede cambiar con la
  /// pantalla ya montada.
  String _typeLabel(String tipo) => switch (tipo) {
    'estudiante' => 'auth.type_student_short'.tr(),
    'particular' => 'auth.type_external_title'.tr(),
    'negocio' => 'auth.type_vendor_title'.tr(),
    _ => 'auth.account'.tr(),
  };

  bool get _isBusiness => widget.userType == 'negocio';

  /// La cuenta la va a crear Google: no se pide contraseña y el correo no se
  /// puede editar (el backend lo saca del idToken, no de este campo).
  bool get _conGoogle => widget.google != null;

  @override
  void initState() {
    super.initState();
    final google = widget.google;
    if (google != null) {
      _emailController.text = google.email;
      // El nombre de Google es solo un punto de partida: quien registra un
      // negocio normalmente quiere otro nombre, y puede cambiarlo.
      if (google.nombre.isNotEmpty) {
        _nameController.text = google.nombre;
        _responsibleNameController.text = google.nombre;
      }
    }
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
      // Respaldo local, igual que publish_product_screen y wanted_post_screen.
      //
      // Aquí el agujero pesaba más que en las otras pantallas: sin items el
      // desplegable se auto-deshabilita, y como el registro de negocio manda
      // `_selectedBusinessCategory` sí o sí, todos los que se registraran con
      // el endpoint caído quedarían clasificados en el 'food' que trae por
      // defecto, sin haber podido elegir otra cosa.
      if (!mounted) return;
      setState(() {
        _businessCategories = mockCategories;
        _selectedBusinessCategory = mockCategories.first.id;
        _loadingCategories = false;
      });
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

  Future<void> _pickLocation() async {
    final picked = await LocationPickerScreen.open(
      context,
      initialLat: _locationLat,
      initialLng: _locationLng,
      title: 'register.business_location_title'.tr(),
    );
    if (picked != null) {
      setState(() {
        _locationLat = picked.latitude;
        _locationLng = picked.longitude;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPaymentMethods.isEmpty) {
      setState(() => _showPaymentMethodsError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('register.payment_methods_required'.tr())),
      );
      return;
    }
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('register.terms_required'.tr())));
      return;
    }

    final auth = context.read<AuthProvider>();
    final google = widget.google;

    try {
      if (google != null) {
        // Registro con Google: mismos datos, misma pantalla, mismo
        // resultado. Lo único que cambia es que la identidad la respalda el
        // idToken en vez de una contraseña, y que el correo lo pone el
        // servidor a partir de ese token.
        String displayName = _isBusiness
            ? _businessNameController.text.trim()
            : _nameController.text.trim();
        if (displayName.isEmpty) {
          displayName = _responsibleNameController.text.trim();
        }

        await auth.registrarConGoogle(
          idToken: google.idToken,
          name: displayName,
          phone: _phoneController.text.trim(),
          userType: switch (widget.userType) {
            'negocio' => AccountType.negocio,
            'estudiante' => AccountType.estudiante,
            _ => AccountType.particular,
          },
          paymentMethods: _selectedPaymentMethods.toList(),
          businessName: _isBusiness ? displayName : null,
          businessType: _isBusiness ? _selectedBusinessCategory : null,
          responsibleName:
              _isBusiness && _responsibleNameController.text.trim().isNotEmpty
              ? _responsibleNameController.text.trim()
              : null,
          businessDescription:
              _isBusiness &&
                  _businessDescriptionController.text.trim().isNotEmpty
              ? _businessDescriptionController.text.trim()
              : null,
          logoPath: _isBusiness ? _logoFile?.path : null,
          businessHours: _isBusiness ? _businessHours : null,
        );
      } else if (_isBusiness) {
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
          paymentMethods: _selectedPaymentMethods.toList(),
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
          paymentMethods: _selectedPaymentMethods.toList(),
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

      // Si es negocio con ubicación marcada, guardarla en el backend
      if (_isBusiness && _locationLat != null && _locationLng != null) {
        final authProvider = context.read<AuthProvider>();
        final sellerId = authProvider.backendSellerId;
        if (sellerId != null) {
          try {
            await ApiService.updateSellerProfile(
              sellerId: sellerId,
              locationLat: _locationLat,
              locationLng: _locationLng,
            );
          } catch (_) {
            // Si falla el guardado de ubicación, no bloqueamos el registro
          }
        }
      }

      if (!mounted) return;
      final accountType = auth.accountType;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => accountType == AccountType.particular
              ? const AccountCreatedScreen()
              : VerificationScreen(tipo: accountType, desdeRegistro: true),
        ),
      );
    } catch (e, stack) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensajeDeError(
              e,
              stack: stack,
              fallback: 'register.submit_error'.tr(),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final typeLabel = _typeLabel(widget.userType);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isBusiness
              ? 'register.title_business'.tr()
              : 'register.title_basic'.tr(namedArgs: {'type': typeLabel}),
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

                const SizedBox(height: 24),
                // ─── Métodos de pago (obligatorio, todos los tipos) ──
                _buildPaymentMethodsSection(),

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
                        : Text(
                            _isBusiness
                                ? 'register.submit_business'.tr()
                                : 'auth.create_account'.tr(),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'auth.have_account'.tr(),
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
                      child: Text(
                        'auth.login_button'.tr(),
                        style: TextStyle(
                          color: context.colors.primary,
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
      Text(
        'register.your_data'.tr(),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        'register.your_data_subtitle'.tr(),
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
        'register.business_heading'.tr(),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        'register.business_subtitle'.tr(),
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
        decoration: InputDecoration(
          labelText: 'register.full_name'.tr(),
          prefixIcon: const Icon(Icons.person_rounded),
        ),
        textCapitalization: TextCapitalization.words,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'validation.name_required'.tr()
            : null,
      ),
      const SizedBox(height: 14),
      _buildEmailField(),
      const SizedBox(height: 14),
      _buildPhoneField(),
      if (!_conGoogle) ...[
        const SizedBox(height: 14),
        _buildPasswordField(),
        const SizedBox(height: 14),
        _buildConfirmPasswordField(),
      ],
    ];
  }

  // ─── Secciones de negocio ────────────────────────────────────

  List<Widget> _buildBusinessSections() {
    return [
      // ─── Datos del negocio ────────────────────────────────
      _buildSectionTitle('register.section_business'.tr(), Icons.store_rounded),
      const SizedBox(height: 14),
      TextFormField(
        controller: _businessNameController,
        decoration: InputDecoration(
          labelText: 'register.business_name'.tr(),
          hintText: 'register.business_name_hint'.tr(),
          prefixIcon: const Icon(Icons.store_rounded),
        ),
        textCapitalization: TextCapitalization.words,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'validation.business_name_required'.tr()
            : null,
      ),
      const SizedBox(height: 14),
      _loadingCategories
          ? const AppShimmer(child: ShimmerBox(height: 52, borderRadius: 10))
          : DropdownButtonFormField<String>(
              initialValue: _selectedBusinessCategory,
              decoration: InputDecoration(
                labelText: 'register.business_category'.tr(),
                prefixIcon: const Icon(Icons.category_rounded),
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
              color: _logoFile != null
                  ? context.colors.accent
                  : context.colors.border,
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
                    color: context.colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_rounded,
                    color: context.colors.primary,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _logoFile != null
                      ? 'register.logo_selected'.tr()
                      : 'register.logo_optional'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _logoFile != null
                        ? context.colors.accent
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
        decoration: InputDecoration(
          labelText: 'register.short_description'.tr(),
          hintText: 'register.short_description_hint'.tr(),
          alignLabelWithHint: true,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: const Icon(Icons.description_rounded),
          ),
        ),
        textCapitalization: TextCapitalization.sentences,
      ),
      const SizedBox(height: 14),
      BusinessHoursEditor(
        initialHours: _businessHours,
        onChanged: (hours) => _businessHours = hours,
      ),
      const SizedBox(height: 14),
      Text(
        'register.business_location_optional'.tr(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: context.colors.muted,
        ),
      ),
      const SizedBox(height: 8),
      if (_locationLat != null && _locationLng != null) ...[
        StaticMiniMap(
          lat: _locationLat,
          lng: _locationLng,
          showOpenInMapsButton: false,
          height: 120,
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: _pickLocation,
        icon: const Icon(Icons.map_outlined),
        label: Text(
          _locationLat != null
              ? 'register.change_location'.tr()
              : 'register.mark_location'.tr(),
        ),
      ),

      const SizedBox(height: 24),
      // ─── Datos de contacto ─────────────────────────────────
      _buildSectionTitle(
        'register.section_contact'.tr(),
        Icons.contacts_rounded,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _responsibleNameController,
        decoration: InputDecoration(
          labelText: 'register.owner_name'.tr(),
          hintText: 'register.owner_name_hint'.tr(),
          prefixIcon: const Icon(Icons.person_rounded),
        ),
        textCapitalization: TextCapitalization.words,
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'validation.owner_name_required'.tr()
            : null,
      ),
      const SizedBox(height: 14),
      _buildEmailField(),
      const SizedBox(height: 14),
      _buildPhoneField(),

      if (!_conGoogle) ...[
        const SizedBox(height: 24),
        // ─── Seguridad ───────────────────────────────────────
        _buildSectionTitle('Seguridad', Icons.lock_rounded),
        const SizedBox(height: 14),
        _buildPasswordField(),
        const SizedBox(height: 14),
        _buildConfirmPasswordField(),
      ],
    ];
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: context.colors.primary),
        ),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  // ─── Métodos de pago (obligatorio, todos los tipos de cuenta) ──

  Widget _buildPaymentMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'register.section_payments'.tr(),
          Icons.payments_rounded,
        ),
        const SizedBox(height: 6),
        Text(
          'register.payment_methods_prompt'.tr(),
          style: TextStyle(
            color: context.colors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        PaymentMethodsSelector(
          selected: _selectedPaymentMethods,
          showError: _showPaymentMethodsError,
          onChanged: (methods) => setState(() {
            _selectedPaymentMethods
              ..clear()
              ..addAll(methods);
            if (methods.isNotEmpty) _showPaymentMethodsError = false;
          }),
        ),
      ],
    );
  }

  // ─── Campos reutilizables ────────────────────────────────────

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      // Con Google el correo no se edita: la cuenta se crea con el que venga
      // firmado en el idToken, así que un valor distinto aquí sería mentira.
      readOnly: _conGoogle,
      decoration: InputDecoration(
        labelText: 'auth.email_label'.tr(),
        prefixIcon: const Icon(Icons.email_rounded),
        helperText: _conGoogle ? 'auth.google_email_locked'.tr() : null,
        suffixIcon: _conGoogle
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: GoogleLogo(size: 18),
              )
            : null,
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return 'validation.email_required'.tr();
        }
        if (!v.contains('@')) return 'validation.email_invalid'.tr();
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      decoration: InputDecoration(
        labelText: 'register.phone'.tr(),
        prefixIcon: const Icon(Icons.phone_rounded),
      ),
      keyboardType: TextInputType.phone,
      validator: (v) => (v == null || v.trim().isEmpty)
          ? 'validation.phone_required'.tr()
          : null,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'auth.password_label'.tr(),
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
        if (v == null || v.length < 6) return 'validation.password_min'.tr();
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      decoration: InputDecoration(
        labelText: 'register.confirm_password'.tr(),
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
          return 'validation.passwords_mismatch'.tr();
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
            activeColor: context.colors.primary,
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
                    TextSpan(text: 'register.accept_terms_prefix'.tr()),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TermsScreen(),
                          ),
                        ),
                        child: Text(
                          'settings.terms'.tr(),
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    TextSpan(text: 'register.accept_terms_middle'.tr()),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PrivacyScreen(),
                          ),
                        ),
                        child: Text(
                          'settings.privacy'.tr(),
                          style: TextStyle(
                            color: context.colors.primary,
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
