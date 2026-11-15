import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_aggregates.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';

/// Copia congelada de una corrida para un artículo: el artículo muestra exactamente los datos
/// con que se redactó aunque después se ejecuten más corridas, y el lector no necesita permisos
/// sobre lab_runs.
Future<Map<String, dynamic>> buildRunSnapshot(String runId, Map<String, dynamic> run) async {
  final study = studyById('${run['studyId']}');
  final snap = <String, dynamic>{
    'type': 'run',
    'runId': runId,
    'studyId': run['studyId'],
    'studyTitle': study?.title ?? run['studyId'],
    'criterion': study?.criterion ?? '',
    'kind': study?.kind.name ?? 'scenarios',
    'label': run['label'] ?? '',
    'startedAt': fmtDate(run['startedAt']),
    'notes': run['notes'] ?? '',
    'summary': run['summary'] ?? {},
  };
  if (study?.kind == LabStudyKind.scenarios) {
    final rows = await LabRepository.instance.rows(runId);
    snap['series'] = [
      for (final r in rows)
        if (r['e2e_s'] != null)
          {
            'id': (r['scenario'] as Map?)?['id'],
            'title': (r['scenario'] as Map?)?['title'],
            'e2e_s': r['e2e_s'],
            'stops': (r['metrics'] as Map?)?['stops'],
            'feasible': (r['metrics'] as Map?)?['feasible'],
            'overlap': (r['metrics'] as Map?)?['overlap_mean'],
          }
    ];
  }
  return snap;
}

/// Métricas principales de una corrida en una línea (consola y tablero de resultados).
String labRunHeadline(LabStudyKind? kind, Map summary) {
  final s = summary;
  switch (kind) {
    case LabStudyKind.scenarios:
      return '${s['completed'] ?? '—'}/${s['n'] ?? '—'} completados · p95 ${fmtNum(s['e2e_p95_s'], suffix: ' s')} · CA-01 ${fmtNum(s['feasible_pct'], suffix: '%')} · traslape ${fmtNum(s['overlap_mean'], digits: 2)}';
    case LabStudyKind.load:
      final lv = (s['levels'] as Map?) ?? {};
      return lv.entries
          .map((e) => '${e.key}: ${(e.value as Map)['completed']}/${(e.value as Map)['n']} (${fmtNum((e.value as Map)['error_rate_pct'], suffix: '% error')})')
          .join(' · ');
    case LabStudyKind.checklist:
      return '${s['pass'] ?? 0}/${s['total'] ?? 0} pasos aprobados · ${s['fail'] ?? 0} fallas';
    default:
      return '';
  }
}

Map<String, dynamic> buildAggregateSnapshot(LabStudy study, Map<String, dynamic> agg) => {
      'type': 'aggregate',
      'studyId': study.id,
      'studyTitle': study.title,
      'criterion': study.criterion,
      'kind': study.kind.name,
      'agg': agg,
    };

/// Vista de lectura de un artículo (consola, testers y blog público).
class LabArticleView extends StatelessWidget {
  final Map<String, dynamic> post;
  const LabArticleView({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final blocks = (post['snapshots'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${post['kicker'] ?? 'OHTLI LABS'}'.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: OhtliColors.stormyTeal)),
      const SizedBox(height: 8),
      Text('${post['title'] ?? ''}', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1.15)),
      const SizedBox(height: 8),
      Text([if ((post['authors'] ?? '').toString().isNotEmpty) post['authors'], fmtDate(post['publishedAt'] ?? post['updatedAt'])].join(' · '),
          style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText)),
      if ((post['summary'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('${post['summary']}', style: GoogleFonts.inter(fontSize: 16, height: 1.55, color: OhtliColors.onyx, fontWeight: FontWeight.w500)),
      ],
      const SizedBox(height: 18),
      LabMarkdown(text: '${post['body'] ?? ''}'),
      for (final b in blocks) ...[const SizedBox(height: 18), LabSnapshotBlock(block: b)],
    ]);
  }
}

/// Markdown mínimo: "## " subtítulo, "- " viñeta, línea en blanco = párrafo, **negritas**.
class LabMarkdown extends StatelessWidget {
  final String text;
  const LabMarkdown({super.key, required this.text});

  TextSpan _inline(String s, TextStyle base) {
    final parts = s.split('**');
    return TextSpan(children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(text: parts[i], style: i.isOdd ? base.copyWith(fontWeight: FontWeight.w700) : base),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.inter(fontSize: 15, height: 1.6, color: OhtliColors.onyx);
    final out = <Widget>[];
    for (final block in text.trim().split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n');
      if (block.trim().isEmpty) continue;
      if (lines.first.startsWith('## ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(lines.first.substring(3), style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
        ));
        if (lines.length > 1) out.add(Text.rich(_inline(lines.skip(1).join(' '), base)));
      } else if (lines.every((l) => l.trimLeft().startsWith('- '))) {
        for (final l in lines) {
          out.add(Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: base),
              Expanded(child: Text.rich(_inline(l.trimLeft().substring(2), base))),
            ]),
          ));
        }
      } else {
        out.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: Text.rich(_inline(lines.join(' '), base))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }
}

/// Bloque de una corrida o un agregado (artículos y tablero de /resultados).
class LabSnapshotBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  const LabSnapshotBlock({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final kind = block['kind'];
    final s = Map<String, dynamic>.from(block['summary'] as Map? ?? {});
    Widget body;
    if (block['type'] == 'aggregate') {
      body = AggregateView(
        kind: kind == 'sus' ? LabStudyKind.sus : LabStudyKind.relevance,
        agg: Map<String, dynamic>.from(block['agg'] as Map? ?? {}),
      );
    } else if (kind == 'load') {
      final lv = Map<String, dynamic>.from(s['levels'] as Map? ?? {});
      body = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 34,
          columns: const [
            DataColumn(label: Text('Simultáneas')),
            DataColumn(label: Text('Completadas')),
            DataColumn(label: Text('Error')),
            DataColumn(label: Text('Media (s)')),
            DataColumn(label: Text('p95 (s)')),
            DataColumn(label: Text('≤ 45 s')),
          ],
          rows: lv.entries.map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            return DataRow(cells: [
              DataCell(Text(e.key, style: labCell(bold: true))),
              DataCell(Text('${m['completed']}/${m['n']}', style: labCell())),
              DataCell(Text(fmtNum(m['error_rate_pct'], suffix: '%'), style: labCell())),
              DataCell(Text(fmtNum(m['e2e_mean_s']), style: labCell())),
              DataCell(Text(fmtNum(m['e2e_p95_s']), style: labCell())),
              DataCell(Text('${m['sla_ok']}/${m['completed']}', style: labCell())),
            ]);
          }).toList(),
        ),
      );
    } else if (kind == 'checklist') {
      body = Wrap(spacing: 10, runSpacing: 10, children: [
        MetricTile(label: 'Pasos aprobados', value: '${s['pass'] ?? 0}/${s['total'] ?? 0}'),
        MetricTile(label: 'Cumplimiento', value: fmtNum(s['pass_pct'], suffix: '%')),
      ]);
    } else {
      final series = (block['series'] as List?) ?? [];
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          MetricTile(label: 'Completados', value: '${s['completed']}/${s['n']}'),
          MetricTile(label: 'Latencia media', value: fmtNum(s['e2e_mean_s'], suffix: ' s')),
          MetricTile(label: 'p95', value: fmtNum(s['e2e_p95_s'], suffix: ' s'), hint: 'SLA ≤ ${s['sla_s'] ?? 45} s'),
          MetricTile(label: 'Viabilidad CA-01', value: fmtNum(s['feasible_pct'], suffix: '%')),
          MetricTile(label: 'Traslape', value: fmtNum(s['overlap_mean'], digits: 2), hint: '0 = alternativas distintas'),
        ]),
        if (series.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Latencia de punta a punta por escenario (s)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
          const SizedBox(height: 6),
          LabBars(
            threshold: (s['sla_s'] as num?)?.toDouble() ?? 45,
            unit: ' s',
            data: series.map((r) => MapEntry('${(r as Map)['id']}', ((r['e2e_s'] as num?) ?? 0).toDouble())).toList(),
          ),
        ],
      ]);
    }
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabSectionTitle('${block['studyTitle']}',
            caption: [block['criterion'], if (block['startedAt'] != null) 'corrida del ${block['startedAt']}'].where((x) => '$x'.isNotEmpty).join(' · ')),
        if ((block['notes'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('${block['notes']}', style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: OhtliColors.onyx))),
        body,
      ]),
    );
  }
}
