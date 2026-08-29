import 'package:flutter/material.dart';

import 'legal_document_screen.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(namespace: 'legal.privacy', sections: 11);
  }
}
