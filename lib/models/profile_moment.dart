import 'trip_model.dart';

/// Foto de un viaje que la persona fijó en su perfil ("Momentos").
/// Se guarda en `users/{uid}.moments` y se copia a `public_profiles/{uid}.moments` (lectura
/// pública). Si quien mira no puede ver el
/// viaje (privado o borrador), solo ve la foto: ni título ni enlace al viaje.
class ProfileMoment {
  final String url;
  final String tripId;
  final String tripTitle;

  /// Lugar o texto de donde salió la foto (p. ej. el nombre de la parada).
  final String caption;
  final DateTime? date;

  const ProfileMoment({required this.url, required this.tripId, required this.tripTitle, this.caption = '', this.date});

  static const int maxMoments = 12;

  factory ProfileMoment.fromMap(Map<String, dynamic> m) => ProfileMoment(
        url: (m['url'] ?? '').toString(),
        tripId: (m['tripId'] ?? '').toString(),
        tripTitle: (m['tripTitle'] ?? '').toString(),
        caption: (m['caption'] ?? '').toString(),
        date: m['date'] is int ? DateTime.fromMillisecondsSinceEpoch(m['date'] as int) : null,
      );

  Map<String, dynamic> toMap() => {
        'url': url,
        'tripId': tripId,
        'tripTitle': tripTitle,
        'caption': caption,
        if (date != null) 'date': date!.millisecondsSinceEpoch,
      };

  /// Lee la lista del documento del perfil, ignorando entradas rotas.
  static List<ProfileMoment> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          ProfileMoment.fromMap(Map<String, dynamic>.from(e)),
    ].where((m) => m.url.isNotEmpty && m.tripId.isNotEmpty).take(maxMoments).toList();
  }
}

/// Fotos que se pueden elegir como momento de un viaje: portada, fotos de cada parada
/// e imágenes de los bloques de texto. Sin repetir y sin imágenes incrustadas (data:),
/// que no caben en el documento del perfil.
List<({String url, String caption})> momentCandidates(Trip trip, TripContent? content) {
  final out = <({String url, String caption})>[];
  final seen = <String>{};
  void add(String? url, String caption) {
    if (url == null || url.isEmpty || url.startsWith('data:') || !seen.add(url)) return;
    out.add((url: url, caption: caption));
  }

  add(trip.coverUrl, trip.title);
  for (final s in content?.sections ?? const <TripSection>[]) {
    if (s is PlaceSection) {
      add(s.coverUrl, s.title);
      add(s.ownMainPhotoUrl, s.title);
      for (final u in s.secondaryPhotoUrls) {
        add(u, s.title);
      }
    } else if (s is TextImageSection) {
      add(s.imageUrl, trip.title);
    }
  }
  return out;
}
