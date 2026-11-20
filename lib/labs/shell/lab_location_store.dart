import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Recuerda dónde estaba la persona en Labs: la ubicación va en la URL (`?r=<clave>`, así recargar o
/// compartir el enlace abre lo mismo) y el último proyecto y los recientes en localStorage.
///
/// En lab.ohtli.quest la app no sincroniza la URL por su cuenta, así que aquí se usa
/// `history.replaceState` (sin entradas nuevas en el historial) y se conservan los demás parámetros,
/// como `testLabApp`.
abstract class LabLocationStore {
  /// Ubicación pedida en la URL al abrir Labs.
  String? get initialKey;
  String? get lastProjectId;
  List<String> get recentProjects;
  void save(String key, {String? projectId});

  static LabLocationStore create() => kIsWeb ? _WebLocationStore() : MemoryLocationStore();
}

/// Para pruebas y fuera de la web.
class MemoryLocationStore implements LabLocationStore {
  @override
  String? initialKey;
  @override
  String? lastProjectId;
  @override
  final List<String> recentProjects = [];
  final List<String> saved = [];

  MemoryLocationStore({this.initialKey, this.lastProjectId});

  @override
  void save(String key, {String? projectId}) {
    saved.add(key);
    if (projectId != null) {
      lastProjectId = projectId;
      updateRecent(recentProjects, projectId);
    }
  }
}

const kLabRecentProjectsMax = 5;

/// Pone [projectId] al frente de los recientes, sin repetidos y con máximo [kLabRecentProjectsMax].
void updateRecent(List<String> recent, String projectId) {
  recent
    ..remove(projectId)
    ..insert(0, projectId);
  if (recent.length > kLabRecentProjectsMax) recent.removeRange(kLabRecentProjectsMax, recent.length);
}

class _WebLocationStore implements LabLocationStore {
  static const _lastKey = 'labs.project';
  static const _recentKey = 'labs.recentProjects';
  static const _param = 'r';

  @override
  late final String? initialKey = _read();

  String? _read() {
    try {
      final r = Uri.parse(web.window.location.href).queryParameters[_param];
      return (r == null || r.isEmpty) ? null : r;
    } catch (_) {
      return null;
    }
  }

  String? _get(String k) {
    try {
      return web.window.localStorage.getItem(k);
    } catch (_) {
      return null; // almacenamiento bloqueado (modo privado): se trabaja sin recordar
    }
  }

  void _set(String k, String v) {
    try {
      web.window.localStorage.setItem(k, v);
    } catch (_) {}
  }

  @override
  String? get lastProjectId => _get(_lastKey);

  @override
  List<String> get recentProjects => [for (final s in (_get(_recentKey) ?? '').split(',')) if (s.isNotEmpty) s];

  @override
  void save(String key, {String? projectId}) {
    if (projectId != null) {
      _set(_lastKey, projectId);
      final recent = recentProjects;
      updateRecent(recent, projectId);
      _set(_recentKey, recent.join(','));
    }
    try {
      final uri = Uri.parse(web.window.location.href);
      final params = Map<String, String>.from(uri.queryParameters)..[_param] = key;
      final next = uri.replace(queryParameters: params);
      final url = '${next.path}?${next.query}${uri.hasFragment ? '#${uri.fragment}' : ''}';
      web.window.history.replaceState(null, '', url);
    } catch (_) {}
  }
}
