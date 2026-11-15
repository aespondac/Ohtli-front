import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/lab/experiments/agents_experiment_page.dart';
import '../screens/lab/experiments/apis_experiment_page.dart';
import '../screens/lab/experiments/osrm_experiment_page.dart';
import '../screens/lab/experiments/recolector_experiment_page.dart';
import '../screens/lab/experiments/taste_vector_experiment_page.dart';
import '../theme/colors.dart';
import '../widgets/ohtli_account_chip.dart';
import '../widgets/ohtli_theme_toggle.dart';
import 'lab_access.dart';
import 'lab_console_page.dart';
import 'lab_eval_page.dart';
import 'lab_experiments.dart';
import 'lab_publishing.dart';
import 'lab_studies.dart';
import 'lab_widgets.dart';
import 'labs_top_bar.dart';

/// Ohtli Labs con sesión: una sola interfaz con menú lateral (como la app de Ohtli) y vistas
/// según el rol. Antes eran tres pantallas con accesos distintos (espacio de testers, consola y
/// "experimentos técnicos" con su propia lista de espera).
///
///  - Todos (tras aceptar el consentimiento una vez): Participa, Resultados y Experimentos.
///  - Miembros del laboratorio: además las pruebas del TT y la publicación.
///
/// Secciones: `participa`, `resultados`, `exp:<id>`, `study:<id>`, `posts`, `members`.
class LabsAppPage extends StatefulWidget {
  final String? initialSection;
  final VoidCallback onSignOut;
  final VoidCallback onOpenTerms;
  const LabsAppPage({super.key, this.initialSection, required this.onSignOut, required this.onOpenTerms});

  /// La sección pedida tiene sentido para el rol; si no, la de inicio del rol.
  static String validSection(String? section, LabRole role) {
    final fallback = role.isMember ? 'study:${kLabStudies.first.id}' : 'participa';
    final s = section ?? '';
    if (s == 'participa' || s == 'resultados') return s;
    if (s.startsWith('exp:')) return experimentById(s.substring(4)) != null ? s : fallback;
    if (s.startsWith('study:')) return role.isMember && studyById(s.substring(6)) != null ? s : fallback;
    if (s == 'posts') return role.isMember ? s : fallback;
    if (s == 'members') return role == LabRole.admin ? s : fallback;
    return fallback;
  }

  @override
  State<LabsAppPage> createState() => _LabsAppPageState();
}

class _NavEntry {
  final String key;
  final IconData icon;
  final String label;
  final String? badge;
  final Color? badgeColor;
  const _NavEntry(this.key, this.icon, this.label, {this.badge, this.badgeColor});
}

class _LabsAppPageState extends State<LabsAppPage> {
  LabRole _role = LabRole.none;
  bool _loaded = false;
  String? _roleError;
  late String _section;
  // Secciones ya abiertas: se mantienen vivas (IndexedStack) para que cambiar de sección no
  // corte una corrida en curso ni pierda lo que se estaba llenando.
  final List<String> _visited = [];

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? '';
    _load();
  }

  Future<void> _load() async {
    LabRole r;
    try {
      r = await LabAccess.roleOf(FirebaseAuth.instance.currentUser);
    } catch (e) {
      if (mounted) setState(() => _roleError = '$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _role = r;
      _roleError = null;
      _loaded = true;
      _section = LabsAppPage.validSection(_section, r);
    });
  }

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _go(String section) {
    setState(() => _section = LabsAppPage.validSection(section, _role));
    // En móvil el menú es un panel que se cierra al elegir.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) _scaffoldKey.currentState!.closeDrawer();
  }

  List<(String, List<_NavEntry>)> _groups() => [
        ('PARTICIPA', const [
          _NavEntry('participa', Icons.how_to_reg_rounded, 'Estudios abiertos'),
          _NavEntry('resultados', Icons.article_outlined, 'Resultados liberados'),
        ]),
        ('EXPERIMENTOS', [
          for (final e in kLabExperiments) _NavEntry('exp:${e.id}', e.icon, e.title, badge: e.status, badgeColor: e.statusColor),
        ]),
        if (_role.isMember)
          ('PRUEBAS DEL TT', [
            for (final s in kLabStudies) _NavEntry('study:${s.id}', labStudyIcon(s.kind), s.title),
          ]),
        if (_role.isMember)
          ('PUBLICACIÓN', [
            const _NavEntry('posts', Icons.edit_note_rounded, 'Artículos y resultados'),
            if (_role == LabRole.admin) const _NavEntry('members', Icons.manage_accounts_outlined, 'Miembros del laboratorio'),
          ]),
      ];

  String _titleOf(String section) {
    for (final g in _groups()) {
      for (final e in g.$2) {
        if (e.key == section) return e.label;
      }
    }
    return 'Ohtli Labs';
  }

  @override
  Widget build(BuildContext context) {
    currentLabRole = _role;
    final isMobile = MediaQuery.of(context).size.width < 900;
    if (_roleError != null) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: _topBar(isMobile: isMobile, title: 'Ohtli Labs', withMenu: false),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: LabCard(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('No pudimos verificar tu acceso a Labs',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
                  const SizedBox(height: 8),
                  Text('Revisa tu conexión e inténtalo de nuevo.', style: labCell()),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _roleError = null);
                      _load();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    if (!_loaded) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        body: const Center(child: CircularProgressIndicator(color: OhtliColors.stormyTeal)),
      );
    }

    // Sin rol todavía: un solo consentimiento para todo Labs.
    if (_role == LabRole.none) {
      return Scaffold(
        backgroundColor: OhtliColors.cloudDancer,
        appBar: _topBar(isMobile: isMobile, title: 'Ohtli Labs', withMenu: false),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: LabConsentCard(
                onOpenTerms: widget.onOpenTerms,
                onAccepted: () => setState(() {
                  _role = LabRole.tester;
                  _section = 'participa';
                }),
              ),
            ),
          ),
        ),
      );
    }

    if (!_visited.contains(_section)) _visited.add(_section);
    final content = IndexedStack(
      index: _visited.indexOf(_section),
      sizing: StackFit.expand,
      children: [for (final s in _visited) KeyedSubtree(key: ValueKey(s), child: _content(s, isMobile))],
    );

    final nav = _Sidebar(groups: _groups(), selected: _section, onSelect: _go);
    if (isMobile) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: OhtliColors.cloudDancer,
        appBar: _topBar(isMobile: true, title: _titleOf(_section), withMenu: true),
        drawer: Drawer(width: 300, backgroundColor: OhtliColors.cardBg, child: SafeArea(child: nav)),
        body: content,
      );
    }
    return Scaffold(
      backgroundColor: OhtliColors.cloudDancer,
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 272, child: nav),
        Expanded(
          child: Column(children: [
            _topBar(isMobile: false, title: _titleOf(_section), withMenu: false),
            Expanded(child: content),
          ]),
        ),
      ]),
    );
  }

  PreferredSizeWidget _topBar({required bool isMobile, required String title, required bool withMenu}) {
    return AppBar(
      backgroundColor: OhtliColors.cardBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: withMenu
          ? Builder(
              builder: (context) => IconButton(
                tooltip: 'Menú de Labs',
                icon: Icon(Icons.menu_rounded, color: OhtliColors.onyx),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          : null,
      titleSpacing: withMenu ? 0 : 24,
      title: Text(title,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(fontSize: isMobile ? 17 : 19, fontWeight: FontWeight.w800, color: OhtliColors.onyx)),
      shape: Border(bottom: BorderSide(color: OhtliColors.cardBorder)),
      actions: [
        const OhtliThemeToggle(),
        const SizedBox(width: 8),
        OhtliAccountChip(compact: isMobile, onSignOut: () async => widget.onSignOut()),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _scroll(Widget child, {double maxWidth = 1100}) => Builder(builder: (context) {
        final isMobile = MediaQuery.of(context).size.width < 900;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(isMobile ? 16 : 28, 20, isMobile ? 16 : 28, 40),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
          ),
        );
      });

  Widget _content(String section, bool isMobile) {
    if (section == 'participa') {
      return _scroll(
        LabParticipateView(role: _role, onLeft: () => setState(() => _role = LabRole.none)),
        maxWidth: 820,
      );
    }
    if (section == 'resultados') return _scroll(const LabReleasedView(), maxWidth: 820);
    if (section == 'posts') return _scroll(LabPostsPanel(role: _role));
    if (section == 'members') return _scroll(const LabMembersPanel());
    if (section.startsWith('study:')) return _scroll(LabStudyPanel(study: studyById(section.substring(6))!));
    final e = experimentById(section.substring(4))!;
    return LabEmbedded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ExperimentHeader(experiment: e, isMobile: isMobile),
        Expanded(child: _experimentPage(e.id)),
      ]),
    );
  }

  Widget _experimentPage(String id) {
    void back() => _go('participa');
    return switch (id) {
      'recolector' => RecolectorExperimentPage(onBack: back),
      'taste' => TasteVectorExperimentPage(onBack: back),
      'osrm' => OsrmExperimentPage(onBack: back),
      'agents' => AgentsExperimentPage(onBack: back),
      _ => ApisExperimentPage(onBack: back),
    };
  }
}

/// Encabezado común de cada experimento (mismo nombre y estado que en la portada pública).
class _ExperimentHeader extends StatelessWidget {
  final LabExperiment experiment;
  final bool isMobile;
  const _ExperimentHeader({required this.experiment, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final e = experiment;
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 28, 20, isMobile ? 16 : 28, 8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: e.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(e.icon, color: e.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(e.category, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: OhtliColors.subtleText)),
                  _Badge(text: e.status, color: e.statusColor),
                ]),
                const SizedBox(height: 4),
                Text(e.description, style: GoogleFonts.inter(fontSize: 13, color: OhtliColors.subtleText, height: 1.45)),
                const SizedBox(height: 2),
                Text('Experimental: puede fallar o cambiar sin aviso.',
                    style: GoogleFonts.inter(fontSize: 11.5, fontStyle: FontStyle.italic, color: OhtliColors.subtleText)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: color)),
      );
}

/// Menú lateral de Labs: grupos con encabezado y elementos con icono, como el menú de Ohtli.
class _Sidebar extends StatelessWidget {
  final List<(String, List<_NavEntry>)> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  const _Sidebar({required this.groups, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OhtliColors.cardBg,
        border: Border(right: BorderSide(color: OhtliColors.cardBorder)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Marca: lleva a la portada pública de Labs.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
          child: InkWell(
            onTap: () => LabsTopBar.go(LabsSection.home),
            borderRadius: BorderRadius.circular(10),
            child: Row(children: [
              SvgPicture.asset('assets/logo.svg', height: 22, colorFilter: ColorFilter.mode(OhtliColors.onyx, BlendMode.srcIn)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: OhtliColors.stormyTeal, borderRadius: BorderRadius.circular(8)),
                child: Text('LABS', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.white)),
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            children: [
              for (final g in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Text(g.$1,
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: OhtliColors.subtleText)),
                ),
                for (final e in g.$2) _item(e),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: OhtliColors.cardBorder),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: () => LabsTopBar.go(LabsSection.news),
              icon: const Icon(Icons.public_rounded, size: 16),
              label: const Text('Noticias de Labs'),
            ),
            TextButton.icon(
              onPressed: () => LabsTopBar.go(LabsSection.home),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('labs.ohtli.quest'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _item(_NavEntry e) {
    final active = e.key == selected;
    final color = active ? OhtliColors.stormyTeal : OhtliColors.onyx.withValues(alpha: 0.75);
    return Semantics(
      button: true,
      selected: active,
      label: e.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: active ? OhtliColors.stormyTeal.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => onSelect(e.key),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(e.icon, size: 19, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, height: 1.3, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: color)),
                ),
                // Estado del experimento como punto (el nombre completo cabe); el texto en el tooltip
                // y en el encabezado del experimento.
                if (e.badge != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: e.badge!,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: e.badgeColor ?? OhtliColors.subtleText, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
