import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../lab_access.dart';
import '../lab_catalog.dart';
import '../lab_console_page.dart';
import '../lab_functionalities.dart';
import '../lab_sma_page.dart';
import '../lab_widgets.dart';
import '../research/lab_iam.dart';
import '../research/lab_models.dart';
import '../research/lab_research_repository.dart';
import '../research/research_console.dart';
import '../research/research_widgets.dart';
import 'lab_location.dart';
import 'lab_project_views.dart';
import 'lab_resource_page.dart';
import 'lab_settings_cards.dart';

/// Páginas de cada recurso de un proyecto (estudio, experimento, encuesta, funcionalidad): su
/// contenido y, en Configuración, accesos (IAM), estado, liberación, revisiones y bitácora.

final _repo = LabResearch.instance;

/// Lo que comparten las páginas de un proyecto: el proyecto, quién mira y cómo navegar.
class LabPageCtx {
  final LabProject project;
  final LabRole labRole;
  final String? uid;
  final String? tab;
  final ValueChanged<String> go;
  const LabPageCtx({required this.project, required this.labRole, required this.uid, required this.tab, required this.go});

  String key(LabArea a, [String? res, String? tab]) => LabLocation.project(project.id, a, resourceId: res, tab: tab).toKey();

  LabIamRole get projectRole => projectRoleOf(project, uid: uid, labRole: labRole);

  /// Rol sobre un recurso: lo que da el proyecto o lo que da el recurso, lo que sea mayor.
  LabIamRole roleFor({Map<String, String> iam = const {}, String? owner}) {
    final own = effectiveIamRole(uid: uid, labRole: labRole, resourceIam: iam, legacyOwner: owner);
    return own.rank > projectRole.rank ? own : projectRole;
  }

  List<(String, VoidCallback?)> crumbs(LabArea area, String title) => [
        (project.name, () => go(key(LabArea.overview))),
        (area.label, () => go(key(area))),
        (title, null),
      ];

  void Function(String) tabber(LabArea area, String res) => (t) => go(key(area, res, t));
  void Function(String) sectioner(LabArea area, String res) => (s) => go(key(area, res, 'config.$s'));
}

const _configTab = ('config', 'Configuración', Icons.settings_outlined);

LabTabSpec _config(Widget Function() build) => LabTabSpec(_configTab.$1, _configTab.$2, _configTab.$3, build);

Widget _notFound(String what) => LabCard(child: Text('No encontramos $what en este proyecto.', style: labCell()));

// ───────────────────────────── Estudio ─────────────────────────────

class LabStudyPage extends StatelessWidget {
  final LabPageCtx ctx;
  final String studyId;
  const LabStudyPage({super.key, required this.ctx, required this.studyId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LabResearchStudy?>(
      stream: _repo.watchStudy(studyId),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final s = snap.data;
        if (s == null || s.projectId != ctx.project.id) return _notFound('este estudio');
        final role = ctx.roleFor(iam: s.iam, owner: s.ownerUid);
        void back() => ctx.go(ctx.key(LabArea.studies));
        return LabResourcePage(
          breadcrumbs: ctx.crumbs(LabArea.studies, s.title),
          title: s.title,
          subtitle: s.description,
          icon: Icons.biotech_outlined,
          role: role,
          tags: [s.status.label, if (s.confidential) 'Confidencial'],
          tab: ctx.tab,
          onTab: ctx.tabber(LabArea.studies, s.id),
          tabs: [
            LabTabSpec('summary', 'Resumen', Icons.description_outlined,
                () => LabStudyEditor(studyId: s.id, role: ctx.labRole, onBack: back, part: LabStudyPart.summary, editable: role.canEdit)),
            _config(() => LabSettingsLayout(
                  current: labSectionOf(ctx.tab),
                  onSection: ctx.sectioner(LabArea.studies, s.id),
                  sections: [
                    (
                      'iam',
                      'Accesos (IAM)',
                      () => LabIamCard(
                            kind: LabResourceKind.study,
                            id: s.id,
                            projectId: ctx.project.id,
                            inherited: projectIamOf(ctx.project),
                            own: iamFromLegacy(current: s.iam, owner: s.ownerUid),
                            canManage: role.canManageIam,
                          )
                    ),
                    (
                      'state',
                      'Estado y progreso',
                      () => LabStudyEditor(studyId: s.id, role: ctx.labRole, onBack: back, part: LabStudyPart.state, editable: role.canEdit)
                    ),
                    ('release', 'Liberación y revisiones', () => LabStudyEditor(studyId: s.id, role: ctx.labRole, onBack: back, part: LabStudyPart.paper)),
                    ('audit', 'Bitácora', () => LabAuditCard(target: 'study:${s.id}')),
                  ],
                )),
          ],
        );
      },
    );
  }
}

// ───────────────────────────── Experimento ─────────────────────────────

class LabExperimentPage extends StatelessWidget {
  final LabPageCtx ctx;
  final String experimentId;

  /// Pantalla propia de un experimento integrado de la plataforma (ocupa todo el alto).
  final Widget Function()? ownPage;
  const LabExperimentPage({super.key, required this.ctx, required this.experimentId, this.ownPage});

  @override
  Widget build(BuildContext context) {
    final b = builtinExperimentById(experimentId);
    final runner = b?.ttRunner;
    if (b != null && b.projectId != ctx.project.id) return _notFound('este experimento');
    // Pruebas del TT: su configuración vive en su documento de lab_studies (el de siempre).
    if (runner != null) {
      return StreamBuilder<LabResearchStudy?>(
        stream: _repo.watchStudy(runner.id),
        builder: (context, snap) {
          final st = snap.data;
          final role = ctx.roleFor(iam: st?.iam ?? const {}, owner: st?.ownerUid);
          return LabResourcePage(
            breadcrumbs: ctx.crumbs(LabArea.experiments, b!.title),
            title: b.title,
            subtitle: b.description,
            icon: Icons.science_outlined,
            role: role,
            tags: ['Prueba del TT', runner.criterion],
            tab: ctx.tab,
            onTab: ctx.tabber(LabArea.experiments, b.id),
            tabs: [
              LabTabSpec('run', 'Ejecutar y resultados', Icons.play_circle_outline_rounded, () => LabStudyPanel(study: runner), keepAlive: true),
              _config(() => LabSettingsLayout(
                    current: labSectionOf(ctx.tab),
                    onSection: ctx.sectioner(LabArea.experiments, b.id),
                    sections: [
                      (
                        'iam',
                        'Accesos (IAM)',
                        () => LabIamCard(
                              kind: LabResourceKind.study,
                              id: runner.id,
                              projectId: ctx.project.id,
                              inherited: projectIamOf(ctx.project),
                              own: iamFromLegacy(current: st?.iam ?? const {}, owner: st?.ownerUid),
                              canManage: role.canManageIam,
                            )
                      ),
                      (
                        'state',
                        'Estado',
                        () => LabFactsCard(title: 'Estado', facts: [
                              ('Capítulo del TT', runner.chapter),
                              ('Criterio', runner.criterion),
                              ('Corridas', 'Se guardan con la clave «${runner.id}»; su visibilidad se elige en cada corrida (Ejecutar y resultados).'),
                            ])
                      ),
                      ('audit', 'Bitácora', () => LabAuditCard(targets: ['study:${runner.id}', 'experiment:${b.id}'])),
                    ],
                  )),
            ],
          );
        },
      );
    }
    return StreamBuilder<LabLibraryExperiment?>(
      stream: _repo.watchExperimentDoc(experimentId),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final doc = snap.data;
        if (b == null && (doc == null || doc.projectId != ctx.project.id)) return _notFound('este experimento');
        final role = ctx.roleFor(iam: doc?.iam ?? const {}, owner: doc?.ownerUid);
        final title = b?.title ?? doc!.title;
        final description = b?.description ?? doc!.description;
        // Documento que se crea la primera vez que se configura un integrado.
        final seed = b == null
            ? const <String, dynamic>{}
            : {'title': b.title, 'description': b.description, 'builtin': true, 'projectId': ctx.project.id, 'confidential': false};
        final configTab = _config(() => LabSettingsLayout(
              current: labSectionOf(ctx.tab),
              onSection: ctx.sectioner(LabArea.experiments, experimentId),
              sections: [
                (
                  'iam',
                  'Accesos (IAM)',
                  () => LabIamCard(
                        kind: LabResourceKind.experiment,
                        id: experimentId,
                        projectId: ctx.project.id,
                        inherited: projectIamOf(ctx.project),
                        own: iamFromLegacy(current: doc?.iam ?? const {}, owner: doc?.ownerUid),
                        canManage: role.canManageIam,
                        seed: seed,
                      )
                ),
                (
                  'release',
                  'Liberación',
                  () => LabSharedCard(
                        kind: LabResourceKind.experiment,
                        id: experimentId,
                        projectId: ctx.project.id,
                        shared: doc?.shared ?? false,
                        confidential: doc?.confidential ?? ctx.project.confidential,
                        canManage: role.canManageIam,
                        seed: seed,
                      )
                ),
                ('audit', 'Bitácora', () => LabAuditCard(target: 'experiment:$experimentId')),
              ],
            ));
        if (b?.page != null && ownPage != null) {
          return LabResourcePage(
            fill: true,
            breadcrumbs: ctx.crumbs(LabArea.experiments, title),
            title: title,
            subtitle: description,
            icon: b!.page!.icon,
            role: role,
            tags: [b.page!.status, b.page!.category],
            tab: ctx.tab,
            onTab: ctx.tabber(LabArea.experiments, experimentId),
            tabs: [LabTabSpec('run', 'Ejecutar', Icons.play_circle_outline_rounded, ownPage!, scroll: false, keepAlive: true), configTab],
          );
        }
        return LabResourcePage(
          breadcrumbs: ctx.crumbs(LabArea.experiments, title),
          title: title,
          subtitle: description,
          icon: Icons.science_outlined,
          role: role,
          tags: [if (doc?.shared == true) 'Compartido', if (doc?.confidential == true) 'Confidencial'],
          tab: ctx.tab,
          onTab: ctx.tabber(LabArea.experiments, experimentId),
          tabs: [
            LabTabSpec('summary', 'Protocolo', Icons.description_outlined, () => LabFactsCard(title: 'Protocolo', facts: [
                  ('Qué evalúa', description),
                  ('Procedimiento', doc?.procedure.isNotEmpty == true ? doc!.procedure : 'Sin describir.'),
                  ('Métricas', doc?.metricNames.isNotEmpty == true ? doc!.metricNames.join(' · ') : 'Sin definir.'),
                ])),
            configTab,
          ],
        );
      },
    );
  }
}

// ───────────────────────────── Encuesta ─────────────────────────────

class LabSurveyPage extends StatelessWidget {
  final LabPageCtx ctx;
  final String surveyId;
  const LabSurveyPage({super.key, required this.ctx, required this.surveyId});

  @override
  Widget build(BuildContext context) {
    final b = builtinSurveyById(surveyId);
    if (b != null) {
      if (b.projectId != ctx.project.id) return _notFound('esta encuesta');
      // Relevancia y SUS: abrirlas a testers y sus resultados viven en su documento de lab_studies
      // (las reglas de las respuestas lo leen).
      return StreamBuilder<LabResearchStudy?>(
        stream: _repo.watchStudy(b.id),
        builder: (context, snap) {
          final st = snap.data;
          final role = ctx.roleFor(iam: st?.iam ?? const {}, owner: st?.ownerUid);
          return LabResourcePage(
            breadcrumbs: ctx.crumbs(LabArea.surveys, b.title),
            title: b.title,
            subtitle: b.study.description,
            icon: Icons.ballot_outlined,
            role: role,
            tags: ['Integrada', b.study.criterion],
            tab: ctx.tab,
            onTab: ctx.tabber(LabArea.surveys, b.id),
            tabs: [
              LabTabSpec('results', 'Resultados y apertura', Icons.insights_outlined, () => LabStudyPanel(study: b.study), keepAlive: true),
              _config(() => LabSettingsLayout(
                    current: labSectionOf(ctx.tab),
                    onSection: ctx.sectioner(LabArea.surveys, b.id),
                    sections: [
                      (
                        'iam',
                        'Accesos (IAM)',
                        () => LabIamCard(
                              kind: LabResourceKind.study,
                              id: b.id,
                              projectId: ctx.project.id,
                              inherited: projectIamOf(ctx.project),
                              own: iamFromLegacy(current: st?.iam ?? const {}, owner: st?.ownerUid),
                              canManage: role.canManageIam,
                            )
                      ),
                      ('audit', 'Bitácora', () => LabAuditCard(targets: ['study:${b.id}', 'survey:${b.id}'])),
                    ],
                  )),
            ],
          );
        },
      );
    }
    return StreamBuilder<LabSurvey?>(
      stream: _repo.watchSurveyDoc(surveyId),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final q = snap.data;
        if (q == null || q.projectId != ctx.project.id) return _notFound('esta encuesta');
        final role = ctx.roleFor(iam: q.iam, owner: q.ownerUid);
        return LabResourcePage(
          breadcrumbs: ctx.crumbs(LabArea.surveys, q.title),
          title: q.title,
          subtitle: q.description,
          icon: Icons.ballot_outlined,
          role: role,
          tags: [q.open ? 'Abierta' : 'Cerrada', if (q.shared) 'Compartida', if (q.confidential) 'Confidencial'],
          tab: ctx.tab,
          onTab: ctx.tabber(LabArea.surveys, q.id),
          tabs: [
            LabTabSpec('preview', 'Vista previa', Icons.visibility_outlined, () => LabCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${q.questions.length} pregunta(s)', style: labCell(bold: true)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < q.questions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${i + 1}. ${q.questions[i].text}${q.questions[i].required ? '' : ' (opcional)'}', style: labCell()),
                      ),
                    if (role.canEdit) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => SurveyEditorDialog.show(context, q, project: ctx.project),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar preguntas'),
                      ),
                    ],
                  ]),
                )),
            _config(() => LabSettingsLayout(
                  current: labSectionOf(ctx.tab),
                  onSection: ctx.sectioner(LabArea.surveys, q.id),
                  sections: [
                    (
                      'iam',
                      'Accesos (IAM)',
                      () => LabIamCard(
                            kind: LabResourceKind.survey,
                            id: q.id,
                            projectId: ctx.project.id,
                            inherited: projectIamOf(ctx.project),
                            own: iamFromLegacy(current: q.iam, owner: q.ownerUid),
                            canManage: role.canManageIam,
                          )
                    ),
                    (
                      'state',
                      'Estado',
                      () => LabFactsCard(title: 'Estado', facts: [
                            ('Respuestas', q.open ? 'Abierta: los participantes pueden responder.' : 'Cerrada: no se aceptan respuestas.'),
                          ], actions: [
                            if (role.canEdit)
                              FilledButton.tonal(
                                onPressed: () => runLabAction(context, () => _repo.saveSurvey(q.id, {'open': !q.open}),
                                    ok: q.open ? 'Encuesta cerrada.' : 'Encuesta abierta.'),
                                child: Text(q.open ? 'Cerrar' : 'Abrir'),
                              ),
                          ])
                    ),
                    (
                      'release',
                      'Liberación',
                      () => LabSharedCard(
                            kind: LabResourceKind.survey,
                            id: q.id,
                            projectId: ctx.project.id,
                            shared: q.shared,
                            confidential: q.confidential,
                            canManage: role.canManageIam,
                          )
                    ),
                    ('audit', 'Bitácora', () => LabAuditCard(target: 'survey:${q.id}')),
                  ],
                )),
          ],
        );
      },
    );
  }
}

// ───────────────────────────── Funcionalidad ─────────────────────────────

class LabFunctionalityPage extends StatelessWidget {
  final LabPageCtx ctx;
  final String functionalityId;
  const LabFunctionalityPage({super.key, required this.ctx, required this.functionalityId});

  @override
  Widget build(BuildContext context) {
    final module = moduleById(functionalityId);
    // 'sma' es el enlace anterior al sistema completo (antes de dividirlo en funcionalidades).
    final legacySma = functionalityId == 'sma' && ctx.project.id == kPlatformProjectId;
    final moduleTitle = (module != null && module.projectId == ctx.project.id) ? module.title : (legacySma ? 'Sistema multiagente' : null);
    return StreamBuilder<LabFeature?>(
      stream: _repo.watchFeature(functionalityId),
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final f = snap.data;
        if (moduleTitle == null && (f == null || f.projectId != ctx.project.id)) return _notFound('esta funcionalidad');
        final role = ctx.roleFor(iam: f?.iam ?? const {});
        final title = moduleTitle ?? f!.name;
        final seed = moduleTitle == null
            ? const <String, dynamic>{}
            : {'name': moduleTitle, 'projectId': ctx.project.id, 'stage': FeatureStage.desarrollo.name, 'studyIds': const <String>[], 'module': true};
        return LabResourcePage(
          breadcrumbs: ctx.crumbs(LabArea.functionalities, title),
          title: title,
          subtitle: module?.description ?? f?.description,
          icon: moduleTitle != null ? Icons.hub_outlined : Icons.toggle_on_outlined,
          role: role,
          tags: [if (moduleTitle != null) 'Sistema' else f!.stage.label],
          tab: ctx.tab,
          onTab: ctx.tabber(LabArea.functionalities, functionalityId),
          tabs: [
            LabTabSpec(
              'panel',
              'Panel',
              Icons.dashboard_outlined,
              () => moduleTitle != null
                  ? LabSmaPanel(only: module?.sma)
                  : LabFactsCard(title: 'Funcionalidad', facts: [
                      ('Clave en el código', f!.key),
                      ('Qué hace', f.description.isEmpty ? 'Sin describir.' : f.description),
                      ('Dónde probarla', (f.howToTry ?? '').isEmpty ? 'Sin indicar.' : f.howToTry!),
                    ]),
            ),
            _config(() => LabSettingsLayout(
                  current: labSectionOf(ctx.tab),
                  onSection: ctx.sectioner(LabArea.functionalities, functionalityId),
                  sections: [
                    (
                      'iam',
                      'Accesos (IAM)',
                      () => LabIamCard(
                            kind: LabResourceKind.functionality,
                            id: functionalityId,
                            projectId: ctx.project.id,
                            inherited: projectIamOf(ctx.project),
                            own: Map.of(f?.iam ?? const {}),
                            canManage: role.canManageIam,
                            seed: seed,
                          )
                    ),
                    if (f != null && moduleTitle == null) ...[
                      ('state', 'Estado', () => _FeatureStageCard(feature: f, labRole: ctx.labRole, canEdit: role.canEdit)),
                      (
                        'release',
                        'Liberación',
                        () => LabFactsCard(title: 'Liberación', facts: [
                              ('Etapa', f.stage.label),
                              ('Testers beta', '${f.studyIds.length} estudio(s) la ofrecen a sus inscritos. Se ligan desde los componentes de cada estudio.'),
                            ])
                      ),
                    ],
                    ('audit', 'Bitácora', () => LabAuditCard(targets: ['feature:$functionalityId', 'functionality:$functionalityId'])),
                  ],
                )),
          ],
        );
      },
    );
  }
}

class _FeatureStageCard extends StatelessWidget {
  final LabFeature feature;
  final LabRole labRole;
  final bool canEdit;
  const _FeatureStageCard({required this.feature, required this.labRole, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final f = feature;
    final admin = labRole == LabRole.admin;
    // Volverla oficial o retirarla lo decide el admin; el resto solo entre desarrollo y beta.
    final options = [
      for (final st in FeatureStage.values)
        if (st != f.stage &&
            (admin || st == FeatureStage.desarrollo || st == FeatureStage.beta) &&
            (admin || f.stage == FeatureStage.desarrollo || f.stage == FeatureStage.beta))
          st,
    ];
    return LabFactsCard(
      title: 'Estado',
      facts: [('Etapa actual', f.stage.label)],
      actions: [
        if (canEdit)
          for (final st in options)
            OutlinedButton(
              onPressed: () async {
                final reason = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Pasar a «${st.label}»'),
                    content: labField(reason, 'Motivo (queda en la bitácora)', maxLines: 2),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cambiar')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await runLabAction(context, () => _repo.setFeatureStage(f.key, st, reason: reason.text.trim()), ok: 'Ahora: ${st.label}.');
              },
              child: Text('→ ${st.label}'),
            ),
        if (!canEdit) Text('Solo editores y propietarios cambian la etapa.', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.subtleText)),
      ],
    );
  }
}
