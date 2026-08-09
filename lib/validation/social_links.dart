/// Validación de redes sociales del negocio, espejo de
/// backend/src/validation/sellerProfile.js (validateSocialUrl /
/// validateWhatsappNumber) para dar feedback inmediato en el editor sin
/// esperar la respuesta del servidor. La validación real y autoritativa
/// sigue viviendo en el backend.
library;

const socialUrlHosts = <String, Set<String>>{
  'facebook': {'facebook.com', 'www.facebook.com', 'fb.com', 'm.facebook.com'},
  'instagram': {'instagram.com', 'www.instagram.com'},
  'tiktok': {'tiktok.com', 'www.tiktok.com'},
  'twitter': {'twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'},
};

const socialUrlLabels = <String, String>{
  'facebook': 'Facebook',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'twitter': 'X/Twitter',
};

const _maxSocialUrlLength = 200;
final _whatsappNumberRegex = RegExp(r'^\d{10,15}$');

/// Devuelve el mensaje de error, o null si [value] es válido (vacío incluido).
String? validateSocialUrl(String platform, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final label = socialUrlLabels[platform]!;
  if (trimmed.length > _maxSocialUrlLength) {
    return 'El link de $label no puede superar $_maxSocialUrlLength caracteres';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return 'El link de $label no es una dirección web válida';
  }
  if (uri.scheme != 'https') {
    return 'El link de $label debe empezar con https://';
  }
  if (!socialUrlHosts[platform]!.contains(uri.host.toLowerCase())) {
    return 'El link debe ser de $label';
  }
  return null;
}

/// Devuelve el mensaje de error, o null si [value] es válido (vacío incluido).
String? validateWhatsappNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (!_whatsappNumberRegex.hasMatch(trimmed)) {
    return 'El número de WhatsApp debe tener solo dígitos con código de país (10 a 15 dígitos)';
  }
  return null;
}
