import 'dart:math' as math;

import '../models/trip_model.dart';

/// Distancia (m) por debajo de la cual dos puntos se toman como el mismo lugar.
const double kSameEndpointMeters = 80;

double metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Inicio o fin del recorrido.
class RouteEndpoint {
  final String name;
  final double lat;
  final double lng;

  /// Parada que está en ese mismo punto (la primera para el inicio, la última para el fin):
  /// la línea de tiempo la marca en lugar de agregar otra fila. Null = el punto va aparte.
  final String? sectionId;

  /// true si el viaje no lo guarda (`startPoint`/`endPoint`) y se tomó de las paradas.
  final bool derived;

  const RouteEndpoint({required this.name, required this.lat, required this.lng, this.sectionId, this.derived = false});

  Map<String, dynamic> toPoint() => {'name': name, 'lat': lat, 'lng': lng};

  bool sameAs(RouteEndpoint? o) => o != null && metersBetween(lat, lng, o.lat, o.lng) < kSameEndpointMeters;
}

/// Inicio y fin de un viaje.
class RouteEndpoints {
  final RouteEndpoint? start;
  final RouteEndpoint? end;

  const RouteEndpoints(this.start, this.end);

  /// Ida y vuelta: empieza y termina en el mismo lugar.
  bool get roundTrip => start != null && start!.sameAs(end);

  bool get isEmpty => start == null && end == null;

  /// Etiqueta de una parada marcada como inicio, fin o ambos (null si no es ninguno).
  String? labelFor(String sectionId) {
    final s = start?.sectionId == sectionId, e = end?.sectionId == sectionId;
    if (s && e) return 'Inicio y fin';
    if (s) return 'Inicio';
    if (e) return 'Fin';
    return null;
  }
}

/// Inicio y fin del recorrido: los que guarda el viaje ([startPoint]/[endPoint]) o, si no
/// tiene, los que se deducen de las paradas: el punto de partida y el de llegada de un plan
/// hecho a mano (paradas con id `…_start` / `…_end`), el regreso al punto de partida de un
/// plan con IA (traslado final), o la primera y la última parada con ubicación.
/// [coordsOf] da la ubicación de una parada (por defecto, su lat/lng).
RouteEndpoints routeEndpointsOf({
  Map<String, dynamic>? startPoint,
  Map<String, dynamic>? endPoint,
  required List<TripSection> sections,
  (double, double)? Function(PlaceSection p)? coordsOf,
}) {
  (double, double)? at(PlaceSection p) =>
      coordsOf != null ? coordsOf(p) : (p.lat != null && p.lng != null ? (p.lat!, p.lng!) : null);
  final places = [
    for (final s in sections)
      if (s is PlaceSection && !s.unplanned && s.branchId == null && at(s) != null) s,
  ];
  final PlaceSection? first = places.isEmpty ? null : places.first;
  final PlaceSection? last = places.isEmpty ? null : places.last;

  String? near(PlaceSection? p, double lat, double lng) {
    if (p == null) return null;
    final c = at(p)!;
    return metersBetween(c.$1, c.$2, lat, lng) < kSameEndpointMeters ? p.id : null;
  }

  RouteEndpoint? fromPoint(Map<String, dynamic>? raw, PlaceSection? edge, String fallback) {
    final p = tripPointFrom(raw);
    if (p == null) return null;
    final lat = p['lat'] as double, lng = p['lng'] as double;
    final n = (p['name'] as String).trim();
    final id = near(edge, lat, lng);
    final name = n.isNotEmpty ? n : (id != null ? places.firstWhere((x) => x.id == id).title : fallback);
    return RouteEndpoint(name: name.isEmpty ? fallback : name, lat: lat, lng: lng, sectionId: id);
  }

  RouteEndpoint fromSection(PlaceSection p, String fallback) {
    final c = at(p)!;
    final t = p.title.trim();
    return RouteEndpoint(name: t.isEmpty ? fallback : t, lat: c.$1, lng: c.$2, sectionId: p.id, derived: true);
  }

  // Inicio
  RouteEndpoint? start = fromPoint(startPoint, first, 'Punto de partida');
  if (start == null) {
    final tagged = places.where((p) => p.id.endsWith('_start')).firstOrNull;
    final p = tagged ?? first;
    if (p != null) start = fromSection(p, 'Punto de partida');
  }

  // Fin
  RouteEndpoint? end = fromPoint(endPoint, last, 'Punto de llegada');
  if (end == null) {
    final tagged = places.where((p) => p.id.endsWith('_end')).lastOrNull;
    final lastBlock = sections.where((s) => s is! TextSection && s is! TextImageSection && s is! UnknownSection).lastOrNull;
    final bool returnsHome = lastBlock is TransferSection && lastBlock.notes.contains('Regreso al punto de partida');
    if (tagged != null) {
      end = fromSection(tagged, 'Punto de llegada');
    } else if (returnsHome && start != null) {
      // Plan con IA de ida y vuelta: termina con el traslado de regreso al inicio.
      end = RouteEndpoint(name: start.name, lat: start.lat, lng: start.lng, derived: true);
    } else if (last != null) {
      end = fromSection(last, 'Punto de llegada');
    }
  }
  return RouteEndpoints(start, end);
}
