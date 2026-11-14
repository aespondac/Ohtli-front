import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Relaciones sociales de un usuario, fuera del perfil público para que las reglas
/// de Firestore puedan protegerlas:
///
/// * `users/{uid}/social/graph`: `friends`, `following`, `followers`. La leen el dueño,
///   sus amigos y, si el perfil es público (`profilePrivate` != true), cualquiera.
/// * `users/{uid}/social/close`: `closeFriends` (mis mejores amigos) y `closeFriendOf`
///   (quién me tiene como mejor amigo). Solo la lee su dueño.
///
/// Los demás usuarios solo pueden agregarse o quitarse a sí mismos de `friends`,
/// `followers` y `closeFriendOf` (ver firestore.rules).
///
/// Las cuentas anteriores tienen estas listas en `users/{uid}`; [watchGraph] y
/// [getGraph] las usan como respaldo hasta que se migren.
class SocialGraph {
  SocialGraph._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const List<String> graphFields = ['friends', 'following', 'followers'];
  static const List<String> closeFields = ['closeFriends', 'closeFriendOf'];

  static DocumentReference<Map<String, dynamic>> graphRef(String uid) =>
      _db.collection('users').doc(uid).collection('social').doc('graph');

  static DocumentReference<Map<String, dynamic>> closeRef(String uid) =>
      _db.collection('users').doc(uid).collection('social').doc('close');

  static List<String> _list(Map<String, dynamic>? data, String key) =>
      ((data?[key] as List?) ?? const []).map((e) => e.toString()).toList();

  /// Listas sociales de [uid]. Si no hay permiso (perfil privado y no somos amigos),
  /// devuelve `hidden: true` y listas vacías.
  static Future<SocialData> getGraph(String uid, {bool includeClose = false}) async {
    Map<String, dynamic>? graph;
    bool hidden = false;
    try {
      graph = (await graphRef(uid).get()).data();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') hidden = true;
    }
    Map<String, dynamic>? close;
    if (includeClose) {
      try {
        close = (await closeRef(uid).get()).data();
      } catch (_) {}
    }
    Map<String, dynamic>? legacy;
    if (!hidden && (graph == null || (includeClose && close == null))) {
      try {
        legacy = (await _db.collection('users').doc(uid).get()).data();
      } catch (_) {}
    }
    return SocialData._(graph ?? legacy, close ?? (includeClose ? legacy : null), hidden);
  }

  /// Igual que [getGraph], en tiempo real.
  static Stream<SocialData> watchGraph(String uid, {bool includeClose = false}) {
    late StreamController<SocialData> controller;
    final subs = <StreamSubscription>[];
    Map<String, dynamic>? graph;
    Map<String, dynamic>? close;
    Map<String, dynamic>? legacy;
    bool hidden = false;
    var pending = includeClose ? 3 : 2;
    final loaded = <String>{};

    void emit(String part) {
      loaded.add(part);
      if (loaded.length < pending) return;
      controller.add(SocialData._(
        hidden ? null : (graph ?? legacy),
        includeClose ? (close ?? legacy) : null,
        hidden,
      ));
    }

    controller = StreamController<SocialData>(
      onListen: () {
        subs.add(graphRef(uid).snapshots().listen((s) {
          graph = s.data();
          hidden = false;
          emit('graph');
        }, onError: (Object e) {
          hidden = e is FirebaseException && e.code == 'permission-denied';
          emit('graph');
        }));
        subs.add(_db.collection('users').doc(uid).snapshots().listen((s) {
          final d = s.data();
          legacy = d == null
              ? null
              : {
                  for (final k in [...graphFields, ...closeFields])
                    if (d.containsKey(k)) k: d[k],
                };
          if (legacy?.isEmpty ?? true) legacy = null;
          emit('legacy');
        }, onError: (Object _) => emit('legacy')));
        if (includeClose) {
          subs.add(closeRef(uid).snapshots().listen((s) {
            close = s.data();
            emit('close');
          }, onError: (Object _) => emit('close')));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    pending = includeClose ? 3 : 2;
    return controller.stream;
  }

  // --- Escrituras --------------------------------------------------------------------

  static Future<void> _union(DocumentReference<Map<String, dynamic>> ref, String field, String uid) =>
      ref.set({field: FieldValue.arrayUnion([uid])}, SetOptions(merge: true));

  static Future<void> _remove(DocumentReference<Map<String, dynamic>> ref, String field, String uid) =>
      ref.set({field: FieldValue.arrayRemove([uid])}, SetOptions(merge: true));

  /// Crea la amistad en ambos sentidos (al aceptar una solicitud).
  static Future<void> addFriendship(String me, String other) async {
    await _union(graphRef(other), 'friends', me);
    await _union(graphRef(me), 'friends', other);
  }

  /// Termina la amistad en ambos sentidos y quita la marca de mejor amigo.
  static Future<void> removeFriendship(String me, String other) async {
    await _remove(graphRef(me), 'friends', other);
    await _remove(graphRef(other), 'friends', me);
    await setCloseFriend(me, other, false);
  }

  static Future<void> setFollowing(String me, String target, bool follow) async {
    if (follow) {
      await _union(graphRef(me), 'following', target);
      await _union(graphRef(target), 'followers', me);
    } else {
      await _remove(graphRef(me), 'following', target);
      await _remove(graphRef(target), 'followers', me);
    }
  }

  static Future<void> setCloseFriend(String me, String other, bool close) async {
    if (close) {
      await _union(closeRef(me), 'closeFriends', other);
      await _union(closeRef(other), 'closeFriendOf', me);
    } else {
      await _remove(closeRef(me), 'closeFriends', other);
      await _remove(closeRef(other), 'closeFriendOf', me);
    }
  }

  /// Copia las listas antiguas del perfil público a los documentos sociales del propio
  /// usuario y las borra del perfil público.
  static Future<void> migrateLegacy(String uid) async {
    try {
      final userRef = _db.collection('users').doc(uid);
      final data = (await userRef.get()).data();
      if (data == null) return;
      final g = {for (final k in graphFields) if (data[k] is List) k: FieldValue.arrayUnion(List.from(data[k]))};
      final c = {
        if (data['closeFriends'] is List) 'closeFriends': FieldValue.arrayUnion(List.from(data['closeFriends'])),
      };
      if (g.isEmpty && c.isEmpty) return;
      if (g.isNotEmpty) await graphRef(uid).set(g, SetOptions(merge: true));
      if (c.isNotEmpty) await closeRef(uid).set(c, SetOptions(merge: true));
      await userRef.update({
        for (final k in [...graphFields, ...closeFields])
          if (data.containsKey(k)) k: FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('[SocialGraph] no se pudieron mover las listas sociales: $e');
    }
  }
}

class SocialData {
  final Map<String, dynamic>? _graph;
  final Map<String, dynamic>? _close;

  /// true si el perfil es privado y quien consulta no es su amigo.
  final bool hidden;

  SocialData._(this._graph, this._close, this.hidden);

  List<String> get friends => SocialGraph._list(_graph, 'friends');
  List<String> get following => SocialGraph._list(_graph, 'following');
  List<String> get followers => SocialGraph._list(_graph, 'followers');
  List<String> get closeFriends => SocialGraph._list(_close, 'closeFriends');
  List<String> get closeFriendOf => SocialGraph._list(_close, 'closeFriendOf');
}
