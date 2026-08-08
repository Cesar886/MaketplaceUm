import 'package:flutter/material.dart';

import '../../widgets/comments_received_list.dart';

/// Los comentarios que otros dejaron en MIS publicaciones.
///
/// Vive como pantalla propia y no como pestaña del perfil porque
/// `profile_screen.dart` no tiene una sección "Publicaciones" que partir en
/// dos: es una lista de métricas y opciones, y las publicaciones propias ya
/// están en su propia pantalla (`MyListingsScreen`). Meterle pestañas a un
/// menú de ajustes sería forzar el patrón donde no encaja.
///
/// El contenido es exactamente el mismo widget que la pestaña "Comentarios"
/// del perfil público del vendedor, para que el dueño vea su respaldo social
/// tal como lo ve un comprador.
class MyCommentsScreen extends StatelessWidget {
  const MyCommentsScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comentarios')),
      body: SafeArea(
        child: CommentsReceivedList(
          userId: userId,
          esPerfilPropio: true,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        ),
      ),
    );
  }
}
