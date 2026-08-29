import 'package:flutter/material.dart';

import 'legal_document_screen.dart';

class CookiesScreen extends StatelessWidget {
  const CookiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(namespace: 'legal.cookies', sections: 7);
  }
}
