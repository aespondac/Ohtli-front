import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/trip_follow.dart';

// Dos paradas a ~1 km: Bellas Artes y el Zócalo.
const bellas = FollowStop('bellas', 19.4352, -99.1412);
const zocalo = FollowStop('zocalo', 19.4326, -99.1332);

GeoFix at(FollowStop s, DateTime t, {double dLat = 0, double acc = 20}) => GeoFix(s.lat + dLat, s.lng, acc, t);

PlaceSection place(String id, {String? arrival, String? departure, double? lat, double? lng}) => PlaceSection(
      id: id,
      title: id,
      description: '',
      rating: 0,
      mainPhotoUrl: '',
      secondaryPhotoUrls: const [],
      arrivalTime: arrival,
      departureTime: departure,
      lat: lat,
      lng: lng,
    );

void main() {
  final t0 = DateTime(2026, 11, 15, 12, 0);

  group('TripFollower', () {
    test('marca la llegada tras 3 minutos cerca, con la hora en que entraron', () {
      final f = TripFollower();
      expect(f.step(now: t0, fix: at(bellas, t0), pending: [bellas, zocalo]), isEmpty);
      // A los 2 minutos todavía no.
      expect(f.step(now: t0.add(const Duration(minutes: 2)), pending: [bellas, zocalo]), isEmpty);
      final e = f.step(now: t0.add(const Duration(minutes: 3)), pending: [bellas, zocalo]);
      expect(e, hasLength(1));
      expect(e.single.kind, FollowEventKind.arrive);
      expect(e.single.stopId, 'bellas');
      expect(e.single.at, t0);
      // No se repite.
      expect(f.step(now: t0.add(const Duration(minutes: 4)), pending: [bellas, zocalo]), isEmpty);
    });

    test('pasar de largo no cuenta como llegada', () {
      final f = TripFollower();
      f.step(now: t0, fix: at(bellas, t0), pending: [bellas, zocalo]);
      // Al minuto ya van 500 m más allá.
      final t1 = t0.add(const Duration(minutes: 1));
      f.step(now: t1, fix: at(bellas, t1, dLat: 0.0045), pending: [bellas, zocalo]);
      expect(f.step(now: t0.add(const Duration(minutes: 5)), pending: [bellas, zocalo]), isEmpty);
    });

    test('marca la salida al alejarse 2 minutos, con la hora en que se alejaron', () {
      final f = TripFollower();
      f.step(now: t0, fix: at(bellas, t0), pending: [zocalo], here: bellas);
      final t1 = t0.add(const Duration(minutes: 30));
      expect(f.step(now: t1, fix: at(bellas, t1, dLat: 0.003), pending: [zocalo], here: bellas), isEmpty);
      final e = f.step(now: t1.add(const Duration(minutes: 2)), pending: [zocalo], here: bellas);
      expect(e.map((x) => x.toString()), ['leave:bellas@${t1.toIso8601String()}']);
    });

    test('en la orilla no rebota: entre los dos radios no sale', () {
      final f = TripFollower();
      // ~150 m: fuera del radio de llegada (95 m) pero dentro del de salida (195 m).
      f.step(now: t0, fix: at(bellas, t0, dLat: 0.00135), pending: [zocalo], here: bellas);
      expect(f.step(now: t0.add(const Duration(minutes: 10)), pending: [zocalo], here: bellas), isEmpty);
    });

    test('ignora lecturas imprecisas y las que ya son viejas', () {
      final f = TripFollower();
      f.step(now: t0, fix: at(bellas, t0, acc: 400), pending: [bellas]);
      expect(f.lastFix, isNull);
      f.step(now: t0, fix: at(bellas, t0), pending: [bellas]);
      expect(f.step(now: t0.add(const Duration(minutes: 6)), pending: [bellas]), isEmpty);
    });

    test('solo mira las dos siguientes paradas y respeta lo deshecho', () {
      final f = TripFollower();
      const lejos = FollowStop('lejos', 19.30, -99.10);
      f.step(now: t0, fix: at(zocalo, t0), pending: [lejos, bellas, zocalo]);
      expect(f.step(now: t0.add(const Duration(minutes: 4)), pending: [lejos, bellas, zocalo]), isEmpty);

      final g = TripFollower()..suppress(FollowEventKind.arrive, 'bellas');
      g.step(now: t0, fix: at(bellas, t0), pending: [bellas]);
      expect(g.step(now: t0.add(const Duration(minutes: 4)), pending: [bellas]), isEmpty);
    });
  });

  group('Hora de salir', () {
    final day = DateTime(2026, 11, 15);

    test('llegada planeada a la siguiente menos el traslado', () {
      final here = place('a', departure: '14:00');
      final next = place('b', arrival: '15:00');
      final plan = leavePlanFor(day: day, here: here, next: next, travelMins: 25)!;
      expect(plan.leaveBy, DateTime(2026, 11, 15, 14, 35));
      expect(plan.arriveBy, DateTime(2026, 11, 15, 15, 0));
    });

    test('sin hora de llegada, la salida planeada', () {
      final plan = leavePlanFor(day: day, here: place('a', departure: '14:00'), next: place('b'), travelMins: 25)!;
      expect(plan.leaveBy, DateTime(2026, 11, 15, 14, 0));
      expect(leavePlanFor(day: day, here: place('a'), next: place('b')), isNull);
    });

    test('avisa 10 minutos antes, a la hora y deja de avisar después', () {
      final leaveBy = DateTime(2026, 11, 15, 14, 35);
      expect(leaveAlertAt(DateTime(2026, 11, 15, 14, 20), leaveBy), isNull);
      expect(leaveAlertAt(DateTime(2026, 11, 15, 14, 26), leaveBy), LeaveAlert.soon);
      expect(leaveAlertAt(DateTime(2026, 11, 15, 14, 35), leaveBy), LeaveAlert.now);
      expect(leaveAlertAt(DateTime(2026, 11, 15, 15, 0), leaveBy), isNull);
    });

    test('el traslado desde la ubicación actual no es menor que el planeado', () {
      final a = place('a', lat: bellas.lat, lng: bellas.lng);
      final b = place('b', lat: zocalo.lat, lng: zocalo.lng);
      final sections = <TripSection>[a, TransferSection(id: 't', mode: 'walking', durationMins: 30), b];
      // ~1 km × 1.3 a pie ≈ 17 min, pero el plan dice 30.
      expect(travelMinutesTo(sections, b, from: a), 30);
      final far = GeoFix(19.40, -99.14, 20, DateTime(2026));
      expect(travelMinutesTo(sections, b, fix: far)!, greaterThan(30));
    });
  });
}
