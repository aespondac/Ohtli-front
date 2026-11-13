import 'package:cloud_firestore/cloud_firestore.dart';

class ErrataEntry {
  final String id;
  final String note;
  final DateTime date;

  ErrataEntry({
    required this.id,
    required this.note,
    required this.date,
  });

  factory ErrataEntry.fromMap(Map<String, dynamic> data) {
    return ErrataEntry(
      id: data['id'] ?? '',
      note: data['note'] ?? '',
      date: data['date'] != null 
          ? (data['date'] as Timestamp).toDate() 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note': note,
      'date': Timestamp.fromDate(date),
    };
  }
}

const String kTripKindTrip = 'trip';
const String kTripKindReleaseNotes = 'release_notes';

class Trip {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String coverUrl;
  final String status; // 'draft', 'published'
  final String visibility; // 'public', 'private'
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? travelDate;
  final List<ErrataEntry> errataHistory;
  
  // Multiple co-authors
  final List<String> coAuthorIds;
  final List<String> coAuthorNames;

  // Surprise fields
  final bool isSurprise;

  // Multiple targets
  final List<String> surpriseTargetIds;
  final List<String> surpriseTargetNames;
  final Map<String, DateTime> surpriseUnlockDates;
  final bool unlockOnPublish;
  final List<String> surpriseOpenedBy; // List of UIDs of users who have unwrapped it

  /// Cuándo el autor calificó las paradas después del viaje (T5). Null = pendiente.
  final DateTime? reviewedAt;

  /// Tipo de publicación: 'trip' (viaje/crónica) o 'release_notes' (notas de
  /// versión de Ohtli, que se destacan en Explorar).
  final String kind;

  /// Versión de la app a la que corresponden las notas (solo 'release_notes').
  final String? version;

  bool get isReleaseNotes => kind == kTripKindReleaseNotes;

  Trip({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.status,
    required this.visibility,
    required this.createdAt,
    required this.updatedAt,
    this.travelDate,
    this.errataHistory = const [],
    this.coAuthorIds = const [],
    this.coAuthorNames = const [],
    this.isSurprise = false,
    this.surpriseTargetIds = const [],
    this.surpriseTargetNames = const [],
    this.surpriseUnlockDates = const {},
    this.unlockOnPublish = false,
    this.surpriseOpenedBy = const [],
    this.reviewedAt,
    this.kind = kTripKindTrip,
    this.version,
  });

  factory Trip.fromMap(Map<String, dynamic> data, String documentId) {
    var errataList = data['errataHistory'] as List<dynamic>? ?? [];
    List<ErrataEntry> parsedErrata = errataList
        .map((e) => ErrataEntry.fromMap(e as Map<String, dynamic>))
        .toList();

    final List<String> coAuthorIds = List<String>.from(data['coAuthorIds'] ?? []);
    final List<String> coAuthorNames = List<String>.from(data['coAuthorNames'] ?? []);
    final List<String> surpriseTargetIds = List<String>.from(data['surpriseTargetIds'] ?? []);
    final List<String> surpriseTargetNames = List<String>.from(data['surpriseTargetNames'] ?? []);

    final List<String> surpriseOpenedBy = List<String>.from(data['surpriseOpenedBy'] ?? []);
    Map<String, DateTime> parsedUnlockDates = {};
    if (data['surpriseUnlockDates'] != null) {
      final rawMap = data['surpriseUnlockDates'] as Map<String, dynamic>;
      rawMap.forEach((key, val) {
        if (val is Timestamp) {
          parsedUnlockDates[key] = val.toDate();
        }
      });
    }
    // Backward compatibility for existing trips with a single date
    if (data['surpriseUnlockDate'] != null && parsedUnlockDates.isEmpty) {
      final singleDate = (data['surpriseUnlockDate'] as Timestamp).toDate();
      for (var targetId in surpriseTargetIds) {
        parsedUnlockDates[targetId] = singleDate;
      }
    }

    return Trip(
      id: documentId,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      coverUrl: data['coverUrl'] ?? '',
      status: data['status'] ?? 'draft',
      visibility: data['visibility'] ?? 'private',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      travelDate: data['travelDate'] != null ? (data['travelDate'] as Timestamp).toDate() : null,
      errataHistory: parsedErrata,
      coAuthorIds: coAuthorIds,
      coAuthorNames: coAuthorNames,
      isSurprise: data['isSurprise'] ?? false,
      surpriseTargetIds: surpriseTargetIds,
      surpriseTargetNames: surpriseTargetNames,
      surpriseUnlockDates: parsedUnlockDates,
      unlockOnPublish: data['unlockOnPublish'] ?? false,
      surpriseOpenedBy: surpriseOpenedBy,
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      kind: (data['kind'] ?? kTripKindTrip).toString(),
      version: data['version']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'description': description,
      'coverUrl': coverUrl,
      'status': status,
      'visibility': visibility,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'travelDate': travelDate != null ? Timestamp.fromDate(travelDate!) : null,
      'errataHistory': errataHistory.map((e) => e.toMap()).toList(),
      'coAuthorIds': coAuthorIds,
      'coAuthorNames': coAuthorNames,
      'isSurprise': isSurprise,
      'surpriseTargetIds': surpriseTargetIds,
      'surpriseTargetNames': surpriseTargetNames,
      'surpriseUnlockDates': surpriseUnlockDates.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
      'unlockOnPublish': unlockOnPublish,
      'surpriseOpenedBy': surpriseOpenedBy,
      // Solo si existe: el editor guarda con merge y no debe borrar la reseña.
      if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
      'kind': kind,
      'version': version,
    };
  }
}

class TripContent {
  final List<TripSection> sections;

  TripContent({required this.sections});

  factory TripContent.fromMap(Map<String, dynamic> data) {
    var sectionList = data['sections'] as List<dynamic>? ?? [];
    List<TripSection> parsedSections =
        sectionList.map((s) => TripSection.fromMap(Map<String, dynamic>.from(s as Map))).toList();
    return TripContent(sections: parsedSections);
  }

  Map<String, dynamic> toMap() {
    return {
      'sections': sections.map((s) => s.toMap()).toList(),
    };
  }
}

abstract class TripSection {
  final String id;
  final String type;

  TripSection({required this.id, required this.type});

  factory TripSection.fromMap(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'place':
        return PlaceSection.fromMap(data);
      case 'text':
        return TextSection.fromMap(data);
      case 'text_image':
        return TextImageSection.fromMap(data);
      case 'transfer':
        return TransferSection.fromMap(data);
      default:
        // Tipos de versiones futuras: se conservan tal cual para no perderlos al guardar.
        return UnknownSection(data);
    }
  }

  Map<String, dynamic> toMap();
}

class PlaceSection extends TripSection {
  final String title;
  final String description;
  final int rating;
  final String mainPhotoUrl;
  final List<String> secondaryPhotoUrls;
  final double cost;
  final String currency;
  final double? lat;
  final double? lng;
  final String? arrivalTime;
  final String? departureTime;

  PlaceSection({
    required super.id,
    required this.title,
    required this.description,
    required this.rating,
    required this.mainPhotoUrl,
    required this.secondaryPhotoUrls,
    this.cost = 0.0,
    this.currency = 'MXN',
    this.lat,
    this.lng,
    this.arrivalTime,
    this.departureTime,
  }) : super(type: 'place');

  /// Copia la parada conservando todos los campos que no se pasen
  /// (coordenadas y horarios incluidos). Usar siempre en lugar de
  /// reconstruir `PlaceSection(...)` a mano para no perder datos.
  PlaceSection copyWith({
    String? title,
    String? description,
    int? rating,
    String? mainPhotoUrl,
    List<String>? secondaryPhotoUrls,
    double? cost,
    String? currency,
    double? lat,
    double? lng,
    String? arrivalTime,
    String? departureTime,
    bool clearArrivalTime = false,
    bool clearDepartureTime = false,
  }) {
    return PlaceSection(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      mainPhotoUrl: mainPhotoUrl ?? this.mainPhotoUrl,
      secondaryPhotoUrls: secondaryPhotoUrls ?? this.secondaryPhotoUrls,
      cost: cost ?? this.cost,
      currency: currency ?? this.currency,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      arrivalTime: clearArrivalTime ? null : (arrivalTime ?? this.arrivalTime),
      departureTime: clearDepartureTime ? null : (departureTime ?? this.departureTime),
    );
  }

  factory PlaceSection.fromMap(Map<String, dynamic> data) {
    double? parsedLat = (data['lat'] as num?)?.toDouble();
    double? parsedLng = (data['lng'] as num?)?.toDouble();
    if (parsedLat == null && data['location'] is Map) {
      parsedLat = (data['location']['lat'] as num?)?.toDouble();
      parsedLng = (data['location']['lng'] as num?)?.toDouble();
    }

    return PlaceSection(
      id: data['id'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      rating: data['rating'] ?? 0,
      mainPhotoUrl: data['mainPhotoUrl'] ?? '',
      secondaryPhotoUrls: List<String>.from(data['secondaryPhotoUrls'] ?? []),
      cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'MXN',
      lat: parsedLat,
      lng: parsedLng,
      arrivalTime: data['arrivalTime'] ?? data['arrival_time'],
      departureTime: data['departureTime'] ?? data['departure_time'],
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'rating': rating,
      'mainPhotoUrl': mainPhotoUrl,
      'secondaryPhotoUrls': secondaryPhotoUrls,
      'cost': cost,
      'currency': currency,
      'lat': lat,
      'lng': lng,
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
      'arrivalTime': arrivalTime,
      'departureTime': departureTime,
    };
  }
}

class TextSection extends TripSection {
  final String markdownText;

  TextSection({
    required super.id,
    required this.markdownText,
  }) : super(type: 'text');

  factory TextSection.fromMap(Map<String, dynamic> data) {
    return TextSection(
      id: data['id'] ?? '',
      markdownText: data['markdownText'] ?? '',
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'markdownText': markdownText,
    };
  }
}

class TextImageSection extends TripSection {
  final String markdownText;
  final String imageUrl;
  final String layout; // 'left' or 'right'

  TextImageSection({
    required super.id,
    required this.markdownText,
    required this.imageUrl,
    required this.layout,
  }) : super(type: 'text_image');

  factory TextImageSection.fromMap(Map<String, dynamic> data) {
    return TextImageSection(
      id: data['id'] ?? '',
      markdownText: data['markdownText'] ?? data['text'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      layout: data['layout'] ?? 'left',
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'markdownText': markdownText,
      'imageUrl': imageUrl,
      'layout': layout,
    };
  }
}

/// Traslado entre dos paradas (a pie, metro, taxi…). Es el mismo bloque para
/// viajes generados por Ohtli y para los que se escriben a mano.
class TransferSection extends TripSection {
  /// walking | metro | metrobus | bus | bike | taxi | car | other
  final String mode;
  final int? durationMins;
  final double? distanceKm;
  final String notes;
  final double cost;
  final String currency;

  /// true si los minutos/distancia los calculó Ohtli (motor o estimación),
  /// false si los escribió la persona.
  final bool isEstimated;

  TransferSection({
    required super.id,
    this.mode = 'walking',
    this.durationMins,
    this.distanceKm,
    this.notes = '',
    this.cost = 0.0,
    this.currency = 'MXN',
    this.isEstimated = false,
  }) : super(type: 'transfer');

  TransferSection copyWith({
    String? mode,
    int? durationMins,
    double? distanceKm,
    String? notes,
    double? cost,
    String? currency,
    bool? isEstimated,
    bool clearDuration = false,
    bool clearDistance = false,
  }) {
    return TransferSection(
      id: id,
      mode: mode ?? this.mode,
      durationMins: clearDuration ? null : (durationMins ?? this.durationMins),
      distanceKm: clearDistance ? null : (distanceKm ?? this.distanceKm),
      notes: notes ?? this.notes,
      cost: cost ?? this.cost,
      currency: currency ?? this.currency,
      isEstimated: isEstimated ?? this.isEstimated,
    );
  }

  factory TransferSection.fromMap(Map<String, dynamic> data) {
    return TransferSection(
      id: data['id'] ?? '',
      mode: data['mode'] ?? 'walking',
      durationMins: (data['durationMins'] as num?)?.toInt(),
      distanceKm: (data['distanceKm'] as num?)?.toDouble(),
      notes: data['notes'] ?? '',
      cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'MXN',
      isEstimated: data['isEstimated'] ?? false,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'mode': mode,
      'durationMins': durationMins,
      'distanceKm': distanceKm,
      'notes': notes,
      'cost': cost,
      'currency': currency,
      'isEstimated': isEstimated,
    };
  }
}

/// Bloque de un tipo que esta versión de la app no conoce. Se guarda sin cambios.
class UnknownSection extends TripSection {
  final Map<String, dynamic> raw;

  UnknownSection(this.raw)
      : super(id: (raw['id'] ?? '').toString(), type: (raw['type'] ?? 'unknown').toString());

  @override
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(raw);
}
