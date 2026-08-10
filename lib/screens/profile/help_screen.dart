import 'package:flutter/material.dart';

import '../../app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = <(String, String)>[
    (
      '¿Cómo publico un producto?',
      'Ve a la pestaña "Publicar", elige una categoría, agrega fotos, '
          'título, descripción y precio, y confirma para que quede visible '
          'en el feed.',
    ),
    (
      '¿Cómo contacto a un vendedor?',
      'Abre el detalle de un producto y toca "Contactar" para iniciar un '
          'chat directo con el vendedor dentro de la app.',
    ),
    (
      '¿Cómo funciona la verificación de cuenta?',
      'Desde tu perfil puedes iniciar la verificación subiendo tu '
          'credencial universitaria o identificación. Un administrador '
          'revisa la solicitud y activa el badge correspondiente.',
    ),
    (
      '¿Cómo reporto un problema?',
      'En el perfil del usuario o dentro de un chat encontrarás la opción '
          'de reportar. Describe la situación y el equipo de soporte la '
          'revisará.',
    ),
    (
      '¿Cómo contacto a soporte?',
      'Escríbenos a soporte@mercaditoum.site y te responderemos en un '
          'plazo máximo de 48 horas hábiles.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: _faqs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final (question, answer) = _faqs[index];
            return Container(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: ExpansionTile(
                title: Text(
                  question,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answer,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
