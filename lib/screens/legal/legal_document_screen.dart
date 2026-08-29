import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';

/// Pantalla base de los tres documentos legales (términos, privacidad,
/// cookies).
///
/// Los tres tenían el mismo cuerpo y su propia copia del widget de sección;
/// aquí viven una sola vez. El texto NO está en el código: cada documento es
/// un bloque de `assets/translations` bajo [namespace], con las secciones
/// numeradas `s1_title`/`s1_body` … `sN_title`/`sN_body`. Numeradas y no una
/// lista porque easy_localization resuelve claves planas, y así una sección
/// nueva es un cambio de JSON más subir [sections].
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.namespace,
    required this.sections,
  });

  /// Prefijo de las claves, p. ej. `legal.terms`.
  final String namespace;

  /// Cuántas secciones numeradas tiene el documento.
  final int sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$namespace.title'.tr())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(
              '$namespace.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '$namespace.updated'.tr(),
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            for (var i = 1; i <= sections; i++)
              _LegalSection(
                title: '$namespace.s${i}_title'.tr(),
                body: '$namespace.s${i}_body'.tr(),
              ),
            const SizedBox(height: 12),
            Divider(color: context.colors.border),
            const SizedBox(height: 12),
            Text(
              '$namespace.footer'.tr(),
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

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, required this.body});

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
