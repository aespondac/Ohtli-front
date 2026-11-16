import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Resultado de enviar una solicitud de amistad.
enum FriendRequestResult { sent, alreadyPending, notSignedIn }

/// Envía solicitudes de amistad (Amigos y el cuestionario de bienvenida usan lo mismo).
class FriendRequests {
  FriendRequests._();

  /// Crea la solicitud y le deja la notificación a la otra persona. No duplica: si ya hay
  /// una pendiente en cualquier sentido, no hace nada.
  static Future<FriendRequestResult> send(String targetUserId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return FriendRequestResult.notSignedIn;
    final db = FirebaseFirestore.instance;
    final requests = db.collection('friend_requests');

    final results = await Future.wait([
      requests.where('senderId', isEqualTo: me.uid).where('receiverId', isEqualTo: targetUserId).where('status', isEqualTo: 'pending').get(),
      requests.where('senderId', isEqualTo: targetUserId).where('receiverId', isEqualTo: me.uid).where('status', isEqualTo: 'pending').get(),
    ]);
    if (results.any((r) => r.docs.isNotEmpty)) return FriendRequestResult.alreadyPending;

    final docRef = await requests.add({
      'senderId': me.uid,
      'senderName': me.displayName ?? 'Un viajero',
      'senderPhoto': me.photoURL,
      'receiverId': targetUserId,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    await db.collection('users').doc(targetUserId).collection('notifications').doc(docRef.id).set({
      'type': 'friend_request',
      'senderId': me.uid,
      'senderName': me.displayName ?? 'Un viajero',
      'senderPhoto': me.photoURL,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    return FriendRequestResult.sent;
  }
}
