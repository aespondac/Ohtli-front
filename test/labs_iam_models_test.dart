import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/research/lab_models.dart';

void main() {
  test('el IAM se lee de cada recurso', () {
    final iam = {'ana': 'owner', '*lab': 'viewer'};
    expect(LabProject.fromDoc('p', {'name': 'P', 'iam': iam}).iam, iam);
    expect(LabResearchStudy.fromDoc('s', {'projectId': 'p', 'iam': iam}).iam, iam);
    expect(LabLibraryExperiment.fromDoc('e', {'iam': iam}).iam, iam);
    expect(LabSurvey.fromDoc('q', {'iam': iam}).iam, iam);
    expect(LabFeature.fromDoc('f', {'iam': iam}).iam, iam);
    expect(LabProject.fromDoc('p', {'name': 'P'}).iam, isEmpty);
  });

  test('las funcionalidades sin proyecto son de la plataforma', () {
    expect(LabFeature.fromDoc('f', const {}).projectId, kPlatformProjectId);
    expect(LabFeature.fromDoc('f', const {'projectId': ''}).projectId, kPlatformProjectId);
    expect(LabFeature.fromDoc('f', const {'projectId': 'p1'}).projectId, 'p1');
  });

  test('un recurso clasificado nunca se lee como compartido', () {
    expect(LabLibraryExperiment.fromDoc('e', const {'shared': true}).shared, isTrue);
    expect(LabLibraryExperiment.fromDoc('e', const {'shared': true, 'confidential': true}).shared, isFalse);
    expect(LabSurvey.fromDoc('q', const {'shared': true, 'confidential': true}).shared, isFalse);
  });

  test('las pruebas del TT y relevancia/SUS se marcan como documentos heredados', () {
    for (final k in ['scenarios', 'load', 'checklist', 'relevance', 'sus']) {
      expect(LabResearchStudy.fromDoc('s', {'builtinKind': k}).legacyHolder, isTrue);
    }
    expect(LabResearchStudy.fromDoc('s', const {}).legacyHolder, isFalse);
  });
}
