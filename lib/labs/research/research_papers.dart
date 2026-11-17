import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../lab_access.dart';
import '../lab_widgets.dart';
import 'lab_models.dart';
import 'lab_research_repository.dart';
import 'research_widgets.dart';

String? get _uid => FirebaseAuth.instance.currentUser?.uid;
final _repo = LabResearch.instance;
TextStyle _h(double size) => GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: OhtliColors.onyx);

/// Paper del estudio y su recorrido: revisión interna → externa* → validación de participantes*
/// → aprobado → blog → destino de las funciones.
class LabPaperPanel extends StatelessWidget {
  final LabResearchStudy study;
  final LabRole role;
  const LabPaperPanel({super.key, required this.study, required this.role});

  @override
  Widget build(BuildContext context) {
    final s = study;
    if (s.currentPaperId == null) {
      final ready = s.status.index >= StudyStatus.enCurso.index && s.status != StudyStatus.cancelado;
      return LabCard(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Paper', style: _h(16)),
              Text(ready ? 'Redacta el paper con los resultados del estudio.' : 'El paper se crea cuando el estudio ya está en curso.', style: labCell()),
            ]),
          ),
          FilledButton(
            onPressed: ready ? () => runLabAction(context, () => _repo.createPaper(s), ok: 'Paper creado.') : null,
            child: const Text('Crear paper'),
          ),
        ]),
      );
    }
    return StreamBuilder<LabPaper?>(
      stream: _repo.watchPaper(s.currentPaperId!),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) return const LabCard(child: Center(child: CircularProgressIndicator()));
        return _PaperView(key: ValueKey('${p.id}-${p.round}'), paper: p, study: s, role: role);
      },
    );
  }
}

class _PaperView extends StatefulWidget {
  final LabPaper paper;
  final LabResearchStudy study;
  final LabRole role;
  const _PaperView({super.key, required this.paper, required this.study, required this.role});

  @override
  State<_PaperView> createState() => _PaperViewState();
}

class _PaperViewState extends State<_PaperView> {
  late final _title = TextEditingController(text: widget.paper.title);
  late final _abstract = TextEditingController(text: widget.paper.abstract);
  late final _body = TextEditingController(text: widget.paper.body);
  late final _app = TextEditingController(text: '${widget.paper.reproducibility['appCommit'] ?? ''}');
  late final _engine = TextEditingController(text: '${widget.paper.reproducibility['engineCommit'] ?? ''}');
  late final _proc = TextEditingController(text: '${widget.paper.reproducibility['procedure'] ?? ''}');
  late final _data = TextEditingController(text: '${widget.paper.reproducibility['datasetUrl'] ?? ''}');
  late final _runs = TextEditingController(text: ((widget.paper.reproducibility['runIds'] as List?) ?? const []).join(', '));

  LabPaper get p => widget.paper;
  bool get _isAuthor => p.authors.contains(_uid) || widget.study.canEdit(_uid, admin: widget.role == LabRole.admin);

  @override
  Widget build(BuildContext context) {
    final pipeline = paperPipeline(widget.study.config);
    final editing = _isAuthor && p.stage == PaperStage.borrador;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Paper · ronda ${p.round}', style: _h(16))),
          LabTag(p.stage.label, color: OhtliColors.accent),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < pipeline.length; i++) ...[
            if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: OhtliColors.subtleText),
            LabTag(pipeline[i].label,
                color: pipeline.indexOf(p.stage) >= i ? OhtliColors.stormyTeal : OhtliColors.subtleText,
                icon: pipeline.indexOf(p.stage) > i ? Icons.check_rounded : null),
          ],
        ]),
        const SizedBox(height: 14),
        labField(_title, 'Título', enabled: editing),
        labField(_abstract, 'Resumen (lo leen los testers en la validación)', maxLines: 4, enabled: editing),
        labField(_body, 'Cuerpo (Markdown)', maxLines: 10, enabled: editing),
        Text('Paquete de reproducibilidad', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        const SizedBox(height: 4),
        Text('Incluye el preregistro (${widget.study.metrics.length} métricas, ${widget.study.amendments} enmienda(s)). '
            'Lo reciben los revisores externos bajo NDA.', style: labCell()),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: labField(_app, 'Commit de la app', enabled: editing)),
          const SizedBox(width: 10),
          Expanded(child: labField(_engine, 'Commit del motor', enabled: editing)),
        ]),
        labField(_runs, 'Corridas usadas (IDs separados por coma)', enabled: editing),
        labField(_data, 'Datos agregados y anónimos (enlace)', enabled: editing),
        labField(_proc, 'Procedimiento para repetirlo', maxLines: 4, enabled: editing),
        if (editing)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _save, child: const Text('Guardar')),
              FilledButton(
                onPressed: () async {
                  await _save();
                  if (!mounted) return;
                  await runLabAction(context, () => _repo.setPaperStage(p, PaperStage.revisionInterna), ok: 'Enviado a revisión interna.');
                },
                child: const Text('Enviar a revisión interna'),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        _StageActions(paper: p, study: widget.study, role: widget.role, isAuthor: _isAuthor),
        const SizedBox(height: 8),
        _ReviewsList(paper: p),
      ]),
    );
  }

  Future<void> _save() => runLabAction(context, () => _repo.savePaper(p.id, {
        'title': _title.text.trim(),
        'abstract': _abstract.text.trim(),
        'body': _body.text,
        'reproducibility.appCommit': _app.text.trim(),
        'reproducibility.engineCommit': _engine.text.trim(),
        'reproducibility.procedure': _proc.text.trim(),
        'reproducibility.datasetUrl': _data.text.trim(),
        'reproducibility.runIds': [for (final r in _runs.text.split(',')) if (r.trim().isNotEmpty) r.trim()],
        'reproducibility.preregistration': {
          'hypotheses': widget.study.hypotheses,
          'analysisPlan': widget.study.analysisPlan,
          'metrics': [for (final m in widget.study.metrics) m.toMap()],
        },
        'reproducibility.amendments': widget.study.amendments,
      }), ok: 'Paper guardado.');
}

/// Lo que se puede hacer en la etapa actual.
class _StageActions extends StatelessWidget {
  final LabPaper paper;
  final LabResearchStudy study;
  final LabRole role;
  final bool isAuthor;
  const _StageActions({required this.paper, required this.study, required this.role, required this.isAuthor});

  @override
  Widget build(BuildContext context) {
    final p = paper;
    switch (p.stage) {
      case PaperStage.revisionInterna:
      case PaperStage.revisionExterna:
        final kind = p.stage == PaperStage.revisionInterna ? 'interna' : 'externa';
        final min = kind == 'interna' ? 1 : study.config.minExternalReviewers;
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _repo.watchReviews(p.id),
          builder: (c, snap) {
            final mine = (snap.data ?? const []).where((r) => r['round'] == p.round && r['kind'] == kind).toList();
            final outcome = reviewOutcome([for (final r in mine) ReviewDecisionX.parse(r['decision'])], minReviews: min);
            final next = nextPaperStage(p.stage, study.config);
            final alreadyReviewed = mine.any((r) => r['uid'] == _uid);
            return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${mine.length} de $min dictamen(es) ${kind == 'interna' ? 'internos' : 'externos'}', style: labCell(bold: true)),
              if (kind == 'interna' && role.isMember && !p.authors.contains(_uid) && !alreadyReviewed)
                FilledButton(onPressed: () => ReviewDialog.show(context, p, 'interna'), child: const Text('Dictaminar')),
              if (isAuthor && outcome == ReviewOutcome.avanza && next != null)
                FilledButton(
                  onPressed: () => runLabAction(
                    context,
                    () => next == PaperStage.validacionParticipantes ? _repo.openMemberCheck(p) : _repo.setPaperStage(p, next),
                    ok: 'Avanzó a ${next.label}.',
                  ),
                  child: Text('Avanzar a «${next.label}»'),
                ),
              if (isAuthor && outcome == ReviewOutcome.regresa)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: OhtliColors.warningText),
                  onPressed: () => runLabAction(context, () => _repo.returnToDraft(p, 'Dictamen de revisión $kind'),
                      ok: 'El paper volvió a borrador (ronda ${p.round + 1}).'),
                  child: const Text('Atender cambios (nueva ronda)'),
                ),
            ]);
          },
        );
      case PaperStage.validacionParticipantes:
        return _MemberCheckStatus(paper: p, study: study, role: role, isAuthor: isAuthor);
      case PaperStage.aprobado:
      case PaperStage.publicado:
        return _PublishAndDecide(paper: p, study: study, role: role);
      case PaperStage.borrador:
        return const SizedBox.shrink();
    }
  }
}

class _MemberCheckStatus extends StatelessWidget {
  final LabPaper paper;
  final LabResearchStudy study;
  final LabRole role;
  final bool isAuthor;
  const _MemberCheckStatus({required this.paper, required this.study, required this.role, required this.isAuthor});

  @override
  Widget build(BuildContext context) {
    final p = paper;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _repo.roundChecks(p),
      builder: (c, snap) {
        final votes = [for (final v in snap.data ?? const []) MemberCheckVoteX.parse(v['vote'])].whereType<MemberCheckVote>().toList();
        final r = memberCheck(votes, study.enrolledCount);
        final closed = p.checkClosesAt != null && DateTime.now().isAfter(p.checkClosesAt!);
        final comments = [for (final v in snap.data ?? const []) (v['comment'] ?? '').toString()].where((x) => x.isNotEmpty).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            MetricTile(label: 'Votos', value: '${r.votes}', hint: 'quórum ${r.quorum} de ${study.enrolledCount} inscritos'),
            MetricTile(label: 'Apoyo', value: '${(r.support * 100).round()} %', hint: 'meta ≥ 67 %'),
            MetricTile(label: '«No»', value: '${(r.rejection * 100).round()} %', hint: 'debe ser < 33 %'),
            MetricTile(
              label: 'Cierra',
              value: p.checkClosesAt == null ? '—' : '${p.checkClosesAt!.day}/${p.checkClosesAt!.month}',
              hint: p.checkExtended ? 'ya se extendió' : 'se puede extender 7 días',
            ),
          ]),
          const SizedBox(height: 10),
          if (comments.isNotEmpty) ...[
            Text('Comentarios de participantes (anónimos)', style: labCell(bold: true)),
            for (final x in comments.take(20)) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $x', style: labCell())),
            const SizedBox(height: 10),
          ],
          if (isAuthor)
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (r.approved)
                FilledButton(
                  onPressed: () => runLabAction(context, () => _repo.setPaperStage(p, PaperStage.aprobado, note: 'Validación de participantes aprobada'),
                      ok: 'Paper aprobado.'),
                  child: const Text('Aprobar paper'),
                ),
              if (r.quorumMet && !r.approved)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: OhtliColors.warningText),
                  onPressed: () => runLabAction(context, () => _repo.returnToDraft(p, 'Los participantes no se vieron reflejados'),
                      ok: 'El paper volvió a borrador.'),
                  child: const Text('Regresar a borrador'),
                ),
              if (!r.quorumMet && closed && !p.checkExtended)
                OutlinedButton(onPressed: () => runLabAction(context, () => _repo.extendMemberCheck(p), ok: 'Ventana extendida 7 días.'),
                    child: const Text('Extender 7 días')),
              if (!r.quorumMet && closed && p.checkExtended && role == LabRole.admin)
                OutlinedButton(
                  onPressed: () => runLabAction(context, () => _repo.setPaperStage(p, PaperStage.aprobado, note: 'Sin quórum: decisión del admin'),
                      ok: 'Aprobado sin quórum (queda registrado).'),
                  child: const Text('Aprobar sin quórum'),
                ),
            ]),
        ]);
      },
    );
  }
}

class _PublishAndDecide extends StatelessWidget {
  final LabPaper paper;
  final LabResearchStudy study;
  final LabRole role;
  const _PublishAndDecide({required this.paper, required this.study, required this.role});

  @override
  Widget build(BuildContext context) {
    final p = paper;
    return StreamBuilder<List<LabProject>>(
      stream: _repo.watchProjects(),
      builder: (c, ps) {
        final project = (ps.data ?? const <LabProject>[]).where((x) => x.id == study.projectId).firstOrNull;
        final confidential = project?.confidential ?? study.confidential;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.stage == PaperStage.aprobado)
            if (role == LabRole.admin)
              FilledButton.icon(
                onPressed: confidential
                    ? null
                    : () async {
                        if (!await confirmLab(context, 'Publicar en el blog', 'La nota será pública en Noticias de Labs.', confirm: 'Publicar')) return;
                        if (!context.mounted) return;
                        await runLabAction(context, () => _repo.publishToBlog(p, projectConfidential: confidential), ok: 'Publicado en el blog.');
                      },
                icon: const Icon(Icons.public_rounded),
                label: Text(confidential ? 'Bloqueado: proyecto confidencial (desclasifícalo primero)' : 'Publicar en el blog'),
              )
            else
              Text('Aprobado. Falta que el admin lo publique en el blog.', style: labCell(bold: true)),
          if (p.stage == PaperStage.publicado) Text('Publicado en Noticias de Labs.', style: labCell(bold: true)),
          if (study.featureKeys.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Destino de las funciones del estudio', style: labCell(bold: true)),
            const SizedBox(height: 4),
            Text(role == LabRole.admin ? 'Decide si cada una se vuelve oficial, sigue en beta o se retira.' : 'Lo decide el admin.', style: labCell()),
            StreamBuilder<List<LabFeature>>(
              stream: _repo.watchFeatures(),
              builder: (c, fs) => Column(children: [
                for (final f in (fs.data ?? const <LabFeature>[]).where((f) => study.featureKeys.contains(f.key)))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(f.name),
                    subtitle: Text(f.stage.label),
                    trailing: role != LabRole.admin || p.stage != PaperStage.publicado
                        ? null
                        : Wrap(spacing: 6, children: [
                            for (final st in [FeatureStage.oficial, FeatureStage.beta, FeatureStage.retirada])
                              if (st != f.stage)
                                OutlinedButton(
                                  onPressed: () => runLabAction(context,
                                      () => _repo.setFeatureStage(f.key, st, reason: 'Decisión tras publicar ${study.title}'),
                                      ok: '${f.name}: ${st.label}.'),
                                  child: Text(st.label),
                                ),
                          ]),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}

class _ReviewsList extends StatelessWidget {
  final LabPaper paper;
  const _ReviewsList({required this.paper});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _repo.watchReviews(paper.id),
        builder: (c, snap) {
          final list = [...?snap.data]..sort((a, b) => (b['round'] as num? ?? 0).compareTo(a['round'] as num? ?? 0));
          if (list.isEmpty) return const SizedBox.shrink();
          return ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Dictámenes (${list.length})', style: labCell(bold: true)),
            children: [
              for (final r in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r['kind'] == 'externa' ? Icons.public_outlined : Icons.groups_outlined, size: 18),
                  title: Text('Ronda ${r['round']} · ${r['kind']} · ${ReviewDecisionX.parse(r['decision']).label}'),
                  subtitle: Text((r['comments'] ?? '').toString()),
                ),
            ],
          );
        },
      );
}

/// Dictamen de un revisor (interno o externo).
class ReviewDialog extends StatefulWidget {
  final LabPaper paper;
  final String kind;
  const ReviewDialog({super.key, required this.paper, required this.kind});

  static Future<void> show(BuildContext context, LabPaper p, String kind) =>
      showDialog<void>(context: context, builder: (_) => ReviewDialog(paper: p, kind: kind));

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  ReviewDecision? _d;
  final _c = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final p = widget.paper;
    final repro = p.reproducibility;
    return AlertDialog(
      title: Text('Dictamen ${widget.kind} · ${p.title}'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Resumen', style: labCell(bold: true)),
            Text(p.abstract, style: labCell()),
            const SizedBox(height: 10),
            Text('Cuerpo', style: labCell(bold: true)),
            SelectableText(p.body, style: labCell()),
            const SizedBox(height: 10),
            Text('Paquete de reproducibilidad', style: labCell(bold: true)),
            SelectableText([
              'App: ${repro['appCommit'] ?? '—'} · Motor: ${repro['engineCommit'] ?? '—'}',
              'Corridas: ${((repro['runIds'] as List?) ?? const []).join(', ')}',
              'Datos: ${repro['datasetUrl'] ?? '—'}',
              'Procedimiento: ${repro['procedure'] ?? '—'}',
              'Preregistro: ${(repro['preregistration'] as Map?)?['hypotheses'] ?? '—'}',
              'Enmiendas: ${repro['amendments'] ?? 0}',
            ].join('\n'), style: GoogleFonts.robotoMono(fontSize: 12, color: OhtliColors.onyx)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              for (final d in ReviewDecision.values) ChoiceChip(label: Text(d.label), selected: _d == d, onSelected: (_) => setState(() => _d = d)),
            ]),
            const SizedBox(height: 10),
            labField(_c, 'Comentarios para los autores', maxLines: 6),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _d == null
              ? null
              : () async {
                  Navigator.pop(context);
                  await runLabAction(context, () => _repo.addReview(p, kind: widget.kind, decision: _d!, comments: _c.text.trim()),
                      ok: 'Dictamen enviado.');
                },
          child: const Text('Enviar dictamen'),
        ),
      ],
    );
  }
}

/// Revisiones pendientes: internas para científicos de Ohtli (que no son autores) y externas para
/// revisores invitados (tras firmar el NDA del estudio).
class LabReviewsPanel extends StatelessWidget {
  final LabRole role;
  const LabReviewsPanel({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    if (role.isReviewer) return const _ExternalReviews();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const LabSectionTitle('Revisiones pendientes', caption: 'Revisión interna de papers en los que no eres autor.'),
      StreamBuilder<List<LabPaper>>(
        stream: _repo.watchPapersAt(PaperStage.revisionInterna),
        builder: (c, snap) {
          final list = (snap.data ?? const <LabPaper>[]).where((p) => !p.authors.contains(_uid)).toList();
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) return LabCard(child: Text('No hay papers esperando tu revisión.', style: labCell()));
          return Column(children: [
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  child: Row(children: [
                    Expanded(child: Text('${p.title} · ronda ${p.round}', style: _h(15))),
                    FilledButton(onPressed: () => ReviewDialog.show(context, p, 'interna'), child: const Text('Dictaminar')),
                  ]),
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}

class _ExternalReviews extends StatelessWidget {
  const _ExternalReviews();

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const SizedBox.shrink();
    return FutureBuilder<List<String>>(
      future: LabAccess.reviewerStudies(uid),
      builder: (c, snap) {
        final ids = snap.data ?? const <String>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const LabSectionTitle('Tus revisiones',
              caption: 'Estudios a los que te invitaron como revisor externo. Firma el acuerdo de confidencialidad de cada uno para ver su paper.'),
          if (!snap.hasData) const Center(child: CircularProgressIndicator()),
          if (snap.hasData && ids.isEmpty) LabCard(child: Text('No tienes revisiones asignadas.', style: labCell())),
          for (final id in ids) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ExternalReviewCard(studyId: id)),
        ]);
      },
    );
  }
}

class _ExternalReviewCard extends StatefulWidget {
  final String studyId;
  const _ExternalReviewCard({required this.studyId});
  @override
  State<_ExternalReviewCard> createState() => _ExternalReviewCardState();
}

class _ExternalReviewCardState extends State<_ExternalReviewCard> {
  late Future<bool> _nda = _repo.hasNda(widget.studyId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LabResearchStudy?>(
      stream: _repo.watchStudy(widget.studyId),
      builder: (c, ss) {
        final s = ss.data;
        if (s == null) return const LabCard(child: Center(child: CircularProgressIndicator()));
        return FutureBuilder<bool>(
          future: _nda,
          builder: (c, nda) {
            final signed = nda.data == true;
            return LabCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: _h(16)),
                Text('Etapa del paper: ${s.paperStage?.label ?? 'sin paper'}', style: labCell()),
                const SizedBox(height: 10),
                if (!signed)
                  FilledButton.icon(
                    icon: const Icon(Icons.handshake_outlined),
                    onPressed: () async {
                      final ok = await NdaDialog.show(context, scopeLabel: s.title);
                      if (ok != true || !context.mounted) return;
                      await runLabAction(context, () => _repo.acceptNda(s.id, 'revisor-v1'), ok: 'Acuerdo firmado.');
                      setState(() => _nda = _repo.hasNda(s.id));
                    },
                    label: const Text('Leer y firmar el acuerdo de confidencialidad'),
                  )
                else if (s.currentPaperId != null && s.paperStage == PaperStage.revisionExterna)
                  FilledButton(
                    onPressed: () async {
                      final p = await _repo.paper(s.currentPaperId!);
                      if (p != null && context.mounted) await ReviewDialog.show(context, p, 'externa');
                    },
                    child: const Text('Revisar y dictaminar'),
                  )
                else
                  Text('Te avisaremos cuando el paper llegue a revisión externa.', style: labCell()),
              ]),
            );
          },
        );
      },
    );
  }
}

/// Acuerdo de confidencialidad (proyecto confidencial para testers o estudio para revisores).
class NdaDialog extends StatefulWidget {
  final String scopeLabel;
  const NdaDialog({super.key, required this.scopeLabel});

  static Future<bool?> show(BuildContext context, {required String scopeLabel}) =>
      showDialog<bool>(context: context, builder: (_) => NdaDialog(scopeLabel: scopeLabel));

  @override
  State<NdaDialog> createState() => _NdaDialogState();
}

class _NdaDialogState extends State<NdaDialog> {
  bool _ok = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Acuerdo de confidencialidad'),
        content: SizedBox(
          width: 540,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Para participar en «${widget.scopeLabel}» te comprometes a:\n\n'
              '1. No compartir, copiar ni divulgar la información, las funciones, los datos ni los resultados que veas.\n'
              '2. Usarlos solo para participar o revisar este estudio.\n'
              '3. Mantener la confidencialidad hasta que Ohtli desclasifique el proyecto y lo publique.\n'
              '4. Avisar a Ohtli Labs si detectas una filtración.\n\n'
              'Tu aceptación queda registrada con fecha. Puedes retirarte del estudio cuando quieras; el compromiso de '
              'confidencialidad sobre lo que ya viste se mantiene.',
              style: labCell(),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _ok,
              onChanged: (v) => setState(() => _ok = v == true),
              title: const Text('Leí y acepto el acuerdo de confidencialidad'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: _ok ? () => Navigator.pop(context, true) : null, child: const Text('Aceptar')),
        ],
      );
}
