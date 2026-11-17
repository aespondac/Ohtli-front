
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'contribution_titles.dart';
import 'group_trip_service.dart';
import 'photo_storage.dart';
import 'poi_suggestion_service.dart';

/// Aportes de la comunidad a un lugar del catálogo (`place_feedback/{id}`), que el administrador
/// aprueba o rechaza:
/// - `photo`: alguien dona una foto suya; al aprobarla pasa a ser la foto del lugar.
/// - `report`: algo falta o está incorrecto (nombre, dirección, horario, precio…); al aprobarlo
///   se aplican los datos corregidos.
const String kFeedbackPhoto = 'photo';
const String kFeedbackReport = 'report';

const String kFeedbackPending = 'pending';
const String kFeedbackApproved = 'approved';
const String kFeedbackRejected = 'rejected';

/// 'missing' (falta) o 'wrong' (está incorrecto).
const String kIssueMissing = 'missing';
const String kIssueWrong = 'wrong';

/// Datos de un lugar que se pueden reportar. `applies`: campo de /pois que se corrige al aprobar
/// (null si el administrador lo resuelve a mano).
class PlaceField {
  final String id;
  final String label;
  final String hint;
  final String? applies;
  const PlaceField(this.id, this.label, this.hint, [this.applies]);
}

const List<PlaceField> kReportableFields = [
  PlaceField('name', 'Nombre', '¿Cómo se llama?', 'name'),
  PlaceField('address', 'Dirección', 'Calle, número y colonia', 'address'),
  PlaceField('location', 'Ubicación en el mapa', '¿Dónde está en realidad? (lat, lng)', 'location'),
  PlaceField('opening_hours', 'Horario', 'p. ej. Lun a vie 9:00–18:00', 'opening_hours'),
  PlaceField('price', 'Precio', 'Gasto promedio por persona en pesos', 'price_mxn_avg'),
  PlaceField('photo', 'Foto', '¿Qué tiene de malo la foto?'),
  PlaceField('category', 'Tipo de lugar', '¿Qué tipo de lugar es?', 'category'),
  PlaceField('accessibility', 'Accesibilidad', 'Rampas, elevador, baños…'),
  PlaceField('description', 'Descripción', '¿Qué le falta o qué está mal?'),
  PlaceField('closed', 'Cerró definitivamente', 'Cuéntanos qué sabes'),
  PlaceField('other', 'Algo más', 'Cuéntanos qué falta o qué está mal'),
];

PlaceField placeFieldOf(String id) =>
    kReportableFields.firstWhere((f) => f.id == id, orElse: () => PlaceField(id, id, ''));

class PlaceIssue {
  final String field;
  final String kind;
  /// La corrección que se aplicaría (texto, monto en pesos, clave de categoría, horario OSM…).
  final String value;
  /// Lo que marcó de una lista cerrada (p. ej. «No es de este lugar», «Se mudó»).
  final List<String> options;
  /// Datos estructurados: nueva ubicación {lat, lng}, dirección, fechas sin abrir, lugar al que
  /// se mudó…
  final Map<String, dynamic> extra;
  const PlaceIssue({required this.field, required this.kind, this.value = '', this.options = const [], this.extra = const {}});

  Map<String, dynamic> toMap() => {
        'field': field,
        'kind': kind,
        if (value.trim().isNotEmpty) 'value': value.trim(),
        if (options.isNotEmpty) 'options': options.take(10).toList(),
        if (extra.isNotEmpty) 'extra': extra,
      };

  static PlaceIssue fromMap(Map m) => PlaceIssue(
        field: (m['field'] ?? '').toString(),
        kind: (m['kind'] ?? kIssueWrong).toString(),
        value: (m['value'] ?? '').toString(),
        options: [for (final o in (m['options'] as List?) ?? const []) o.toString()],
        extra: m['extra'] is Map ? Map<String, dynamic>.from(m['extra'] as Map) : const {},
      );
}

class PlaceFeedback {
  final String id;
  final String type;
  final String poiId;
  final String poiName;
  final String by;
  final String byName;
  final String status;
  final String? photoUrl;
  final List<PlaceIssue> issues;
  final String note;
  final String? reviewNote;
  final DateTime? createdAt;

  const PlaceFeedback({
    required this.id,
    required this.type,
    required this.poiId,
    required this.poiName,
    required this.by,
    required this.byName,
    required this.status,
    this.photoUrl,
    this.issues = const [],
    this.note = '',
    this.reviewNote,
    this.createdAt,
  });

  bool get isPhoto => type == kFeedbackPhoto;
  bool get pending => status == kFeedbackPending;

  factory PlaceFeedback.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PlaceFeedback(
      id: doc.id,
      type: (d['type'] ?? kFeedbackReport).toString(),
      poiId: (d['poiId'] ?? '').toString(),
      poiName: (d['poiName'] ?? 'Lugar').toString(),
      by: (d['by'] ?? '').toString(),
      byName: (d['byName'] ?? 'Viajero Ohtli').toString(),
      status: (d['status'] ?? kFeedbackPending).toString(),
      photoUrl: d['photoUrl']?.toString(),
      issues: [for (final i in (d['issues'] as List?) ?? const []) if (i is Map) PlaceIssue.fromMap(i)],
      note: (d['note'] ?? '').toString(),
      reviewNote: d['reviewNote']?.toString(),
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null,
    );
  }
}

class PlaceFeedbackService {
  PlaceFeedbackService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('place_feedback');

  /// Dona una foto (data URL JPEG) a un lugar del catálogo. Se sube una copia propia, aparte del
  /// viaje, para que siga existiendo aunque el viaje se borre. Devuelve true si con esto ganó
  /// el título Nemactia.
  static Future<bool> donatePhoto({required String poiId, required String poiName, required String dataUrl, String? tripId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para donar fotos.');
    final ref = _col.doc();
    final url = await PhotoStorage.uploadDataUrl('place_donations/${user.uid}/${ref.id}.jpg', dataUrl);
    final me = await GroupTripService.me();
    await ref.set({
      'type': kFeedbackPhoto,
      'poiId': poiId,
      'poiName': poiName,
      'photoUrl': url,
      if (tripId != null) 'tripId': tripId,
      'by': user.uid,
      'byName': me.name,
      'status': kFeedbackPending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ContributionTitles.grant(user.uid, kTitleDonor);
  }

  /// Reporta lo que falta o está incorrecto en un lugar. Devuelve true si con esto ganó Tlamatini.
  static Future<bool> report({required String poiId, required String poiName, required List<PlaceIssue> issues, String note = ''}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Inicia sesión para reportar un lugar.');
    if (issues.isEmpty) throw StateError('Marca qué falta o qué está mal.');
    final me = await GroupTripService.me();
    await _col.add({
      'type': kFeedbackReport,
      'poiId': poiId,
      'poiName': poiName,
      'issues': [for (final i in issues.take(12)) i.toMap()],
      if (note.trim().isNotEmpty) 'note': note.trim().length > 500 ? note.trim().substring(0, 500) : note.trim(),
      'by': user.uid,
      'byName': me.name,
      'status': kFeedbackPending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ContributionTitles.grant(user.uid, kTitleReporter);
  }

  // --- Administrador ---

  static Stream<List<PlaceFeedback>> watchForReview() => _col
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((q) => [for (final d in q.docs) PlaceFeedback.fromDoc(d)]);

  static Stream<int> watchPendingCount() =>
      _col.where('status', isEqualTo: kFeedbackPending).snapshots().map((q) => q.size);

  /// Aprueba una foto: pasa a ser la foto del lugar (con crédito a quien la donó). Lo aplica el
  /// motor en su catálogo y en el del front, y le avisa a quien la donó.
  static Future<void> approvePhoto(PlaceFeedback f) async {
    await PoiSuggestionService.postAdmin('/v1/admin/place-feedback/${f.id}/approve', const {});
  }

  /// Aprueba un reporte y aplica los datos corregidos ([values]: campo de /pois → valor; puede ir
  /// vacío si se resolvió a mano). "Cerró definitivamente" marca el lugar como cerrado.
  static Future<void> approveReport(PlaceFeedback f, Map<String, dynamic> values, {bool closed = false}) async {
    await PoiSuggestionService.postAdmin('/v1/admin/place-feedback/${f.id}/approve', {'values': values, 'closed': closed});
  }

  static Future<void> reject(PlaceFeedback f, {String note = ''}) async {
    await _col.doc(f.id).update({
      'status': kFeedbackRejected,
      if (note.trim().isNotEmpty) 'reviewNote': note.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    await _notify(f, approved: false, note: note);
  }

  /// Aviso a quien aportó (lo escribe el administrador firmando con su uid).
  static Future<void> _notify(PlaceFeedback f, {required bool approved, String note = ''}) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null || f.by.isEmpty || f.by == admin.uid) return;
    try {
      await _db.collection('users').doc(f.by).collection('notifications').doc('place_feedback_${f.id}').set({
        'type': f.isPhoto ? 'place_photo_reviewed' : 'place_report_reviewed',
        'approved': approved,
        'poiId': f.poiId,
        'poiName': f.poiName,
        if (note.trim().isNotEmpty) 'reason': note.trim(),
        'senderId': admin.uid,
        'senderName': 'Ohtli',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
