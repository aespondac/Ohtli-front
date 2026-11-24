// Fotos por defecto de la Ciudad de México (Wikimedia Commons, licencias libres).
// Todas fueron revisadas: cada imagen corresponde a un lugar real de la CDMX.
// Se usan solo cuando un viaje, ruta o lugar no trae fotografía propia.

import 'dart:math' as math;

class CdmxPhotos {
  CdmxPhotos._();

  static const List<String> covers = [
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c5/Palacio_de_Bellas_Artes_00_%282%29.JPG/500px-Palacio_de_Bellas_Artes_00_%282%29.JPG', // Palacio de Bellas Artes 00 (2)
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/85/Mexico_City_Palacio_de_bellas_artes.jpg/500px-Mexico_City_Palacio_de_bellas_artes.jpg', // Mexico City Palacio de bellas artes
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/54/Catedral_Metropolitana_Mexico_City_-_Zocalo_square_-_1.jpg/500px-Catedral_Metropolitana_Mexico_City_-_Zocalo_square_-_1.jpg', // Catedral Metropolitana Mexico City - Zocalo square - 1
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/af/Vista_a%C3%A9rea_del_Castillo_de_Chapultepec_2.jpg/500px-Vista_a%C3%A9rea_del_Castillo_de_Chapultepec_2.jpg', // Vista aérea del Castillo de Chapultepec 2
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/ec/Angel_de_la_independencia170409.jpg/500px-Angel_de_la_independencia170409.jpg', // Angel de la independencia170409
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e3/Casa_de_los_Azulejos%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2014-10-13%2C_DD_47.JPG/500px-Casa_de_los_Azulejos%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2014-10-13%2C_DD_47.JPG', // Casa de los Azulejos, México D.F., México, 2014-10-13, DD 47
    'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e3/Trajinera_de_Xochimilco_-_Ciudad_de_M%C3%A9xico.jpg/500px-Trajinera_de_Xochimilco_-_Ciudad_de_M%C3%A9xico.jpg', // Trajinera de Xochimilco - Ciudad de México
  ];

  static const Map<String, List<String>> byCategory = {
    'cafe': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c1/A_pretty_cafe_in_Coyoac%C3%A1n_district._%2889188993%29.jpg/500px-A_pretty_cafe_in_Coyoac%C3%A1n_district._%2889188993%29.jpg', // A pretty cafe in Coyoacán district. (89188993)
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/39/Tierra_Garat_counter%2C_Roma_Norte%2C_Guanajuato_and_Insurgentes%2C_November_2026.jpg/500px-Tierra_Garat_counter%2C_Roma_Norte%2C_Guanajuato_and_Insurgentes%2C_November_2026.jpg', // Tierra Garat counter, Roma Norte, Guanajuato and Insurgentes, November 2026
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/94/Tierra_Garat_interior%2C_Roma_Norte%2C_Guanajuato_and_Insurgentes%2C_November_2026.jpg/500px-Tierra_Garat_interior%2C_Roma_Norte%2C_Guanajuato_and_Insurgentes%2C_November_2026.jpg', // Tierra Garat interior, Roma Norte, Guanajuato and Insurgentes, November 2026
    ],
    'restaurant': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/bf/Al_pastor_tacos_%2829161834548%29.jpg/500px-Al_pastor_tacos_%2829161834548%29.jpg', // Al pastor tacos (29161834548)
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/cb/Casa_de_Azulejos_3.jpg/500px-Casa_de_Azulejos_3.jpg', // Casa de Azulejos 3
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e3/Casa_de_los_Azulejos%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2014-10-13%2C_DD_47.JPG/500px-Casa_de_los_Azulejos%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2014-10-13%2C_DD_47.JPG', // Casa de los Azulejos, México D.F., México, 2014-10-13, DD 47
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0e/Street_tacos_in_Mexico_City_%288495923877%29.jpg/500px-Street_tacos_in_Mexico_City_%288495923877%29.jpg', // Street tacos in Mexico City (8495923877)
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/5e/Tacos_de_suadero_en_Tacos_Charly.jpg/500px-Tacos_de_suadero_en_Tacos_Charly.jpg', // Tacos de suadero en Tacos Charly
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/42/El_Califa_de_Le%C3%B3n_%282026%29_1.jpg/500px-El_Califa_de_Le%C3%B3n_%282026%29_1.jpg', // El Califa de León (2026) 1
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/bc/Tres_tipos_de_salsa_en_una_taquer%C3%ADa_de_la_Ciudad_de_M%C3%A9xico.jpg/500px-Tres_tipos_de_salsa_en_una_taquer%C3%ADa_de_la_Ciudad_de_M%C3%A9xico.jpg', // Tres tipos de salsa en una taquería de la Ciudad de México
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d5/Restaurante_Rosetta%2C_Ciudad_de_M%C3%A9xico%2C_Mexico_%28Unsplash%29.jpg/500px-Restaurante_Rosetta%2C_Ciudad_de_M%C3%A9xico%2C_Mexico_%28Unsplash%29.jpg', // Restaurante Rosetta, Ciudad de México
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d9/Street_taco_stall_in_Mexico_City.jpg/500px-Street_taco_stall_in_Mexico_City.jpg', // Street taco stall in Mexico City
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/aa/Street_Food_Vendors_in_Mexico_City_%2846733015744%29.jpg/500px-Street_Food_Vendors_in_Mexico_City_%2846733015744%29.jpg', // Street Food Vendors in Mexico City (46733015744)
    ],
    'museum': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b2/Museo_Soumaya%2C_Ciudad_de_M%C3%A9xico%2C_M%C3%A9xico%2C_2015-07-18%2C_DD_12.JPG/500px-Museo_Soumaya%2C_Ciudad_de_M%C3%A9xico%2C_M%C3%A9xico%2C_2015-07-18%2C_DD_12.JPG', // Museo Soumaya, Ciudad de México, México, 2015-07-18, DD 12
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ca/Frida_Kahlo_Museum_Coyoacan.jpg/500px-Frida_Kahlo_Museum_Coyoacan.jpg', // Frida Kahlo Museum Coyoacan
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c4/Museo_Soumaya_en_Plaza_Carso%2C_CDMX_%28detalles%29.jpg/500px-Museo_Soumaya_en_Plaza_Carso%2C_CDMX_%28detalles%29.jpg', // Museo Soumaya en Plaza Carso, CDMX (detalles)
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/61/Museo_Frida_Kahlo_%28exterior%29.jpg/500px-Museo_Frida_Kahlo_%28exterior%29.jpg', // Museo Frida Kahlo (exterior)
    ],
    'park': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/60/Lago_Mayor_de_Chapultepec_-_4.jpg/500px-Lago_Mayor_de_Chapultepec_-_4.jpg', // Lago Mayor de Chapultepec - 4
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0d/Parque_M%C3%A9xico.JPG/500px-Parque_M%C3%A9xico.JPG', // Parque México
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a8/Vista_a%C3%A9rea_del_Parque_M%C3%A9xico_08.jpg/500px-Vista_a%C3%A9rea_del_Parque_M%C3%A9xico_08.jpg', // Vista aérea del Parque México 08
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f4/Alameda_Central_-_Mexico_2024.jpg/500px-Alameda_Central_-_Mexico_2024.jpg', // Alameda Central - Mexico 2024
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f4/Lago_Mayor_de_Chapultepec_-_2.jpg/500px-Lago_Mayor_de_Chapultepec_-_2.jpg', // Lago Mayor de Chapultepec - 2
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/87/Alameda_Central_desde_el_aire_1.jpg/500px-Alameda_Central_desde_el_aire_1.jpg', // Alameda Central desde el aire 1
    ],
    'bar': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/9e/Bar_La_Opera_Centro_Historico_Mexico.JPG/500px-Bar_La_Opera_Centro_Historico_Mexico.JPG', // Bar La Opera Centro Historico Mexico
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1e/Cantina_El_Nivel.jpg/500px-Cantina_El_Nivel.jpg', // Cantina El Nivel
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/2d/Cantina_El_Nivel_2.jpg/500px-Cantina_El_Nivel_2.jpg', // Cantina El Nivel 2
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/fa/Cantina_La_Guadalupana.jpg/500px-Cantina_La_Guadalupana.jpg', // Cantina La Guadalupana
    ],
    'market': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/23/Interior_del_Mercado_de_San_Juan_08.jpg/500px-Interior_del_Mercado_de_San_Juan_08.jpg', // Interior del Mercado de San Juan 08
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c2/Girasoles_en_el_mercado_de_Jamaica.jpg/500px-Girasoles_en_el_mercado_de_Jamaica.jpg', // Girasoles en el mercado de Jamaica
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f6/Interior_del_Mercado_de_San_Juan_03.jpg/500px-Interior_del_Mercado_de_San_Juan_03.jpg', // Interior del Mercado de San Juan 03
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d4/Mercado_de_Jamaica_%286311589578%29.jpg/500px-Mercado_de_Jamaica_%286311589578%29.jpg', // Mercado de Jamaica (6311589578)
    ],
    'artwork': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6c/Diego_Rivera_Mural_Palacio_Nacional_Mexico.jpg/500px-Diego_Rivera_Mural_Palacio_Nacional_Mexico.jpg', // Diego Rivera Mural Palacio Nacional Mexico
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6d/Jos%C3%A9_Clemente_Orozco_murals_-_San_Ildefonso_College_-_Mexico_2024.jpg/500px-Jos%C3%A9_Clemente_Orozco_murals_-_San_Ildefonso_College_-_Mexico_2024.jpg', // José Clemente Orozco murals - San Ildefonso College - Mexico 2024
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ce/Jos%C3%A9_Clemente_Orozco_murals_-_Yellow_wall_courtyard_patio_-_San_Ildefonso_College_-_Mexico_2024.jpg/500px-Jos%C3%A9_Clemente_Orozco_murals_-_Yellow_wall_courtyard_patio_-_San_Ildefonso_College_-_Mexico_2024.jpg', // José Clemente Orozco murals - Yellow wall courtyard patio - San Ildefonso College - Mexico 2024
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/58/Tableros_murales_de_Diego_Rivera_en_el_Palacio_Nacional_11.jpg/500px-Tableros_murales_de_Diego_Rivera_en_el_Palacio_Nacional_11.jpg', // Tableros murales de Diego Rivera en el Palacio Nacional 11
    ],
    'theatre': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6d/Teatro_de_la_Ciudad%2C_CDMX_00074634.jpg/500px-Teatro_de_la_Ciudad%2C_CDMX_00074634.jpg', // Teatro de la Ciudad, CDMX 00074634
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/9e/Palacio_de_Bellas_Artes%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-13%2C_DD_40.jpg/500px-Palacio_de_Bellas_Artes%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-13%2C_DD_40.jpg', // Palacio de Bellas Artes, México D.F., México, 2013-10-13, DD 40
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0a/Palacio_de_Bellas_Artes%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-13%2C_DD_41.jpg/500px-Palacio_de_Bellas_Artes%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-13%2C_DD_41.jpg', // Palacio de Bellas Artes, México D.F., México, 2013-10-13, DD 41
    ],
    'church': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/54/Catedral_Metropolitana_Mexico_City_-_Zocalo_square_-_1.jpg/500px-Catedral_Metropolitana_Mexico_City_-_Zocalo_square_-_1.jpg', // Catedral Metropolitana Mexico City - Zocalo square - 1
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f3/Catedral_Metropolitana%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-16%2C_DD_81.JPG/500px-Catedral_Metropolitana%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-16%2C_DD_81.JPG', // Catedral Metropolitana, México D.F., México, 2013-10-16, DD 81
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/52/Catedral_Metropolitana%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-16%2C_DD_86.JPG/500px-Catedral_Metropolitana%2C_M%C3%A9xico_D.F.%2C_M%C3%A9xico%2C_2013-10-16%2C_DD_86.JPG', // Catedral Metropolitana, México D.F., México, 2013-10-16, DD 86
    ],
    'monument': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/ec/Angel_de_la_independencia170409.jpg/500px-Angel_de_la_independencia170409.jpg', // Angel de la independencia170409
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/ec/Angel_of_Independence_%28Angel_de_la_Independencia%29.jpg/500px-Angel_of_Independence_%28Angel_de_la_Independencia%29.jpg', // Angel of Independence (Angel de la Independencia)
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/57/Monumento_a_la_Revolucion_%282695029304%29.jpg/500px-Monumento_a_la_Revolucion_%282695029304%29.jpg', // Monumento a la Revolución (2695029304)
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a6/Monumento_a_la_Revolucion_Mexicana.JPG/500px-Monumento_a_la_Revolucion_Mexicana.JPG', // Monumento a la Revolución Mexicana
    ],
    'general': [
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/44/Paseo_de_la_Reforma_Skyline_Mexico_City.jpg/500px-Paseo_de_la_Reforma_Skyline_Mexico_City.jpg', // Paseo de la Reforma Skyline Mexico City
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/78/Calle_Francisco_I._Madero_-_Mexico_2024.jpg/500px-Calle_Francisco_I._Madero_-_Mexico_2024.jpg', // Calle Francisco I. Madero - Mexico 2024
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e3/Trajinera_de_Xochimilco_-_Ciudad_de_M%C3%A9xico.jpg/500px-Trajinera_de_Xochimilco_-_Ciudad_de_M%C3%A9xico.jpg', // Trajinera de Xochimilco - Ciudad de México
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b0/Trajineras_en_Xochimilco%2C_CDMX.jpg/500px-Trajineras_en_Xochimilco%2C_CDMX.jpg', // Trajineras en Xochimilco, CDMX
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/85/Mexico_City_Palacio_de_bellas_artes.jpg/500px-Mexico_City_Palacio_de_bellas_artes.jpg', // Mexico City Palacio de bellas artes
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/af/Vista_a%C3%A9rea_del_Castillo_de_Chapultepec_2.jpg/500px-Vista_a%C3%A9rea_del_Castillo_de_Chapultepec_2.jpg', // Vista aérea del Castillo de Chapultepec 2
    ],
  };

  // Palabras clave → grupo de fotos. El orden importa: la primera coincidencia gana
  // (p. ej. "museos_arte" es museo antes que arte; "librerias_cafes" es café).
  static const List<MapEntry<String, List<String>>> _keywords = [
    MapEntry('market', ['mercado', 'market', 'artesania', 'tianguis']),
    MapEntry('museum', ['museo', 'museum', 'galeria', 'gallery']),
    MapEntry('artwork', ['mural', 'artwork', 'arte', 'art']),
    MapEntry('bar', ['cantina', 'bar', 'pub', 'pulque', 'mezcal']),
    MapEntry('cafe', ['cafe', 'coffee', 'bakery', 'pastry', 'panaderia', 'libreria']),
    MapEntry('restaurant', ['restaur', 'food', 'comida', 'gastronom', 'taco', 'taquer', 'fonda', 'torta', 'antojito']),
    MapEntry('park', ['parque', 'park', 'bosque', 'jardin', 'garden', 'lago', 'vivero']),
    MapEntry('theatre', ['teatro', 'theat', 'cine', 'cinema', 'auditorio']),
    MapEntry('church', ['iglesia', 'templo', 'catedral', 'cathedral', 'church', 'parroquia']),
    MapEntry('monument', ['monument', 'arquitectura', 'plaza', 'zocalo']),
  ];

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  /// Grupo de fotos para una categoría (inglés, español o slugs como "museos_arte").
  static String groupFor(String? category) {
    final raw = _normalize((category ?? '').trim());
    if (byCategory.containsKey(raw)) return raw;
    for (final entry in _keywords) {
      if (entry.value.any(raw.contains)) return entry.key;
    }
    return 'general';
  }

  /// Foto de la CDMX para una categoría.
  static String forCategory(String? category, [int seed = 0]) {
    final list = byCategory[groupFor(category)]!;
    return list[seed.abs() % list.length];
  }

  /// Portada panorámica de la CDMX para viajes y rutas sin foto.
  static String cover([int seed = 0]) => covers[seed.abs() % covers.length];

  /// Dónde está lo que muestra cada portada (mismo orden que [covers]).
  static const List<(double, double)> _coverSpots = [
    (19.4352, -99.1412), // Bellas Artes
    (19.4352, -99.1412), // Bellas Artes
    (19.4345, -99.1331), // Catedral Metropolitana
    (19.4204, -99.1819), // Castillo de Chapultepec
    (19.4270, -99.1677), // Ángel de la Independencia
    (19.4342, -99.1406), // Casa de los Azulejos
    (19.2572, -99.1030), // Xochimilco
  ];

  /// Portada de la zona del viaje: una de las postales a menos de 1 km de la más cercana a
  /// ([lat], [lng]), elegida con [seed]. Un viaje por el Centro ya no sale con Xochimilco.
  static String coverNear(double lat, double lng, [int seed = 0]) {
    double km(int i) {
      final (la, lo) = _coverSpots[i];
      final dx = (lo - lng) * 104.9; // km por grado de longitud a la latitud de la CDMX
      final dy = (la - lat) * 110.8;
      return math.sqrt(dx * dx + dy * dy);
    }

    final d = [for (var i = 0; i < covers.length; i++) km(i)];
    final nearest = d.reduce(math.min);
    final within = [
      for (var i = 0; i < covers.length; i++)
        if (d[i] <= nearest + 1.0) i,
    ];
    return covers[within[seed.abs() % within.length]];
  }

  // Archivo de Commons de una URL de miniatura (".../thumb/b/b2/Archivo.jpg/500px-Archivo.jpg"
  // → "b/b2/Archivo.jpg"): la misma foto en cualquier tamaño (el motor guarda 1280 px).
  static final RegExp _commonsFile = RegExp(r'/commons/thumb/([0-9a-f]/[0-9a-f]{2}/[^/]+)/');

  static String? _fileOf(String url) => _commonsFile.firstMatch(url)?.group(1);

  static final Set<String> _referenceFiles = {
    for (final u in [...covers, for (final l in byCategory.values) ...l]) ?_fileOf(u),
  };

  static final Set<String> _coverFiles = {for (final u in covers) ?_fileOf(u)};

  /// La URL es una de estas fotos de referencia (de otro lugar de la ciudad), no una foto del
  /// lugar. Sirve también para viajes guardados antes, que la tenían como foto de la parada.
  static bool isReference(String? url) {
    if (url == null || url.isEmpty) return false;
    final f = _fileOf(url);
    return f != null && _referenceFiles.contains(f);
  }

  /// Foto de referencia de una categoría que no es postal de portada (p. ej. el Museo Soumaya
  /// para cualquier museo): como portada de un viaje hacía creer que se visita ese lugar.
  static bool isCategoryReference(String? url) {
    if (!isReference(url)) return false;
    return !_coverFiles.contains(_fileOf(url!));
  }

  /// Portada que se muestra para un viaje: la suya o, si no tiene o es la foto de referencia de
  /// una categoría (viajes guardados antes de este cambio), una postal de la CDMX.
  static String tripCover(String? coverUrl, [int seed = 0]) {
    final url = (coverUrl ?? '').trim();
    if (url.isEmpty || isCategoryReference(url)) return cover(seed);
    return url;
  }

  static final RegExp _thumbWidth = RegExp(r'/(\d+)px-');
  // Anchos que Wikimedia sirve como miniatura estándar (otros, como 640, responden 400)
  static const List<int> _thumbSteps = [250, 330, 500, 960, 1280];

  /// Misma foto de Wikimedia en el tamaño en que se muestra: [logicalWidth] puntos a la
  /// densidad de la pantalla ([pixelRatio]). Antes todas se pedían a 1280 px, también en
  /// tarjetas de 270 px. Otras URLs se devuelven igual.
  static String sized(String url, double logicalWidth, double pixelRatio) {
    final m = _thumbWidth.firstMatch(url);
    if (m == null || !url.contains('wikimedia.org') || !logicalWidth.isFinite) return url;
    final current = int.parse(m.group(1)!);
    // Imágenes chicas (tarjetas): hasta 1.5x, que cae en 500 px (~60 KB) en vez de 960 (~200 KB);
    // en un teléfono la diferencia no se nota y una lista carga varias veces más rápido
    final density = pixelRatio.clamp(1.0, logicalWidth < 400 ? 1.5 : 2.0);
    final needed = logicalWidth * density;
    final step = _thumbSteps.firstWhere((w) => w >= needed, orElse: () => _thumbSteps.last);
    // Las fotos de la app vienen a 500 px (ligeras para tarjetas); aquí se pide el tamaño justo,
    // más chico o más grande (hasta 1280, que todas las originales tienen)
    if (step == current) return url;
    return url.replaceFirst(_thumbWidth, '/${step}px-');
  }
}
