import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../config/locales.dart';

/// Selector del idioma de la interfaz.
///
/// El cambio se aplica de inmediato: `context.setLocale()` reconstruye el
/// árbol entero desde el `EasyLocalization` que envuelve a la app en
/// `main.dart`, así que no hace falta reiniciar ni avisarle a nadie más.
/// La preferencia queda guardada en disco por el propio paquete.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  Future<void> _seleccionar(BuildContext context, Locale locale) async {
    if (context.locale == locale) return;

    await context.setLocale(locale);
    if (!context.mounted) return;

    // El nombre sale ya en el idioma nuevo: para cuando aparece el snackbar
    // el cambio está aplicado, y verlo en el idioma anterior se leería como
    // si no hubiera surtido efecto.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'language.changed'.tr(
            namedArgs: {'language': AppLocales.claveNombre(locale).tr()},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final actual = context.locale;

    return Scaffold(
      appBar: AppBar(title: Text('language.title'.tr())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'language.header'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'language.description'.tr(),
              style: TextStyle(fontSize: 13, height: 1.4, color: colors.muted),
            ),
            const SizedBox(height: 18),

            for (final locale in AppLocales.localesSoportados)
              _LanguageOption(
                locale: locale,
                seleccionado: locale.languageCode == actual.languageCode,
                onTap: () => _seleccionar(context, locale),
              ),

            const SizedBox(height: 10),
            _CurrentLanguageBanner(locale: actual),
          ],
        ),
      ),
    );
  }
}

/// Fila de un idioma. Sigue el mismo lenguaje visual que `OptionTile`
/// (tarjeta con borde sutil sobre surface elevado), con el estado
/// seleccionado marcado en el acento del swatch activo.
class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.locale,
    required this.seleccionado,
    required this.onTap,
  });

  final Locale locale;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: seleccionado ? colors.accentTintBorder : colors.border,
          width: seleccionado ? 1.5 : 1,
        ),
      ),
      // El fondo va en el Material, no en este Container: ListTile pinta su
      // ripple sobre el Material ancestro más cercano, y un Container con
      // color de por medio lo tapa (error en debug de Flutter).
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: seleccionado ? colors.accentTint : colors.surfaceElevated,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          leading: Icon(
            Icons.translate_rounded,
            color: seleccionado ? colors.accent : colors.primary,
          ),
          // El nombre principal va en su propio idioma ("English", no
          // "Inglés"): quien viene a esta pantalla puede no entender el
          // idioma activo, y su lengua debe reconocerla sin traducción.
          title: Text(
            AppLocales.nombreNativo(locale),
            style: TextStyle(fontWeight: FontWeight.w700, color: colors.ink),
          ),
          subtitle: Text(
            AppLocales.claveNombre(locale).tr(),
            style: TextStyle(fontSize: 12, color: colors.muted),
          ),
          trailing: seleccionado
              ? Icon(Icons.check_circle_rounded, color: colors.accent)
              : Icon(Icons.circle_outlined, color: colors.border),
        ),
      ),
    );
  }
}

/// Recuadro con el idioma activo. Redundante con la palomita de la lista a
/// propósito: es la respuesta directa a "¿en qué idioma estoy?", sin que
/// haya que interpretar un icono.
class _CurrentLanguageBanner extends StatelessWidget {
  const _CurrentLanguageBanner({required this.locale});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.neutralBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${'language.current'.tr()}: ',
                    style: TextStyle(fontSize: 13, color: colors.muted),
                  ),
                  TextSpan(
                    text: AppLocales.nombreNativo(locale),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
