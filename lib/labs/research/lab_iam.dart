import '../lab_access.dart';

/// IAM de Ohtli Labs, al estilo de GCP: cada proyecto tiene un mapa `iam` {uid → rol} que heredan
/// sus estudios, experimentos, encuestas y funcionalidades; un recurso puede además dar acceso a
/// alguien en particular. Las concesiones solo suman: un rol en el recurso nunca quita lo que da el
/// proyecto. Las reglas de Firestore aplican lo mismo (firestore.rules: projAtLeast / resAtLeast).
enum LabIamRole { none, viewer, editor, owner }

/// Recursos con IAM propio. El de [project] lo heredan los demás.
enum LabResourceKind { project, study, experiment, survey, functionality }

/// Principal "todos los miembros del laboratorio" (científicos y admin), como un dominio en GCP.
const kLabAllMembers = '*lab';

extension LabIamRoleX on LabIamRole {
  int get rank => index;
  String get label => switch (this) {
        LabIamRole.owner => 'Propietario',
        LabIamRole.editor => 'Editor',
        LabIamRole.viewer => 'Lector',
        LabIamRole.none => 'Sin acceso',
      };
  String get description => switch (this) {
        LabIamRole.owner => 'Todo, incluido dar y quitar accesos y liberar resultados.',
        LabIamRole.editor => 'Crea y edita, ejecuta experimentos y cambia estados.',
        LabIamRole.viewer => 'Ve el contenido y los resultados, sin cambiarlos.',
        LabIamRole.none => '',
      };

  /// Valor que se guarda en Firestore (null para "sin acceso").
  String? get key => this == LabIamRole.none ? null : name;

  bool get canView => rank >= LabIamRole.viewer.rank;
  bool get canEdit => rank >= LabIamRole.editor.rank;
  bool get canManageIam => this == LabIamRole.owner;

  /// Liberar a testers. Liberar al público además exige al superusuario (como en las reglas).
  bool get canRelease => this == LabIamRole.owner;
}

LabIamRole parseIamRole(Object? v) => switch (v) {
      'owner' => LabIamRole.owner,
      'editor' => LabIamRole.editor,
      'viewer' => LabIamRole.viewer,
      _ => LabIamRole.none,
    };

LabIamRole _max(LabIamRole a, LabIamRole b) => a.rank >= b.rank ? a : b;

LabIamRole _grant(Map<String, dynamic>? iam, String? uid, LabRole labRole) {
  if (iam == null || iam.isEmpty) return LabIamRole.none;
  var r = uid == null ? LabIamRole.none : parseIamRole(iam[uid]);
  if (labRole.isMember) r = _max(r, parseIamRole(iam[kLabAllMembers]));
  return r;
}

/// Rol efectivo de una persona sobre un recurso.
///
/// [projectIam] es el IAM del proyecto (o del propio proyecto, si el recurso es el proyecto);
/// [resourceIam] el del recurso. Los campos `legacy*` son el modelo anterior (dueño, miembros del
/// proyecto, colaboradores del estudio) y cuentan mientras dure la migración.
LabIamRole effectiveIamRole({
  required String? uid,
  required LabRole labRole,
  Map<String, dynamic>? projectIam,
  Map<String, dynamic>? resourceIam,
  String? legacyOwner,
  List<String> legacyMembers = const [],
  List<String> legacyCollaborators = const [],
}) {
  if (labRole == LabRole.admin) return LabIamRole.owner;
  var r = _max(_grant(projectIam, uid, labRole), _grant(resourceIam, uid, labRole));
  if (uid != null) {
    if (legacyOwner == uid) r = _max(r, LabIamRole.owner);
    if (legacyMembers.contains(uid) || legacyCollaborators.contains(uid)) r = _max(r, LabIamRole.editor);
  }
  return r;
}

/// Revisa un cambio de IAM antes de guardarlo. Devuelve el motivo si no es válido.
String? validateIamChange(Map<String, dynamic> after, {bool requireOwner = true}) {
  for (final e in after.entries) {
    if (parseIamRole(e.value) == LabIamRole.none) return 'Rol no válido para ${e.key}.';
  }
  if (parseIamRole(after[kLabAllMembers]) == LabIamRole.owner) {
    return '"Todos los miembros del laboratorio" no puede ser propietario.';
  }
  if (requireOwner && !after.values.any((v) => parseIamRole(v) == LabIamRole.owner)) {
    return 'Debe quedar al menos un propietario.';
  }
  return null;
}

/// IAM inicial a partir del modelo anterior (para la migración): el dueño queda como propietario y
/// los miembros o colaboradores como editores. Lo que ya estaba en [current] se respeta.
Map<String, String> iamFromLegacy({
  Map<String, dynamic> current = const {},
  String? owner,
  List<String> editors = const [],
  bool labViewers = false,
}) {
  final out = <String, String>{};
  for (final u in editors) {
    if (u.isNotEmpty) out[u] = 'editor';
  }
  if (labViewers) out[kLabAllMembers] = 'viewer';
  if (owner != null && owner.isNotEmpty) out[owner] = 'owner';
  for (final e in current.entries) {
    final r = parseIamRole(e.value);
    if (r != LabIamRole.none) out[e.key] = r.name;
  }
  return out;
}
