import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'friend_options.dart';
import 'itinerary_blackboard_service.dart';

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

  /// Lo escribe el motor: las 3 rutas, quiénes cuentan en el promedio y votan, la ganadora…
  final List<Map<String, dynamic>> options;
  final List<String> participantIds;
  final int? winner;
  final String? generationError;
  final String? cancelReason;

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
    this.options = const [],
    this.participantIds = const [],
    this.winner,
    this.generationError,
    this.cancelReason,
  });

  bool get isManual => kind == kGroupKindManual;

  /// Quiénes votan: el organizador y quienes aceptaron, como cuenta el motor al cerrar
  /// (también quien aceptó tarde, aunque sus gustos ya no entraran en las rutas).
  List<String> get voters => {hostId, ...acceptedIds}.toList();

  List<String> votersFor(int option) => [
        for (final u in voters)
          if (votes[u] == option) u,
      ];

  bool get everyoneVoted => voters.isNotEmpty && voters.every(votes.containsKey);

  bool get everyoneResponded => pendingIds.isEmpty;

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
      options: [
        for (final o in (d['options'] as List?) ?? const [])
          if (o is Map) Map<String, dynamic>.from(o),
      ],
      participantIds: ((d['participantIds'] as List?) ?? const []).map((e) => e.toString()).toList(),
      winner: (d['winner'] as num?)?.toInt(),
      generationError: d['generationError']?.toString(),
      cancelReason: d['cancelReason']?.toString(),
    );
  }
}

class GroupTripService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('group_trips');

  static String newId() => 'grp_${const Uuid().v4()}';

  static Stream<GroupTrip?> watch(String id) =>
      _col.doc(id).snapshots().map((s) => s.exists ? GroupTrip.fromMap(s.id, s.data()!) : null);

  /// Tus planes en grupo: los que organizas y a los que te invitaron.
  static Stream<List<GroupTrip>> watchMine(String uid) {
    late StreamController<List<GroupTrip>> controller;
    var hosted = <GroupTrip>[];
    var invited = <GroupTrip>[];
    StreamSubscription? a;
    StreamSubscription? b;
    void emit() {
      final byId = {for (final g in [...hosted, ...invited]) g.id: g};
      controller.add(byId.values.toList());
    }

    controller = StreamController<List<GroupTrip>>(
      onListen: () {
        a = _col.where('hostId', isEqualTo: uid).snapshots().listen((s) {
          hosted = [for (final d in s.docs) GroupTrip.fromMap(d.id, d.data())];
          emit();
        }, onError: (_) {});
        b = _col.where('invitedIds', arrayContains: uid).snapshots().listen((s) {
          invited = [for (final d in s.docs) GroupTrip.fromMap(d.id, d.data())];
          emit();
        }, onError: (_) {});
      },
      onCancel: () {
        a?.cancel();
        b?.cancel();
      },
    );
    return controller.stream;
  }

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

  /// Solicitud de un plan con IA: el motor genera las rutas con los gustos de quienes acepten
  /// (al responder todos o al vencer [respondWindow]) y luego votan durante [voteWindow].
  static Future<String> createAi({
    required String title,
    required DateTime travelDate,
    required Map<String, dynamic> params,
    required List<FriendOption> invitees,
    required Duration respondWindow,
    required Duration voteWindow,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final host = await me();
    final id = newId();
    final respondBy = DateTime.now().add(respondWindow);
    await _col.doc(id).set({
      'kind': kGroupKindAi,
      'hostId': uid,
      'hostName': host.name,
      'hostPhoto': ?host.photo,
      'title': title,
      'travelDate': Timestamp.fromDate(travelDate),
      'invitedIds': [for (final f in invitees) f.uid],
      'members': {
        for (final f in invitees) f.uid: {'name': f.name, 'photo': ?f.photoUrl},
      },
      'responses': <String, String>{},
      'intentions': <String, String>{},
      'votes': <String, int>{},
      'params': params,
      'respondBy': Timestamp.fromDate(respondBy),
      'voteBy': Timestamp.fromDate(respondBy.add(voteWindow)),
      'status': 'inviting',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _notifyInvitees(id, title, host, uid, invitees);
    return id;
  }

  /// Pide al motor generar las rutas ya (el organizador, o cualquiera cuando todos respondieron).
  static Future<bool> generate(String id) => _postEngine('/v1/group-trips/$id/generate');

  /// Pide al motor cerrar la votación y crear el viaje (el organizador, o cuando todos votaron).
  static Future<bool> close(String id) => _postEngine('/v1/group-trips/$id/close');

  static Future<bool> _postEngine(String path) async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    for (final base in ItineraryBlackboardService.apiBases) {
      try {
        final res = await http
            .post(Uri.parse('$base$path'),
                headers: {'Content-Type': 'application/json', 'Authorization': ?(token == null ? null : 'Bearer $token')},
                body: jsonEncode(const {}))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
        // Un 4xx (sin permiso, estado que no lo permite) no cambia en el otro servidor.
        if (res.statusCode >= 400 && res.statusCode < 500) return false;
      } catch (_) {}
    }
    return false;
  }

  /// Tu voto (índice de la ruta). Si con él ya votaron todos, se cierra la votación.
  static Future<void> vote(GroupTrip g, int option) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _col.doc(g.id).update({'votes.$uid': option});
    final fresh = await get(g.id);
    if (fresh != null && fresh.status == 'voting' && fresh.everyoneVoted) unawaited(close(g.id));
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
    // Plan con IA: si con esta respuesta ya respondieron todos, se generan las rutas.
    if (!g.isManual) {
      try {
        final fresh = await get(g.id);
        // Si todos rechazaron, el motor lo cancela al momento (en vez de esperar al plazo).
        if (fresh != null && fresh.status == 'inviting' && fresh.everyoneResponded) {
          unawaited(generate(g.id));
        }
      } catch (_) {}
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
