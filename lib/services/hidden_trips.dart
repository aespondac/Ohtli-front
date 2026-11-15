import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Viajes de otras personas (sorpresas que te prepararon o viajes donde eres coautor)
/// que quitaste de tus viajes. Solo se ocultan para ti: el viaje sigue siendo de su
/// dueño y nadie más se entera.
///
/// Se guardan en `users/{uid}/private/hidden_trips` (`tripIds`), que solo tú puedes
/// leer o escribir.
class HiddenTrips extends ChangeNotifier {
  HiddenTrips._();
  static final HiddenTrips instance = HiddenTrips._();

  String? _uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Set<String> _ids = {};

  Set<String> get ids => _ids;
  bool contains(String tripId) => _ids.contains(tripId);

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('private').doc('hidden_trips');

  void start(String uid) {
    if (_uid == uid && _sub != null) return;
    _sub?.cancel();
    _uid = uid;
    _ids = {};
    _sub = _doc(uid).snapshots().listen((snap) {
      final raw = snap.data()?['tripIds'];
      _ids = raw is List ? raw.map((e) => e.toString()).toSet() : {};
      notifyListeners();
    }, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _ids = {};
  }

  Future<void> hide(String tripId) => _set(tripId, true);
  Future<void> unhide(String tripId) => _set(tripId, false);

  Future<void> _set(String tripId, bool hidden) async {
    final uid = _uid;
    if (uid == null) return;
    // Cambio optimista: la tarjeta desaparece (o vuelve) en el acto
    hidden ? _ids.add(tripId) : _ids.remove(tripId);
    notifyListeners();
    try {
      await _doc(uid).set({
        'tripIds': hidden ? FieldValue.arrayUnion([tripId]) : FieldValue.arrayRemove([tripId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      hidden ? _ids.remove(tripId) : _ids.add(tripId);
      notifyListeners();
      rethrow;
    }
  }
}
