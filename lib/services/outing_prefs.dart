/// Preferencias de salida del perfil cultural (onboarding) que admiten varias opciones:
/// con quién, a qué hora, ritmo y cómo te mueves.
///
/// Cada una se guarda en dos campos:
/// - la lista completa (p. ej. `social_companions`), y
/// - el campo de siempre con la primera opción (p. ej. `social_companion`), que siguen
///   leyendo el motor y los perfiles guardados antes de la selección múltiple.
class OutingPref {
  const OutingPref(this.listKey, this.legacyKey, this.fallback);

  final String listKey;
  final String legacyKey;
  final String fallback;

  static const companion = OutingPref('social_companions', 'social_companion', 'pareja');
  static const timeWindow = OutingPref('preferred_time_windows', 'preferred_time_window', 'tarde');
  static const pace = OutingPref('travel_paces', 'travel_pace', 'moderado');
  static const transport = OutingPref('transport_preferences', 'transport_preference', 'caminata');

  static const all = [companion, timeWindow, pace, transport];

  /// Opciones elegidas: la lista si existe; si no, el valor único viejo (texto o lista).
  /// Nunca vacía: sin datos devuelve [fallback].
  List<String> read(Map? profile) {
    final out = <String>[];
    void addAll(Object? raw) {
      if (raw is String) {
        if (raw.trim().isNotEmpty) out.add(raw.trim());
      } else if (raw is Iterable) {
        for (final e in raw) {
          final v = e?.toString().trim() ?? '';
          if (v.isNotEmpty && !out.contains(v)) out.add(v);
        }
      }
    }

    if (profile != null) {
      addAll(profile[listKey]);
      if (out.isEmpty) addAll(profile[legacyKey]);
    }
    return out.isEmpty ? [fallback] : out;
  }

  /// Campos a guardar para [values]: la lista y el valor único con la primera opción.
  Map<String, Object> write(Iterable<String> values) {
    final list = values.where((v) => v.trim().isNotEmpty).toSet().toList();
    if (list.isEmpty) list.add(fallback);
    return {listKey: list, legacyKey: list.first};
  }
}

/// Texto legible de varias opciones: "solo", "solo y amigos", "solo, amigos y familia".
String joinOptions(List<String> values) {
  if (values.isEmpty) return '';
  if (values.length == 1) return values.first;
  return '${values.sublist(0, values.length - 1).join(', ')} y ${values.last}';
}
