import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_access.dart';
import 'package:othli_front/labs/lab_catalog.dart';
import 'package:othli_front/labs/lab_experiments.dart';
import 'package:othli_front/labs/labs_app_page.dart';

void main() {
  // Inicio de los miembros: el panel del último proyecto (sin uno, la plataforma), como en GCP.
  const home = 'p:$kPlatformProjectId/overview';
  String v(String? s, LabRole r, {String? last}) => LabsAppPage.validSection(s, r, lastProjectId: last);

  test('sección de inicio según el rol', () {
    expect(v(null, LabRole.tester), 'participa');
    expect(v(null, LabRole.researcher), home);
    expect(v(null, LabRole.admin), home);
    expect(v(null, LabRole.researcher, last: 'abc'), 'p:abc/overview');
    expect(v(null, LabRole.reviewer), 'reviews');
  });

  test('las secciones del menú anterior llevan a su lugar en un proyecto', () {
    expect(v('studies', LabRole.researcher), 'p:$kPlatformProjectId/studies');
    expect(v('library', LabRole.researcher, last: 'abc'), 'p:abc/experiments');
    expect(v('surveys', LabRole.researcher), 'p:$kPlatformProjectId/surveys');
    expect(v('features', LabRole.researcher), 'p:$kPlatformProjectId/functionalities');
    expect(v('audit', LabRole.researcher), 'p:$kPlatformProjectId/settings/audit');
    expect(v('sma', LabRole.researcher), 'p:$kPlatformProjectId/functionalities');
    expect(v('study:bateria_30', LabRole.researcher), 'p:$kTtProjectId/experiments/bateria_30');
    expect(v('study:sus', LabRole.researcher), 'p:$kTtProjectId/surveys/sus');
    expect(v('exp:osrm', LabRole.researcher), 'p:$kPlatformProjectId/experiments/osrm');
  });

  test('laboratorio solo para miembros; el revisor invitado solo ve sus revisiones', () {
    for (final s in ['projects', 'reviews', 'posts']) {
      expect(v(s, LabRole.researcher), s);
      expect(v(s, LabRole.tester), 'participa');
    }
    expect(v('p:$kTtProjectId/experiments', LabRole.tester), 'participa');
    expect(v('reviews', LabRole.reviewer), 'reviews');
    expect(v('studies', LabRole.reviewer), 'reviews');
    expect(v('participa', LabRole.reviewer), 'reviews');
    expect(v('encuestas', LabRole.reviewer), 'reviews');
  });

  test('testers: estudios y encuestas abiertos, resultados y experimentos', () {
    for (final s in ['participa', 'encuestas', 'resultados']) {
      expect(v(s, LabRole.tester), s);
      expect(v(s, LabRole.researcher), s);
    }
    for (final e in kLabExperiments) {
      expect(v('exp:${e.id}', LabRole.tester), 'exp:${e.id}');
    }
    for (final s in ['study:bateria_30', 'posts', 'members', 'sma', 'projects']) {
      expect(v(s, LabRole.tester), 'participa');
    }
  });

  test('Miembros del laboratorio solo para administración', () {
    expect(v('members', LabRole.researcher), home);
    expect(v('members', LabRole.admin), 'members');
  });

  test('secciones inexistentes vuelven al inicio del rol', () {
    expect(v('exp:nada', LabRole.tester), 'participa');
    expect(v('study:nada', LabRole.admin), home);
    expect(v('cualquier', LabRole.tester), 'participa');
    expect(v('p:x/nada', LabRole.researcher), home);
  });

  test('catálogo de experimentos con rutas /labs/<id> únicas', () {
    final ids = kLabExperiments.map((e) => e.id).toSet();
    expect(ids, hasLength(kLabExperiments.length));
    expect(kLabExperiments.map((e) => e.path), everyElement(startsWith('/labs/')));
  });
}
