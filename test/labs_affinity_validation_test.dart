import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/affinity_validation.dart';

Map<String, dynamic> _poi(String id, String category, double score, {double price = 100, bool wc = true, String desc = ''}) => {
      'poi_id': id,
      'name': 'Lugar $id',
      'category': category,
      'match_score': score,
      'price_mxn': price,
      'wheelchair_accessible': wc,
      'semantic_description': desc.isEmpty ? '[EJE 1 - X]: descripción de $id' : desc,
    };

/// Motor simulado "bueno": cada tema devuelve 12 lugares propios y del tema, con buena separación;
/// respeta presupuesto y accesibilidad, y recupera el lugar cuya descripción se le da.
Future<Map<String, dynamic>> _goodEngine(Map<String, dynamic> p) async {
  final bio = (p['free_bio'] ?? '').toString();
  final known = RegExp(r'descripción de (\w+)').firstMatch(bio);
  if (known != null) {
    return {
      'ranked_pois': [_poi(known.group(1)!, 'museum', 0.9), for (var i = 0; i < 11; i++) _poi('x$i', 'museum', 0.8 - i * 0.01)],
      'embedding_source': 'vertex_ai_text_embedding_004',
    };
  }
  final cultural = (p['cultural_interests'] as List).cast<String>();
  final culinary = (p['culinary_interests'] as List).cast<String>();
  final (prefix, cats) = cultural.contains('parques_bosques')
      ? ('nat', ['park', 'garden'])
      : culinary.contains('pulquerias')
          ? ('noc', ['bar', 'cantina'])
          : culinary.contains('cafeterias_especialidad')
              ? ('caf', ['cafe', 'bakery'])
              : ('cul', ['museum', 'gallery']);
  final ranked = [for (var i = 0; i < 12; i++) _poi('$prefix$i', cats[i % 2], 0.9 - i * 0.01)];
  // Al perfil de café con museos se le cuelan lugares de cultura.
  if (prefix == 'caf' && cultural.contains('museos_arte')) {
    ranked[10] = _poi('cul0', 'museum', 0.8);
    ranked[11] = _poi('cul1', 'gallery', 0.79);
  }
  final out = <String, dynamic>{
    'ranked_pois': ranked,
    'filtered_out_pois': <Map<String, dynamic>>[],
    'embedding_source': 'vertex_ai_text_embedding_004',
  };
  if (p['budget_tier'] == 'economico') {
    out['filtered_out_pois'] = [
      {'name': 'Caro', 'filter_reason': r'Excede presupuesto por persona ($950 > $250 MXN)'},
    ];
  }
  if (p['accessibility_needs'] == 'accesibilidad_universal') out['_bytes'] = 300 * 1024;
  return out;
}

void main() {
  group('métricas', () {
    test('categorías compuestas cuentan', () {
      expect(inCategories({'category': 'bakery;pastry'}, {'pastry'}), isTrue);
      expect(inCategories({'category': 'restaurant'}, {'cafe'}), isFalse);
    });

    test('precisión temática y Jaccard', () {
      final r = [_poi('a', 'museum', 1), _poi('b', 'cafe', 1), _poi('c', 'gallery', 1), _poi('d', 'bar', 1)];
      expect(themePrecision(r, {'museum', 'gallery'}), 0.5);
      expect(jaccard(['a', 'b'], ['b', 'c']), closeTo(1 / 3, 1e-9));
      expect(jaccard(<String>[], <String>[]), 0);
    });

    test('tope de presupuesto desde el motivo de descarte', () {
      expect(budgetLimitFrom([{'filter_reason': r'Excede presupuesto por persona ($950 > $500 MXN)'}]), 500);
      expect(budgetLimitFrom([{'filter_reason': 'Sin rampa'}]), isNull);
    });

    test('Spearman con empates', () {
      expect(spearman([1, 2, 3, 4], [10, 20, 30, 40]), closeTo(1, 1e-9));
      expect(spearman([1, 2, 3, 4], [4, 3, 2, 1]), closeTo(-1, 1e-9));
      expect(spearman([1, 1, 1], [1, 2, 3]), isNull);
      expect(spearman([1, 2], [1, 2]), isNull);
    });
  });

  group('pruebas automáticas', () {
    test('un motor que funciona aprueba todo', () async {
      final checks = await runAffinityChecks(_goodEngine);
      final failing = checks.where((c) => c.status != CheckStatus.pass).map((c) => '${c.id}: ${c.result}').toList();
      expect(failing, isEmpty);
      expect(checks.map((c) => c.id), containsAll(['discriminacion', 'genericos', 'sensibilidad', 'determinismo', 'lugar_conocido']));
    });

    test('un motor que da lo mismo a todos falla discriminación y genéricos', () async {
      Future<Map<String, dynamic>> same(Map<String, dynamic> p) async =>
          {'ranked_pois': [for (var i = 0; i < 12; i++) _poi('g$i', 'restaurant', 0.75 - i * 0.001)]};
      final byId = {for (final c in await runAffinityChecks(same)) c.id: c};
      expect(byId['discriminacion']!.status, CheckStatus.fail);
      expect(byId['genericos']!.status, CheckStatus.fail);
      expect(byId['coherencia_cultura']!.status, CheckStatus.fail);
      expect(byId['resolucion']!.status, CheckStatus.fail);
    });

    test('un motor caído marca todo como fallido sin lanzar error', () async {
      final checks = await runAffinityChecks((_) async => throw Exception('caído'));
      expect(checks, isNotEmpty);
      expect(checks.every((c) => c.status == CheckStatus.fail), isTrue);
    });

    test('detecta presupuesto y accesibilidad violados', () async {
      Future<Map<String, dynamic>> bad(Map<String, dynamic> p) async {
        final base = await _goodEngine(p);
        if (p['budget_tier'] == 'economico') (base['ranked_pois'] as List)[0] = _poi('caro', 'museum', 0.9, price: 900);
        if (p['accessibility_needs'] == 'accesibilidad_universal') {
          (base['ranked_pois'] as List)[0] = _poi('escalera', 'museum', 0.9, wc: false);
          base['_bytes'] = 17 * 1024 * 1024;
        }
        return base;
      }

      final byId = {for (final c in await runAffinityChecks(bad)) c.id: c};
      expect(byId['presupuesto']!.status, CheckStatus.fail);
      expect(byId['accesibilidad']!.status, CheckStatus.fail);
      expect(byId['peso_respuesta']!.status, CheckStatus.fail);
    });
  });

  group('calibración', () {
    test('mezcla 6 del sistema y 6 al azar sin repetir lugares del ranking', () {
      final ranked = [for (var i = 0; i < 12; i++) _poi('s$i', 'museum', 0.9)];
      final catalog = [
        for (var i = 0; i < 12; i++) _poi('s$i', 'museum', 0),
        for (var i = 0; i < 30; i++) _poi('c$i', 'park', 0),
      ];
      final items = buildCalibrationItems(ranked, catalog, math.Random(1));
      expect(items, hasLength(12));
      expect(items.where((i) => i.source == 'sistema').map((i) => i.rank).toSet(), {1, 2, 3, 4, 5, 6});
      final base = items.where((i) => i.source == 'base');
      expect(base, hasLength(6));
      expect(base.every((i) => i.id.startsWith('c') && i.rank == 0), isTrue);
    });

    test('resumen: sistema contra azar y correlación de posición', () {
      final responses = [
        {
          'sources': ['sistema', 'sistema', 'sistema', 'base', 'base', 'base'],
          'ranks': [1, 2, 3, 0, 0, 0],
          'grades': [5, 4, 3, 2, 1, 2],
        },
        {
          'sources': ['sistema', 'base', 'sistema', 'base'],
          'ranks': [1, 0, 2, 0],
          'grades': [3, 3, 3, 3],
        },
        {'sources': ['sistema'], 'grades': [5, 4]}, // mal formada: se ignora
      ];
      final s = summarizeCalibration(responses);
      expect(s.sessions, 2);
      expect(s.wins, 1);
      expect(s.ties, 1);
      expect(s.losses, 0);
      expect(s.meanSystem, closeTo((5 + 4 + 3 + 3 + 3) / 5, 1e-9));
      expect(s.meanBase, closeTo((2 + 1 + 2 + 3 + 3) / 5, 1e-9));
      expect(s.lift, greaterThan(0));
      expect(s.relevantSystem, closeTo(2 / 5, 1e-9));
      expect(s.rankCorrelation, greaterThan(0));
    });

    test('ID de respuesta determinista por persona y perfil', () {
      expect(calibrationResponseId('u1', 'cafe'), 'afi_u1_cafe');
    });
  });

  group('corridas repetidas y veredicto', () {
    AffinityCheck c(String id, CheckStatus st, [String r = 'r']) =>
        AffinityCheck(id: id, title: id, question: 'q', result: r, status: st);

    test('una prueba que cambia entre corridas queda como inestable y nunca aprobada', () {
      final merged = mergeRuns([
        [c('a', CheckStatus.pass), c('b', CheckStatus.fail), c('d', CheckStatus.warn)],
        [c('a', CheckStatus.pass), c('b', CheckStatus.pass), c('d', CheckStatus.fail)],
        [c('a', CheckStatus.pass), c('b', CheckStatus.pass), c('d', CheckStatus.fail)],
      ]);
      final byId = {for (final m in merged) m.id: m};
      expect(byId['a']!.status, CheckStatus.pass);
      expect(byId['a']!.unstable, isFalse);
      expect(byId['a']!.result, contains('igual en 3 corridas'));
      expect(byId['b']!.status, CheckStatus.warn);
      expect(byId['b']!.unstable, isTrue);
      expect(byId['b']!.result, 'Inestable: aprobó 2 de 3 corridas');
      // Sin ninguna corrida aprobada, la mezcla de aviso y falla se queda como falla.
      expect(byId['d']!.status, CheckStatus.fail);
    });

    test('una prueba que solo corrió una vez (la pesada) se conserva tal cual', () {
      final merged = mergeRuns([
        [c('a', CheckStatus.pass), c('peso', CheckStatus.fail, '17 MB')],
        [c('a', CheckStatus.pass)],
      ]);
      expect(merged.map((m) => m.id), ['a', 'peso']);
      expect(merged.last.result, '17 MB');
    });

    test('las corridas repetidas solo hacen la prueba pesada una vez', () async {
      var heavy = 0;
      Future<Map<String, dynamic>> counting(Map<String, dynamic> p) {
        if (p['accessibility_needs'] == 'accesibilidad_universal') heavy++;
        return _goodEngine(p);
      }

      final merged = await runAffinityChecksRepeated(counting, times: 3);
      expect(heavy, 1);
      expect(merged.where((m) => m.unstable), isEmpty);
      expect(verdictOf(merged).level, VerdictLevel.reliable);
    });

    test('detecta respuestas con el embedding de respaldo', () async {
      var n = 0;
      Future<Map<String, dynamic>> flaky(Map<String, dynamic> p) async {
        final r = await _goodEngine(p);
        if (n++ == 2) r['embedding_source'] = 'deterministic_4axis_768d';
        return r;
      }

      final checks = await runAffinityChecks(flaky);
      final emb = checks.firstWhere((c) => c.id == 'embedding');
      expect(emb.status, CheckStatus.fail);
      expect(emb.result, contains('1 de'));
      expect(verdictOf(checks).level, VerdictLevel.unreliable);
    });

    test('veredicto', () {
      final unstableCritical = AffinityCheck(
          id: 'determinismo', title: 'Determinismo', question: 'q', result: 'r', status: CheckStatus.warn, unstable: true);
      expect(verdictOf([unstableCritical]).level, VerdictLevel.unreliable);
      expect(verdictOf([c('discriminacion', CheckStatus.fail)]).level, VerdictLevel.unreliable);
      expect(verdictOf([c('coherencia_cafe', CheckStatus.fail)]).level, VerdictLevel.unreliable);
      // Fallas no esenciales (peso de la respuesta, lugares genéricos): confiable con reservas.
      expect(verdictOf([c('discriminacion', CheckStatus.pass), c('peso_respuesta', CheckStatus.fail)]).level,
          VerdictLevel.caveats);
      expect(verdictOf([c('discriminacion', CheckStatus.pass)]).level, VerdictLevel.reliable);
    });
  });

  group('estadística de la calibración', () {
    test('prueba de signos exacta', () {
      expect(signTestPValue(10, 0), closeTo(2 / 1024, 1e-12));
      expect(signTestPValue(5, 5), 1.0);
      expect(signTestPValue(8, 2), closeTo(0.109375, 1e-9));
      expect(signTestPValue(0, 0), isNull);
      // n grande sin desbordar
      expect(signTestPValue(300, 200), lessThan(0.001));
    });

    test('intervalo bootstrap: determinista y alrededor de la media', () {
      final v = [1.0, 2.0, 3.0, 2.0, 1.5, 2.5, 2.0, 3.0];
      final a = bootstrapMeanCi(v)!, b = bootstrapMeanCi(v)!;
      expect(a, b);
      final mean = v.reduce((x, y) => x + y) / v.length;
      expect(a.$1, lessThan(mean));
      expect(a.$2, greaterThan(mean));
      expect(bootstrapMeanCi([1.0, 2.0]), isNull);
    });

    Map<String, dynamic> session(String profile, List<int> sys, List<int> base) => {
          'profileId': profile,
          'sources': [...sys.map((_) => 'sistema'), ...base.map((_) => 'base')],
          'ranks': [for (var i = 0; i < sys.length; i++) i + 1, ...base.map((_) => 0)],
          'grades': [...sys, ...base],
        };

    test('evidencia de que supera al azar y desglose por perfil', () {
      final responses = [
        for (var i = 0; i < 8; i++) session('cultura', [5, 4, 4], [2, 1, 2]),
        for (var i = 0; i < 3; i++) session('noche', [2, 2, 3], [3, 3, 2]),
      ];
      final all = summarizeCalibration(responses);
      expect(all.wins, 8);
      expect(all.losses, 3);
      expect(all.beatsRandom, isFalse); // 8 contra 3: p ≈ 0.23, aún sin evidencia

      final strong = summarizeCalibration([for (var i = 0; i < 12; i++) session('cultura', [5, 4, 4], [2, 1, 2])]);
      expect(strong.signTestP, lessThan(0.05));
      expect(strong.liftCi95!.$1, greaterThan(0));
      expect(strong.beatsRandom, isTrue);

      final byProfile = summarizeCalibrationByProfile(responses);
      expect(byProfile.keys, ['cultura', 'noche']);
      expect(byProfile['noche']!.losses, 3);
      expect(byProfile['cultura']!.lift, greaterThan(0));
    });
  });
}
