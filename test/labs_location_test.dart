import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_access.dart';
import 'package:othli_front/labs/lab_catalog.dart';
import 'package:othli_front/labs/lab_experiments.dart';
import 'package:othli_front/labs/research/lab_models.dart' show kTtProjectId;
import 'package:othli_front/labs/shell/lab_location.dart';

String r(String? key, LabRole role, {String? last}) => LabLocation.resolve(key, role, lastProjectId: last).toKey();

void main() {
  test('clave de ida y vuelta', () {
    for (final k in [
      'p:trabajo_terminal/experiments/bateria_30/config.iam',
      'p:ohtli_plataforma/overview',
      'p:x/surveys/sus',
      'p:x/settings/audit',
      'participa',
      'exp:osrm',
    ]) {
      expect(LabLocation.parse(k)!.toKey(), k);
    }
    expect(LabLocation.parse('p:x')!.toKey(), 'p:x/overview');
    expect(LabLocation.parse('p:x/nada'), isNull);
    expect(LabLocation.parse(''), isNull);
    expect(LabLocation.parse('p:x/experiments/osrm/run')!.withoutTab.toKey(), 'p:x/experiments/osrm');
  });

  test('miembros: el menú anterior lleva a su lugar dentro de un proyecto', () {
    const m = LabRole.researcher;
    expect(r('exp:osrm', m), 'p:$kPlatformProjectId/experiments/osrm');
    expect(r('study:bateria_30', m), 'p:$kTtProjectId/experiments/bateria_30');
    expect(r('study:offline_ca05', m), 'p:$kTtProjectId/experiments/offline_ca05');
    expect(r('study:sus', m), 'p:$kTtProjectId/surveys/sus');
    expect(r('study:relevancia', m), 'p:$kTtProjectId/surveys/relevancia');
    expect(r('sma', m), 'p:$kPlatformProjectId/functionalities');
    expect(r('studies', m, last: 'abc'), 'p:abc/studies');
    expect(r('library', m), 'p:$kPlatformProjectId/experiments');
    expect(r('features', m), 'p:$kPlatformProjectId/functionalities');
    expect(r('audit', m, last: 'abc'), 'p:abc/settings/audit');
    expect(r(null, m), 'p:$kPlatformProjectId/overview');
    expect(r(null, m, last: 'abc'), 'p:abc/overview');
    expect(r('cualquier', m), 'p:$kPlatformProjectId/overview');
    expect(r('study:nada', m), 'p:$kPlatformProjectId/overview');
    for (final g in ['participa', 'encuestas', 'resultados', 'reviews', 'posts', 'projects']) {
      expect(r(g, m), g);
    }
    expect(r('members', m), 'p:$kPlatformProjectId/overview');
    expect(r('members', LabRole.admin), 'members');
  });

  test('testers: participación y experimentos por exp:, nunca proyectos', () {
    const t = LabRole.tester;
    expect(r(null, t), 'participa');
    for (final k in ['participa', 'encuestas', 'resultados']) {
      expect(r(k, t), k);
    }
    for (final e in kLabExperiments) {
      expect(r('exp:${e.id}', t), 'exp:${e.id}');
    }
    for (final k in ['p:$kTtProjectId/experiments/bateria_30', 'study:bateria_30', 'sma', 'posts', 'projects', 'members', 'exp:nada']) {
      expect(r(k, t), 'participa');
    }
  });

  test('revisor invitado: solo revisiones y resultados', () {
    const rv = LabRole.reviewer;
    expect(r(null, rv), 'reviews');
    expect(r('resultados', rv), 'resultados');
    expect(r('p:$kTtProjectId/overview', rv), 'reviews');
    expect(r('participa', rv), 'reviews');
  });
}
