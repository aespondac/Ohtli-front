import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ohtli_features.dart';
import '../../theme/colors.dart';
import '../../widgets/ohtli_ui.dart';

/// Logros: los títulos de viajero de la persona. Es una función en prueba (`logros` en
/// lab_features): solo la ven los testers de su estudio hasta que el admin la vuelva oficial.
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
            builder: (context, access, _) => !access.isOn(kFeatureLogros)
                ? const OhtliEmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'Logros todavía está en prueba',
                    message: 'Por ahora solo la ven los testers del estudio que la evalúa.',
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Logros', style: OhtliUi.title(size: width < 700 ? 28 : 38)),
                    const SizedBox(height: 6),
                    Text('Los títulos que has ganado viajando y aportando a Ohtli.', style: OhtliUi.body()),
                    const SizedBox(height: 28),
                    const _TitlesSection(),
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
