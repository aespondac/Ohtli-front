import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/trip_model.dart';

/// Votos de las propuestas de lugares de un viaje (`users/{dueño}/trips/{id}/votes/{bloque}`):
/// un campo por persona con el lugar que eligió. Viven fuera del contenido para que guardar el
/// viaje no los pise.
class ProposalVotes {
  static DocumentReference<Map<String, dynamic>> _ref(String ownerId, String tripId, String proposalId) =>
      FirebaseFirestore.instance.collection('users').doc(ownerId).collection('trips').doc(tripId).collection('votes').doc(proposalId);

  /// Votos de la propuesta: uid → id del lugar.
  static Stream<Map<String, String>> watch(String ownerId, String tripId, String proposalId) =>
      _ref(ownerId, tripId, proposalId).snapshots().map((s) => {
            for (final e in (s.data() ?? const <String, dynamic>{}).entries) e.key: e.value.toString(),
          });

  /// Tu voto por [candidateId]; con null lo quitas.
  static Future<void> vote(String ownerId, String tripId, String proposalId, String? candidateId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _ref(ownerId, tripId, proposalId).set({uid: candidateId ?? FieldValue.delete()}, SetOptions(merge: true));
  }
}

/// El lugar que gana: el más votado; en empate, el que votó [tieBreakerUid] (quien organiza)
/// si está entre los empatados, y si no el que se propuso primero. Sin votos, ninguno.
ProposalCandidate? proposalWinner(List<ProposalCandidate> candidates, Map<String, String> votes, {String? tieBreakerUid}) {
  final count = <String, int>{};
  for (final v in votes.values) {
    count[v] = (count[v] ?? 0) + 1;
  }
  final valid = candidates.where((c) => (count[c.id] ?? 0) > 0).toList();
  if (valid.isEmpty) return null;
  final best = valid.map((c) => count[c.id]!).reduce((a, b) => a > b ? a : b);
  final tied = valid.where((c) => count[c.id] == best).toList();
  if (tied.length == 1) return tied.single;
  final pick = tieBreakerUid == null ? null : votes[tieBreakerUid];
  for (final c in tied) {
    if (c.id == pick) return c;
  }
  return tied.first;
}

/// ¿Ya votaron todos los que editan el viaje?
bool everyoneVotedOn(Map<String, String> votes, Iterable<String> editors) =>
    editors.isNotEmpty && editors.every(votes.containsKey);
