import 'package:flutter/material.dart';

import '../../app_theme.dart';
import 'register_form_screen.dart';

class RegisterTypeScreen extends StatelessWidget {
  const RegisterTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Cómo quieres registrarte?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige el tipo de cuenta que mejor describa tu rol.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _TypeCard(
                      emoji: '🎓',
                      title: 'Estudiante',
                      subtitle:
                          'Alumno activo de la Universidad de Montemorelos',
                      features: ['Publica libros, apuntes, electrónicos y más'],
                      color: AppColors.teal,
                      onTap: () => _goToForm(context, 'estudiante'),
                    ),
                    const SizedBox(height: 12),
                    _TypeCard(
                      emoji: '🏪',
                      title: 'Negocio',
                      subtitle: 'Puesto dentro o cerca del campus',
                      features: [
                        'Vende comida, papelería, servicios y más',
                        'Confirmación manual por administrador',
                      ],
                      color: AppColors.gold,
                      onTap: () => _goToForm(context, 'negocio'),
                    ),
                    const SizedBox(height: 12),
                    _TypeCard(
                      emoji: '🧑',
                      title: 'Particular',
                      subtitle: 'Persona externa a la universidad',
                      features: [
                        'Ofrece hospedaje, servicios y productos',
                        'Verifica tu identidad opcionalmente',
                      ],
                      color: AppColors.orange,
                      onTap: () => _goToForm(context, 'particular'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToForm(BuildContext context, String type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterFormScreen(userType: type),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.features,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<String> features;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final f in features) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 6),
                          child: Icon(Icons.check_rounded,
                              size: 16, color: AppColors.teal),
                        ),
                        Expanded(
                          child: Text(
                            f,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
