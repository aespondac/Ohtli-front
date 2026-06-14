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
    };
  }
}

class TripContent {
  final List<TripSection> sections;

  TripContent({required this.sections});

  factory TripContent.fromMap(Map<String, dynamic> data) {
    var sectionList = data['sections'] as List<dynamic>? ?? [];
    List<TripSection> parsedSections = sectionList.map((s) => TripSection.fromMap(s as Map<String, dynamic>)).toList();
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
      default:
        throw Exception('Unknown section type');
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

  PlaceSection({
    required super.id,
    required this.title,
    required this.description,
    required this.rating,
    required this.mainPhotoUrl,
    required this.secondaryPhotoUrls,
    this.cost = 0.0,
    this.currency = 'MXN',
  }) : super(type: 'place');

  factory PlaceSection.fromMap(Map<String, dynamic> data) {
    return PlaceSection(
      id: data['id'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      rating: data['rating'] ?? 0,
      mainPhotoUrl: data['mainPhotoUrl'] ?? '',
      secondaryPhotoUrls: List<String>.from(data['secondaryPhotoUrls'] ?? []),
      cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
      currency: data['currency'] ?? 'MXN',
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
