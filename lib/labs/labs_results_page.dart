// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_aggregates.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';
import 'labs_top_bar.dart';

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
      appBar: const LabsTopBar(current: LabsSection.news),
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
                children.add(_BlogHeader(isMobile: isMobile));
                if (paper['published'] == true) {
                  // Entrada destacada: el reporte completo de resultados del laboratorio
                  children.add(_BlogPost(
                    tag: 'Reporte de resultados',
                    date: fmtDate(paper['publishedAt'] ?? paper['updatedAt']),
                    title: '${paper['title'] ?? 'Resultados de Ohtli Labs'}',
                    excerpt: '${paper['abstract'] ?? paper['summary'] ?? 'Metodología, resultados por estudio y conclusiones de las pruebas del laboratorio.'}',
                    cta: 'Leer el reporte completo',
                    featured: true,
                    onTap: () => _goResults(),
                  ));
                }
                if (paper['newsEnabled'] != true || runs.isEmpty) {
                  if (paper['published'] != true) {
                    children.add(LabCard(child: Text('Aún no hay noticias publicadas. Vuelve pronto.', style: labCell())));
                  }
                } else {
                  for (final r in runs) {
                    final s = studyById('${r.data()['studyId']}');
                    children.add(_BlogPost(
                      tag: 'Resultados de laboratorio',
                      date: fmtDate(r.data()['publishedAt'] ?? r.data()['startedAt']),
                      title: s?.title ?? '${r.data()['studyId']}',
                      excerpt: '${r.data()['notes'] ?? ''}',
                      cta: 'Ver resultados',
                      onTap: () => _goResults(),
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

void _goResults() {
  if (!kIsWeb) return;
  final host = html.window.location.hostname ?? '';
  html.window.location.href = host.endsWith('ohtli.quest') ? 'https://labs.ohtli.quest/resultados' : '/resultados?testLab';
}

/// Encabezado del blog de noticias de Labs.
class _BlogHeader extends StatelessWidget {
  final bool isMobile;
  const _BlogHeader({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOTICIAS DEL LABORATORIO',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: OhtliColors.accentText)),
          const SizedBox(height: 10),
          Text('Lo que estamos probando y aprendiendo',
              style: GoogleFonts.outfit(fontSize: isMobile ? 30 : 42, fontWeight: FontWeight.w800, color: OhtliColors.onyx, letterSpacing: -1, height: 1.08)),
          const SizedBox(height: 10),
          Text('Novedades de Ohtli Labs y resultados de cada estudio, publicados al concluir las pruebas.',
              style: GoogleFonts.inter(fontSize: 15.5, color: OhtliColors.subtleText, height: 1.55)),
        ],
      ),
    );
  }
}

/// Entrada del blog de Labs (noticia o resultado publicado).
class _BlogPost extends StatefulWidget {
  final String tag;
  final String date;
  final String title;
  final String excerpt;
  final String cta;
  final bool featured;
  final VoidCallback onTap;

  const _BlogPost({
    required this.tag,
    required this.date,
    required this.title,
    required this.excerpt,
    required this.cta,
    required this.onTap,
    this.featured = false,
  });

  @override
  State<_BlogPost> createState() => _BlogPostState();
}

class _BlogPostState extends State<_BlogPost> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final featured = widget.featured;
    final fg = featured ? Colors.white : OhtliColors.onyx;
    final sub = featured ? Colors.white.withValues(alpha: 0.78) : OhtliColors.subtleText;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          padding: EdgeInsets.all(featured ? 30 : 24),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: featured ? null : OhtliColors.cardBg,
            gradient: featured
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF123338), OhtliColors.stormyTeal])
                : null,
            borderRadius: BorderRadius.circular(24),
            border: featured ? null : Border.all(color: _hover ? OhtliColors.accentText.withValues(alpha: 0.5) : OhtliColors.cardBorder),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hover ? 0.14 : 0.05), blurRadius: _hover ? 26 : 12, offset: Offset(0, _hover ? 12 : 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: featured ? Colors.white.withValues(alpha: 0.16) : OhtliColors.stormyTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(widget.tag,
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: featured ? Colors.white : OhtliColors.accentText)),
                  ),
                  const SizedBox(width: 12),
                  Text(widget.date, style: GoogleFonts.inter(fontSize: 12.5, color: sub)),
                ],
              ),
              const SizedBox(height: 14),
              Text(widget.title,
                  style: GoogleFonts.outfit(fontSize: featured ? 26 : 21, fontWeight: FontWeight.w800, color: fg, height: 1.15)),
              if (widget.excerpt.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(widget.excerpt, maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14.5, color: sub, height: 1.55)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.cta,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: featured ? OhtliColors.cempasuchil : OhtliColors.accentText)),
                  const SizedBox(width: 6),
                  AnimatedSlide(
                    offset: Offset(_hover ? 0.3 : 0, 0),
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.arrow_forward_rounded, size: 17, color: featured ? OhtliColors.cempasuchil : OhtliColors.accentText),
                  ),
                ],
              ),
            ],
          ),
        ),
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
