import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'lab_studies.dart';

/// Ejecuta escenarios de Labs contra el motor en producción (api.ohtli.quest) con el ID token
/// del superusuario y calcula las métricas que reporta el capítulo 6.
///
/// No usa el simulador de respaldo del planificador: si el motor falla, la corrida lo registra
/// como error en lugar de inventar un itinerario.
/// Latencia de punta a punta con las marcas del servidor: acuse (cliente) + created_at →
/// completed_at (mismo reloj del motor). Null si faltan las marcas o no son coherentes.
double? serverE2eSeconds(int? ackMs, Map<String, dynamic> job) {
  final created = DateTime.tryParse('${job['created_at'] ?? ''}');
  final completed = DateTime.tryParse('${job['completed_at'] ?? ''}');
  if (ackMs == null || created == null || completed == null || !completed.isAfter(created)) return null;
  return ackMs / 1000.0 + completed.difference(created).inMilliseconds / 1000.0;
}

class LabRunner {
  static const String apiBase = 'https://api.ohtli.quest';
  static const Duration jobTimeout = Duration(minutes: 5);
  final Map<String, List<double>> _vibeCache = {};

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<List<double>> vibeVector(String profile) async {
    final cached = _vibeCache[profile];
    if (cached != null) return cached;
    final text = kLabProfiles[profile] ?? profile;
    final res = await http
        .post(Uri.parse('$apiBase/v1/api/vibe'), headers: await _headers(), body: jsonEncode({'vibe_description': text}))
        .timeout(const Duration(seconds: 60));
    final v = ((jsonDecode(res.body) as Map)['vector'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? <double>[];
    if (v.length == 768) _vibeCache[profile] = v;
    return v;
  }

  /// Registra el trabajo (202) y espera a que el SMA lo complete. Devuelve la fila de resultados.
  Future<Map<String, dynamic>> runScenario(LabScenario sc, {void Function(String stage)? onStage}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final row = <String, dynamic>{'scenario': sc.toJson(), 'started_at': DateTime.now().toUtc().toIso8601String()};
    if (uid == null) return row..addAll({'status': 'error', 'error': 'sin sesión'});
    try {
      onStage?.call('vectorizando perfil');
      final vibe = await vibeVector(sc.profile);
      final jobId = 'lab_${const Uuid().v4()}';
      final payload = {
        'job_id': jobId,
        'user_id': uid,
        'budget': sc.budget,
        'mood_vector': <double>[],
        'vibe_vector': vibe,
        'origin': sc.origin.point,
        'destination': (sc.destination ?? sc.origin).point,
        'topology': sc.topology,
        'mood_text': sc.mood,
        'origin_name': sc.origin.name,
        if (sc.travelDate != null) 'travel_date': sc.travelDate,
        if (sc.radiusKm != null) 'radius_km': sc.radiusKm,
        if (sc.startTime != null) 'start_time': sc.startTime,
        if (sc.endTime != null) 'end_time': sc.endTime,
        'stay_factor': sc.stayFactor,
      };
      row['job_id'] = jobId;
      final t0 = DateTime.now();
      onStage?.call('enviando solicitud');
      final post = await http
          .post(Uri.parse('$apiBase/v1/itinerary'), headers: await _headers(), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
      row['ack_ms'] = DateTime.now().difference(t0).inMilliseconds;
      row['http_status'] = post.statusCode;
      if (post.statusCode >= 300) {
        return row..addAll({'status': 'error', 'error': 'HTTP ${post.statusCode}: ${post.body.substring(0, math.min(200, post.body.length))}'});
      }
      Map<String, dynamic>? job;
      while (DateTime.now().difference(t0) < jobTimeout) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          final g = await http
              .get(Uri.parse('$apiBase/v1/itinerary/$jobId'), headers: await _headers())
              .timeout(const Duration(seconds: 15));
          if (g.statusCode != 200) continue;
          final d = jsonDecode(g.body) as Map<String, dynamic>;
          onStage?.call('${d['current_agent'] ?? d['status']}');
          if (d['status'] == 'completed' || d['status'] == 'error') {
            job = d;
            break;
          }
        } catch (_) {}
      }
      final pollE2e = DateTime.now().difference(t0).inMilliseconds / 1000.0;
      row['e2e_poll_s'] = pollE2e;
      row['e2e_s'] = pollE2e;
      if (job == null) return row..addAll({'status': 'timeout'});
      // Sondear cada 2 s sumaba entre 0 y 2 s a cada medida: con las marcas del servidor la
      // latencia es el acuse más lo que tardó el trabajo de verdad.
      final server = serverE2eSeconds(row['ack_ms'] as int?, job);
      if (server != null) row['e2e_s'] = server;
      row['e2e_source'] = server != null ? 'servidor' : 'sondeo';
      row['status'] = job['status'];
      row['error'] = job['error_detail'];
      row['agent_ms'] = {
        for (final k in ['comparador', 'generador', 'recomendador'])
          k: ((job['steps'] as Map?)?[k] as Map?)?['execution_time_ms'],
      };
      final options = (((job['result'] as Map?)?['options']) as List?) ?? [];
      row['options'] = options.map((o) => _compactOption(Map<String, dynamic>.from(o as Map))).toList();
      row['metrics'] = scenarioMetrics(sc, row['options'] as List);
      return row;
    } catch (e) {
      return row..addAll({'status': 'error', 'error': e.toString()});
    }
  }

  static Map<String, dynamic> _compactOption(Map<String, dynamic> o) => {
        'theme': o['theme'],
        'theme_key': o['theme_key'],
        'total_cost_mxn': o['total_cost_mxn'],
        'total_duration_mins': o['total_duration_mins'],
        'total_walking_km': o['total_walking_km'],
        'start_time': o['start_time'],
        'end_time': o['end_time'],
        'headline': (o['editorial_headline'] ?? '').toString(),
        'narrative': (o['narrative_summary'] ?? '').toString(),
        'route': ((o['route'] as List?) ?? []).map((s) {
          final m = Map<String, dynamic>.from(s as Map);
          return {
            for (final k in [
              'poi_id', 'name', 'category', 'price_mxn', 'price_is_estimate', 'arrival_time', 'departure_time',
              'time_window', 'stay_duration_mins', 'travel_time_from_prev_mins', 'match_score', 'opening_hours', 'description'
            ])
              k: k == 'description' ? (m[k] ?? '').toString().substring(0, math.min(400, (m[k] ?? '').toString().length)) : m[k],
          };
        }).toList(),
      };
}

int _min(String? hhmm) {
  if (hhmm == null || !hhmm.contains(':')) return -1;
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// Métricas por escenario: viabilidad (CA-01), diversidad y procedencia de los lugares.
Map<String, dynamic> scenarioMetrics(LabScenario sc, List options) {
  var stops = 0, windowOk = 0, dayOk = 0, budgetOk = 0, nonEmpty = 0;
  final cats = <String>{};
  final ids = <Set<String>>[];
  final sources = <String, int>{};
  var estimated = 0;
  var scoreSum = 0.0;
  final dayStart = _min(sc.startTime), dayEnd = _min(sc.endTime);
  for (final o in options) {
    final route = (o['route'] as List?) ?? [];
    if (route.isNotEmpty) nonEmpty++;
    final cost = (o['total_cost_mxn'] as num?)?.toDouble() ?? 0;
    if (cost <= sc.budget + 0.01) budgetOk++;
    final set = <String>{};
    for (final s in route) {
      stops++;
      final tw = (s['time_window'] as List?) ?? [];
      final arr = _min(s['arrival_time']), dep = _min(s['departure_time']);
      if (tw.length == 2 && arr >= _min(tw[0]) && dep <= _min(tw[1])) windowOk++;
      if (dayStart < 0 || (arr >= dayStart && dep <= dayEnd)) dayOk++;
      cats.add('${s['category']}');
      final id = '${s['poi_id']}';
      set.add(id);
      final src = id.contains('_') ? id.split('_').first : 'otro';
      sources[src] = (sources[src] ?? 0) + 1;
      if (s['price_is_estimate'] != false) estimated++;
      scoreSum += (s['match_score'] as num?)?.toDouble() ?? 0;
    }
    ids.add(set);
  }
  // Traslape medio de Jaccard entre las alternativas (0 = totalmente distintas)
  final overlaps = <double>[];
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final u = ids[i].union(ids[j]).length;
      overlaps.add(u == 0 ? 0 : ids[i].intersection(ids[j]).length / u);
    }
  }
  return {
    'options': options.length,
    'options_with_stops': nonEmpty,
    'stops': stops,
    'window_ok_pct': stops == 0 ? null : 100.0 * windowOk / stops,
    'day_ok_pct': stops == 0 ? null : 100.0 * dayOk / stops,
    'budget_ok_pct': options.isEmpty ? null : 100.0 * budgetOk / options.length,
    'feasible': stops > 0 && windowOk == stops && dayOk == stops && budgetOk == options.length,
    'distinct_categories': cats.length,
    'overlap_mean': overlaps.isEmpty ? null : overlaps.reduce((a, b) => a + b) / overlaps.length,
    'match_mean': stops == 0 ? null : scoreSum / stops,
    'sources': sources,
    'price_estimated_pct': stops == 0 ? null : 100.0 * estimated / stops,
  };
}

double? percentile(List<double> xs, double p) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final k = (s.length - 1) * p;
  final f = k.floor(), c = k.ceil();
  return f == c ? s[f] : s[f] + (s[c] - s[f]) * (k - f);
}

/// Resumen de una corrida de escenarios (o de un nivel de concurrencia).
Map<String, dynamic> summarizeRows(List<Map<String, dynamic>> rows, {double slaSeconds = 45}) {
  final done = rows.where((r) => r['status'] == 'completed').toList();
  final lat = done.map((r) => (r['e2e_s'] as num).toDouble()).toList();
  final ms = done.map((r) => Map<String, dynamic>.from(r['metrics'] as Map? ?? {})).toList();
  double? mean(Iterable<num?> v) {
    final l = v.whereType<num>().map((e) => e.toDouble()).toList();
    return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }

  final sources = <String, int>{};
  for (final m in ms) {
    (m['sources'] as Map? ?? {}).forEach((k, v) => sources['$k'] = (sources['$k'] ?? 0) + (v as num).toInt());
  }
  return {
    'n': rows.length,
    'completed': done.length,
    'errors': rows.where((r) => r['status'] == 'error').length,
    'timeouts': rows.where((r) => r['status'] == 'timeout').length,
    'error_rate_pct': rows.isEmpty ? null : 100.0 * (rows.length - done.length) / rows.length,
    'e2e_mean_s': mean(lat),
    'e2e_p50_s': percentile(lat, 0.5),
    'e2e_p95_s': percentile(lat, 0.95),
    'e2e_max_s': lat.isEmpty ? null : lat.reduce(math.max),
    'sla_s': slaSeconds,
    'sla_ok': lat.where((x) => x <= slaSeconds).length,
    'feasible_pct': ms.isEmpty ? null : 100.0 * ms.where((m) => m['feasible'] == true).length / ms.length,
    'window_ok_pct': mean(ms.map((m) => m['window_ok_pct'] as num?)),
    'budget_ok_pct': mean(ms.map((m) => m['budget_ok_pct'] as num?)),
    'stops_mean': mean(ms.map((m) => m['stops'] as num?)),
    'overlap_mean': mean(ms.map((m) => m['overlap_mean'] as num?)),
    'match_mean': mean(ms.map((m) => m['match_mean'] as num?)),
    'distinct_categories_mean': mean(ms.map((m) => m['distinct_categories'] as num?)),
    'price_estimated_pct': mean(ms.map((m) => m['price_estimated_pct'] as num?)),
    'sources': sources,
  };
}

/// Puntaje SUS (0–100) a partir de 10 respuestas 1–5.
double susScore(List<int> answers) {
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += i.isEven ? answers[i] - 1 : 5 - answers[i];
  }
  return sum * 2.5;
}

/// nDCG@k con calificaciones 1–5 (ganancia = calificación − 1) en el orden recomendado.
double ndcg(List<int> grades, [int? k]) {
  final g = grades.take(k ?? grades.length).map((x) => (x - 1).toDouble()).toList();
  double dcg(List<double> v) {
    var s = 0.0;
    for (var i = 0; i < v.length; i++) {
      s += (math.pow(2, v[i]) - 1) / (math.log(i + 2) / math.ln2);
    }
    return s;
  }

  final ideal = [...g]..sort((a, b) => b.compareTo(a));
  final d = dcg(ideal);
  return d == 0 ? 0 : dcg(g) / d;
}
