import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/presence_service.dart';
import '../../widgets/badges.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/online_status_avatar.dart';
import '../chat_screen.dart';

/// "Reportar un problema" del menú de ajustes: en vez de un formulario,
/// manda directo a chatear con las cuentas oficiales de soporte
/// (`getCuentasSoporte` en el backend). Mismo canal que cualquier otra
/// conversación, así que la respuesta llega por donde la persona ya revisa
/// sus mensajes, sin un buzón aparte que nadie mira.
class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  late Future<List<Seller>> _contactos;

  @override
  void initState() {
    super.initState();
    _contactos = ApiService.getSupportContacts();
  }

  Future<void> _abrirChat(Seller contacto) async {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && auth.backendSellerId == contacto.id) return;

    // Mismo patrón que el botón "Contactar por chat" del perfil público:
    // busca primero si ya hay un hilo directo, para no abrir el chat en
    // blanco cuando ya se le reportó algo antes a esta misma cuenta.
    String conversationId = '';
    try {
      conversationId =
          await ApiService.getDirectConversationId(contacto.id) ?? '';
    } catch (_) {
      // Sin conexión: se abre igual con hilo vacío.
    }
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          sellerId: contacto.id,
          otherUser: ChatUser.deSeller(contacto),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('report_problem.title'.tr())),
      body: FutureBuilder<List<Seller>>(
        future: _contactos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppListSkeleton(itemCount: 3);
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'report_problem.load_error'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.muted),
                ),
              ),
            );
          }
          final contactos = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: [
              Text(
                'report_problem.intro'.tr(),
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < contactos.length; i++) ...[
                _ContactoSoporteTile(
                  contacto: contactos[i],
                  // La primera cuenta de la lista es la de "Reportes"
                  // (`CORREOS_SOPORTE` la manda primero en el backend); el
                  // resto son administradores.
                  rol: i == 0
                      ? 'report_problem.role_reports'.tr()
                      : 'report_problem.role_admin'.tr(),
                  onTap: () => _abrirChat(contactos[i]),
                ),
                if (i != contactos.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Tarjeta de contacto con el mismo lenguaje visual que una fila de la
/// bandeja de chats (radio 14, sombra suave, avatar con punto de conexión),
/// para que se sienta parte de la misma app y no un aviso aparte.
class _ContactoSoporteTile extends StatelessWidget {
  const _ContactoSoporteTile({
    required this.contacto,
    required this.rol,
    required this.onTap,
  });

  final Seller contacto;
  final String rol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enLinea = context
        .watch<PresenceService>()
        .estadoDe(contacto.id)
        .enLinea;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: context.colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.colors.border, width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: context.colors.primary.withValues(alpha: 0.06),
          highlightColor: context.colors.primary.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                OnlineStatusAvatar(
                  radius: 24,
                  iniciales: contacto.avatarInitials,
                  imageUrl:
                      contacto.logoUrl != null && contacto.logoUrl!.isNotEmpty
                      ? '${ApiService.baseUrl}${contacto.logoUrl}'
                      : null,
                  enLinea: enLinea,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              contacto.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.colors.ink,
                                fontSize: 15,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          InsigniaCuenta.deSeller(contacto, size: 14),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        rol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: context.colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: context.colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
