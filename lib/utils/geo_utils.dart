import 'dart:math';

import 'package:easy_localization/easy_localization.dart';

/// Coordenadas de referencia de la Universidad de Montemorelos (N.L.).
/// Aproximadas — reemplazar por el valor exacto del pin si se necesita
/// mayor precisión.
const double campusLat = 25.1875;
const double campusLng = -99.8283;

const double _earthRadiusKm = 6371;
const double _walkingSpeedKmh = 5;

/// Distancia en línea recta (km) entre dos coordenadas, vía Haversine.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_degToRad(lat1)) *
          cos(_degToRad(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return _earthRadiusKm * c;
}

double _degToRad(double deg) => deg * (pi / 180);

/// Distancia de una coordenada al campus, en km.
double distanceToCampusKm(double lat, double lng) {
  return distanceKm(lat, lng, campusLat, campusLng);
}

/// Texto corto tipo "a 8 min caminando del campus", asumiendo ~5 km/h.
String campusDistanceLabel(double lat, double lng) {
  final km = distanceToCampusKm(lat, lng);
  final minutes = (km / _walkingSpeedKmh * 60).round().clamp(1, 999);
  return 'map.walking_from_campus'.tr(namedArgs: {'minutes': '$minutes'});
}
