import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/cdmx_photos.dart';

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
    if (locData is Map) {
      final m = Map<String, dynamic>.from(locData);
      loc = PoiLocation.fromMap(m);
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

    final poiName = (data['name'] ?? 'Lugar sin nombre').toString();
    final poiCat = (data['category'] ?? 'general').toString().toLowerCase();
    final rawPriceLvl = (data['price_level'] as num?)?.toInt() ?? 1;
    final rawPriceMxn = (data['price_mxn_avg'] as num?)?.toDouble();
    final resolvedPriceLvl = inferPriceLevel(poiName, poiCat, rawPriceLvl, rawPriceMxn);

    return Poi(
      poiId: (data['poi_id'] ?? fallbackId ?? '').toString(),
      name: poiName,
      category: poiCat,
      subcategories: subcats,
      location: loc,
      priceLevel: resolvedPriceLvl,
      priceMxnAvg: rawPriceMxn,
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

  /// Corrige el fallback histórico donde price_level era siempre 1 cuando no había price_mxn_avg.
  static int inferPriceLevel(String name, String category, int rawLevel, double? priceMxnAvg) {
    if (rawLevel != 1 || priceMxnAvg != null) {
      return rawLevel.clamp(0, 4);
    }
    final n = name.trim().toLowerCase();
    final c = category.trim().toLowerCase();

    const paidLookouts = ['mirador 360', 'miralto', 'torre latino', 'cetro'];
    final isPaidLookout = paidLookouts.any((k) => n.contains(k));
    if (!isPaidLookout) {
      if (const {'park', 'garden', 'nature_reserve', 'artwork', 'monument', 'memorial', 'library', 'community_centre', 'viewpoint'}.contains(c)) {
        return 0;
      }
      const freeKeywords = [
        'parque', 'jardín', 'jardin', 'alameda', 'bosque', 'plaza ', 'plazuela',
        'glorieta', 'kiosco', 'quiosco', 'camellón', 'monumento', 'escultura',
        'mural', 'estatua', 'biblioteca', 'zócalo', 'zoológico de chapultepec',
        'museo soumaya', 'palacio postal', 'casa del lago',
      ];
      if (freeKeywords.any((k) => n.contains(k))) return 0;
    }

    const tier4 = [
      'pujol', 'quintonil', 'sud 777', 'maximo bistrot', 'máximo bistrot',
      'contramar', 'entremar', 'rosetta', 'limosneros', 'azulísimo', 'azulisimo',
      'azul histórico', 'azul condesa', 'miralto', 'bellini', 'balcón del zócalo',
      'au pied de cochon', 'nobu', 'ling ling', 'suntory', 'hunan',
      'hacienda de los morales', 'rosanegra', 'chambao', 'sonora prime',
      'mochomos', 'cuerno', 'ryoshi', 'hotaru', 'handshake', 'limantour',
      'fifty mils', 'dulce patria', 'guzina oaxaca', 'nicos', 'sartoria',
      'meroma', 'havre 77', 'la docena', 'lardo',
    ];
    if (tier4.any((k) => n.contains(k))) return 4;

    const tier3 = [
      "fisher's", 'fishers', 'sonora grill', 'puerto madero', 'cambalache',
      'rincón argentino', 'la buena barra', 'negroni', 'huset', 'páramo',
      'broka', 'maque', 'peltre', 'ojo de agua', 'ojo de noche',
      'terraza catedral', 'terraza cha cha', 'supra', 'toledo rooftop',
      'balmori', 'vigneron', 'cariñito', 'ladyboy', 'soul la roma',
      'belmondo', 'mog', 'marcello', 'el diez', 'mirador 360', 'petra',
      'kuili', 'the lamb', 'yu yu', 'departamento', 'patrick miller',
      'auditorio nacional', 'palacio de bellas artes', 'teatro telcel',
      'teatro insurgentes', 'acuario inbursa', 'papalote', 'six flags',
      'pinche gringo', 'cancino', 'ardente', 'olive garden', 'cheesecake factory',
      'pf chang', 'bistro', 'bistró', 'trattoria', 'osteria', 'rooftop',
      'terraza', 'steakhouse', 'wine bar', 'speakeasy',
    ];
    if (tier3.any((k) => n.contains(k))) return 3;
    if (const {'nightclub', 'biergarten', 'music_venue', 'theme_park', 'aquarium'}.contains(c)) {
      return 3;
    }

    const tier1 = [
      'tacos', 'taco ', 'taquería', 'taqueria', 'mexitaco', 'taco naco', 'taco santo',
      'tortas', 'tortería', 'torteria', 'fonda', 'cocina económica', 'cocina central',
      'comida corrida', 'antojitos', 'quesadillas', 'gorditas', 'tlacoyos', 'tamales',
      'pozole', 'birria', 'carnitas', 'barbacoa', 'machetes', 'chalupería',
      'elotes', 'esquites', 'churros', 'nevería', 'helados', 'michoacana',
      'pulquería', 'pulqueria', 'expendio de pulque', 'duelistas', 'jarocho',
      'el huequito', 'los especiales', 'los güeros', 'los gueros', 'streetfood',
      'mcdonald', 'burger king', 'kfc', 'subway', 'el globo', 'mercado',
    ];
    if (tier1.any((k) => n.contains(k))) return 1;
    if (const {'fast_food', 'food_court', 'ice_cream', 'marketplace', 'bakery', 'pastry', 'museum'}.contains(c)) {
      return 1;
    }

    if (const {'restaurant', 'bar', 'pub', 'cinema', 'theatre', 'theater', 'cafe', 'coffee', 'books', 'gallery', 'arts_centre', 'art'}.contains(c)) {
      return 2;
    }
    return 1;
  }

  static const Set<String> _blockedPoiIds = {
    '2005860965',
    'osm_2005860965',
  };

  static const Set<String> _genericNames = {
    '',
    'lugar',
    'lugar sin nombre',
    'sin nombre',
    'poi',
    'unnamed',
    'n/a',
    'null',
    'none',
  };

  static const Set<String> _blockedCategories = {
    'entrance',
    'barrier',
    'parking',
    'parking_entrance',
    'parking_space',
    'toilets',
    'atm',
    'bank',
    'fuel',
    'waste_basket',
    'recycling',
    'bench',
    'shelter',
    'telephone',
    'post_box',
    'vending_machine',
    'charging_station',
    'bicycle_parking',
    'taxi',
    'information',
  };

  static final RegExp _infrastructureNameRegex = RegExp(
    r'('
    r'\b(s[oó]lo\s+entrada|only\s+entrance|s[oó]lo\s+salida|only\s+exit|no\s+exit|no\s+entry|sin\s+salida|entrada\s+y\s+salida|staff\s+only)\b|'
    r'^(entrada|salida|acceso|puerta|port[oó]n|reja|barrera|torniquetes?|caseta|vigilancia|taquillas?|estacionamiento|parking|ba[ñn]os?|sanitarios?|wc|cajero|atm|m[oó]dulo\s+de\s+informaci[oó]n|informaci[oó]n|mapa|letrero|and[eé]n)(\b|\s|:|-|/)|'
    r'\b(entrada\s+principal|entrada\s+peatonal|entrada\s+vehicular|entrada\s+norte|entrada\s+sur|entrada\s+este|entrada\s+oeste|entrada\s+poniente|entrada\s+oriente|'
    r'acceso\s+peatonal|acceso\s+vehicular|acceso\s+principal|acceso\s+norte|acceso\s+sur|acceso\s+este|acceso\s+oeste|acceso\s+poniente|acceso\s+oriente|'
    r'puerta\s+\d+|acceso\s+\d+|entrada\s+\d+|gate\s+\d+|main\s+entrance|pedestrian\s+entrance|vehicle\s+entrance)\b'
    r')',
    caseSensitive: false,
  );

  static bool isValidPoiNameAndId(String name, [String poiId = '', String category = '']) {
    final cleanId = poiId.trim();
    if (_blockedPoiIds.contains(cleanId)) return false;

    final cleanName = name.trim();
    if (cleanName.length < 3) return false;
    if (_genericNames.contains(cleanName.toLowerCase())) return false;
    if (_infrastructureNameRegex.hasMatch(cleanName)) return false;

    final cleanCat = category.trim().toLowerCase();
    if (cleanCat.isNotEmpty && _blockedCategories.contains(cleanCat)) {
      return false;
    }
    return true;
  }

  /// Determina si este POI corresponde a un recinto cultural/recreativo real
  /// y NO a un acceso físico perimetral (entrance=yes), puerta o nodo de infraestructura.
  bool get isValidCulturalPlace {
    return isValidPoiNameAndId(name, poiId, category);
  }

  String get imageUrl {
    if (photoUrl.isNotEmpty) return photoUrl;
    return CdmxPhotos.forCategory(category, poiId.hashCode);
  }

  String get categoryEmoji {
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case 'cafe':
      case 'coffee':
        return '☕';
      case 'restaurant':
        return '🍽️';
      case 'fast_food':
        return '🍔';
      case 'bakery':
      case 'pastry':
        return '🥐';
      case 'ice_cream':
        return '🍦';
      case 'museum':
        return '🏛️';
      case 'park':
      case 'zoo':
        return '🌳';
      case 'artwork':
      case 'gallery':
      case 'arts_centre':
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
      case 'books':
      case 'book_store':
        return '📚';
      case 'department_store':
      case 'marketplace':
      case 'market':
        return '🛍️';
      case 'attraction':
      case 'theme_park':
        return '✨';
      case 'viewpoint':
        return '🔭';
      case 'community_centre':
      case 'cultural_centre':
        return '🏛️';
      case 'internet_cafe':
        return '💻';
      case 'hotel':
      case 'hostel':
        return '🏨';
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

  /// Clean narrative for visitor reading without internal technical labels
  String get cleanNarrative {
    String text = semanticDescription.isNotEmpty ? semanticDescription : description;
    if (text.isEmpty && editorialSummary.isNotEmpty) {
      text = editorialSummary;
    }

    if (text.isEmpty) {
      return 'Un rincón fascinante de la Ciudad de México para descubrir su historia, arquitectura y vida cotidiana.';
    }

    // 1. Extraer reseña inmersiva legacy si existe el marcador
    if (text.contains('Reseña Inmersiva (OEP AI):')) {
      final parts = text.split('Reseña Inmersiva (OEP AI):');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        text = parts[1].trim();
      }
    } else if (text.contains('Reseña Inmersiva:')) {
      final parts = text.split('Reseña Inmersiva:');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        text = parts[1].trim();
      }
    }

    // 2. Formato por 4 Ejes Ontológicos (EJE 1: Vocación, EJE 2: Atmósfera, EJE 3: Dinámica, EJE 4: Entorno)
    final axisRegex = RegExp(r'\[EJE\s*\d+[^\]]*\]:\s*', caseSensitive: false);
    if (axisRegex.hasMatch(text)) {
      final rawSegments = text.split(axisRegex);
      final cleanSegments = rawSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (cleanSegments.length >= 4) {
        // Párrafo 1: Vocación + Atmósfera (Identidad y vibra)
        final p1 = '${cleanSegments[0]} ${cleanSegments[1]}';
        // Párrafo 2: Dinámica social + Micro-entorno (Experiencia de visita y barrio)
        final p2 = '${cleanSegments[2]} ${cleanSegments[3]}';
        return '$p1\n\n$p2';
      } else if (cleanSegments.isNotEmpty) {
        return cleanSegments.join('\n\n');
      }
    }

    // 3. Limpieza de líneas técnicas de metadatos o prefijos de base de datos
    final lines = text.split('\n');
    final cleanLines = <String>[];
    for (final line in lines) {
      final lower = line.trim().toLowerCase();
      if (lower.isEmpty) continue;
      if (lower.startsWith('lugar:') ||
          lower.startsWith('categoría:') ||
          lower.startsWith('categoria:') ||
          lower.startsWith('costo:') ||
          lower.startsWith('vibras') ||
          lower.startsWith('contexto urbano') ||
          lower.startsWith('formalidad') ||
          lower.startsWith('seguridad') ||
          lower.startsWith('siapem') ||
          lower.startsWith('fgj') ||
          lower.startsWith('[eje') ||
          lower.startsWith('eje 1:') ||
          lower.startsWith('eje 2:') ||
          lower.startsWith('eje 3:') ||
          lower.startsWith('eje 4:')) {
        continue;
      }
      cleanLines.add(line.trim());
    }

    final result = cleanLines.join('\n\n').trim();
    if (result.isEmpty) {
      return 'Un rincón fascinante de la Ciudad de México para descubrir su historia, arquitectura y vida cotidiana.';
    }
    return result;
  }

  String get priceRangeEstimate {
    if (priceMxnAvg != null && priceMxnAvg! > 0) {
      return '\$${priceMxnAvg!.toStringAsFixed(0)} MXN aprox.';
    }
    switch (priceLevel) {
      case 0:
        return 'Entrada libre / Gratis';
      case 1:
        return 'Económico (~ \$50 - \$120 MXN)';
      case 2:
        return 'Moderado (~ \$150 - \$300 MXN)';
      case 3:
        return 'Costoso (~ \$350 - \$600 MXN)';
      case 4:
        return 'Exclusivo (+ \$700 MXN)';
      default:
        return 'Asequible';
    }
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
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case 'cafe':
      case 'coffee':
        return 'Cafetería';
      case 'restaurant':
        return 'Restaurante';
      case 'fast_food':
        return 'Comida Rápida';
      case 'bakery':
        return 'Panadería';
      case 'pastry':
        return 'Pastelería';
      case 'ice_cream':
        return 'Heladería';
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
        return 'Pub / Cervecería';
      case 'nightclub':
        return 'Club Nocturno';
      case 'zoo':
        return 'Zoológico';
      case 'theme_park':
        return 'Parque Temático';
      case 'gallery':
        return 'Galería de Arte';
      case 'arts_centre':
        return 'Centro de las Artes';
      case 'community_centre':
        return 'Centro Comunitario';
      case 'cultural_centre':
        return 'Centro Cultural';
      case 'library':
        return 'Biblioteca';
      case 'books':
      case 'book_store':
        return 'Librería';
      case 'department_store':
        return 'Tienda Departamental';
      case 'hotel':
        return 'Hotel';
      case 'hostel':
        return 'Hostal';
      case 'marketplace':
      case 'market':
        return 'Mercado Tradicional';
      case 'viewpoint':
        return 'Mirador';
      case 'attraction':
      case 'tourist_attraction':
        return 'Atracción Turística';
      case 'internet_cafe':
        return 'Cibercafé';
      case 'car_parts':
        return 'Refaccionaria / Autopartes';
      default:
        if (cat.isEmpty) return 'Punto de Interés';
        // Formatear cualquier categoría en snake_case o kebab-case a palabras limpias
        return cat
            .split(RegExp(r'[_\-\s]+'))
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  IconData get categoryIcon {
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case 'cafe':
      case 'coffee':
        return Icons.local_cafe_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'fast_food':
        return Icons.fastfood_rounded;
      case 'bakery':
      case 'pastry':
        return Icons.bakery_dining_rounded;
      case 'ice_cream':
        return Icons.icecream_rounded;
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
      case 'attraction':
        return Icons.attractions_rounded;
      case 'gallery':
      case 'arts_centre':
        return Icons.photo_library_rounded;
      case 'library':
      case 'books':
      case 'book_store':
        return Icons.menu_book_rounded;
      case 'department_store':
        return Icons.store_mall_directory_rounded;
      case 'hotel':
      case 'hostel':
        return Icons.hotel_rounded;
      case 'marketplace':
      case 'market':
        return Icons.storefront_rounded;
      case 'viewpoint':
        return Icons.visibility_rounded;
      case 'community_centre':
      case 'cultural_centre':
        return Icons.apartment_rounded;
      case 'internet_cafe':
        return Icons.devices_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Color get categoryColor {
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case 'cafe':
      case 'coffee':
        return const Color(0xFF8D6E63);
      case 'restaurant':
        return OhtliColors.cempasuchil;
      case 'fast_food':
        return const Color(0xFFE65100);
      case 'bakery':
      case 'pastry':
        return const Color(0xFFD84315);
      case 'ice_cream':
        return const Color(0xFF00897B);
      case 'museum':
      case 'artwork':
      case 'gallery':
      case 'arts_centre':
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
      case 'books':
      case 'book_store':
      case 'library':
        return const Color(0xFF00695C);
      case 'department_store':
      case 'marketplace':
      case 'market':
        return const Color(0xFF3949AB);
      case 'hotel':
      case 'hostel':
        return const Color(0xFF1976D2);
      case 'attraction':
      case 'theme_park':
        return const Color(0xFFF57C00);
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
