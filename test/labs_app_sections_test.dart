import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_access.dart';
import 'package:othli_front/labs/lab_experiments.dart';
import 'package:othli_front/labs/lab_studies.dart';
import 'package:othli_front/labs/labs_app_page.dart';

void main() {
  final firstStudy = 'study:${kLabStudies.first.id}';

  test('sección de inicio según el rol', () {
    expect(LabsAppPage.validSection(null, LabRole.tester), 'participa');
    expect(LabsAppPage.validSection(null, LabRole.researcher), firstStudy);
    expect(LabsAppPage.validSection(null, LabRole.admin), firstStudy);
  });

  test('testers: participan, ven resultados y experimentos; no las pruebas ni la publicación', () {
    expect(LabsAppPage.validSection('participa', LabRole.tester), 'participa');
    expect(LabsAppPage.validSection('resultados', LabRole.tester), 'resultados');
    for (final e in kLabExperiments) {
      expect(LabsAppPage.validSection('exp:${e.id}', LabRole.tester), 'exp:${e.id}');
    }
    expect(LabsAppPage.validSection(firstStudy, LabRole.tester), 'participa');
    expect(LabsAppPage.validSection('posts', LabRole.tester), 'participa');
    expect(LabsAppPage.validSection('members', LabRole.tester), 'participa');
  });

  test('miembros: pruebas y publicación; Miembros solo administración', () {
    expect(LabsAppPage.validSection(firstStudy, LabRole.researcher), firstStudy);
    expect(LabsAppPage.validSection('posts', LabRole.researcher), 'posts');
    expect(LabsAppPage.validSection('members', LabRole.researcher), firstStudy);
    expect(LabsAppPage.validSection('members', LabRole.admin), 'members');
  });

  test('secciones inexistentes vuelven al inicio del rol', () {
    expect(LabsAppPage.validSection('exp:nada', LabRole.tester), 'participa');
    expect(LabsAppPage.validSection('study:nada', LabRole.admin), firstStudy);
    expect(LabsAppPage.validSection('cualquier', LabRole.tester), 'participa');
  });

  test('catálogo de experimentos con rutas /labs/<id> únicas', () {
    final ids = kLabExperiments.map((e) => e.id).toSet();
    expect(ids, hasLength(kLabExperiments.length));
    expect(kLabExperiments.map((e) => e.path), everyElement(startsWith('/labs/')));
  });
}
