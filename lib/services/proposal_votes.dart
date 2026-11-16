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

/// Quiénes votaron por [candidateId] (uids, en el orden en que llegaron los votos).
List<String> votersOf(Map<String, String> votes, String candidateId) =>
    [for (final e in votes.entries) if (e.value == candidateId) e.key];

/// Votos válidos (de lugares que siguen propuestos) por persona: si alguien votó por un lugar
/// que ya se quitó, su voto no cuenta y puede volver a votar.
Map<String, String> validVotes(Map<String, String> votes, List<ProposalCandidate> candidates) {
  final ids = {for (final c in candidates) c.id};
  return {for (final e in votes.entries) if (ids.contains(e.value)) e.key: e.value};
}

/// «3 de 4 ya votaron», con quién falta.
String proposalTally(Map<String, String> votes, List<String> editors, Map<String, String> names, {String? myUid}) {
  final voted = editors.where(votes.containsKey).length;
  if (editors.isEmpty) return '${votes.length} ${votes.length == 1 ? 'voto' : 'votos'}';
  if (voted == editors.length) return 'Ya votaron todos';
  final others = [
    for (final e in editors)
      if (!votes.containsKey(e) && e != myUid) names[e]?.trim().isNotEmpty == true ? names[e]!.trim() : 'alguien',
  ];
  final bool meMissing = myUid != null && editors.contains(myUid) && !votes.containsKey(myUid);
  String falta = '';
  if (meMissing && others.isEmpty) {
    falta = ' · falta tu voto';
  } else if (others.length + (meMissing ? 1 : 0) <= 3) {
    final all = [...others, if (meMissing) 'tú'];
    falta = ' · falta${all.length == 1 ? '' : 'n'} ${_joinNames(all)}';
  }
  return '$voted de ${editors.length} ya votaron$falta';
}

String _joinNames(List<String> xs) {
  if (xs.length <= 1) return xs.join();
  return '${xs.take(xs.length - 1).join(', ')} y ${xs.last}';
}
