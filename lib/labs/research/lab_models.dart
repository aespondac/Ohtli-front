/// Modelos de la estructura de investigación de Ohtli Labs (ver docs/labs_estructura.md).
///
/// Proyecto → Estudio → {experimentos, encuestas, métricas, funcionalidades} → paper → blog.
/// Aquí vive también la lógica pura (transiciones, validación de participantes, dictámenes) para
/// poder probarla sin Firestore.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
List<String> _strings(dynamic v) => [for (final x in (v as List?) ?? const []) x.toString()];

// ───────────────────────────── Proyecto ─────────────────────────────

class LabProject {
  final String id;
  final String name; // nombre visible: el real o "Proyecto <Codename>"
  final String description;
  final bool confidential;
  final String? codename;
  final List<String> members; // uids con acceso a lo clasificado
  final String ownerUid;
  final DateTime? declassifiedAt;
  final DateTime? createdAt;

  const LabProject({
    required this.id,
    required this.name,
    this.description = '',
    this.confidential = false,
    this.codename,
    this.members = const [],
    this.ownerUid = '',
    this.declassifiedAt,
    this.createdAt,
  });

  factory LabProject.fromDoc(String id, Map<String, dynamic> d) => LabProject(
        id: id,
        name: (d['name'] ?? '').toString(),
        description: (d['description'] ?? '').toString(),
        confidential: d['confidential'] == true,
        codename: d['codename'] as String?,
        members: _strings(d['members']),
        ownerUid: (d['ownerUid'] ?? '').toString(),
        declassifiedAt: _date(d['declassifiedAt']),
        createdAt: _date(d['createdAt']),
      );

  bool canSeeSecret(String? uid, {bool admin = false}) => !confidential || admin || (uid != null && members.contains(uid));
}

/// Proyecto público al que pertenecen las pruebas del Trabajo Terminal.
const kTtProjectId = 'trabajo_terminal';

// ───────────────────────────── Estudio ─────────────────────────────

enum StudyStatus { borrador, preregistrado, reclutando, enCurso, analisis, enRevision, publicado, archivado, pausado, cancelado }

extension StudyStatusX on StudyStatus {
  String get id => switch (this) {
        StudyStatus.enCurso => 'en_curso',
        StudyStatus.enRevision => 'en_revision',
        _ => name,
      };
  String get label => switch (this) {
        StudyStatus.borrador => 'Borrador',
        StudyStatus.preregistrado => 'Preregistrado',
        StudyStatus.reclutando => 'Reclutando',
        StudyStatus.enCurso => 'En curso',
        StudyStatus.analisis => 'Análisis',
        StudyStatus.enRevision => 'En revisión',
        StudyStatus.publicado => 'Publicado',
        StudyStatus.archivado => 'Archivado',
        StudyStatus.pausado => 'Pausado',
        StudyStatus.cancelado => 'Cancelado',
      };

  /// Las funciones del estudio están en beta para los inscritos.
  bool get featuresLive => this == StudyStatus.enCurso;
  bool get acceptsEnrollment => this == StudyStatus.reclutando || this == StudyStatus.enCurso;
  bool get preregFrozen => index >= StudyStatus.preregistrado.index && this != StudyStatus.cancelado;

  static StudyStatus parse(dynamic v) {
    for (final s in StudyStatus.values) {
      if (s.id == v) return s;
    }
    return StudyStatus.borrador;
  }
}

/// Avance permitido de un estado (el camino principal) y las salidas laterales.
const Map<StudyStatus, List<StudyStatus>> kStudyTransitions = {
  StudyStatus.borrador: [StudyStatus.preregistrado, StudyStatus.cancelado],
  StudyStatus.preregistrado: [StudyStatus.reclutando, StudyStatus.cancelado],
  StudyStatus.reclutando: [StudyStatus.enCurso, StudyStatus.pausado, StudyStatus.cancelado],
  StudyStatus.enCurso: [StudyStatus.analisis, StudyStatus.pausado, StudyStatus.cancelado],
  StudyStatus.analisis: [StudyStatus.enRevision, StudyStatus.cancelado],
  StudyStatus.enRevision: [StudyStatus.publicado, StudyStatus.analisis],
  StudyStatus.publicado: [StudyStatus.archivado],
  StudyStatus.pausado: [StudyStatus.reclutando, StudyStatus.enCurso, StudyStatus.cancelado],
  StudyStatus.archivado: [],
  StudyStatus.cancelado: [],
};

bool canTransition(StudyStatus from, StudyStatus to) => kStudyTransitions[from]?.contains(to) ?? false;

/// Una métrica preregistrada: qué se mide, cómo y cuándo se considera éxito.
class LabMetric {
  final String id;
  final String name;
  final String formula;
  final String unit;
  final String successThreshold; // p. ej. "≥ 68" o "p < 0.05"
  const LabMetric({required this.id, required this.name, this.formula = '', this.unit = '', this.successThreshold = ''});

  factory LabMetric.fromMap(Map<String, dynamic> m) => LabMetric(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        formula: (m['formula'] ?? '').toString(),
        unit: (m['unit'] ?? '').toString(),
        successThreshold: (m['successThreshold'] ?? '').toString(),
      );
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'formula': formula, 'unit': unit, 'successThreshold': successThreshold};
}

class StudyConfig {
  final bool externalReview;
  final int minExternalReviewers;
  final bool participantValidation;
  final int capacity; // 0 = sin límite
  final String eligibility;
  const StudyConfig({
    this.externalReview = false,
    this.minExternalReviewers = 2,
    this.participantValidation = true,
    this.capacity = 0,
    this.eligibility = '',
  });
  factory StudyConfig.fromMap(Map<String, dynamic>? m) => StudyConfig(
        externalReview: m?['externalReview'] == true,
        minExternalReviewers: (m?['minExternalReviewers'] as num?)?.toInt() ?? 2,
        participantValidation: m?['participantValidation'] != false,
        capacity: (m?['capacity'] as num?)?.toInt() ?? 0,
        eligibility: (m?['eligibility'] ?? '').toString(),
      );
  Map<String, dynamic> toMap() => {
        'externalReview': externalReview,
        'minExternalReviewers': minExternalReviewers,
        'participantValidation': participantValidation,
        'capacity': capacity,
        'eligibility': eligibility,
      };
}

class LabResearchStudy {
  final String id;
  final String projectId;
  final String title;
  final String description;
  final StudyStatus status;
  final bool confidential;
  final String ownerUid;
  final List<String> collaborators;
  final String hypotheses;
  final String analysisPlan;
  final List<LabMetric> metrics;
  final DateTime? frozenAt;
  final int amendments;
  final StudyConfig config;
  final List<String> experimentIds;
  final List<String> surveyIds;
  final List<String> featureKeys;
  final int consentVersion;
  final String consentText;
  final int enrolledCount;
  final String? builtinKind; // pruebas del TT con su propio panel
  final String? currentPaperId;
  final PaperStage? paperStage;
  final DateTime? updatedAt;

  const LabResearchStudy({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.status = StudyStatus.borrador,
    this.confidential = false,
    this.ownerUid = '',
    this.collaborators = const [],
    this.hypotheses = '',
    this.analysisPlan = '',
    this.metrics = const [],
    this.frozenAt,
    this.amendments = 0,
    this.config = const StudyConfig(),
    this.experimentIds = const [],
    this.surveyIds = const [],
    this.featureKeys = const [],
    this.consentVersion = 1,
    this.consentText = '',
    this.enrolledCount = 0,
    this.builtinKind,
    this.currentPaperId,
    this.paperStage,
    this.updatedAt,
  });

  factory LabResearchStudy.fromDoc(String id, Map<String, dynamic> d) {
    final prereg = (d['preregistration'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LabResearchStudy(
      id: id,
      projectId: (d['projectId'] ?? kTtProjectId).toString(),
      title: (d['title'] ?? id).toString(),
      description: (d['description'] ?? '').toString(),
      status: StudyStatusX.parse(d['status']),
      confidential: d['confidential'] == true,
      ownerUid: (d['ownerUid'] ?? '').toString(),
      collaborators: _strings(d['collaborators']),
      hypotheses: (prereg['hypotheses'] ?? '').toString(),
      analysisPlan: (prereg['analysisPlan'] ?? '').toString(),
      metrics: [for (final m in (prereg['metrics'] as List?) ?? const []) LabMetric.fromMap((m as Map).cast<String, dynamic>())],
      frozenAt: _date(prereg['frozenAt']),
      amendments: (prereg['amendments'] as num?)?.toInt() ?? 0,
      config: StudyConfig.fromMap((d['config'] as Map?)?.cast<String, dynamic>()),
      experimentIds: _strings(d['experimentIds']),
      surveyIds: _strings(d['surveyIds']),
      featureKeys: _strings(d['featureKeys']),
      consentVersion: (d['consentVersion'] as num?)?.toInt() ?? 1,
      consentText: (d['consentText'] ?? '').toString(),
      enrolledCount: (d['enrolledCount'] as num?)?.toInt() ?? 0,
      builtinKind: d['builtinKind'] as String?,
      currentPaperId: d['currentPaperId'] as String?,
      paperStage: d['paperStage'] == null ? null : PaperStageX.parse(d['paperStage']),
      updatedAt: _date(d['updatedAt']),
    );
  }

  bool get isFull => config.capacity > 0 && enrolledCount >= config.capacity;
  bool canEdit(String? uid, {bool admin = false}) => admin || (uid != null && (uid == ownerUid || collaborators.contains(uid)));
}

// ───────────────────────────── Funcionalidad ─────────────────────────────

enum FeatureStage { desarrollo, beta, oficial, retirada }

extension FeatureStageX on FeatureStage {
  String get label => switch (this) {
        FeatureStage.desarrollo => 'En desarrollo',
        FeatureStage.beta => 'Beta para testers',
        FeatureStage.oficial => 'Oficial',
        FeatureStage.retirada => 'Retirada',
      };
  static FeatureStage parse(dynamic v) =>
      FeatureStage.values.firstWhere((s) => s.name == v, orElse: () => FeatureStage.desarrollo);
}

class LabFeature {
  final String key; // el mismo que usa el código: FeatureGate(key: ...)
  final String name;
  final String description;
  final FeatureStage stage;
  final List<String> studyIds;
  final bool confidential;
  final String? howToTry; // dónde encontrarla en la app
  const LabFeature({
    required this.key,
    required this.name,
    this.description = '',
    this.stage = FeatureStage.desarrollo,
    this.studyIds = const [],
    this.confidential = false,
    this.howToTry,
  });
  factory LabFeature.fromDoc(String id, Map<String, dynamic> d) => LabFeature(
        key: id,
        name: (d['name'] ?? id).toString(),
        description: (d['description'] ?? '').toString(),
        stage: FeatureStageX.parse(d['stage']),
        studyIds: _strings(d['studyIds']),
        confidential: d['confidential'] == true,
        howToTry: d['howToTry'] as String?,
      );
}

/// ¿Ve la persona la función? Laboratorio siempre; testers si está en beta y están inscritos a
/// alguno de sus estudios en curso; todos si es oficial.
bool featureVisible({
  required LabFeature feature,
  required bool isLabMember,
  required Set<String> enrolledStudyIds,
  required Set<String> liveStudyIds,
}) {
  switch (feature.stage) {
    case FeatureStage.oficial:
      return true;
    case FeatureStage.retirada:
      return false;
    case FeatureStage.desarrollo:
      return isLabMember;
    case FeatureStage.beta:
      if (isLabMember) return true;
      return feature.studyIds.any((s) => enrolledStudyIds.contains(s) && liveStudyIds.contains(s));
  }
}

// ───────────────────────────── Paper y validación ─────────────────────────────

enum PaperStage { borrador, revisionInterna, revisionExterna, validacionParticipantes, aprobado, publicado }

extension PaperStageX on PaperStage {
  String get id => switch (this) {
        PaperStage.revisionInterna => 'revision_interna',
        PaperStage.revisionExterna => 'revision_externa',
        PaperStage.validacionParticipantes => 'validacion_participantes',
        _ => name,
      };
  String get label => switch (this) {
        PaperStage.borrador => 'Borrador',
        PaperStage.revisionInterna => 'Revisión interna',
        PaperStage.revisionExterna => 'Revisión externa',
        PaperStage.validacionParticipantes => 'Validación de participantes',
        PaperStage.aprobado => 'Aprobado',
        PaperStage.publicado => 'Publicado',
      };
  static PaperStage parse(dynamic v) => PaperStage.values.firstWhere((s) => s.id == v, orElse: () => PaperStage.borrador);
}

/// Etapas que recorre el paper según la configuración del estudio.
List<PaperStage> paperPipeline(StudyConfig c) => [
      PaperStage.borrador,
      PaperStage.revisionInterna,
      if (c.externalReview) PaperStage.revisionExterna,
      if (c.participantValidation) PaperStage.validacionParticipantes,
      PaperStage.aprobado,
      PaperStage.publicado,
    ];

PaperStage? nextPaperStage(PaperStage current, StudyConfig c) {
  final p = paperPipeline(c);
  final i = p.indexOf(current);
  return (i < 0 || i + 1 >= p.length) ? null : p[i + 1];
}

enum ReviewDecision { aceptar, cambiosMenores, cambiosMayores, rechazar }

extension ReviewDecisionX on ReviewDecision {
  String get id => switch (this) {
        ReviewDecision.cambiosMenores => 'cambios_menores',
        ReviewDecision.cambiosMayores => 'cambios_mayores',
        _ => name,
      };
  String get label => switch (this) {
        ReviewDecision.aceptar => 'Aceptar',
        ReviewDecision.cambiosMenores => 'Cambios menores',
        ReviewDecision.cambiosMayores => 'Cambios mayores',
        ReviewDecision.rechazar => 'Rechazar',
      };
  static ReviewDecision parse(dynamic v) =>
      ReviewDecision.values.firstWhere((s) => s.id == v, orElse: () => ReviewDecision.cambiosMayores);
}

enum ReviewOutcome { pendiente, avanza, regresa }

/// Resultado de una etapa de revisión: avanza con al menos [minReviews] dictámenes, ninguno
/// "rechazar" ni "cambios mayores"; regresa a borrador si alguno lo pide.
ReviewOutcome reviewOutcome(List<ReviewDecision> decisions, {int minReviews = 1}) {
  if (decisions.any((d) => d == ReviewDecision.rechazar || d == ReviewDecision.cambiosMayores)) return ReviewOutcome.regresa;
  if (decisions.length < minReviews) return ReviewOutcome.pendiente;
  return ReviewOutcome.avanza;
}

enum MemberCheckVote { si, enParte, no }

extension MemberCheckVoteX on MemberCheckVote {
  String get id => switch (this) { MemberCheckVote.enParte => 'en_parte', _ => name };
  String get label => switch (this) { MemberCheckVote.si => 'Sí', MemberCheckVote.enParte => 'En parte', MemberCheckVote.no => 'No' };
  static MemberCheckVote? parse(dynamic v) {
    for (final x in MemberCheckVote.values) {
      if (x.id == v) return x;
    }
    return null;
  }
}

class MemberCheckResult {
  final int votes;
  final int quorum;
  final double support; // (sí + 0.5·en parte) / votos
  final double rejection; // no / votos
  final bool quorumMet;
  final bool approved;
  const MemberCheckResult(this.votes, this.quorum, this.support, this.rejection, this.quorumMet, this.approved);
}

/// Quórum de la validación de participantes: max(3, 30 % de los inscritos), sin pasar de ellos.
int memberCheckQuorum(int enrolled) {
  final q = (enrolled * 0.3).ceil();
  final base = q < 3 ? 3 : q;
  return enrolled > 0 && base > enrolled ? enrolled : base;
}

/// Se aprueba con quórum, apoyo ≥ 2/3 y "no" < 1/3 (docs/labs_estructura.md).
MemberCheckResult memberCheck(List<MemberCheckVote> votes, int enrolled) {
  final n = votes.length;
  final si = votes.where((v) => v == MemberCheckVote.si).length;
  final parte = votes.where((v) => v == MemberCheckVote.enParte).length;
  final no = votes.where((v) => v == MemberCheckVote.no).length;
  final quorum = memberCheckQuorum(enrolled);
  final support = n == 0 ? 0.0 : (si + 0.5 * parte) / n;
  final rejection = n == 0 ? 0.0 : no / n;
  final quorumMet = n >= quorum && n > 0;
  return MemberCheckResult(n, quorum, support, rejection, quorumMet, quorumMet && support >= 2 / 3 - 1e-9 && rejection < 1 / 3);
}

/// Ventana de la validación de participantes y su única prórroga.
const kMemberCheckWindow = Duration(days: 10);
const kMemberCheckExtension = Duration(days: 7);

class LabPaper {
  final String id;
  final String studyId;
  final String title;
  final String abstract;
  final String body;
  final PaperStage stage;
  final int round;
  final List<String> authors;
  final Map<String, dynamic> reproducibility;
  final DateTime? checkOpensAt;
  final DateTime? checkClosesAt;
  final bool checkExtended;
  final String? postId;
  final DateTime? updatedAt;

  const LabPaper({
    required this.id,
    required this.studyId,
    required this.title,
    this.abstract = '',
    this.body = '',
    this.stage = PaperStage.borrador,
    this.round = 1,
    this.authors = const [],
    this.reproducibility = const {},
    this.checkOpensAt,
    this.checkClosesAt,
    this.checkExtended = false,
    this.postId,
    this.updatedAt,
  });

  factory LabPaper.fromDoc(String id, Map<String, dynamic> d) => LabPaper(
        id: id,
        studyId: (d['studyId'] ?? '').toString(),
        title: (d['title'] ?? '').toString(),
        abstract: (d['abstract'] ?? '').toString(),
        body: (d['body'] ?? '').toString(),
        stage: PaperStageX.parse(d['stage']),
        round: (d['round'] as num?)?.toInt() ?? 1,
        authors: _strings(d['authors']),
        reproducibility: (d['reproducibility'] as Map?)?.cast<String, dynamic>() ?? const {},
        checkOpensAt: _date(d['checkOpensAt']),
        checkClosesAt: _date(d['checkClosesAt']),
        checkExtended: d['checkExtended'] == true,
        postId: d['postId'] as String?,
        updatedAt: _date(d['updatedAt']),
      );
}

// ───────────────────────────── Experimentos y encuestas ─────────────────────────────

class LabLibraryExperiment {
  final String id;
  final String title;
  final String description;
  final String procedure;
  final List<String> metricNames;
  final bool builtin;
  final bool confidential;
  final String? projectId;
  final String ownerUid;
  const LabLibraryExperiment({
    required this.id,
    required this.title,
    this.description = '',
    this.procedure = '',
    this.metricNames = const [],
    this.builtin = false,
    this.confidential = false,
    this.projectId,
    this.ownerUid = '',
  });
  factory LabLibraryExperiment.fromDoc(String id, Map<String, dynamic> d) => LabLibraryExperiment(
        id: id,
        title: (d['title'] ?? id).toString(),
        description: (d['description'] ?? '').toString(),
        procedure: (d['procedure'] ?? '').toString(),
        metricNames: _strings(d['metricNames']),
        builtin: d['builtin'] == true,
        confidential: d['confidential'] == true,
        projectId: d['projectId'] as String?,
        ownerUid: (d['ownerUid'] ?? '').toString(),
      );
}

enum SurveyQuestionType { likert5, single, multi, number, text }

class SurveyQuestion {
  final String id;
  final SurveyQuestionType type;
  final String text;
  final List<String> options;
  final bool required;
  const SurveyQuestion({required this.id, required this.type, required this.text, this.options = const [], this.required = true});
  factory SurveyQuestion.fromMap(Map<String, dynamic> m) => SurveyQuestion(
        id: (m['id'] ?? '').toString(),
        type: SurveyQuestionType.values.firstWhere((t) => t.name == m['type'], orElse: () => SurveyQuestionType.text),
        text: (m['text'] ?? '').toString(),
        options: _strings(m['options']),
        required: m['required'] != false,
      );
  Map<String, dynamic> toMap() => {'id': id, 'type': type.name, 'text': text, 'options': options, 'required': required};

  /// ¿La respuesta es válida para esta pregunta?
  bool accepts(dynamic v) {
    if (v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty)) return !required;
    return switch (type) {
      SurveyQuestionType.likert5 => v is int && v >= 1 && v <= 5,
      SurveyQuestionType.single => v is String && options.contains(v),
      SurveyQuestionType.multi => v is List && v.every(options.contains),
      SurveyQuestionType.number => v is num,
      SurveyQuestionType.text => v is String && v.length <= 1000,
    };
  }
}

class LabSurvey {
  final String id;
  final String title;
  final String description;
  final List<SurveyQuestion> questions;
  final bool open;
  final bool confidential;
  final String? projectId;
  final String ownerUid;
  const LabSurvey({
    required this.id,
    required this.title,
    this.description = '',
    this.questions = const [],
    this.open = false,
    this.confidential = false,
    this.projectId,
    this.ownerUid = '',
  });
  factory LabSurvey.fromDoc(String id, Map<String, dynamic> d) => LabSurvey(
        id: id,
        title: (d['title'] ?? id).toString(),
        description: (d['description'] ?? '').toString(),
        questions: [for (final q in (d['questions'] as List?) ?? const []) SurveyQuestion.fromMap((q as Map).cast<String, dynamic>())],
        open: d['open'] == true,
        confidential: d['confidential'] == true,
        projectId: d['projectId'] as String?,
        ownerUid: (d['ownerUid'] ?? '').toString(),
      );
}
