import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/colors.dart';
import '../research/lab_iam.dart';

/// Esqueleto de la página de un recurso (estudio, experimento, encuesta, funcionalidad), como las
/// páginas de detalle de la consola de GCP: ruta de navegación, título con tu rol y pestañas. La
/// última pestaña suele ser Configuración ([LabSettingsLayout]).
///
/// La pestaña viaja en la ubicación (`p:<proyecto>/<área>/<recurso>/<pestaña>`): `config.iam` abre
/// Configuración en la sección de accesos.
class LabTabSpec {
  final String id;
  final String label;
  final IconData icon;
  final Widget Function() build;

  /// En una página que llena la vista ([LabResourcePage.fill]), si el contenido va en un scroll
  /// (Configuración) o ocupa todo el alto (la pantalla propia de un experimento).
  final bool scroll;

  /// Sigue viva (oculta) al cambiar de pestaña: una corrida en curso no se corta por ir a
  /// Configuración.
  final bool keepAlive;
  const LabTabSpec(this.id, this.label, this.icon, this.build, {this.scroll = true, this.keepAlive = false});
}

/// Pestaña de una clave de ubicación: `config.iam` → `config`; sin pestaña, la primera.
String labTabOf(String? tab, List<LabTabSpec> tabs) {
  final base = (tab ?? '').split('.').first;
  return tabs.any((t) => t.id == base) ? base : tabs.first.id;
}

/// Sección de Configuración de una clave de ubicación: `config.iam` → `iam`.
String? labSectionOf(String? tab) {
  final parts = (tab ?? '').split('.');
  return parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
}

class LabResourcePage extends StatelessWidget {
  /// Ruta: pares (texto, al tocar). El último es el recurso actual.
  final List<(String, VoidCallback?)> breadcrumbs;
  final String title;
  final String? subtitle;
  final IconData icon;
  final LabIamRole role;
  final List<String> tags;
  final List<LabTabSpec> tabs;
  final String? tab;
  final ValueChanged<String> onTab;

  /// La página ocupa todo el alto (no va dentro de un scroll): para experimentos con pantalla propia.
  final bool fill;
  const LabResourcePage({
    super.key,
    required this.breadcrumbs,
    required this.title,
    required this.icon,
    required this.role,
    required this.tabs,
    required this.tab,
    required this.onTab,
    this.subtitle,
    this.tags = const [],
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = labTabOf(tab, tabs);
    final alive = [for (final t in tabs) if (t.id == current || t.keepAlive) t];
    // Cada pestaña viva va siempre en el mismo Offstage con clave: si cambiara de lugar en el árbol
    // al ocultarse, perdería su estado (y una corrida en curso).
    Widget slot(LabTabSpec t, Widget child) => Offstage(
          key: ValueKey('tab-${t.id}'),
          offstage: t.id != current,
          child: TickerMode(enabled: t.id == current, child: child),
        );
    if (!fill) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ..._header(current),
        for (final t in alive) slot(t, t.build()),
      ]);
    }
    final isMobile = MediaQuery.of(context).size.width < 900;
    final pad = EdgeInsets.fromLTRB(isMobile ? 16 : 28, 20, isMobile ? 16 : 28, 0);
    Widget limit(Widget w) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: w));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: pad, child: limit(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _header(current)))),
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          for (final t in alive) slot(t, t.scroll ? SingleChildScrollView(padding: pad.copyWith(bottom: 40), child: limit(t.build())) : t.build()),
        ]),
      ),
    ]);
  }

  List<Widget> _header(String current) {
    return [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var i = 0; i < breadcrumbs.length; i++) ...[
          if (i > 0) Icon(Icons.chevron_right_rounded, size: 18, color: OhtliColors.subtleText),
          breadcrumbs[i].$2 == null
              ? Text(breadcrumbs[i].$1, style: GoogleFonts.inter(fontSize: 12.5, color: OhtliColors.subtleText))
              : InkWell(
                  onTap: breadcrumbs[i].$2,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Text(breadcrumbs[i].$1,
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: OhtliColors.stormyTeal)),
                  ),
                ),
        ],
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: OhtliColors.stormyTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: OhtliColors.stormyTeal, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.4)),
              ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _Chip(text: 'Tu rol: ${role.label}', color: OhtliColors.stormyTeal),
              for (final t in tags) _Chip(text: t, color: OhtliColors.subtleText),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TabButton(spec: t, selected: t.id == current, onTap: () => onTab(t.id)),
            ),
        ]),
      ),
      Divider(height: 1, color: OhtliColors.cardBorder),
      const SizedBox(height: 16),
    ];
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );
}

class _TabButton extends StatelessWidget {
  final LabTabSpec spec;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.spec, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? OhtliColors.stormyTeal : Colors.transparent, width: 2.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(spec.icon, size: 17, color: selected ? OhtliColors.stormyTeal : OhtliColors.subtleText),
            const SizedBox(width: 6),
            Text(spec.label,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? OhtliColors.stormyTeal : OhtliColors.onyx,
                )),
          ]),
        ),
      );
}

/// Configuración en sub-secciones: lista a la izquierda en escritorio, menú desplegable en móvil.
class LabSettingsLayout extends StatelessWidget {
  final List<(String, String, Widget Function())> sections;
  final String? current;
  final ValueChanged<String> onSection;
  const LabSettingsLayout({super.key, required this.sections, required this.current, required this.onSection});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final cur = sections.any((s) => s.$1 == current) ? current! : sections.first.$1;
    final body = KeyedSubtree(key: ValueKey('section-$cur'), child: sections.firstWhere((s) => s.$1 == cur).$3());
    final nav = isMobile
        ? DropdownButtonFormField<String>(
            initialValue: cur,
            decoration: const InputDecoration(labelText: 'Sección', border: OutlineInputBorder(), isDense: true),
            items: [for (final s in sections) DropdownMenuItem(value: s.$1, child: Text(s.$2))],
            onChanged: (v) => v == null ? null : onSection(v),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final s in sections)
              ListTile(
                dense: true,
                selected: s.$1 == cur,
                selectedTileColor: OhtliColors.stormyTeal.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: Text(s.$2, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: s.$1 == cur ? FontWeight.w700 : FontWeight.w500)),
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
