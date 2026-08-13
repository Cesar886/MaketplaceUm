import 'package:flutter_test/flutter_test.dart';
import 'package:mercadito_um/validation/social_links.dart';

void main() {
  test('acepta una URL https del dominio correcto', () {
    expect(
      validateSocialUrl('facebook', 'https://facebook.com/minegocio'),
      isNull,
    );
    expect(validateSocialUrl('twitter', 'https://x.com/minegocio'), isNull);
  });

  test('vacío es válido (campo opcional)', () {
    expect(validateSocialUrl('facebook', ''), isNull);
    expect(validateWhatsappNumber(''), isNull);
  });

  test('rechaza el dominio de otra plataforma', () {
    expect(
      validateSocialUrl('instagram', 'https://facebook.com/minegocio'),
      isNotNull,
    );
  });

  test('rechaza http', () {
    expect(
      validateSocialUrl('tiktok', 'http://tiktok.com/@minegocio'),
      isNotNull,
    );
  });

  test('WhatsApp: acepta solo dígitos con código de país', () {
    expect(validateWhatsappNumber('5215512345678'), isNull);
  });

  test('WhatsApp: rechaza el signo + y espacios', () {
    expect(validateWhatsappNumber('+52 155 1234 5678'), isNotNull);
  });

  test('WhatsApp: rechaza menos de 10 dígitos', () {
    expect(validateWhatsappNumber('123'), isNotNull);
  });
}
