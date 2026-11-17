import 'package:cloud_firestore/cloud_firestore.dart';

import 'social_graph.dart';

/// Un amigo que se puede invitar a un viaje.
class FriendOption {
  final String uid;
  final String name;
  final String? photoUrl;
  final String? usertag;

  /// Mejores amigos mutuos: los dos se tienen como mejor amigo. Solo a ellos se les puede
  /// preparar un plan sorpresa (y por eso el plan puede usar sus gustos).
  final bool isMutualCloseFriend;
  final bool isCloseFriend;

  const FriendOption({
    required this.uid,
    required this.name,
    this.photoUrl,
    this.usertag,
    this.isMutualCloseFriend = false,
    this.isCloseFriend = false,
  });

  String get initials {
    final parts = name.split(' ').where((w) => w.isNotEmpty).take(2);
    final s = parts.map((w) => w[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }
}

/// Amigos de [uid] con su nombre y foto, mejores amigos primero y luego por nombre.
Future<List<FriendOption>> loadFriendOptions(String uid) async {
  final social = await SocialGraph.getGraph(uid, includeClose: true);
  final friends = social.friends.toSet();
  if (friends.isEmpty) return const [];
  final close = social.closeFriends.toSet();
  final closeOf = social.closeFriendOf.toSet();

  final out = <FriendOption>[];
  final ids = friends.toList();
  // whereIn admite hasta 30 valores por consulta.
  for (int i = 0; i < ids.length; i += 30) {
    final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
    final snap = await FirebaseFirestore.instance.collection('public_profiles').where(FieldPath.documentId, whereIn: chunk).get();
    for (final doc in snap.docs) {
      final data = doc.data();
      out.add(FriendOption(
        uid: doc.id,
        name: (data['displayName'] as String?)?.trim().isNotEmpty == true ? (data['displayName'] as String).trim() : 'Viajero Ohtli',
        photoUrl: (data['photoURL'] as String?)?.isNotEmpty == true ? data['photoURL'] as String : null,
        usertag: (data['usertag'] as String?)?.isNotEmpty == true ? data['usertag'] as String : null,
        isMutualCloseFriend: close.contains(doc.id) && closeOf.contains(doc.id),
        isCloseFriend: close.contains(doc.id),
      ));
    }
  }
  out.sort((a, b) {
    if (a.isMutualCloseFriend != b.isMutualCloseFriend) return a.isMutualCloseFriend ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}
