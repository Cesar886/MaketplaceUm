import '../models.dart';
import 'anon_session.dart';
import 'api_service.dart';

class SupportConversation {
  const SupportConversation({
    required this.contact,
    required this.conversationId,
  });

  final Seller contact;
  final String conversationId;
}

/// Prepara exclusivamente el chat con la primera cuenta oficial que devuelve
/// el backend (Reportes). La identidad anónima está firmada por el servidor y
/// no reutiliza el JWT de la cuenta suspendida o baneada.
Future<SupportConversation> prepareReportsConversation() async {
  await AnonSession.ensure();
  final contacts = await ApiService.getSupportContacts();
  if (contacts.isEmpty) {
    throw StateError('La cuenta oficial de Reportes no está disponible.');
  }
  final contact = contacts.first;
  final conversationId =
      await ApiService.getDirectConversationId(contact.id) ?? '';
  return SupportConversation(
    contact: contact,
    conversationId: conversationId,
  );
}
