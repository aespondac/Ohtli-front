import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../lab_widgets.dart';
import 'lab_models.dart';
import 'lab_research_repository.dart';
import 'member_check_dialog.dart';
import 'research_papers.dart' show NdaDialog;
import 'research_widgets.dart';

final _repo = LabResearch.instance;
TextStyle _h(double size) => GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: OhtliColors.onyx);

/// Estudios de la nueva estructura abiertos a testers (los del TT siguen con su flujo propio).
class LabOpenStudiesView extends StatelessWidget {
  const LabOpenStudiesView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LabResearchStudy>>(
      stream: _repo.watchStudies(),
      builder: (context, ss) => StreamBuilder<Map<String, int>>(
        stream: _repo.watchMyConsentVersions(),
        builder: (context, es) {
          final mine = es.data ?? const <String, int>{};
          final list = (ss.data ?? const <LabResearchStudy>[])
              .where((s) => s.builtinKind == null && (s.status.acceptsEnrollment || mine.containsKey(s.id)))
              .toList()
            ..sort((a, b) => (mine.containsKey(b.id) ? 1 : 0).compareTo(mine.containsKey(a.id) ? 1 : 0));
          if (list.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 8),
            const LabSectionTitle('Estudios de investigación',
                caption: 'Inscríbete para usar sus funciones en prueba y responder sus encuestas. Puedes darte de baja cuando quieras.'),
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OpenStudyCard(study: s, enrolled: mine.containsKey(s.id), consentVersion: mine[s.id]),
              ),
          ]);
        },
      ),
    );
  }
}

class _OpenStudyCard extends StatelessWidget {
  final LabResearchStudy study;
  final bool enrolled;
  final int? consentVersion;
  const _OpenStudyCard({required this.study, required this.enrolled, this.consentVersion});

  @override
  Widget build(BuildContext context) {
    final s = study;
    final needsReconsent = enrolled && (consentVersion ?? 1) < s.consentVersion;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.title, style: _h(18))),
          if (s.confidential) const ConfidentialTag(),
          const SizedBox(width: 6),
          LabTag(enrolled ? 'Inscrito' : s.status.label, color: enrolled ? OhtliColors.stormyTeal : studyStatusColor(s.status)),
        ]),
        const SizedBox(height: 6),
        if (s.description.isNotEmpty) Text(s.description, style: labCell()),
        if (s.config.eligibility.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Requisitos: ${s.config.eligibility}', style: labCell())),
        if (s.config.capacity > 0)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Lugares: ${s.enrolledCount} de ${s.config.capacity}', style: labCell())),
        const SizedBox(height: 12),
        if (!enrolled)
          FilledButton(
            onPressed: s.isFull || !s.status.acceptsEnrollment ? null : () => _enroll(context),
            child: Text(s.isFull ? 'Cupo lleno' : 'Inscribirme'),
          )
        else ...[
          if (needsReconsent)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.icon(
                icon: const Icon(Icons.update_rounded),
                onPressed: () async {
                  if (await _consent(context) != true || !context.mounted) return;
                  await runLabAction(context, () => _repo.reconsent(s), ok: 'Consentimiento actualizado.');
                },
                label: const Text('El consentimiento cambió: revísalo'),
              ),
            ),
          if (s.surveyIds.isNotEmpty) _Surveys(study: s),
          if (s.paperStage == PaperStage.validacionParticipantes && s.currentPaperId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () async {
                  final p = await _repo.paper(s.currentPaperId!);
                  if (p != null && context.mounted) await MemberCheckDialog.show(context, p);
                },
                label: const Text('Validar resultados'),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => _leave(context), child: const Text('Darme de baja')),
          ),
        ],
      ]),
    );
  }

  Future<bool?> _consent(BuildContext context) {
    var ok = false;
    return showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Consentimiento · ${study.title}'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(study.consentText.isEmpty ? 'Participación voluntaria y anónima.' : study.consentText, style: labCell()),
                const SizedBox(height: 10),
                Text('Versión ${study.consentVersion}. Puedes retirarte cuando quieras y pedir que se borren tus datos antes del análisis.',
                    style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ok,
                  onChanged: (v) => set(() => ok = v == true),
                  title: const Text('Acepto participar en este estudio'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: ok ? () => Navigator.pop(c, true) : null, child: const Text('Aceptar')),
          ],
        ),
      ),
    );
  }

  Future<void> _enroll(BuildContext context) async {
    final s = study;
    if (s.confidential && !await _repo.hasNda(s.projectId)) {
      if (!context.mounted) return;
      final ok = await NdaDialog.show(context, scopeLabel: s.title);
      if (ok != true || !context.mounted) return;
      await runLabAction(context, () => _repo.acceptNda(s.projectId, 'tester-v1'));
    }
    if (!context.mounted) return;
    if (await _consent(context) != true || !context.mounted) return;
    await runLabAction(context, () => _repo.enroll(s), ok: '¡Listo! Ya participas en ${s.title}. Sus funciones en prueba aparecen en Logros.');
  }

  Future<void> _leave(BuildContext context) async {
    var withdraw = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Darme de baja'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dejarás de ver las funciones en prueba de este estudio. Tus respuestas ya dadas se conservan anónimas.', style: labCell()),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: withdraw,
                onChanged: (v) => set(() => withdraw = v == true),
                title: const Text('Además, retirar mis datos del estudio'),
                subtitle: const Text('El laboratorio los borrará antes del análisis.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Darme de baja')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await runLabAction(context, () => _repo.leave(study, withdrawData: withdraw), ok: 'Te diste de baja.');
  }
}

Future<(LabSurvey?, bool)> _loadSurvey(String id) async => (await _repo.survey(id), await _repo.answeredSurvey(id));

class _Surveys extends StatelessWidget {
  final LabResearchStudy study;
  const _Surveys({required this.study});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Encuestas del estudio', style: labCell(bold: true)),
      const SizedBox(height: 4),
      for (final id in study.surveyIds.where((x) => x != 'sus'))
        FutureBuilder<(LabSurvey?, bool)>(
          future: _loadSurvey(id),
          builder: (c, snap) {
            final s = snap.data?.$1;
            if (s == null) return const SizedBox.shrink();
            final done = snap.data!.$2;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(done ? Icons.check_circle_rounded : Icons.ballot_outlined, color: done ? OhtliColors.stormyTeal : null),
              title: Text(s.title),
              subtitle: Text(done ? 'Respondida. ¡Gracias!' : (s.open ? '${s.questions.length} preguntas' : 'Aún no abre')),
              trailing: done || !s.open
                  ? null
                  : FilledButton(onPressed: () => SurveyFormDialog.show(context, s, studyId: study.id), child: const Text('Responder')),
            );
          },
        ),
    ]);
  }
}

/// Formulario para responder una encuesta.
class SurveyFormDialog extends StatefulWidget {
  final LabSurvey survey;
  final String? studyId;
  const SurveyFormDialog({super.key, required this.survey, this.studyId});

  static Future<void> show(BuildContext context, LabSurvey s, {String? studyId}) =>
      showDialog<void>(context: context, builder: (_) => SurveyFormDialog(survey: s, studyId: studyId));

  @override
  State<SurveyFormDialog> createState() => _SurveyFormDialogState();
}

class _SurveyFormDialogState extends State<SurveyFormDialog> {
  final Map<String, dynamic> _a = {};
  final Map<String, TextEditingController> _text = {};

  bool get _complete => widget.survey.questions.every((q) => q.accepts(_value(q)));

  dynamic _value(SurveyQuestion q) {
    if (q.type == SurveyQuestionType.text) return _text[q.id]?.text.trim();
    if (q.type == SurveyQuestionType.number) return num.tryParse(_text[q.id]?.text.trim() ?? '');
    return _a[q.id];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.survey;
    return AlertDialog(
      title: Text(s.title),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (s.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(s.description, style: labCell())),
            for (final q in s.questions) ...[
              Text('${q.text}${q.required ? '' : ' (opcional)'}', style: labCell(bold: true)),
              const SizedBox(height: 6),
              _input(q),
              const SizedBox(height: 14),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !_complete
              ? null
              : () async {
                  final answers = {
                    for (final q in s.questions)
                      if (_value(q) != null && !(_value(q) is String && (_value(q) as String).isEmpty)) q.id: _value(q),
                  };
                  Navigator.pop(context);
                  await runLabAction(context, () => _repo.answerSurvey(s, answers, studyId: widget.studyId), ok: 'Respuestas enviadas. ¡Gracias!');
                },
          child: const Text('Enviar'),
        ),
      ],
    );
  }

  Widget _input(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.likert5:
        return Wrap(spacing: 6, children: [
          for (var i = 1; i <= 5; i++) ChoiceChip(label: Text('$i'), selected: _a[q.id] == i, onSelected: (_) => setState(() => _a[q.id] = i)),
        ]);
      case SurveyQuestionType.single:
        return Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in q.options) ChoiceChip(label: Text(o), selected: _a[q.id] == o, onSelected: (_) => setState(() => _a[q.id] = o)),
        ]);
      case SurveyQuestionType.multi:
        final sel = (_a[q.id] as List?)?.cast<String>() ?? <String>[];
        return Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in q.options)
            FilterChip(
              label: Text(o),
              selected: sel.contains(o),
              onSelected: (v) => setState(() => _a[q.id] = v ? [...sel, o] : sel.where((x) => x != o).toList()),
            ),
        ]);
      case SurveyQuestionType.number:
      case SurveyQuestionType.text:
        return TextField(
          controller: _text.putIfAbsent(q.id, TextEditingController.new),
          keyboardType: q.type == SurveyQuestionType.number ? TextInputType.number : TextInputType.multiline,
          maxLines: q.type == SurveyQuestionType.text ? 3 : 1,
          maxLength: q.type == SurveyQuestionType.text ? 1000 : null,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        );
    }
  }
}
