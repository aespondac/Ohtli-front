// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'package:web/web.dart' as web;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Lugares guardados ("Mis lugares") de la cuenta, en `users/{uid}/private/saved_places`
/// (solo su dueño lo lee o escribe). Antes vivían en localStorage: se perdían al cambiar de
/// dispositivo o de navegador y los compartían todas las cuentas del mismo navegador.
///
/// [ids] va del más reciente al más antiguo y se actualiza en vivo en todas las pantallas.
class SavedPlaces {
  SavedPlaces._();

  static const String _legacyKey = 'ohtli_saved_pois';

  static final ValueNotifier<List<String>> ids = ValueNotifier(const []);

  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  static String? _uid;

  static DocumentReference<Map<String, dynamic>> _ref(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('saved_places');

  /// Empieza a escuchar la cuenta activa. Se puede llamar varias veces.
  static void ensureStarted() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen(_onUser);
    _onUser(FirebaseAuth.instance.currentUser);
  }

  static bool contains(String poiId) => ids.value.contains(poiId);

  static void _onUser(User? user) {
    if (user?.uid == _uid) return;
    _docSub?.cancel();
    _docSub = null;
    _uid = user?.uid;
    ids.value = const [];
    if (user == null) return;
    final uid = user.uid;
    var first = true;
    _docSub = _ref(uid).snapshots().listen((snap) {
      final remote = _parse(snap.data()?['ids']);
      if (first) {
        first = false;
        _migrateLegacy(uid, remote);
      }
      if (_uid == uid) ids.value = remote;
    }, onError: (Object e) => debugPrint('[SavedPlaces] no se pudo leer: $e'));
  }

  static List<String> _parse(dynamic raw) =>
      raw is List ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : <String>[];

  /// Lista antigua del navegador: se suma a la cuenta que inicia sesión y se borra de
  /// localStorage para que no pase a otra cuenta.
  static void _migrateLegacy(String uid, List<String> remote) {
    if (!kIsWeb) return;
    try {
      final raw = web.window.localStorage.getItem(_legacyKey);
      if (raw == null) return;
      final legacy = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      final merged = [...remote, ...legacy.where((id) => !remote.contains(id))];
      web.window.localStorage.removeItem(_legacyKey);
      if (merged.length != remote.length) _write(uid, merged);
    } catch (_) {}
  }

  /// Guarda o quita [poiId]. Devuelve si quedó guardado.
  static Future<bool> toggle(String poiId) => setSaved(poiId, !contains(poiId));

  static Future<bool> setSaved(String poiId, bool saved) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || poiId.isEmpty) return false;
    final previous = ids.value;
    final next = [
      if (saved) poiId,
      ...previous.where((id) => id != poiId),
    ];
    ids.value = next; // se muestra al instante; el listener confirma lo guardado
    try {
      await _write(uid, next);
    } catch (e) {
      debugPrint('[SavedPlaces] no se pudo guardar: $e');
      if (_uid == uid) ids.value = previous;
      rethrow;
    }
    return saved;
  }

  static Future<void> _write(String uid, List<String> list) => _ref(uid).set({
        'ids': list,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
