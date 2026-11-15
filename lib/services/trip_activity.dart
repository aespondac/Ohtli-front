// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'package:web/web.dart' as web;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/trip_model.dart';

/// Novedades de Mis viajes: comentarios nuevos en tus viajes publicados y
/// planes con IA que terminaron y aún no abres.
///
/// Lo "visto" se recuerda en este navegador (localStorage, por usuario).
/// La primera vez que se revisa algo se toma como punto de partida, así no
/// aparece todo marcado como nuevo.
class TripActivity extends ChangeNotifier {
  TripActivity._();
  static final TripActivity instance = TripActivity._();

  String? _uid;
  Map<String, int> _tripSeen = {};
  Set<String> _jobsSeen = {};
  bool _jobsBaselined = false;

  /// Viajes publicados con comentarios que no has visto.
  final Set<String> tripsWithNews = {};
  final Map<String, Future<bool>> _checks = {};

  String get _key => 'ohtli_trip_activity_${_uid ?? ''}';

  void start(String uid) {
    if (_uid == uid) return;
    _uid = uid;
    tripsWithNews.clear();
    _checks.clear();
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _tripSeen = (data['trips'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        _jobsSeen = ((data['jobs'] as List?) ?? const []).map((e) => e.toString()).toSet();
        _jobsBaselined = data['jobsBaselined'] == true;
      } else {
        _tripSeen = {};
        _jobsSeen = {};
        _jobsBaselined = false;
      }
    } catch (_) {
      _tripSeen = {};
      _jobsSeen = {};
    }
  }

  void _save() {
    try {
      web.window.localStorage.setItem(_key, jsonEncode({
        'trips': _tripSeen,
        'jobs': _jobsSeen.take(300).toList(),
        'jobsBaselined': _jobsBaselined,
      }));
    } catch (_) {}
  }

  // ───────────── Viajes publicados ─────────────

  /// Marca el viaje como revisado (al abrirlo).
  void markTripSeen(String tripId) {
    _tripSeen[tripId] = DateTime.now().millisecondsSinceEpoch;
    _save();
    if (tripsWithNews.remove(tripId)) notifyListeners();
  }

  /// Revisa (una vez por sesión) si hay comentarios de otros después de tu última visita.
  void check(Trip trip) {
    final uid = _uid;
    if (uid == null || trip.status != 'published') return;
    _checks[trip.id] ??= _hasNewNotes(trip, uid).then((isNew) {
      if (isNew && tripsWithNews.add(trip.id)) notifyListeners();
      return isNew;
    });
  }

  Future<bool> _hasNewNotes(Trip trip, String uid) async {
    final seen = _tripSeen[trip.id];
    if (seen == null) {
      // Primera vez: a partir de ahora cuenta lo nuevo
      _tripSeen[trip.id] = DateTime.now().millisecondsSinceEpoch;
      _save();
      return false;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(trip.userId)
          .collection('trips')
          .doc(trip.id)
          .collection('notes')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final ts = data['createdAt'];
        if (ts is! Timestamp) continue;
        if (ts.millisecondsSinceEpoch <= seen) break;
        if ((data['authorId'] ?? '') != uid) return true;
      }
    } catch (_) {
      // Sin permiso para leer notas de este viaje: no se marca nada
    }
    return false;
  }

  // ───────────── Planes con IA ─────────────

  /// La primera vez, todo lo ya terminado se da por visto.
  void baselineJobs(Iterable<String> completedJobIds) {
    if (_jobsBaselined) return;
    _jobsSeen.addAll(completedJobIds);
    _jobsBaselined = true;
    _save();
  }

  bool isJobNew(String jobId) => _jobsBaselined && !_jobsSeen.contains(jobId);

  void markJobSeen(String jobId) {
    if (_jobsSeen.add(jobId)) {
      _save();
      notifyListeners();
    }
  }
}
