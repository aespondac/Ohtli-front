import 'package:flutter_test/flutter_test.dart';
import 'package:othli_front/labs/lab_runner.dart';
import 'package:othli_front/labs/lab_studies.dart';

void main() {
  test('SUS: respuestas ideales = 100 y neutras = 50', () {
    expect(susScore([5, 1, 5, 1, 5, 1, 5, 1, 5, 1]), 100);
    expect(susScore(List.filled(10, 3)), 50);
  });

  test('nDCG: orden ideal = 1 y orden inverso < 1', () {
    expect(ndcg([5, 4, 3, 2, 1]), closeTo(1, 1e-9));
    expect(ndcg([1, 2, 3, 4, 5]), lessThan(1));
    expect(ndcg([1, 1, 1]), 0);
  });

  test('Viabilidad CA-01: ventana, jornada y presupuesto', () {
    final sc = formalScenarios().first; // 10:00–18:00, $500
    final ok = [
      {
        'total_cost_mxn': 300,
        'route': [
          {'poi_id': 'osm_1', 'category': 'museum', 'arrival_time': '10:30', 'departure_time': '12:00', 'time_window': ['10:00', '17:00'], 'price_is_estimate': true, 'match_score': 0.8},
          {'poi_id': 'sic_2', 'category': 'gallery', 'arrival_time': '12:20', 'departure_time': '13:00', 'time_window': ['09:00', '19:00'], 'price_is_estimate': false, 'match_score': 0.7},
        ],
      },
    ];
    final m = scenarioMetrics(sc, ok);
    expect(m['feasible'], true);
    expect(m['sources'], {'osm': 1, 'sic': 1});
    final late = [
      {
        'total_cost_mxn': 600,
        'route': [
          {'poi_id': 'osm_1', 'category': 'museum', 'arrival_time': '16:30', 'departure_time': '18:30', 'time_window': ['10:00', '17:00']},
        ],
      },
    ];
    final m2 = scenarioMetrics(sc, late);
    expect(m2['feasible'], false);
    expect(m2['budget_ok_pct'], 0);
  });

  test('Batería: 30 escenarios deterministas con tres topologías', () {
    final b = batteryScenarios();
    expect(b.length, 30);
    expect(b.map((s) => s.topology).toSet(), {'radio', 'anillo', 'elipse'});
    expect(b.where((s) => s.topology == 'elipse').every((s) => s.destination != null), true);
  });

  test('Resumen: percentil 95 y tasa de error', () {
    final rows = [
      for (var i = 1; i <= 19; i++) {'status': 'completed', 'e2e_s': i.toDouble(), 'metrics': {'feasible': true}},
      {'status': 'error'},
    ];
    final s = summarizeRows(rows);
    expect(s['completed'], 19);
    expect(s['error_rate_pct'], 5);
    expect(s['e2e_p95_s'], closeTo(18.1, 1e-9));
  });
}

