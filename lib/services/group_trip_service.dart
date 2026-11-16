import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'friend_options.dart';

/// Plan hecho a mano: el viaje ya existe y quienes aceptan se suman como coautores.
const String kGroupKindManual = 'manual';

/// Plan con IA: las rutas salen de los gustos de quienes aceptan y luego se vota.
const String kGroupKindAi = 'ai';

/// Solicitud de viaje en grupo (`group_trips/{id}`).
///
/// La lista de invitados ([invitedIds], [members]) la controla quien organiza; las respuestas,
/// intenciones y votos los escribe cada invitado en su propia llave (las reglas no dejan que
/// nadie responda por otro). Así nadie usa los gustos de una persona que no aceptó.
class GroupTrip {
  final String id;
  final String kind;
  final String hostId;
  final String hostName;
  final String? hostPhoto;
  final String title;
  final String status;
  final String? tripId;
  final DateTime? travelDate;
  final List<String> invitedIds;
  final Map<String, ({String name, String? photo})> members;
  final Map<String, String> responses;
  final Map<String, String> intentions;
  final Map<String, int> votes;
  final DateTime? respondBy;
  final DateTime? voteBy;

  const GroupTrip({
    required this.id,
    required this.kind,
    required this.hostId,
    required this.hostName,
    this.hostPhoto,
    required this.title,
    required this.status,
    this.tripId,
    this.travelDate,
    this.invitedIds = const [],
    this.members = const {},
    this.responses = const {},
    this.intentions = const {},
    this.votes = const {},
    this.respondBy,
    this.voteBy,
  });

  bool get isManual => kind == kGroupKindManual;

  /// 'pending', 'accepted' o 'declined'.
  String responseOf(String uid) {
    final r = responses[uid];
    return (r == 'accepted' || r == 'declined') ? r! : 'pending';
  }

  List<String> get acceptedIds => [for (final u in invitedIds) if (responses[u] == 'accepted') u];
  List<String> get pendingIds => [for (final u in invitedIds) if (responseOf(u) == 'pending') u];

  String nameOf(String uid) => uid == hostId ? hostName : (members[uid]?.name ?? 'Viajero Ohtli');

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

  static Map<String, String> _strings(Object? v) =>
      v is Map ? {for (final e in v.entries) e.key.toString(): e.value.toString()} : const {};

  factory GroupTrip.fromMap(String id, Map<String, dynamic> d) {
    final members = <String, ({String name, String? photo})>{};
    final rawMembers = d['members'];
    if (rawMembers is Map) {
      rawMembers.forEach((k, v) {
        if (v is Map) {
          final photo = v['photo']?.toString();
          members[k.toString()] = (name: (v['name'] ?? 'Viajero Ohtli').toString(), photo: (photo == null || photo.isEmpty) ? null : photo);
        }
      });
    }
    final votes = <String, int>{};
    final rawVotes = d['votes'];
    if (rawVotes is Map) {
      rawVotes.forEach((k, v) {
        if (v is num) votes[k.toString()] = v.toInt();
      });
    }
    final photo = d['hostPhoto']?.toString();
    return GroupTrip(
      id: id,
      kind: (d['kind'] ?? kGroupKindManual).toString(),
      hostId: (d['hostId'] ?? '').toString(),
      hostName: (d['hostName'] ?? 'Viajero Ohtli').toString(),
      hostPhoto: (photo == null || photo.isEmpty) ? null : photo,
      title: (d['title'] ?? 'Plan en grupo').toString(),
      status: (d['status'] ?? 'open').toString(),
      tripId: d['tripId']?.toString(),
      travelDate: _date(d['travelDate']),
      invitedIds: ((d['invitedIds'] as List?) ?? const []).map((e) => e.toString()).toList(),
      members: members,
      responses: _strings(d['responses']),
      intentions: _strings(d['intentions']),
      votes: votes,
      respondBy: _date(d['respondBy']),
      voteBy: _date(d['voteBy']),
    );
  }
}

class GroupTripService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('group_trips');

  static String newId() => 'grp_${const Uuid().v4()}';

  static Stream<GroupTrip?> watch(String id) =>
      _col.doc(id).snapshots().map((s) => s.exists ? GroupTrip.fromMap(s.id, s.data()!) : null);

  static Future<GroupTrip?> get(String id) async {
    final s = await _col.doc(id).get();
    return s.exists ? GroupTrip.fromMap(s.id, s.data()!) : null;
  }

  /// Nombre y foto de quien usa la app.
  static Future<({String name, String? photo})> me() async {
    final user = FirebaseAuth.instance.currentUser!;
    String name = user.displayName ?? '';
    String? photo = user.photoURL;
    try {
      final d = (await _db.collection('users').doc(user.uid).get()).data();
      if ((d?['displayName'] as String?)?.trim().isNotEmpty == true) name = (d!['displayName'] as String).trim();
      if ((d?['photoURL'] as String?)?.isNotEmpty == true) photo = d!['photoURL'] as String;
    } catch (_) {}
    return (name: name.trim().isEmpty ? 'Viajero Ohtli' : name.trim(), photo: photo);
  }

  /// Solicitud de un plan hecho a mano: el viaje [tripId] ya existe (con `groupTripId: id`).
  /// Avisa a cada invitado; quien acepta se suma como coautor.
  static Future<void> createManual({
    required String id,
    required String tripId,
    required String title,
    DateTime? travelDate,
    required List<FriendOption> invitees,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final host = await me();
    await _col.doc(id).set({
      'kind': kGroupKindManual,
      'hostId': uid,
      'hostName': host.name,
      'hostPhoto': ?host.photo,
      'title': title,
      'tripId': tripId,
      if (travelDate != null) 'travelDate': Timestamp.fromDate(travelDate),
      'invitedIds': [for (final f in invitees) f.uid],
      'members': {
        for (final f in invitees) f.uid: {'name': f.name, if (f.photoUrl != null) 'photo': f.photoUrl},
      },
      'responses': <String, String>{},
      'intentions': <String, String>{},
      'votes': <String, int>{},
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _notifyInvitees(id, title, host, uid, invitees, tripId: tripId);
  }

  static Future<void> _notifyInvitees(String id, String title, ({String name, String? photo}) host, String hostId,
      List<FriendOption> invitees,
      {String? tripId}) async {
    final batch = _db.batch();
    for (final f in invitees) {
      batch.set(_db.collection('users').doc(f.uid).collection('notifications').doc('group_${id}_invite'), {
        'type': 'group_trip_invite',
        'senderId': hostId,
        'senderName': host.name,
        'senderPhoto': ?host.photo,
        'groupTripId': id,
        'tripId': ?tripId,
        'tripOwnerId': hostId,
        'tripTitle': title,
        'isPlan': true,
        'status': 'pending',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
    } catch (_) {
      // Un aviso que ya existía no se puede reescribir: los demás se mandan uno por uno.
      for (final f in invitees) {
        try {
          await _db.collection('users').doc(f.uid).collection('notifications').doc('group_${id}_invite').set({
            'type': 'group_trip_invite',
            'senderId': hostId,
            'senderName': host.name,
            'senderPhoto': ?host.photo,
            'groupTripId': id,
            'tripId': ?tripId,
            'tripOwnerId': hostId,
            'tripTitle': title,
            'isPlan': true,
            'status': 'pending',
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    }
  }

  /// Responder la invitación. En un plan a mano, aceptar te suma como coautor del viaje.
  static Future<void> respond(GroupTrip g, {required bool accept, String intention = ''}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final mine = await me();
    final answer = accept ? 'accepted' : 'declined';
    final text = intention.trim();
    await _col.doc(g.id).update({
      'responses.$uid': answer,
      if (accept && text.isNotEmpty) 'intentions.$uid': text,
    });
    if (accept && g.isManual && g.tripId != null) {
      await _db.collection('users').doc(g.hostId).collection('trips').doc(g.tripId).update({
        'coAuthorIds': FieldValue.arrayUnion([uid]),
        'coAuthorNames': FieldValue.arrayUnion([mine.name]),
      });
    }
    // Tu aviso queda como respondido.
    try {
      await _db.collection('users').doc(uid).collection('notifications').doc('group_${g.id}_invite').update({'status': answer, 'read': true});
    } catch (_) {}
    // Y quien organiza se entera.
    try {
      await _db.collection('users').doc(g.hostId).collection('notifications').doc('group_${g.id}_${answer}_$uid').set({
        'type': accept ? 'group_trip_accepted' : 'group_trip_declined',
        'senderId': uid,
        'senderName': mine.name,
        'senderPhoto': ?mine.photo,
        'groupTripId': g.id,
        'tripId': ?g.tripId,
        'tripOwnerId': g.hostId,
        'tripTitle': g.title,
        'isPlan': true,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
