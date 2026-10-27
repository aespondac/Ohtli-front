import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class PoiLocation {
  final double lat;
  final double lng;

  const PoiLocation({required this.lat, required this.lng});

  factory PoiLocation.fromMap(Map<String, dynamic> map) {
    return PoiLocation(
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};

  bool get isValid => lat != 0.0 || lng != 0.0;
}

class Poi {
  final String poiId;
  final String name;
  final String category;
  final List<String> subcategories;
  final PoiLocation location;
  final int priceLevel; // 0: Gratis, 1: Económico, 2: Moderado, 3: Costoso, 4: Lujo
  final double? priceMxnAvg;
  final String description;
  final String editorialSummary;
  final String semanticDescription;
  final Map<String, String> oepAxes;
  final List<String> vibeTags;
  final List<String> reviewsSnippets;
  final String nivelSeguridad;
  final bool formalidad;
  final int coeficienteMovilidad;
  final bool areaVerdeCercana;
  final bool patrimonioHistorico;
  final bool wheelchairAccessible;
  final bool musicaEnVivo;
  final bool consumoAlcohol;
  final String actividadEconomica;
  final String tamanoEmpresa;
  final double? acceptabilityScore;
  final double? resilienceScore;
  final double? replaceabilityScore;
  final double? ctrScore;
  final bool hasVector;
  final List<double> embeddingVector;

  final String photoUrl;
  final String address;
  final String openingHours;

  const Poi({
    required this.poiId,
    required this.name,
    required this.category,
    this.subcategories = const [],
    required this.location,
    this.priceLevel = 1,
    this.priceMxnAvg,
    this.description = '',
    this.editorialSummary = '',
    this.semanticDescription = '',
    this.oepAxes = const {},
    this.vibeTags = const [],
    this.reviewsSnippets = const [],
    this.photoUrl = '',
    this.address = '',
    this.openingHours = '',
    this.nivelSeguridad = '',
    this.formalidad = false,
    this.coeficienteMovilidad = 0,
    this.areaVerdeCercana = false,
    this.patrimonioHistorico = false,
    this.wheelchairAccessible = false,
    this.musicaEnVivo = false,
    this.consumoAlcohol = false,
    this.actividadEconomica = '',
    this.tamanoEmpresa = '',
    this.acceptabilityScore,
    this.resilienceScore,
    this.replaceabilityScore,
    this.ctrScore,
    this.hasVector = false,
    this.embeddingVector = const [],
  });

  factory Poi.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Poi.fromMap(data, doc.id);
  }

  factory Poi.fromMap(Map<String, dynamic> data, [String? fallbackId]) {
    final locData = data['location'];
    PoiLocation loc;
    if (locData is Map<String, dynamic>) {
      loc = PoiLocation.fromMap(locData);
    } else if (locData is GeoPoint) {
      loc = PoiLocation(lat: locData.latitude, lng: locData.longitude);
    } else {
      loc = const PoiLocation(lat: 0.0, lng: 0.0);
    }

    final subcats = <String>[];
    if (data['subcategories'] is List) {
      for (final s in data['subcategories']) {
        if (s != null && s.toString().trim().isNotEmpty) {
          subcats.add(s.toString().trim());
        }
      }
    }

    final vibes = <String>[];
    if (data['vibe_tags'] is List) {
      for (final v in data['vibe_tags']) {
        if (v != null && v.toString().trim().isNotEmpty) {
          vibes.add(v.toString().trim());
        }
      }
    }

    final reviews = <String>[];
    if (data['reviews_snippets'] is List) {
      for (final r in data['reviews_snippets']) {
        if (r != null && r.toString().trim().isNotEmpty) {
          reviews.add(r.toString().trim());
        }
      }
    }

    final rawAxes = data['oep_axes'];
    final axes = <String, String>{};
    if (rawAxes is Map) {
      rawAxes.forEach((key, value) {
        if (key != null && value != null) {
          axes[key.toString()] = value.toString();
        }
      });
    }

    final hasEmbedding = data.containsKey('embedding_vector') || data.containsKey('embedding');
    final List<double> vectorList = [];
    final rawVec = data['embedding_vector'] ?? data['embedding'];
    if (rawVec is List) {
      for (final v in rawVec) {
        if (v is num) vectorList.add(v.toDouble());
      }
    }

    String photo = (data['photo_url'] ?? data['image_url'] ?? data['photo'] ?? '').toString();
    if (photo.isEmpty && data['photos'] is List && (data['photos'] as List).isNotEmpty) {
      photo = (data['photos'] as List).first.toString();
    }

    final addr = (data['address'] ?? data['direccion'] ?? data['colonia'] ?? '').toString();
    final schedule = (data['opening_hours'] ?? data['horario'] ?? data['schedule'] ?? '').toString();

    return Poi(
      poiId: (data['poi_id'] ?? fallbackId ?? '').toString(),
      name: (data['name'] ?? 'Lugar sin nombre').toString(),
      category: (data['category'] ?? 'general').toString().toLowerCase(),
      subcategories: subcats,
      location: loc,
      priceLevel: (data['price_level'] as num?)?.toInt() ?? 1,
      priceMxnAvg: (data['price_mxn_avg'] as num?)?.toDouble(),
      description: (data['description'] ?? '').toString(),
      editorialSummary: (data['editorial_summary'] ?? '').toString(),
      semanticDescription: (data['semantic_description'] ?? '').toString(),
      oepAxes: axes,
      vibeTags: vibes,
      reviewsSnippets: reviews,
      photoUrl: photo,
      address: addr,
      openingHours: schedule,
      nivelSeguridad: (data['nivel_seguridad'] ?? '').toString(),
      formalidad: data['formalidad'] == true,
      coeficienteMovilidad: (data['coeficiente_movilidad'] as num?)?.toInt() ?? 0,
      areaVerdeCercana: data['area_verde_cercana'] == true,
      patrimonioHistorico: data['patrimonio_historico'] == true,
      wheelchairAccessible: data['wheelchair_accessible'] == true,
      musicaEnVivo: data['musica_en_vivo'] == true,
      consumoAlcohol: data['consumo_alcohol'] == true,
      actividadEconomica: (data['actividad_economica'] ?? '').toString(),
      tamanoEmpresa: (data['tamano_empresa'] ?? '').toString(),
      acceptabilityScore: (data['acceptability_score'] as num?)?.toDouble(),
      resilienceScore: (data['resilience_score'] as num?)?.toDouble(),
      replaceabilityScore: (data['replaceability_score'] as num?)?.toDouble(),
      ctrScore: (data['ctr_score'] as num?)?.toDouble(),
      hasVector: hasEmbedding || vectorList.isNotEmpty,
      embeddingVector: vectorList,
    );
  }

  static const Map<String, List<String>> _curatedImages = {
    'cafe': [
      'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1442512595331-e89e73853f31?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'restaurant': [
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1552566626-52f8b828add9?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'museum': [
      'https://images.unsplash.com/photo-1565008447742-97f6f38c985c?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1582555172866-f73bb12a2ab3?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1518998053901-5348d3961a04?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1566127444979-b3d2b654e3d7?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'artwork': [
      'https://images.unsplash.com/photo-1518998053901-5348d3961a04?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1565008447742-97f6f38c985c?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'gallery': [
      'https://images.unsplash.com/photo-1582555172866-f73bb12a2ab3?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1566127444979-b3d2b654e3d7?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'park': [
      'https://images.unsplash.com/photo-1519331379826-f10be5486c6f?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'bar': [
      'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1543007630-9710e4a00a20?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'cinema': [
      'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'theatre': [
      'https://images.unsplash.com/photo-1507676184212-d03ab07a01bf?auto=format&fit=crop&w=800&h=450&q=80',
    ],
    'general': [
      'https://images.unsplash.com/photo-1512815779059-d6e4df987dca?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1518638150340-f706e86654de?auto=format&fit=crop&w=800&h=450&q=80',
      'https://images.unsplash.com/photo-1520699049698-acd2fccb8cc8?auto=format&fit=crop&w=800&h=450&q=80',
    ],
  };

  String get imageUrl {
    if (photoUrl.isNotEmpty) return photoUrl;
    final key = _curatedImages.containsKey(category) ? category : 'general';
    final list = _curatedImages[key]!;
    final index = poiId.hashCode.abs() % list.length;
    return list[index];
  }

  String get categoryEmoji {
    switch (category) {
      case 'cafe':
        return '☕';
      case 'restaurant':
        return '🍽️';
      case 'museum':
        return '🏛️';
      case 'park':
      case 'zoo':
        return '🌳';
      case 'artwork':
      case 'gallery':
        return '🎨';
      case 'bar':
      case 'pub':
        return '🍸';
      case 'nightclub':
        return '🪩';
      case 'cinema':
        return '🎬';
      case 'theatre':
      case 'theater':
        return '🎭';
      case 'library':
        return '📚';
      case 'hotel':
      case 'hostel':
        return '🏨';
      case 'marketplace':
        return '🛍️';
      case 'viewpoint':
        return '🔭';
      default:
        return '📍';
    }
  }

  String get compactMetadata => '$categoryEmoji $categoryDisplay • $priceSymbols';

  String get coloniaAlcaldiaDisplay {
    if (address.isNotEmpty) {
      return address;
    }
    if (location.isValid) {
      final lat = location.lat;
      final lng = location.lng;
      if (lat >= 19.428 && lat <= 19.445 && lng >= -99.215 && lng <= -99.180) {
        return 'Polanco, Miguel Hidalgo';
      } else if (lat >= 19.405 && lat <= 19.423 && lng >= -99.175 && lng <= -99.155) {
        return 'Roma Norte, Cuauhtémoc';
      } else if (lat >= 19.405 && lat <= 19.420 && lng >= -99.185 && lng <= -99.168) {
        return 'Condesa, Cuauhtémoc';
      } else if (lat >= 19.425 && lat <= 19.445 && lng >= -99.150 && lng <= -99.125) {
        return 'Centro Histórico, Cuauhtémoc';
      } else if (lat >= 19.420 && lat <= 19.435 && lng >= -99.170 && lng <= -99.152) {
        return 'Juárez, Cuauhtémoc';
      } else if (lat >= 19.410 && lat <= 19.428 && lng >= -99.205 && lng <= -99.180) {
        return 'Bosque de Chapultepec, Miguel Hidalgo';
      } else if (lat >= 19.335 && lat <= 19.365 && lng >= -99.175 && lng <= -99.140) {
        return 'Coyoacán, Coyoacán';
      } else if (lat >= 19.335 && lat <= 19.355 && lng >= -99.200 && lng <= -99.180) {
        return 'San Ángel, Álvaro Obregón';
      } else if (lat >= 19.375 && lat <= 19.405 && lng >= -99.185 && lng <= -99.155) {
        return 'Del Valle, Benito Juárez';
      } else if (lat >= 19.390 && lat <= 19.410 && lng >= -99.190 && lng <= -99.170) {
        return 'Nápoles, Benito Juárez';
      }
    }
    return 'Ciudad de México';
  }

  String get openingHoursDisplay {
    if (openingHours.isNotEmpty) return openingHours;
    switch (category) {
      case 'cafe':
        return 'Lun - Dom: 07:30 - 21:00';
      case 'restaurant':
        return 'Mar - Dom: 13:00 - 23:00';
      case 'museum':
      case 'artwork':
      case 'gallery':
        return 'Mar - Dom: 10:00 - 18:00';
      case 'park':
      case 'zoo':
        return 'Mar - Dom: 06:00 - 18:00';
      case 'bar':
      case 'pub':
      case 'nightclub':
        return 'Mié - Sáb: 18:00 - 02:00';
      case 'cinema':
      case 'theatre':
      case 'theater':
        return 'Mar - Dom: 16:00 - 22:30';
      case 'library':
        return 'Lun - Vie: 09:00 - 19:00';
      case 'marketplace':
        return 'Lun - Dom: 09:00 - 18:00';
      default:
        return 'Lun - Dom: 09:00 - 20:00';
    }
  }

  String get categoryDisplay {
    switch (category) {
      case 'cafe':
        return 'Cafetería';
      case 'restaurant':
        return 'Restaurante';
      case 'museum':
        return 'Museo';
      case 'park':
        return 'Parque / Jardín';
      case 'artwork':
        return 'Monumento / Arte';
      case 'cinema':
        return 'Cine';
      case 'theatre':
      case 'theater':
        return 'Teatro';
      case 'bar':
        return 'Bar / Cantina';
      case 'pub':
        return 'Pub';
      case 'nightclub':
        return 'Club Nocturno';
      case 'zoo':
        return 'Zoológico';
      case 'theme_park':
        return 'Atracción / Parque Temático';
      case 'gallery':
        return 'Galería de Arte';
      case 'library':
        return 'Biblioteca';
      case 'hotel':
        return 'Hotel';
      case 'hostel':
        return 'Hostal';
      case 'marketplace':
        return 'Mercado Tradicional';
      case 'viewpoint':
        return 'Mirador';
      default:
        return category.isEmpty ? 'Punto de Interés' : '${category[0].toUpperCase()}${category.substring(1)}';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case 'cafe':
        return Icons.local_cafe_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'museum':
        return Icons.museum_rounded;
      case 'park':
        return Icons.park_rounded;
      case 'artwork':
        return Icons.palette_rounded;
      case 'cinema':
        return Icons.movie_rounded;
      case 'theatre':
      case 'theater':
        return Icons.theater_comedy_rounded;
      case 'bar':
      case 'pub':
        return Icons.local_bar_rounded;
      case 'nightclub':
        return Icons.nightlife_rounded;
      case 'zoo':
        return Icons.pets_rounded;
      case 'theme_park':
        return Icons.attractions_rounded;
      case 'gallery':
        return Icons.photo_library_rounded;
      case 'library':
        return Icons.menu_book_rounded;
      case 'hotel':
      case 'hostel':
        return Icons.hotel_rounded;
      case 'marketplace':
        return Icons.storefront_rounded;
      case 'viewpoint':
        return Icons.visibility_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Color get categoryColor {
    switch (category) {
      case 'cafe':
        return const Color(0xFF8D6E63);
      case 'restaurant':
        return OhtliColors.cempasuchil;
      case 'museum':
      case 'artwork':
      case 'gallery':
        return OhtliColors.xoconostle;
      case 'park':
      case 'zoo':
        return const Color(0xFF2E7D32);
      case 'bar':
      case 'pub':
      case 'nightclub':
        return const Color(0xFF7B1FA2);
      case 'cinema':
      case 'theatre':
      case 'theater':
        return const Color(0xFFC2185B);
      case 'hotel':
      case 'hostel':
        return const Color(0xFF1976D2);
      default:
        return OhtliColors.stormyTeal;
    }
  }

  String get priceDisplay {
    switch (priceLevel) {
      case 0:
        return 'Gratis';
      case 1:
        return '\$ (Económico)';
      case 2:
        return '\$\$ (Moderado)';
      case 3:
        return '\$\$\$ (Costoso)';
      case 4:
        return '\$\$\$\$ (Exclusivo)';
      default:
        return '\$';
    }
  }

  String get priceSymbols {
    switch (priceLevel) {
      case 0:
        return 'Gratis';
      case 1:
        return '\$';
      case 2:
        return '\$\$';
      case 3:
        return '\$\$\$';
      case 4:
        return '\$\$\$\$';
      default:
        return '\$';
    }
  }
}
