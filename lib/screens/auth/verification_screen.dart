import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import 'account_created_screen.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _submitting = false;
  String? _errorMessage;

  // Campos para estudiante
  final _matriculaController = TextEditingController();
  final _carreraController = TextEditingController();
  String? _studentPhotoPath;

  // Campos para particular
  final _fullNameController = TextEditingController();
  String? _idDocPath;

  // Campos para negocio
  final _businessNameController = TextEditingController();
  String _businessType = 'Comida';
  final _locationController = TextEditingController();
  final _scheduleController = TextEditingController();

  @override
  void dispose() {
    _matriculaController.dispose();
    _carreraController.dispose();
    _fullNameController.dispose();
    _businessNameController.dispose();
    _locationController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify(AuthProvider auth) async {
    // Validar campos requeridos según el tipo
    switch (auth.accountType) {
      case AccountType.estudiante:
        if (_matriculaController.text.trim().isEmpty) {
          _showError('Ingresa tu matrícula');
          return;
        }
        if (_studentPhotoPath == null) {
          _showError('Selecciona una foto de tu credencial');
          return;
        }
      case AccountType.particular:
        if (_fullNameController.text.trim().isEmpty) {
          _showError('Ingresa tu nombre completo');
          return;
        }
        if (_idDocPath == null) {
          _showError('Selecciona una foto de tu identificación');
          return;
        }
      case AccountType.negocio:
        if (_businessNameController.text.trim().isEmpty) {
          _showError('Ingresa el nombre del negocio');
          return;
        }
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      switch (auth.accountType) {
        case AccountType.estudiante:
          await auth.submitStudentVerification(
            matricula: _matriculaController.text.trim(),
            carrera: _carreraController.text.trim().isEmpty
                ? null
                : _carreraController.text.trim(),
            credentialPhotoPath: _studentPhotoPath!,
          );
        case AccountType.particular:
          await auth.submitParticularVerification(
            fullNameOnId: _fullNameController.text.trim(),
            idDocumentPath: _idDocPath!,
          );
        case AccountType.negocio:
          await auth.createBusinessProfile(
            businessName: _businessNameController.text.trim(),
            businessType: _businessType,
            locationDescription: _locationController.text.trim().isEmpty
                ? null
                : _locationController.text.trim(),
            schedule: _scheduleController.text.trim().isEmpty
                ? null
                : _scheduleController.text.trim(),
          );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AccountCreatedScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Error al verificar: $e');
      setState(() => _submitting = false);
    }
  }

  void _handleSkip() {
    // El usuario ya está registrado con status 'no_iniciada'.
    // No necesitamos llamar a la DB porque el status inicial ya es ese.
    // Solo navegamos directamente.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AccountCreatedScreen()),
    );
  }

  void _showError(String msg) {
    setState(() => _errorMessage = msg);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Verificación')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verifica tu cuenta (opcional)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                _descriptionFor(auth.accountType),
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // ─── Error ───────────────────────────────────
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 20,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ─── Formulario según tipo ───────────────────
              Builder(
                builder: (context) {
                  switch (auth.accountType) {
                    case AccountType.estudiante:
                      return _buildStudentForm();
                    case AccountType.particular:
                      return _buildParticularForm();
                    case AccountType.negocio:
                      return _buildBusinessForm();
                  }
                },
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _handleVerify(auth),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verificar ahora'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _submitting ? null : _handleSkip,
                  child: const Text('Hacerlo después'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _descriptionFor(AccountType type) {
    switch (type) {
      case AccountType.estudiante:
        return 'Sube una foto de tu credencial universitaria para obtener el badge "Verificado UM".';
      case AccountType.particular:
        return 'Sube una foto de tu identificación oficial para obtener el badge "Identidad verificada".';
      case AccountType.negocio:
        return 'Registra los datos de tu negocio. Un administrador confirmará tu puesto manualmente.';
    }
  }

  // ─── Form: Estudiante ──────────────────────────────────────
  Widget _buildStudentForm() {
    return Column(
      children: [
        TextFormField(
          controller: _matriculaController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Matrícula *',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _carreraController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Carrera (opcional)',
            prefixIcon: Icon(Icons.school_rounded),
          ),
        ),
        const SizedBox(height: 14),
        _PhotoUploadTile(
          icon: Icons.credit_card_rounded,
          label: 'Foto de credencial universitaria *',
          path: _studentPhotoPath,
          selectedLabel: 'Credencial seleccionada ✓',
          onPick: () => setState(() {
            _studentPhotoPath =
                'mock_credencial_${DateTime.now().millisecondsSinceEpoch}.jpg';
          }),
        ),
      ],
    );
  }

  // ─── Form: Particular ──────────────────────────────────────
  Widget _buildParticularForm() {
    return Column(
      children: [
        TextFormField(
          controller: _fullNameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre completo (como aparece en el documento) *',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
        ),
        const SizedBox(height: 14),
        _PhotoUploadTile(
          icon: Icons.folder_copy_rounded,
          label: 'Identificación oficial *',
          path: _idDocPath,
          selectedLabel: 'Identificación seleccionada ✓',
          onPick: () => setState(() {
            _idDocPath =
                'mock_identificacion_${DateTime.now().millisecondsSinceEpoch}.jpg';
          }),
        ),
      ],
    );
  }

  // ─── Form: Negocio ─────────────────────────────────────────
  Widget _buildBusinessForm() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.teal.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Negocio registrado',
                      style: TextStyle(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Los datos de tu negocio ya fueron guardados durante el registro. '
                      'Un administrador revisará y confirmará tu puesto manualmente. '
                      'Te notificaremos cuando sea aprobado.',
                      style: TextStyle(
                        color: context.colors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoUploadTile extends StatelessWidget {
  const _PhotoUploadTile({
    required this.icon,
    required this.label,
    required this.path,
    required this.onPick,
    this.selectedLabel,
  });

  final IconData icon;
  final String label;
  final String? path;
  final VoidCallback onPick;
  final String? selectedLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: path != null ? AppColors.teal : context.colors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              path != null ? Icons.check_circle_rounded : icon,
              color: path != null ? AppColors.teal : context.colors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                path != null
                    ? (selectedLabel ?? 'Archivo seleccionado ✓')
                    : label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: path != null ? AppColors.teal : context.colors.ink,
                ),
              ),
            ),
            if (path == null)
              Icon(Icons.upload_file_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}
