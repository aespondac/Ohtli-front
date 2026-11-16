import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Perfil visible para los demás: `public_profiles/{uid}`.
///
/// `users/{uid}` solo lo lee su dueño (ver firestore.rules). Lo que otras personas ven del
/// autor de un viaje, de un amigo o de un coautor (nombre, foto, usertag, título, portada,
/// momentos y las marcas de perfil privado o dado de baja) vive en este documento, que
/// escribe el propio usuario cada vez que guarda esos campos en su perfil.
class PublicProfiles {
  PublicProfiles._();

  /// Únicos campos que se copian al perfil visible. Las reglas rechazan cualquier otro.
  static const Set<String> fields = {
    'displayName',
    'photoURL',
    'coverURL',
    'coverUrl',
    'usertag',
    'activeTitleId',
    'possessedTitles',
    'moments',
    'createdAt',
    'profilePrivate',
    'isDeleted',
  };

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get collection => _db.collection('public_profiles');

  static DocumentReference<Map<String, dynamic>> ref(String uid) => collection.doc(uid);

  /// Deja solo los campos visibles de [data].
  static Map<String, dynamic> pick(Map<String, dynamic> data) => {
        for (final e in data.entries)
          if (fields.contains(e.key)) e.key: e.value,
      };

  /// Copia al perfil visible los campos de [changes] que le corresponden (los demás se
  /// ignoran). No falla: si la escritura no pasa, el perfil se repara la siguiente vez que
  /// el usuario abre la app ([syncFromUserDoc]).
  static Future<void> mirror(String uid, Map<String, dynamic> changes) async {
    final visible = pick(changes);
    if (visible.isEmpty) return;
    try {
      await ref(uid).set({
        ...visible,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[PublicProfiles] no se pudo actualizar el perfil visible de $uid: $e');
    }
  }

  /// Rehace el perfil visible a partir del documento completo `users/{uid}` del propio
  /// usuario (cuentas creadas antes de esta colección o escrituras que fallaron).
  static Future<void> syncFromUserDoc(String uid, Map<String, dynamic> userData) async {
    final visible = pick(userData);
    if (visible.isEmpty) return;
    try {
      final current = (await ref(uid).get()).data();
      if (current != null && visible.entries.every((e) => _same(current[e.key], e.value))) return;
      await ref(uid).set({
        ...visible,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[PublicProfiles] no se pudo sincronizar el perfil visible de $uid: $e');
    }
  }

  static bool _same(Object? a, Object? b) {
    if (a is Timestamp && b is Timestamp) return a == b;
    if (a is List && b is List) return listEquals(a, b);
    if (a is Map && b is Map) return mapEquals(a, b);
    return a == b;
  }

  /// Lee varios perfiles visibles por uid (en tandas de 30, el límite de `whereIn`).
  static Future<Map<String, Map<String, dynamic>>> getMany(Iterable<String> uids) async {
    final ids = uids.where((u) => u.isNotEmpty).toSet().toList();
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await collection.where(FieldPath.documentId, whereIn: chunk).get();
      for (final d in snap.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }
}
