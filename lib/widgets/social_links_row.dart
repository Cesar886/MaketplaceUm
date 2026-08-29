import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models.dart';

class SocialLinkEntry {
  const SocialLinkEntry({
    required this.icon,
    required this.url,
    required this.label,
  });

  final FaIconData icon;
  final String url;
  final String label;
}

/// Una entrada por cada red social que el negocio llenó, en orden fijo
/// (Facebook, Instagram, WhatsApp, TikTok, X/Twitter). Lista vacía si no
/// llenó ninguna — [SocialLinksRow] se omite por completo en ese caso.
List<SocialLinkEntry> buildSocialLinkEntries(Seller seller) {
  final entries = <SocialLinkEntry>[];
  final facebookUrl = seller.facebookUrl;
  if (facebookUrl != null && facebookUrl.isNotEmpty) {
    entries.add(
      SocialLinkEntry(
        icon: FontAwesomeIcons.facebook,
        url: facebookUrl,
        label: 'Facebook',
      ),
    );
  }
  final instagramUrl = seller.instagramUrl;
  if (instagramUrl != null && instagramUrl.isNotEmpty) {
    entries.add(
      SocialLinkEntry(
        icon: FontAwesomeIcons.instagram,
        url: instagramUrl,
        label: 'Instagram',
      ),
    );
  }
  final whatsappNumber = seller.whatsappNumber;
  if (whatsappNumber != null && whatsappNumber.isNotEmpty) {
    entries.add(
      SocialLinkEntry(
        icon: FontAwesomeIcons.whatsapp,
        url: 'https://wa.me/$whatsappNumber',
        label: 'WhatsApp',
      ),
    );
  }
  final tiktokUrl = seller.tiktokUrl;
  if (tiktokUrl != null && tiktokUrl.isNotEmpty) {
    entries.add(
      SocialLinkEntry(
        icon: FontAwesomeIcons.tiktok,
        url: tiktokUrl,
        label: 'TikTok',
      ),
    );
  }
  final twitterUrl = seller.twitterUrl;
  if (twitterUrl != null && twitterUrl.isNotEmpty) {
    entries.add(
      SocialLinkEntry(
        icon: FontAwesomeIcons.xTwitter,
        url: twitterUrl,
        label: 'social.twitter'.tr(),
      ),
    );
  }
  return entries;
}

/// Fila de íconos de redes sociales del negocio. Se omite por completo
/// (sin espacio reservado) cuando el negocio no llenó ninguna.
class SocialLinksRow extends StatelessWidget {
  const SocialLinksRow({super.key, required this.seller});

  final Seller seller;

  Future<void> _open(BuildContext context, SocialLinkEntry entry) async {
    final uri = Uri.parse(entry.url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'social.open_error'.tr(namedArgs: {'network': entry.label}),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = buildSocialLinkEntries(seller);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: InkWell(
              onTap: () => _open(context, entry),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: FaIcon(entry.icon, size: 22, color: context.colors.ink),
              ),
            ),
          ),
      ],
    );
  }
}
