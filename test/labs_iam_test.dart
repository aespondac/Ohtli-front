import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_access.dart';
import 'package:othli_front/labs/research/lab_iam.dart';

void main() {
  LabIamRole eff(String? uid, LabRole lr, {Map<String, dynamic>? p, Map<String, dynamic>? res, String? owner, List<String> m = const [], List<String> c = const []}) =>
      effectiveIamRole(uid: uid, labRole: lr, projectIam: p, resourceIam: res, legacyOwner: owner, legacyMembers: m, legacyCollaborators: c);

  test('el admin siempre es propietario', () {
    expect(eff('x', LabRole.admin), LabIamRole.owner);
  });

  test('se hereda del proyecto y el recurso solo suma', () {
    const r = LabRole.researcher;
    expect(eff('ana', r, p: {'ana': 'viewer'}), LabIamRole.viewer);
    expect(eff('ana', r, p: {'ana': 'viewer'}, res: {'ana': 'editor'}), LabIamRole.editor);
    expect(eff('ana', r, p: {'ana': 'owner'}, res: {'ana': 'viewer'}), LabIamRole.owner);
    expect(eff('ana', r, res: {'ana': 'editor'}), LabIamRole.editor);
    expect(eff('ana', r), LabIamRole.none);
  });

  test('"todos los miembros" solo aplica a miembros del laboratorio', () {
    final p = {kLabAllMembers: 'editor'};
    expect(eff('ana', LabRole.researcher, p: p), LabIamRole.editor);
    expect(eff('tes', LabRole.tester, p: p), LabIamRole.none);
    expect(eff(null, LabRole.researcher, p: p), LabIamRole.editor);
  });

  test('campos del modelo anterior cuentan durante la migración', () {
    const r = LabRole.researcher;
    expect(eff('ana', r, owner: 'ana'), LabIamRole.owner);
    expect(eff('ana', r, m: ['ana']), LabIamRole.editor);
    expect(eff('ana', r, c: ['ana'], p: {'ana': 'viewer'}), LabIamRole.editor);
  });

  test('permisos por rol', () {
    expect(LabIamRole.viewer.canView && !LabIamRole.viewer.canEdit, isTrue);
    expect(LabIamRole.editor.canEdit && !LabIamRole.editor.canManageIam, isTrue);
    expect(LabIamRole.owner.canManageIam && LabIamRole.owner.canRelease, isTrue);
    expect(LabIamRole.none.canView, isFalse);
  });

  test('validar cambios de IAM', () {
    expect(validateIamChange({'ana': 'owner', kLabAllMembers: 'viewer'}), isNull);
    expect(validateIamChange({'ana': 'editor'}), contains('propietario'));
    expect(validateIamChange({'ana': 'editor'}, requireOwner: false), isNull);
    expect(validateIamChange({'ana': 'owner', kLabAllMembers: 'owner'}), contains('Todos los miembros'));
    expect(validateIamChange({'ana': 'owner', 'beto': 'jefe'}), contains('beto'));
  });

  test('IAM desde el modelo anterior respeta lo ya asignado', () {
    expect(iamFromLegacy(owner: 'ana', editors: ['beto', 'ana'], labViewers: true),
        {'ana': 'owner', 'beto': 'editor', kLabAllMembers: 'viewer'});
    expect(iamFromLegacy(current: {'beto': 'viewer'}, owner: 'ana', editors: ['beto']), {'ana': 'owner', 'beto': 'viewer'});
  });
}
