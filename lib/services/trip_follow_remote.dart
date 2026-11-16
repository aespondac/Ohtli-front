import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// «Seguir mi viaje» en el servidor: `trip_follows/{tripId}_{uid}`. Con él, la función programada
/// (functions/trip_follow.js) manda «Sal en N min de X» y «Es hora de salir de X» como push aunque
/// Ohtli esté cerrado. Lo escribe el visor al encender o apagar el seguimiento.
///
/// [sent] son las claves de los avisos ya dados (`soon:<parada>`, `now:<parada>`), las mismas que
/// guarda la app: así cada aviso sale una sola vez, lo dé la app o el servidor.
class TripFollowRemote {
  TripFollowRemote._();

  static String followId(String tripId, String uid) => '${tripId}_$uid';

  /// "YYYY-MM-DD" de [d] (el día local del viaje).
  static String dayOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Campos al encender el seguimiento (sin `sent`, que se conserva si ya existía).
  static Map<String, Object?> startFields({
    required String uid,
    required String ownerId,
    required String tripId,
    required DateTime now,
    String? timeZone,
    required Object updatedAt,
  }) =>
      {
        'uid': uid,
        'ownerId': ownerId,
        'tripId': tripId,
        'day': dayOf(now),
        'tz': timeZone,
        'tzOffsetMin': now.timeZoneOffset.inMinutes,
        'enabled': true,
        'updatedAt': updatedAt,
      };

  static DocumentReference<Map<String, dynamic>>? _ref(String tripId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || tripId.isEmpty) return null;
    return FirebaseFirestore.instance.collection('trip_follows').doc(followId(tripId, uid));
  }

  /// Enciende el seguimiento en el servidor y devuelve los avisos que ya se dieron hoy.
  static Future<Set<String>> start({required String tripId, required String ownerId}) async {
    final ref = _ref(tripId);
    if (ref == null) return {};
    final now = DateTime.now();
    try {
      final prev = await ref.get();
      final sameDay = prev.exists && prev.data()?['day'] == dayOf(now);
      await ref.set({
        ...startFields(
          uid: FirebaseAuth.instance.currentUser!.uid,
          ownerId: ownerId,
          tripId: tripId,
          now: now,
          timeZone: _ianaTimeZone(),
          updatedAt: FieldValue.serverTimestamp(),
        ),
        // Otro día, otra lista de avisos.
        if (!sameDay) 'sent': <String>[],
      }, SetOptions(merge: true));
      if (!sameDay) return {};
      return ((prev.data()?['sent'] as List?) ?? const []).map((e) => e.toString()).toSet();
    } catch (e) {
      debugPrint('[Seguir viaje] no se pudo avisar al servidor: $e');
      return {};
    }
  }

  static Future<void> stop(String tripId) async {
    final ref = _ref(tripId);
    if (ref == null) return;
    try {
      await ref.set({'enabled': false, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Seguir viaje] no se pudo apagar en el servidor: $e');
    }
  }

  /// La app ya dio el aviso [key]: el servidor no lo repite.
  static Future<void> markSent(String tripId, String key) async {
    final ref = _ref(tripId);
    if (ref == null) return;
    try {
      await ref.update({'sent': FieldValue.arrayUnion([key])});
    } catch (_) {}
  }

  /// Zona horaria del navegador ("America/Mexico_City"); el servidor la usa para saber la hora local.
  static String? _ianaTimeZone() {
    try {
      final intl = globalContext.getProperty<JSObject>('Intl'.toJS);
      final dtf = intl.getProperty<JSFunction>('DateTimeFormat'.toJS).callAsConstructor<JSObject>();
      return dtf.callMethod<JSObject>('resolvedOptions'.toJS).getProperty<JSString?>('timeZone'.toJS)?.toDart;
    } catch (_) {
      return null;
    }
  }
}
