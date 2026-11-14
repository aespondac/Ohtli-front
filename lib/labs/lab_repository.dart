import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Persistencia de Ohtli Labs en Firestore (proyecto othli-497404).
///
///  lab_runs/{runId}              corrida de un estudio: configuración, estado, resumen, publicación
///  lab_runs/{runId}/rows/{n}     resultado de cada escenario o solicitud
///  lab_studies/{studyId}         estado del estudio (activo para testers, corrida fuente del juicio)
///  lab_responses/{id}            respuestas de testers (SUS, juicios de relevancia)
///  lab_site/paper                texto del reporte público de labs.ohtli.quest
///
/// Las reglas de firestore.rules restringen la escritura al superusuario y la lectura pública a
/// lo publicado; esta clase no decide permisos.
class LabRepository {
  LabRepository._();
  static final LabRepository instance = LabRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get runs => _db.collection('lab_runs');
  CollectionReference<Map<String, dynamic>> get studies => _db.collection('lab_studies');
  CollectionReference<Map<String, dynamic>> get responses => _db.collection('lab_responses');
  DocumentReference<Map<String, dynamic>> get paper => _db.collection('lab_site').doc('paper');

  Future<String> createRun(String studyId, Map<String, dynamic> config, {String? label}) async {
    final ref = runs.doc();
    await ref.set({
      'studyId': studyId,
      'label': label ?? '',
      'status': 'running',
      'config': config,
      'startedAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
      'published': false,
      'evalSource': false,
      'summary': null,
      'notes': '',
    });
    return ref.id;
  }

  Future<void> addRow(String runId, int index, Map<String, dynamic> row) =>
      runs.doc(runId).collection('rows').doc(index.toString().padLeft(4, '0')).set({...row, 'index': index});

  Future<void> updateRun(String runId, Map<String, dynamic> data) => runs.doc(runId).update(data);

  Future<void> finishRun(String runId, Map<String, dynamic> summary, {String status = 'completed'}) =>
      runs.doc(runId).update({'status': status, 'summary': summary, 'finishedAt': FieldValue.serverTimestamp()});

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRuns(String studyId) =>
      runs.where('studyId', isEqualTo: studyId).orderBy('startedAt', descending: true).limit(30).snapshots();

  /// Corridas publicadas (para labs.ohtli.quest).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPublished() =>
      runs.where('published', isEqualTo: true).orderBy('startedAt', descending: true).limit(60).snapshots();

  Future<List<Map<String, dynamic>>> rows(String runId) async {
    final q = await runs.doc(runId).collection('rows').orderBy('index').get();
    return q.docs.map((d) => d.data()).toList();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchStudy(String studyId) => studies.doc(studyId).snapshots();

  Future<void> setStudy(String studyId, Map<String, dynamic> data) =>
      studies.doc(studyId).set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  Future<void> addResponse(String studyId, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return responses.add({
      ...data,
      'studyId': studyId,
      'uid': uid,
      'consent': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchResponses(String studyId) =>
      responses.where('studyId', isEqualTo: studyId).snapshots();

  /// Resultados agregados de los estudios con testers (los escribe la consola al publicarlos).
  DocumentReference<Map<String, dynamic>> aggregate(String studyId) => _db.collection('lab_site').doc('agg_$studyId');
}
