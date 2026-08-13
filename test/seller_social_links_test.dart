import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/models.dart';

void main() {
  test('Seller.fromJson lee los 5 campos de redes sociales', () {
    final seller = Seller.fromJson({
      'id': 's1',
      'name': 'Negocio Test',
      'avatarInitials': 'NT',
      'major': '',
      'isBusiness': true,
      'rating': 4.5,
      'reviews': 10,
      'verified': true,
      'facebookUrl': 'https://facebook.com/negocio',
      'instagramUrl': 'https://instagram.com/negocio',
      'whatsappNumber': '5215512345678',
      'tiktokUrl': 'https://tiktok.com/@negocio',
      'twitterUrl': 'https://x.com/negocio',
    });

    expect(seller.facebookUrl, 'https://facebook.com/negocio');
    expect(seller.instagramUrl, 'https://instagram.com/negocio');
    expect(seller.whatsappNumber, '5215512345678');
    expect(seller.tiktokUrl, 'https://tiktok.com/@negocio');
    expect(seller.twitterUrl, 'https://x.com/negocio');
  });

  test('Seller.fromJson deja los campos en null cuando el backend no los manda', () {
    final seller = Seller.fromJson({
      'id': 's2',
      'name': 'Negocio Viejo',
      'avatarInitials': 'NV',
      'major': '',
      'isBusiness': true,
      'rating': 0,
      'reviews': 0,
      'verified': true,
    });

    expect(seller.facebookUrl, isNull);
    expect(seller.instagramUrl, isNull);
    expect(seller.whatsappNumber, isNull);
    expect(seller.tiktokUrl, isNull);
    expect(seller.twitterUrl, isNull);
  });
}
