import 'package:flutter/material.dart';

import '../../app_theme.dart';

class CookiesScreen extends StatelessWidget {
  const CookiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aviso de Cookies')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(
              'Aviso de Cookies',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Última actualización: 22 de julio de 2026',
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const _SectionC(
              title: '¿Qué son las cookies?',
              body:
                  'Las cookies son pequeños archivos de texto que se almacenan '
                  'en tu dispositivo (computadora, tableta, teléfono) cuando '
                  'visitas una aplicación o sitio web. Permiten que la Plataforma '
                  'recuerde tus preferencias y mejore tu experiencia de uso.',
            ),
            const _SectionC(
              title: 'Tipos de cookies que utilizamos',
              body:
                  'Cookies esenciales: Necesarias para el funcionamiento básico '
                  'de la Plataforma. Permiten la autenticación del usuario, '
                  'la navegación y el acceso a funciones seguras. Sin estas '
                  'cookies, la Plataforma no puede funcionar correctamente.\n\n'
                  'Cookies de preferencias: Recuerdan tus preferencias y '
                  'configuración (como el tipo de cuenta o filtros de búsqueda) '
                  'para personalizar tu experiencia.\n\n'
                  'Cookies analíticas: Recopilan información anónima sobre cómo '
                  'los usuarios interactúan con la Plataforma (páginas más '
                  'visitadas, tiempo de uso, errores). Usamos esta información '
                  'para mejorar el servicio.\n\n'
                  'Cookies de sesión: Temporales y se eliminan cuando cierras '
                  'la aplicación. Permiten mantener tu sesión activa mientras '
                  'usas la Plataforma.',
            ),
            const _SectionC(
              title: 'Cookies de terceros',
              body:
                  'Actualmente no utilizamos cookies de terceros (servicios '
                  'de publicidad, redes sociales, etc.). En caso de implementarlas '
                  'en el futuro, actualizaremos este aviso y te lo notificaremos.',
            ),
            const _SectionC(
              title: 'Cómo controlar las cookies',
              body:
                  'Puedes gestionar las cookies desde la configuración de tu '
                  'dispositivo o navegador. La mayoría de los navegadores te '
                  'permiten:\n\n'
                  '• Bloquear todas las cookies.\n'
                  '• Aceptar solo cookies de sitios específicos.\n'
                  '• Eliminar cookies almacenadas.\n'
                  '• Configurar notificaciones antes de aceptar cookies.\n\n'
                  'Si deshabilitas las cookies esenciales, algunas funciones '
                  'de la Plataforma podrían no estar disponibles.',
            ),
            const _SectionC(
              title: 'Consentimiento',
              body:
                  'Al usar Mercadito UM, aceptas el uso de cookies esenciales '
                  'y de preferencias necesarias para el funcionamiento de la '
                  'Plataforma. Para las cookies analíticas, solicitaremos tu '
                  'consentimiento explícito la primera vez que uses la app.',
            ),
            const _SectionC(
              title: 'Actualizaciones',
              body:
                  'Podemos actualizar este Aviso de Cookies periódicamente. '
                  'Te notificaremos cualquier cambio significativo a través de '
                  'la Plataforma.',
            ),
            const _SectionC(
              title: 'Contacto',
              body:
                  'Si tienes preguntas sobre nuestro uso de cookies, '
                  'contáctanos en: mercadito@um.edu.mx',
            ),
            const SizedBox(height: 12),
            Divider(color: context.colors.border),
            const SizedBox(height: 12),
            Text(
              'Al continuar usando Mercadito UM, aceptas el uso de cookies '
              'según lo descrito en este aviso.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionC extends StatelessWidget {
  const _SectionC({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: context.colors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(height: 1.5, color: context.colors.ink)),
        ],
      ),
    );
  }
}
