import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/trip_model.dart';

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

      // 2. Fetch all followers (users who follow authorId)
      final followersSnapshot = await _firestore
          .collection('users')
          .where('following', arrayContains: authorId)
          .get();

      if (followersSnapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (var doc in followersSnapshot.docs) {
        final followerId = doc.id;

        // Check if follower already has a notification for this trip to avoid duplicate spam
        final existing = await _firestore
            .collection('users')
            .doc(followerId)
            .collection('notifications')
            .where('tripId', isEqualTo: trip.id)
            .where('type', isEqualTo: 'new_publication')
            .get();

        if (existing.docs.isEmpty) {
          final notifRef = _firestore
              .collection('users')
              .doc(followerId)
              .collection('notifications')
              .doc(); // Auto-generated ID

          batch.set(notifRef, {
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
        }
      }
      await batch.commit();
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

  Future<void> updateTripContent(String userId, String tripId, TripContent content) async {
    final ref = _tripsRef(userId).doc(tripId).collection('details').doc('content');
    await ref.set(content.toMap()); // Usar set para crear o reemplazar
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
