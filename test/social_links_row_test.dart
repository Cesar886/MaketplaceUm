import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mercadito_um/models.dart';
import 'package:mercadito_um/widgets/social_links_row.dart';

Seller _seller({
  String? facebookUrl,
  String? instagramUrl,
  String? whatsappNumber,
  String? tiktokUrl,
  String? twitterUrl,
}) {
  return Seller(
    name: 'Negocio Test',
    avatarInitials: 'NT',
    major: '',
    isBusiness: true,
    rating: 0,
    reviews: 0,
    verified: true,
    facebookUrl: facebookUrl,
    instagramUrl: instagramUrl,
    whatsappNumber: whatsappNumber,
    tiktokUrl: tiktokUrl,
    twitterUrl: twitterUrl,
  );
}

void main() {
  test('sin ninguna red social, la lista de entradas está vacía', () {
    expect(buildSocialLinkEntries(_seller()), isEmpty);
  });

  test('solo agrega entradas para los campos llenos', () {
    final entries = buildSocialLinkEntries(
      _seller(facebookUrl: 'https://facebook.com/negocio', tiktokUrl: 'https://tiktok.com/@negocio'),
    );
    expect(entries.length, 2);
    expect(entries.map((e) => e.label), containsAll(['Facebook', 'TikTok']));
  });

  test('WhatsApp arma el link wa.me a partir del número crudo', () {
    final entries = buildSocialLinkEntries(_seller(whatsappNumber: '5215512345678'));
    expect(entries.single.url, 'https://wa.me/5215512345678');
    expect(entries.single.icon, FontAwesomeIcons.whatsapp);
  });

  test('las demás plataformas usan la URL guardada tal cual', () {
    final entries = buildSocialLinkEntries(_seller(instagramUrl: 'https://instagram.com/negocio'));
    expect(entries.single.url, 'https://instagram.com/negocio');
  });
}
