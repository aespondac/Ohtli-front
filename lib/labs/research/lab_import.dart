/// Qué experimentos o encuestas puede usar un estudio, como compartir recursos entre proyectos en
/// GCP: los de su proyecto y los que otros proyectos comparten. Pura (sin Firebase) para probarla.
class LabImportable {
  final String id;
  final String title;
  final String? projectId;
  final bool shared;
  final bool confidential;
  const LabImportable({required this.id, required this.title, this.projectId, this.shared = false, this.confidential = false});
}

class LabImportSplit {
  /// Del proyecto del estudio (integrados primero).
  final Map<String, String> own;

  /// Compartidos por otros proyectos, con el nombre del proyecto de origen en la etiqueta.
  final Map<String, String> shared;

  /// Ya elegidos en el estudio que su proyecto dejó de compartir: siguen listados, con aviso.
  final Map<String, String> stale;
  const LabImportSplit({required this.own, required this.shared, required this.stale});

  /// Etiqueta de un componente ya elegido.
  String labelOf(String id) => own[id] ?? shared[id] ?? (stale.containsKey(id) ? '${stale[id]} (ya no está compartido)' : id);
}

LabImportSplit splitImportables({
  required String projectId,
  required Map<String, String> builtins,
  required List<LabImportable> items,
  required Map<String, String> projectNames,
  List<String> selected = const [],
}) {
  final own = <String, String>{...builtins};
  final shared = <String, String>{};
  final stale = <String, String>{};
  for (final it in items) {
    if (own.containsKey(it.id)) continue;
    if (it.projectId == projectId) {
      own[it.id] = it.title;
    } else if (it.projectId == null && !it.confidential) {
      // Biblioteca anterior a los proyectos: pública para todos (hasta la migración).
      shared[it.id] = '${it.title} · biblioteca pública';
    } else if (it.shared && !it.confidential) {
      shared[it.id] = '${it.title} · de ${projectNames[it.projectId] ?? it.projectId}';
    } else if (selected.contains(it.id)) {
      stale[it.id] = it.title;
    }
  }
  return LabImportSplit(own: own, shared: shared, stale: stale);
}
