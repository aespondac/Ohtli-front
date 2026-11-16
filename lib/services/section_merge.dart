import '../models/trip_model.dart';

/// Después de un guardado en la nube: aplica a los bloques actuales solo las fotos que se
/// subieron (`data:` → URL), y únicamente donde la foto no cambió desde que empezó el guardado.
///
/// [current] son los bloques de ahora, [before] la copia que se tomó al empezar a guardar y
/// [uploaded] esa copia con las fotos ya subidas. Lo que se editó mientras se guardaba
/// (títulos, textos, etiquetas, bloques nuevos o borrados) se conserva tal cual.
List<TripSection> mergeUploadedPhotos(List<TripSection> current, List<TripSection> before, List<TripSection> uploaded) {
  final beforeById = {for (final s in before) s.id: s};
  final uploadedById = {for (final s in uploaded) s.id: s};
  String pick(String now, String was, String up) => now == was ? up : now;

  TripSection merge(TripSection s) {
    final was = beforeById[s.id], up = uploadedById[s.id];
    if (was == null || up == null) return s;
    if (s is PlaceSection && was is PlaceSection && up is PlaceSection) {
      final secondary = [
        for (int i = 0; i < s.secondaryPhotoUrls.length; i++)
          (i < was.secondaryPhotoUrls.length && i < up.secondaryPhotoUrls.length)
              ? pick(s.secondaryPhotoUrls[i], was.secondaryPhotoUrls[i], up.secondaryPhotoUrls[i])
              : s.secondaryPhotoUrls[i],
      ];
      final String? cover = (s.coverUrl ?? '') == (was.coverUrl ?? '') ? up.coverUrl : s.coverUrl;
      return s.copyWith(
        mainPhotoUrl: pick(s.mainPhotoUrl, was.mainPhotoUrl, up.mainPhotoUrl),
        secondaryPhotoUrls: secondary,
        coverUrl: cover,
        clearCoverUrl: cover == null,
      );
    }
    if (s is TextImageSection && was is TextImageSection && up is TextImageSection) {
      return TextImageSection(
        id: s.id,
        markdownText: s.markdownText,
        imageUrl: pick(s.imageUrl, was.imageUrl, up.imageUrl),
        layout: s.layout,
      );
    }
    return s;
  }

  return [for (final s in current) merge(s)];
}

// ---------------------------------------------------------------------------
// Edición en vivo: merge a 3 vías
// ---------------------------------------------------------------------------
//
// Tres versiones del mismo contenido:
// - base: la última versión sincronizada (lo que este editor vio por última vez en la nube),
// - local: lo que hay ahora en este editor,
// - remote: lo que hay ahora en la nube (otro editor pudo cambiarlo).
//
// Reglas, bloque por bloque (por id) y campo por campo:
// - lo que cambió otro y yo no toqué, entra;
// - lo que yo edité, se queda;
// - si los dos cambiamos el mismo campo de texto y las ediciones no se enciman, se quedan
//   las dos; si se enciman (o es otro tipo de campo), gana lo local y el bloque queda
//   marcado como conflicto;
// - los bloques nuevos de otro se insertan en su posición relativa;
// - los borrados remotos que no toqué se quitan (si los toqué, se quedan y se marcan).
//
// Es genérico: trabaja sobre mapas; cualquier lista de mapas con `id` (bloques, fe de
// erratas, propuestas…) se combina por id y los mapas anidados (p. ej. votos por persona)
// llave por llave.

/// Campos de texto libre que se combinan aunque los dos los hayan cambiado.
const Set<String> kMergeableTextFields = {'title', 'description', 'markdownText', 'notes', 'note'};

const Object _missing = _Missing();

class _Missing {
  const _Missing();
}

/// Igualdad profunda de valores de Firestore (mapas, listas, números, textos, fechas).
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

class TextMergeResult {
  final String text;
  final bool conflict;
  const TextMergeResult(this.text, {this.conflict = false});
}

/// La parte de un texto que cambió: [start, end) del texto original se reemplaza por [inserted].
class _Edit {
  final int start, end;
  final String inserted;
  _Edit(this.start, this.end, this.inserted);
  bool get isInsertion => start == end;
}

_Edit _diff(String from, String to) {
  int p = 0;
  final int maxP = from.length < to.length ? from.length : to.length;
  while (p < maxP && from.codeUnitAt(p) == to.codeUnitAt(p)) {
    p++;
  }
  int s = 0;
  while (s < from.length - p && s < to.length - p &&
      from.codeUnitAt(from.length - 1 - s) == to.codeUnitAt(to.length - 1 - s)) {
    s++;
  }
  return _Edit(p, from.length - s, to.substring(p, to.length - s));
}

/// Combina dos ediciones de un mismo texto. Si tocan partes distintas se quedan las dos;
/// si se enciman, gana [local] y se marca conflicto.
TextMergeResult mergeText(String base, String local, String remote) {
  if (local == remote) return TextMergeResult(local);
  if (local == base) return TextMergeResult(remote);
  if (remote == base) return TextMergeResult(local);
  final l = _diff(base, local), r = _diff(base, remote);
  if (l.isInsertion && r.isInsertion && l.start == r.start) {
    // Los dos escribieron en el mismo punto: primero lo mío y luego lo suyo.
    final both = l.inserted == r.inserted ? l.inserted : l.inserted + r.inserted;
    return TextMergeResult(base.substring(0, l.start) + both + base.substring(l.end));
  }
  if (l.end <= r.start) {
    return TextMergeResult(
        base.substring(0, l.start) + l.inserted + base.substring(l.end, r.start) + r.inserted + base.substring(r.end));
  }
  if (r.end <= l.start) {
    return TextMergeResult(
        base.substring(0, r.start) + r.inserted + base.substring(r.end, l.start) + l.inserted + base.substring(l.end));
  }
  return TextMergeResult(local, conflict: true);
}

/// Dónde queda una posición de [oldText] (p. ej. el cursor) cuando el texto cambia a
/// [newText] por una edición ajena.
int mapTextOffset(String oldText, String newText, int offset) {
  if (offset < 0 || oldText == newText) return offset;
  final e = _diff(oldText, newText);
  if (offset <= e.start) return offset;
  if (offset >= e.end) return offset + (newText.length - oldText.length);
  return e.start + e.inserted.length;
}

class FieldMergeResult {
  final Map<String, dynamic> value;

  /// Campos (con ruta, p. ej. `location.lat`) que los dos cambiaron distinto; ganó lo local.
  final Set<String> conflicts;
  const FieldMergeResult(this.value, this.conflicts);
  bool get hasConflict => conflicts.isNotEmpty;
}

bool _isIdList(Object? v) =>
    v is List && v.isNotEmpty && v.every((e) => e is Map && e['id'] is String && (e['id'] as String).isNotEmpty);

bool _idListsCompatible(Object? b, Object? l, Object? r) {
  bool okOrEmpty(Object? v) => v == null || identical(v, _missing) || (v is List && (v.isEmpty || _isIdList(v)));
  return l is List && r is List && okOrEmpty(b) && okOrEmpty(l) && okOrEmpty(r) && (_isIdList(l) || _isIdList(r));
}

/// Combina un mapa (un bloque, el documento del viaje…) campo por campo.
FieldMergeResult mergeFields(
  Map<String, dynamic> base,
  Map<String, dynamic> local,
  Map<String, dynamic> remote, {
  Set<String> textFields = kMergeableTextFields,
  String path = '',
}) {
  final out = <String, dynamic>{};
  final conflicts = <String>{};
  final keys = <String>{...local.keys, ...remote.keys, ...base.keys};
  for (final k in keys) {
    final Object? b = base.containsKey(k) ? base[k] : _missing;
    final Object? l = local.containsKey(k) ? local[k] : _missing;
    final Object? r = remote.containsKey(k) ? remote[k] : _missing;
    final bool baseEmpty = b == null || identical(b, _missing);
    Object? v;
    if (deepEquals(l, r)) {
      v = l;
    } else if (deepEquals(l, b)) {
      v = r;
    } else if (deepEquals(r, b)) {
      v = l;
    } else if (l is String && r is String && (b is String || baseEmpty) && textFields.contains(k)) {
      final t = mergeText(b is String ? b : '', l, r);
      v = t.text;
      if (t.conflict) conflicts.add('$path$k');
    } else if (l is Map && r is Map && (b is Map || baseEmpty)) {
      final m = mergeFields(
        b is Map ? Map<String, dynamic>.from(b) : const {},
        Map<String, dynamic>.from(l),
        Map<String, dynamic>.from(r),
        textFields: textFields,
        path: '$path$k.',
      );
      v = m.value;
      conflicts.addAll(m.conflicts);
    } else if (_idListsCompatible(b, l, r)) {
      List<Map<String, dynamic>> maps(Object? x) =>
          x is List ? [for (final e in x) Map<String, dynamic>.from(e as Map)] : <Map<String, dynamic>>[];
      final m = mergeBlocks(maps(b), maps(l), maps(r), textFields: textFields);
      v = m.blocks;
      if (m.conflicts.isNotEmpty) conflicts.add('$path$k');
    } else {
      v = l;
      conflicts.add('$path$k');
    }
    if (!identical(v, _missing)) out[k] = v;
  }
  return FieldMergeResult(out, conflicts);
}

class BlockMergeResult {
  final List<Map<String, dynamic>> blocks;

  /// Bloques donde ganó lo local sobre un cambio ajeno (id → versión remota, o null si el
  /// otro lo borró y aquí se quedó porque se había editado).
  final Map<String, Map<String, dynamic>?> conflicts;

  /// Bloques que cambiaron respecto a lo local por algo que vino de fuera (incluye los nuevos).
  final Set<String> changedIds;

  /// Bloques locales que se quitaron porque otro los borró.
  final Set<String> removedIds;

  /// Bloques que se borraron aquí y que otro había cambiado (id → su versión).
  final Map<String, Map<String, dynamic>> deletedHereChangedThere;

  /// El orden de los bloques locales cambió.
  final bool reordered;

  const BlockMergeResult({
    required this.blocks,
    this.conflicts = const {},
    this.changedIds = const {},
    this.removedIds = const {},
    this.deletedHereChangedThere = const {},
    this.reordered = false,
  });
}

/// Inserta en [skeleton] los ids de [newIds] junto al vecino que tenían en [order].
void _insertRelative(List<String> skeleton, List<String> order, Set<String> newIds) {
  for (int i = 0; i < order.length; i++) {
    final id = order[i];
    if (!newIds.contains(id) || skeleton.contains(id)) continue;
    int at = -1;
    for (int j = i - 1; j >= 0 && at < 0; j--) {
      final k = skeleton.indexOf(order[j]);
      if (k >= 0) at = k + 1;
    }
    for (int j = i + 1; j < order.length && at < 0; j++) {
      final k = skeleton.indexOf(order[j]);
      if (k >= 0) at = k;
    }
    skeleton.insert(at < 0 ? skeleton.length : at, id);
  }
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

FieldMergeResult _mergeBlock(Map<String, dynamic> b, Map<String, dynamic> l, Map<String, dynamic> r, Set<String> textFields) {
  final bt = b['type'], lt = l['type'], rt = r['type'];
  if (lt != rt) {
    // Cambió el tipo de bloque: se toma entero el lado que lo cambió, si el otro no tocó nada.
    if (lt == bt && deepEquals(l, b)) return FieldMergeResult(r, const {});
    if (rt == bt && deepEquals(r, b)) return FieldMergeResult(l, const {});
    return FieldMergeResult(l, const {'type'});
  }
  return mergeFields(b, l, r, textFields: textFields);
}

/// Combina listas de bloques (mapas con `id`) a 3 vías. Ver las reglas arriba.
BlockMergeResult mergeBlocks(
  List<Map<String, dynamic>> base,
  List<Map<String, dynamic>> local,
  List<Map<String, dynamic>> remote, {
  Set<String> textFields = kMergeableTextFields,
}) {
  String idOf(Map<String, dynamic> m) => (m['id'] ?? '').toString();
  final baseById = {for (final m in base) idOf(m): m};
  final localById = {for (final m in local) idOf(m): m};
  final remoteById = {for (final m in remote) idOf(m): m};

  final merged = <String, Map<String, dynamic>>{};
  final conflicts = <String, Map<String, dynamic>?>{};
  final changed = <String>{};
  final removed = <String>{};
  final deletedHere = <String, Map<String, dynamic>>{};

  for (final l in local) {
    final id = idOf(l);
    final b = baseById[id], r = remoteById[id];
    if (b == null) {
      // Nuevo aquí. (Si el otro también trae ese id, se combina como si no hubiera base.)
      if (r == null) {
        merged[id] = l;
      } else {
        final m = _mergeBlock(const {}, l, r, textFields);
        merged[id] = m.value;
        if (m.hasConflict) conflicts[id] = r;
      }
    } else if (r == null) {
      // El otro lo borró: se quita si no lo toqué; si lo toqué, se queda y se marca.
      if (deepEquals(l, b)) {
        removed.add(id);
      } else {
        merged[id] = l;
        conflicts[id] = null;
      }
    } else {
      final m = _mergeBlock(b, l, r, textFields);
      merged[id] = m.value;
      if (m.hasConflict) conflicts[id] = r;
    }
    if (merged.containsKey(id) && !deepEquals(merged[id], l)) changed.add(id);
  }

  final remoteNew = <String>{};
  for (final r in remote) {
    final id = idOf(r);
    if (localById.containsKey(id)) continue;
    final b = baseById[id];
    if (b == null) {
      merged[id] = r;
      remoteNew.add(id);
      changed.add(id);
    } else if (!deepEquals(r, b)) {
      // Lo borré aquí y el otro lo cambió: se queda borrado (gana lo local), pero se avisa.
      deletedHere[id] = r;
    }
  }

  // Orden: si yo no reordené y el otro sí, se toma el suyo; si no, el mío. Lo nuevo de
  // cada lado entra junto a su vecino.
  final common = {
    for (final id in merged.keys)
      if (baseById.containsKey(id) && localById.containsKey(id) && remoteById.containsKey(id)) id,
  };
  List<String> commonOrder(List<Map<String, dynamic>> xs) => [for (final m in xs) if (common.contains(idOf(m))) idOf(m)];
  final localAll = [for (final m in local) if (merged.containsKey(idOf(m))) idOf(m)];
  final List<String> order;
  if (_sameOrder(commonOrder(local), commonOrder(base)) && !_sameOrder(commonOrder(remote), commonOrder(base))) {
    order = [for (final m in remote) if (merged.containsKey(idOf(m))) idOf(m)];
    _insertRelative(order, [for (final m in local) idOf(m)], {for (final id in localAll) if (!order.contains(id)) id});
  } else {
    order = List.of(localAll);
    _insertRelative(order, [for (final m in remote) idOf(m)], remoteNew);
  }
  final reordered = !_sameOrder([for (final id in order) if (localById.containsKey(id)) id], localAll);

  return BlockMergeResult(
    blocks: [for (final id in order) merged[id]!],
    conflicts: conflicts,
    changedIds: changed,
    removedIds: removed,
    deletedHereChangedThere: deletedHere,
    reordered: reordered,
  );
}

/// Resultado de combinar los bloques del viaje.
class SectionMergeResult {
  final List<TripSection> sections;

  /// Bloques donde ganó la versión local (id → versión remota; null = el otro lo borró).
  final Map<String, TripSection?> conflicts;
  final Set<String> changedIds;
  final Set<String> removedIds;
  final Map<String, TripSection> deletedHereChangedThere;
  final bool reordered;

  const SectionMergeResult({
    required this.sections,
    required this.conflicts,
    required this.changedIds,
    required this.removedIds,
    required this.deletedHereChangedThere,
    required this.reordered,
  });

  /// Algo de fuera cambió lo que se ve en este editor.
  bool get touchesLocal => changedIds.isNotEmpty || removedIds.isNotEmpty || reordered;
}

/// Merge a 3 vías de los bloques del viaje, por id. [base] es la última versión sincronizada.
SectionMergeResult mergeSections(List<TripSection> base, List<TripSection> local, List<TripSection> remote) {
  List<Map<String, dynamic>> maps(List<TripSection> xs) => [for (final s in xs) s.toMap()];
  final localById = {for (final s in local) s.id: s};
  final m = mergeBlocks(maps(base), maps(local), maps(remote));
  // Los bloques que no cambiaron conservan su objeto.
  final sections = [
    for (final map in m.blocks)
      (!m.changedIds.contains(map['id']) && localById[map['id']] != null) ? localById[map['id']]! : TripSection.fromMap(map),
  ];
  return SectionMergeResult(
    sections: sections,
    conflicts: {for (final e in m.conflicts.entries) e.key: e.value == null ? null : TripSection.fromMap(e.value!)},
    changedIds: m.changedIds,
    removedIds: m.removedIds,
    deletedHereChangedThere: {for (final e in m.deletedHereChangedThere.entries) e.key: TripSection.fromMap(e.value)},
    reordered: m.reordered,
  );
}

/// Las fotos ya subidas (URL) que usan los bloques.
Set<String> sectionPhotoUrls(Iterable<TripSection> sections) {
  final out = <String>{};
  for (final s in sections) {
    if (s is PlaceSection) {
      out.add(s.mainPhotoUrl);
      out.addAll(s.secondaryPhotoUrls);
      out.add(s.coverUrl ?? '');
    } else if (s is TextImageSection) {
      out.add(s.imageUrl);
    }
  }
  out.removeWhere((u) => u.isEmpty || u.startsWith('data:'));
  return out;
}

/// Fotos que quitó este editor: estaban en lo sincronizado ([base]) y ya no están en lo
/// local ni en lo que quedó escrito en la nube ([written]). Nunca incluye fotos que este
/// editor no conocía (p. ej. las que acaba de subir otro).
Set<String> photosRemovedHere({
  required List<TripSection> base,
  required List<TripSection> local,
  required List<TripSection> written,
}) =>
    sectionPhotoUrls(base).difference(sectionPhotoUrls(local)).difference(sectionPhotoUrls(written));
