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
