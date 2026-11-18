import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_catalog.dart';
import 'package:othli_front/labs/lab_experiments.dart';
import 'package:othli_front/labs/lab_studies.dart';
import 'package:othli_front/labs/research/lab_models.dart' show LabProject, kTtProjectId;
import 'package:othli_front/labs/research/lab_research_repository.dart' show libraryScopeFields;

void main() {
  test('cada recurso integrado tiene un id único y un proyecto', () {
    final ids = [...kBuiltinExperiments.map((e) => e.id), ...kBuiltinSurveys.map((s) => s.id)];
    expect(ids.toSet(), hasLength(ids.length));
    expect(kBuiltinExperiments.every((e) => e.projectId.isNotEmpty), isTrue);
  });

  test('plataforma: los experimentos con pantalla propia', () {
    expect(builtinExperimentsOf(kPlatformProjectId).map((e) => e.id), kLabExperiments.map((e) => e.id));
    expect(builtinExperimentsOf(kPlatformProjectId).every((e) => e.page != null && e.runKey == null), isTrue);
  });

  test('Trabajo Terminal: pruebas como experimentos (con su historial) y relevancia y SUS como encuestas', () {
    expect(builtinExperimentsOf(kTtProjectId).map((e) => e.id), ['escenarios_formales', 'bateria_30', 'concurrencia', 'offline_ca05']);
    for (final e in builtinExperimentsOf(kTtProjectId)) {
      // Las corridas se guardan con el id de siempre: no se pierde el historial.
      expect(e.runKey, e.id);
      expect(studyById(e.runKey!), isNotNull);
    }
    expect(builtinSurveysOf(kTtProjectId).map((s) => s.id), ['relevancia', 'sus']);
    expect(builtinSurveyById('sus')!.study.kind, LabStudyKind.sus);
  });

  test('editar sin proyecto no borra el que ya tiene', () {
    final p = LabProject(id: 'p1', name: 'P', description: '', confidential: true, codename: 'Tecolotl', ownerUid: 'u', members: const []);
    expect(libraryScopeFields(isNew: true), {'projectId': null, 'confidential': false});
    expect(libraryScopeFields(isNew: true, project: p), {'projectId': 'p1', 'confidential': true});
    expect(libraryScopeFields(isNew: false), isEmpty);
    expect(libraryScopeFields(isNew: false, project: p), {'projectId': 'p1', 'confidential': true});
  });
}
