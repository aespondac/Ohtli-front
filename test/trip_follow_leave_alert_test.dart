import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/models/trip_model.dart';
import 'package:othli_front/services/trip_follow.dart';
import 'package:othli_front/services/trip_follow_remote.dart';

import 'fixtures/leave_alert_cases.dart';

String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Lo que calcula el visor (_hereStop, _pendingStops, _leavePlanFor y _checkLeaveAlert) sin la
/// ubicación en vivo, que es lo mismo que hace el servidor con Ohtli cerrado.
Map<String, dynamic>? appAlert(List<TripSection> sections, DateTime now) {
  final places = sections.whereType<PlaceSection>().toList();
  PlaceSection? here;
  for (final p in places.reversed) {
    if (p.arrivedAt != null && p.leftAt == null) {
      here = p;
      break;
    }
  }
  if (here == null) return null;
  final pending = [for (final p in places) if (p.arrivedAt == null && !identical(p, here)) p];
  final next = pending.isEmpty ? null : pending.first;
  final mins = next == null ? null : travelMinutesTo(sections, next, from: here);
  final plan = leavePlanFor(day: DateTime(now.year, now.month, now.day), here: here, next: next, travelMins: mins);
  if (plan == null) return null;
  final alert = leaveAlertAt(now, plan.leaveBy);
  if (alert == null) return null;
  final text = leaveAlertText(sections: sections, here: here, plan: plan, alert: alert, now: now);
  return {
    'alert': alert.name,
    'stopId': here.id,
    'nextId': next?.id,
    'leaveBy': hhmm(plan.leaveBy),
    'travelMins': plan.travelMins,
    'title': text.title,
    'body': text.body,
  };
}

void main() {
  // Los mismos casos que prueba el servidor (functions/test/trip_follow.test.js).
  group('aviso para salir: igual en la app y en el servidor', () {
    final cases = (jsonDecode(leaveAlertCasesJson) as List).cast<Map<String, dynamic>>();
    test('hay casos', () => expect(cases.length, greaterThan(5)));
    for (final c in cases) {
      test(c['name'], () {
        final sections = [for (final s in c['sections'] as List) TripSection.fromMap(Map<String, dynamic>.from(s as Map))];
        final parts = (c['now'] as String).split(':').map(int.parse).toList();
        final now = DateTime(2026, 11, 15, parts[0], parts[1], parts.length > 2 ? parts[2] : 0);
        expect(appAlert(sections, now), c['expected']);
      });
    }
  });

  group('trip_follows', () {
    test('id y día local', () {
      expect(TripFollowRemote.followId('viaje1', 'ana'), 'viaje1_ana');
      expect(TripFollowRemote.dayOf(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    });

    test('campos al encender (los que aceptan las reglas)', () {
      final f = TripFollowRemote.startFields(
        uid: 'ana',
        ownerId: 'luis',
        tripId: 'viaje1',
        now: DateTime(2026, 11, 15, 9),
        timeZone: 'America/Mexico_City',
        updatedAt: 'ahora',
      );
      expect(f.keys.toSet(), {'uid', 'ownerId', 'tripId', 'day', 'tz', 'tzOffsetMin', 'enabled', 'updatedAt'});
      expect(f['day'], '2026-11-15');
      expect(f['enabled'], isTrue);
      expect(f['tzOffsetMin'], isA<int>());
    });
  });
}
