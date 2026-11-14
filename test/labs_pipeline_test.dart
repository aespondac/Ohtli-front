import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_access.dart';
import 'package:othli_front/labs/lab_publishing.dart';

void main() {
  test('Visibilidad: valores nuevos y corridas anteriores a la pipeline', () {
    expect(LabVisibility.of({'visibility': 'testers'}), 'testers');
    expect(LabVisibility.of({'published': true}), 'public');
    expect(LabVisibility.of({}), 'private');
    expect(LabVisibility.of({'visibility': 'otra'}), 'private');
  });

  test('Roles: solo admin y researcher son miembros del laboratorio', () {
    expect(LabRole.admin.isMember, true);
    expect(LabRole.researcher.isMember, true);
    expect(LabRole.tester.isMember, false);
    expect(LabRole.tester.isTester, true);
    expect(LabRole.none.isTester, false);
  });

  test('Ruta del artículo', () {
    expect(slugify('Resultados de la batería: 30 escenarios (CA-01)'), 'resultados-de-la-bateria-30-escenarios-ca-01');
    expect(slugify('  Ñandú y Pingüino  '), 'nandu-y-pinguino');
  });
}
