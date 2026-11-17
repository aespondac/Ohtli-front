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

  /// Claves para buscar personas sin importar mayúsculas, acentos ni el orden: los prefijos (de
  /// 2 letras en adelante) de cada palabra del nombre y del usertag. «Alfredo Esponda» se
  /// encuentra con «esp», «alfredo» o «ALF». El motor usa el mismo cálculo (api/admin_places.py).
  static List<String> searchKeysFor(String? name, String? tag) {
    final keys = <String>{};
    void addWord(String w) {
      for (var n = 2; n <= w.length && n <= 15; n++) {
        keys.add(w.substring(0, n));
      }
    }

    for (final w in fold(name ?? '').split(RegExp(r'[^a-z0-9]+'))) {
      if (w.length >= 2) addWord(w);
    }
    final t = fold(tag ?? '').replaceAll('@', '');
    if (t.length >= 2) {
      addWord(t);
      for (final w in t.split(RegExp(r'[^a-z0-9]+'))) {
        if (w.length >= 2) addWord(w);
      }
    }
    return keys.take(80).toList();
  }

  /// Minúsculas y sin acentos.
  static String fold(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// Busca perfiles públicos por nombre (cualquier palabra, sin acentos), @usertag (con o sin
  /// arroba), correo o teléfono. Devuelve también perfiles privados: quien llama decide.
  static Future<List<DocumentSnapshot<Map<String, dynamic>>>> search(
    String query, {
    required Future<String?> Function(String kind, String value) lookup,
    required ({String kind, String value})? Function(String q) classify,
    required String? Function(String raw) normalizeTag,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final found = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    Future<void> addUid(String? uid) async {
      if (uid == null || found.containsKey(uid)) return;
      final d = await ref(uid).get();
      if (d.exists) found[uid] = d;
    }

    final kind = classify(q);
    if (kind != null && kind.kind != 'name') {
      await addUid(await lookup(kind.kind, kind.value));
      return found.values.toList();
    }
    // Un usertag escrito sin @
    final tag = normalizeTag(q);
    if (tag != null && !q.contains(' ')) await addUid(await lookup('tag', tag));

    final words = fold(q).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 2).toList();
    if (words.isNotEmpty) {
      try {
        final first = words.first.length > 15 ? words.first.substring(0, 15) : words.first;
        final snap = await collection.where('searchKeys', arrayContains: first).limit(limit * 2).get();
        for (final d in snap.docs) {
          final keys = ((d.data()['searchKeys'] as List?) ?? const []).map((e) => e.toString()).toSet();
          // Todas las palabras escritas tienen que estar
          if (words.every((w) => keys.contains(w.length > 15 ? w.substring(0, 15) : w))) found[d.id] = d;
        }
      } catch (e) {
        debugPrint('[PublicProfiles] búsqueda por claves: $e');
      }
    }
    // Perfiles que aún no tienen claves: prefijo del nombre tal cual y con mayúscula inicial
    for (final v in {q, q[0].toUpperCase() + q.substring(1)}) {
      try {
        final snap = await collection
            .where('displayName', isGreaterThanOrEqualTo: v)
            .where('displayName', isLessThan: '$v\uf8ff')
            .limit(limit)
            .get();
        for (final d in snap.docs) {
          found.putIfAbsent(d.id, () => d);
        }
      } catch (_) {}
    }
    return found.values.take(limit).toList();
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get collection => _db.collection('public_profiles');

  static DocumentReference<Map<String, dynamic>> ref(String uid) => collection.doc(uid);

  /// Deja solo los campos visibles de [data].
  static Map<String, dynamic> pick(Map<String, dynamic> data) => {
        for (final e in data.entries)
          if (fields.contains(e.key)) e.key: e.value,
      };

  /// Con nombre y usertag a la mano, agrega las claves de búsqueda.
  static Map<String, dynamic> _withKeys(Map<String, dynamic> visible, Map<String, dynamic>? current) {
    if (!visible.containsKey('displayName') && !visible.containsKey('usertag')) return visible;
    final name = (visible['displayName'] ?? current?['displayName'])?.toString();
    final tag = (visible['usertag'] ?? current?['usertag'])?.toString();
    return {...visible, 'searchKeys': searchKeysFor(name, tag)};
  }

  /// Copia al perfil visible los campos de [changes] que le corresponden (los demás se
  /// ignoran). No falla: si la escritura no pasa, el perfil se repara la siguiente vez que
  /// el usuario abre la app ([syncFromUserDoc]).
  static Future<void> mirror(String uid, Map<String, dynamic> changes) async {
    var visible = pick(changes);
    if (visible.isEmpty) return;
    try {
      if (visible.containsKey('displayName') || visible.containsKey('usertag')) {
        Map<String, dynamic>? current;
        if (!visible.containsKey('displayName') || !visible.containsKey('usertag')) {
          try {
            current = (await ref(uid).get()).data();
          } catch (_) {}
        }
        visible = _withKeys(visible, current);
      }
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
    final visible = _withKeys(pick(userData), null);
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
