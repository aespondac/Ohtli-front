import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../lab_access.dart';
import '../lab_catalog.dart';
import '../lab_widgets.dart';
import 'lab_import.dart';
import 'lab_models.dart';
import 'lab_research_repository.dart';
import 'research_papers.dart';
import 'research_widgets.dart';

String? get _uid => FirebaseAuth.instance.currentUser?.uid;
final _repo = LabResearch.instance;

TextStyle _h(double size) => GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: OhtliColors.onyx);

// ═════════════════════════════ Proyectos ═════════════════════════════

class LabProjectsPanel extends StatelessWidget {
  final LabRole role;

  /// Abre un proyecto en la consola (selector de proyecto).
  final ValueChanged<String>? onOpen;
  const LabProjectsPanel({super.key, required this.role, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(
          child: LabSectionTitle('Proyectos',
              caption: 'Agrupan estudios. Un proyecto confidencial se muestra con su nombre en clave hasta que el admin lo desclasifique.'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final id = await showCreateProjectDialog(context);
            if (id != null) onOpen?.call(id);
          },
          icon: const Icon(Icons.add),
          label: const Text('Nuevo proyecto'),
        ),
      ]),
      StreamBuilder<List<LabProject>>(
        stream: _repo.watchProjects(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!..sort((a, b) => a.name.compareTo(b.name));
          if (list.isEmpty) return LabCard(child: Text('Aún no hay proyectos.', style: labCell()));
          return Column(children: [
            for (final p in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _ProjectCard(project: p, role: role, onOpen: onOpen)),
          ]);
        },
      ),
    ]);
  }

}

/// Diálogo "Nuevo proyecto". Devuelve el id del proyecto creado (o null si se canceló o falló).
Future<String?> showCreateProjectDialog(BuildContext context) async {
    final name = TextEditingController(), desc = TextEditingController();
    var confidential = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Nuevo proyecto'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              labField(name, 'Nombre'),
              labField(desc, 'Descripción', maxLines: 3),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: confidential,
                onChanged: (v) => set(() => confidential = v),
                title: const Text('Confidencial'),
                subtitle: const Text('Recibe un nombre en clave único; el nombre real solo lo ven sus miembros. '
                    'No se publica en el blog hasta que el admin lo desclasifique.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return null;
    String? id;
    await runLabAction(context, () async {
      id = await _repo.createProject(name: name.text.trim(), description: desc.text.trim(), confidential: confidential);
    }, ok: confidential ? 'Proyecto creado con nombre en clave.' : 'Proyecto creado.');
    return id;
}

class _ProjectCard extends StatelessWidget {
  final LabProject project;
  final LabRole role;
  final ValueChanged<String>? onOpen;
  const _ProjectCard({required this.project, required this.role, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = project;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: RevealedText(
              masked: p.name,
              confidential: p.confidential,
              load: () => SecretCache.project(p.id),
              field: 'name',
              style: _h(17),
            ),
          ),
          if (p.confidential) const ConfidentialTag(),
          if (p.declassifiedAt != null) LabTag('Desclasificado', color: OhtliColors.stormyTeal),
        ]),
        const SizedBox(height: 4),
        RevealedText(
          masked: p.description,
          confidential: p.confidential,
          load: () => SecretCache.project(p.id),
          field: 'description',
          style: labCell(),
        ),
        const SizedBox(height: 6),
        Text('${p.iam.length} acceso(s) en IAM · se gestionan en Configuración del proyecto',
            style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (onOpen != null)
            FilledButton.tonalIcon(
              onPressed: () => onOpen!(p.id),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Abrir'),
            ),
          if (p.confidential && role == LabRole.admin)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: OhtliColors.warningText),
              onPressed: () async {
                if (!await confirmLab(context, 'Desclasificar ${p.name}',
                    'Se revelará el nombre real del proyecto y de todo lo que cuelga de él (estudios, experimentos, encuestas, '
                    'funciones y papers), y podrá publicarse en el blog. No se puede deshacer.',
                    confirm: 'Desclasificar')) {
                  return;
                }
                if (!context.mounted) return;
                await runLabAction(context, () async {
                  final n = await _repo.declassify(p.id);
                  SecretCache.forget('project:${p.id}');
                  debugPrint('[Labs] desclasificados $n elementos');
                }, ok: 'Proyecto desclasificado.');
              },
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Desclasificar'),
            ),
        ]),
      ]),
    );
  }


}

// ═════════════════════════════ Estudios ═════════════════════════════

class LabStudiesPanel extends StatefulWidget {
  final LabRole role;

  /// Solo los estudios de este proyecto (consola por proyectos). Sin él, todos agrupados.
  final LabProject? project;

  /// Abre el estudio en su propia página (consola por proyectos); sin él, se edita aquí mismo.
  final ValueChanged<String>? onOpen;
  const LabStudiesPanel({super.key, required this.role, this.project, this.onOpen});

  @override
  State<LabStudiesPanel> createState() => _LabStudiesPanelState();
}

class _LabStudiesPanelState extends State<LabStudiesPanel> {
  String? _open;

  @override
  void initState() {
    super.initState();
    // Las pruebas del TT entran a la estructura como estudios del proyecto "Trabajo Terminal".
    if (widget.role == LabRole.admin) {
      _repo.ensureTtStudies().catchError((e) => debugPrint('[Labs] TT: $e'));
      _repo.ensureBaseProjects().catchError((e) => debugPrint('[Labs] proyectos base: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_open != null) {
      return LabStudyEditor(studyId: _open!, role: widget.role, onBack: () => setState(() => _open = null));
    }
    return StreamBuilder<List<LabProject>>(
      stream: _repo.watchProjects(),
      builder: (context, ps) => StreamBuilder<List<LabResearchStudy>>(
        stream: _repo.watchStudies(),
        builder: (context, ss) {
          final scope = widget.project;
          final projects = scope != null ? [scope] : (ps.data ?? const <LabProject>[]);
          // En un proyecto, las pruebas del TT y relevancia/SUS se ven como experimentos y encuestas.
          final studies = [
            for (final s in ss.data ?? const <LabResearchStudy>[])
              if (scope == null || (s.projectId == scope.id && !s.legacyHolder)) s,
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(
                child: LabSectionTitle('Estudios',
                    caption: 'Borrador → preregistrado → reclutando → en curso → análisis → en revisión → publicado.'),
              ),
              FilledButton.icon(
                onPressed: projects.isEmpty ? null : () => _create(context, projects),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo estudio'),
              ),
            ]),
            if (!ss.hasData) const Center(child: CircularProgressIndicator()),
            if (scope != null && ss.hasData && studies.isEmpty)
              LabCard(child: Text('Este proyecto aún no tiene estudios.', style: labCell())),
            if (scope != null)
              for (final s in studies)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _StudyRow(study: s, onOpen: () => widget.onOpen != null ? widget.onOpen!(s.id) : setState(() => _open = s.id)))
            else
              for (final p in projects..sort((a, b) => a.name.compareTo(b.name)))
              if (studies.any((s) => s.projectId == p.id)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Row(children: [
                    Text(p.name.toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: OhtliColors.subtleText)),
                    if (p.confidential) ...[const SizedBox(width: 8), const ConfidentialTag()],
                  ]),
                ),
                for (final s in studies.where((s) => s.projectId == p.id))
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: _StudyRow(study: s, onOpen: () => widget.onOpen != null ? widget.onOpen!(s.id) : setState(() => _open = s.id))),
              ],
          ]);
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, List<LabProject> projects) async {
    final title = TextEditingController(), desc = TextEditingController();
    var project = widget.project ?? projects.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Nuevo estudio'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.project == null)
              DropdownButtonFormField<LabProject>(
                initialValue: project,
                decoration: const InputDecoration(labelText: 'Proyecto', border: OutlineInputBorder(), isDense: true),
                items: [for (final p in projects) DropdownMenuItem(value: p, child: Text(p.name))],
                onChanged: (v) => set(() => project = v ?? project),
              ),
              const SizedBox(height: 12),
              labField(title, 'Título'),
              labField(desc, 'Descripción', maxLines: 3),
              if (project.confidential)
                Text('El estudio se verá como «${project.codename} · Estudio N» para quien no sea del proyecto.', style: labCell()),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await runLabAction(context, () async {
      final id = await _repo.createStudy(project: project, title: title.text.trim(), description: desc.text.trim());
      if (!mounted) return;
      if (widget.onOpen != null) {
        widget.onOpen!(id);
      } else {
        setState(() => _open = id);
      }
    });
  }
}

class _StudyRow extends StatelessWidget {
  final LabResearchStudy study;
  final VoidCallback onOpen;
  const _StudyRow({required this.study, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = study;
    return Material(
      color: OhtliColors.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: OhtliColors.cardBorder)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                RevealedText(
                  masked: s.title,
                  confidential: s.confidential,
                  load: () => SecretCache.study(s.id),
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: OhtliColors.onyx),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.enrolledCount} inscritos · ${s.metrics.length} métricas · ${s.experimentIds.length} experimentos · '
                  '${s.surveyIds.length} encuestas · ${s.featureKeys.length} funciones',
                  style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText),
                ),
              ]),
            ),
            if (s.paperStage != null) ...[LabTag('Paper: ${s.paperStage!.label}', color: OhtliColors.accent), const SizedBox(width: 6)],
            LabTag(s.status.label, color: studyStatusColor(s.status)),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

/// Editor de un estudio: datos, preregistro, componentes, estado, proyecto, paper y bitácora.
/// Partes del editor de estudios: todo junto (vista anterior) o por pestaña de la página del estudio.
enum LabStudyPart { all, summary, state, paper }

class LabStudyEditor extends StatelessWidget {
  final String studyId;
  final LabRole role;
  final VoidCallback onBack;
  final LabStudyPart part;

  /// Permiso de edición calculado con el IAM (consola por proyectos). Sin él, el modelo anterior.
  final bool? editable;
  const LabStudyEditor({
    super.key,
    required this.studyId,
    required this.role,
    required this.onBack,
    this.part = LabStudyPart.all,
    this.editable,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LabResearchStudy?>(
      stream: _repo.watchStudy(studyId),
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) return const Center(child: CircularProgressIndicator());
        final editable = this.editable ?? (s.canEdit(_uid, admin: role == LabRole.admin) || s.builtinKind != null);
        switch (part) {
          case LabStudyPart.summary:
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _StudyInfoCard(key: ValueKey('info-${s.id}'), study: s, editable: editable),
              const SizedBox(height: 12),
              _PreregCard(key: ValueKey('prereg-${s.id}-${s.amendments}-${s.frozenAt != null}'), study: s, editable: editable),
              const SizedBox(height: 12),
              _ComponentsCard(study: s, editable: editable),
            ]);
          case LabStudyPart.state:
            return _StudyHeader(study: s, role: role, editable: editable);
          case LabStudyPart.paper:
            return LabPaperPanel(study: s, role: role);
          case LabStudyPart.all:
            break;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back), label: const Text('Estudios'))),
          _StudyHeader(study: s, role: role, editable: editable),
          const SizedBox(height: 12),
          _StudyInfoCard(key: ValueKey('info-${s.id}'), study: s, editable: editable),
          const SizedBox(height: 12),
          _PreregCard(key: ValueKey('prereg-${s.id}-${s.amendments}-${s.frozenAt != null}'), study: s, editable: editable),
          const SizedBox(height: 12),
          _ComponentsCard(study: s, editable: editable),
          const SizedBox(height: 12),
          LabPaperPanel(study: s, role: role),
          const SizedBox(height: 12),
          _AuditCard(target: 'study:${s.id}'),
        ]);
      },
    );
  }
}

class _StudyHeader extends StatelessWidget {
  final LabResearchStudy study;
  final LabRole role;
  final bool editable;
  const _StudyHeader({required this.study, required this.role, required this.editable});

  @override
  Widget build(BuildContext context) {
    final s = study;
    final next = kStudyTransitions[s.status] ?? const [];
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: RevealedText(masked: s.title, confidential: s.confidential, load: () => SecretCache.study(s.id), style: _h(20))),
          if (s.confidential) const ConfidentialTag(),
          const SizedBox(width: 6),
          LabTag(s.status.label, color: studyStatusColor(s.status)),
        ]),
        const SizedBox(height: 6),
        Text('${s.enrolledCount}${s.config.capacity > 0 ? ' de ${s.config.capacity}' : ''} inscritos'
            '${s.builtinKind != null ? ' · prueba del TT (su panel está en «Pruebas del TT»)' : ''}',
            style: labCell()),
        if (editable && next.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final to in next)
              if (to != StudyStatus.preregistrado) // se llega congelando el preregistro
                (to == StudyStatus.cancelado || to == StudyStatus.pausado)
                    ? OutlinedButton(onPressed: () => _go(context, to), child: Text(to.label))
                    : FilledButton(onPressed: () => _go(context, to), child: Text('Pasar a «${to.label}»')),
            StreamBuilder<List<LabProject>>(
              stream: _repo.watchProjects(),
              builder: (c, ps) => PopupMenuButton<LabProject>(
                tooltip: 'Cambiar de proyecto',
                itemBuilder: (_) => [
                  for (final p in ps.data ?? const <LabProject>[])
                    if (p.id != s.projectId && !(s.confidential && !p.confidential)) PopupMenuItem(value: p, child: Text(p.name)),
                ],
                onSelected: (p) => runLabAction(context, () => _repo.moveStudy(s, p), ok: 'Estudio movido a ${p.name}.'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.drive_file_move_outline, size: 18), SizedBox(width: 6), Text('Cambiar de proyecto')]),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Future<void> _go(BuildContext context, StudyStatus to) async {
    final s = study;
    if (to == StudyStatus.reclutando && s.consentText.trim().isEmpty && s.builtinKind == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el consentimiento del estudio antes de reclutar.')));
      return;
    }
    if (to == StudyStatus.enRevision && s.currentPaperId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crea el paper del estudio antes de pasarlo a revisión.')));
      return;
    }
    if (to == StudyStatus.publicado) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El estudio se publica al publicar su paper aprobado.')));
      return;
    }
    if (to == StudyStatus.cancelado && !await confirmLab(context, 'Cancelar estudio', 'El estudio se cierra y no podrá reabrirse.')) return;
    if (!context.mounted) return;
    await runLabAction(context, () => _repo.transition(s, to), ok: 'Estado: ${to.label}.');
  }
}

class _StudyInfoCard extends StatefulWidget {
  final LabResearchStudy study;
  final bool editable;
  const _StudyInfoCard({super.key, required this.study, required this.editable});

  @override
  State<_StudyInfoCard> createState() => _StudyInfoCardState();
}

class _StudyInfoCardState extends State<_StudyInfoCard> {
  late final _title = TextEditingController(text: widget.study.title);
  late final _desc = TextEditingController(text: widget.study.description);
  late final _consent = TextEditingController(text: widget.study.consentText);
  late final _capacity = TextEditingController(text: '${widget.study.config.capacity}');
  late final _eligibility = TextEditingController(text: widget.study.config.eligibility);
  late final _minRev = TextEditingController(text: '${widget.study.config.minExternalReviewers}');
  late bool _external = widget.study.config.externalReview;
  late bool _participants = widget.study.config.participantValidation;

  @override
  void initState() {
    super.initState();
    if (widget.study.confidential) {
      SecretCache.study(widget.study.id).then((d) {
        if (d == null || !mounted) return;
        setState(() {
          _title.text = (d['title'] ?? _title.text).toString();
          _desc.text = (d['description'] ?? _desc.text).toString();
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.study;
    final e = widget.editable;
    final locked = s.status.index >= StudyStatus.reclutando.index && s.status != StudyStatus.pausado;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Datos y configuración', style: _h(16)),
        const SizedBox(height: 12),
        labField(_title, s.confidential ? 'Título real (solo lo ve el proyecto)' : 'Título', enabled: e),
        labField(_desc, 'Descripción', maxLines: 3, enabled: e),
        labField(_consent, 'Consentimiento del estudio (lo acepta cada tester al inscribirse)', maxLines: 5, enabled: e),
        if (locked && e)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Cambiar el consentimiento con el estudio abierto sube su versión; los inscritos lo verán de nuevo.', style: labCell()),
          ),
        Row(children: [
          Expanded(child: labField(_capacity, 'Cupo (0 = sin límite)', enabled: e, keyboard: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: labField(_eligibility, 'Requisitos para participar', enabled: e)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _participants,
          onChanged: e ? (v) => setState(() => _participants = v) : null,
          title: const Text('Validación de participantes'),
          subtitle: const Text('Los testers inscritos confirman si se ven reflejados en los resultados (quórum y 2/3 de apoyo).'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _external,
          onChanged: e ? (v) => setState(() => _external = v) : null,
          title: const Text('Revisión externa por científicos invitados'),
          subtitle: const Text('Con NDA y paquete de reproducibilidad.'),
        ),
        if (_external) labField(_minRev, 'Mínimo de revisores externos', enabled: e, keyboard: TextInputType.number),
        if (e)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                final consentChanged = _consent.text.trim() != s.consentText.trim();
                final config = StudyConfig(
                  externalReview: _external,
                  minExternalReviewers: int.tryParse(_minRev.text) ?? 2,
                  participantValidation: _participants,
                  capacity: int.tryParse(_capacity.text) ?? 0,
                  eligibility: _eligibility.text.trim(),
                );
                final data = <String, dynamic>{
                  if (!s.confidential) 'title': _title.text.trim(),
                  if (!s.confidential) 'description': _desc.text.trim(),
                  'consentText': _consent.text.trim(),
                  if (consentChanged && locked) 'consentVersion': s.consentVersion + 1,
                  'config': config.toMap(),
                };
                runLabAction(
                  context,
                  () => _repo.updateStudy(s, data, secret: {'title': _title.text.trim(), 'description': _desc.text.trim()}),
                  ok: 'Estudio guardado.',
                );
              },
              child: const Text('Guardar'),
            ),
          ),
      ]),
    );
  }
}

class _PreregCard extends StatefulWidget {
  final LabResearchStudy study;
  final bool editable;
  const _PreregCard({super.key, required this.study, required this.editable});

  @override
  State<_PreregCard> createState() => _PreregCardState();
}

class _PreregCardState extends State<_PreregCard> {
  late final _hyp = TextEditingController(text: widget.study.hypotheses);
  late final _plan = TextEditingController(text: widget.study.analysisPlan);
  late List<LabMetric> _metrics = [...widget.study.metrics];
  bool _amending = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.study;
    final frozen = s.frozenAt != null;
    final canType = widget.editable && (!frozen || _amending);
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Preregistro', style: _h(16))),
          if (frozen)
            LabTag('Congelado ${s.frozenAt!.day}/${s.frozenAt!.month}/${s.frozenAt!.year}'
                '${s.amendments > 0 ? ' · ${s.amendments} enmienda(s)' : ''}', color: const Color(0xFF6C5CE7), icon: Icons.lock_clock_outlined),
        ]),
        const SizedBox(height: 4),
        Text('Hipótesis, métricas y plan de análisis se fijan antes de medir. Después solo cambian con una enmienda registrada.',
            style: labCell()),
        const SizedBox(height: 12),
        labField(_hyp, 'Hipótesis', maxLines: 4, enabled: canType),
        labField(_plan, 'Plan de análisis', maxLines: 4, enabled: canType),
        Text('Métricas', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: OhtliColors.onyx)),
        const SizedBox(height: 6),
        for (var i = 0; i < _metrics.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.straighten_rounded, size: 18),
            title: Text(_metrics[i].name),
            subtitle: Text([
              if (_metrics[i].formula.isNotEmpty) _metrics[i].formula,
              if (_metrics[i].unit.isNotEmpty) _metrics[i].unit,
              if (_metrics[i].successThreshold.isNotEmpty) 'éxito: ${_metrics[i].successThreshold}',
            ].join(' · ')),
            trailing: canType
                ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _metrics.removeAt(i)))
                : null,
          ),
        if (canType) TextButton.icon(onPressed: _addMetric, icon: const Icon(Icons.add), label: const Text('Agregar métrica')),
        if (widget.editable) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (!frozen) ...[
              OutlinedButton(
                onPressed: () => runLabAction(context, () => _repo.saveDraftPrereg(s, _hyp.text, _plan.text, _metrics), ok: 'Borrador guardado.'),
                child: const Text('Guardar borrador'),
              ),
              if (s.status == StudyStatus.borrador)
                FilledButton.icon(
                  icon: const Icon(Icons.lock_outline, size: 16),
                  onPressed: () async {
                    if (!await confirmLab(context, 'Congelar preregistro',
                        'Hipótesis, métricas y plan quedarán fijos con fecha. Después solo se cambian con una enmienda que queda en la bitácora y en el paper.')) {
                      return;
                    }
                    if (!context.mounted) return;
                    await runLabAction(context, () => _repo.freeze(s, _hyp.text, _plan.text, _metrics), ok: 'Preregistro congelado.');
                  },
                  label: const Text('Congelar y preregistrar'),
                ),
            ] else if (!_amending)
              OutlinedButton(onPressed: () => setState(() => _amending = true), child: const Text('Enmendar'))
            else ...[
              TextButton(
                onPressed: () => setState(() {
                  _amending = false;
                  _hyp.text = s.hypotheses;
                  _plan.text = s.analysisPlan;
                  _metrics = [...s.metrics];
                }),
                child: const Text('Descartar'),
              ),
              FilledButton(onPressed: _amend, child: const Text('Registrar enmienda')),
            ],
          ]),
        ],
      ]),
    );
  }

  Future<void> _amend() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Motivo de la enmienda'),
        content: SizedBox(width: 460, child: labField(reason, 'Por qué cambia el preregistro', maxLines: 4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await runLabAction(context, () async {
      await _repo.amend(widget.study, reason.text, _hyp.text, _plan.text, _metrics);
      if (mounted) setState(() => _amending = false);
    }, ok: 'Enmienda registrada.');
  }

  Future<void> _addMetric() async {
    final name = TextEditingController(), formula = TextEditingController(), unit = TextEditingController(), th = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nueva métrica'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            labField(name, 'Nombre (p. ej. Puntaje SUS)'),
            labField(formula, 'Cómo se calcula'),
            labField(unit, 'Unidad'),
            labField(th, 'Umbral de éxito (p. ej. ≥ 68)'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    setState(() => _metrics.add(LabMetric(
          id: 'm${DateTime.now().millisecondsSinceEpoch}',
          name: name.text.trim(),
          formula: formula.text.trim(),
          unit: unit.text.trim(),
          successThreshold: th.text.trim(),
        )));
  }
}

/// Experimentos, encuestas y funcionalidades que usa el estudio.
class _ComponentsCard extends StatelessWidget {
  final LabResearchStudy study;
  final bool editable;
  const _ComponentsCard({required this.study, required this.editable});

  @override
  Widget build(BuildContext context) {
    final s = study;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Componentes', style: _h(16)),
        const SizedBox(height: 4),
        Text('Usa los experimentos y encuestas de este proyecto o los que otros proyectos comparten, y las funciones '
            'de la app que mide este estudio.',
            style: labCell()),
        const SizedBox(height: 12),
        StreamBuilder<List<LabProject>>(
          stream: _repo.watchProjects(),
          builder: (c, ps) {
            final names = {for (final p in ps.data ?? const <LabProject>[]) p.id: p.name};
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StreamBuilder<List<LabLibraryExperiment>>(
                stream: _repo.watchLibrary(),
                builder: (c, lib) => StreamBuilder<List<LabLibraryExperiment>>(
                  stream: _repo.watchProjectExperiments(s.projectId),
                  builder: (c, mine) => _picker(
                    context,
                    label: 'Experimentos',
                    icon: Icons.science_outlined,
                    all: const {},
                    split: splitImportables(
                      projectId: s.projectId,
                      builtins: {for (final b in builtinExperimentsOf(s.projectId)) b.id: b.title},
                      items: [
                        for (final e in [...?mine.data, ...?lib.data])
                          if (!e.builtin || e.projectId != null)
                            LabImportable(id: e.id, title: e.title, projectId: e.projectId, shared: e.shared, confidential: e.confidential),
                      ],
                      projectNames: names,
                      selected: s.experimentIds,
                    ),
                    selected: s.experimentIds,
                    field: 'experimentIds',
                  ),
                ),
              ),
              StreamBuilder<List<LabSurvey>>(
                stream: _repo.watchSurveys(),
                builder: (c, lib) => StreamBuilder<List<LabSurvey>>(
                  stream: _repo.watchProjectSurveys(s.projectId),
                  builder: (c, mine) => _picker(
                    context,
                    label: 'Encuestas',
                    icon: Icons.ballot_outlined,
                    all: const {},
                    split: splitImportables(
                      projectId: s.projectId,
                      // SUS es el cuestionario estándar: cualquier estudio puede usarlo.
                      builtins: {for (final b in builtinSurveysOf(s.projectId)) b.id: b.title, 'sus': 'SUS (usabilidad)'},
                      items: [
                        for (final q in [...?mine.data, ...?lib.data])
                          LabImportable(id: q.id, title: q.title, projectId: q.projectId, shared: q.shared, confidential: q.confidential),
                      ],
                      projectNames: names,
                      selected: s.surveyIds,
                    ),
                    selected: s.surveyIds,
                    field: 'surveyIds',
                  ),
                ),
              ),
            ]);
          },
        ),
        StreamBuilder<List<LabFeature>>(
          stream: _repo.watchFeatures(),
          builder: (c, snap) => _picker(
            context,
            label: 'Funcionalidades',
            icon: Icons.toggle_on_outlined,
            all: {for (final f in snap.data ?? const <LabFeature>[]) f.key: '${f.name} (${f.stage.label})'},
            selected: s.featureKeys,
            field: 'featureKeys',
            onChanged: (keys) async {
              // La función sabe en qué estudios está (la puerta y las reglas lo leen de ella).
              for (final f in snap.data ?? const <LabFeature>[]) {
                final has = f.studyIds.contains(s.id);
                final want = keys.contains(f.key);
                if (has != want) {
                  await _repo.saveFeature(f.key, {'studyIds': want ? [...f.studyIds, s.id] : f.studyIds.where((x) => x != s.id).toList()});
                }
              }
            },
          ),
        ),
      ]),
    );
  }

  Widget _picker(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Map<String, String> all,
    required List<String> selected,
    required String field,
    Future<void> Function(List<String>)? onChanged,
    LabImportSplit? split,
  }) {
    String labelOf(String id) => split?.labelOf(id) ?? all[id] ?? id;
    PopupMenuItem<String> header(String t) => PopupMenuItem<String>(
          enabled: false,
          height: 30,
          child: Text(t, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: OhtliColors.subtleText)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600))]),
          ),
        ),
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in selected)
              InputChip(
                avatar: split?.stale.containsKey(id) == true ? Icon(Icons.warning_amber_rounded, size: 16, color: OhtliColors.xoconostle) : null,
                label: Text(labelOf(id)),
                onDeleted: editable
                    ? () => runLabAction(context, () async {
                          final next = selected.where((x) => x != id).toList();
                          await _repo.updateStudy(study, {field: next});
                          await onChanged?.call(next);
                        })
                    : null,
              ),
            if (editable)
              PopupMenuButton<String>(
                tooltip: 'Agregar',
                itemBuilder: (_) => split == null
                    ? [
                        for (final e in all.entries)
                          if (!selected.contains(e.key)) PopupMenuItem(value: e.key, child: Text(e.value)),
                      ]
                    : [
                        header('DE ESTE PROYECTO'),
                        for (final e in split.own.entries)
                          if (!selected.contains(e.key)) PopupMenuItem(value: e.key, child: Text(e.value)),
                        if (split.shared.keys.any((k) => !selected.contains(k))) ...[
                          header('COMPARTIDOS POR OTROS PROYECTOS'),
                          for (final e in split.shared.entries)
                            if (!selected.contains(e.key)) PopupMenuItem(value: e.key, child: Text(e.value)),
                        ],
                      ],
                onSelected: (id) => runLabAction(context, () async {
                  final next = [...selected, id];
                  await _repo.updateStudy(study, {field: next});
                  await onChanged?.call(next);
                }),
                child: const Chip(avatar: Icon(Icons.add, size: 16), label: Text('Agregar')),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _AuditCard extends StatelessWidget {
  final String? target;
  const _AuditCard({this.target});

  @override
  Widget build(BuildContext context) {
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Bitácora', style: _h(16)),
        const SizedBox(height: 4),
        Text('Solo se agrega: nadie puede editarla ni borrarla.', style: labCell()),
        const SizedBox(height: 8),
        StreamBuilder(
          stream: _repo.watchAudit(limit: 300),
          builder: (c, snap) {
            final docs = (snap.data?.docs ?? const []).where((d) => target == null || d.data()['target'] == target).take(60).toList();
            if (docs.isEmpty) return Text('Sin movimientos todavía.', style: labCell());
            return Column(children: [
              for (final d in docs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded, size: 18),
                  title: Text(_auditLabel(d.data()['action']?.toString() ?? ''), style: labCell(bold: true)),
                  subtitle: Text([
                    if (target == null) d.data()['target']?.toString() ?? '',
                    _auditDetail(d.data()['detail']),
                  ].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: Text(fmtDate(d.data()['at']), style: GoogleFonts.inter(fontSize: 11, color: OhtliColors.subtleText)),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

String _auditDetail(dynamic d) {
  if (d is! Map || d.isEmpty) return '';
  return [
    for (final e in d.entries)
      if (e.key != 'before') '${e.key}: ${e.value}',
  ].join(', ');
}

String _auditLabel(String a) => switch (a) {
      'project.create' => 'Proyecto creado',
      'project.members' => 'Miembros del proyecto',
      'project.declassify' => 'Proyecto desclasificado',
      'study.create' => 'Estudio creado',
      'study.preregister' => 'Preregistro congelado',
      'study.amend' => 'Enmienda al preregistro',
      'study.status' => 'Cambio de estado',
      'study.move' => 'Cambio de proyecto',
      'study.enroll' => 'Inscripción de un tester',
      'study.leave' => 'Baja de un tester',
      'paper.create' => 'Paper creado',
      'paper.stage' => 'Etapa del paper',
      'paper.review' => 'Dictamen',
      'paper.check_extend' => 'Validación extendida',
      'paper.publish' => 'Publicado en el blog',
      'feature.save' => 'Funcionalidad guardada',
      'feature.stage' => 'Destino de la funcionalidad',
      'nda.accept' => 'NDA aceptado',
      _ => a,
    };


// ═════════════════════════════ Biblioteca de experimentos ═════════════════════════════

class LabLibraryPanel extends StatelessWidget {
  /// Solo los experimentos de este proyecto, con los integrados del catálogo primero.
  final LabProject? project;

  /// Abre un experimento integrado del proyecto (su pantalla o el runner de la prueba del TT).
  final ValueChanged<String>? onOpen;
  const LabLibraryPanel({super.key, this.project, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scope = project;
    final builtins = scope == null ? const <LabBuiltinExperiment>[] : builtinExperimentsOf(scope.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: scope == null
              ? const LabSectionTitle('Biblioteca de experimentos',
                  caption: 'Públicos y reutilizables por cualquier científico en su estudio (los clasificados no aparecen aquí).')
              : const LabSectionTitle('Experimentos',
                  caption: 'Miden o prueban una funcionalidad del sistema o su interacción. Los integrados se ejecutan aquí mismo.'),
        ),
        FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Nuevo experimento')),
      ]),
      for (final b in builtins)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LabCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(b.title, style: _h(15))),
                    const SizedBox(width: 8),
                    LabTag(b.ttRunner != null ? 'Prueba del TT' : 'Integrado', color: OhtliColors.stormyTeal),
                  ]),
                  const SizedBox(height: 4),
                  Text(b.description, style: labCell()),
                ]),
              ),
              if (onOpen != null) FilledButton.tonal(onPressed: () => onOpen!(b.id), child: const Text('Abrir')),
            ]),
          ),
        ),
      StreamBuilder<List<LabLibraryExperiment>>(
        stream: scope == null ? _repo.watchLibrary() : _repo.watchProjectExperiments(scope.id),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final builtinIds = {for (final b in builtins) b.id};
          final list = [for (final e in snap.data!) if (!builtinIds.contains(e.id)) e];
          if (scope != null && list.isEmpty && builtins.isEmpty) {
            return LabCard(child: Text('Este proyecto aún no tiene experimentos.', style: labCell()));
          }
          return Column(children: [
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(e.title, style: _h(15))),
                          const SizedBox(width: 8),
                          if (e.builtin) LabTag('Integrado', color: OhtliColors.stormyTeal) else LabTag('Protocolo', color: OhtliColors.accent),
                        ]),
                        const SizedBox(height: 4),
                        Text(e.description, style: labCell()),
                        if (e.metricNames.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Mide: ${e.metricNames.join(' · ')}', style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
                          ),
                      ]),
                    ),
                    if (!e.builtin && e.ownerUid == _uid)
                      IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, e)),
                    if (onOpen != null) FilledButton.tonal(onPressed: () => onOpen!(e.id), child: const Text('Abrir')),
                  ]),
                ),
              ),
          ]);
        },
      ),
    ]);
  }

  Future<void> _edit(BuildContext context, LabLibraryExperiment? e) async {
    final title = TextEditingController(text: e?.title), desc = TextEditingController(text: e?.description);
    final proc = TextEditingController(text: e?.procedure), metrics = TextEditingController(text: e?.metricNames.join(', '));
    LabProject? project = this.project;
    final projects = await _repo.watchProjects().first;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(e == null ? 'Nuevo experimento' : 'Editar experimento'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                labField(title, 'Título'),
                labField(desc, 'Qué evalúa', maxLines: 2),
                labField(proc, 'Procedimiento (para que otro lo pueda repetir)', maxLines: 6),
                labField(metrics, 'Métricas que produce (separadas por coma)'),
                if (e == null && this.project == null)
                  DropdownButtonFormField<LabProject?>(
                    initialValue: project,
                    decoration: const InputDecoration(labelText: 'Proyecto (opcional)', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Ninguno: público')),
                      for (final p in projects) DropdownMenuItem(value: p, child: Text('${p.name}${p.confidential ? ' (clasificado)' : ''}')),
                    ],
                    onChanged: (v) => set(() => project = v),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await runLabAction(
      context,
      () => _repo.saveExperiment(e?.id, {
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'procedure': proc.text.trim(),
        'metricNames': [for (final m in metrics.text.split(',')) if (m.trim().isNotEmpty) m.trim()],
        'builtin': false,
      }, project: project),
      ok: 'Experimento guardado.',
    );
  }
}

// ═════════════════════════════ Encuestas ═════════════════════════════

class LabSurveysPanel extends StatelessWidget {
  /// Solo las encuestas de este proyecto, con las integradas (relevancia, SUS) primero.
  final LabProject? project;

  /// Abre una encuesta integrada (su panel de resultados y apertura a testers).
  final ValueChanged<String>? onOpen;
  const LabSurveysPanel({super.key, this.project, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scope = project;
    final builtins = scope == null ? const <LabBuiltinSurvey>[] : builtinSurveysOf(scope.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: LabSectionTitle('Encuestas', caption: 'Cualquier científico puede crearlas. Una respuesta por persona.')),
        FilledButton.icon(
            onPressed: () => SurveyEditorDialog.show(context, null, project: scope), icon: const Icon(Icons.add), label: const Text('Nueva encuesta')),
      ]),
      for (final b in builtins)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LabCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(b.title, style: _h(15))),
                    const SizedBox(width: 8),
                    LabTag('Integrada', color: OhtliColors.stormyTeal),
                  ]),
                  const SizedBox(height: 4),
                  Text(b.study.description, style: labCell()),
                ]),
              ),
              if (onOpen != null) FilledButton.tonal(onPressed: () => onOpen!(b.id), child: const Text('Abrir')),
            ]),
          ),
        ),
      StreamBuilder<List<LabSurvey>>(
        stream: scope == null ? _repo.watchSurveys() : _repo.watchProjectSurveys(scope.id),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final builtinIds = {for (final b in builtins) b.id};
          final list = [for (final s in snap.data!) if (!builtinIds.contains(s.id)) s];
          if (list.isEmpty) {
            return builtins.isNotEmpty ? const SizedBox.shrink() : LabCard(child: Text('Aún no hay encuestas.', style: labCell()));
          }
          return Column(children: [
            for (final s in list)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _SurveyCard(survey: s, onOpen: onOpen)),
          ]);
        },
      ),
    ]);
  }
}

class _SurveyCard extends StatelessWidget {
  final LabSurvey survey;

  /// Abre la página de la encuesta (consola por proyectos).
  final ValueChanged<String>? onOpen;
  const _SurveyCard({required this.survey, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = survey;
    final mine = s.ownerUid == _uid || currentLabRole == LabRole.admin;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.title, style: _h(15))),
          LabTag(s.open ? 'Abierta' : 'Cerrada', color: s.open ? OhtliColors.stormyTeal : OhtliColors.subtleText),
        ]),
        const SizedBox(height: 4),
        Text('${s.questions.length} preguntas${s.description.isEmpty ? '' : ' · ${s.description}'}', style: labCell()),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (mine) OutlinedButton(onPressed: () => SurveyEditorDialog.show(context, s), child: const Text('Editar')),
          if (mine)
            OutlinedButton(
              onPressed: () => runLabAction(context, () => _repo.saveSurvey(s.id, {'open': !s.open}), ok: s.open ? 'Encuesta cerrada.' : 'Encuesta abierta.'),
              child: Text(s.open ? 'Cerrar' : 'Abrir'),
            ),
          OutlinedButton(onPressed: () => _results(context), child: const Text('Resultados')),
          if (onOpen != null) FilledButton.tonal(onPressed: () => onOpen!(s.id), child: const Text('Detalle')),
        ]),
      ]),
    );
  }

  Future<void> _results(BuildContext context) async {
    final answers = await _repo.surveyAnswers(survey.id).catchError((_) => <Map<String, dynamic>>[]);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${survey.title} · ${answers.length} respuestas'),
        content: SizedBox(
          width: 560,
          child: ListView(shrinkWrap: true, children: [
            for (final q in survey.questions) ...[
              Text(q.text, style: labCell(bold: true)),
              Padding(padding: const EdgeInsets.only(bottom: 12, top: 4), child: Text(summarizeAnswers(q, answers), style: labCell())),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }
}

/// Resumen de las respuestas de una pregunta (promedio en Likert y número; conteo en opciones).
String summarizeAnswers(SurveyQuestion q, List<Map<String, dynamic>> answers) {
  final vals = [for (final a in answers) a[q.id]].where((v) => v != null).toList();
  if (vals.isEmpty) return 'Sin respuestas.';
  switch (q.type) {
    case SurveyQuestionType.likert5:
    case SurveyQuestionType.number:
      final nums = vals.whereType<num>().toList();
      if (nums.isEmpty) return 'Sin respuestas.';
      final mean = nums.reduce((a, b) => a + b) / nums.length;
      return 'Promedio ${mean.toStringAsFixed(2)} (n = ${nums.length})';
    case SurveyQuestionType.single:
    case SurveyQuestionType.multi:
      final counts = <String, int>{};
      for (final v in vals) {
        for (final o in (v is List ? v : [v])) {
          counts[o.toString()] = (counts[o.toString()] ?? 0) + 1;
        }
      }
      return [for (final o in q.options) '$o: ${counts[o] ?? 0}'].join(' · ');
    case SurveyQuestionType.text:
      return '${vals.length} comentarios';
  }
}

class SurveyEditorDialog extends StatefulWidget {
  final LabSurvey? survey;
  final LabProject? project;
  const SurveyEditorDialog({super.key, this.survey, this.project});

  static Future<void> show(BuildContext context, LabSurvey? s, {LabProject? project}) =>
      showDialog<void>(context: context, builder: (_) => SurveyEditorDialog(survey: s, project: project));

  @override
  State<SurveyEditorDialog> createState() => _SurveyEditorDialogState();
}

class _SurveyEditorDialogState extends State<SurveyEditorDialog> {
  late final _title = TextEditingController(text: widget.survey?.title);
  late final _desc = TextEditingController(text: widget.survey?.description);
  late final List<SurveyQuestion> _qs = [...?widget.survey?.questions];

  static String _typeLabel(SurveyQuestionType t) => switch (t) {
        SurveyQuestionType.likert5 => 'Escala 1–5',
        SurveyQuestionType.single => 'Opción única',
        SurveyQuestionType.multi => 'Opción múltiple',
        SurveyQuestionType.number => 'Número',
        SurveyQuestionType.text => 'Texto libre',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.survey == null ? 'Nueva encuesta' : 'Editar encuesta'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            labField(_title, 'Título'),
            labField(_desc, 'Instrucciones', maxLines: 2),
            for (var i = 0; i < _qs.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${i + 1}. ${_qs[i].text}'),
                subtitle: Text([_typeLabel(_qs[i].type), if (_qs[i].options.isNotEmpty) _qs[i].options.join(' / '), if (!_qs[i].required) 'opcional'].join(' · ')),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _qs.removeAt(i))),
              ),
            TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Agregar pregunta')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _title.text.trim().isEmpty && _qs.isEmpty
              ? null
              : () async {
                  Navigator.pop(context);
                  await runLabAction(
                    context,
                    () => _repo.saveSurvey(widget.survey?.id, {
                      'title': _title.text.trim(),
                      'description': _desc.text.trim(),
                      'questions': [for (final q in _qs) q.toMap()],
                      if (widget.survey == null) 'open': false,
                    }, project: widget.project),
                    ok: 'Encuesta guardada.',
                  );
                },
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _add() async {
    final text = TextEditingController(), options = TextEditingController();
    var type = SurveyQuestionType.likert5;
    var required = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Pregunta'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              labField(text, 'Pregunta'),
              DropdownButtonFormField<SurveyQuestionType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder(), isDense: true),
                items: [for (final t in SurveyQuestionType.values) DropdownMenuItem(value: t, child: Text(_typeLabel(t)))],
                onChanged: (v) => set(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              if (type == SurveyQuestionType.single || type == SurveyQuestionType.multi) labField(options, 'Opciones (separadas por coma)'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: required,
                onChanged: (v) => set(() => required = v ?? true),
                title: const Text('Obligatoria'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    setState(() => _qs.add(SurveyQuestion(
          id: 'q${_qs.length + 1}_${DateTime.now().millisecondsSinceEpoch % 100000}',
          type: type,
          text: text.text.trim(),
          options: [for (final o in options.text.split(',')) if (o.trim().isNotEmpty) o.trim()],
          required: required,
        )));
  }
}

// ═════════════════════════════ Funcionalidades ═════════════════════════════

class LabFeaturesPanel extends StatelessWidget {
  final LabRole role;

  /// Solo las funcionalidades de este proyecto.
  final String? projectId;

  /// Módulos del sistema con tablero propio (p. ej. el SMA en la plataforma): id, título y
  /// descripción; "Abrir" llama a [onOpen] con el id.
  final List<(String, String, String)> modules;
  final ValueChanged<String>? onOpen;
  const LabFeaturesPanel({super.key, required this.role, this.projectId, this.modules = const [], this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(
          child: LabSectionTitle('Funcionalidades',
              caption: 'En desarrollo → beta (solo testers inscritos a un estudio en curso) → oficial o retirada. '
                  'Volverla oficial o retirarla lo decide el admin tras publicar el estudio.'),
        ),
        FilledButton.icon(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('Nueva funcionalidad')),
      ]),
      for (final m in modules)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LabCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(m.$2, style: _h(15))),
                    const SizedBox(width: 8),
                    LabTag('Sistema', color: const Color(0xFF6C5CE7)),
                  ]),
                  const SizedBox(height: 4),
                  Text(m.$3, style: labCell()),
                ]),
              ),
              if (onOpen != null) FilledButton.tonal(onPressed: () => onOpen!(m.$1), child: const Text('Abrir')),
            ]),
          ),
        ),
      StreamBuilder<List<LabFeature>>(
        stream: _repo.watchFeatures(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          // El documento de configuración de un módulo del sistema (p. ej. 'sma') no es otra funcionalidad.
          final list = [
            for (final f in snap.data!)
              if ((projectId == null || f.projectId == projectId) && !modules.any((m) => m.$1 == f.key)) f,
          ];
          if (list.isEmpty) {
            return modules.isNotEmpty ? const SizedBox.shrink() : LabCard(child: Text('Aún no hay funcionalidades registradas.', style: labCell()));
          }
          return Column(children: [
            for (final f in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(f.name, style: _h(15))),
                      LabTag(f.stage.label, color: switch (f.stage) {
                        FeatureStage.oficial => const Color(0xFF2F6F4F),
                        FeatureStage.beta => OhtliColors.accent,
                        FeatureStage.retirada => OhtliColors.subtleText,
                        FeatureStage.desarrollo => const Color(0xFF6C5CE7),
                      }),
                    ]),
                    const SizedBox(height: 4),
                    Text('Clave en el código: ${f.key} · ${f.studyIds.length} estudio(s)', style: GoogleFonts.robotoMono(fontSize: 11.5, color: OhtliColors.subtleText)),
                    if (f.description.isNotEmpty) Text(f.description, style: labCell()),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(onPressed: () => _edit(context, f), child: const Text('Editar')),
                      if (onOpen != null) FilledButton.tonal(onPressed: () => onOpen!(f.key), child: const Text('Abrir')),
                      for (final st in FeatureStage.values)
                        if (st != f.stage && (role == LabRole.admin || st == FeatureStage.desarrollo || st == FeatureStage.beta) &&
                            (role == LabRole.admin || f.stage == FeatureStage.desarrollo || f.stage == FeatureStage.beta))
                          OutlinedButton(onPressed: () => _stage(context, f, st), child: Text('→ ${st.label}')),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    ]);
  }

  Future<void> _stage(BuildContext context, LabFeature f, FeatureStage st) async {
    final reason = TextEditingController();
    final decisive = st == FeatureStage.oficial || st == FeatureStage.retirada;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${f.name} → ${st.label}'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(switch (st) {
              FeatureStage.oficial => 'La verán todas las personas de Ohtli.',
              FeatureStage.retirada => 'Se apaga para todos. Lo que los testers hicieron con ella se conserva en solo lectura.',
              FeatureStage.beta => 'La verán los testers inscritos a un estudio en curso que la incluya.',
              FeatureStage.desarrollo => 'Solo la ve el laboratorio.',
            }),
            if (decisive) labField(reason, 'Motivo (queda en la bitácora)', maxLines: 3),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runLabAction(context, () => _repo.setFeatureStage(f.key, st, reason: reason.text.trim()), ok: 'Ahora: ${st.label}.');
  }

  Future<void> _edit(BuildContext context, LabFeature? f) async {
    final key = TextEditingController(text: f?.key), name = TextEditingController(text: f?.name);
    final desc = TextEditingController(text: f?.description), how = TextEditingController(text: f?.howToTry);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f == null ? 'Nueva funcionalidad' : 'Editar funcionalidad'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            labField(key, 'Clave en el código (FeatureGate)', enabled: f == null, hint: 'p. ej. viaje_por_voz'),
            labField(name, 'Nombre para los testers'),
            labField(desc, 'Qué hace', maxLines: 3),
            labField(how, 'Dónde encontrarla en la app'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    final k = key.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    if (ok != true || k.isEmpty || name.text.trim().isEmpty || !context.mounted) return;
    await runLabAction(
      context,
      () => _repo.saveFeature(k, {
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'howToTry': how.text.trim(),
        if (f == null) 'stage': FeatureStage.desarrollo.name,
        if (f == null) 'studyIds': const <String>[],
        if (f == null) 'projectId': projectId ?? kPlatformProjectId,
      }),
      ok: 'Funcionalidad guardada.',
    );
  }
}
