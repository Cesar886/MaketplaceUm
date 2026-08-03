import 'package:flutter/material.dart';

import '../../app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Política de Privacidad')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(
              'Política de Privacidad',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Última actualización: 22 de julio de 2026',
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const _SectionP(
              title: '1. Responsable del tratamiento',
              body:
                  'Mercadito UM, parte de la Universidad de Montemorelos '
                  '(en adelante, "la Plataforma"), es el responsable del '
                  'tratamiento de tus datos personales. Nuestro domicilio se '
                  'ubica en Montemorelos, Nuevo León, México.',
            ),
            const _SectionP(
              title: '2. Datos personales que recopilamos',
              body:
                  'Podemos recopilar las siguientes categorías de datos:\n\n'
                  '• Datos de identificación: nombre completo, correo electrónico, '
                  'número de teléfono.\n'
                  '• Datos académicos: matrícula, carrera, semestre (solo para '
                  'cuentas de estudiante).\n'
                  '• Datos de identificación oficial: fotografía de credencial '
                  'universitaria o identificación oficial (solo para verificación).\n'
                  '• Datos de negocio: nombre del negocio, tipo, ubicación, '
                  'horario (solo para cuentas de negocio).\n'
                  '• Datos de uso: interacciones en la Plataforma, publicaciones, '
                  'favoritos, carrito de compras.\n'
                  '• Datos técnicos: dirección IP, tipo de dispositivo, '
                  'sistema operativo, versión de la app.',
            ),
            const _SectionP(
              title: '3. Finalidades del tratamiento',
              body:
                  'Utilizamos tus datos personales para:\n\n'
                  'Finalidades necesarias:\n'
                  '• Crear y gestionar tu cuenta en la Plataforma.\n'
                  '• Permitir la publicación de productos y servicios.\n'
                  '• Facilitar la comunicación entre compradores y vendedores.\n'
                  '• Verificar la identidad de los usuarios (cuando aplique).\n'
                  '• Enviar notificaciones sobre tu actividad en la Plataforma.\n'
                  '• Dar cumplimiento a obligaciones legales.\n\n'
                  'Finalidades opcionales (sujetas a tu consentimiento):\n'
                  '• Enviar comunicaciones promocionales sobre planes destacados.\n'
                  '• Realizar análisis estadísticos para mejorar la Plataforma.',
            ),
            const _SectionP(
              title: '4. Base legal del tratamiento',
              body:
                  'El tratamiento de tus datos se basa en:\n\n'
                  '• Tu consentimiento expreso al aceptar esta Política de Privacidad.\n'
                  '• La relación contractual derivada de los Términos y Condiciones.\n'
                  '• El interés legítimo de la Plataforma para mejorar sus servicios.\n'
                  '• El cumplimiento de obligaciones legales aplicables.',
            ),
            const _SectionP(
              title: '5. Transferencia de datos',
              body:
                  'Tus datos personales no serán compartidos con terceros '
                  'no relacionados con la Plataforma, salvo:\n\n'
                  '• Cuando sea necesario para cumplir con una obligación legal.\n'
                  '• Cuando medie tu consentimiento expreso.\n'
                  '• Con autoridades competentes en el ejercicio de sus funciones.\n\n'
                  'Los datos de perfil (nombre, foto, calificación) son visibles '
                  'para otros usuarios de la Plataforma según tu configuración.',
            ),
            const _SectionP(
              title: '6. Derechos ARCO',
              body:
                  'Tienes derecho a:\n\n'
                  '• Acceso: Conocer qué datos personales tenemos sobre ti.\n'
                  '• Rectificación: Solicitar la corrección de datos inexactos.\n'
                  '• Cancelación: Solicitar la eliminación de tus datos.\n'
                  '• Oposición: Oponerte al tratamiento de tus datos para fines '
                  'específicos.\n\n'
                  'Para ejercer estos derechos, envía un correo a '
                  'mercadito@um.edu.mx con el asunto "Derechos ARCO". '
                  'Responderemos a tu solicitud en un plazo máximo de 20 días hábiles.',
            ),
            const _SectionP(
              title: '7. Seguridad de los datos',
              body:
                  'Implementamos medidas de seguridad administrativas, técnicas '
                  'y físicas para proteger tus datos personales contra daño, '
                  'pérdida, alteración, destrucción o uso no autorizado. Sin '
                  'embargo, ninguna transmisión por internet es completamente segura.',
            ),
            const _SectionP(
              title: '8. Conservación de datos',
              body:
                  'Conservamos tus datos personales mientras mantengas una cuenta '
                  'activa en la Plataforma. Al eliminar tu cuenta, conservaremos '
                  'cierta información durante el periodo exigido por las leyes '
                  'aplicables para fines de cumplimiento legal y resolución de disputas.',
            ),
            const _SectionP(
              title: '9. Cookies y tecnologías similares',
              body:
                  'Utilizamos cookies y tecnologías similares para mejorar tu '
                  'experiencia en la Plataforma. Puedes consultar más detalles '
                  'en nuestro Aviso de Cookies disponible en la sección '
                  'correspondiente.',
            ),
            const _SectionP(
              title: '10. Cambios a esta política',
              body:
                  'Nos reservamos el derecho de actualizar esta Política de '
                  'Privacidad en cualquier momento. Los cambios serán notificados '
                  'a través de la Plataforma. Te recomendamos revisar esta '
                  'política periódicamente.',
            ),
            const _SectionP(
              title: '11. Contacto',
              body:
                  'Si tienes dudas sobre esta Política de Privacidad o sobre '
                  'el tratamiento de tus datos personales, contáctanos en:\n\n'
                  'Correo: mercadito@um.edu.mx\n'
                  'Dirección: Universidad de Montemorelos, '
                  'Montemorelos, Nuevo León, México.',
            ),
            const SizedBox(height: 12),
            Divider(color: context.colors.border),
            const SizedBox(height: 12),
            Text(
              'Al usar Mercadito UM, confirmas que has leído y entendido '
              'esta Política de Privacidad.',
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

class _SectionP extends StatelessWidget {
  const _SectionP({required this.title, required this.body});

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
