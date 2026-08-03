import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_type_screen.dart';

/// Muro de registro "justo a tiempo": aparece solo cuando alguien sin sesión
/// intenta publicar (producto o "se busca"), nunca antes. El copy deja claro
/// que la cuenta es para publicar, no un login desconectado del contexto.
class PublishAuthGate extends StatelessWidget {
  const PublishAuthGate({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.storefront_rounded,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.primary),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.heading(18),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RegisterTypeScreen(),
                  ),
                ),
                child: const Text('Crear cuenta'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
                child: const Text('Ya tengo cuenta'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
