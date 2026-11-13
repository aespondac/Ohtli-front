import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/trip_model.dart';

/// Datos de cada modo de traslado. Las velocidades y tarifas son referencias
/// para estimar en CDMX; la persona siempre puede corregirlas.
class TransferMode {
  final String id;
  final String label;
  final String verb; // "a pie", "en metro"…
  final IconData icon;
  final double kmh;
  final double baseCostMxn;
  final double costPerKmMxn;
  final String googleTravelMode; // walking | transit | driving | bicycling

  const TransferMode(this.id, this.label, this.verb, this.icon, this.kmh, this.baseCostMxn, this.costPerKmMxn,
      this.googleTravelMode);
}

const List<TransferMode> kTransferModes = [
  TransferMode('walking', 'Caminando', 'a pie', Icons.directions_walk_rounded, 4.5, 0, 0, 'walking'),
  TransferMode('metro', 'Metro', 'en metro', Icons.subway_rounded, 25, 5, 0, 'transit'),
  TransferMode('metrobus', 'Metrobús', 'en metrobús', Icons.directions_bus_filled_rounded, 18, 6, 0, 'transit'),
  TransferMode('bus', 'Camión / pesero', 'en camión', Icons.directions_bus_rounded, 14, 7, 0, 'transit'),
  TransferMode('bike', 'Bici (Ecobici)', 'en bici', Icons.pedal_bike_rounded, 13, 0, 0, 'bicycling'),
  TransferMode('taxi', 'Taxi / app', 'en taxi', Icons.local_taxi_rounded, 20, 35, 9, 'driving'),
  TransferMode('car', 'Auto propio', 'en auto', Icons.directions_car_rounded, 20, 0, 0, 'driving'),
  TransferMode('other', 'Otro', '', Icons.alt_route_rounded, 15, 0, 0, 'transit'),
];

TransferMode transferModeOf(String id) =>
    kTransferModes.firstWhere((m) => m.id == id, orElse: () => kTransferModes.first);

/// Normaliza los modos que entrega el motor ("walking", "foot", "transit"…).
String normalizeTransferMode(String? raw) {
  final r = (raw ?? '').toLowerCase();
  if (r.contains('walk') || r.contains('foot') || r.contains('pie')) return 'walking';
  if (r.contains('metrob')) return 'metrobus';
  if (r.contains('metro') || r.contains('subway') || r.contains('transit')) return 'metro';
  if (r.contains('bus') || r.contains('cami')) return 'bus';
  if (r.contains('bik') || r.contains('bici') || r.contains('cycl')) return 'bike';
  if (r.contains('taxi') || r.contains('uber') || r.contains('didi')) return 'taxi';
  if (r.contains('car') || r.contains('driv') || r.contains('auto')) return 'car';
  return r.isEmpty ? 'walking' : 'other';
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Estima un traslado entre dos paradas con coordenadas. La distancia en línea
/// recta se multiplica por 1.3 para aproximar el recorrido por calles.
TransferSection? estimateTransfer(PlaceSection from, PlaceSection to, String modeId, {required String id}) {
  if (from.lat == null || from.lng == null || to.lat == null || to.lng == null) return null;
  final mode = transferModeOf(modeId);
  final km = haversineKm(from.lat!, from.lng!, to.lat!, to.lng!) * 1.3;
  // Transporte público: suma unos minutos de espera y transbordo.
  final wait = (mode.id == 'metro' || mode.id == 'metrobus' || mode.id == 'bus') ? 8 : (mode.id == 'taxi' ? 5 : 0);
  final mins = math.max(1, (km / mode.kmh * 60).round() + wait);
  final cost = mode.baseCostMxn + mode.costPerKmMxn * km;
  return TransferSection(
    id: id,
    mode: mode.id,
    durationMins: mins,
    distanceKm: double.parse(km.toStringAsFixed(2)),
    cost: cost.roundToDouble(),
    isEstimated: true,
  );
}

int? parseClockMinutes(String? value) {
  if (value == null) return null;
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String formatClock(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String formatDuration(int mins) {
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final r = mins % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

String describeTransfer(TransferSection t) {
  final mode = transferModeOf(t.mode);
  final parts = <String>[];
  if (t.durationMins != null) parts.add(formatDuration(t.durationMins!));
  if (t.distanceKm != null && t.distanceKm! > 0) {
    parts.add(t.distanceKm! < 1 ? '${(t.distanceKm! * 1000).round()} m' : '${t.distanceKm!.toStringAsFixed(1)} km');
  }
  final head = parts.isEmpty ? mode.label : parts.join(' · ');
  return mode.verb.isEmpty ? head : '$head ${mode.verb}';
}

/// Traslado que va justo antes de la parada [placeIndex] (entre ella y la parada
/// anterior), si existe.
TransferSection? transferBefore(List<TripSection> sections, int placeIndex) {
  for (int i = placeIndex - 1; i >= 0; i--) {
    final s = sections[i];
    if (s is TransferSection) return s;
    if (s is PlaceSection) return null;
  }
  return null;
}

/// Inserta traslados estimados entre paradas consecutivas que no tengan uno.
/// Devuelve la nueva lista y cuántos se agregaron.
(List<TripSection>, int) fillMissingTransfers(List<TripSection> sections, String modeId, String Function() newId) {
  final out = <TripSection>[];
  PlaceSection? lastPlace;
  bool sawTransfer = false;
  int added = 0;
  for (final s in sections) {
    if (s is PlaceSection) {
      if (lastPlace != null && !sawTransfer) {
        final t = estimateTransfer(lastPlace, s, modeId, id: newId());
        if (t != null) {
          // Justo antes de la parada, aunque haya notas entre medio.
          out.add(t);
          added++;
        }
      }
      lastPlace = s;
      sawTransfer = false;
    } else if (s is TransferSection) {
      sawTransfer = true;
    }
    out.add(s);
  }
  return (out, added);
}

/// Recalcula los horarios en cascada: llegada = salida anterior + traslado;
/// salida = llegada + estancia (la que ya tenía la parada, o [defaultStayMins]).
/// La primera parada conserva su hora de llegada (o [startTime]).
List<TripSection> recalculateSchedule(List<TripSection> sections,
    {String startTime = '10:00', int defaultStayMins = 60}) {
  final out = <TripSection>[];
  int? clock;
  int pendingTransfer = 0;
  for (final s in sections) {
    if (s is TransferSection) {
      pendingTransfer += s.durationMins ?? 0;
      out.add(s);
      continue;
    }
    if (s is! PlaceSection) {
      out.add(s);
      continue;
    }
    final a = parseClockMinutes(s.arrivalTime);
    final d = parseClockMinutes(s.departureTime);
    final stay = (a != null && d != null && d > a) ? d - a : defaultStayMins;
    final arrival = clock == null ? (a ?? parseClockMinutes(startTime) ?? 600) : clock + pendingTransfer;
    final departure = arrival + stay;
    out.add(s.copyWith(arrivalTime: formatClock(arrival), departureTime: formatClock(departure)));
    clock = departure;
    pendingTransfer = 0;
  }
  return out;
}
