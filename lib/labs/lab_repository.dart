import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Persistencia de Ohtli Labs en Firestore (proyecto othli-497404).
///
///  lab_runs/{runId}              corrida de un estudio: configuración, estado, resumen, publicación
///  lab_runs/{runId}/rows/{n}     resultado de cada escenario o solicitud
///  lab_studies/{studyId}         estado del estudio (activo para testers, corrida fuente del juicio)
///  lab_responses/{id}            respuestas de testers (SUS, juicios de relevancia)
///  lab_site/agg_{studyId}        agregados de los estudios con testers (con visibilidad)
///  lab_posts/{postId}            artículos: borrador → privado → testers → público (blog)
///  lab_members/{uid}, lab_invites/{email}  roles del laboratorio (ver lab_access.dart)
///
/// Visibilidad (campo visibility): private = solo miembros del laboratorio, testers = también
/// testers registrados, public = cualquiera sin iniciar sesión (solo el superusuario).
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
      'visibility': 'private',
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

  /// Corridas visibles en los niveles dados (p. ej. ['public'] para el sitio abierto).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchVisible(List<String> levels) =>
      runs.where('visibility', whereIn: levels).orderBy('startedAt', descending: true).limit(60).snapshots();

  Future<void> setRunVisibility(String runId, String visibility) => runs.doc(runId).update({
        'visibility': visibility,
        if (visibility != 'private') 'releasedAt': FieldValue.serverTimestamp(),
      });

  // ---- Artículos ----
  CollectionReference<Map<String, dynamic>> get posts => _db.collection('lab_posts');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllPosts() => posts.orderBy('updatedAt', descending: true).snapshots();

  /// Artículos publicados en los niveles dados (blog público: ['public']).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPublishedPosts(List<String> levels) => posts
      .where('status', isEqualTo: 'published')
      .where('visibility', whereIn: levels)
      .orderBy('publishedAt', descending: true)
      .limit(50)
      .snapshots();

  Future<Map<String, dynamic>?> postBySlug(String slug, List<String> levels) async {
    final q = await posts
        .where('slug', isEqualTo: slug)
        .where('status', isEqualTo: 'published')
        .where('visibility', whereIn: levels)
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : {...q.docs.first.data(), 'id': q.docs.first.id};
  }

  Future<String> savePost(String? id, Map<String, dynamic> data) async {
    final ref = id == null ? posts.doc() : posts.doc(id);
    await ref.set({
      ...data,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      if (id == null) 'authorUid': FirebaseAuth.instance.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  Future<List<Map<String, dynamic>>> rows(String runId) async {
    final q = await runs.doc(runId).collection('rows').orderBy('index').get();
    return q.docs.map((d) => d.data()).toList();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchStudy(String studyId) => studies.doc(studyId).snapshots();

  Future<void> setStudy(String studyId, Map<String, dynamic> data) =>
      studies.doc(studyId).set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// Guarda una respuesta con ID determinista ([susResponseId] / [relevanceResponseId]): las
  /// reglas solo permiten crearla, así que reenviar no la duplica (falla con permission-denied).
  Future<void> addResponse(String studyId, String id, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return responses.doc(id).set({
      ...data,
      'studyId': studyId,
      'uid': uid,
      'consent': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Respuestas propias de un estudio (las reglas dejan leer a cada tester solo las suyas).
  Future<List<Map<String, dynamic>>> myResponses(String studyId, {String? runId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    Query<Map<String, dynamic>> q = responses.where('uid', isEqualTo: uid).where('studyId', isEqualTo: studyId);
    if (runId != null) q = q.where('runId', isEqualTo: runId);
    return (await q.get()).docs.map((d) => d.data()).toList();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchResponses(String studyId) =>
      responses.where('studyId', isEqualTo: studyId).snapshots();

  /// Resultados agregados de los estudios con testers (los escribe la consola al publicarlos).
  DocumentReference<Map<String, dynamic>> aggregate(String studyId) => _db.collection('lab_site').doc('agg_$studyId');
}
