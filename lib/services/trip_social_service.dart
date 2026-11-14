import 'package:cloud_firestore/cloud_firestore.dart';

/// Reacciones rápidas estilo "tapback": una por persona en cada bloque o nota.
class Tapback {
  final String id;
  final String emoji;
  final String label;
  const Tapback(this.id, this.emoji, this.label);
}

const List<Tapback> kTapbacks = [
  Tapback('heart', '❤️', 'Me encanta'),
  Tapback('haha', '😂', 'Jaja'),
  Tapback('surprise', '😮', '¡Sorpresa!'),
  Tapback('hundred', '💯', 'Cien por ciento'),
  Tapback('fire', '🔥', '¡Está buenísimo!'),
  Tapback('photo', '📸', '¡Qué foto!'),
];

Tapback? tapbackOf(String? id) {
  for (final t in kTapbacks) {
    if (t.id == id) return t;
  }
  return null;
}

/// Cuenta reacciones por tipo, en el orden de [kTapbacks], omitiendo las desconocidas.
List<MapEntry<Tapback, int>> summarizeReactions(Map<String, String> byUser) {
  final counts = <String, int>{};
  for (final kind in byUser.values) {
    if (tapbackOf(kind) != null) counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return [
    for (final t in kTapbacks)
      if ((counts[t.id] ?? 0) > 0) MapEntry(t, counts[t.id]!),
  ];
}

/// Nota del grupo anclada a un bloque del viaje.
class TripNote {
  final String id;
  final String blockId;
  final String authorId;
  final String authorName;
  final String? authorPhoto;
  final String text;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final Map<String, String> reactions;

  const TripNote({
    required this.id,
    required this.blockId,
    required this.authorId,
    required this.authorName,
    this.authorPhoto,
    required this.text,
    this.createdAt,
    this.editedAt,
    this.reactions = const {},
  });

  factory TripNote.fromMap(String id, Map<String, dynamic> data) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    final raw = data['reactions'];
    return TripNote(
      id: id,
      blockId: (data['blockId'] ?? '').toString(),
      authorId: (data['authorId'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'Viajero').toString(),
      authorPhoto: data['authorPhoto'] as String?,
      text: (data['text'] ?? '').toString(),
      createdAt: ts(data['createdAt']),
      editedAt: ts(data['editedAt']),
      reactions: raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v.toString())) : const {},
    );
  }
}

/// Notas y reacciones privadas de los miembros de un viaje.
/// Viven en users/{ownerId}/trips/{tripId}/notes y /reactions.
class TripSocialService {
  final String ownerId;
  final String tripId;
  final FirebaseFirestore _db;

  TripSocialService(this.ownerId, this.tripId, {FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _trip => _db.collection('users').doc(ownerId).collection('trips').doc(tripId);
  CollectionReference<Map<String, dynamic>> get _notes => _trip.collection('notes');
  CollectionReference<Map<String, dynamic>> get _reactions => _trip.collection('reactions');

  static const int maxNoteLength = 1000;

  Stream<List<TripNote>> notesStream() => _notes
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map((d) => TripNote.fromMap(d.id, d.data())).toList());

  /// blockId → (uid → tapback)
  Stream<Map<String, Map<String, String>>> reactionsStream() => _reactions.snapshots().map((s) => {
        for (final d in s.docs) d.id: d.data().map((k, v) => MapEntry(k, v.toString())),
      });

  Future<void> addNote({
    required String blockId,
    required String authorId,
    required String authorName,
    String? authorPhoto,
    required String text,
  }) {
    final clean = text.trim();
    if (clean.isEmpty) return Future.value();
    return _notes.add({
      'blockId': blockId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhoto': authorPhoto,
      'text': clean.length > maxNoteLength ? clean.substring(0, maxNoteLength) : clean,
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': <String, String>{},
    });
  }

  Future<void> editNote(String noteId, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return Future.value();
    return _notes.doc(noteId).update({
      'text': clean.length > maxNoteLength ? clean.substring(0, maxNoteLength) : clean,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNote(String noteId) => _notes.doc(noteId).delete();

  /// [kind] null quita la reacción.
  Future<void> reactToNote(String noteId, String uid, String? kind) =>
      _notes.doc(noteId).update({'reactions.$uid': kind ?? FieldValue.delete()});

  /// [kind] null quita la reacción.
  Future<void> reactToBlock(String blockId, String uid, String? kind) =>
      _reactions.doc(blockId).set({uid: kind ?? FieldValue.delete()}, SetOptions(merge: true));
}
