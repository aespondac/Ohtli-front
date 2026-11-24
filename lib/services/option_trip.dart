import '../models/trip_model.dart';
import '../theme/cdmx_photos.dart';
import 'trip_transfers.dart';

// De una alternativa del motor al viaje guardado. Lo usan el planificador (lo que se ve al
// elegir) y saveOptionAsTrip (lo que queda guardado), para que las dos pantallas digan lo mismo.

/// Foto propia del lugar que trae una parada del motor. Vacía si no tiene o si es una de las
/// fotos de referencia de [CdmxPhotos] (de otro lugar de la ciudad).
String ownStopPhoto(Map stop) {
  final raw = (stop['photo_url'] ?? stop['main_photo_url'] ?? stop['image_url'] ?? stop['photo'] ?? '').toString().trim();
  return CdmxPhotos.isReference(raw) ? '' : raw;
}

(double, double)? _coordsOf(Map stop) {
  double? lat = (stop['lat'] as num?)?.toDouble();
  double? lng = (stop['lng'] as num?)?.toDouble();
  final loc = stop['location'];
  if ((lat == null || lng == null) && loc is Map) {
    lat = (loc['lat'] as num?)?.toDouble();
    lng = (loc['lng'] as num?)?.toDouble();
  }
  if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;
  return (lat, lng);
}

/// Portada de una alternativa y del viaje que se guarda con ella: la primera foto propia de sus
/// paradas o, si ninguna tiene, una postal de la CDMX de la zona del recorrido. Antes el viaje
/// guardado tomaba la foto de referencia de la categoría de la primera parada (la Casa Azul para
/// un recorrido de museos del Centro) y el planificador mostraba otra.
String optionCover(Map option, {int seed = 0}) {
  final given = (option['cover_url'] ?? '').toString().trim();
  if (given.isNotEmpty && !CdmxPhotos.isReference(given)) return given;
  final stops = (option['route'] as List?) ?? const [];
  for (final s in stops) {
    if (s is Map) {
      final own = ownStopPhoto(s);
      if (own.isNotEmpty) return own;
    }
  }
  final pts = [for (final s in stops) if (s is Map) ?_coordsOf(s)];
  if (pts.isEmpty) return CdmxPhotos.cover(seed);
  final lat = pts.fold<double>(0, (a, p) => a + p.$1) / pts.length;
  final lng = pts.fold<double>(0, (a, p) => a + p.$2) / pts.length;
  return CdmxPhotos.coverNear(lat, lng, seed);
}

/// Semilla de la portada de una alternativa: la misma en la tarjeta del planificador y en el
/// viaje guardado.
int optionCoverSeed(Map option) => (option['editorial_headline'] ?? option['theme'] ?? '').toString().hashCode;

/// Tramo de salida: del punto de partida a la primera parada, con los minutos y kilómetros que
/// el motor ya cuenta en sus totales. Antes no se guardaba y el viaje decía 3.2 km donde la
/// propuesta decía 4.1. Null si la ruta empieza en la primera parada (sin punto de partida).
TransferSection? departureLeg(Map option, {required String id}) {
  final stops = (option['route'] as List?) ?? const [];
  if (stops.isEmpty || stops.first is! Map) return null;
  final first = stops.first as Map;
  final mins = (first['travel_time_from_prev_mins'] as num?)?.toInt();
  final km = (first['travel_distance_from_prev_km'] as num?)?.toDouble();
  if ((km ?? 0) <= 0.05 && (mins ?? 0) <= 0) return null;
  return TransferSection(
    id: id,
    mode: normalizeTransferMode((first['transport_mode'] ?? option['transport_mode'])?.toString()),
    durationMins: mins,
    distanceKm: km,
    cost: (first['transport_cost_mxn'] as num?)?.toDouble() ?? 0.0,
    notes: 'Salida desde el punto de partida',
    isEstimated: true,
  );
}

/// Jornada de la alternativa como la cuenta el viaje guardado ([tripTimeSpan]): salida del punto
/// de partida (primera llegada menos el tramo de salida) hasta el regreso (última salida más el
/// tramo final). La duración del motor contaba desde la hora de inicio del tema aunque la ruta
/// esperara a que abriera la primera parada (demo E1: 7 h 35 min en la propuesta y 7 h 11 min en
/// el viaje guardado). Null sin horarios.
({int start, int end})? optionTimeSpan(Map option) {
  final route = [for (final s in (option['route'] as List? ?? const [])) if (s is Map) s];
  if (route.isEmpty) return null;
  final arrivals = [for (final s in route) ?parseClockMinutes(s['arrival_time']?.toString())];
  final departures = [for (final s in route) ?parseClockMinutes(s['departure_time']?.toString())];
  if (arrivals.isEmpty || departures.isEmpty) return null;
  final firstLeg = (route.first['travel_time_from_prev_mins'] as num?)?.toInt() ?? 0;
  final finalLeg = option['final_leg'] is Map ? (num.tryParse('${(option['final_leg'] as Map)['mins']}') ?? 0).toInt() : 0;
  final start = arrivals.reduce((a, b) => a < b ? a : b) - firstLeg;
  final end = departures.reduce((a, b) => a > b ? a : b) + finalLeg;
  return end > start ? (start: start, end: end) : null;
}
