import '../lab_access.dart';
import '../lab_catalog.dart';
import '../lab_experiments.dart';

/// Dónde está la persona dentro de Ohtli Labs, al estilo de la consola de GCP: un proyecto elegido
/// arriba y, dentro, sus áreas (estudios, experimentos, encuestas, funcionalidades, configuración).
///
/// Clave de texto (la que se guarda en la URL y en el menú):
///   `p:<proyecto>/<área>[/<recurso>[/<pestaña>]]`, p. ej. `p:trabajo_terminal/experiments/bateria_30/config.iam`
/// Las secciones fuera de un proyecto conservan su clave de siempre (participa, encuestas, …) y los
/// testers siguen abriendo los experimentos con `exp:<id>`.
enum LabArea { overview, studies, experiments, surveys, functionalities, settings }

extension LabAreaX on LabArea {
  String get label => switch (this) {
        LabArea.overview => 'Panel',
        LabArea.studies => 'Estudios',
        LabArea.experiments => 'Experimentos',
        LabArea.surveys => 'Encuestas',
        LabArea.functionalities => 'Funcionalidades',
        LabArea.settings => 'Configuración',
      };
}

LabArea? _areaOf(String s) {
  for (final a in LabArea.values) {
    if (a.name == s) return a;
  }
  return null;
}

/// Secciones de laboratorio fuera de un proyecto.
const kLabGlobalSections = {'participa', 'encuestas', 'resultados', 'reviews', 'posts', 'members', 'projects'};

/// Secciones de participación: las ven todos los roles con acceso a Labs.
const _participantSections = {'participa', 'encuestas', 'resultados'};

class LabLocation {
  /// Sección global (participa, posts, …) o `exp:<id>` de tester. Null si está dentro de un proyecto.
  final String? global;
  final String? projectId;
  final LabArea? area;
  final String? resourceId;
  final String? tab;

  const LabLocation.global(String this.global)
      : projectId = null,
        area = null,
        resourceId = null,
        tab = null;

  const LabLocation.project(String this.projectId, LabArea this.area, {this.resourceId, this.tab}) : global = null;

  bool get inProject => projectId != null;

  /// Misma ubicación sin la pestaña (para conservar viva la vista al cambiar de pestaña).
  LabLocation get withoutTab =>
      inProject ? LabLocation.project(projectId!, area!, resourceId: resourceId) : this;

  String toKey() {
    if (!inProject) return global!;
    final parts = ['p:$projectId', area!.name, ?resourceId, if (resourceId != null) ?tab];
    return parts.join('/');
  }

  /// Interpreta una clave. Devuelve null si no tiene la forma esperada (no valida permisos).
  static LabLocation? parse(String? key) {
    if (key == null || key.isEmpty) return null;
    if (!key.startsWith('p:')) return LabLocation.global(key);
    final parts = key.substring(2).split('/');
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final area = parts.length > 1 ? _areaOf(parts[1]) : LabArea.overview;
    if (area == null) return null;
    final res = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
    final tab = res != null && parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
    return LabLocation.project(parts.first, area, resourceId: res, tab: tab);
  }

  /// Ubicación válida para el rol a partir de cualquier clave, incluidas las del menú anterior
  /// (`exp:`, `study:`, `sma`, `studies`, `library`, …). [lastProjectId] es el último proyecto
  /// elegido; sin él, el de la plataforma. Si el proyecto existe y la persona tiene acceso se
  /// comprueba después, cuando cargan los proyectos.
  static LabLocation resolve(String? key, LabRole role, {String? lastProjectId}) {
    final home = lastProjectId ?? kPlatformProjectId;
    if (role.isReviewer) {
      return LabLocation.global(key == 'resultados' ? 'resultados' : 'reviews');
    }
    final k = key ?? '';
    if (!role.isMember) {
      if (_participantSections.contains(k)) return LabLocation.global(k);
      if (k.startsWith('exp:') && experimentById(k.substring(4)) != null) return LabLocation.global(k);
      return const LabLocation.global('participa');
    }

    final fallback = LabLocation.project(home, LabArea.overview);
    if (kLabGlobalSections.contains(k)) {
      if (k == 'members' && role != LabRole.admin) return fallback;
      return LabLocation.global(k);
    }
    if (k.startsWith('p:')) return parse(k) ?? fallback;
    if (k.startsWith('exp:')) {
      final id = k.substring(4);
      return experimentById(id) == null ? fallback : LabLocation.project(kPlatformProjectId, LabArea.experiments, resourceId: id);
    }
    if (k.startsWith('study:')) {
      final id = k.substring(6);
      final e = builtinExperimentById(id);
      if (e != null) return LabLocation.project(e.projectId, LabArea.experiments, resourceId: id);
      final s = builtinSurveyById(id);
      if (s != null) return LabLocation.project(s.projectId, LabArea.surveys, resourceId: id);
      return fallback;
    }
    return switch (k) {
      'sma' => const LabLocation.project(kPlatformProjectId, LabArea.functionalities),
      'studies' => LabLocation.project(home, LabArea.studies),
      'library' => LabLocation.project(home, LabArea.experiments),
      'surveys' => LabLocation.project(home, LabArea.surveys),
      'features' => LabLocation.project(home, LabArea.functionalities),
      // En Configuración del proyecto, el "recurso" es la sub-sección (iam, audit, …).
      'audit' => LabLocation.project(home, LabArea.settings, resourceId: 'audit'),
      _ => fallback,
    };
  }

  @override
  bool operator ==(Object other) => other is LabLocation && other.toKey() == toKey();

  @override
  int get hashCode => toKey().hashCode;

  @override
  String toString() => 'LabLocation(${toKey()})';
}
