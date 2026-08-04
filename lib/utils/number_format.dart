/// Formatea un número entero de forma compacta para mostrar en la UI
/// (ej. contadores de vistas): 999 → "999", 1500 → "1.5k", 25000 → "25k",
/// 1200000 → "1.2M".
String formatCompactNumber(int value) {
  if (value < 1000) return '$value';

  if (value < 1000000) {
    final k = value / 1000;
    return '${_trimDecimal(k)}k';
  }

  final m = value / 1000000;
  return '${_trimDecimal(m)}M';
}

String _trimDecimal(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toStringAsFixed(1);
}
