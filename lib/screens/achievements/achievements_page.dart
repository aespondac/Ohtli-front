import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../labs/labs_top_bar.dart';
import '../../labs/research/lab_models.dart';
import '../../labs/research/lab_research_repository.dart';
import '../../labs/research/member_check_dialog.dart';
import '../../services/ohtli_features.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_ui.dart';

/// Logros: los títulos de la persona y, si es tester de Ohtli Labs, las funciones en prueba de
/// los estudios a los que se inscribió y lo que esos estudios le piden (validar resultados).
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final pad = OhtliUi.pagePadding(width);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 28, pad, 64),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ValueListenableBuilder<FeatureAccess>(
            valueListenable: OhtliFeatures.instance.access,
            builder: (context, access, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Logros', style: OhtliUi.title(size: width < 700 ? 28 : 38)),
              const SizedBox(height: 6),
              Text('Lo que has ganado viajando y aportando a Ohtli.', style: OhtliUi.body()),
              const SizedBox(height: 28),
              const _TitlesSection(),
              const SizedBox(height: 36),
              if (access.isTester) ...[
                _BetaFeaturesSection(access: access),
                const SizedBox(height: 36),
                _MyStudiesSection(access: access),
              ] else
                const _JoinLabsCard(),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────── Títulos ─────────────

class _TitlesSection extends StatelessWidget {
  const _TitlesSection();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        final possessed = {for (final t in (userSnap.data?.data()?['possessedTitles'] as List?) ?? const ['viajero']) t.toString()};
        final active = userSnap.data?.data()?['activeTitleId'] ?? 'viajero';
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('titles').snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final mine = docs.where((d) => possessed.contains(d.id)).toList();
            final pending = docs.where((d) => !possessed.contains(d.id) && d.data()['hidden'] != true).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OhtliSectionHeader(
                eyebrow: 'TÍTULOS',
                title: 'Tus títulos',
                subtitle: '${mine.length} de ${docs.isEmpty ? possessed.length : docs.length}. Elige cuál mostrar desde tu perfil.',
                icon: Icons.workspace_premium_outlined,
              ),
              const SizedBox(height: 14),
              if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else
                _grid(context, [
                  for (final d in mine) _TitleTile(data: d.data(), owned: true, active: d.id == active),
                  for (final d in pending) _TitleTile(data: d.data(), owned: false, active: false),
                ]),
            ]);
          },
        );
      },
    );
  }
}

Widget _grid(BuildContext context, List<Widget> children) => LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 560 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
    });

class _TitleTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool owned;
  final bool active;
  const _TitleTile({required this.data, required this.owned, required this.active});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: owned ? 1 : 0.55,
      child: OhtliSurface(
        selected: active,
        padding: const EdgeInsets.all(18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(owned ? Icons.stars_rounded : Icons.lock_outline_rounded, color: owned ? OhtliColors.accent : OhtliColors.subtleText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text((data['name'] ?? '').toString(),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: OhtliColors.onyx)),
                ),
                if (active) ...[const SizedBox(width: 8), _Pill(label: 'En tu perfil', color: OhtliColors.accent)],
              ]),
              const SizedBox(height: 4),
              Text(owned ? (data['description'] ?? '').toString() : 'Por ganar · ${(data['description'] ?? '').toString()}',
                  style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: OhtliColors.subtleText)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ───────────── Funciones en prueba ─────────────

class _BetaFeaturesSection extends StatelessWidget {
  final FeatureAccess access;
  const _BetaFeaturesSection({required this.access});

  @override
  Widget build(BuildContext context) {
    final list = access.myBetaFeatures;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const OhtliSectionHeader(
        eyebrow: 'OHTLI LABS',
        title: 'Funciones en prueba',
        subtitle: 'Solo las ven los testers de los estudios que las evalúan. Pueden cambiar o retirarse.',
        icon: Icons.science_outlined,
      ),
      const SizedBox(height: 14),
      if (list.isEmpty)
        const OhtliEmptyState(
          icon: Icons.science_outlined,
          title: 'Todavía no tienes funciones en prueba',
          message: 'Inscríbete a un estudio en Ohtli Labs para probar funciones antes que nadie.',
        )
      else
        _grid(context, [
          for (final f in list)
            _FeatureTile(
              feature: f,
              on: access.isOn(f.key),
              studies: [for (final id in f.studyIds) access.enrolledStudies[id]].whereType<LabResearchStudy>().toList(),
            ),
        ]),
    ]);
  }
}

class _FeatureTile extends StatelessWidget {
  final LabFeature feature;
  final bool on;
  final List<LabResearchStudy> studies;
  const _FeatureTile({required this.feature, required this.on, required this.studies});

  @override
  Widget build(BuildContext context) {
    final f = feature;
    final (label, color) = switch (f.stage) {
      FeatureStage.oficial => ('Ya es oficial', OhtliColors.stormyTeal),
      FeatureStage.retirada => ('Retirada', OhtliColors.subtleText),
      _ => (on ? 'Activa para ti' : 'En pausa', on ? OhtliColors.accent : OhtliColors.subtleText),
    };
    return OhtliSurface(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(f.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: OhtliColors.onyx)),
          ),
          _Pill(label: label, color: color),
        ]),
        const SizedBox(height: 6),
        if (f.description.isNotEmpty)
          Text(f.description, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: OhtliColors.subtleText)),
        if (f.stage == FeatureStage.retirada)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Se retiró tras el estudio. Lo que hiciste con ella se conserva.',
                style: GoogleFonts.inter(fontSize: 12, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
          ),
        if (on && (f.howToTry ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Dónde encontrarla: ${f.howToTry}', style: GoogleFonts.inter(fontSize: 12, color: OhtliColors.onyx)),
          ),
        if (studies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Estudio: ${studies.map((s) => s.title).join(', ')}',
                style: GoogleFonts.inter(fontSize: 11.5, color: OhtliColors.subtleText)),
          ),
      ]),
    );
  }
}

// ───────────── Mis estudios ─────────────

class _MyStudiesSection extends StatelessWidget {
  final FeatureAccess access;
  const _MyStudiesSection({required this.access});

  @override
  Widget build(BuildContext context) {
    final studies = access.enrolledStudies.values.toList()..sort((a, b) => a.title.compareTo(b.title));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OhtliSectionHeader(
        eyebrow: 'PARTICIPACIÓN',
        title: 'Tus estudios',
        subtitle: 'Cuando un estudio termina te pedimos confirmar que sus resultados reflejan lo que aportaste.',
        icon: Icons.how_to_reg_outlined,
        trailing: OhtliSecondaryButton(label: 'Ir a Labs', icon: Icons.open_in_new_rounded, onPressed: LabsTopBar.openLab),
      ),
      const SizedBox(height: 14),
      if (studies.isEmpty)
        OhtliEmptyState(
          icon: Icons.how_to_reg_outlined,
          title: 'No estás inscrito a ningún estudio',
          message: 'Los estudios abiertos están en Ohtli Labs → Participa.',
          action: OhtliPrimaryButton(label: 'Ver estudios abiertos', compact: true, onPressed: LabsTopBar.openLab),
        )
      else
        Column(children: [for (final s in studies) Padding(padding: const EdgeInsets.only(bottom: 12), child: _StudyTile(study: s))]),
    ]);
  }
}

class _StudyTile extends StatelessWidget {
  final LabResearchStudy study;
  const _StudyTile({required this.study});

  @override
  Widget build(BuildContext context) {
    final s = study;
    final validating = s.paperStage == PaperStage.validacionParticipantes && s.currentPaperId != null;
    return OhtliSurface(
      padding: const EdgeInsets.all(18),
      accent: validating ? OhtliColors.accent : null,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5, color: OhtliColors.onyx)),
            const SizedBox(height: 4),
            Text(
              [s.status.label, if (s.paperStage != null) 'Paper: ${s.paperStage!.label}'].join(' · '),
              style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText),
            ),
          ]),
        ),
        if (validating)
          OhtliPrimaryButton(
            label: 'Validar resultados',
            compact: true,
            onPressed: () async {
              final paper = await LabResearch.instance.paper(s.currentPaperId!);
              if (paper != null && context.mounted) await MemberCheckDialog.show(context, paper);
            },
          ),
      ]),
    );
  }
}

class _JoinLabsCard extends StatelessWidget {
  const _JoinLabsCard();

  @override
  Widget build(BuildContext context) => OhtliSurface(
        accent: OhtliColors.stormyTeal,
        child: Row(children: [
          const Icon(Icons.science_outlined, color: OhtliColors.stormyTeal, size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Prueba funciones antes que nadie',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: OhtliColors.onyx)),
              const SizedBox(height: 4),
              Text('Únete a Ohtli Labs como tester: participas en estudios, usas funciones en prueba y validas sus resultados.',
                  style: OhtliUi.body(size: 13.5)),
            ]),
          ),
          const SizedBox(width: 12),
          OhtliPrimaryButton(label: 'Unirme a Labs', compact: true, onPressed: () => LabsTopBar.go(LabsSection.participate)),
        ]),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}
