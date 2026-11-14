import 'package:cloud_firestore/cloud_firestore.dart';

/// Viaje destacado en el bloque principal de Explorar.
class FeaturedTrip {
  final String tripId;
  final String authorId;
  final String title;
  const FeaturedTrip({required this.tripId, required this.authorId, this.title = ''});

  Map<String, dynamic> toMap() => {'tripId': tripId, 'authorId': authorId, 'title': title};

  static FeaturedTrip? fromMap(Object? m) {
    if (m is! Map) return null;
    final tripId = (m['tripId'] ?? '').toString();
    final authorId = (m['authorId'] ?? '').toString();
    if (tripId.isEmpty || authorId.isEmpty) return null;
    return FeaturedTrip(tripId: tripId, authorId: authorId, title: (m['title'] ?? '').toString());
  }
}

/// Lo que el superusuario elige para el bloque principal de Explorar (`app_config/explore`).
/// [pinned] == null significa que nunca se ha configurado (se usan los destacados por defecto).
class ExploreConfig {
  final List<FeaturedTrip>? pinned;
  final bool showReleaseNotes;
  const ExploreConfig({this.pinned, this.showReleaseNotes = true});
}

class ExploreConfigService {
  ExploreConfigService._();

  static final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('app_config').doc('explore');

  static ExploreConfig _parse(Map<String, dynamic>? d) {
    if (d == null) return const ExploreConfig();
    final raw = d['pinned'];
    return ExploreConfig(
      pinned: raw is List ? raw.map(FeaturedTrip.fromMap).whereType<FeaturedTrip>().toList() : null,
      showReleaseNotes: d['showReleaseNotes'] != false,
    );
  }

  static Future<ExploreConfig> load() async {
    try {
      final snap = await _doc.get().timeout(const Duration(seconds: 10));
      return _parse(snap.data());
    } catch (_) {
      return const ExploreConfig();
    }
  }

  static Stream<ExploreConfig> watch() => _doc.snapshots().map((s) => _parse(s.data()));

  /// Solo el superusuario (las reglas lo exigen).
  static Future<void> save({required List<FeaturedTrip> pinned, required bool showReleaseNotes}) {
    return _doc.set({
      'pinned': pinned.map((p) => p.toMap()).toList(),
      'showReleaseNotes': showReleaseNotes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
