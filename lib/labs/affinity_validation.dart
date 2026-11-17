import 'dart:math' as math;

/// Validación de afinidad: comprueba que el puntaje de afinidad del Comparador mide lo que dice
/// medir. Dos partes:
///
///  1. Pruebas automáticas contra `/v1/comparador/match-test` (sin participantes): coherencia
///     temática contra la tasa base del catálogo, discriminación entre perfiles opuestos, lugares
///     genéricos que salen para todos, sensibilidad, determinismo, recuperación de un lugar
///     conocido, resolución del puntaje y restricciones duras (presupuesto y accesibilidad).
///  2. Calibración con personas: el participante califica a ciegas lugares del sistema mezclados
///     con lugares al azar del catálogo; si la afinidad sirve, el sistema le gana al azar.
///
/// Esta parte no hace red: recibe una función [MatchFn] para poder probarla con respuestas fijas.

typedef MatchFn = Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

enum CheckStatus { pass, warn, fail }

class AffinityCheck {
  final String id;
  final String title;

  /// Qué se pregunta y con qué umbral se aprueba.
  final String question;

  /// Resultado medido, en una línea.
  final String result;
  final CheckStatus status;

  /// Datos de apoyo (lugares, puntajes) para revisar a mano.
  final List<String> details;

  /// Cambió de resultado entre corridas repetidas.
  final bool unstable;

  const AffinityCheck({
    required this.id,
    required this.title,
    required this.question,
    required this.result,
    required this.status,
    this.details = const [],
    this.unstable = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'question': question,
        'result': result,
        'status': status.name,
        'details': details,
        if (unstable) 'unstable': true,
      };
}

/// Perfil de prueba con un tema claro y las categorías del catálogo que cuentan como "del tema".
class AffinityTheme {
  final String id;
  final String label;

  /// Cómo se le describe el perfil a quien califica en la calibración.
  final String description;
  final Map<String, dynamic> payload;
  final Set<String> categories;

  /// Fracción del catálogo que es del tema (conteo del 16-nov-2026, 13,205 lugares). Un ranking al
  /// azar tendría en promedio esta proporción de lugares del tema.
  final double baseRate;

  const AffinityTheme({
    required this.id,
    required this.label,
    required this.description,
    required this.payload,
    required this.categories,
    required this.baseRate,
  });
}

Map<String, dynamic> _profile({
  List<String> cultural = const [],
  List<String> culinary = const [],
  List<String> atmosphere = const [],
  String companion = 'pareja',
  String time = 'tarde',
  String bio = '',
  String mood = '',
}) =>
    {
      'user_id': 'lab_affinity_validation',
      'cultural_interests': cultural,
      'culinary_interests': culinary,
      'atmosphere_preference': atmosphere,
      'social_companion': companion,
      'discovery_style': 'equilibrado',
      'preferred_time_window': time,
      'travel_pace': 'moderado',
      // Presupuesto alto y sin requisito de accesibilidad: así los filtros duros no se mezclan con la
      // afinidad (esos se prueban aparte).
      'budget_tier': 'alto',
      'transport_preference': 'caminata',
      'accessibility_needs': 'estandar',
      'free_bio': bio,
      'mood_override': mood,
      'alpha_fusion': 0.65,
    };

final kAffinityThemes = <AffinityTheme>[
  AffinityTheme(
    id: 'cultura',
    label: 'Cultura e historia',
    description: 'Le gustan los museos, las galerías, las zonas arqueológicas y la arquitectura histórica.',
    payload: _profile(
      cultural: ['museos_arte', 'arqueologia', 'arquitectura_virreinal'],
      atmosphere: ['historico', 'tranquilo_arbolado'],
      time: 'manana',
      bio: 'Museos, galerías de arte, zonas arqueológicas y arquitectura histórica.',
      mood: 'Aprender de historia y arte.',
    ),
    categories: {
      'museum', 'gallery', 'artwork', 'arts_centre', 'monument', 'historic', 'arqueologia', 'art', 'theatre', 'library', //
      'attraction',
    },
    baseRate: 0.138,
  ),
  AffinityTheme(
    id: 'noche',
    label: 'Noche y fiesta',
    description: 'Busca cantinas, pulquerías, bares y música en vivo de noche con amigos.',
    payload: _profile(
      cultural: ['musica_conciertos'],
      culinary: ['pulquerias', 'cantinas_tradicionales'],
      atmosphere: ['festivo_nocturno', 'vibrante_concurrido'],
      companion: 'amigos',
      time: 'noche',
      bio: 'Cantinas, pulquerías, bares y música en vivo de noche.',
      mood: 'Noche de fiesta con amigos.',
    ),
    categories: {'bar', 'pub', 'cantina', 'pulqueria', 'nightclub', 'biergarten', 'music_venue'},
    baseRate: 0.041,
  ),
  AffinityTheme(
    id: 'cafe',
    label: 'Café y panaderías',
    description: 'Le gusta el café de especialidad, las panaderías y los postres.',
    payload: _profile(
      culinary: ['cafeterias_especialidad', 'panaderias_clasicas'],
      atmosphere: ['bohemio', 'tranquilo_arbolado'],
      bio: 'Café de especialidad, panaderías clásicas y postres.',
      mood: 'Una tarde tranquila de café y pan dulce.',
    ),
    categories: {'cafe', 'coffee', 'bakery', 'pastry', 'ice_cream', 'bakery;pastry'},
    baseRate: 0.157,
  ),
  AffinityTheme(
    id: 'naturaleza',
    label: 'Naturaleza y aire libre',
    description: 'Prefiere parques, bosques, jardines y miradores al aire libre.',
    payload: _profile(
      cultural: ['parques_bosques'],
      atmosphere: ['tranquilo_arbolado'],
      companion: 'familia',
      time: 'manana',
      bio: 'Parques, bosques, jardines y miradores al aire libre.',
      mood: 'Una mañana al aire libre en familia.',
    ),
    categories: {'park', 'garden', 'nature_reserve', 'viewpoint', 'zoo', 'dog_park'},
    baseRate: 0.086,
  ),
];

AffinityTheme? themeById(String id) {
  for (final t in kAffinityThemes) {
    if (t.id == id) return t;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Métricas puras
// ---------------------------------------------------------------------------------------------

List<Map<String, dynamic>> rankedOf(Map<String, dynamic> response) =>
    ((response['ranked_pois'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

List<String> idsOf(List<Map<String, dynamic>> ranked) => ranked.map((p) => p['poi_id'].toString()).toList();

/// ¿El lugar es de alguna de [categories]? Hay categorías compuestas en el catálogo ("bakery;pastry").
bool inCategories(Map<String, dynamic> poi, Set<String> categories) {
  final raw = (poi['category'] ?? '').toString().toLowerCase();
  if (categories.contains(raw)) return true;
  return raw.split(RegExp(r'[;,]')).map((s) => s.trim()).any(categories.contains);
}

/// Fracción de [ranked] que es del tema.
double themePrecision(List<Map<String, dynamic>> ranked, Set<String> categories) {
  if (ranked.isEmpty) return 0;
  return ranked.where((p) => inCategories(p, categories)).length / ranked.length;
}

double jaccard(Iterable<String> a, Iterable<String> b) {
  final sa = a.toSet(), sb = b.toSet();
  final union = sa.union(sb);
  if (union.isEmpty) return 0;
  return sa.intersection(sb).length / union.length;
}

/// Cuántas listas contienen cada lugar.
Map<String, int> appearanceCounts(List<List<String>> lists) {
  final out = <String, int>{};
  for (final l in lists) {
    for (final id in l.toSet()) {
      out[id] = (out[id] ?? 0) + 1;
    }
  }
  return out;
}

/// Diferencia de puntaje entre el primero y el último del ranking.
double scoreSpread(List<Map<String, dynamic>> ranked) {
  final scores = ranked.map((p) => (p['match_score'] as num?)?.toDouble()).whereType<double>().toList();
  if (scores.length < 2) return 0;
  return scores.reduce(math.max) - scores.reduce(math.min);
}

/// Tope de presupuesto que aplicó el motor, leído de los motivos de descarte
/// ("Excede presupuesto por persona ($950 > $500 MXN)").
double? budgetLimitFrom(List<Map<String, dynamic>> filteredOut) {
  final re = RegExp(r'>\s*\$\s*([\d.,]+)');
  for (final f in filteredOut) {
    final m = re.firstMatch((f['filter_reason'] ?? '').toString());
    if (m != null) return double.tryParse(m.group(1)!.replaceAll(',', ''));
  }
  return null;
}

List<double> _ranks(List<double> v) {
  final idx = List<int>.generate(v.length, (i) => i)..sort((a, b) => v[a].compareTo(v[b]));
  final r = List<double>.filled(v.length, 0);
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
      j++;
    }
    final avg = (i + j) / 2 + 1; // empates: rango promedio
    for (var k = i; k <= j; k++) {
      r[idx[k]] = avg;
    }
    i = j + 1;
  }
  return r;
}

/// Correlación de rangos de Spearman (con empates). Null si no hay variación o menos de 3 pares.
double? spearman(List<double> x, List<double> y) {
  if (x.length != y.length || x.length < 3) return null;
  final rx = _ranks(x), ry = _ranks(y);
  final mx = rx.reduce((a, b) => a + b) / rx.length, my = ry.reduce((a, b) => a + b) / ry.length;
  var num = 0.0, dx = 0.0, dy = 0.0;
  for (var i = 0; i < rx.length; i++) {
    num += (rx[i] - mx) * (ry[i] - my);
    dx += (rx[i] - mx) * (rx[i] - mx);
    dy += (ry[i] - my) * (ry[i] - my);
  }
  if (dx == 0 || dy == 0) return null;
  return num / math.sqrt(dx * dy);
}

// ---------------------------------------------------------------------------------------------
// Pruebas automáticas
// ---------------------------------------------------------------------------------------------

const _kNoEngine = 'El motor no respondió';

/// Ejecuta todas las pruebas automáticas. [match] llama a `/v1/comparador/match-test`; si la
/// respuesta trae `_bytes` (tamaño del cuerpo) se usa para medir el peso de la respuesta.
///
/// [includeHeavy] incluye la prueba de accesibilidad, cuya respuesta pesa ~17 MB: en corridas
/// repetidas solo se hace una vez.
Future<List<AffinityCheck>> runAffinityChecks(
  MatchFn match, {
  void Function(String step)? onProgress,
  bool includeHeavy = true,
}) async {
  // Fuente del embedding de cada respuesta: cuando Vertex falla el motor usa un embedding de respaldo
  // sin significado y no lo avisa en ninguna otra parte.
  final sources = <String>[];
  Future<Map<String, dynamic>?> safe(Map<String, dynamic> payload) async {
    try {
      final r = await match(payload);
      sources.add((r['embedding_source'] ?? 'desconocida').toString());
      return r;
    } catch (_) {
      return null;
    }
  }

  onProgress?.call('Calculando los 4 perfiles temáticos…');
  final themed = await Future.wait(kAffinityThemes.map((t) => safe(t.payload)));
  final byTheme = {for (var i = 0; i < kAffinityThemes.length; i++) kAffinityThemes[i].id: themed[i]};
  final rankedBy = {for (final e in byTheme.entries) e.key: e.value == null ? null : rankedOf(e.value!)};

  // Lugares objetivo para "lugar conocido": el 6.º de cada perfil (no el primero, para no regalar la prueba).
  final targets = <String, Map<String, dynamic>>{};
  for (final t in kAffinityThemes) {
    final r = rankedBy[t.id];
    if (r == null || r.isEmpty) continue;
    final target = r[math.min(5, r.length - 1)];
    if ((target['semantic_description'] ?? '').toString().trim().isNotEmpty) targets[t.id] = target;
  }

  onProgress?.call('Probando sensibilidad, determinismo, restricciones y lugares conocidos…');
  final cafe = themeById('cafe')!, cultura = themeById('cultura')!;
  final variantPayload = {
    ...cafe.payload,
    'cultural_interests': [...(cafe.payload['cultural_interests'] as List), 'museos_arte', 'arqueologia'],
    'free_bio': '${cafe.payload['free_bio']} También me encantan los museos de arte y la historia.',
  };
  final extra = await Future.wait([
    safe(variantPayload),
    safe(cultura.payload),
    safe({...cultura.payload, 'budget_tier': 'economico'}),
    includeHeavy ? safe({...cultura.payload, 'accessibility_needs': 'accesibilidad_universal'}) : Future.value(null),
    for (final target in targets.values)
      safe({
        ..._profile(bio: target['semantic_description'].toString()),
        'alpha_fusion': 1.0,
      }),
  ]);
  final variant = extra[0], repeat = extra[1], budget = extra[2], access = extra[3];
  final knownItem = extra.sublist(4);

  final checks = <AffinityCheck>[];

  // 0. Fuente del embedding
  {
    const q = '¿Todas las respuestas usaron el modelo de embeddings real (Vertex AI)? Con el respaldo determinista '
        'el ranking no tiene relación con los gustos. Falla con una sola respuesta de respaldo.';
    final fallback = sources.where((s) => !s.startsWith('vertex')).toList();
    checks.add(AffinityCheck(
      id: 'embedding',
      title: 'Modelo de embeddings',
      question: q,
      result: sources.isEmpty
          ? _kNoEngine
          : (fallback.isEmpty
              ? 'Las ${sources.length} respuestas usaron Vertex AI'
              : '${fallback.length} de ${sources.length} respuestas usaron el respaldo (${fallback.toSet().join(', ')})'),
      status: sources.isNotEmpty && fallback.isEmpty ? CheckStatus.pass : CheckStatus.fail,
    ));
  }

  // 1. Coherencia temática
  for (final t in kAffinityThemes) {
    final r = rankedBy[t.id];
    final q = 'De los lugares que recomienda, ¿cuántos son del tema? Aprueba con 50 % o más '
        '(un ranking al azar daría ${(t.baseRate * 100).toStringAsFixed(0)} %).';
    if (r == null || r.isEmpty) {
      checks.add(AffinityCheck(
          id: 'coherencia_${t.id}', title: 'Coherencia: ${t.label}', question: q, result: _kNoEngine, status: CheckStatus.fail));
      continue;
    }
    final p = themePrecision(r, t.categories);
    final lift = t.baseRate > 0 ? p / t.baseRate : 0;
    checks.add(AffinityCheck(
      id: 'coherencia_${t.id}',
      title: 'Coherencia: ${t.label}',
      question: q,
      result: '${(p * 100).toStringAsFixed(0)} % del tema (${lift.toStringAsFixed(1)}× el azar)',
      status: p >= 0.5 ? CheckStatus.pass : (p >= 0.33 ? CheckStatus.warn : CheckStatus.fail),
      details: [
        for (final poi in r)
          '${inCategories(poi, t.categories) ? '✓' : '✗'} ${poi['name']} · ${poi['category']} · ${_score(poi)}',
      ],
    ));
  }

  // 2. Discriminación entre perfiles
  {
    const q = '¿Perfiles distintos reciben lugares distintos? Promedio de traslape (Jaccard) entre los 6 pares '
        'de perfiles: aprueba con 0.15 o menos.';
    final available = kAffinityThemes.where((t) => rankedBy[t.id]?.isNotEmpty ?? false).toList();
    if (available.length < 2) {
      checks.add(const AffinityCheck(
          id: 'discriminacion', title: 'Discriminación entre perfiles', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final pairs = <String>[];
      var sum = 0.0;
      var n = 0;
      for (var i = 0; i < available.length; i++) {
        for (var j = i + 1; j < available.length; j++) {
          final a = available[i], b = available[j];
          final jac = jaccard(idsOf(rankedBy[a.id]!), idsOf(rankedBy[b.id]!));
          sum += jac;
          n++;
          pairs.add('${a.label} vs ${b.label}: ${jac.toStringAsFixed(2)}');
        }
      }
      final mean = sum / n;
      checks.add(AffinityCheck(
        id: 'discriminacion',
        title: 'Discriminación entre perfiles',
        question: q,
        result: 'Traslape promedio ${mean.toStringAsFixed(2)}',
        status: mean <= 0.15 ? CheckStatus.pass : (mean <= 0.3 ? CheckStatus.warn : CheckStatus.fail),
        details: pairs,
      ));
    }
  }

  // 3. Lugares genéricos (salen para cualquiera)
  {
    const q = '¿Hay lugares que aparecen sin importar el perfil? Falla si alguno sale en 3 o más de los 4 perfiles; '
        'avisa si sale en 2 perfiles que no comparten tema.';
    final lists = [for (final t in kAffinityThemes) if (rankedBy[t.id] != null) idsOf(rankedBy[t.id]!)];
    if (lists.length < 3) {
      checks.add(const AffinityCheck(
          id: 'genericos', title: 'Lugares genéricos', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final counts = appearanceCounts(lists);
      final names = <String, String>{};
      final themesOf = <String, List<String>>{};
      for (final t in kAffinityThemes) {
        for (final p in rankedBy[t.id] ?? const <Map<String, dynamic>>[]) {
          names[p['poi_id'].toString()] = '${p['name']} · ${p['category']}';
          themesOf.putIfAbsent(p['poi_id'].toString(), () => []).add(t.label);
        }
      }
      final hubs = counts.entries.where((e) => e.value >= 3).map((e) => e.key).toList();
      final shared = counts.entries.where((e) => e.value == 2).map((e) => e.key).toList();
      checks.add(AffinityCheck(
        id: 'genericos',
        title: 'Lugares genéricos',
        question: q,
        result: hubs.isNotEmpty
            ? '${hubs.length} lugar(es) salen en 3+ perfiles'
            : shared.isNotEmpty
                ? '${shared.length} lugar(es) compartidos por 2 perfiles'
                : 'Ningún lugar se repite entre perfiles',
        status: hubs.isNotEmpty ? CheckStatus.fail : (shared.isNotEmpty ? CheckStatus.warn : CheckStatus.pass),
        details: [
          for (final id in [...hubs, ...shared]) '${names[id]} → ${themesOf[id]!.join(', ')}',
        ],
      ));
    }
  }

  // 4. Sensibilidad: agregar "museos" a un perfil de café debe traer más cultura
  {
    const q = 'Si a un perfil de café se le agregan museos e historia, ¿suben los lugares de cultura? '
        'Aprueba si su proporción aumenta.';
    final before = rankedBy['cafe'];
    if (before == null || variant == null) {
      checks.add(const AffinityCheck(
          id: 'sensibilidad', title: 'Sensibilidad a los gustos', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final after = rankedOf(variant);
      final pb = themePrecision(before, cultura.categories), pa = themePrecision(after, cultura.categories);
      checks.add(AffinityCheck(
        id: 'sensibilidad',
        title: 'Sensibilidad a los gustos',
        question: q,
        result: 'Cultura: ${(pb * 100).toStringAsFixed(0)} % → ${(pa * 100).toStringAsFixed(0)} %',
        status: pa > pb ? CheckStatus.pass : (pa == pb ? CheckStatus.warn : CheckStatus.fail),
        details: [
          for (final p in after) '${inCategories(p, cultura.categories) ? '✓' : ' '} ${p['name']} · ${p['category']}',
        ],
      ));
    }
  }

  // 5. Determinismo
  {
    const q = '¿El mismo perfil da el mismo resultado dos veces? Aprueba si el orden es idéntico y los puntajes '
        'varían menos de 0.001.';
    final first = rankedBy['cultura'];
    if (first == null || repeat == null) {
      checks.add(const AffinityCheck(
          id: 'determinismo', title: 'Determinismo', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final second = rankedOf(repeat);
      final sameOrder = idsOf(first).join('|') == idsOf(second).join('|');
      var maxDiff = 0.0;
      for (var i = 0; i < math.min(first.length, second.length); i++) {
        final a = (first[i]['match_score'] as num?)?.toDouble() ?? 0, b = (second[i]['match_score'] as num?)?.toDouble() ?? 0;
        maxDiff = math.max(maxDiff, (a - b).abs());
      }
      final ok = sameOrder && maxDiff < 0.001;
      checks.add(AffinityCheck(
        id: 'determinismo',
        title: 'Determinismo',
        question: q,
        result: ok ? 'Idéntico' : (sameOrder ? 'Mismo orden, puntajes varían ${maxDiff.toStringAsFixed(4)}' : 'El orden cambió'),
        status: ok ? CheckStatus.pass : (sameOrder ? CheckStatus.warn : CheckStatus.fail),
      ));
    }
  }

  // 6. Recuperación de un lugar conocido
  {
    const q = 'Si alguien describe exactamente un lugar, ¿el sistema lo encuentra? Con la descripción de un lugar como '
        'único gusto, ese lugar debe quedar entre los 3 primeros. Aprueba si pasa en 3 de cada 4 casos o más.';
    if (targets.isEmpty) {
      checks.add(const AffinityCheck(
          id: 'lugar_conocido', title: 'Recuperación de un lugar conocido', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      var hits = 0;
      final details = <String>[];
      final entries = targets.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final target = entries[i].value;
        final resp = knownItem[i];
        final ids = resp == null ? const <String>[] : idsOf(rankedOf(resp));
        final pos = ids.indexOf(target['poi_id'].toString());
        if (pos >= 0 && pos < 3) hits++;
        details.add('${target['name']}: ${resp == null ? _kNoEngine : (pos < 0 ? 'no aparece en el top ${ids.length}' : 'posición ${pos + 1}')}');
      }
      final rate = hits / entries.length;
      checks.add(AffinityCheck(
        id: 'lugar_conocido',
        title: 'Recuperación de un lugar conocido',
        question: q,
        result: '$hits de ${entries.length} entre los 3 primeros',
        status: rate >= 0.75 ? CheckStatus.pass : (rate >= 0.5 ? CheckStatus.warn : CheckStatus.fail),
        details: details,
      ));
    }
  }

  // 7. Resolución del puntaje
  {
    const q = '¿El puntaje separa al mejor del 12.º lo suficiente para que el porcentaje signifique algo? '
        'Aprueba con 0.05 o más de diferencia promedio; avisa entre 0.02 y 0.05.';
    final spreads = [
      for (final t in kAffinityThemes)
        if (rankedBy[t.id]?.isNotEmpty ?? false) (t.label, scoreSpread(rankedBy[t.id]!), rankedBy[t.id]!),
    ];
    if (spreads.isEmpty) {
      checks.add(const AffinityCheck(
          id: 'resolucion', title: 'Resolución del puntaje', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final mean = spreads.map((s) => s.$2).reduce((a, b) => a + b) / spreads.length;
      checks.add(AffinityCheck(
        id: 'resolucion',
        title: 'Resolución del puntaje',
        question: q,
        result: 'Diferencia promedio ${mean.toStringAsFixed(3)} entre el 1.º y el último',
        status: mean >= 0.05 ? CheckStatus.pass : (mean >= 0.02 ? CheckStatus.warn : CheckStatus.fail),
        details: [
          for (final s in spreads)
            '${s.$1}: ${_score(s.$3.first)} → ${_score(s.$3.last)} (${s.$2.toStringAsFixed(3)})',
        ],
      ));
    }
  }

  // 8. Presupuesto
  {
    const q = 'Con presupuesto económico, ¿algún lugar recomendado excede el tope? Falla con uno solo.';
    if (budget == null) {
      checks.add(const AffinityCheck(
          id: 'presupuesto', title: 'Respeta el presupuesto', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final ranked = rankedOf(budget);
      final filtered = ((budget['filtered_out_pois'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final limit = budgetLimitFrom(filtered);
      final over = limit == null
          ? const <Map<String, dynamic>>[]
          : ranked.where((p) => ((p['price_mxn'] as num?)?.toDouble() ?? 0) > limit).toList();
      checks.add(AffinityCheck(
        id: 'presupuesto',
        title: 'Respeta el presupuesto',
        question: q,
        result: limit == null
            ? 'No se pudo leer el tope (ningún lugar fue descartado por precio)'
            : (over.isEmpty
                ? 'Todos dentro del tope de \$${limit.toStringAsFixed(0)} MXN'
                : '${over.length} lugar(es) exceden \$${limit.toStringAsFixed(0)} MXN'),
        status: limit == null ? CheckStatus.warn : (over.isEmpty ? CheckStatus.pass : CheckStatus.fail),
        details: [for (final p in over) '${p['name']}: \$${p['price_mxn']}'],
      ));
    }
  }

  // 9. Accesibilidad (y el peso de la respuesta)
  if (includeHeavy) {
    const q = 'Con accesibilidad universal, ¿todos los lugares recomendados tienen accesibilidad? Falla con uno solo.';
    if (access == null) {
      checks.add(const AffinityCheck(
          id: 'accesibilidad', title: 'Respeta la accesibilidad', question: q, result: _kNoEngine, status: CheckStatus.fail));
    } else {
      final ranked = rankedOf(access);
      final bad = ranked.where((p) => p['wheelchair_accessible'] != true).toList();
      checks.add(AffinityCheck(
        id: 'accesibilidad',
        title: 'Respeta la accesibilidad',
        question: q,
        result: ranked.isEmpty
            ? 'No quedó ningún lugar'
            : (bad.isEmpty ? 'Los ${ranked.length} lugares tienen accesibilidad' : '${bad.length} sin accesibilidad'),
        status: ranked.isEmpty ? CheckStatus.warn : (bad.isEmpty ? CheckStatus.pass : CheckStatus.fail),
        details: [for (final p in bad) '${p['name']} · ${p['category']}'],
      ));
      final bytes = (access['_bytes'] as num?)?.toInt();
      if (bytes != null) {
        final mb = bytes / (1024 * 1024);
        final filteredCount = ((access['filtered_out_pois'] as List?) ?? const []).length;
        checks.add(AffinityCheck(
          id: 'peso_respuesta',
          title: 'Peso de la respuesta',
          question: '¿La respuesta del Comparador es ligera para un teléfono? Avisa sobre 1 MB; falla sobre 5 MB.',
          result: '${mb.toStringAsFixed(1)} MB con accesibilidad universal ($filteredCount lugares descartados incluidos)',
          status: mb <= 1 ? CheckStatus.pass : (mb <= 5 ? CheckStatus.warn : CheckStatus.fail),
        ));
      }
    }
  }

  return checks;
}

const _severity = {CheckStatus.pass: 0, CheckStatus.warn: 1, CheckStatus.fail: 2};

/// Une varias corridas de la misma batería. Una prueba que dio lo mismo en todas conserva su
/// resultado; una que cambió entre corridas queda como aviso "inestable" (una sola corrida no
/// basta para concluir nada de ella) con el resultado de cada corrida en el detalle.
List<AffinityCheck> mergeRuns(List<List<AffinityCheck>> runs) {
  if (runs.isEmpty) return const [];
  if (runs.length == 1) return runs.first;
  final order = <String>[];
  final byId = <String, List<AffinityCheck?>>{};
  for (var r = 0; r < runs.length; r++) {
    for (final c in runs[r]) {
      if (!byId.containsKey(c.id)) {
        order.add(c.id);
        byId[c.id] = List<AffinityCheck?>.filled(runs.length, null);
      }
      byId[c.id]![r] = c;
    }
  }
  return [
    for (final id in order)
      () {
        final all = byId[id]!;
        final present = all.whereType<AffinityCheck>().toList();
        final first = present.first;
        if (present.length == 1) return first;
        final statuses = present.map((c) => c.status).toSet();
        final passes = present.where((c) => c.status == CheckStatus.pass).length;
        final runLines = [
          for (var r = 0; r < all.length; r++)
            if (all[r] != null) 'Corrida ${r + 1}: ${all[r]!.status.name.toUpperCase()} · ${all[r]!.result}',
        ];
        if (statuses.length == 1) {
          return AffinityCheck(
            id: id,
            title: first.title,
            question: first.question,
            result: '${first.result} · igual en ${present.length} corridas',
            status: first.status,
            details: [...runLines, ...present.last.details],
          );
        }
        // Inestable: nunca cuenta como aprobada; si alguna corrida falló, se mantiene la falla más visible.
        final worst = present.map((c) => c.status).reduce((a, b) => _severity[a]! >= _severity[b]! ? a : b);
        return AffinityCheck(
          id: id,
          title: first.title,
          question: first.question,
          result: 'Inestable: aprobó $passes de ${present.length} corridas',
          status: worst == CheckStatus.fail && passes == 0 ? CheckStatus.fail : CheckStatus.warn,
          details: [...runLines, ...present.last.details],
          unstable: true,
        );
      }(),
  ];
}

/// Corre la batería [times] veces (la prueba pesada solo en la primera) y une los resultados.
Future<List<AffinityCheck>> runAffinityChecksRepeated(
  MatchFn match, {
  int times = 3,
  void Function(String step)? onProgress,
}) async {
  final runs = <List<AffinityCheck>>[];
  for (var i = 0; i < times; i++) {
    runs.add(await runAffinityChecks(
      match,
      includeHeavy: i == 0,
      onProgress: (s) => onProgress?.call(times > 1 ? 'Corrida ${i + 1} de $times · $s' : s),
    ));
  }
  return mergeRuns(runs);
}

enum VerdictLevel { reliable, caveats, unreliable }

class AffinityVerdict {
  final VerdictLevel level;
  final String headline;
  final String explanation;
  const AffinityVerdict(this.level, this.headline, this.explanation);
}

/// Pruebas sin las cuales el puntaje no significa lo que dice: si una falla, no es confiable.
const kCriticalChecks = {'embedding', 'discriminacion', 'determinismo', 'presupuesto', 'accesibilidad', 'lugar_conocido'};

bool _isCritical(String id) => kCriticalChecks.contains(id) || id.startsWith('coherencia_');

/// Veredicto en una frase a partir de las pruebas.
AffinityVerdict verdictOf(List<AffinityCheck> checks) {
  final fails = checks.where((c) => c.status == CheckStatus.fail).toList();
  // Una prueba esencial que cambia entre corridas tampoco da certeza: cuenta como no confiable.
  final criticalBad = checks.where((c) => _isCritical(c.id) && (c.status == CheckStatus.fail || c.unstable)).toList();
  final warns = checks.where((c) => c.status == CheckStatus.warn).toList();
  String names(List<AffinityCheck> l) => l.map((c) => c.unstable ? '${c.title} (inestable)' : c.title).join(', ');
  if (criticalBad.isNotEmpty) {
    return AffinityVerdict(
      VerdictLevel.unreliable,
      'Todavía no es confiable',
      'No pasan pruebas esenciales: ${names(criticalBad)}. Mientras sea así, el porcentaje de afinidad no '
          'debería presentarse como una medida.',
    );
  }
  if (fails.isNotEmpty || warns.isNotEmpty) {
    final parts = [
      if (fails.isNotEmpty) 'fallan ${names(fails)}',
      if (warns.isNotEmpty) '${warns.length} prueba(s) quedaron con aviso',
    ];
    return AffinityVerdict(
      VerdictLevel.caveats,
      'Confiable con reservas',
      'Las pruebas esenciales pasan, pero ${parts.join(' y ')}.',
    );
  }
  return const AffinityVerdict(
    VerdictLevel.reliable,
    'Confiable',
    'Todas las pruebas pasaron. Falta confirmarlo con la calibración con personas.',
  );
}

String _score(Map<String, dynamic> poi) => ((poi['match_score'] as num?)?.toDouble() ?? 0).toStringAsFixed(3);

// ---------------------------------------------------------------------------------------------
// Calibración con personas
// ---------------------------------------------------------------------------------------------

const kCalibrationStudyId = 'afinidad';
const kCalibrationPerSource = 6;

/// ID determinista: una calibración por persona y perfil (las reglas solo permiten crear).
String calibrationResponseId(String uid, String themeId) => 'afi_${uid}_$themeId';

/// Un lugar por calificar: del sistema (con su posición en el ranking) o de la línea base al azar.
class CalibrationItem {
  final Map<String, dynamic> poi;
  final String source; // 'sistema' | 'base'
  final int rank; // posición en el ranking del sistema (1…); 0 para la línea base

  const CalibrationItem({required this.poi, required this.source, required this.rank});

  String get id => poi['poi_id'].toString();
}

/// Arma la lista a ciegas: los primeros [perSource] del sistema y [perSource] lugares al azar del
/// [catalog] que no estén en el ranking, todos barajados.
List<CalibrationItem> buildCalibrationItems(
  List<Map<String, dynamic>> ranked,
  List<Map<String, dynamic>> catalog,
  math.Random rng, {
  int perSource = kCalibrationPerSource,
}) {
  final system = <CalibrationItem>[
    for (var i = 0; i < math.min(perSource, ranked.length); i++) CalibrationItem(poi: ranked[i], source: 'sistema', rank: i + 1),
  ];
  final exclude = idsOf(ranked).toSet();
  final pool = catalog.where((p) => p['poi_id'] != null && !exclude.contains(p['poi_id'].toString())).toList()..shuffle(rng);
  final base = [for (final p in pool.take(perSource)) CalibrationItem(poi: p, source: 'base', rank: 0)];
  return [...system, ...base]..shuffle(rng);
}

class CalibrationSummary {
  final int sessions;
  final double? meanSystem;
  final double? meanBase;

  /// Fracción calificada con 4 o 5.
  final double? relevantSystem;
  final double? relevantBase;

  /// Sesiones donde el promedio del sistema superó / empató / quedó debajo del azar.
  final int wins;
  final int ties;
  final int losses;

  /// Spearman entre la posición en el ranking (invertida: 1.º = más alto) y la calificación, sobre
  /// todos los lugares del sistema. Positivo = el orden del sistema coincide con el de las personas.
  final double? rankCorrelation;

  /// Ventaja de cada sesión: promedio del sistema − promedio del azar.
  final List<double> sessionLifts;

  const CalibrationSummary({
    required this.sessions,
    this.meanSystem,
    this.meanBase,
    this.relevantSystem,
    this.relevantBase,
    this.wins = 0,
    this.ties = 0,
    this.losses = 0,
    this.rankCorrelation,
    this.sessionLifts = const [],
  });

  /// ¿Le gana al azar? Diferencia de promedios (sistema − azar) en la escala 1–5.
  double? get lift => meanSystem == null || meanBase == null ? null : meanSystem! - meanBase!;

  /// Prueba de signos (bilateral) sobre las sesiones no empatadas: probabilidad de ver un reparto de
  /// victorias tan desigual si el sistema no fuera mejor ni peor que el azar.
  double? get signTestP => signTestPValue(wins, losses);

  /// Intervalo de confianza del 95 % de la ventaja media por sesión (bootstrap).
  (double, double)? get liftCi95 => bootstrapMeanCi(sessionLifts);

  /// ¿Hay evidencia de que el sistema le gana al azar? (p < 0.05 y el intervalo no toca el 0).
  bool get beatsRandom {
    final p = signTestP, ci = liftCi95;
    return p != null && p < 0.05 && wins > losses && ci != null && ci.$1 > 0;
  }
}

/// Prueba de signos exacta, bilateral. Null sin sesiones decisivas.
double? signTestPValue(int wins, int losses) {
  final n = wins + losses;
  if (n == 0) return null;
  final k = math.min(wins, losses);
  // P(X <= k) con X ~ Binomial(n, 1/2), en logaritmos para no desbordar.
  var logC = 0.0; // log C(n, 0)
  var tail = 0.0;
  for (var i = 0; i <= k; i++) {
    if (i > 0) logC += math.log((n - i + 1) / i);
    tail += math.exp(logC - n * math.ln2);
  }
  return math.min(1.0, 2 * tail);
}

/// Intervalo de confianza del 95 % de la media por bootstrap de percentiles (semilla fija, para que
/// el mismo conjunto de respuestas dé siempre el mismo intervalo). Null con menos de 3 valores.
(double, double)? bootstrapMeanCi(List<double> values, {int iterations = 2000, int seed = 7}) {
  if (values.length < 3) return null;
  final rng = math.Random(seed);
  final means = List<double>.generate(iterations, (_) {
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      sum += values[rng.nextInt(values.length)];
    }
    return sum / values.length;
  })
    ..sort();
  return (means[(iterations * 0.025).floor()], means[(iterations * 0.975).ceil() - 1]);
}

// fold y no reduce: con una List<int> el reduce de (num, num) => num falla en la web.
double? _mean(List<num> v) => v.isEmpty ? null : v.fold<double>(0, (a, b) => a + b) / v.length;

/// Resume respuestas guardadas con `sources`, `ranks` y `grades` (listas paralelas).
CalibrationSummary summarizeCalibration(Iterable<Map<String, dynamic>> responses) {
  final sys = <int>[], base = <int>[];
  final rankX = <double>[], gradeY = <double>[];
  var sessions = 0, wins = 0, ties = 0, losses = 0;
  final lifts = <double>[];
  for (final r in responses) {
    final sources = (r['sources'] as List?)?.map((e) => e.toString()).toList();
    final grades = (r['grades'] as List?)?.map((e) => (e as num).toInt()).toList();
    final ranks = (r['ranks'] as List?)?.map((e) => (e as num).toInt()).toList();
    if (sources == null || grades == null || sources.length != grades.length) continue;
    sessions++;
    final s = <int>[], b = <int>[];
    for (var i = 0; i < grades.length; i++) {
      if (sources[i] == 'sistema') {
        s.add(grades[i]);
        if (ranks != null && i < ranks.length && ranks[i] > 0) {
          rankX.add(-ranks[i].toDouble());
          gradeY.add(grades[i].toDouble());
        }
      } else {
        b.add(grades[i]);
      }
    }
    sys.addAll(s);
    base.addAll(b);
    final ms = _mean(s), mb = _mean(b);
    if (ms != null && mb != null) {
      lifts.add(ms - mb);
      if (ms > mb) {
        wins++;
      } else if (ms == mb) {
        ties++;
      } else {
        losses++;
      }
    }
  }
  double? relevant(List<int> g) => g.isEmpty ? null : g.where((x) => x >= 4).length / g.length;
  return CalibrationSummary(
    sessions: sessions,
    meanSystem: _mean(sys),
    meanBase: _mean(base),
    relevantSystem: relevant(sys),
    relevantBase: relevant(base),
    wins: wins,
    ties: ties,
    losses: losses,
    rankCorrelation: spearman(rankX, gradeY),
    sessionLifts: lifts,
  );
}

/// Un resumen por perfil (`profileId`), en el orden de [kAffinityThemes].
Map<String, CalibrationSummary> summarizeCalibrationByProfile(Iterable<Map<String, dynamic>> responses) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final r in responses) {
    groups.putIfAbsent((r['profileId'] ?? '').toString(), () => []).add(r);
  }
  return {
    for (final t in kAffinityThemes)
      if (groups.containsKey(t.id)) t.id: summarizeCalibration(groups[t.id]!),
  };
}
