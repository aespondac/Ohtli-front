import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_aggregates.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';

/// labs.ohtli.quest — reporte público (tipo paper) y tablero de resultados.
/// Solo muestra lo que el superusuario publicó desde lab.ohtli.quest.
class LabsResultsPage extends StatelessWidget {
  final bool newsMode;
  final VoidCallback onOpenEval;
  const LabsResultsPage({super.key, this.newsMode = false, required this.onOpenEval});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;
    final repo = LabRepository.instance;
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: OhtliColors.cardBg,
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.insights_rounded, color: OhtliColors.stormyTeal),
          const SizedBox(width: 8),
          Text(newsMode ? 'Ohtli Labs · Novedades' : 'Ohtli Labs · Resultados',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
        ]),
        actions: [
          TextButton.icon(onPressed: onOpenEval, icon: const Icon(Icons.volunteer_activism_outlined, size: 16), label: const Text('Participa')),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: repo.paper.snapshots(),
        builder: (context, paperSnap) {
          final paper = paperSnap.data?.data() ?? {};
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: repo.watchPublished(),
            builder: (context, runsSnap) {
              final runs = runsSnap.data?.docs ?? [];
              final children = <Widget>[];
              if (newsMode) {
                if (paper['newsEnabled'] != true || runs.isEmpty) {
                  children.add(LabCard(child: Text('Aún no hay novedades publicadas.', style: labCell())));
                } else {
                  for (final r in runs) {
                    final s = studyById('${r.data()['studyId']}');
                    children.add(Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LabCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(fmtDate(r.data()['publishedAt'] ?? r.data()['startedAt']), style: labCell()),
                          Text(s?.title ?? '${r.data()['studyId']}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                          if ((r.data()['notes'] ?? '').toString().isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text('${r.data()['notes']}', style: GoogleFonts.inter(fontSize: 13, height: 1.45, color: OhtliColors.onyx))),
                        ]),
                      ),
                    ));
                  }
                }
              } else {
                children.add(_PaperHeader(paper: paper, published: paper['published'] == true));
                if (runs.isEmpty) {
                  children.add(LabCard(child: Text('Los resultados se publicarán aquí al concluir las pruebas.', style: labCell())));
                }
                // Una sección por estudio con su corrida publicada más reciente
                for (final study in kLabStudies) {
                  final rs = runs.where((r) => r.data()['studyId'] == study.id).toList();
                  if (rs.isNotEmpty) children.add(_PublishedStudy(study: study, run: rs.first, older: rs.length - 1));
                }
                for (final sid in ['relevancia', 'sus']) {
                  children.add(_PublishedAggregate(study: studyById(sid)!));
                }
                if (paper['published'] == true && (paper['conclusions'] ?? '').toString().isNotEmpty) {
                  children.add(LabCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const LabSectionTitle('Conclusiones'),
                      Text('${paper['conclusions']}', style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: OhtliColors.onyx)),
                    ]),
                  ));
                }
              }
              return ListView(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 40, vertical: 24),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: children.expand((w) => [w, const SizedBox(height: 16)]).toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PaperHeader extends StatelessWidget {
  final Map<String, dynamic> paper;
  final bool published;
  const _PaperHeader({required this.paper, required this.published});

  @override
  Widget build(BuildContext context) {
    final title = published ? (paper['title'] ?? 'Ohtli Labs') : 'Ohtli Labs';
    return LabCard(
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('REPORTE DE EVALUACIÓN', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: OhtliColors.stormyTeal)),
        const SizedBox(height: 8),
        Text('$title', style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w800, color: OhtliColors.onyx, height: 1.15)),
        if (published && (paper['authors'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${paper['authors']}', style: labCell())),
        if (published && (paper['abstract'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Resumen', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 4),
          Text('${paper['abstract']}', style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: OhtliColors.onyx)),
        ],
        if (published && (paper['method'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Método', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
          const SizedBox(height: 4),
          Text('${paper['method']}', style: GoogleFonts.inter(fontSize: 14, height: 1.55, color: OhtliColors.onyx)),
        ],
        if (!published)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Resultados de las pruebas del sistema Ohtli (Trabajo Terminal 2026-B156, ESCOM-IPN).',
                style: GoogleFonts.inter(fontSize: 14, color: OhtliColors.subtleText)),
          ),
      ]),
    );
  }
}

class _PublishedStudy extends StatelessWidget {
  final LabStudy study;
  final QueryDocumentSnapshot<Map<String, dynamic>> run;
  final int older;
  const _PublishedStudy({required this.study, required this.run, required this.older});

  @override
  Widget build(BuildContext context) {
    final d = run.data();
    final s = Map<String, dynamic>.from(d['summary'] as Map? ?? {});
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabSectionTitle(study.title, caption: '${study.criterion} · corrida del ${fmtDate(d['startedAt'])}${older > 0 ? ' · $older corridas anteriores' : ''}'),
        if ((d['notes'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('${d['notes']}', style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: OhtliColors.onyx))),
        switch (study.kind) {
          LabStudyKind.scenarios => _ScenarioPublic(runId: run.id, summary: s),
          LabStudyKind.load => _LoadPublic(summary: s),
          LabStudyKind.checklist => Wrap(spacing: 10, runSpacing: 10, children: [
              MetricTile(label: 'Pasos aprobados', value: '${s['pass'] ?? 0}/${s['total'] ?? 0}'),
              MetricTile(label: 'Cumplimiento', value: fmtNum(s['pass_pct'], suffix: '%')),
              MetricTile(label: 'Fallas', value: '${s['fail'] ?? 0}'),
            ]),
          _ => const SizedBox.shrink(),
        },
      ]),
    );
  }
}

class _ScenarioPublic extends StatelessWidget {
  final String runId;
  final Map<String, dynamic> summary;
  const _ScenarioPublic({required this.runId, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        MetricTile(label: 'Completados', value: '${summary['completed']}/${summary['n']}'),
        MetricTile(label: 'Latencia media', value: fmtNum(summary['e2e_mean_s'], suffix: ' s')),
        MetricTile(label: 'p95', value: fmtNum(summary['e2e_p95_s'], suffix: ' s'), hint: 'SLA ≤ ${summary['sla_s'] ?? 45} s'),
        MetricTile(label: 'Viabilidad CA-01', value: fmtNum(summary['feasible_pct'], suffix: '%')),
        MetricTile(label: 'Traslape', value: fmtNum(summary['overlap_mean'], digits: 2)),
      ]),
      const SizedBox(height: 14),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: LabRepository.instance.rows(runId),
        builder: (context, snap) {
          final rows = snap.data ?? [];
          if (rows.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Latencia de punta a punta por escenario (s)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
            const SizedBox(height: 6),
            LabBars(
              threshold: (summary['sla_s'] as num?)?.toDouble() ?? 45,
              unit: ' s',
              data: rows
                  .where((r) => r['e2e_s'] != null)
                  .map((r) => MapEntry('${(r['scenario'] as Map)['id']}', (r['e2e_s'] as num).toDouble()))
                  .toList(),
            ),
          ]);
        },
      ),
    ]);
  }
}

class _LoadPublic extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _LoadPublic({required this.summary});

  @override
  Widget build(BuildContext context) {
    final lv = Map<String, dynamic>.from(summary['levels'] as Map? ?? {});
    return Column(
      children: lv.entries.map((e) {
        final s = Map<String, dynamic>.from(e.value as Map);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            MetricTile(label: '${e.key} simultáneas', value: '${s['completed']}/${s['n']}', hint: 'error ${fmtNum(s['error_rate_pct'], suffix: '%')}'),
            MetricTile(label: 'Media', value: fmtNum(s['e2e_mean_s'], suffix: ' s')),
            MetricTile(label: 'p95', value: fmtNum(s['e2e_p95_s'], suffix: ' s')),
          ]),
        );
      }).toList(),
    );
  }
}

class _PublishedAggregate extends StatelessWidget {
  final LabStudy study;
  const _PublishedAggregate({required this.study});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: LabRepository.instance.aggregate(study.id).snapshots(),
      builder: (context, snap) {
        final agg = snap.data?.data();
        if (agg == null || agg['published'] != true) return const SizedBox.shrink();
        return LabCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabSectionTitle(study.title, caption: '${study.criterion} · actualizado ${fmtDate(agg['updatedAt'])}'),
            AggregateView(kind: study.kind, agg: agg),
          ]),
        );
      },
    );
  }
}
