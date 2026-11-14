import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Categorías que se pueden elegir al sugerir un lugar (claves del catálogo → etiqueta).
const Map<String, String> kSuggestionCategories = {
  'museum': 'Museo',
  'gallery': 'Galería de arte',
  'artwork': 'Monumento / arte público',
  'theatre': 'Teatro',
  'cinema': 'Cine',
  'arts_centre': 'Centro cultural',
  'park': 'Parque / jardín',
  'cafe': 'Cafetería',
  'restaurant': 'Restaurante',
  'bar': 'Bar / cantina',
  'marketplace': 'Mercado',
  'place_of_worship': 'Templo / iglesia',
  'attraction': 'Atracción turística',
  'other': 'Otro',
};

/// Estados de una sugerencia.
const String kSuggestionPending = 'pending';
const String kSuggestionApproved = 'approved';
const String kSuggestionRejected = 'rejected';

/// Lugar sugerido por una persona desde el editor de viajes.
///
/// Vive en `poi_suggestions/{id}` y solo se usa en el viaje de quien lo sugirió.
/// Cuando el superusuario lo aprueba se copia a `pois/{id}` (mismo id), así las
/// paradas que ya lo usan quedan vinculadas al catálogo sin tocar sus viajes.
class PoiSuggestion {
  final String id;
  final String name;
  final String category;
  final double? lat;
  final double? lng;
  final String address;
  final String description;
  final String photoUrl;
  final double? priceMxnAvg;
  final String status;
  final String createdBy;
  final String createdByName;
  final String? tripId;
  final DateTime? createdAt;
  final String? reviewNote;

  const PoiSuggestion({
    required this.id,
    required this.name,
    required this.category,
    this.lat,
    this.lng,
    this.address = '',
    this.description = '',
    this.photoUrl = '',
    this.priceMxnAvg,
    this.status = kSuggestionPending,
    required this.createdBy,
    this.createdByName = '',
    this.tripId,
    this.createdAt,
    this.reviewNote,
  });

  bool get hasLocation => lat != null && lng != null;

  factory PoiSuggestion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final loc = d['location'];
    return PoiSuggestion(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      category: (d['category'] ?? 'other').toString(),
      lat: loc is Map ? (loc['lat'] as num?)?.toDouble() : null,
      lng: loc is Map ? (loc['lng'] as num?)?.toDouble() : null,
      address: (d['address'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      photoUrl: (d['photo_url'] ?? '').toString(),
      priceMxnAvg: (d['price_mxn_avg'] as num?)?.toDouble(),
      status: (d['status'] ?? kSuggestionPending).toString(),
      createdBy: (d['createdBy'] ?? '').toString(),
      createdByName: (d['createdByName'] ?? '').toString(),
      tripId: d['tripId']?.toString(),
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
      reviewNote: d['reviewNote']?.toString(),
    );
  }

  /// Documento para `pois/{id}` con los campos que leen el catálogo y el motor.
  Map<String, dynamic> toPoiDocument({required String approvedBy}) {
    final name = this.name.trim();
    return {
      'poi_id': id,
      'name': name,
      'category': category,
      'subcategories': <String>[],
      if (hasLocation) 'location': {'lat': lat, 'lng': lng},
      'address': address,
      'description': description,
      'editorial_summary': description,
      'photo_url': photoUrl,
      if (priceMxnAvg != null) 'price_mxn_avg': priceMxnAvg,
      'price_level': priceMxnAvg == null ? 1 : (priceMxnAvg! <= 0 ? 0 : (priceMxnAvg! < 150 ? 1 : (priceMxnAvg! < 400 ? 2 : 3))),
      'vibe_tags': <String>[],
      'source': 'user_suggestion',
      'suggested_by': createdBy,
      'approved_by': approvedBy,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}

class PoiSuggestionService {
  PoiSuggestionService._();

  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('poi_suggestions');

  /// Crea la sugerencia (pendiente) y devuelve su id, que también será el id del
  /// lugar en `pois` si se aprueba.
  static Future<String> create({
    required String name,
    required String category,
    double? lat,
    double? lng,
    String address = '',
    String description = '',
    String photoUrl = '',
    double? priceMxnAvg,
    String? tripId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para sugerir un lugar.');
    final ref = _col.doc('sug_${_col.doc().id}');
    await ref.set({
      'name': name.trim(),
      'category': category,
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
      'address': address.trim(),
      'description': description.trim(),
      'photo_url': photoUrl,
      if (priceMxnAvg != null) 'price_mxn_avg': priceMxnAvg,
      'status': kSuggestionPending,
      'createdBy': user.uid,
      'createdByName': user.displayName ?? user.email ?? 'Viajero',
      if (tripId != null) 'tripId': tripId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Estado actual de varias sugerencias propias (las que no se pudieron leer se omiten).
  static Future<Map<String, String>> statuses(Iterable<String> ids) async {
    final out = <String, String>{};
    await Future.wait(ids.toSet().map((id) async {
      try {
        final doc = await _col.doc(id).get();
        if (doc.exists) out[id] = (doc.data()?['status'] ?? kSuggestionPending).toString();
      } catch (_) {}
    }));
    return out;
  }

  /// Sugerencias para revisión (solo superusuario), las pendientes primero.
  static Stream<List<PoiSuggestion>> watchForReview() {
    return _col.orderBy('createdAt', descending: true).limit(200).snapshots().map((q) {
      final list = q.docs.map(PoiSuggestion.fromDoc).toList();
      int rank(PoiSuggestion s) => s.status == kSuggestionPending ? 0 : 1;
      list.sort((a, b) => rank(a).compareTo(rank(b)));
      return list;
    });
  }

  static Stream<int> watchPendingCount() =>
      _col.where('status', isEqualTo: kSuggestionPending).snapshots().map((q) => q.size);

  /// Aprueba: crea `pois/{id}` y marca la sugerencia en una sola escritura atómica.
  static Future<void> approve(PoiSuggestion s, {PoiSuggestion? edited}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    final data = edited ?? s;
    final batch = FirebaseFirestore.instance.batch();
    batch.set(FirebaseFirestore.instance.collection('pois').doc(s.id), data.toPoiDocument(approvedBy: user.uid));
    batch.update(_col.doc(s.id), {
      'status': kSuggestionApproved,
      'name': data.name.trim(),
      'category': data.category,
      'reviewedBy': user.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> reject(PoiSuggestion s, {String note = ''}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    await _col.doc(s.id).update({
      'status': kSuggestionRejected,
      'reviewNote': note.trim(),
      'reviewedBy': user.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }
}
