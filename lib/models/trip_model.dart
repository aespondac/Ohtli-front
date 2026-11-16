import 'package:cloud_firestore/cloud_firestore.dart';

/// Entrada de la fe de erratas: quién cambió qué y cuándo (después del viaje).
class ErrataEntry {
  final String id;
  final String note;
  final DateTime date;

  /// Quién hizo el cambio (vacío en entradas antiguas).
  final String authorId;
  final String authorName;

  /// Lo que cambió, una línea por cambio (p. ej. "Gasto real de «Tacos»: $180 → $236").
  final List<String> changes;

  ErrataEntry({
    required this.id,
    required this.note,
    required this.date,
    this.authorId = '',
    this.authorName = '',
    this.changes = const [],
  });

  factory ErrataEntry.fromMap(Map<String, dynamic> data) {
    final d = data['date'];
    return ErrataEntry(
      id: data['id'] ?? '',
      note: data['note'] ?? '',
      date: d is Timestamp ? d.toDate() : (d is DateTime ? d : DateTime.now()),
      authorId: (data['authorId'] ?? '').toString(),
      authorName: (data['authorName'] ?? '').toString(),
      changes: data['changes'] is List ? List<String>.from((data['changes'] as List).map((e) => e.toString())) : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note': note,
      'date': Timestamp.fromDate(date),
      if (authorId.isNotEmpty) 'authorId': authorId,
      if (authorName.isNotEmpty) 'authorName': authorName,
      if (changes.isNotEmpty) 'changes': changes,
    };
  }
}

const String kTripKindTrip = 'trip';
const String kTripKindReleaseNotes = 'release_notes';

/// Tipos de novedad en las notas de versión (id → nombre visible).
const Map<String, String> kReleaseTags = {
  'nuevo': 'Nuevo',
  'mejora': 'Mejora',
  'correccion': 'Corrección',
};

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

  /// Cuándo terminaron el viaje desde el modo viaje: desde ahí el viaje está en "después".
  final DateTime? finishedAt;

  /// Tipo de publicación: 'trip' (viaje/crónica) o 'release_notes' (notas de
  /// versión de Ohtli, que se destacan en Explorar).
  final String kind;

  /// Versión de la app a la que corresponden las notas (solo 'release_notes').
  final String? version;

  bool get isReleaseNotes => kind == kTripKindReleaseNotes;

  /// Lugares que propuso el motor cuando el viaje salió de una recomendación
  /// (`recommendation.poi_ids` del documento; lo escribe saveOptionAsTrip). Con esto la
  /// retroalimentación distingue "quitó una recomendación" de "quitó algo que agregó a mano".
  final List<String> recommendedPoiIds;
  final String? recommendationJobId;

  /// Forma de la ruta elegida en el asistente: 'anillo' (ida y vuelta) o, en la abierta,
  /// qué extremos se fijaron ('inicio', 'fin' o 'ambos').
  final String? routeShape;

  /// Solicitud de viaje en grupo de la que salió (group_trips/{id}): con ella los invitados
  /// que aceptan se suman como coautores.
  final String? groupTripId;

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
    this.finishedAt,
    this.kind = kTripKindTrip,
    this.version,
    this.recommendedPoiIds = const [],
    this.recommendationJobId,
    this.routeShape,
    this.groupTripId,
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
      finishedAt: (data['finishedAt'] as Timestamp?)?.toDate(),
      kind: (data['kind'] ?? kTripKindTrip).toString(),
      version: data['version']?.toString(),
      recommendedPoiIds: data['recommendation'] is Map
          ? List<String>.from(((data['recommendation'] as Map)['poi_ids'] as List?) ?? const [])
          : const [],
      recommendationJobId:
          data['recommendation'] is Map ? (data['recommendation'] as Map)['job_id']?.toString() : null,
      routeShape: data['routeShape']?.toString(),
      groupTripId: data['groupTripId']?.toString(),
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
      if (finishedAt != null) 'finishedAt': Timestamp.fromDate(finishedAt!),
      'kind': kind,
      'version': version,
      // Solo si existen: el editor guarda con merge y no debe borrarlos.
      if (routeShape != null) 'routeShape': routeShape,
      if (groupTripId != null) 'groupTripId': groupTripId,
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

/// Origen del lugar de una parada.
/// - catalog: vinculado a un lugar de la base de Ohtli (`pois/{poiId}`).
/// - suggestion: lugar nuevo sugerido por la persona (`poi_suggestions/{poiId}`); solo
///   se usa en su viaje hasta que el superusuario lo aprueba. Al aprobarse se crea
///   `pois/{poiId}` con el mismo id y la parada pasa a `catalog`.
/// - null: lugar genérico, sin vínculo con la base.
const String kPlaceSourceCatalog = 'catalog';
const String kPlaceSourceSuggestion = 'suggestion';

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
  final String? poiId;
  final String? poiSource;

  /// Lugar no previsto que los viajeros agregaron durante el viaje (un "desvío").
  final bool unplanned;

  /// Hora real de llegada y salida ("HH:mm"), registradas con "Llegué" / "Ya me voy".
  final String? arrivedAt;
  final String? leftAt;

  /// Lo que realmente se gastó en la parada (el costo estimado sigue en [cost]).
  final double? realCost;

  /// Portada elegida por los viajeros. Si no hay, se usa la del catálogo o una de referencia.
  final String? coverUrl;

  /// Solo en notas de versión: la parada es una "novedad" y esto dice de qué tipo es
  /// ('nuevo', 'mejora' o 'correccion', ver [kReleaseTags]).
  final String? changeTag;

  bool get isLinkedToCatalog => poiId != null && poiSource == kPlaceSourceCatalog;
  bool get isSuggestion => poiId != null && poiSource == kPlaceSourceSuggestion;
  bool get isGeneric => !isLinkedToCatalog && !isSuggestion;

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
    this.poiId,
    this.poiSource,
    this.unplanned = false,
    this.arrivedAt,
    this.leftAt,
    this.realCost,
    this.coverUrl,
    this.changeTag,
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
    String? poiId,
    String? poiSource,
    bool clearPoi = false,
    bool? unplanned,
    String? arrivedAt,
    String? leftAt,
    double? realCost,
    bool clearArrivedAt = false,
    bool clearLeftAt = false,
    bool clearRealCost = false,
    String? coverUrl,
    bool clearCoverUrl = false,
    String? changeTag,
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
      poiId: clearPoi ? null : (poiId ?? this.poiId),
      poiSource: clearPoi ? null : (poiSource ?? this.poiSource),
      unplanned: unplanned ?? this.unplanned,
      arrivedAt: clearArrivedAt ? null : (arrivedAt ?? this.arrivedAt),
      leftAt: clearLeftAt ? null : (leftAt ?? this.leftAt),
      realCost: clearRealCost ? null : (realCost ?? this.realCost),
      coverUrl: clearCoverUrl ? null : (coverUrl ?? this.coverUrl),
      changeTag: changeTag ?? this.changeTag,
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
      poiId: (data['poiId'] ?? data['poi_id'])?.toString(),
      poiSource: data['poiSource']?.toString() ??
          ((data['poiId'] ?? data['poi_id']) != null ? kPlaceSourceCatalog : null),
      unplanned: data['unplanned'] == true,
      arrivedAt: data['arrivedAt']?.toString(),
      leftAt: data['leftAt']?.toString(),
      realCost: (data['realCost'] as num?)?.toDouble(),
      coverUrl: (data['coverUrl'] as String?)?.trim().isEmpty == true ? null : data['coverUrl'] as String?,
      changeTag: kReleaseTags.containsKey(data['changeTag']) ? data['changeTag'] as String : null,
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
      if (poiId != null) 'poiId': poiId,
      if (poiId != null) 'poiSource': poiSource ?? kPlaceSourceCatalog,
      if (unplanned) 'unplanned': true,
      if (arrivedAt != null) 'arrivedAt': arrivedAt,
      if (leftAt != null) 'leftAt': leftAt,
      if (realCost != null) 'realCost': realCost,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (changeTag != null) 'changeTag': changeTag,
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
