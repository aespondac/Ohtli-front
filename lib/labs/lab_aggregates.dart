import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_runner.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';

// ───────────── Respuestas de testers: validación, una por persona y anonimato ─────────────

/// ID de la respuesta SUS: una por persona (las reglas solo permiten crearla, no reescribirla).
String susResponseId(String uid) => 'sus_$uid';

/// ID de un juicio de relevancia: uno por persona y alternativa de la corrida fuente.
String relevanceResponseId(String uid, String runId, int rowIndex, int optionIndex) => 'rel_${uid}_${runId}_${rowIndex}_$optionIndex';

/// Calificaciones 1–5. Devuelve null si falta o si algún valor no es una calificación válida
/// (respuestas anteriores a la validación en las reglas), para descartarla en vez de romper el panel.
List<int>? likertList(dynamic v, {int? length}) {
  if (v is! List || v.isEmpty) return null;
  if (length != null && v.length != length) return null;
  final out = <int>[];
  for (final e in v) {
    if (e is! num || e != e.roundToDouble() || e < 1 || e > 5) return null;
    out.add(e.toInt());
  }
  return out;
}

int _millis(dynamic ts) {
  try {
    return ((ts as dynamic).toDate() as DateTime).millisecondsSinceEpoch;
  } catch (_) {
    return ts is DateTime ? ts.millisecondsSinceEpoch : 0;
  }
}

/// Respuestas válidas y sin duplicados. Antes del ID determinista se podía reenviar el SUS o
/// recalificar una alternativa tras recargar: se conserva la más reciente por persona (SUS) o por
/// persona y alternativa (relevancia).
List<Map<String, dynamic>> cleanResponses(LabStudyKind kind, List<Map<String, dynamic>> docs) {
  final sorted = [...docs]..sort((a, b) => _millis(a['createdAt']).compareTo(_millis(b['createdAt'])));
  final latest = <String, Map<String, dynamic>>{};
  var anon = 0;
  for (final d in sorted) {
    if (kind == LabStudyKind.sus) {
      if (likertList(d['sus'], length: 10) == null) continue;
    } else {
      if (likertList(d['grades']) == null) continue;
    }
    final uid = d['uid'] ?? 'anon${anon++}';
    final key = kind == LabStudyKind.sus ? '$uid' : '$uid|${d['runId']}|${d['rowIndex']}|${d['optionIndex']}';
    latest[key] = d; // la más reciente gana
  }
  return latest.values.toList();
}

/// Para exportar: el uid se reemplaza por un participante P001, P002… (en orden de primera
/// respuesta), así el archivo no permite reidentificar a nadie y conserva quién respondió qué.
List<Map<String, dynamic>> anonymizeResponses(List<Map<String, dynamic>> docs) {
  final sorted = [...docs]..sort((a, b) => _millis(a['createdAt']).compareTo(_millis(b['createdAt'])));
  final ids = <String, String>{};
  for (final d in sorted) {
    final uid = '${d['uid']}';
    ids.putIfAbsent(uid, () => 'P${(ids.length + 1).toString().padLeft(3, '0')}');
  }
  return docs.map((d) {
    final m = Map<String, dynamic>.from(d)..remove('uid');
    m['participante'] = ids['${d['uid']}'];
    return m;
  }).toList();
}

double? _mean(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

double? _sd(List<double> v) {
  if (v.length < 2) return null;
  final m = _mean(v)!;
  return math.sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (v.length - 1));
}

/// Agregados del cuestionario SUS y de satisfacción.
Map<String, dynamic> aggregateSus(List<Map<String, dynamic>> docs) {
  final scores = <double>[];
  final sat = List.generate(kSatisfactionItems.length, (_) => <double>[]);
  final tasks = List.generate(kSusTasks.length, (_) => <String, int>{});
  final profiles = <String, int>{};
  for (final d in docs) {
    final sus = likertList(d['sus'], length: 10);
    if (sus != null) scores.add(susScore(sus));
    final s = likertList(d['satisfaction']) ?? const <int>[];
    for (var i = 0; i < math.min(s.length, sat.length); i++) {
      sat[i].add(s[i].toDouble());
    }
    final t = (d['tasks'] as List?) ?? [];
    for (var i = 0; i < math.min(t.length, tasks.length); i++) {
      tasks[i]['${t[i]}'] = (tasks[i]['${t[i]}'] ?? 0) + 1;
    }
    final p = (d['profile'] as Map?)?['visitor_type'];
    if (p != null) profiles['$p'] = (profiles['$p'] ?? 0) + 1;
  }
  return {
    'kind': 'sus',
    'n': scores.length,
    'sus_mean': _mean(scores),
    'sus_sd': _sd(scores),
    'sus_min': scores.isEmpty ? null : scores.reduce(math.min),
    'sus_max': scores.isEmpty ? null : scores.reduce(math.max),
    'sus_ge_68_pct': scores.isEmpty ? null : 100.0 * scores.where((x) => x >= 68).length / scores.length,
    'satisfaction_means': [for (final l in sat) _mean(l)],
    'tasks': tasks,
    'visitor_types': profiles,
  };
}

/// Agregados de los juicios de relevancia: una respuesta = calificaciones 1–5 de las paradas de
/// una alternativa, en el orden en que el sistema las recomendó.
Map<String, dynamic> aggregateRelevance(List<Map<String, dynamic>> docs) {
  final grades = <double>[];
  final p5 = <double>[];
  final ndcgs = <double>[];
  final byTheme = <String, List<double>>{};
  final judges = <String>{};
  for (final d in docs) {
    final g = likertList(d['grades']) ?? const <int>[];
    if (g.isEmpty) continue;
    if (d['uid'] != null) judges.add('${d['uid']}');
    grades.addAll(g.map((x) => x.toDouble()));
    final k = math.min(5, g.length);
    p5.add(g.take(k).where((x) => x >= 4).length / k);
    ndcgs.add(ndcg(g, 5));
    byTheme.putIfAbsent('${d['theme'] ?? 'sin tema'}', () => []).addAll(g.map((x) => x.toDouble()));
  }
  return {
    'kind': 'relevance',
    'judgments': p5.length,
    'judges': judges.length,
    'stops_rated': grades.length,
    'grade_mean': _mean(grades),
    'precision_at_5': _mean(p5),
    'ndcg_at_5': _mean(ndcgs),
    'relevant_pct': grades.isEmpty ? null : 100.0 * grades.where((x) => x >= 4).length / grades.length,
    'grade_mean_by_theme': {for (final e in byTheme.entries) e.key: _mean(e.value)},
  };
}

String responsesCsv(LabStudyKind kind, List<Map<String, dynamic>> docs) {
  if (kind == LabStudyKind.sus) {
    return toCsv(
      ['respuesta', ...List.generate(10, (i) => 'sus${i + 1}'), 'sus_puntaje',
       ...List.generate(kSatisfactionItems.length, (i) => 'sat${i + 1}'), ...List.generate(kSusTasks.length, (i) => 'tarea${i + 1}'),
       'tipo_visitante', 'edad', 'dispositivo', 'comentario'],
      docs.asMap().entries.map((e) {
        final d = e.value;
        final sus = likertList(d['sus'], length: 10) ?? const <int>[];
        final p = (d['profile'] as Map?) ?? {};
        return [
          e.key + 1, ...List.generate(10, (i) => i < sus.length ? sus[i] : null), sus.length == 10 ? susScore(sus) : null,
          ...List.generate(kSatisfactionItems.length, (i) => ((d['satisfaction'] as List?) ?? []).elementAtOrNull(i)),
          ...List.generate(kSusTasks.length, (i) => ((d['tasks'] as List?) ?? []).elementAtOrNull(i)),
          p['visitor_type'], p['age_range'], p['device'], d['comment'],
        ];
      }).toList(),
    );
  }
  return toCsv(
    ['respuesta', 'corrida', 'escenario', 'alternativa', 'tema', 'intencion', 'calificaciones', 'p@5', 'ndcg@5'],
    docs.asMap().entries.map((e) {
      final d = e.value;
      final g = likertList(d['grades']) ?? const <int>[];
      final k = math.min(5, g.length);
      return [
        e.key + 1, d['runId'], d['scenarioId'], d['optionIndex'], d['theme'], d['mood'], g.join(' '),
        k == 0 ? null : g.take(k).where((x) => x >= 4).length / k, g.isEmpty ? null : ndcg(g, 5),
      ];
    }).toList(),
  );
}

class AggregateView extends StatelessWidget {
  final LabStudyKind kind;
  final Map<String, dynamic> agg;
  const AggregateView({super.key, required this.kind, required this.agg});

  @override
  Widget build(BuildContext context) {
    if (kind == LabStudyKind.sus) {
      final sat = (agg['satisfaction_means'] as List?) ?? [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          MetricTile(label: 'Participantes', value: '${agg['n'] ?? 0}'),
          MetricTile(
              label: 'SUS medio',
              value: fmtNum(agg['sus_mean']),
              hint: 'DE ${fmtNum(agg['sus_sd'])} · umbral 68',
              color: (agg['sus_mean'] ?? 0) >= 68 ? const Color(0xFF3F8F5B) : OhtliColors.cempasuchil),
          MetricTile(label: 'SUS ≥ 68', value: fmtNum(agg['sus_ge_68_pct'], suffix: '%')),
          MetricTile(label: 'Rango', value: '${fmtNum(agg['sus_min'], digits: 0)}–${fmtNum(agg['sus_max'], digits: 0)}'),
        ]),
        if (sat.any((x) => x != null)) ...[
          const SizedBox(height: 14),
          Text('Satisfacción con el itinerario (1–5)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          const SizedBox(height: 6),
          LabBars(
            maxValue: 5,
            data: [
              for (var i = 0; i < kSatisfactionItems.length; i++)
                if (i < sat.length && sat[i] != null) MapEntry('S${i + 1}', (sat[i] as num).toDouble()),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < kSatisfactionItems.length; i++)
            Text('S${i + 1}. ${kSatisfactionItems[i]}', style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
        ],
      ]);
    }
    final byTheme = (agg['grade_mean_by_theme'] as Map?) ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        MetricTile(label: 'Juicios', value: '${agg['judgments'] ?? 0}', hint: '${agg['judges'] ?? 0} evaluadores · ${agg['stops_rated'] ?? 0} paradas'),
        MetricTile(label: 'Precision@5', value: fmtNum(agg['precision_at_5'], digits: 2), hint: 'relevante = calificación ≥ 4'),
        MetricTile(label: 'nDCG@5', value: fmtNum(agg['ndcg_at_5'], digits: 2)),
        MetricTile(label: 'Calificación media', value: fmtNum(agg['grade_mean'], digits: 2), hint: 'escala 1–5'),
      ]),
      if (byTheme.isNotEmpty) ...[
        const SizedBox(height: 14),
        LabBars(maxValue: 5, data: byTheme.entries.where((e) => e.value != null).map((e) => MapEntry('${e.key}', (e.value as num).toDouble())).toList()),
      ],
    ]);
  }
}
