import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../lab_experiments.dart';
import '../lab_studies.dart';
import 'lab_codenames.dart';
import 'lab_iam.dart';
import 'lab_models.dart';

/// Persistencia de la estructura de investigación (docs/labs_estructura.md). No decide permisos:
/// eso lo hacen las reglas de Firestore. Todo cambio relevante queda en `lab_audit`.
/// Escrituras por lote (Firestore admite 500; se deja margen).
const kMaxBatchWrites = 450;

/// Campos de proyecto de un experimento o encuesta. Al crear se escriben siempre; al editar solo si
/// se conoce el proyecto, para no borrar el que ya tiene.
Map<String, dynamic> libraryScopeFields({required bool isNew, LabProject? project}) =>
    (isNew || project != null) ? {'projectId': project?.id, 'confidential': project?.confidential ?? false} : const {};

class LabResearch {
  LabResearch._();
  static final LabResearch instance = LabResearch._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get projects => _db.collection('lab_projects');
  CollectionReference<Map<String, dynamic>> get studies => _db.collection('lab_studies');
  CollectionReference<Map<String, dynamic>> get features => _db.collection('lab_features');
  CollectionReference<Map<String, dynamic>> get enrollments => _db.collection('lab_enrollments');
  CollectionReference<Map<String, dynamic>> get papers => _db.collection('lab_papers');
  CollectionReference<Map<String, dynamic>> get experiments => _db.collection('lab_experiments');
  CollectionReference<Map<String, dynamic>> get surveys => _db.collection('lab_surveys');
  CollectionReference<Map<String, dynamic>> get surveyResponses => _db.collection('lab_survey_responses');
  CollectionReference<Map<String, dynamic>> get ndas => _db.collection('lab_ndas');
  CollectionReference<Map<String, dynamic>> get audit => _db.collection('lab_audit');
  CollectionReference<Map<String, dynamic>> get codenames => _db.collection('lab_codenames');

  DocumentReference<Map<String, dynamic>> details(DocumentReference<Map<String, dynamic>> ref) =>
      ref.collection('private').doc('details');

  static String enrollmentId(String studyId, String uid) => '${studyId}_$uid';
  static String ndaId(String scope, String uid) => '${scope}_$uid';

  // ───────────── Bitácora ─────────────

  /// [projectId] va dentro de `detail` (las reglas fijan los campos de primer nivel) y permite ver la
  /// bitácora de todo un proyecto con [watchProjectAudit].
  Future<void> log(String action, String target, [Map<String, dynamic> detail = const {}, String? projectId]) async {
    try {
      await audit.add({
        'action': action,
        'target': target,
        'detail': {...detail, 'projectId': ?projectId},
        'actorUid': _uid,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // La bitácora no debe tumbar la operación principal; las reglas la exigen en lo crítico.
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAudit({String? target, int limit = 80}) {
    Query<Map<String, dynamic>> q = audit.orderBy('at', descending: true).limit(limit);
    if (target != null) q = audit.where('target', isEqualTo: target).orderBy('at', descending: true).limit(limit);
    return q.snapshots();
  }

  /// Bitácora de un proyecto: todo lo registrado con su `projectId` (entradas desde la fase 1).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchProjectAudit(String projectId, {int limit = 120}) => audit
      .where('detail.projectId', isEqualTo: projectId)
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots();

  // ───────────── Proyectos ─────────────

  Stream<List<LabProject>> watchProjects() =>
      projects.snapshots().map((s) => [for (final d in s.docs) LabProject.fromDoc(d.id, d.data())]);

  /// Crea un proyecto. Si es confidencial, reserva un nombre en clave único y guarda el nombre real
  /// en `private/details`.
  Future<String> createProject({required String name, String description = '', required bool confidential}) async {
    final ref = projects.doc();
    final uid = _uid;
    String? codename;
    if (confidential) {
      final taken = (await codenames.get()).docs.map((d) => d.id).toSet();
      for (var attempt = 0; attempt < 6; attempt++) {
        final word = pickCodename(taken);
        try {
          await codenames.doc(word).set({'projectId': ref.id, 'at': FieldValue.serverTimestamp()});
          codename = word;
          break;
        } catch (_) {
          taken.add(word); // otro la tomó al mismo tiempo (las reglas solo dejan crearla una vez)
        }
      }
      if (codename == null) throw StateError('No se pudo reservar un nombre en clave');
    }
    final batch = _db.batch();
    batch.set(ref, {
      'name': confidential ? codenameLabel(codename!) : name,
      'description': confidential ? 'Proyecto confidencial.' : description,
      'confidential': confidential,
      'codename': codename,
      'ownerUid': uid,
      'members': [?uid],
      'iam': {?uid: 'owner'},
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (confidential) batch.set(details(ref), {'name': name, 'description': description});
    await batch.commit();
    await log('project.create', 'project:${ref.id}', {'confidential': confidential});
    return ref.id;
  }

  Future<Map<String, dynamic>?> secretOf(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      final d = await details(ref).get();
      return d.data();
    } catch (_) {
      return null; // sin autorización: se queda el nombre en clave
    }
  }

  CollectionReference<Map<String, dynamic>> _collectionOf(LabResourceKind kind) => switch (kind) {
        LabResourceKind.project => projects,
        LabResourceKind.study => studies,
        LabResourceKind.experiment => experiments,
        LabResourceKind.survey => surveys,
        LabResourceKind.functionality => features,
      };

  /// Guarda el IAM de un recurso. Mientras dure la migración también escribe el modelo anterior
  /// (`members` del proyecto, `collaborators` del estudio) para que las reglas y pantallas viejas
  /// sigan funcionando. [seed] crea el documento de un recurso integrado que aún no lo tiene.
  Future<void> setIam(LabResourceKind kind, String id, Map<String, String> iam,
      {String? projectId, Map<String, dynamic> seed = const {}}) async {
    final problem = validateIamChange(iam, requireOwner: kind == LabResourceKind.project);
    if (problem != null) throw StateError(problem);
    final ref = _collectionOf(kind).doc(id);
    final people = [for (final e in iam.entries) if (e.key != kLabAllMembers) e.key];
    final editors = [for (final e in iam.entries) if (e.key != kLabAllMembers && parseIamRole(e.value).canEdit) e.key];
    final exists = (await ref.get()).exists;
    await ref.set({
      if (!exists) ...seed,
      if (!exists && seed.isNotEmpty) 'ownerUid': _uid,
      'iam': iam,
      if (kind == LabResourceKind.project) 'members': people,
      if (kind == LabResourceKind.study) 'collaborators': editors,
    }, SetOptions(merge: true));
    await log('iam.update', '${kind.name}:$id', {'grants': iam.length}, projectId ?? (kind == LabResourceKind.project ? id : null));
  }

  /// Migración del modelo anterior al IAM (solo admin; se puede correr varias veces). Devuelve
  /// cuántos documentos cambió.
  Future<int> migrateIam() async {
    var changed = 0;
    var batch = _db.batch();
    var pending = 0;
    Future<void> put(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
      batch.update(ref, data);
      changed++;
      if (++pending >= kMaxBatchWrites) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    bool same(Map<String, dynamic>? a, Map<String, String> b) =>
        a != null && a.length == b.length && b.entries.every((e) => a[e.key] == e.value);

    for (final d in (await projects.get()).docs) {
      final v = d.data();
      final iam = iamFromLegacy(
        current: (v['iam'] as Map?)?.cast<String, dynamic>() ?? const {},
        owner: v['ownerUid'] as String?,
        editors: [for (final m in (v['members'] as List?) ?? const []) m.toString()],
        labViewers: v['confidential'] != true,
      );
      if (!same((v['iam'] as Map?)?.cast<String, dynamic>(), iam)) await put(d.reference, {'iam': iam});
    }
    for (final d in (await studies.get()).docs) {
      final v = d.data();
      final iam = iamFromLegacy(
        current: (v['iam'] as Map?)?.cast<String, dynamic>() ?? const {},
        owner: v['ownerUid'] as String?,
        editors: [for (final m in (v['collaborators'] as List?) ?? const []) m.toString()],
      );
      if (iam.isNotEmpty && !same((v['iam'] as Map?)?.cast<String, dynamic>(), iam)) await put(d.reference, {'iam': iam});
    }
    for (final col in [experiments, surveys]) {
      for (final d in (await col.get()).docs) {
        final v = d.data();
        final iam = iamFromLegacy(current: (v['iam'] as Map?)?.cast<String, dynamic>() ?? const {}, owner: v['ownerUid'] as String?);
        final noProject = (v['projectId'] as String?)?.isNotEmpty != true;
        final data = {
          if (iam.isNotEmpty && !same((v['iam'] as Map?)?.cast<String, dynamic>(), iam)) 'iam': iam,
          if (noProject) 'projectId': kPlatformProjectId,
        };
        if (data.isNotEmpty) await put(d.reference, data);
      }
    }
    for (final d in (await features.get()).docs) {
      if ((d.data()['projectId'] as String?)?.isNotEmpty != true) await put(d.reference, {'projectId': kPlatformProjectId});
    }
    if (pending > 0) await batch.commit();
    await log('iam.migrate', 'lab', {'changed': changed});
    return changed;
  }

  Future<void> setProjectMembers(String projectId, List<String> members) async {
    await projects.doc(projectId).update({'members': members});
    await log('project.members', 'project:$projectId', {'count': members.length});
  }

  /// Desclasificar (solo admin, lo exigen las reglas): copia los datos reales al documento público
  /// del proyecto y de todo lo que cuelga de él.
  Future<int> declassify(String projectId) async {
    final pRef = projects.doc(projectId);
    final secret = await secretOf(pRef) ?? const {};
    // Lotes de hasta 450 escrituras: Firestore no acepta más de 500 por lote y un proyecto grande
    // hacía fallar la desclasificación completa.
    var batch = _db.batch();
    var pending = 0;
    Future<void> add(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
      batch.update(ref, data);
      if (++pending >= kMaxBatchWrites) {
        await batch.commit();
        batch = _db.batch();
        pending = 0;
      }
    }

    var n = 0;
    for (final col in [studies, experiments, surveys, features, papers]) {
      final q = await col.where('projectId', isEqualTo: projectId).get();
      for (final d in q.docs) {
        final s = await secretOf(d.reference) ?? const {};
        await add(d.reference, {...s, 'confidential': false, 'declassifiedAt': FieldValue.serverTimestamp()});
        n++;
      }
    }
    // El proyecto al final: si algo falla a la mitad, sigue marcado como clasificado y se puede reintentar.
    await add(pRef, {
      if (secret['name'] != null) 'name': secret['name'],
      if (secret['description'] != null) 'description': secret['description'],
      'confidential': false,
      'declassifiedAt': FieldValue.serverTimestamp(),
    });
    if (pending > 0) await batch.commit();
    await log('project.declassify', 'project:$projectId', {'items': n});
    return n;
  }

  // ───────────── Estudios ─────────────

  Stream<List<LabResearchStudy>> watchStudies() => studies.snapshots().map((s) => [
        for (final d in s.docs)
          if (d.data().containsKey('status') || d.data().containsKey('builtinKind')) LabResearchStudy.fromDoc(d.id, d.data()),
      ]);

  Stream<LabResearchStudy?> watchStudy(String id) =>
      studies.doc(id).snapshots().map((d) => d.exists ? LabResearchStudy.fromDoc(d.id, d.data()!) : null);

  /// Las seis pruebas del TT como estudios del proyecto público "Trabajo Terminal" (idempotente).
  /// Proyectos base de la consola (solo admin): "Ohtli.quest (plataforma)", con los experimentos
  /// integrados y las funcionalidades del SMA, visible para todo el laboratorio; y Trabajo Terminal
  /// editable por todo el laboratorio (como hasta ahora: cualquier miembro corre las pruebas del TT).
  Future<void> ensureBaseProjects() async {
    final uid = _uid;
    final platform = projects.doc(kPlatformProjectId);
    if (!(await platform.get()).exists) {
      await platform.set({
        'name': 'Ohtli.quest (plataforma)',
        'description': 'Experimentos de la plataforma y funcionalidades del sistema multiagente.',
        'confidential': false,
        'ownerUid': uid,
        'members': [?uid],
        // Todo el laboratorio la ve; editar cada experimento o funcionalidad es de su propietario.
        'iam': {?uid: 'owner', kLabAllMembers: 'viewer'},
        'createdAt': FieldValue.serverTimestamp(),
      });
      await log('project.create', 'project:$kPlatformProjectId', const {}, kPlatformProjectId);
    }
    final tt = projects.doc(kTtProjectId);
    final ttData = (await tt.get()).data();
    if (ttData != null && (ttData['iam'] as Map?)?.containsKey(kLabAllMembers) != true) {
      final iam = iamFromLegacy(
        current: (ttData['iam'] as Map?)?.cast<String, dynamic>() ?? const {},
        owner: ttData['ownerUid'] as String?,
        editors: [for (final m in (ttData['members'] as List?) ?? const []) m.toString()],
      )..[kLabAllMembers] = 'editor';
      await tt.update({'iam': iam});
    }
  }

  Future<void> ensureTtStudies() async {
    final p = projects.doc(kTtProjectId);
    if (!(await p.get()).exists) {
      await p.set({
        'name': 'Trabajo Terminal',
        'description': 'Pruebas del capítulo 6 del Trabajo Terminal 2026-B156.',
        'confidential': false,
        'ownerUid': _uid,
        'members': [?_uid],
        'iam': {?_uid: 'owner', kLabAllMembers: 'editor'},
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    for (final s in kLabStudies) {
      final ref = studies.doc(s.id);
      final cur = (await ref.get()).data() ?? const {};
      if (cur.containsKey('builtinKind')) continue;
      await ref.set({
        'projectId': kTtProjectId,
        'title': s.title,
        'description': s.description,
        'builtinKind': s.kind.name,
        'status': cur['active'] == true ? StudyStatus.enCurso.id : StudyStatus.preregistrado.id,
        'confidential': false,
        'ownerUid': _uid,
        'preregistration': {
          'hypotheses': 'Criterio de aceptación: ${s.criterion}',
          'analysisPlan': 'Ver ${s.chapter} del Trabajo Terminal.',
          'metrics': const [],
          'frozenAt': FieldValue.serverTimestamp(),
          'amendments': 0,
        },
        'config': StudyConfig(participantValidation: s.needsTesters).toMap(),
        'experimentIds': const [],
        'surveyIds': [if (s.kind == LabStudyKind.sus) 'sus'],
        'featureKeys': const [],
        'consentVersion': 1,
        'enrolledCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<String> createStudy({required LabProject project, required String title, String description = ''}) async {
    final ref = studies.doc();
    final masked = project.confidential;
    final batch = _db.batch();
    final count = (await studies.where('projectId', isEqualTo: project.id).count().get()).count ?? 0;
    batch.set(ref, {
      'projectId': project.id,
      'title': masked ? '${project.codename} · Estudio ${count + 1}' : title,
      'description': masked ? 'Estudio confidencial.' : description,
      'confidential': masked,
      'status': StudyStatus.borrador.id,
      'ownerUid': _uid,
      'collaborators': const [],
      'preregistration': {'hypotheses': '', 'analysisPlan': '', 'metrics': const [], 'frozenAt': null, 'amendments': 0},
      'config': const StudyConfig().toMap(),
      'experimentIds': const [],
      'surveyIds': const [],
      'featureKeys': const [],
      'consentVersion': 1,
      'consentText': '',
      'enrolledCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (masked) batch.set(details(ref), {'title': title, 'description': description});
    await batch.commit();
    await log('study.create', 'study:${ref.id}', {'projectId': project.id});
    return ref.id;
  }

  /// Guarda campos editables (no el preregistro una vez congelado: eso es [amend]).
  Future<void> updateStudy(LabResearchStudy s, Map<String, dynamic> data, {Map<String, dynamic>? secret}) async {
    final batch = _db.batch();
    batch.update(studies.doc(s.id), {...data, 'updatedAt': FieldValue.serverTimestamp()});
    if (secret != null && s.confidential) batch.set(details(studies.doc(s.id)), secret, SetOptions(merge: true));
    await batch.commit();
  }

  Map<String, dynamic> _prereg(String hypotheses, String plan, List<LabMetric> metrics) => {
        'preregistration.hypotheses': hypotheses,
        'preregistration.analysisPlan': plan,
        'preregistration.metrics': [for (final m in metrics) m.toMap()],
      };

  Future<void> saveDraftPrereg(LabResearchStudy s, String hypotheses, String plan, List<LabMetric> metrics) =>
      studies.doc(s.id).update({..._prereg(hypotheses, plan, metrics), 'updatedAt': FieldValue.serverTimestamp()});

  /// Congela el preregistro y pasa el estudio a "preregistrado".
  Future<void> freeze(LabResearchStudy s, String hypotheses, String plan, List<LabMetric> metrics) async {
    if (hypotheses.trim().isEmpty || metrics.isEmpty) {
      throw StateError('El preregistro necesita hipótesis y al menos una métrica.');
    }
    await studies.doc(s.id).update({
      ..._prereg(hypotheses, plan, metrics),
      'preregistration.frozenAt': FieldValue.serverTimestamp(),
      'status': StudyStatus.preregistrado.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await log('study.preregister', 'study:${s.id}', {'metrics': metrics.length});
  }

  /// Enmienda al preregistro congelado: queda en la bitácora con su motivo y la lista el paper.
  Future<void> amend(LabResearchStudy s, String reason, String hypotheses, String plan, List<LabMetric> metrics) async {
    if (reason.trim().length < 10) throw StateError('Explica el motivo de la enmienda.');
    await studies.doc(s.id).update({
      ..._prereg(hypotheses, plan, metrics),
      'preregistration.amendments': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await log('study.amend', 'study:${s.id}', {
      'reason': reason,
      'number': s.amendments + 1,
      'before': {'hypotheses': s.hypotheses, 'analysisPlan': s.analysisPlan, 'metrics': [for (final m in s.metrics) m.toMap()]},
    });
  }

  Future<void> transition(LabResearchStudy s, StudyStatus to) async {
    if (!canTransition(s.status, to)) throw StateError('No se puede pasar de ${s.status.label} a ${to.label}.');
    await studies.doc(s.id).update({
      'status': to.id,
      // Compatibilidad con las pruebas del TT: "activo" = acepta respuestas de testers.
      if (s.builtinKind != null) 'active': to == StudyStatus.enCurso || to == StudyStatus.reclutando,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await log('study.status', 'study:${s.id}', {'from': s.status.id, 'to': to.id});
  }

  /// Cambiar de proyecto. A uno confidencial lo enmascara; a uno público solo si el actual no lo es.
  Future<void> moveStudy(LabResearchStudy s, LabProject to) async {
    if (s.confidential && !to.confidential) {
      throw StateError('Un estudio confidencial solo se hace público al desclasificar su proyecto.');
    }
    final batch = _db.batch();
    final ref = studies.doc(s.id);
    if (to.confidential && !s.confidential) {
      batch.set(details(ref), {'title': s.title, 'description': s.description});
      batch.update(ref, {'title': '${to.codename} · ${s.id.substring(0, 4).toUpperCase()}', 'description': 'Estudio confidencial.', 'confidential': true});
    }
    batch.update(ref, {'projectId': to.id, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
    await log('study.move', 'study:${s.id}', {'from': s.projectId, 'to': to.id});
  }

  // ───────────── Inscripción y NDA ─────────────

  Stream<Set<String>> watchMyEnrolledStudyIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(const {});
    return enrollments
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((s) => {for (final d in s.docs) (d.data()['studyId'] ?? '').toString()});
  }

  Future<bool> hasNda(String scope) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      return (await ndas.doc(ndaId(scope, uid)).get()).exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> acceptNda(String scope, String version) async {
    final uid = _uid!;
    await ndas.doc(ndaId(scope, uid)).set({'uid': uid, 'scope': scope, 'version': version, 'at': FieldValue.serverTimestamp()});
    await log('nda.accept', scope);
  }

  /// Inscribirse: consentimiento del estudio (y NDA del proyecto si es confidencial, que ya se
  /// aceptó con [acceptNda]). Sube el contador; las reglas solo dejan moverlo de uno en uno.
  Future<void> enroll(LabResearchStudy s) async {
    final uid = _uid!;
    if (s.isFull) throw StateError('El estudio ya llegó a su cupo.');
    try {
      if ((await enrollments.doc(enrollmentId(s.id, uid)).get()).exists) return rejoin(s);
    } catch (_) {
      // Sin documento previo la regla de lectura no aplica; seguimos con el alta.
    }
    final batch = _db.batch();
    batch.set(enrollments.doc(enrollmentId(s.id, uid)), {
      'uid': uid,
      'studyId': s.id,
      'status': 'active',
      'consentVersion': s.consentVersion,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(studies.doc(s.id), {'enrolledCount': FieldValue.increment(1)});
    await batch.commit();
    await log('study.enroll', 'study:${s.id}'); // sin identidad en el detalle
  }

  /// Inscripciones propias activas con la versión de consentimiento que aceptó cada una.
  Stream<Map<String, int>> watchMyConsentVersions() {
    final uid = _uid;
    if (uid == null) return Stream.value(const {});
    return enrollments.where('uid', isEqualTo: uid).where('status', isEqualTo: 'active').snapshots().map((s) => {
          for (final d in s.docs) (d.data()['studyId'] ?? '').toString(): (d.data()['consentVersion'] as num?)?.toInt() ?? 1,
        });
  }

  /// Aceptar el consentimiento actualizado del estudio.
  Future<void> reconsent(LabResearchStudy s) =>
      enrollments.doc(enrollmentId(s.id, _uid!)).update({'consentVersion': s.consentVersion, 'status': 'active'});

  /// Volver a inscribirse tras una baja (el documento ya existe).
  Future<void> rejoin(LabResearchStudy s) async {
    final batch = _db.batch();
    batch.update(enrollments.doc(enrollmentId(s.id, _uid!)), {'status': 'active', 'consentVersion': s.consentVersion});
    batch.update(studies.doc(s.id), {'enrolledCount': FieldValue.increment(1)});
    await batch.commit();
    await log('study.enroll', 'study:${s.id}');
  }

  Future<void> leave(LabResearchStudy s, {bool withdrawData = false}) async {
    final uid = _uid!;
    final batch = _db.batch();
    batch.update(enrollments.doc(enrollmentId(s.id, uid)), {
      'status': 'left',
      'leftAt': FieldValue.serverTimestamp(),
      'withdrawData': withdrawData,
    });
    batch.update(studies.doc(s.id), {'enrolledCount': FieldValue.increment(-1)});
    await batch.commit();
    await log('study.leave', 'study:${s.id}', {'withdrawData': withdrawData});
  }

  // ───────────── Funcionalidades ─────────────

  Stream<List<LabFeature>> watchFeatures() =>
      features.snapshots().map((s) => [for (final d in s.docs) LabFeature.fromDoc(d.id, d.data())]);

  Future<void> saveFeature(String key, Map<String, dynamic> data) async {
    await features.doc(key).set({...data, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await log('feature.save', 'feature:$key');
  }

  /// Decisión del admin sobre el destino de la función (oficial, beta o retirada).
  Future<void> setFeatureStage(String key, FeatureStage stage, {String reason = ''}) async {
    await features.doc(key).update({'stage': stage.name, 'stageChangedAt': FieldValue.serverTimestamp(), 'stageReason': reason});
    await log('feature.stage', 'feature:$key', {'stage': stage.name, 'reason': reason});
  }

  // ───────────── Papers ─────────────

  Stream<List<LabPaper>> watchPapers({String? studyId}) {
    final Query<Map<String, dynamic>> q = studyId == null ? papers : papers.where('studyId', isEqualTo: studyId);
    return q.snapshots().map((s) => [for (final d in s.docs) LabPaper.fromDoc(d.id, d.data())]);
  }

  Stream<LabPaper?> watchPaper(String id) =>
      papers.doc(id).snapshots().map((d) => d.exists ? LabPaper.fromDoc(d.id, d.data()!) : null);

  /// Papers no clasificados en una etapa (los de proyectos confidenciales se abren desde su estudio).
  Stream<List<LabPaper>> watchPapersAt(PaperStage stage) => papers
      .where('confidential', isEqualTo: false)
      .where('stage', isEqualTo: stage.id)
      .snapshots()
      .map((s) => [for (final d in s.docs) LabPaper.fromDoc(d.id, d.data())]);

  Future<String> createPaper(LabResearchStudy s) async {
    final ref = papers.doc();
    await ref.set({
      'studyId': s.id,
      'projectId': s.projectId,
      'title': s.title,
      'abstract': '',
      'body': '',
      'stage': PaperStage.borrador.id,
      'round': 1,
      'authors': [if (_uid != null) _uid],
      'reproducibility': {
        'preregistration': {'hypotheses': s.hypotheses, 'analysisPlan': s.analysisPlan, 'metrics': [for (final m in s.metrics) m.toMap()]},
        'amendments': s.amendments,
        'runIds': const [],
        'appCommit': '',
        'engineCommit': '',
        'procedure': '',
        'datasetUrl': '',
      },
      'confidential': s.confidential,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // El estudio (lectura pública, enmascarado) apunta a su paper vigente: así los testers lo
    // abren por ID, que es lo que las reglas pueden autorizar.
    await studies.doc(s.id).update({'currentPaperId': ref.id, 'paperStage': PaperStage.borrador.id});
    await log('paper.create', 'paper:${ref.id}', {'studyId': s.id});
    return ref.id;
  }

  Future<void> savePaper(String id, Map<String, dynamic> data) =>
      papers.doc(id).update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> setPaperStage(LabPaper p, PaperStage to, {Map<String, dynamic> extra = const {}, String? note}) async {
    final batch = _db.batch();
    batch.update(papers.doc(p.id), {'stage': to.id, ...extra, 'updatedAt': FieldValue.serverTimestamp()});
    batch.update(studies.doc(p.studyId), {'paperStage': to.id});
    await batch.commit();
    await log('paper.stage', 'paper:${p.id}', {'from': p.stage.id, 'to': to.id, 'round': p.round, if (note != null) 'note': note});
  }

  /// Una etapa pidió cambios: vuelve a borrador con una ronda nueva.
  Future<void> returnToDraft(LabPaper p, String reason) => setPaperStage(p, PaperStage.borrador,
      extra: {'round': p.round + 1, 'checkOpensAt': null, 'checkClosesAt': null, 'checkExtended': false}, note: reason);

  CollectionReference<Map<String, dynamic>> reviews(String paperId) => papers.doc(paperId).collection('reviews');
  CollectionReference<Map<String, dynamic>> checks(String paperId) => papers.doc(paperId).collection('checks');

  static String reviewId(int round, String kind, String uid) => 'r${round}_${kind}_$uid';

  Future<void> addReview(LabPaper p, {required String kind, required ReviewDecision decision, required String comments}) async {
    final uid = _uid!;
    await reviews(p.id).doc(reviewId(p.round, kind, uid)).set({
      'uid': uid,
      'kind': kind, // interna | externa
      'round': p.round,
      'decision': decision.id,
      'comments': comments,
      'at': FieldValue.serverTimestamp(),
    });
    await log('paper.review', 'paper:${p.id}', {'kind': kind, 'decision': decision.id, 'round': p.round});
  }

  Stream<List<Map<String, dynamic>>> watchReviews(String paperId) =>
      reviews(paperId).snapshots().map((s) => [for (final d in s.docs) {...d.data(), 'id': d.id}]);

  Future<void> openMemberCheck(LabPaper p) => setPaperStage(p, PaperStage.validacionParticipantes, extra: {
        'checkOpensAt': FieldValue.serverTimestamp(),
        'checkClosesAt': Timestamp.fromDate(DateTime.now().add(kMemberCheckWindow)),
        'checkExtended': false,
      });

  Future<void> extendMemberCheck(LabPaper p) async {
    final base = p.checkClosesAt ?? DateTime.now();
    await papers.doc(p.id).update({'checkClosesAt': Timestamp.fromDate(base.add(kMemberCheckExtension)), 'checkExtended': true});
    await log('paper.check_extend', 'paper:${p.id}');
  }

  /// Voto del tester: el ID es su uid y la ronda, así que no puede votar dos veces.
  Future<void> vote(LabPaper p, MemberCheckVote v, String comment) async {
    final uid = _uid!;
    await checks(p.id).doc('r${p.round}_$uid').set({
      'uid': uid,
      'round': p.round,
      'vote': v.id,
      'comment': comment,
      'at': FieldValue.serverTimestamp(),
    });
  }

  Future<MemberCheckVote?> myVote(LabPaper p) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final d = await checks(p.id).doc('r${p.round}_$uid').get();
      return MemberCheckVoteX.parse(d.data()?['vote']);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> roundChecks(LabPaper p) async {
    final q = await checks(p.id).where('round', isEqualTo: p.round).get();
    return [for (final d in q.docs) d.data()];
  }

  /// Publica la nota del blog ligada al paper (solo admin; bloqueado si el proyecto es confidencial).
  Future<String> publishToBlog(LabPaper p, {required bool projectConfidential}) async {
    if (projectConfidential) throw StateError('El proyecto es confidencial: desclasifícalo antes de publicar.');
    if (p.stage != PaperStage.aprobado) throw StateError('El paper aún no está aprobado.');
    final post = _db.collection('lab_posts').doc();
    final slug = p.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñü]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final batch = _db.batch();
    batch.set(post, {
      'title': p.title,
      'slug': '$slug-${post.id.substring(0, 5).toLowerCase()}',
      'summary': p.abstract,
      'body': p.body,
      'paperId': p.id,
      'studyId': p.studyId,
      'status': 'published',
      'visibility': 'public',
      'authorUid': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'publishedAt': FieldValue.serverTimestamp(),
    });
    batch.update(papers.doc(p.id), {'stage': PaperStage.publicado.id, 'postId': post.id, 'updatedAt': FieldValue.serverTimestamp()});
    batch.update(studies.doc(p.studyId),
        {'status': StudyStatus.publicado.id, 'paperStage': PaperStage.publicado.id, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
    await log('paper.publish', 'paper:${p.id}', {'postId': post.id});
    return post.id;
  }

  // ───────────── Biblioteca de experimentos y encuestas ─────────────

  /// Integrados (con pantalla propia) + los creados por científicos que la persona puede ver.
  Stream<List<LabLibraryExperiment>> watchLibrary() => experiments.where('confidential', isEqualTo: false).snapshots().map((s) {
        final created = [for (final d in s.docs) LabLibraryExperiment.fromDoc(d.id, d.data())];
        final ids = created.map((e) => e.id).toSet();
        return [
          for (final e in kLabExperiments)
            if (!ids.contains(e.id))
              LabLibraryExperiment(id: e.id, title: e.title, description: e.description, metricNames: e.metrics.split(' · '), builtin: true),
          ...created,
        ];
      });

  /// Proyecto con el que se guarda un experimento o encuesta. Al crear es el que se eligió; al editar
  /// sin proyecto (p. ej. el botón Abrir/Cerrar) es el que ya tiene el documento. Antes se escribía
  /// `projectId: null` y `confidential: false` en cada edición: el recurso perdía su proyecto y, si
  /// era clasificado, dejaba de serlo.
  Future<LabProject?> _scopeFor(DocumentReference<Map<String, dynamic>> ref, String? id, LabProject? project) async {
    if (project != null || id == null) return project;
    final current = (await ref.get()).data() ?? const {};
    final pid = current['projectId'];
    if (pid is String && pid.isNotEmpty) {
      try {
        final p = await projects.doc(pid).get();
        if (p.exists) return LabProject.fromDoc(p.id, p.data()!);
      } catch (_) {}
    }
    if (current['confidential'] == true) {
      // Sin el proyecto no se puede enmascarar: mejor no guardar que exponer el texto real.
      throw StateError('No pudimos confirmar el proyecto clasificado de este recurso. Intenta de nuevo.');
    }
    return null;
  }

  Future<String> saveExperiment(String? id, Map<String, dynamic> data, {LabProject? project}) async {
    final ref = id == null ? experiments.doc() : experiments.doc(id);
    project = await _scopeFor(ref, id, project);
    final masked = project?.confidential ?? false;
    final batch = _db.batch();
    batch.set(ref, {
      ...data,
      if (masked) 'title': '${project!.codename} · Experimento',
      if (masked) 'description': 'Experimento clasificado.',
      if (masked) 'procedure': '',
      ...libraryScopeFields(isNew: id == null, project: project),
      if (id == null) 'ownerUid': _uid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (masked) {
      batch.set(details(ref), {'title': data['title'], 'description': data['description'], 'procedure': data['procedure']});
    }
    await batch.commit();
    await log(id == null ? 'experiment.create' : 'experiment.update', 'experiment:${ref.id}');
    return ref.id;
  }

  /// Documento de un experimento (null si no existe: p. ej. un integrado sin configuración propia).
  Stream<LabLibraryExperiment?> watchExperimentDoc(String id) =>
      experiments.doc(id).snapshots().map((d) => d.exists ? LabLibraryExperiment.fromDoc(d.id, d.data()!) : null);

  Stream<LabSurvey?> watchSurveyDoc(String id) => surveys.doc(id).snapshots().map((d) => d.exists ? LabSurvey.fromDoc(d.id, d.data()!) : null);

  Stream<LabFeature?> watchFeature(String key) => features.doc(key).snapshots().map((d) => d.exists ? LabFeature.fromDoc(d.id, d.data()!) : null);

  /// Compartir un experimento o encuesta con otros proyectos (solo propietario; nunca si es
  /// clasificado). [seed] crea el documento de un integrado que aún no lo tiene.
  Future<void> setShared(LabResourceKind kind, String id, bool shared, {String? projectId, Map<String, dynamic> seed = const {}}) async {
    final ref = _collectionOf(kind).doc(id);
    final exists = (await ref.get()).exists;
    await ref.set({
      if (!exists) ...seed,
      if (!exists && seed.isNotEmpty) 'ownerUid': _uid,
      'shared': shared,
    }, SetOptions(merge: true));
    await log(shared ? 'resource.share' : 'resource.unshare', '${kind.name}:$id', const {}, projectId);
  }

  /// Experimentos creados en un proyecto (incluidos los clasificados, para quien tenga acceso).
  Stream<List<LabLibraryExperiment>> watchProjectExperiments(String projectId) => experiments
      .where('projectId', isEqualTo: projectId)
      .snapshots()
      .map((s) => [for (final d in s.docs) LabLibraryExperiment.fromDoc(d.id, d.data())]);

  /// Encuestas de un proyecto.
  Stream<List<LabSurvey>> watchProjectSurveys(String projectId) => surveys
      .where('projectId', isEqualTo: projectId)
      .snapshots()
      .map((s) => [for (final d in s.docs) LabSurvey.fromDoc(d.id, d.data())]);

  /// Encuestas no clasificadas (las de proyectos confidenciales se abren por ID con [survey]).
  Stream<List<LabSurvey>> watchSurveys() => surveys
      .where('confidential', isEqualTo: false)
      .snapshots().map((s) => [for (final d in s.docs) LabSurvey.fromDoc(d.id, d.data())]);

  Future<String> saveSurvey(String? id, Map<String, dynamic> data, {LabProject? project}) async {
    final ref = id == null ? surveys.doc() : surveys.doc(id);
    project = await _scopeFor(ref, id, project);
    await ref.set({
      ...data,
      ...libraryScopeFields(isNew: id == null, project: project),
      if (id == null) 'ownerUid': _uid,
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await log(id == null ? 'survey.create' : 'survey.update', 'survey:${ref.id}');
    return ref.id;
  }

  Future<LabSurvey?> survey(String id) async {
    try {
      final d = await surveys.doc(id).get();
      return d.exists ? LabSurvey.fromDoc(d.id, d.data()!) : null;
    } catch (_) {
      return null;
    }
  }

  Future<LabPaper?> paper(String id) async {
    try {
      final d = await papers.doc(id).get();
      return d.exists ? LabPaper.fromDoc(d.id, d.data()!) : null;
    } catch (_) {
      return null;
    }
  }

  static String surveyResponseId(String surveyId, String uid) => '${surveyId}_$uid';

  Future<void> answerSurvey(LabSurvey s, Map<String, dynamic> answers, {String? studyId}) async {
    for (final q in s.questions) {
      if (!q.accepts(answers[q.id])) throw StateError('Revisa la pregunta: ${q.text}');
    }
    final uid = _uid!;
    await surveyResponses.doc(surveyResponseId(s.id, uid)).set({
      'surveyId': s.id,
      'studyId': studyId,
      'uid': uid,
      'answers': answers,
      'at': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> answeredSurvey(String surveyId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      return (await surveyResponses.doc(surveyResponseId(surveyId, uid)).get()).exists;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> surveyAnswers(String surveyId) async {
    final q = await surveyResponses.where('surveyId', isEqualTo: surveyId).get();
    return [for (final d in q.docs) (d.data()['answers'] as Map?)?.cast<String, dynamic>() ?? const {}];
  }
}
