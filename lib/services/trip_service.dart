import 'social_graph.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/trip_model.dart';
import 'section_merge.dart';

/// Lo que quedó en la nube después de un guardado en vivo.
class LiveSaveResult {
  /// Bloques escritos (lo local combinado con lo que había en la nube).
  final List<TripSection> sections;

  /// Bloques que había en la nube justo antes de escribir.
  final List<TripSection> remoteSections;

  /// Bloques donde ganó lo local sobre un cambio ajeno (id → versión ajena; null = la borró).
  final Map<String, TripSection?> conflicts;
  final Map<String, TripSection> deletedHereChangedThere;

  /// Campos del documento del viaje escritos (ver [TripService.editorTripFields]).
  final Map<String, dynamic> tripFields;

  /// Esos campos en la nube justo antes de escribir (null si el documento no existía).
  final Map<String, dynamic>? remoteTripFields;

  /// Campos del viaje que los dos cambiaron distinto (ganó lo local).
  final Set<String> tripConflicts;

  /// Revisión escrita (sirve para ignorar avisos viejos del listener).
  final int rev;

  /// Quién había guardado lo que estaba en la nube.
  final String remoteEditorName;
  final String remoteEditorUid;
  final List<String> previousCoAuthorIds;

  const LiveSaveResult({
    required this.sections,
    required this.remoteSections,
    required this.conflicts,
    required this.deletedHereChangedThere,
    required this.tripFields,
    required this.remoteTripFields,
    this.tripConflicts = const {},
    required this.rev,
    required this.remoteEditorName,
    required this.remoteEditorUid,
    required this.previousCoAuthorIds,
  });
}

/// Alguien con el editor del viaje abierto.
class EditorPresence {
  final String uid;
  final String name;
  final String? photo;

  /// Bloque en el que está escribiendo (null = en ninguno).
  final String? blockId;
  final DateTime? lastSeen;

  const EditorPresence({required this.uid, required this.name, this.photo, this.blockId, this.lastSeen});

  factory EditorPresence.fromDoc(String uid, Map<String, dynamic> d) => EditorPresence(
        uid: uid,
        name: (d['name'] ?? '').toString().trim().isEmpty ? 'Alguien' : d['name'].toString().trim(),
        photo: (d['photo'] is String && (d['photo'] as String).trim().isNotEmpty) ? d['photo'] as String : null,
        blockId: d['blockId'] as String?,
        lastSeen: (d['lastSeen'] as Timestamp?)?.toDate(),
      );

  /// Sigue ahí si dio señales hace poco (el latido es cada 20 s). Sin hora todavía = recién llegó.
  bool isActive(DateTime now, {Duration window = const Duration(seconds: 60)}) =>
      lastSeen == null || now.difference(lastSeen!).abs() < window;

  String get firstName => name.split(RegExp(r'\s+')).first;
}

class TripService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference _tripsRef(String userId) => 
      _firestore.collection('users').doc(userId).collection('trips');

  Stream<List<Trip>> getTripsStream(String userId) {
    return _tripsRef(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Trip.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  Future<Trip> createTrip(String userId, Trip trip) async {
    final ref = _tripsRef(userId).doc(trip.id);
    await ref.set(trip.toMap());
    _checkAndNotifyFollowers(userId, trip);
    // Notify all initial co-authors
    if (trip.coAuthorIds.isNotEmpty) {
      _notifyNewCoAuthors(userId, trip, trip.coAuthorIds);
    }
    return trip;
  }

  Future<void> updateTrip(String userId, Trip trip) async {
    final ref = _tripsRef(userId).doc(trip.id);

    // Read existing trip to detect newly added co-authors
    List<String> newlyAddedCoAuthors = [];
    try {
      final existingDoc = await ref.get();
      if (existingDoc.exists) {
        final existingData = existingDoc.data() as Map<String, dynamic>?;
        final List<String> oldCoAuthorIds = List<String>.from(existingData?['coAuthorIds'] ?? []);
        newlyAddedCoAuthors = trip.coAuthorIds.where((id) => !oldCoAuthorIds.contains(id)).toList();
      } else {
        // New trip, all co-authors are new
        newlyAddedCoAuthors = List.from(trip.coAuthorIds);
      }
    } catch (e) {
      print('Error reading existing trip for co-author diff: $e');
    }

    await ref.set(trip.toMap(), SetOptions(merge: true));
    _checkAndNotifyFollowers(userId, trip);

    // Notify only the newly added co-authors
    if (newlyAddedCoAuthors.isNotEmpty) {
      _notifyNewCoAuthors(userId, trip, newlyAddedCoAuthors);
    }
  }

  Future<void> _checkAndNotifyFollowers(String authorId, Trip trip) async {
    if (trip.status != 'published') return;

    try {
      // 1. Fetch author details
      final authorDoc = await _firestore.collection('users').doc(authorId).get();
      if (!authorDoc.exists) return;
      final authorData = authorDoc.data();
      final String authorName = authorData?['displayName'] ?? 'Viajero Ohtli';
      final String? authorPhoto = authorData?['photoURL'];

      // Handle surprise plan notifications for multiple recipients
      if (trip.isSurprise && trip.surpriseTargetIds.isNotEmpty) {
        final batch = _firestore.batch();
        for (var targetId in trip.surpriseTargetIds) {
          final existing = await _firestore
              .collection('users')
              .doc(targetId)
              .collection('notifications')
              .where('tripId', isEqualTo: trip.id)
              .where('type', isEqualTo: 'surprise_plan')
              .get();

          if (existing.docs.isEmpty) {
            final notifRef = _firestore
                .collection('users')
                .doc(targetId)
                .collection('notifications')
                .doc();

            batch.set(notifRef, {
              'type': 'surprise_plan',
              'senderId': authorId,
              'senderName': authorName,
              'senderPhoto': authorPhoto,
              'tripId': trip.id,
              'tripTitle': trip.title,
              'isPlan': true,
              'status': 'unread',
              'read': false,
              'timestamp': trip.surpriseUnlockDates[targetId] != null
                  ? Timestamp.fromDate(trip.surpriseUnlockDates[targetId]!)
                  : FieldValue.serverTimestamp(),
            });
          }
        }
        await batch.commit();
        return; // Do not notify other followers for surprise plans
      }

      // 2. Seguidores del autor: su propia lista en users/{authorId}/social/graph
      final followers = (await SocialGraph.getGraph(authorId)).followers;
      if (followers.isEmpty) return;

      // Un id fijo por viaje evita duplicados: si ya existe, las reglas rechazan
      // reescribirlo (solo el dueño de la notificación la modifica) y se omite.
      for (final followerId in followers) {
        try {
          await _firestore
              .collection('users')
              .doc(followerId)
              .collection('notifications')
              .doc('new_publication_${trip.id}')
              .set({
            'type': 'new_publication',
            'senderId': authorId,
            'senderName': authorName,
            'senderPhoto': authorPhoto,
            'tripId': trip.id,
            'tripTitle': trip.title,
            'isPlan': trip.travelDate != null, // If travelDate is set, it's a plan!
            'status': 'unread',
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // Ya notificado antes
        }
      }
    } catch (e) {
      print("Error notifying followers of new publication: $e");
    }
  }

  /// Sends a 'co_author_added' notification to each newly added co-author.
  Future<void> _notifyNewCoAuthors(String authorId, Trip trip, List<String> newCoAuthorIds) async {
    try {
      // Fetch author details
      final authorDoc = await _firestore.collection('users').doc(authorId).get();
      if (!authorDoc.exists) return;
      final authorData = authorDoc.data();
      final String authorName = authorData?['displayName'] ?? 'Viajero Ohtli';
      final String? authorPhoto = authorData?['photoURL'];

      final batch = _firestore.batch();
      for (var coAuthorId in newCoAuthorIds) {
        // Don't notify the author themselves
        if (coAuthorId == authorId) continue;

        // Check for existing notification to avoid duplicates
        final existing = await _firestore
            .collection('users')
            .doc(coAuthorId)
            .collection('notifications')
            .where('tripId', isEqualTo: trip.id)
            .where('type', isEqualTo: 'co_author_added')
            .where('senderId', isEqualTo: authorId)
            .get();

        if (existing.docs.isEmpty) {
          final notifRef = _firestore
              .collection('users')
              .doc(coAuthorId)
              .collection('notifications')
              .doc();

          final bool isPlan = trip.status != 'published';
          batch.set(notifRef, {
            'type': 'co_author_added',
            'senderId': authorId,
            'senderName': authorName,
            'senderPhoto': authorPhoto,
            'tripId': trip.id,
            'tripTitle': trip.title,
            'tripOwnerId': trip.userId,
            'isPlan': isPlan,
            'status': 'unread',
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    } catch (e) {
      print('Error notifying new co-authors: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Edición en vivo (dueño y coautores a la vez)
  // ---------------------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _tripDoc(String ownerId, String tripId) =>
      _firestore.collection('users').doc(ownerId).collection('trips').doc(tripId);

  DocumentReference<Map<String, dynamic>> _contentDoc(String ownerId, String tripId) =>
      _tripDoc(ownerId, tripId).collection('details').doc('content');

  /// Cambios del contenido (bloques) del viaje, en vivo.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchTripContent(String ownerId, String tripId) =>
      _contentDoc(ownerId, tripId).snapshots();

  /// Cambios del documento del viaje (título, fecha, portada…), en vivo.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchTripDoc(String ownerId, String tripId) =>
      _tripDoc(ownerId, tripId).snapshots();

  /// Campos del documento del viaje que maneja el editor, normalizados para compararlos
  /// (sin dueño ni fechas de creación y de último cambio, que no se combinan).
  static Map<String, dynamic> editorTripFields(Trip trip) {
    final m = trip.toMap();
    m.remove('createdAt');
    m.remove('updatedAt');
    m.remove('userId');
    return m;
  }

  /// Lo mismo, a partir del documento tal como viene de la nube.
  static Map<String, dynamic> editorTripFieldsFromDoc(Map<String, dynamic> data, String tripId) =>
      editorTripFields(Trip.fromMap(data, tripId));

  /// Guarda lo del editor sin pisar lo que otro guardó mientras tanto: en una transacción
  /// lee lo que hay en la nube, lo combina a 3 vías con lo local ([mergeSections] y
  /// [mergeFields]) y escribe el resultado. [baseSections]/[baseTrip] son lo último que este
  /// editor vio sincronizado; [localSections]/[localTrip], lo que hay ahora en el editor.
  Future<LiveSaveResult> saveTripLive({
    required String ownerId,
    required Trip localTrip,
    required Map<String, dynamic> baseTrip,
    required List<TripSection> baseSections,
    required List<TripSection> localSections,
    required int baseRev,
    required String editorUid,
    required String editorName,
  }) async {
    final tripId = localTrip.id;
    final tripRef = _tripDoc(ownerId, tripId);
    final contentRef = _contentDoc(ownerId, tripId);
    final localFields = editorTripFields(localTrip);

    final result = await _firestore.runTransaction<LiveSaveResult>((tx) async {
      final contentSnap = await tx.get(contentRef);
      final tripSnap = await tx.get(tripRef);
      final contentData = contentSnap.data();
      final tripData = tripSnap.data();

      final remoteSections = contentData == null ? <TripSection>[] : TripContent.fromMap(contentData).sections;
      final merged = mergeSections(baseSections, localSections, remoteSections);

      final remoteFields = tripData == null ? null : editorTripFieldsFromDoc(tripData, tripId);
      final FieldMergeResult tripMerge =
          remoteFields == null ? FieldMergeResult(localFields, const {}) : mergeFields(baseTrip, localFields, remoteFields);

      int revOf(Map<String, dynamic>? d, String key) => (d?[key] as num?)?.toInt() ?? 0;
      final rev = [baseRev, revOf(contentData, 'rev'), revOf(tripData, 'editRev')].reduce((a, b) => a > b ? a : b) + 1;

      tx.set(contentRef, {
        'sections': [for (final s in merged.sections) s.toMap()],
        'rev': rev,
        'updatedBy': editorUid,
        'updatedByName': editorName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (tripData == null) {
        tx.set(tripRef, {...localTrip.toMap(), 'editRev': rev, 'editedBy': editorUid, 'editedByName': editorName},
            SetOptions(merge: true));
      } else {
        // Solo los campos que cambian: un coautor no puede tocar al dueño ni a los participantes.
        final changes = <String, dynamic>{
          for (final e in tripMerge.value.entries)
            if (!deepEquals(e.value, remoteFields![e.key])) e.key: e.value,
        };
        tx.update(tripRef, {
          ...changes,
          'updatedAt': Timestamp.fromDate(localTrip.updatedAt),
          'editRev': rev,
          'editedBy': editorUid,
          'editedByName': editorName,
        });
      }

      return LiveSaveResult(
        sections: merged.sections,
        remoteSections: remoteSections,
        conflicts: merged.conflicts,
        deletedHereChangedThere: merged.deletedHereChangedThere,
        tripFields: tripMerge.value,
        remoteTripFields: remoteFields,
        tripConflicts: tripMerge.conflicts,
        rev: rev,
        remoteEditorName: (contentData?['updatedByName'] ?? '').toString(),
        remoteEditorUid: (contentData?['updatedBy'] ?? '').toString(),
        previousCoAuthorIds: List<String>.from(tripData?['coAuthorIds'] ?? const []),
      );
    });

    // Avisos (seguidores al publicar, coautores nuevos), igual que updateTrip.
    final savedTrip = Trip.fromMap({...localTrip.toMap(), ...result.tripFields}, tripId);
    _checkAndNotifyFollowers(ownerId, savedTrip);
    final added = savedTrip.coAuthorIds.where((id) => !result.previousCoAuthorIds.contains(id)).toList();
    if (added.isNotEmpty) _notifyNewCoAuthors(ownerId, savedTrip, added);
    return result;
  }

  // --- Presencia: quién tiene abierto el editor y en qué bloque está ---

  CollectionReference<Map<String, dynamic>> _presence(String ownerId, String tripId) =>
      _tripDoc(ownerId, tripId).collection('presence');

  Stream<List<EditorPresence>> watchPresence(String ownerId, String tripId) => _presence(ownerId, tripId)
      .snapshots()
      .map((q) => [for (final d in q.docs) EditorPresence.fromDoc(d.id, d.data())]);

  Future<void> setPresence(String ownerId, String tripId, String uid, {required String name, String? photo, String? blockId}) {
    return _presence(ownerId, tripId).doc(uid).set({
      'name': name,
      'photo': photo,
      'blockId': blockId,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearPresence(String ownerId, String tripId, String uid) => _presence(ownerId, tripId).doc(uid).delete();

  /// Cambia el contenido sin pisar lo que otro guardó mientras tanto (p. ej. el modo viaje
  /// del visor con alguien en el editor en vivo): en una transacción lee la versión actual,
  /// le aplica [change] y la escribe con una revisión nueva, que los editores abiertos aplican.
  /// Devuelve el contenido de antes y el de después.
  Future<(List<TripSection>, List<TripSection>)> changeTripContent(
    String ownerId,
    String tripId,
    List<TripSection> Function(List<TripSection> sections) change, {
    String? editorUid,
    String? editorName,
  }) {
    final contentRef = _contentDoc(ownerId, tripId);
    final tripRef = _tripDoc(ownerId, tripId);
    return _firestore.runTransaction<(List<TripSection>, List<TripSection>)>((tx) async {
      final content = (await tx.get(contentRef)).data();
      final trip = (await tx.get(tripRef)).data();
      final before = content == null ? <TripSection>[] : TripContent.fromMap(content).sections;
      final after = change(List.of(before));
      int revOf(Map<String, dynamic>? d, String key) => (d?[key] as num?)?.toInt() ?? 0;
      // Mayor que cualquier revisión que un editor ya conozca (las dos se escriben juntas).
      final a = revOf(content, 'rev'), b = revOf(trip, 'editRev');
      tx.set(contentRef, {
        'sections': [for (final s in after) s.toMap()],
        'rev': (a > b ? a : b) + 1,
        'updatedBy': ?editorUid,
        'updatedByName': ?editorName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return (before, after);
    });
  }

  Future<void> updateTripContent(String userId, String tripId, TripContent content) async {
    final ref = _tripsRef(userId).doc(tripId).collection('details').doc('content');
    await ref.set(content.toMap()); // Usar set para crear o reemplazar
  }

  /// Guarda la reseña posterior al viaje (T5): calificaciones/notas de las paradas
  /// y la marca `reviewedAt` en el documento del viaje.
  Future<void> saveTripReview(String userId, String tripId, TripContent content) async {
    await updateTripContent(userId, tripId, content);
    await _tripsRef(userId).doc(tripId).update({
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Trip?> getTrip(String userId, String tripId) async {
    final doc = await _tripsRef(userId).doc(tripId).get();
    if (!doc.exists) return null;
    return Trip.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  Future<TripContent?> getTripContent(String userId, String tripId) async {
    final doc = await _tripsRef(userId).doc(tripId).collection('details').doc('content').get();
    if (!doc.exists) return null;
    return TripContent.fromMap(doc.data() as Map<String, dynamic>);
  }

  /// Ejecuta la eliminación en cascada de un viaje
  Future<void> deleteTrip(String userId, String tripId) async {
    // 1. Borrar sub-documento de contenido
    final contentRef = _tripsRef(userId).doc(tripId).collection('details').doc('content');
    await contentRef.delete();

    // 2. Borrar recursivamente imágenes del viaje en Storage
    final storageRef = _storage.ref('users/$userId/trips/$tripId/');
    try {
      final listResult = await storageRef.listAll();
      // Borrar archivos en la raíz del viaje
      for (var item in listResult.items) {
        await item.delete();
      }
      // Borrar archivos en subcarpetas de 1 nivel (si las hubiera)
      for (var prefix in listResult.prefixes) {
        final subList = await prefix.listAll();
        for (var subItem in subList.items) {
          await subItem.delete();
        }
      }
    } catch (e) {
      // Si la carpeta no existe, Firebase Storage puede lanzar un error, lo ignoramos de forma segura.
      print('Aviso: Error borrando imágenes de Storage: $e');
    }

    // 3. Borrar el documento principal del viaje
    await _tripsRef(userId).doc(tripId).delete();
  }
}
