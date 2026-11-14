import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

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

/// Datos que la persona puede conocer y que el motor usa para el perfil del lugar
/// (deben coincidir con los campos permitidos en firestore.rules).
const List<String> kSuggestionDetailKeys = [
  'subcategories', 'vibe_tags', 'ideal_for', 'price_level', 'opening_hours', 'wheelchair_accessible',
  'musica_en_vivo', 'consumo_alcohol', 'area_verde_cercana', 'patrimonio_historico', 'tips',
];

/// Lugar sugerido por una persona desde el editor de viajes.
///
/// Vive en `poi_suggestions/{id}` y solo se usa en el viaje de quien lo sugirió. El
/// superusuario genera su perfil (receta y vector, en el motor) y, al aprobarlo, el lugar
/// entra a `pois/{id}` con el mismo id y lo puede usar el recomendador.
class PoiSuggestion {
  final String id;
  final String name;
  final String category;
  final double? lat;
  final double? lng;
  final String address;
  final String description;
  final String photoUrl;
  final String status;
  final String createdBy;
  final String createdByName;
  final String? tripId;
  final DateTime? createdAt;
  final String? reviewNote;
  final Map<String, dynamic> details;
  final Map<String, dynamic>? profile;
  final String? profileStatus;

  const PoiSuggestion({
    required this.id,
    required this.name,
    required this.category,
    this.lat,
    this.lng,
    this.address = '',
    this.description = '',
    this.photoUrl = '',
    this.status = kSuggestionPending,
    required this.createdBy,
    this.createdByName = '',
    this.tripId,
    this.createdAt,
    this.reviewNote,
    this.details = const {},
    this.profile,
    this.profileStatus,
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
      status: (d['status'] ?? kSuggestionPending).toString(),
      createdBy: (d['createdBy'] ?? '').toString(),
      createdByName: (d['createdByName'] ?? '').toString(),
      tripId: d['tripId']?.toString(),
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
      reviewNote: d['reviewNote']?.toString(),
      details: {for (final k in kSuggestionDetailKeys) if (d.containsKey(k)) k: d[k]},
      profile: d['profile'] is Map ? Map<String, dynamic>.from(d['profile'] as Map) : null,
      profileStatus: d['profileStatus']?.toString(),
    );
  }
}

/// Aporte de otra persona (desde el visor) para completar una sugerencia.
class PoiContribution {
  final String id;
  final String byName;
  final DateTime? createdAt;
  final Map<String, dynamic> data;
  const PoiContribution({required this.id, required this.byName, this.createdAt, required this.data});
}

class PoiSuggestionService {
  PoiSuggestionService._();

  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('poi_suggestions');

  static const String _primaryApiUrl = String.fromEnvironment('yollotlApiUrl', defaultValue: 'https://api-xluju5gywq-uc.a.run.app');
  static const String _secondaryApiUrl = 'https://api.ohtli.quest';

  /// Crea la sugerencia (pendiente) y devuelve su id, que también será el id del
  /// lugar en `pois` si se aprueba. [details] viene de PlaceDetailsDraft.toMap().
  static Future<String> create({
    required String name,
    required String category,
    double? lat,
    double? lng,
    String address = '',
    String description = '',
    String photoUrl = '',
    String? tripId,
    Map<String, dynamic> details = const {},
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
      for (final k in kSuggestionDetailKeys)
        if (details.containsKey(k)) k: details[k],
      'status': kSuggestionPending,
      'createdBy': user.uid,
      'createdByName': user.displayName ?? user.email ?? 'Viajero',
      if (tripId != null) 'tripId': tripId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Añade lo que otra persona sabe del lugar (desde el visor del viaje).
  static Future<void> contribute(String suggestionId, Map<String, dynamic> details) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para aportar información.');
    await _col.doc(suggestionId).collection('contributions').add({
      for (final k in [...kSuggestionDetailKeys, 'description'])
        if (details.containsKey(k)) k: details[k],
      'by': user.uid,
      'byName': user.displayName ?? 'Viajero',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<PoiContribution>> contributions(String suggestionId) async {
    final q = await _col.doc(suggestionId).collection('contributions').orderBy('createdAt').get();
    return q.docs.map((d) {
      final data = d.data();
      return PoiContribution(
        id: d.id,
        byName: (data['byName'] ?? 'Viajero').toString(),
        createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
        data: data,
      );
    }).toList();
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

  /// Superusuario: corrige nombre, tipo o descripción antes de generar el perfil.
  static Future<void> updateBasics(String id, {required String name, required String category, required String description}) {
    return _col.doc(id).update({'name': name.trim(), 'category': category, 'description': description.trim()});
  }

  /// Superusuario: el motor redacta la receta de 4 ejes y calcula el vector del lugar.
  static Future<Map<String, dynamic>> generateProfile(String id) async {
    final res = await _postToEngine('/v1/admin/place-suggestions/$id/profile', {});
    return Map<String, dynamic>.from(res['profile'] as Map? ?? {});
  }

  /// Superusuario: aprueba el perfil. El lugar entra a la base y al recomendador.
  /// Si se corrigió la receta, el motor recalcula el vector con esa versión.
  static Future<Map<String, dynamic>> approveProfile(String id, {String? semanticDescription}) {
    return _postToEngine('/v1/admin/place-suggestions/$id/approve', {
      if (semanticDescription != null) 'semantic_description': semanticDescription,
    });
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

  static Future<Map<String, dynamic>> _postToEngine(String path, Map<String, dynamic> body) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión.');
    final token = await user.getIdToken();
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
    http.Response? res;
    Object? lastError;
    for (final base in [_primaryApiUrl, _secondaryApiUrl]) {
      try {
        // Generar el perfil usa IA y puede tardar
        res = await http.post(Uri.parse('$base$path'), headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 120));
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (res == null) throw lastError ?? StateError('No pudimos conectar con el servidor.');
    final decoded = res.body.isNotEmpty ? jsonDecode(utf8.decode(res.bodyBytes)) : {};
    if (res.statusCode >= 400) {
      final detail = decoded is Map ? (decoded['detail'] ?? '').toString() : '';
      throw StateError(detail.isNotEmpty ? detail : 'El servidor respondió ${res.statusCode}.');
    }
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }
}
