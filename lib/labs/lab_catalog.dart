import 'lab_experiments.dart';
import 'lab_studies.dart';
import 'research/lab_models.dart' show kTtProjectId;

/// Recursos integrados de Ohtli Labs, ordenados por proyecto (el código es la fuente de verdad, como
/// ya hacía `watchLibrary` con los experimentos integrados).
///
///  - Ohtli.quest (plataforma): los experimentos con pantalla propia y las funcionalidades del SMA.
///  - Trabajo Terminal: las pruebas del capítulo 6 como experimentos (miden partes del sistema) y
///    las de relevancia y SUS como encuestas.
///
/// Los documentos `lab_studies/{id}` de las pruebas del TT se conservan tal cual: las corridas
/// (`lab_runs.studyId`) y las reglas de `lab_responses` los usan. Por eso cada experimento del TT
/// guarda su [LabBuiltinExperiment.runKey], que es el id de siempre.
const kPlatformProjectId = 'ohtli_plataforma';
const kPlatformProjectName = 'Ohtli.quest (plataforma)';
const kTtProjectName = 'Trabajo Terminal';

class LabBuiltinExperiment {
  final String id;
  final String projectId;
  final String title;
  final String description;

  /// Experimento con pantalla propia (lib/screens/lab/experiments).
  final LabExperiment? page;

  /// Prueba del TT que se ejecuta con su runner (escenarios, carga o lista de verificación).
  final LabStudy? ttRunner;

  const LabBuiltinExperiment({
    required this.id,
    required this.projectId,
    required this.title,
    required this.description,
    this.page,
    this.ttRunner,
  });

  /// Clave de sus corridas en `lab_runs.studyId` (solo las pruebas del TT guardan corridas).
  String? get runKey => ttRunner?.id;
}

class LabBuiltinSurvey {
  final String id;
  final String projectId;
  final LabStudy study;
  const LabBuiltinSurvey({required this.id, required this.projectId, required this.study});
  String get title => study.title;
}

const _ttExperimentKinds = {LabStudyKind.scenarios, LabStudyKind.load, LabStudyKind.checklist};
const _ttSurveyKinds = {LabStudyKind.relevance, LabStudyKind.sus};

final List<LabBuiltinExperiment> kBuiltinExperiments = [
  for (final e in kLabExperiments)
    LabBuiltinExperiment(id: e.id, projectId: kPlatformProjectId, title: e.title, description: e.description, page: e),
  for (final s in kLabStudies)
    if (_ttExperimentKinds.contains(s.kind))
      LabBuiltinExperiment(id: s.id, projectId: kTtProjectId, title: s.title, description: s.description, ttRunner: s),
];

final List<LabBuiltinSurvey> kBuiltinSurveys = [
  for (final s in kLabStudies)
    if (_ttSurveyKinds.contains(s.kind)) LabBuiltinSurvey(id: s.id, projectId: kTtProjectId, study: s),
];

LabBuiltinExperiment? builtinExperimentById(String id) {
  for (final e in kBuiltinExperiments) {
    if (e.id == id) return e;
  }
  return null;
}

LabBuiltinSurvey? builtinSurveyById(String id) {
  for (final s in kBuiltinSurveys) {
    if (s.id == id) return s;
  }
  return null;
}

List<LabBuiltinExperiment> builtinExperimentsOf(String projectId) =>
    [for (final e in kBuiltinExperiments) if (e.projectId == projectId) e];

List<LabBuiltinSurvey> builtinSurveysOf(String projectId) => [for (final s in kBuiltinSurveys) if (s.projectId == projectId) s];
