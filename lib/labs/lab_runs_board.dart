import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'lab_access.dart';
import 'lab_article.dart';
import 'lab_repository.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';

/// Corridas liberadas por el laboratorio (visibilidad «Público» o «Testers»): cada una con sus
/// métricas principales y, al abrirla, la tabla completa (la misma que en los artículos).
/// Antes marcar una corrida como pública no la mostraba en ningún lado.
class LabRunsBoard extends StatefulWidget {
  final List<String> levels;
  const LabRunsBoard({super.key, required this.levels});

  @override
  State<LabRunsBoard> createState() => _LabRunsBoardState();
}

class _LabRunsBoardState extends State<LabRunsBoard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _runs = LabRepository.instance.watchVisible(widget.levels);
  final Map<String, Future<Map<String, dynamic>>> _details = {};
  String? _open;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _runs,
      builder: (context, snap) {
        if (snap.hasError && !snap.hasData) {
          return LabCard(child: Text('No pudimos cargar las corridas: ${labErrorText(snap.error)}.', style: labCell()));
        }
        if (!snap.hasData) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)));
        }
        final docs = snap.data!.docs.where((d) => d.data()['status'] == 'completed').toList();
        if (docs.isEmpty) {
          return LabCard(child: Text('Todavía no hay corridas liberadas.', style: labCell()));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in docs) Padding(padding: const EdgeInsets.only(bottom: 12), child: _runCard(d.id, d.data())),
        ]);
      },
    );
  }

  Widget _runCard(String id, Map<String, dynamic> run) {
    final study = studyById('${run['studyId']}');
    final open = _open == id;
    final label = (run['label'] ?? '').toString();
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() {
            _open = open ? null : id;
            if (!open) _details.putIfAbsent(id, () => buildRunSnapshot(id, run));
          }),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(study?.title ?? '${run['studyId']}',
                        style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                    if (study != null)
                      Text(study.criterion, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: OhtliColors.accentText)),
                    Icon(LabVisibility.icon(LabVisibility.of(run)), size: 14, color: OhtliColors.subtleText),
                  ]),
                  const SizedBox(height: 4),
                  Text([fmtDate(run['startedAt']), if (label.isNotEmpty) '“$label”'].join(' · '), style: labCell()),
                  const SizedBox(height: 6),
                  Text(labRunHeadline(study?.kind, (run['summary'] as Map?) ?? {}),
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OhtliColors.onyx)),
                ]),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: OhtliColors.subtleText),
            ]),
          ),
        ),
        if (open)
          FutureBuilder<Map<String, dynamic>>(
            future: _details[id],
            builder: (context, s) {
              if (s.hasError) return Text('No pudimos cargar el detalle: ${labErrorText(s.error)}.', style: labCell());
              if (!s.hasData) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              return Padding(padding: const EdgeInsets.only(top: 12), child: LabSnapshotBlock(block: s.data!));
            },
          ),
      ]),
    );
  }
}
