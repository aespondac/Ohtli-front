import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../lab_access.dart';
import '../lab_catalog.dart';
import '../lab_widgets.dart';
import '../research/lab_iam.dart';
import '../research/lab_models.dart';
import '../research/lab_research_repository.dart';
import '../research/research_widgets.dart';
import 'lab_location.dart';
import 'lab_settings_cards.dart';

final _repo = LabResearch.instance;
TextStyle _h(double size) => GoogleFonts.outfit(fontSize: size, fontWeight: FontWeight.w800, color: OhtliColors.onyx);

/// IAM del proyecto para mostrar y editar: el mapa `iam` y, mientras no se haya migrado, el dueño y
/// los miembros del modelo anterior.
Map<String, String> projectIamOf(LabProject p) => iamFromLegacy(current: p.iam, owner: p.ownerUid, editors: p.members);

/// Rol de la persona en el proyecto.
LabIamRole projectRoleOf(LabProject p, {required String? uid, required LabRole labRole}) => effectiveIamRole(
      uid: uid,
      labRole: labRole,
      projectIam: p.iam,
      legacyOwner: p.ownerUid,
      legacyMembers: p.members,
    );

/// Panel del proyecto (como la página de inicio de un proyecto en GCP): qué tiene y cómo va.
class LabProjectOverview extends StatelessWidget {
  final LabProject project;
  final LabIamRole role;
  final ValueChanged<LabArea> onGo;
  const LabProjectOverview({super.key, required this.project, required this.role, required this.onGo});

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LabCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: RevealedText(
                masked: p.name,
                confidential: p.confidential,
                load: () => SecretCache.project(p.id),
                field: 'name',
                style: _h(22),
              ),
            ),
            if (p.confidential) const ConfidentialTag(),
          ]),
          const SizedBox(height: 4),
          RevealedText(masked: p.description, confidential: p.confidential, load: () => SecretCache.project(p.id), field: 'description', style: labCell()),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text('ID: ${p.id}', style: GoogleFonts.robotoMono(fontSize: 11.5, color: OhtliColors.subtleText)),
            Text('Tu rol: ${role.label}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OhtliColors.subtleText)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      StreamBuilder<List<LabResearchStudy>>(
        stream: _repo.watchStudies(),
        builder: (context, ss) => StreamBuilder<List<LabLibraryExperiment>>(
          stream: _repo.watchProjectExperiments(p.id),
          builder: (context, es) => StreamBuilder<List<LabSurvey>>(
            stream: _repo.watchProjectSurveys(p.id),
            builder: (context, qs) => StreamBuilder<List<LabFeature>>(
              stream: _repo.watchFeatures(),
              builder: (context, fs) {
                final studies = [for (final s in ss.data ?? const <LabResearchStudy>[]) if (s.projectId == p.id && !s.legacyHolder) s];
                final builtinExp = builtinExperimentsOf(p.id);
                final builtinSur = builtinSurveysOf(p.id);
                final exps = builtinExp.length + [for (final e in es.data ?? const <LabLibraryExperiment>[]) if (!builtinExp.any((b) => b.id == e.id)) e].length;
                final surs = builtinSur.length + [for (final s in qs.data ?? const <LabSurvey>[]) if (!builtinSur.any((b) => b.id == s.id)) s].length;
                final feats = [for (final f in fs.data ?? const <LabFeature>[]) if (f.projectId == p.id) f].length + (p.id == kPlatformProjectId ? 1 : 0);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _Tile(icon: Icons.biotech_outlined, label: 'Estudios', value: '${studies.length}', onTap: () => onGo(LabArea.studies)),
                    _Tile(icon: Icons.science_outlined, label: 'Experimentos', value: '$exps', onTap: () => onGo(LabArea.experiments)),
                    _Tile(icon: Icons.ballot_outlined, label: 'Encuestas', value: '$surs', onTap: () => onGo(LabArea.surveys)),
                    _Tile(icon: Icons.toggle_on_outlined, label: 'Funcionalidades', value: '$feats', onTap: () => onGo(LabArea.functionalities)),
                  ]),
                  const SizedBox(height: 14),
                  LabCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Progreso de los estudios', style: _h(16)),
                      const SizedBox(height: 8),
                      if (studies.isEmpty) Text('Este proyecto aún no tiene estudios.', style: labCell()),
                      for (final st in StudyStatus.values)
                        if (studies.any((s) => s.status == st))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              SizedBox(width: 120, child: LabTag(st.label, color: studyStatusColor(st))),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(studies.where((s) => s.status == st).map((s) => s.title).join(' · '),
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: labCell()),
                              ),
                            ]),
                          ),
                    ]),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      LabAuditCard(projectId: p.id),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: Material(
          color: OhtliColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: OhtliColors.cardBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: OhtliColors.stormyTeal),
                const SizedBox(height: 8),
                Text(value, style: _h(24)),
                Text(label, style: labCell()),
              ]),
            ),
          ),
        ),
      );
}

/// Secciones de la configuración del proyecto.
const kProjectSettingsSections = [('general', 'General'), ('iam', 'Accesos (IAM)'), ('audit', 'Bitácora')];

/// Configuración del proyecto: general, accesos y bitácora.
class LabProjectSettings extends StatelessWidget {
  final LabProject project;
  final LabIamRole role;
  final LabRole labRole;

  /// Sub-sección abierta (general, iam, audit).
  final String section;
  final ValueChanged<String> onSection;
  const LabProjectSettings({
    super.key,
    required this.project,
    required this.role,
    required this.labRole,
    required this.section,
    required this.onSection,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final current = kProjectSettingsSections.any((s) => s.$1 == section) ? section : 'general';
    final body = switch (current) {
      'iam' => LabIamCard(
          kind: LabResourceKind.project,
          id: project.id,
          projectId: project.id,
          own: projectIamOf(project),
          canManage: role.canManageIam,
        ),
      'audit' => LabAuditCard(projectId: project.id),
      _ => _General(project: project, labRole: labRole),
    };
    final nav = isMobile
        ? DropdownButtonFormField<String>(
            initialValue: current,
            decoration: const InputDecoration(labelText: 'Sección', border: OutlineInputBorder(), isDense: true),
            items: [for (final s in kProjectSettingsSections) DropdownMenuItem(value: s.$1, child: Text(s.$2))],
            onChanged: (v) => v == null ? null : onSection(v),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final s in kProjectSettingsSections)
              ListTile(
                dense: true,
                selected: s.$1 == current,
                selectedTileColor: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: Text(s.$2, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: s.$1 == current ? FontWeight.w700 : FontWeight.w500)),
                onTap: () => onSection(s.$1),
              ),
          ]);
    if (isMobile) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [nav, const SizedBox(height: 14), body]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 200, child: nav),
      const SizedBox(width: 20),
      Expanded(child: body),
    ]);
  }
}

class _General extends StatelessWidget {
  final LabProject project;
  final LabRole labRole;
  const _General({required this.project, required this.labRole});

  @override
  Widget build(BuildContext context) {
    final p = project;
    return LabCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('General', style: _h(16)),
        const SizedBox(height: 8),
        Text('Nombre', style: labCell(bold: true)),
        RevealedText(masked: p.name, confidential: p.confidential, load: () => SecretCache.project(p.id), field: 'name', style: labCell()),
        const SizedBox(height: 8),
        Text('Descripción', style: labCell(bold: true)),
        RevealedText(masked: p.description, confidential: p.confidential, load: () => SecretCache.project(p.id), field: 'description', style: labCell()),
        const SizedBox(height: 8),
        Text('ID', style: labCell(bold: true)),
        SelectableText(p.id, style: GoogleFonts.robotoMono(fontSize: 12.5, color: OhtliColors.onyx)),
        const SizedBox(height: 8),
        Text('Confidencialidad', style: labCell(bold: true)),
        Text(
          p.confidential
              ? 'Confidencial: se muestra como «${p.name}». El nombre real solo lo ven quienes tienen acceso al proyecto.'
              : (p.declassifiedAt != null ? 'Público (desclasificado el ${fmtDate(p.declassifiedAt)}).' : 'Público.'),
          style: labCell(),
        ),
        if (p.confidential && labRole == LabRole.admin) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Desclasificar'),
            onPressed: () async {
              final ok = await confirmLab(context, 'Desclasificar ${p.name}',
                  'El nombre real y lo que cuelga del proyecto pasan a ser visibles para todo el laboratorio. No se puede deshacer.');
              if (!ok || !context.mounted) return;
              await runLabAction(context, () async {
                final n = await _repo.declassify(p.id);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Desclasificado: $n elemento(s).')));
              });
            },
          ),
        ],
      ]),
    );
  }
}
