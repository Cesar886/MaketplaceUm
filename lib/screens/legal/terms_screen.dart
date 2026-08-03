import 'package:flutter/material.dart';

import '../../app_theme.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y Condiciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(
              'Términos y Condiciones de Uso',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Última actualización: 22 de julio de 2026',
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const _Section(
              title: '1. Aceptación de los términos',
              body:
                  'Al registrarte y utilizar Mercadito UM ("la Plataforma"), '
                  'aceptas los presentes Términos y Condiciones. Si no estás de acuerdo, '
                  'no debes usar la Plataforma. Estos términos constituyen un acuerdo '
                  'legal vinculante entre tú ("el Usuario") y los administradores de '
                  'Mercadito UM ("la Administración").',
            ),
            const _Section(
              title: '2. Descripción del servicio',
              body:
                  'Mercadito UM es una plataforma universitaria que conecta '
                  'miembros de la comunidad de la Universidad de Montemorelos '
                  'para la compra, venta e intercambio de productos y servicios '
                  'entre estudiantes, personal académico y negocios locales cercanos '
                  'al campus. La Plataforma actúa únicamente como intermediario '
                  'y no participa en las transacciones entre usuarios.',
            ),
            const _Section(
              title: '3. Elegibilidad',
              body:
                  'Para usar Mercadito UM debes:\n\n'
                  '• Ser mayor de 18 años o tener autorización de un tutor legal.\n'
                  '• Ser miembro de la comunidad UM (estudiante, docente, '
                  'administrativo) o un negocio local afiliado.\n'
                  '• Proporcionar información veraz y actualizada durante el registro.\n'
                  '• No tener cuenta suspendida previamente por violar estos términos.',
            ),
            const _Section(
              title: '4. Registro y cuenta',
              body:
                  'Eres responsable de mantener la confidencialidad de tu '
                  'contraseña y de todas las actividades que ocurran en tu cuenta. '
                  'Debes notificar inmediatamente a la Administración sobre '
                  'cualquier uso no autorizado de tu cuenta. La Administración '
                  'no será responsable por pérdidas derivadas del uso no autorizado '
                  'de tu cuenta.',
            ),
            const _Section(
              title: '5. Conducta del usuario',
              body:
                  'Al usar la Plataforma, aceptas:\n\n'
                  '• No publicar productos o servicios prohibidos (armas, sustancias '
                  'ilegales, contenido fraudulento, etc.).\n'
                  '• No acosar, amenazar o discriminar a otros usuarios.\n'
                  '• No usar la Plataforma para fines ilegales o no autorizados.\n'
                  '• No interferir con el funcionamiento de la Plataforma.\n'
                  '• No suplantar la identidad de otra persona o entidad.\n'
                  '• Publicar descripciones precisas y fotografías reales de los productos.\n\n'
                  'El incumplimiento puede resultar en la suspensión o eliminación '
                  'de tu cuenta sin previo aviso.',
            ),
            const _Section(
              title: '6. Publicaciones y contenido',
              body:
                  'Al publicar contenido en Mercadito UM, declaras que:\n\n'
                  '• Tienes derecho a vender el producto u ofrecer el servicio.\n'
                  '• Toda la información proporcionada es veraz y no engañosa.\n'
                  '• El contenido no infringe derechos de propiedad intelectual de terceros.\n\n'
                  'La Administración se reserva el derecho de eliminar cualquier '
                  'publicación que considere inapropiada o que viole estos términos, '
                  'sin previo aviso ni responsabilidad.',
            ),
            const _Section(
              title: '7. Transacciones y pagos',
              body:
                  'Mercadito UM facilita el contacto entre compradores y vendedores, '
                  'pero no procesa pagos ni garantiza transacciones. Los acuerdos '
                  'de precio, forma de pago, entrega y cualquier另一 condición '
                  'son responsabilidad exclusiva de las partes involucradas. '
                  'Recomendamos:\n\n'
                  '• Coordinar entregas en espacios públicos del campus.\n'
                  '• Inspeccionar los productos antes de pagar.\n'
                  '• Conservar evidencia de la transacción (mensajes, comprobantes).',
            ),
            const _Section(
              title: '8. Planes destacados (Highlight)',
              body:
                  'Los planes de visibilidad pagada ("Highlight") son opcionales '
                  'y no garantizan la venta del producto. El pago de estos planes '
                  'se realiza a través de los métodos habilitados en la Plataforma. '
                  'Los planes adquiridos no son reembolsables, salvo disposición '
                  'legal aplicable. La Administración se reserva el derecho de '
                  'modificar los precios y las características de los planes '
                  'con aviso previo en la Plataforma.',
            ),
            const _Section(
              title: '9. Verificación de cuentas',
              body:
                  'La verificación de identidad (credencial universitaria, '
                  'identificación oficial o registro de negocio) es voluntaria '
                  'y tiene fines de generar confianza en la comunidad. La '
                  'Administración no garantiza la exactitud de la información '
                  'verificada ni se hace responsable por el uso que terceros '
                  'puedan darle.',
            ),
            const _Section(
              title: '10. Privacidad y protección de datos',
              body:
                  'El tratamiento de tus datos personales se rige por nuestra '
                  'Política de Privacidad, disponible en la sección correspondiente '
                  'de la Plataforma. Al usar Mercadito UM, aceptas las prácticas '
                  'descritas en dicha política.',
            ),
            const _Section(
              title: '11. Limitación de responsabilidad',
              body:
                  'Mercadito UM se proporciona "tal cual" y "según disponibilidad". '
                  'La Administración no garantiza que la Plataforma sea ininterrumpida, '
                  'segura o libre de errores. En la máxima medida permitida por la ley, '
                  'la Administración no será responsable por:\n\n'
                  '• Daños directos, indirectos, incidentales o consecuentes.\n'
                  '• Pérdida de datos, ingresos o oportunidades de negocio.\n'
                  '• Disputas entre usuarios de la Plataforma.\n'
                  '• Contenido publicado por terceros.',
            ),
            const _Section(
              title: '12. Modificaciones',
              body:
                  'La Administración se reserva el derecho de modificar estos '
                  'términos en cualquier momento. Los cambios serán notificados '
                  'a través de la Plataforma o por correo electrónico. El uso '
                  'continuado de la Plataforma después de la notificación '
                  'constituye aceptación de los nuevos términos.',
            ),
            const _Section(
              title: '13. Terminación',
              body:
                  'La Administración puede suspender o terminar tu acceso a la '
                  'Plataforma en cualquier momento, sin previo aviso, si '
                  'determina que has violado estos términos. Puedes eliminar tu '
                  'cuenta en cualquier momento desde la configuración de perfil. '
                  'Las disposiciones sobre limitación de responsabilidad y '
                  'privacidad sobrevivirán a la terminación.',
            ),
            const _Section(
              title: '14. Ley aplicable',
              body:
                  'Estos términos se rigen por las leyes de los Estados Unidos '
                  'Mexicanos. Cualquier controversia relacionada con estos '
                  'términos será resuelta en los tribunales competentes de '
                  'Montemorelos, Nuevo León.',
            ),
            const _Section(
              title: '15. Contacto',
              body:
                  'Si tienes preguntas sobre estos términos, contáctanos en:\n'
                  'Correo: mercadito@um.edu.mx\n'
                  'Dirección: Universidad de Montemorelos, '
                  'Montemorelos, Nuevo León, México.',
            ),
            const SizedBox(height: 12),
            Divider(color: context.colors.border),
            const SizedBox(height: 12),
            Text(
              'Al usar Mercadito UM, confirmas que has leído, entendido y '
              'aceptado estos Términos y Condiciones.',
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

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
