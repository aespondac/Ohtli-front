import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Ubicación del dispositivo con su dirección aproximada.
class CurrentLocation {
  final double lat;
  final double lng;

  /// Dirección legible (calle, colonia, alcaldía); vacía si no se pudo obtener.
  final String address;
  const CurrentLocation(this.lat, this.lng, this.address);

  /// Dentro del área de la Ciudad de México y su zona conurbada.
  bool get inCdmx => lat >= 18.8 && lat <= 20.0 && lng >= -99.7 && lng <= -98.6;
}

/// Error con un mensaje listo para mostrar.
class CurrentLocationException implements Exception {
  final String message;
  const CurrentLocationException(this.message);
  @override
  String toString() => message;
}

/// Pide al navegador la ubicación actual (con el permiso del usuario) y busca su
/// dirección en OpenStreetMap (Nominatim).
Future<CurrentLocation> getCurrentLocation() async {
  final geo = web.window.navigator.geolocation;
  final completer = Completer<web.GeolocationPosition>();
  geo.getCurrentPosition(
    ((web.GeolocationPosition p) {
      if (!completer.isCompleted) completer.complete(p);
    }).toJS,
    ((web.GeolocationPositionError e) {
      if (completer.isCompleted) return;
      completer.completeError(CurrentLocationException(switch (e.code) {
        1 => 'Necesitamos permiso para ver tu ubicación. Actívalo en el candado de la barra de direcciones.',
        3 => 'Tu ubicación tardó demasiado. Intenta de nuevo.',
        _ => 'No pudimos obtener tu ubicación. Intenta de nuevo o busca la dirección.',
      }));
    }).toJS,
    web.PositionOptions(enableHighAccuracy: true, timeout: 15000, maximumAge: 60000),
  );
  final pos = await completer.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw const CurrentLocationException('Tu ubicación tardó demasiado. Intenta de nuevo.'),
  );
  final lat = pos.coords.latitude.toDouble();
  final lng = pos.coords.longitude.toDouble();
  return CurrentLocation(lat, lng, await _reverse(lat, lng));
}

Future<String> _reverse(double lat, double lng) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      'zoom': '18',
      'accept-language': 'es',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return '';
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! Map) return '';
    final a = data['address'];
    if (a is Map) {
      final street = [a['road'], a['house_number']].where((x) => x != null && '$x'.isNotEmpty).join(' ');
      final parts = [
        street,
        a['neighbourhood'] ?? a['suburb'] ?? a['quarter'],
        a['city_district'] ?? a['borough'] ?? a['municipality'],
      ].where((x) => x != null && '$x'.trim().isNotEmpty).map((x) => '$x').toList();
      if (parts.isNotEmpty) return parts.join(', ');
    }
    return (data['display_name'] ?? '').toString();
  } catch (_) {
    return '';
  }
}
