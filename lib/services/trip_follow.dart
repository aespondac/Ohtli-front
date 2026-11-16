import 'dart:math' as math;

import '../models/trip_model.dart';
import 'trip_transfers.dart';

/// Seguir el viaje con la ubicación: llegada y salida automáticas y la hora de salir.
/// Aquí solo va la lógica (sin navegador) para poder probarla con horas inventadas.

/// Una lectura de la ubicación.
class GeoFix {
  final double lat;
  final double lng;

  /// Radio de precisión, en metros.
  final double accuracy;
  final DateTime at;
  const GeoFix(this.lat, this.lng, this.accuracy, this.at);
}

/// Parada con ubicación, la única que se puede detectar.
class FollowStop {
  final String id;
  final double lat;
  final double lng;
  const FollowStop(this.id, this.lat, this.lng);
}

enum FollowEventKind { arrive, leave }

class FollowEvent {
  final FollowEventKind kind;
  final String stopId;

  /// Cuándo pasó de verdad: al entrar (llegada) o al alejarse (salida), no cuando se confirmó.
  final DateTime at;
  const FollowEvent(this.kind, this.stopId, this.at);

  @override
  String toString() => '${kind.name}:$stopId@${at.toIso8601String()}';
}

double distanceMeters(double lat1, double lng1, double lat2, double lng2) => haversineKm(lat1, lng1, lat2, lng2) * 1000;

/// Detecta llegadas y salidas. Para no marcar una parada por la que solo se pasa, la llegada
/// se confirma tras [arriveDwell] dentro del radio, y la salida tras [leaveDwell] lejos de él.
class TripFollower {
  static const Duration arriveDwell = Duration(minutes: 3);
  static const Duration leaveDwell = Duration(minutes: 2);

  /// Una ubicación más vieja que esto ya no cuenta.
  static const Duration staleAfter = Duration(minutes: 5);

  /// Lecturas menos precisas que esto (en metros) se ignoran.
  static const double maxAccuracy = 150;

  /// Radio de llegada: 75 m más la imprecisión de la lectura, hasta 120 m.
  static double insideRadius(double accuracy) => 75 + math.min(accuracy, 45).toDouble();

  /// Para la salida hay que alejarse 100 m más (así no rebota en la orilla).
  static double outsideRadius(double accuracy) => insideRadius(accuracy) + 100;

  GeoFix? _last;
  String? _candidate;
  DateTime? _enteredAt;
  String? _watchingLeave;
  DateTime? _outsideSince;
  final Set<String> _handled = {};

  GeoFix? get lastFix => _last;

  /// Después de una marca automática (o de deshacerla) esa parada ya no se vuelve a marcar sola.
  void suppress(FollowEventKind kind, String stopId) => _handled.add('${kind.name}:$stopId');

  void reset() {
    _last = null;
    _candidate = null;
    _enteredAt = null;
    _watchingLeave = null;
    _outsideSince = null;
  }

  /// Procesa una lectura nueva ([fix]) o solo el paso del tiempo (sin [fix]: quien no se
  /// mueve casi no recibe lecturas). [pending]: paradas a las que aún no llegan, en orden.
  /// [here]: la parada donde están (llegaron y no se han ido), si tiene ubicación.
  List<FollowEvent> step({required DateTime now, GeoFix? fix, required List<FollowStop> pending, FollowStop? here}) {
    if (fix != null && fix.accuracy <= maxAccuracy) _last = fix;
    final f = _last;
    if (f == null || now.difference(f.at) > staleAfter) return const [];
    final events = <FollowEvent>[];

    // Salida de donde están.
    if (here != null && !_handled.contains('leave:${here.id}')) {
      if (_watchingLeave != here.id) {
        _watchingLeave = here.id;
        _outsideSince = null;
      }
      final d = distanceMeters(f.lat, f.lng, here.lat, here.lng);
      if (d > outsideRadius(f.accuracy)) {
        _outsideSince ??= f.at;
      } else if (d <= insideRadius(f.accuracy)) {
        _outsideSince = null;
      }
      if (_outsideSince != null && !now.isBefore(_outsideSince!.add(leaveDwell))) {
        events.add(FollowEvent(FollowEventKind.leave, here.id, _outsideSince!));
        _handled.add('leave:${here.id}');
        _outsideSince = null;
      }
    } else {
      _watchingLeave = null;
      _outsideSince = null;
    }

    // Llegada: a la siguiente parada o a la de después (por si se saltan una).
    FollowStop? best;
    double bestD = double.infinity;
    for (final s in pending.take(2)) {
      if (_handled.contains('arrive:${s.id}')) continue;
      final d = distanceMeters(f.lat, f.lng, s.lat, s.lng);
      if (d <= insideRadius(f.accuracy) && d < bestD) {
        best = s;
        bestD = d;
      }
    }
    if (best != null) {
      if (_candidate != best.id) {
        _candidate = best.id;
        _enteredAt = f.at;
      }
    } else if (_candidate != null) {
      // Se olvida si ya no está entre las siguientes o si se alejaron con holgura.
      FollowStop? c;
      for (final s in pending.take(2)) {
        if (s.id == _candidate) c = s;
      }
      if (c == null || distanceMeters(f.lat, f.lng, c.lat, c.lng) > insideRadius(f.accuracy) + 25) {
        _candidate = null;
        _enteredAt = null;
      }
    }
    if (_candidate != null && _enteredAt != null && !now.isBefore(_enteredAt!.add(arriveDwell))) {
      events.add(FollowEvent(FollowEventKind.arrive, _candidate!, _enteredAt!));
      _handled.add('arrive:$_candidate');
      _candidate = null;
      _enteredAt = null;
    }
    return events;
  }
}

/// La hora "HH:mm" en el día [day].
DateTime? atClock(DateTime day, String? hhmm) {
  final m = parseClockMinutes(hhmm);
  if (m == null) return null;
  return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
}

/// Minutos para llegar a [to]: desde la ubicación actual si se conoce, si no desde la parada
/// [from]; con el medio del traslado que va antes de [to]. Si no hay ubicaciones, el tiempo
/// que dice ese traslado.
int? travelMinutesTo(List<TripSection> sections, PlaceSection to, {PlaceSection? from, GeoFix? fix}) {
  final t = transferBefore(sections, sections.indexOf(to));
  if (to.lat != null && to.lng != null) {
    double? lat, lng;
    if (fix != null) {
      lat = fix.lat;
      lng = fix.lng;
    } else if (from?.lat != null && from?.lng != null) {
      lat = from!.lat;
      lng = from.lng;
    }
    if (lat != null && lng != null) {
      final mode = transferModeOf(t?.mode ?? 'walking');
      final km = haversineKm(lat, lng, to.lat!, to.lng!) * 1.3;
      final wait = (mode.id == 'metro' || mode.id == 'metrobus' || mode.id == 'bus') ? 8 : (mode.id == 'taxi' ? 5 : 0);
      final live = math.max(1, (km / mode.kmh * 60).round() + wait);
      // Lo planeado manda si es más largo (incluye esperas que la línea recta no ve).
      return math.max(live, t?.durationMins ?? 0);
    }
  }
  return t?.durationMins;
}

/// Cuándo salir de una parada.
class LeavePlan {
  final DateTime leaveBy;

  /// La parada que sigue y a qué hora hay que llegar (si el plan lo dice).
  final PlaceSection? next;
  final DateTime? arriveBy;
  final int? travelMins;
  const LeavePlan(this.leaveBy, {this.next, this.arriveBy, this.travelMins});
}

/// Hora de salir de [here]: la llegada planeada a [next] menos el traslado; si no se puede
/// calcular, la salida planeada de [here].
LeavePlan? leavePlanFor({required DateTime day, required PlaceSection here, PlaceSection? next, int? travelMins}) {
  final arriveBy = next == null ? null : atClock(day, next.arrivalTime);
  if (arriveBy != null && travelMins != null) {
    return LeavePlan(arriveBy.subtract(Duration(minutes: travelMins)), next: next, arriveBy: arriveBy, travelMins: travelMins);
  }
  final dep = atClock(day, here.departureTime);
  if (dep != null) return LeavePlan(dep, next: next, arriveBy: arriveBy, travelMins: travelMins);
  return null;
}

enum LeaveAlert { soon, now }

/// Qué aviso toca a la hora [now]: "sal en un rato" [soonBefore] antes, "es hora de salir" a
/// la hora y hasta [window] después. Más tarde ya no se avisa.
LeaveAlert? leaveAlertAt(DateTime now, DateTime leaveBy,
    {Duration soonBefore = const Duration(minutes: 10), Duration window = const Duration(minutes: 20)}) {
  if (now.isBefore(leaveBy.subtract(soonBefore))) return null;
  if (now.isBefore(leaveBy)) return LeaveAlert.soon;
  if (now.isBefore(leaveBy.add(window))) return LeaveAlert.now;
  return null;
}

String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Título y cuerpo del aviso para salir de [here]. Con Ohtli cerrado, el mismo texto lo arma el
/// servidor (functions/trip_follow.js); test/fixtures/leave_alert_cases.dart prueba los dos.
({String title, String body}) leaveAlertText({
  required List<TripSection> sections,
  required PlaceSection here,
  required LeavePlan plan,
  required LeaveAlert alert,
  required DateTime now,
}) {
  final name = here.title.trim().isEmpty ? 'esta parada' : here.title.trim();
  final next = plan.next;
  final nextName = next == null ? '' : (next.title.trim().isEmpty ? 'la siguiente parada' : next.title.trim());
  final String body;
  if (next != null && plan.arriveBy != null) {
    final mode = transferModeOf(transferBefore(sections, sections.indexOf(next))?.mode ?? 'walking');
    final trip = plan.travelMins != null ? ' (unos ${formatDuration(plan.travelMins!)}${mode.verb.isEmpty ? '' : ' ${mode.verb}'})' : '';
    body = 'Para llegar a $nextName a las ${_clock(plan.arriveBy!)}$trip.';
  } else {
    body = 'El plan era salir a las ${_clock(plan.leaveBy)}${next != null ? ' rumbo a $nextName' : ''}.';
  }
  final String title;
  if (alert == LeaveAlert.soon) {
    final mins = math.max(1, (plan.leaveBy.difference(now).inSeconds / 60).ceil());
    title = 'Sal en $mins min de $name';
  } else {
    title = 'Es hora de salir de $name';
  }
  return (title: title, body: body);
}

/// "350 m" o "1.2 km".
String formatMeters(double m) => m < 1000 ? '${(m / 10).round() * 10} m' : '${(m / 1000).toStringAsFixed(1)} km';
